// Harness 接缝：SDK 做协议面，driver 做真正的 agent 循环。
//
// 契约（设计 §7.2）：
//   1. driver 不碰存储、不碰 SSE：只往 TurnSink 写语义事件，帧与序号由 SDK 保证；
//   2. driver 抛异常 = SDK 记 failed(harness_error)，绝不允许吞成 completed；
//   3. 取消是协作式的：cancel 只置标志，driver 尽快返回 Cancelled；
//   4. 预算截断必须报 Incomplete，不允许报 Completed。
package uhp.server

import std.collection.ArrayList
import std.sync.{AtomicBool, Mutex}
import uhp.types.generated.*

public enum IncompleteReason {
    | MaxSteps
    | Timeout
    | InputRequired
    | Other(String)
}

public func incompleteReasonName(r: IncompleteReason): String {
    return match (r) {
        case IncompleteReason.MaxSteps => "max_steps"
        case IncompleteReason.Timeout => "timeout"
        case IncompleteReason.InputRequired => "input_required"
        case IncompleteReason.Other(s) => s
    }
}

public enum TurnOutcome {
    | Completed(Option<Usage>)
    | Incomplete(IncompleteReason, Option<Usage>)
    | Failed(String, String)      // code, message
    | Cancelled(Option<Usage>)
}

public class CancelToken {
    private let flag = AtomicBool(false)

    public init() {}

    public func cancel(): Unit {
        this.flag.store(true)
    }

    public func isCancelled(): Bool {
        return this.flag.load()
    }
}

// 随任务一起交给 driver 的文件（内联 file_data 或引用已上传的 file_id，都在 SDK 里解析成字节）
public class TurnFile {
    public let filename: String
    public let mediaType: String
    public let bytes: Array<UInt8>

    public init(filename: String, mediaType: String, bytes: Array<UInt8>) {
        this.filename = filename
        this.mediaType = mediaType
        this.bytes = bytes
    }
}

public class TurnContext {
    public let sessionId: String
    public let input: String
    public let model: String
    public let maxStep: Option<Int64>
    // 本轮可用的 MCP 服务器（直接配置 + 启用插件的并集，每轮重算）。
    // 元素是 McpServer 的 JSON 文本：driver 自己决定怎么连（UHP 不执行 MCP）。
    public let mcpServers: Array<String>
    // 本轮如果是「回答一个问题」的续跑，这里带人名下已答的答案（driver 不用自己去翻历史）
    public let answers: Array<String>
    // 本轮所在环境（Environments §6）：id + 只读 mount 路径，driver 自己决定怎么用
    public let environment: Option<String>
    public let environmentMount: Option<String>
    // 本次任务的输入文件（driver 自己决定怎么交给 agent）
    public let files: Array<TurnFile>

    public init(sessionId: String, input: String, model: String, maxStep!: Option<Int64> = None,
                mcpServers!: Array<String> = [], answers!: Array<String> = [],
                environment!: Option<String> = None, environmentMount!: Option<String> = None,
                files!: Array<TurnFile> = []) {
        this.sessionId = sessionId
        this.input = input
        this.model = model
        this.maxStep = maxStep
        this.mcpServers = mcpServers
        this.answers = answers
        this.environment = environment
        this.environmentMount = environmentMount
        this.files = files
    }
}

// driver 只能通过这些方法报事件；SDK 负责翻译成 UHP 事件并分配 sequence_number。
public interface TurnSink {
    func textDelta(delta: String): Unit
    func reasoningDelta(delta: String): Unit
    func toolCallArgsDelta(delta: String): Unit
    // MCP 挂掉之类的降级必须可见，不能静默
    func degrade(reason: String): Unit
    // driver 在会话工作目录里产出的文件。由 driver 声明（它拥有工作目录与工具），
    // SDK 负责登记成产物（Session -> Container -> File）。
    func producedFile(filename: String, content: Array<UInt8>): Unit
    // 向人提问（Tasks §3.2）：返回 input_request 的 id，driver 随后结束本轮。
    // 问题本身由 SDK 落成 items 与事件；答案通过下一次续跑的 TurnContext.answers 回到 driver。
    func ask(kind: String, prompt: String, options: Array<(String, String)>): String
    // 一次工具调用（§1.1 的 step 以「调用 + 结果」为一轮）。返回 call_id，
    // driver 拿到结果后用 toolResult 回填——两半都成为 response 的 output items。
    func toolCall(name: String, arguments: String): String
    func toolResult(callId: String, output: String): Unit
}

public class HarnessCapabilities {
    public let hardToolBlock: Bool
    public let inputRequests: Bool

    public init(hardToolBlock: Bool, inputRequests: Bool) {
        this.hardToolBlock = hardToolBlock
        this.inputRequests = inputRequests
    }
}

public interface HarnessDriver {
    func base(): String
    func baseLabel(): String
    func models(): Array<Model>
    func capabilities(): HarnessCapabilities
    func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome
}

// ---------- ScriptedHarness：给测试与一致性 SUT 用的确定性 driver ----------

public enum ScriptStep {
    | Text(String)
    | Reasoning(String)
    | ToolArgs(String)
    | Degrade(String)
    | File(String, String)      // 文件名, 内容（UTF-8 文本）
}

public class ScriptedHarness <: HarnessDriver {
    private let steps: Array<ScriptStep>
    private let finalOutcome: TurnOutcome
    // 每步之间检查取消标志，模拟协作式取消
    private let cancelledAfter: Int64

    // delayMillis：每步之间停一下。既让流式可观察（套件 S-09 检查「渐进而非末尾一把刷」），
    // 也给 background 任务留出被轮询到 in_progress 的窗口。
    private let delayMillis: Int64

    public init(steps: Array<ScriptStep>, finalOutcome: TurnOutcome, cancelledAfter!: Int64 = -1,
                delayMillis!: Int64 = 0) {
        this.steps = steps
        this.finalOutcome = finalOutcome
        this.cancelledAfter = cancelledAfter
        this.delayMillis = delayMillis
    }

    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "Scripted Harness"
    }

    public func models(): Array<Model> {
        let m = Model()
        m.id = "scripted-model"
        m.available = true
        return [m]
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        var i: Int64 = 0
        for (step in this.steps) {
            if (cancel.isCancelled()) {
                return TurnOutcome.Cancelled(None)
            }
            if (this.cancelledAfter >= 0 && i >= this.cancelledAfter) {
                cancel.cancel()
            }
            match (step) {
                case Text(t) => sink.textDelta(t)
                case Reasoning(t) => sink.reasoningDelta(t)
                case ToolArgs(t) => sink.toolCallArgsDelta(t)
                case Degrade(t) => sink.degrade(t)
                case File(name, content) => sink.producedFile(name, content.toArray())
            }
            if (this.delayMillis > 0) {
                sleep(Duration.millisecond * this.delayMillis)
            }
            i = i + 1
        }
        if (cancel.isCancelled()) {
            return TurnOutcome.Cancelled(None)
        }
        return this.finalOutcome
    }
}
