// 服务端引擎：把「协议语义」和「HTTP 传输」隔开。
//
// 引擎负责：harness 注册、任务执行（driver -> 事件通道 -> Response 对象）、会话并发控制、
// 对象 scope（跨 principal 一律当作不存在）。HTTP 层只做请求解析、鉴权与错误封套。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.base.*
import uhp.types.codec.*
import uhp.types.generated.*
import uhp.types.handwritten.*

public class Principal {
    public let name: String

    public init(name: String) {
        this.name = name
    }
}

// 一个 configured harness：base + 配置 + 真正跑 agent 的 driver。
public class ConfiguredHarness {
    public let id: String
    public let name: String
    public let base: String
    public let defaultModel: String
    public let driver: HarnessDriver

    public init(id: String, name: String, base: String, defaultModel: String, driver: HarnessDriver) {
        this.id = id
        this.name = name
        this.base = base
        this.defaultModel = defaultModel
        this.driver = driver
    }
}

// 引擎级错误：带协议错误码与 HTTP 状态，HTTP 层直接翻译成错误封套。
public class EngineError <: Exception {
    public let code: String
    public let httpStatus: UInt16
    public let param: Option<String>
    public let reason: Option<String>

    public init(code: String, httpStatus: UInt16, param!: Option<String> = None, reason!: Option<String> = None) {
        super(code)
        this.code = code
        this.httpStatus = httpStatus
        this.param = param
        this.reason = reason
    }

    public func toEnvelope(): ErrorEnvelope {
        let t = if (this.httpStatus >= 500) { ErrorType.ServerError } else { ErrorType.InvalidRequestError }
        let env = ErrorEnvelope(t, this.code, messageFor(this.code))
        env.param = this.param
        return env
    }
}

func messageFor(code: String): String {
    return match (code) {
        case "harness_not_found" => "No such harness."
        case "harness_mismatch" => "The task named a different harness than the session it continues."
        case "session_busy" => "A task is already running in this session."
        case "response_not_found" => "No such response."
        case "session_not_found" => "No such session."
        case "session_expired" => "The session is past its retention."
        case "unsupported_protocol_version" => "The server cannot serve the requested protocol version."
        case "invalid_input" => "The request body is malformed."
        case _ => "Request failed."
    }
}

public class TaskRequest {
    public let input: String
    public let model: Option<String>
    public let harnessId: Option<String>
    public let previousResponseId: Option<String>

    public init(input: String, model!: Option<String> = None, harnessId!: Option<String> = None,
                previousResponseId!: Option<String> = None) {
        this.input = input
        this.model = model
        this.harnessId = harnessId
        this.previousResponseId = previousResponseId
    }
}

public class TaskResult {
    // 非流式路径直接读它；流式路径通过 channel 逐事件读
    public let response: Response
    public let channel: EventChannel

    public init(response: Response, channel: EventChannel) {
        this.response = response
        this.channel = channel
    }
}

class StoredResponse {
    public let owner: String
    public let response: Response
    public let channel: EventChannel

    public init(owner: String, response: Response, channel: EventChannel) {
        this.owner = owner
        this.response = response
        this.channel = channel
    }
}

public class Engine {
    private let lock = Mutex()
    private let idSource = IdSource()
    private let harnesses: HashMap<String, ConfiguredHarness> = HashMap<String, ConfiguredHarness>()
    private var defaultHarness: String = ""
    private let stored: HashMap<String, StoredResponse> = HashMap<String, StoredResponse>()
    private let sessions: HashMap<String, SessionState> = HashMap<String, SessionState>()
    private let sessionOwners: HashMap<String, String> = HashMap<String, String>()
    private let versions: Array<String>
    private let cls: ConformanceClass
    private let capabilitiesValue: Capabilities

    public init(harnesses: Array<ConfiguredHarness>, versions!: Array<String> = ["2026-10-19"],
                cls!: ConformanceClass = ConformanceClass.Core) {
        for (h in harnesses) {
            this.harnesses[h.id] = h
            if (this.defaultHarness == "") {
                this.defaultHarness = h.id
            }
        }
        this.versions = versions
        this.cls = cls
        // 端到端跑通 Core 所需的能力位（服务端 MUST 全写，缺省视为 false）
        let caps = Capabilities()
        caps.streaming = true
        caps.sessions = true
        caps.cancellation = true
        this.capabilitiesValue = caps
    }

