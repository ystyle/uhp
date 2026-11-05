// opencode 2.x 的 UHP HarnessDriver 适配器。
//
// 这是**消费方代码**：SDK（uhp-cj）负责协议面，本类只做两件事——
//   1. 把 UHP 的 TurnContext 翻成 opencode 的 session + prompt；
//   2. 把 opencode 的全局事件流翻成 UHP 的 TurnSink 调用与 TurnOutcome。
//
// 实测（opencode 2.2.5）：
//   * 事件是**全局**的 /api/event，必须按 data.sessionID 过滤；
//   * 一次执行以 session.execution.succeeded / .failed / .interrupted 收尾；
//   * 工具调用的名字在 session.tool.input.started，参数在 session.tool.called.input；
//   * 中断是 POST /api/session/{id}/interrupt，约 10ms 内生效。
package uhp_opencode

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.DateTime
import uhp.server.*
import uhp.types.generated.*
import uhp_opencode.client.*

public class OpencodeOptions {
    public let baseUrl: String
    public let directory: String
    public let user: String
    public let password: String
    // (modelID, providerID)；None = 用 opencode 自己的默认模型
    public let model: Option<(String, String)>
    public let timeoutSeconds: Int64
    public let label: String

    public init(baseUrl: String, directory: String,
                user!: String = "opencode", password!: String = "",
                model!: Option<(String, String)> = None,
                timeoutSeconds!: Int64 = 600, label!: String = "opencode 2.x") {
        this.baseUrl = baseUrl
        this.directory = directory
        this.user = user
        this.password = password
        this.model = model
        this.timeoutSeconds = timeoutSeconds
        this.label = label
    }
}

public class OpencodeDriver <: HarnessDriver {
    private let opts: OpencodeOptions
    private let lock = Mutex()
    // UHP 会话 -> opencode 会话：同一个 UHP 会话的后续任务应落在同一个 opencode 会话里
    private let sessions: HashMap<String, String> = HashMap<String, String>()
    // 等人类批准的权限请求（按 UHP 会话记）：下一轮续跑时把答案回给 opencode
    private let pendingPermissions: HashMap<String, String> = HashMap<String, String>()

    public init(opts: OpencodeOptions) {
        this.opts = opts
    }

    public func base(): String {
        return "opencode"
    }

    public func baseLabel(): String {
        return this.opts.label
    }

    public func models(): Array<Model> {
        let m = Model()
        match (this.opts.model) {
            case Some((mid, _)) =>
                m.id = mid
                m.label = mid
            case None =>
                m.id = "opencode-default"
                m.label = "opencode 默认模型"
        }
        m.available = true
        m.default = Some(true)
        return [m]
    }

    public func capabilities(): HarnessCapabilities {
        // 工具执行由 opencode 自己的沙箱做；input_requests 已接 opencode 的 permission 事件
        return HarnessCapabilities(false, true)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        try {
            return this.runInner(ctx, sink, cancel)
        } catch (e: Exception) {
            // 适配器自己出问题（网络/解析）必须是 failed，绝不能让它冒成 500 或吞成 completed
            eprintln("oc: driver exception: " + e.toString())
            return TurnOutcome.Failed("harness_error", "opencode adapter error")
        }
    }

