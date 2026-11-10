// ACP（Agent Client Protocol）的 UHP HarnessDriver 适配器。
//
// 翻译关系（一对一，不做语义加工）：
//   UHP TurnContext.input            -> ACP session/prompt（内容块 = 一行文本）
//   ACP agent_message_chunk          -> TurnSink.textDelta
//   ACP agent_thought_chunk          -> TurnSink.reasoningDelta
//   ACP tool_call / tool_call_update -> TurnSink.toolCall / toolResult
//   ACP stopReason                   -> UHP TurnOutcome
//   UHP CancelToken                  -> ACP session/cancel（旁路线程）
//   ACP session/request_permission   -> UHP 的两轮问答（见下）
//
// 权限请求为什么不能「直接答」：ACP 的 request_permission 是**同步回调**——Agent 在
// session/prompt 里阻塞等 Client 立刻回应；而 UHP 的提问是「本轮结束为 incomplete，
// 下一轮用 input_response 续跑」。所以本适配器把 prompt 放到后台线程跑：
//   回调到达 -> 记下挂起请求 -> 让当前 run 以 Incomplete(input_required) 返回；
//   下一轮 run 收到答案 -> 写入挂起槽 -> 回调立即返回 selected(optionId) -> Agent 继续；
//   该轮 run 等后台 prompt 结束，返回最终 stopReason。
package uhp_acp

import std.collection.{ArrayList, HashMap}
import std.fs.{File as FsFile}
import std.convert.*
import std.sync.{AtomicBool, Mutex}
import std.time.DateTime
import std.io.ByteBuffer
import jsonvalue.*
import stdx.encoding.json.stream.*
import acp.*
import acp.types.*
import acp.transport.*
import ystyle::jsonrpc.{Result, Transport}
import uhp.server.*
import uhp.types.generated.*

// 调试埋点（仅诊断用，定位 CI 上的卡点）：把进度追加到 /tmp/acp-dbg.log。
// 测试框架会吞掉测试用例里的 stderr，所以走文件；诊断完删掉。
public func dbg(msg: String): Unit {
    try {
        FsFile.appendTo("/tmp/acp-dbg.log", ("[" + nowMillis().toString() + "] " + msg + "\n").toArray())
    } catch (e: Exception) {
        ()
    }
}

// 诊断用：包一层传输，记录 send/receive 的进度（PR 关闭前删除）
class DbgTransport <: Transport {
    private let inner: Transport
    public init(inner: Transport) {
        this.inner = inner
    }
    public func send(data: Array<Byte>): Unit {
        dbg("[dbg] transport send " + data.size.toString())
        this.inner.send(data)
        dbg("[dbg] transport send ok")
    }
    public func receive(): ?Array<Byte> {
        let r = this.inner.receive()
        match (r) {
            case Some(d) => dbg("[dbg] transport recv " + d.size.toString())
            case None => dbg("[dbg] transport recv none")
        }
        r
    }
    public func isClosed(): Bool {
        this.inner.isClosed()
    }
    public func close(): Unit {
        dbg("[dbg] transport close")
        this.inner.close()
        dbg("[dbg] transport closed")
    }
}

public class AcpOptions {
    public let command: String
    public let args: Array<String>
    public let cwd: String
    public let label: String
    public let clientName: String
    public let timeoutSeconds: Int64
    public let permissionTimeoutSeconds: Int64

    public init(command: String, args!: Array<String> = [], cwd!: String = "/tmp",
                label!: String = "ACP agent", clientName!: String = "uhp-cj",
                timeoutSeconds!: Int64 = 600, permissionTimeoutSeconds!: Int64 = 600) {
        this.command = command
        this.args = args
        this.cwd = cwd
        this.label = label
        this.clientName = clientName
        this.timeoutSeconds = timeoutSeconds
        this.permissionTimeoutSeconds = permissionTimeoutSeconds
    }
}

// 一个 UHP 会话对应的一轮执行状态（prompt 在后台线程跑，主线程按事件轮询）
class TurnState {
    public let acpSession: String
    public var sink: Option<TurnSink> = None
    public var inFlight: Bool = false
    public var promptDone: Bool = false
    public var stopReason: String = ""
    public var promptError: Option<String> = None
    public var permPending: Bool = false
    public var permToolCallId: String = ""
    public var permTitle: String = "Allow this tool call?"
    public var permOptions: Array<(String, String)> = []
    public var permAnswer: Option<String> = None
    public var permAsked: Bool = false
    // 挂起的 elicitation（表单）请求
    public var elicitPending: Bool = false
    public var elicitTitle: String = ""
    public var elicitKind: String = "free_text"
    public var elicitOptions: Array<(String, String)> = []
    public var elicitFieldKey: String = ""
    public var elicitValueKind: String = "string"
    public var elicitMulti: Bool = false
    public var elicitAnswer: Option<String> = None
    public var elicitAsked: Bool = false