    // ---------- 发现 ----------

    public func discovery(): Discovery {
        let d = Discovery()
        d.objectKind = "uhp.discovery"
        d.protocol = "uhp"
        d.versions = this.versions
        d.default_version = this.versions[0]
        d.conformance_class = conformanceClassName(this.cls)
        d.capabilities = this.capabilitiesValue
        let impl = DiscoveryImplementation()
        impl.name = "uhp-cj"
        impl.version = "0.1.0"
        d.implementation = Some(impl)
        return d
    }

    // ---------- harness ----------

    public func listHarnesses(): Array<Harness> {
        let out = ArrayList<Harness>()
        for ((_, h) in this.harnesses) {
            out.add(toHarness(h))
        }
        return out.toArray()
    }

    public func getHarness(id: String): Harness {
        match (this.harnesses.get(id)) {
            case Some(h) => return toHarness(h)
            case None => throw EngineError("harness_not_found", UInt16(404))
        }
    }

    public func harnessModels(id: String): HarnessModels {
        let h = match (this.harnesses.get(id)) {
            case Some(v) => v
            case None => throw EngineError("harness_not_found", UInt16(404))
        }
        let m = HarnessModels()
        m.harness_id = Some(h.id)
        m.backend = Some(h.base)
        m.default = Some(h.defaultModel)
        m.models = h.driver.models()
        return m
    }

    private func toHarness(h: ConfiguredHarness): Harness {
        let out = Harness()
        out.id = h.id
        out.objectKind = Some("harness")
        out.name = h.name
        out.base = h.base
        out.baseLabel = Some(h.driver.baseLabel())
        out.defaultModel = Some(h.defaultModel)
        out.createdAt = Some(nowSeconds())
        return out
    }

    // ---------- 任务 ----------

    public func createTask(p: Principal, req: TaskRequest): TaskResult {
        synchronized(this.lock) {
            return this.createTaskLocked(p, req)
        }
    }

    private func createTaskLocked(p: Principal, req: TaskRequest): TaskResult {
        let harnessId = match (req.harnessId) {
            case Some(h) => h
            case None => this.defaultHarness
        }
        let harness = match (this.harnesses.get(harnessId)) {
            case Some(h) => h
            case None => throw EngineError("harness_not_found", UInt16(404), param: Some("metadata.harness_id"))
        }

        let responseId = this.idSource.response()
        let sessionId: String
        let session: SessionState
        let previous: Option<Response>
        match (req.previousResponseId) {
            case Some(prevId) =>
                let prev = this.getStoredLocked(p, prevId)
                sessionId = match (prev.response.metadata) {
                    case Some(m) => m.session_id ?? ""
                    case None => ""
                }
                session = match (this.sessions.get(sessionId)) {
                    case Some(s) => s
                    case None => throw EngineError("session_not_found", UInt16(404))
                }
                if (!session.acceptsHarness(harnessId)) {
                    throw EngineError("harness_mismatch", UInt16(409))
                }
                previous = Some(prev.response)
            case None =>
                sessionId = this.idSource.session()
                session = SessionState(sessionId, harnessId)
                this.sessions[sessionId] = session
                this.sessionOwners[sessionId] = p.name
                previous = None
        }
        if (!session.tryBegin(responseId)) {
            throw EngineError("session_busy", UInt16(409))
        }

        let channel = EventChannel()
        let model = match (req.model) {
            case Some(m) => m
            case None => harness.defaultModel
        }
        let resp = Response()
        resp.id = responseId
        resp.objectKind = "response"
        resp.created_at = nowSeconds()
        resp.status = "in_progress"
        resp.model = model
        resp.store = Some(true)
        let meta = ResponseMetadata()
        meta.session_id = Some(sessionId)
        resp.metadata = Some(meta)
        match (previous) {
            case Some(prev) => resp.previous_response_id = Some("\"" + prev.id + "\"")
            case None => ()
        }

        // 事件 0：response.created（规范：created 必须是流的第一个事件）
        channel.emit("response.created", eventWithResponse("response.created", 0, resp))

        let sink = EngineSink(channel, this.idSource)
        let outcome = try {
            harness.driver.run(TurnContext(sessionId, req.input, model), sink, CancelToken())
        } catch (e: Exception) {
            // driver 抛异常 = failed(harness_error)，绝不允许吞成 completed
            TurnOutcome.Failed("harness_error", "harness failed")
        }

        let finalStatus = this.applyOutcome(resp, outcome, sink)
        let terminalType = match (finalStatus) {
            case TaskStatus.Completed => "response.completed"
            case TaskStatus.Incomplete => "response.incomplete"
            case TaskStatus.Failed => "response.failed"
            case TaskStatus.Cancelled => "response.failed"   // 规范：取消也用 failed 事件，status 才是权威
            case _ => "response.completed"
        }
        let seq = channel.lastSeq() + 1
        channel.emit(terminalType, eventWithResponse(terminalType, seq, resp))
        channel.close()

        this.stored[responseId] = StoredResponse(p.name, resp, channel)
        session.finish()
        return TaskResult(resp, channel)
    }

