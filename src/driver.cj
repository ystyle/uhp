// ACP（Agent Client Protocol）的 UHP HarnessDriver 适配器。
//
// 翻译关系（一对一，不做语义加工）：
//   UHP TurnContext.input          -> ACP session/prompt（内容块 = 一行文本）
//   ACP agent_message_chunk        -> TurnSink.textDelta
//   ACP agent_thought_chunk        -> TurnSink.reasoningDelta
//   ACP tool_call / tool_call_update -> TurnSink.toolCall / toolResult
//   ACP stopReason                 -> UHP TurnOutcome（end_turn/cancelled/max_* 等）
//   UHP CancelToken                -> ACP session/cancel（由监控线程发）
//
// ACP 的 session/request_permission（Agent 反向请求）暂未映射成 UHP input_request：
// 那是**同步**回调，而 UHP 的提问要走「本轮结束 + 下一轮续跑」，两者模型不同；
// 需要的能力已在 acp-cj 里（setOnRequestPermission），留给后续按两轮问答实现。
package uhp_acp

import std.collection.{ArrayList, HashMap}
import std.sync.{AtomicBool, Mutex}
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

    public init(command: String, args!: Array<String> = [], cwd!: String = "/tmp",
                label!: String = "ACP agent", clientName!: String = "uhp-cj",
                timeoutSeconds!: Int64 = 600) {
        this.command = command
        this.args = args
        this.cwd = cwd
        this.label = label
        this.clientName = clientName
        this.timeoutSeconds = timeoutSeconds
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
    private var seq: Int64 = 0

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
        return HarnessCapabilities(false, false)
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
        let sessionId = match (this.ensureSession(client, ctx.sessionId)) {
            case Some(s) => s
            case None => return TurnOutcome.Failed("harness_error", "ACP session/new failed")
        }
        synchronized(this.lock) {
            this.currentSink = Some(sink)
            this.currentSession = sessionId
        }
        // 取消监控：ACP 的 prompt 是阻塞调用，取消只能从旁路线程发 session/cancel
        let done = AtomicBool(false)
        let monitor = spawn {
            while (!done.load()) {
                if (cancel.isCancelled()) {
                    client.cancel(sessionId)
                    break
                }
                sleep(Duration.millisecond * 20)
            }
        }
        let result = client.promptText(sessionId, ctx.input,
            timeout: Duration.second * this.opts.timeoutSeconds)
        done.store(true)
        synchronized(this.lock) {
            this.currentSink = None
            this.currentSession = ""
        }
        let _ = monitor
        return match (result) {
            case Result.Ok(resp) => outcomeOf(resp.stopReason)
            case Result.Err(msg) => TurnOutcome.Failed("harness_error", "ACP prompt failed: " + msg)
        }
    }

    // ---------- 连接与会话 ----------

    private func ensureClient(): Option<AcpClient> {
        synchronized(this.lock) {
            match (this.client) {
                case Some(c) => return Some(c)
                case None => ()
            }
            let transport = SubprocessTransport(this.opts.command, args: this.opts.args)
            let c = AcpClient(transport)
            c.setOnSessionUpdate({ sid, update => this.onUpdate(sid, update) })
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

    // ---------- 通知映射 ----------

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