    public init(acpSession: String) {
        this.acpSession = acpSession
    }
}

public class AcpDriver <: HarnessDriver {
    private let opts: AcpOptions
    private let lock = Mutex()
    private var client: Option<AcpClient> = None
    private var currentSink: Option<TurnSink> = None
    private var currentSession: String = ""
    private let callIds = HashMap<String, String>()
    private let sessions: HashMap<String, String> = HashMap<String, String>()
    private let turns: HashMap<String, TurnState> = HashMap<String, TurnState>()

    public init(opts: AcpOptions) {
        this.opts = opts
    }

    // 释放 Agent 子进程与接收线程。适配器持有的是外部进程，driver 退出时必须显式收尾，
    // 否则子进程与阻塞中的接收线程会一直挂在那里（长跑服务换 driver、测试用例收尾都受影响）。
    public func close(): Unit {
        // 先摘掉引用再关：关闭链路会等子进程退出，不能把锁一起抱着（回调线程还要取它）
        let c: Option<AcpClient> = synchronized(this.lock) {
            let cur = this.client
            this.client = None
            cur
        }
        match (c) {
            case Some(cc) => cc.close()
            case None => ()
        }
    }

    public func base(): String {
        return "acp"
    }

    public func baseLabel(): String {
        return this.opts.label
    }