    private func applyOutcome(resp: Response, outcome: TurnOutcome, sink: EngineSink): TaskStatus {
        let status = match (outcome) {
            case TurnOutcome.Completed(_) => TaskStatus.Completed
            case TurnOutcome.Incomplete(_, _) => TaskStatus.Incomplete
            case TurnOutcome.Failed(_, _) => TaskStatus.Failed
            case TurnOutcome.Cancelled(_) => TaskStatus.Cancelled
        }
        resp.status = taskStatusName(status)
        match (outcome) {
            case TurnOutcome.Completed(u) => resp.usage = u
            case TurnOutcome.Incomplete(reason, u) =>
                resp.usage = u
                let d = ResponseIncompleteDetails()
                // schema 里 ResponseIncompleteDetails 没有 reason 字段（prose 要求有）：
                // 用 extras 承载原始 JSON，结构以 prose 为准、不发明新字段。
                d.extras["reason"] = "\"" + incompleteReasonName(reason) + "\""
                resp.incomplete_details = Some(d)
            case TurnOutcome.Failed(code, msg) =>
                let e = ErrorObject()
                e.typeName = "harness_error"
                e.code = code
                e.message = msg
                resp.error = Some(e)
            case TurnOutcome.Cancelled(_) => ()
        }
        // 输出项：文本/推理/工具参数各聚成一个 item（够 Core 用；细粒度事件后续补）
        let items = ArrayList<OutputItem>()
        let text = sink.joinedText()
        if (text.size > 0) {
            let part = ContentPart()
            part.typeName = "output_text"
            part.text = Some(text)
            let item = OutputItem()
            item.typeName = "message"
            item.role = Some("assistant")
            item.status = Some("completed")
            item.content = Some([part])
            items.add(item)
        }
        let reasoning = sink.joinedReasoning()
        if (reasoning.size > 0) {
            let item = OutputItem()
            item.typeName = "reasoning"
            item.status = Some("completed")
            item.summary = Some([reasoning])
            items.add(item)
        }
        let args = sink.joinedToolArgs()
        if (args.size > 0) {
            let item = OutputItem()
            item.typeName = "function_call"
            item.name = Some("tool")
            item.arguments = Some(args)
            item.status = Some("completed")
            items.add(item)
        }
        resp.output = items.toArray()
        return status
    }

    // ---------- 读回 / 取消 / 删除 ----------

    public func getResponse(p: Principal, id: String): Response {
        synchronized(this.lock) {
            return this.getStoredLocked(p, id).response
        }
    }

    public func getEvents(p: Principal, id: String, fromSeq: Int64): Array<StoredEvent> {
        synchronized(this.lock) {
            return this.getStoredLocked(p, id).channel.replay(fromSeq)
        }
    }

