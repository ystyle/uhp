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
import std.convert.*
import std.sync.{AtomicBool, Mutex}
import std.time.DateTime
import acp.*
import acp.types.*
import acp.transport.*
import ystyle::jsonrpc.Result
import uhp.server.*
import uhp.types.generated.*

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
        let client = match (this.ensureClient()) {
            case Some(c) => c
            case None => return TurnOutcome.Failed("harness_error", "ACP agent not available")
        }
        let acpSession = match (this.ensureSession(client, ctx.sessionId)) {
            case Some(s) => s
            case None => return TurnOutcome.Failed("harness_error", "ACP session/new failed")
        }
        let state = this.turnState(ctx.sessionId, acpSession)
        if (ctx.answers.size > 0) {
            let st = state
            synchronized(this.lock) {
                if (st.permPending) {
                    st.permAnswer = Some(ctx.answers[0])
                }
            }
        }
        let resumeOnly = synchronized(this.lock) {
            state.inFlight
        }
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
            let input = ctx.input
            let c = client
            spawn {
                let res = c.promptText(acpSession, input,
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
        while (nowMillis() < deadline) {
            let (done, reason, err) = synchronized(this.lock) {
                (state.promptDone, state.stopReason, state.promptError)
            }
            if (done) {
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
                synchronized(this.lock) {
                    state.permAsked = true
                    state.sink = None
                    this.currentSink = None
                }
                return TurnOutcome.Incomplete(IncompleteReason.InputRequired, None)
            }
            if (cancel.isCancelled()) {
                client.cancel(acpSession)
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
            let transport = SubprocessTransport(this.opts.command, args: this.opts.args)
            let c = AcpClient(transport)
            c.setOnSessionUpdate({ sid, update => this.onUpdate(sid, update) })
            c.setOnRequestPermission({ req => this.onPermission(req) })
            c.setOnError({ e => eprintln("acp: rpc error: " + e.toString()) })
            let info = Implementation(this.opts.clientName, "0.1.0")
            match (c.connect(info, ClientCapabilities())) {
                case Result.Ok(_) =>
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

    private func onPermission(req: RequestPermissionRequest): RequestPermissionResponse {
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