    public func models(): Array<Model> {
        let m = Model()
        m.id = "acp-agent"
        m.label = this.opts.label
        m.available = true
        m.default = Some(true)
        return [m]
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, true)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        try {
            return this.runInner(ctx, sink, cancel)
        } catch (e: Exception) {
            eprintln("acp: driver exception: " + e.toString())
            return TurnOutcome.Failed("harness_error", "ACP adapter error")
        }
    }

    private func runInner(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        dbg("[dbg] runInner enter sid=" + ctx.sessionId + " answers=" + ctx.answers.size.toString())
        let client = match (this.ensureClient()) {
            case Some(c) => c
            case None => return TurnOutcome.Failed("harness_error", "ACP agent not available")
        }
        dbg("[dbg] client ok")
        let acpSession = match (this.ensureSession(client, ctx.sessionId)) {
            case Some(s) => s
            case None => return TurnOutcome.Failed("harness_error", "ACP session/new failed")
        }
        dbg("[dbg] session ok acp=" + acpSession)
        let state = this.turnState(ctx.sessionId, acpSession)
        if (ctx.answers.size > 0) {
            let st = state
            synchronized(this.lock) {
                if (st.permPending) {
                    st.permAnswer = Some(ctx.answers[0])
                } else if (st.elicitPending) {
                    st.elicitAnswer = Some(ctx.answers[0])
                }
            }
        }
        let resumeOnly = synchronized(this.lock) {
            state.inFlight
        }
        dbg("[dbg] resumeOnly=" + resumeOnly.toString() + " permPending=" + state.permPending.toString() + " permAsked=" + state.permAsked.toString() + " promptDone=" + state.promptDone.toString())
        synchronized(this.lock) {
            state.sink = Some(sink)
            this.currentSink = Some(sink)
            this.currentSession = acpSession
        }
        if (!resumeOnly) {
            synchronized(this.lock) {
                state.inFlight = true
                state.promptDone = false
                state.stopReason = ""
                state.promptError = None
            }
            let st = state
            let blocks = buildPromptBlocks(ctx)
            let c = client
            spawn {
                let res = c.prompt(acpSession, blocks,
                    timeout: Duration.second * this.opts.timeoutSeconds)
                let st2 = st
                synchronized(this.lock) {
                    match (res) {
                        case Result.Ok(resp) =>
                            st2.stopReason = resp.stopReason
                        case Result.Err(msg) =>
                            st2.promptError = Some(msg)
                    }
                    st2.promptDone = true
                    st2.inFlight = false
                }
            }
        }
        let deadline = nowMillis() + this.opts.timeoutSeconds * 1000
        var dbgTick = 0
        while (nowMillis() < deadline) {
            dbgTick = dbgTick + 1
            let (done, reason, err) = synchronized(this.lock) {
                (state.promptDone, state.stopReason, state.promptError)
            }
            if (done) {
                dbg("[dbg] done reason=" + reason + " err=" + err.isSome().toString())
                synchronized(this.lock) {
                    state.sink = None
                    this.currentSink = None
                    this.currentSession = ""
                }
                match (err) {
                    case Some(msg) => return TurnOutcome.Failed("harness_error", "ACP prompt failed: " + msg)
                    case None => return outcomeOf(reason)
                }
            }
            let askable = synchronized(this.lock) {
                state.permPending && !state.permAsked && state.permAnswer.isNone()
            }
            if (askable) {
                let title = synchronized(this.lock) {
                    state.permTitle
                }
                let options = synchronized(this.lock) {
                    state.permOptions
                }
                let _ = sink.ask("choice", title, options)
                dbg("[dbg] ask permission -> incomplete")
                synchronized(this.lock) {
                    state.permAsked = true
                    state.sink = None
                    this.currentSink = None
                }
                return TurnOutcome.Incomplete(IncompleteReason.InputRequired, None)
            }
            let askElicit = synchronized(this.lock) {
                state.elicitPending && !state.elicitAsked && state.elicitAnswer.isNone()
            }
            if (askElicit) {
                let kind = synchronized(this.lock) {
                    state.elicitKind
                }
                let title = synchronized(this.lock) {
                    state.elicitTitle
                }
                let options = synchronized(this.lock) {
                    state.elicitOptions
                }
                let _ = sink.ask(kind, title, options)
                synchronized(this.lock) {
                    state.elicitAsked = true
                    state.sink = None
                    this.currentSink = None
                }
                return TurnOutcome.Incomplete(IncompleteReason.InputRequired, None)
            }
            if (cancel.isCancelled()) {
                client.cancel(acpSession)
            }
            if (dbgTick % 100 == 0) {
                let spin = synchronized(this.lock) {
                    (state.permPending, state.permAnswer.isSome(), state.permAsked)
                }
                dbg("[dbg] poll tick=" + dbgTick.toString() + " permPending=" + spin[0].toString() + " answer=" + spin[1].toString() + " asked=" + spin[2].toString())
            }
            sleep(Duration.millisecond * 10)
        }
        return TurnOutcome.Failed("harness_error", "ACP timeout")
    }

    private func ensureClient(): Option<AcpClient> {
        synchronized(this.lock) {
            match (this.client) {
                case Some(c) => return Some(c)
                case None => ()
            }
            let transport = DbgTransport(SubprocessTransport(this.opts.command, args: this.opts.args))
            let c = AcpClient(transport)
            dbg("[dbg] client constructed")
            c.setOnSessionUpdate({ sid, update => this.onUpdate(sid, update) })
            c.setOnRequestPermission({ req => this.onPermission(req) })
            c.setOnElicitationCreate({ req => this.onElicitation(req) })
            c.setOnError({ e => eprintln("acp: rpc error: " + e.toString()) })
            let info = Implementation(this.opts.clientName, "0.1.0")
            // 只声明 form 能力：url 模式的引导式外链没有对应的 UHP 提问形态，不假装支持
            let caps = ClientCapabilities()
            let elicitCaps = ElicitationCapabilities()
            elicitCaps.form = Some(EmptyCapability())
            caps.elicitation = Some(elicitCaps)
            dbg("[dbg] connect start")
            spawn {
                dbg("[dbg] watchdog started")
                var w = 0
                while (w < 60) {
                    sleep(Duration.second)
                    w = w + 1
                    dbg("[dbg] watchdog t=" + w.toString() + "s connected=" + c.isConnected().toString())
                }
            }
            match (c.connect(info, caps)) {
                case Result.Ok(_) =>
                    dbg("[dbg] connect ok")
                    this.client = Some(c)
                    return Some(c)
                case Result.Err(msg) =>
                    eprintln("acp: connect failed: " + msg)
                    c.close()
                    return None
            }
        }
    }

    private func ensureSession(client: AcpClient, uhpSession: String): Option<String> {
        synchronized(this.lock) {
            match (this.sessions.get(uhpSession)) {
                case Some(s) => return Some(s)
                case None => ()
            }
        }
        match (client.newSession(this.opts.cwd)) {
            case Result.Ok(resp) =>
                synchronized(this.lock) {
                    this.sessions[uhpSession] = resp.sessionId
                }
                return Some(resp.sessionId)
            case Result.Err(msg) =>
                eprintln("acp: session/new failed: " + msg)
                return None
        }
    }

    private func turnState(uhpSession: String, acpSession: String): TurnState {
        synchronized(this.lock) {
            match (this.turns.get(uhpSession)) {
                case Some(s) => return s
                case None =>
                    let s = TurnState(acpSession)
                    this.turns[uhpSession] = s
                    return s
            }
        }
    }

    private func stateByAcpSession(acpSession: String): Option<TurnState> {
        synchronized(this.lock) {
            for ((_, st) in this.turns) {
                if (st.acpSession == acpSession) {
                    return Some(st)
                }
            }
            return None
        }
    }


    // elicitation/create（表单）：和 permission 一样是同步回调，靠挂起槽 + 下一轮答案接起来。
    // 单字段映射成 UHP 的 choice/confirm/free_text；多字段压成「回一个 JSON 对象」（提示里列出 key）。
    private func onElicitation(req: CreateElicitationRequest): CreateElicitationResponse {
        let sid = req.sessionId ?? ""
        let st = match (this.stateByAcpSession(sid)) {
            case Some(s) => s
            case None => return CreateElicitationResponse.declined()
        }
        if (req.mode != ElicitationModeForm) {
            return CreateElicitationResponse.declined()
        }
        let schema = match (req.requestedSchema) {
            case Some(sc) => sc
            case None => return CreateElicitationResponse.declined()
        }
        if (schema.properties.size == 0) {
            return CreateElicitationResponse.declined()
        }
        var title = req.message
        if (title.size == 0) {
            title = match (schema.title) {
                case Some(t) => t
                case None => "Please provide input"
            }
        }
        var singleKey = ""
        var valueKind = "string"
        var kind = "free_text"
        var options = Array<(String, String)>()
        let multi = schema.properties.size > 1
        if (!multi) {
            for ((k, pfield) in schema.properties) {
                singleKey = k
                let ptype = pfield.`type`
                title = match (pfield.title) {
                    case Some(t) => t
                    case None => title
                }
                if (ptype == PropTypeBoolean) {
                    kind = "confirm"
                    valueKind = "bool"
                    options = [("true", "Yes"), ("false", "No")]
                } else if (ptype == PropTypeNumber || ptype == PropTypeInteger) {
                    kind = "free_text"
                    valueKind = "number"
                } else if (ptype == PropTypeArray) {
                    kind = "free_text"
                    valueKind = "array"
                } else if (ptype == PropTypeString) {
                    let opts = ArrayList<(String, String)>()
                    match (pfield.titledOptions) {
                        case Some(list) =>
                            for (o in list) {
                                opts.add((o.`const`, o.title))
                            }
                        case None => ()
                    }
                    if (opts.size == 0) {
                        match (pfield.enumValues) {
                            case Some(vals) =>
                                for (v in vals) {
                                    opts.add((v, v))
                                }
                            case None => ()
                        }
                    }
                    if (opts.size > 0) {
                        kind = "choice"
                        options = opts.toArray()
                    } else {
                        kind = "free_text"
                        valueKind = "string"
                    }
                } else {
                    kind = "free_text"
                    valueKind = "string"
                }
            }
        } else {
            var keys = ""
            for ((k, _) in schema.properties) {
                keys = if (keys.size == 0) { k } else { keys + ", " + k }
            }
            title = title + " (reply a JSON object with keys: " + keys + ")"
            kind = "free_text"
        }
        synchronized(this.lock) {
            st.elicitPending = true
            st.elicitTitle = title
            st.elicitKind = kind
            st.elicitOptions = options
            st.elicitFieldKey = singleKey
            st.elicitValueKind = valueKind
            st.elicitMulti = multi
            st.elicitAnswer = None
            st.elicitAsked = false
        }
        let deadline = nowMillis() + this.opts.permissionTimeoutSeconds * 1000
        while (nowMillis() < deadline) {
            let ans = synchronized(this.lock) {
                st.elicitAnswer
            }
            match (ans) {
                case Some(a) =>
                    synchronized(this.lock) {
                        st.elicitPending = false
                        st.elicitAnswer = None
                        st.elicitAsked = false
                    }
                    let contentJson = buildElicitationContent(singleKey, valueKind, multi, a)
                    match (contentJson) {
                        case Some(cj) =>
                            let value = try {
                                JsonValue.fromJson(JsonReader(ByteBuffer(cj.toArray())))
                            } catch (e: Exception) {
                                JsonValue.Null
                            }
                            return CreateElicitationResponse.accepted(content: Some(value))
                        case None => return CreateElicitationResponse.cancelled()
                    }
                case None => ()
            }
            sleep(Duration.millisecond * 10)
        }
        synchronized(this.lock) {
            st.elicitPending = false
            st.elicitAsked = false
        }
        return CreateElicitationResponse.declined()
    }

    private func onPermission(req: RequestPermissionRequest): RequestPermissionResponse {
        dbg("[dbg] onPermission enter sid=" + req.sessionId)
        let st = match (this.stateByAcpSession(req.sessionId)) {
            case Some(s) => s
            case None => return RequestPermissionResponse(RequestPermissionOutcome.cancelled())
        }
        let options = ArrayList<(String, String)>()
        for (o in req.options) {
            options.add((o.optionId, o.name))
        }
        if (options.size == 0) {
            return RequestPermissionResponse(RequestPermissionOutcome.cancelled())
        }
        let title = match (req.toolCall.title) {
            case Some(t) => "Allow: " + t + "?"
            case None => "Allow this tool call?"
        }
        synchronized(this.lock) {
            st.permPending = true
            st.permToolCallId = req.toolCall.toolCallId
            st.permTitle = title
            st.permOptions = options.toArray()
            st.permAnswer = None
            st.permAsked = false
        }
        let deadline = nowMillis() + this.opts.permissionTimeoutSeconds * 1000
        while (nowMillis() < deadline) {
            let ans = synchronized(this.lock) {
                st.permAnswer
            }
            match (ans) {
                case Some(a) =>
                    dbg("[dbg] onPermission got answer=" + a)
                    synchronized(this.lock) {
                        st.permPending = false
                        st.permAnswer = None
                        st.permAsked = false
                    }
                    return RequestPermissionResponse(RequestPermissionOutcome.selected(a))
                case None => ()
            }
            sleep(Duration.millisecond * 10)
        }
        dbg("[dbg] onPermission timeout")
        synchronized(this.lock) {
            st.permPending = false
            st.permAsked = false
        }
        return RequestPermissionResponse(RequestPermissionOutcome.cancelled())
    }

    private func onUpdate(sid: String, update: SessionUpdate) {
        let target: Option<TurnSink> = synchronized(this.lock) {
            if (sid != this.currentSession) {
                None
            } else {
                this.currentSink
            }
        }
        let sink = match (target) {
            case Some(s) => s
            case None => return
        }
        let kind = update.sessionUpdate
        if (kind == SessionUpdateAgentMessageChunk) {
            match (update.content) {
                case Some(c) => match (c.text) {
                    case Some(t) => sink.textDelta(t)
                    case None => ()
                }
                case None => ()
            }
        } else if (kind == SessionUpdateAgentThoughtChunk) {
            match (update.content) {
                case Some(c) => match (c.text) {
                    case Some(t) => sink.reasoningDelta(t)
                    case None => ()
                }
                case None => ()
            }
        } else if (kind == SessionUpdateToolCall) {
            let acpId = update.toolCallId ?? ""
            let title = update.title ?? "tool"
            let args = match (update.rawInput) {
                case Some(v) => v.stringify()
                case None => "{}"
            }
            let uhpCall = sink.toolCall(title, args)
            if (acpId.size > 0) {
                synchronized(this.lock) {
                    this.callIds[acpId] = uhpCall
                }
            }
        } else if (kind == SessionUpdateToolCallUpdate) {
            let acpId = update.toolCallId ?? ""
            let uhpCall = synchronized(this.lock) {
                this.callIds.get(acpId) ?? acpId
            }
            var text = ""
            match (update.toolContent) {
                case Some(items) =>
                    for (item in items) {
                        match (item.content) {
                            case Some(c) => match (c.text) {
                                case Some(t) =>
                                    text = if (text.size == 0) { t } else { text + t }
                                case None => ()
                            }
                            case None => ()
                        }
                    }
                case None => ()
            }
            match (update.rawOutput) {
                case Some(v) => text = text + v.stringify()
                case None => ()
            }
            if (text.size > 0) {
                sink.toolResult(uhpCall, text)
            }
            // 文件产物：ACP 的 diff 内容块带 path + newText，直接作为产物交给 UHP
            match (update.toolContent) {
                case Some(items) =>
                    for (item in items) {
                        if (item.`type` == "diff") {
                            match (item.path) {
                                case Some(path) =>
                                    match (item.newText) {
                                        case Some(content) =>
                                            sink.producedFile(path, content.toArray())
                                        case None => ()
                                    }
                                case None => ()
                            }
                        }
                    }
                case None => ()
            }
        }
    }
}