    private func runInner(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        let http = OcHttp(this.opts.baseUrl, this.opts.user, this.opts.password)
        let ocSession = match (this.ensureSession(http, ctx.sessionId)) {
            case Some(v) => v
            case None => return TurnOutcome.Failed("harness_error", "opencode session create failed")
        }
        // 续跑（回答问题）：把答案作为权限决定回给 opencode，然后继续读事件（不再发 prompt）
        let answered = ctx.answers.size > 0 && this.pendingPermissions.contains(ctx.sessionId)
        let pump = EventPump(http)
        this.waitSubscription(pump, 3000)
        if (answered) {
            let permId = this.pendingPermissions[ctx.sessionId]
            this.pendingPermissions.remove(ctx.sessionId)
            let decision = ctx.answers[0]
            let reply = "{\"decision\":" + ocJsonQuote(decision) + "}"
            let (rstatus, _) = http.post("/api/session/" + ocSession + "/permission/" + permId + "/reply", reply)
            if (rstatus != UInt16(204) && rstatus != UInt16(200)) {
                return TurnOutcome.Failed("harness_error", "opencode permission reply HTTP " + rstatus.toString())
            }
        } else {
            let (pstatus, _) = http.post("/api/session/" + ocSession + "/prompt", this.promptJson(ctx.input))
            if (pstatus != UInt16(200)) {
                return TurnOutcome.Failed("harness_error", "opencode prompt HTTP " + pstatus.toString())
            }
        }
        let usage = Usage()
        let callNames = HashMap<String, String>()
        let callIds = HashMap<String, String>()
        let deadline = nowMillis() + this.opts.timeoutSeconds * 1000
        var interrupted = false
        while (true) {
            for (data in pump.drain()) {
                let ev = match (ocParseJson(data)) {
                    case Some(v) => v
                    case None => continue
                }
                let ty = ev.str("type") ?? ""
                if (ty == "server.connected") {
                    continue
                }
                let payload = match (ev.obj("data")) {
                    case Some(v) => v
                    case None => continue
                }
                let sid = payload.str("sessionID") ?? ""
                if (sid.size > 0 && sid != ocSession) {
                    continue
                }
                match (ty) {
                    case "session.text.delta" =>
                        sink.textDelta(payload.str("delta") ?? "")
                    case "session.reasoning.delta" =>
                        sink.reasoningDelta(payload.str("delta") ?? "")
                    case "session.tool.input.started" =>
                        let id = payload.str("id") ?? ""
                        if (id.size > 0) {
                            callNames[id] = payload.str("name") ?? "tool"
                        }
                    case "session.tool.called" =>
                        let id = payload.str("id") ?? ""
                        let name = callNames.get(id) ?? "tool"
                        let args = match (payload.raw("input")) {
                            case Some(v) => v
                            case None => "{}"
                        }
                        let uhpCall = sink.toolCall(name, args)
                        if (id.size > 0) {
                            callIds[id] = uhpCall
                        }
                    case "session.tool.success" =>
                        let id = payload.str("id") ?? ""
                        let uhpCall = callIds.get(id) ?? id
                        sink.toolResult(uhpCall, this.toolText(payload.raw("content") ?? "[]"))
                    case "session.tool.error" =>
                        let id = payload.str("id") ?? ""
                        let uhpCall = callIds.get(id) ?? id
                        sink.toolResult(uhpCall, this.toolText(payload.raw("content") ?? "[]"))
                    case "session.usage.updated" =>
                        this.fillUsage(usage, payload.raw("tokens"))
                    case "session.step.ended" =>
                        this.fillUsage(usage, payload.raw("tokens"))
                    case "permission.asked" =>
                        // opencode 在等工具批准：把它变成 UHP 的 input_request，本轮结束
                        let permId = payload.str("id") ?? ""
                        let action = payload.str("action") ?? "an action"
                        var prompt = "Allow " + action + "?"
                        match (payload.str("message")) {
                            case Some(m) => if (m.size > 0) {
                                prompt = m
                            }
                            case None => ()
                        }
                        let _ = sink.ask("confirm", prompt,
                            [("once", "Allow once"), ("always", "Always allow"), ("reject", "Reject")])
                        if (permId.size > 0) {
                            this.pendingPermissions[ctx.sessionId] = permId
                        }
                        return TurnOutcome.Incomplete(IncompleteReason.InputRequired, None)
                    case "session.execution.succeeded" =>
                        return TurnOutcome.Completed(Some(usage))
                    case "session.execution.failed" =>
                        return TurnOutcome.Failed("harness_error", "opencode execution failed")
                    case "session.execution.interrupted" =>
                        return TurnOutcome.Cancelled(Some(usage))
                    case _ => ()
                }
            }
            if (cancel.isCancelled() && !interrupted) {
                let (istatus, _) = http.post("/api/session/" + ocSession + "/interrupt", "{}")
                interrupted = true
                if (istatus != UInt16(200)) {
                    return TurnOutcome.Cancelled(Some(usage))
                }
            }
            if (interrupted) {
                // 等 opencode 回 interrupted 事件；超时就自己收尾
                if (nowMillis() > deadline) {
                    return TurnOutcome.Cancelled(Some(usage))
                }
            } else if (nowMillis() > deadline) {
                return TurnOutcome.Failed("harness_error", "opencode timeout")
            } else if (pump.isClosed() && pump.drain().size == 0) {
                return TurnOutcome.Failed("harness_error", "opencode event stream closed")
            }
            sleep(Duration.millisecond * 20)
        }
        return TurnOutcome.Failed("harness_error", "unreachable")
    }