    public func cancelResponse(p: Principal, id: String): Response {
        synchronized(this.lock) {
            let stored = this.getStoredLocked(p, id)
            // 同步执行模型下任务已经结束；取消已终态的任务必须成功且无副作用（规范）
            return stored.response
        }
    }

    public func cancelSession(p: Principal, sessionId: String): Unit {
        synchronized(this.lock) {
            match (this.sessionOwners.get(sessionId)) {
                case Some(owner) => if (owner != p.name) {
                        throw EngineError("session_not_found", UInt16(404))
                    }
                case None => throw EngineError("session_not_found", UInt16(404))
            }
        }
    }

    public func deleteResponse(p: Principal, id: String): Bool {
        synchronized(this.lock) {
            match (this.stored.get(id)) {
                case Some(s) =>
                    if (s.owner != p.name) {
                        throw EngineError("response_not_found", UInt16(404))
                    }
                    this.stored.remove(id)
                    return true
                case None => throw EngineError("response_not_found", UInt16(404))
            }
        }
    }

    private func getStoredLocked(p: Principal, id: String): StoredResponse {
        return match (this.stored.get(id)) {
            // 跨 principal 一律 404（403 会确认 id 存在）
            case Some(s) => if (s.owner == p.name) { s } else { throw EngineError("response_not_found", UInt16(404)) }
            case None => throw EngineError("response_not_found", UInt16(404))
        }
    }
}

// ---------- driver 事件累积 ----------

class EngineSink <: TurnSink {
    private let channel: EventChannel
    private let ids: IdSource
    private let texts: ArrayList<String> = ArrayList<String>()
    private let reasonings: ArrayList<String> = ArrayList<String>()
    private let toolArgs: ArrayList<String> = ArrayList<String>()
    private var seq: Int64 = 1
    private let itemId: String

    public init(channel: EventChannel, ids: IdSource) {
        this.channel = channel
        this.ids = ids
        this.itemId = "msg_" + channel.lastSeq().toString()
    }

    public func textDelta(delta: String): Unit {
        this.texts.add(delta)
        this.emitDelta("response.output_text.delta", delta)
    }

    public func reasoningDelta(delta: String): Unit {
        this.reasonings.add(delta)
        this.emitDelta("response.reasoning_summary_text.delta", delta)
    }

    public func toolCallArgsDelta(delta: String): Unit {
        this.toolArgs.add(delta)
        this.emitDelta("response.function_call_arguments.delta", delta)
    }

    public func degrade(reason: String): Unit {
        // 降级要可见：写一个 error 事件（非终止），随后仍有终态事件
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("type").writeValue("error")
        w.writeName("sequence_number").writeValue(this.channel.lastSeq() + 1)
        w.writeName("message").writeValue(reason)
        w.endObject()
        w.flush()
        this.channel.emit("error", String.fromUtf8(out.bytes()))
    }

    private func emitDelta(eventType: String, delta: String): Unit {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("type").writeValue(eventType)
        w.writeName("sequence_number").writeValue(this.channel.lastSeq() + 1)
        w.writeName("item_id").writeValue(this.itemId)
        w.writeName("output_index").writeValue(0)
        w.writeName("content_index").writeValue(0)
        w.writeName("delta").writeValue(delta)
        w.endObject()
        w.flush()
        this.channel.emit(eventType, String.fromUtf8(out.bytes()))
    }

    public func joinedText(): String {
        return String.join(this.texts.toArray(), delimiter: "")
    }

    public func joinedReasoning(): String {
        return String.join(this.reasonings.toArray(), delimiter: "")
    }

    public func joinedToolArgs(): String {
        return String.join(this.toolArgs.toArray(), delimiter: "")
    }
}

// ---------- 序列化辅助 ----------

func nowSeconds(): Int64 {
    return DateTime.now().toUnixTimeStamp().toSeconds()
}

func jsonOf<T>(v: T): String where T <: JsonSerializable {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    v.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}

func eventWithResponse(eventType: String, seq: Int64, resp: Response): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("type").writeValue(eventType)
    w.writeName("sequence_number").writeValue(seq)
    w.writeName("response").jsonValue(jsonOf(resp))
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}