func outcomeOf(stopReason: String): TurnOutcome {
    if (stopReason == StopReasonEndTurn) {
        return TurnOutcome.Completed(None)
    }
    if (stopReason == StopReasonCancelled) {
        return TurnOutcome.Cancelled(None)
    }
    if (stopReason == StopReasonMaxTurnRequests) {
        return TurnOutcome.Incomplete(IncompleteReason.MaxSteps, None)
    }
    if (stopReason == StopReasonMaxTokens) {
        return TurnOutcome.Incomplete(IncompleteReason.Other("max_tokens"), None)
    }
    if (stopReason == StopReasonRefusal) {
        return TurnOutcome.Failed("harness_error", "agent refusal")
    }
    return TurnOutcome.Incomplete(IncompleteReason.Other(stopReason), None)
}

public func nowMillis(): Int64 {
    return DateTime.now().toUnixTimeStamp().toMilliseconds()
}


// 把 UHP 的输入文件映射成 ACP 内容块：
//   image/*    -> image 块（base64 + mimeType）
//   text/*     -> text 块（文件名 + 内容拼成一段文本）
//   其它二进制 -> resource_link（data URI + 文件名）
func buildPromptBlocks(ctx: TurnContext): ArrayList<ContentBlock> {
    let blocks = ArrayList<ContentBlock>()
    blocks.add(ContentBlock.ofText(ctx.input))
    for (f in ctx.files) {
        if (f.mediaType.startsWith("image/")) {
            blocks.add(ContentBlock.image(base64Encode(f.bytes), f.mediaType))
        } else if (f.mediaType.startsWith("text/")) {
            blocks.add(ContentBlock.ofText("File " + f.filename + "|" + String.fromUtf8(f.bytes)))
        } else {
            blocks.add(ContentBlock.resourceLink(
                "data:" + f.mediaType + ";base64," + base64Encode(f.bytes), f.filename))
        }
    }
    return blocks
}