    // 建/复用 opencode 会话
    private func ensureSession(http: OcHttp, uhpSession: String): Option<String> {
        synchronized(this.lock) {
            match (this.sessions.get(uhpSession)) {
                case Some(v) => return Some(v)
                case None => ()
            }
            // 首次：建会话并（可选）钉模型
            let body = "{\"title\":" + ocJsonQuote("uhp session " + uhpSession) +
                ",\"location\":{\"directory\":" + ocJsonQuote(this.opts.directory) + "}}"
            let (status, text) = http.post("/api/session", body)
            if (status != UInt16(200)) {
                return None
            }
            let sid = match (ocParseJson(text)) {
                case Some(o) => match (o.obj("data")) {
                    case Some(d) => d.str("id") ?? ""
                    case None => ""
                }
                case None => ""
            }
            if (sid.size == 0) {
                return None
            }
            match (this.opts.model) {
                case Some((mid, provider)) =>
                    let mbody = "{\"model\":{\"id\":" + ocJsonQuote(mid) +
                        ",\"providerID\":" + ocJsonQuote(provider) + "}}"
                    let _ = http.post("/api/session/" + sid + "/model", mbody)
                case None => ()
            }
            this.sessions[uhpSession] = sid
            return Some(sid)
        }
    }

    private func waitSubscription(pump: EventPump, timeoutMs: Int64): Unit {
        let deadline = nowMillis() + timeoutMs
        while (nowMillis() < deadline) {
            if (pump.drain().size > 0) {
                return
            }
            if (pump.isClosed()) {
                return
            }
            sleep(Duration.millisecond * 20)
        }
    }

    private func promptJson(text: String): String {
        return "{\"text\":" + ocJsonQuote(text) + ",\"delivery\":\"queue\"}"
    }

    private func fillUsage(usage: Usage, tokensRaw: Option<String>): Unit {
        let tokens = match (tokensRaw) {
            case Some(v) => match (ocParseJson(v)) {
                case Some(o) => o
                case None => return
            }
            case None => return
        }
        match (tokens.asInt("input")) {
            case Some(v) => usage.input_tokens = Some(v)
            case None => ()
        }
        match (tokens.asInt("output")) {
            case Some(v) => usage.output_tokens = Some(v)
            case None => ()
        }
        match (tokens.obj("cache")) {
            case Some(c) =>
                usage.cache_read_tokens = c.asInt("read")
                usage.cache_write_tokens = c.asInt("write")
            case None => ()
        }
        usage.total_tokens = Some(
            (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0))
    }

    // 工具结果：content 数组里取 text 部分
    private func toolText(contentRaw: String): String {
        let out = StringBuilder()
        for ((t, _) in ocJsonStrings(contentRaw, "text")) {
            out.append(t)
        }
        return out.toString()
    }
}

public func nowMillis(): Int64 {
    return DateTime.now().toUnixTimeStamp().toMilliseconds()
}