func base64Encode(bytes: Array<UInt8>): String {
    let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    let chars = ArrayList<UInt8>()
    var i = 0
    while (i + 2 < bytes.size) {
        let n = (Int64(bytes[i]) << 16) | (Int64(bytes[i + 1]) << 8) | Int64(bytes[i + 2])
        chars.add(UInt8((n >> 18) & 63))
        chars.add(UInt8((n >> 12) & 63))
        chars.add(UInt8((n >> 6) & 63))
        chars.add(UInt8(n & 63))
        i = i + 3
    }
    let rem = bytes.size - i
    if (rem == 1) {
        let n = Int64(bytes[i]) << 16
        chars.add(UInt8((n >> 18) & 63))
        chars.add(UInt8((n >> 12) & 63))
        chars.add(UInt8(64))
        chars.add(UInt8(64))
    } else if (rem == 2) {
        let n = (Int64(bytes[i]) << 16) | (Int64(bytes[i + 1]) << 8)
        chars.add(UInt8((n >> 18) & 63))
        chars.add(UInt8((n >> 12) & 63))
        chars.add(UInt8((n >> 6) & 63))
        chars.add(UInt8(64))
    }
    let out = ArrayList<UInt8>()
    for (c in chars) {
        let idx = Int64(c)
        if (idx == 64) {
            out.add(UInt8(61))
        } else {
            out.add(table[idx])
        }
    }
    return String.fromUtf8(out.toArray())
}

// 把 UHP 的一行答案编码成 elicitation content 对象（匹配 requestedSchema）
func buildElicitationContent(key: String, valueKind: String, multi: Bool, answer: String): Option<String> {
    if (multi) {
        let t = answer.trimAscii()
        if (t.size >= 2 && t.startsWith("{") && t.endsWith("}")) {
            return Some(answer)
        }
        return None
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName(key)
    if (valueKind == "bool") {
        if (answer == "true" || answer == "false") {
            w.jsonValue(answer)
        } else {
            w.writeValue(answer)
        }
    } else if (valueKind == "number") {
        match (Float64.tryParse(answer)) {
            case Some(_) => w.jsonValue(answer)
            case None => w.writeValue(answer)
        }
    } else if (valueKind == "array") {
        w.startArray()
        for (part in answer.split(",")) {
            let v = part.trimAscii()
            if (v.size > 0) {
                w.writeValue(v)
            }
        }
        w.endArray()
    } else {
        w.writeValue(answer)
    }
    w.endObject()
    w.flush()
    return Some(String.fromUtf8(out.bytes()))
}
