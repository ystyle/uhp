// 服务端引擎：把「协议语义」和「HTTP 传输」隔开。
//
// 引擎负责：harness 注册、任务执行（driver -> 事件通道 -> Response 对象）、会话并发控制、
// 对象 scope（跨 principal 一律当作不存在）。HTTP 层只做请求解析、鉴权与错误封套。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.env
import std.fs.{Directory, canonicalize, exists, removeIfExists, File as FsFile}
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
    // 结构化 detail 的 JSON 片段（如 {"supported":[...]}）
    public let detailJson: Option<String>

    public init(code: String, httpStatus: UInt16, param!: Option<String> = None,
                reason!: Option<String> = None, detailJson!: Option<String> = None) {
        super(code)
        this.code = code
        this.httpStatus = httpStatus
        this.param = param
        this.reason = reason
        this.detailJson = detailJson
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

// 请求里的文件引用：内联数据（data URL 解出的字节）或已上传文件 id
public class TaskFileRef {
    public let filename: String
    public let mediaType: String
    public let bytes: Option<Array<UInt8>>
    public let fileId: Option<String>

    public init(filename: String, mediaType: String, bytes!: Option<Array<UInt8>> = None,
                fileId!: Option<String> = None) {
        this.filename = filename
        this.mediaType = mediaType
        this.bytes = bytes
        this.fileId = fileId
    }
}

public class TaskRequest {
    public let input: String
    public let model: Option<String>
    public let harnessId: Option<String>
    public let previousResponseId: Option<String>
    // background: 立即返回 in_progress，任务在后台跑（Lifecycle §3 的唯一非终态）
    public let background: Bool
    // 客户端发了、但服务端不执行的字段（UHP 的 tools/include 是保留字段）：
    // 规范要求「忽略必须可观测」，必须出现在 metadata.ignored_fields 里。
    public let ignoredFields: Array<String>
    // 续跑如果是「回答一个问题」：input_request_id + 答案（§3.2）
    public let inputResponse: Option<(String, String)>
    // §1.1 的 step 预算：超过了必须 incomplete，且不许报 completed
    public let maxStep: Option<Int64>
    // metadata.environment：本任务在哪个环境里跑（§5/§6）
    public let environment: Option<String>
    // 输入文件：内联字节或已上传文件 id（engine 在开任务前解析成 TurnFile）
    public let files: Array<TaskFileRef>

    public init(input: String, model!: Option<String> = None, harnessId!: Option<String> = None,
                previousResponseId!: Option<String> = None, background!: Bool = false,
                ignoredFields!: Array<String> = [], inputResponse!: Option<(String, String)> = None,
                maxStep!: Option<Int64> = None, environment!: Option<String> = None,
                files!: Array<TaskFileRef> = []) {
        this.input = input
        this.model = model
        this.harnessId = harnessId
        this.previousResponseId = previousResponseId
        this.background = background
        this.ignoredFields = ignoredFields
        this.inputResponse = inputResponse
        this.maxStep = maxStep
        this.environment = environment
        this.files = files
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
    // 会话元数据（列表/检查/turns 用）与产物存储
    private let records: HashMap<String, SessionRecord> = HashMap<String, SessionRecord>()
    // harness 管理（Full 类）
    private let harnessRecords: HashMap<String, HarnessRecord> = HashMap<String, HarnessRecord>()
    private let idemKeys: HashMap<String, String> = HashMap<String, String>()
    private let idemBodies: HashMap<String, String> = HashMap<String, String>()
    private var factory: Option<(String) -> HarnessDriver> = None
    private let supportedBases: Array<String>
    private let files: HashMap<String, StoredFile> = HashMap<String, StoredFile>()
    // 分享（Sessions §5）与每个响应的文本（共享视图用，不存 provider 侧任何东西）
    private let shares: HashMap<String, ShareRecord> = HashMap<String, ShareRecord>()
    private let responseTexts: HashMap<String, String> = HashMap<String, String>()
    // 待回答的问题（按 input_request id）与每个响应收到的输入 items（客户端可读，secret 除外）
    private let inputRequests: HashMap<String, PendingInputRequest> = HashMap<String, PendingInputRequest>()
    private let inputItems: HashMap<String, String> = HashMap<String, String>()
    // 环境（Environments 章）：每个环境一个真实目录（mount），build 后只读
    private let envs: HashMap<String, EnvRecord> = HashMap<String, EnvRecord>()
    private let envBase: String = envBaseDir()
    // 包检查的 registry 查询接缝：宿主注入（None = 本服务端不提供该可选端点）
    private var packageChecker: Option<(String, String) -> Option<PackageCheckResult>> = None
    // 记忆（Memories 章）：树节点 / 记录 / 双向链接
    private let memories: HashMap<String, MemoryNodeRec> = HashMap<String, MemoryNodeRec>()
    private let memRecords: HashMap<String, MemoryRecordRec> = HashMap<String, MemoryRecordRec>()
    private let memLinks: HashMap<String, ArrayList<(String, String)>> = HashMap<String, ArrayList<(String, String)>>()
    private let memProvider: String = "uhp-local"
    // POST 记录的应答要带 closed/conflicts（不存储）
    private let memWriteExtras: HashMap<String, (Array<String>, Array<String>)> = HashMap<String, (Array<String>, Array<String>)>()
    private let versions: Array<String>
    private let cls: ConformanceClass
    private let capabilitiesValue: Capabilities

    public init(harnesses: Array<ConfiguredHarness>, versions!: Array<String> = ["2026-10-19"],
                cls!: ConformanceClass = ConformanceClass.Core,
                driverFactory!: Option<(String) -> HarnessDriver> = None,
                supportedBases!: Option<Array<String>> = None,
                packageChecker!: Option<(String, String) -> Option<PackageCheckResult>> = None) {
        let bases = ArrayList<String>()
        for (h in harnesses) {
            this.harnesses[h.id] = h
            if (this.defaultHarness == "") {
                this.defaultHarness = h.id
            }
            let rec = HarnessRecord(h.id, h.name, h.base)
            rec.defaultModel = Some(h.defaultModel)
            this.harnessRecords[h.id] = rec
            bases.add(h.base)
        }
        this.factory = driverFactory
        this.packageChecker = packageChecker
        if (let Some(bs) <- supportedBases) {
            this.supportedBases = bs
        } else {
            this.supportedBases = bases.toArray()
        }
        this.versions = versions
        this.cls = cls
        // 端到端跑通 Core 所需的能力位（服务端 MUST 全写，缺省视为 false）
        let caps = Capabilities()
        caps.streaming = true
        caps.sessions = true
        caps.cancellation = true
        // Extended 才要求文件与会话列举；能力与类必须自洽（Lifecycle §2）
        match (cls) {
            case ConformanceClass.Core => ()
            case ConformanceClass.Extended =>
                caps.filesInput = true
                caps.filesOutput = true
                caps.sessionListing = true
            case ConformanceClass.Full =>
                caps.filesInput = true
                caps.filesOutput = true
                caps.sessionListing = true
                caps.harnessManagement = true
                // 创建 harness 的幂等键（F-10）：key 保留在内存里，同 key 返回第一次的结果
                caps.harnessIdempotency = true
                caps.plugins = true
                caps.sessionSharing = true
                caps.inputRequests = true
                caps.environments = true
                caps.memories = true
        }
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
        if (this.capabilitiesValue.plugins) {
            d.plugin_schemas = Some(SUPPORTED_PLUGIN_SCHEMAS)
        }
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

    // 同步语义：启动任务并等到终态（测试、非 background 的非流式请求走这里）。
    public func createTask(p: Principal, req: TaskRequest): TaskResult {
        let result = this.startTask(p, req)
        // 等任务落终态（通道关闭即表示终态事件已发出）
        while (!result.channel.isClosed()) {
            sleep(Duration.millisecond * 2)
        }
        return result
    }

    // 异步启动：立刻返回 in_progress 的 response 与事件通道；driver 在后台协程里跑。
    // background 请求与流式请求都走这里——否则 background 永远返回 completed（套件 T-11）。
    public func startTask(p: Principal, req: TaskRequest): TaskResult {
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
        // 回答一个问题：请求、选项、重复都要在开新响应之前判断（否则会留下一个孤儿响应）
        match (req.inputResponse) {
            case Some((requestId, answer)) =>
                let pending = match (this.inputRequests.get(requestId)) {
                    case Some(v) => v
                    case None => throw EngineError("input_not_pending", UInt16(409), param: Some("input"))
                }
                if (pending.answered) {
                    throw EngineError("input_not_pending", UInt16(409), param: Some("input"))
                }
                if (!pending.accepts(answer)) {
                    throw EngineError("input_response_invalid", UInt16(422), param: Some("input"))
                }
                pending.answered = true
            case None => ()
        }
        let previousId = match (req.inputResponse) {
            case Some((requestId, _)) => match (this.inputRequests.get(requestId)) {
                case Some(p) => Some(p.responseId)
                case None => req.previousResponseId
            }
            case None => req.previousResponseId
        }
        let sessionId: String
        let session: SessionState
        let previous: Option<Response>
        match (previousId) {
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
                let containerId = this.idSource.container()
                this.records[sessionId] = SessionRecord(sessionId, harnessId, p.name, containerId,
                    titleOf(req.input))
                previous = None
        }
        // 环境：显式 metadata.environment 优先，否则用 harness 配的那个
        let envId: Option<String> = match (req.environment) {
            case Some(e) => Some(e)
            case None => match (this.harnessRecords.get(harness.id)) {
                case Some(rec) => rec.environment
                case None => None
            }
        }
        let envMount: Option<String> = match (envId) {
            case Some(eid) =>
                let env = match (this.envs.get(eid)) {
                    case Some(e) => e
                    case None => throw EngineError("environment_not_found", UInt16(404), param: Some("metadata.environment"))
                }
                // 没 build 的环境不能拿来跑任务：必须在任务开始前拒绝（EN-05）
                match (env.active) {
                    case Some(_) => ()
                    case None => throw EngineError("environment_not_ready", UInt16(409), param: Some("metadata.environment"))
                }
                Some(env.mount)
            case None => None
        }
        // 输入文件：内联字节直接用；file_id 从已上传文件表解析（跨 principal 一律当不存在）
        let turnFiles = ArrayList<TurnFile>()
        for (fref in req.files) {
            match (fref.bytes) {
                case Some(b) => turnFiles.add(TurnFile(fref.filename, fref.mediaType, b))
                case None => match (fref.fileId) {
                    case Some(fid) => match (this.files.get(fid)) {
                        case Some(stored) =>
                            if (stored.owner == p.name) {
                                let name = if (fref.filename.size > 0) { fref.filename } else { stored.filename }
                                let mt = if (fref.mediaType.size > 0) { fref.mediaType } else { stored.contentType() }
                                turnFiles.add(TurnFile(name, mt, stored.bytes))
                            }
                        case None => ()
                    }
                    case None => ()
                }
            }
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
        if (req.ignoredFields.size > 0) {
            // 规范：服务端忽略请求字段时必须点名（tools/include 是保留字段）
            meta.ignored_fields = Some(req.ignoredFields)
        }
        match (envId) {
            case Some(eid) =>
                meta.environment = Some(eid)
                match (this.records.get(sessionId)) {
                    case Some(rec) => rec.environment = Some(eid)
                    case None => ()
                }
            case None => ()
        }
        resp.metadata = Some(meta)
        match (previous) {
            case Some(prev) => resp.previous_response_id = Some("\"" + prev.id + "\"")
            case None => ()
        }

        // 事件 0：response.created（规范：created 必须是流的第一个事件）
        channel.emit("response.created", eventWithResponse("response.created", 0, resp))
        this.stored[responseId] = StoredResponse(p.name, resp, channel)
        this.inputItems[responseId] = this.inputItemsJsonFor(req)
        match (this.records.get(sessionId)) {
            case Some(rec) =>
                rec.responseIds.add(responseId)
                rec.updatedAt = nowSeconds()
            case None => ()
        }

        // driver 在后台跑：background / 流式请求要能立刻拿到 in_progress 与事件通道。
        // 校验（harness/session/scope）已经在锁内完成，所以 4xx 能赶在响应头之前返回。
        let sink = EngineSink(channel, this.idSource)
        spawn {
            this.executeTask(harness, req, sessionId, resp, channel, sink, envId, envMount,
                turnFiles.toArray())
        }
        return TaskResult(resp, channel)
    }

    private func executeTask(harness: ConfiguredHarness, req: TaskRequest, sessionId: String,
                             resp: Response, channel: EventChannel, sink: EngineSink,
                             envId: Option<String>, envMount: Option<String>,
                             turnFiles: Array<TurnFile>): Unit {
        let outcome = try {
            let mcpServers = match (this.harnessRecords.get(harness.id)) {
                case Some(rec) => composedMcpServers(rec)
                case None => Array<String>()
            }
            let answers = match (req.inputResponse) {
                case Some((_, answer)) => [answer]
                case None => Array<String>()
            }
            harness.driver.run(TurnContext(sessionId, req.input, resp.model, maxStep: req.maxStep,
                mcpServers: mcpServers, answers: answers, environment: envId,
                environmentMount: envMount, files: turnFiles), sink, CancelToken())
        } catch (e: Exception) {
            // driver 抛异常 = failed(harness_error)，绝不允许吞成 completed
            TurnOutcome.Failed("harness_error", "harness failed")
        }
        synchronized(this.lock) {
            let pending = sink.pendingRequests()
            let maxStep = req.maxStep
            let overBudget = match (maxStep) {
                case Some(n) => sink.rounds() > n
                case None => false
            }
            let effective = if (pending.size > 0) {
                match (outcome) {
                    case TurnOutcome.Completed(_) => TurnOutcome.Incomplete(IncompleteReason.InputRequired, None)
                    case other => other
                }
            } else if (overBudget) {
                // 规范：被预算截断的工作绝不报 completed（否则客户端会把截断当成完成）
                match (outcome) {
                    case TurnOutcome.Failed(_, _) => outcome
                    case TurnOutcome.Cancelled(_) => outcome
                    case _ => TurnOutcome.Incomplete(IncompleteReason.MaxSteps, None)
                }
            } else {
                outcome
            }
            let finalStatus = this.applyOutcome(resp, effective, sink)
            if (pending.size > 0) {
                this.finishWithQuestions(resp, pending)
            }
            let terminalType = match (finalStatus) {
                case TaskStatus.Completed => "response.completed"
                case TaskStatus.Incomplete => "response.incomplete"
                case TaskStatus.Failed => "response.failed"
                case TaskStatus.Cancelled => "response.failed"   // 取消也用 failed 事件；status 才是权威
                case _ => "response.completed"
            }
            let seq = channel.lastSeq() + 1
            channel.emit(terminalType, eventWithResponse(terminalType, seq, resp))
            channel.close()
            this.responseTexts[resp.id] = sink.collectedText()
            // 产物登记：driver 声明它写了哪些文件，SDK 记进会话容器
            match (this.records.get(sessionId)) {
                case Some(rec) =>
                    for ((name, content) in sink.producedFiles()) {
                        let fid = this.idSource.file()
                        this.files[fid] = StoredFile(fid, rec.containerId, sessionId, rec.owner, name, content)
                    }
                case None => ()
            }
            match (this.sessions.get(sessionId)) {
                case Some(s) => s.finish()
                case None => ()
            }
        }
    }

    // 问题落成 items：function_call（ask_user）+ 承载问题文本的 message + input_request
    private func finishWithQuestions(resp: Response, pending: Array<PendingInputRequest>): Unit {
        for (p in pending) {
            this.inputRequests[p.id] = PendingInputRequest(p.id, resp.id, p.kind, p.prompt, p.options)
        }
        let items = ArrayList<OutputItem>()
        for (o in resp.output) {
            items.add(o)
        }
        for (p in pending) {
            items.add(p.toFunctionCallItem())
        }
        var promptText = ""
        for (p in pending) {
            promptText = promptText + p.prompt + " "
        }
        let part = ContentPart()
        part.typeName = "output_text"
        part.text = Some(promptText)
        let msg = OutputItem()
        msg.id = Some("msg_" + resp.id)
        msg.typeName = "message"
        msg.role = Some("assistant")
        msg.status = Some("incomplete")
        msg.content = Some([part])
        items.add(msg)
        for (p in pending) {
            items.add(p.toItem())
        }
        resp.output = items.toArray()
    }

    // 客户端可读的输入 items：secret 的答案**不写进来**（T-14 逐一检查）
    private func inputItemsJsonFor(req: TaskRequest): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        match (req.inputResponse) {
            case Some((requestId, answer)) =>
                let secret = match (this.inputRequests.get(requestId)) {
                    case Some(p) => p.isSecret()
                    case None => false
                }
                w.startObject()
                w.writeName("type").writeValue("input_response")
                w.writeName("input_request_id").writeValue(requestId)
                if (!secret) {
                    w.writeName("answer").writeValue(answer)
                }
                w.endObject()
            case None =>
                w.startObject()
                w.writeName("type").writeValue("message")
                w.writeName("role").writeValue("user")
                w.writeName("content")
                w.startArray()
                w.startObject()
                w.writeName("type").writeValue("input_text")
                w.writeName("text").writeValue(req.input)
                w.endObject()
                w.endArray()
                w.endObject()
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(out.bytes())
    }

    public func responseInputItems(p: Principal, responseId: String): String {
        synchronized(this.lock) {
            let _ = this.getStoredLocked(p, responseId)
            return this.inputItems.get(responseId) ?? "[]"
        }
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
        for ((callId, name, args) in sink.toolCalls()) {
            let item = OutputItem()
            item.id = Some("fc_" + callId)
            item.typeName = "function_call"
            item.name = Some(name)
            item.call_id = Some(callId)
            item.arguments = Some(args)
            item.status = Some("completed")
            items.add(item)
        }
        for ((callId, output) in sink.toolResults()) {
            let item = OutputItem()
            item.id = Some("fco_" + callId)
            item.typeName = "function_call_output"
            item.call_id = Some(callId)
            item.output = Some(output)
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

    // ---------- 记忆（Memories） ----------

    public func memoryProviderJsonText(): String {
        return memoryProviderJson()
    }

    public func createMemory(p: Principal, name: String, description: Option<String>,
                             parentId: Option<String>, provider: Option<String>): MemoryNodeRec {
        synchronized(this.lock) {
            let id = "hmem_" + this.idSource.session().replace("hsess", "")
            var prov = this.memProvider
            let provIn = match (provider) {
                case Some(v) => v
                case None => this.memProvider
            }
            prov = provIn
            let rec = MemoryNodeRec(id, name, description, prov)
            match (parentId) {
                case Some(pid) =>
                    let parent = this.memoryLocked(pid)
                    rec.parentId = Some(pid)
                    let anc = ArrayList<String>()
                    for (a in parent.ancestors) {
                        anc.add(a)
                    }
                    anc.add(parent.id)
                    rec.ancestors = anc.toArray()
                case None => ()
            }
            this.memories[id] = rec
            return rec
        }
    }

    private func memoryLocked(id: String): MemoryNodeRec {
        return match (this.memories.get(id)) {
            case Some(m) => m
            case None => throw EngineError("memory_not_found", UInt16(404), param: Some("memory_id"))
        }
    }

    public func getMemory(id: String): MemoryNodeRec {
        synchronized(this.lock) {
            return this.memoryLocked(id)
        }
    }

    public func memoriesByParent(parentId: String): Array<MemoryNodeRec> {
        synchronized(this.lock) {
            let out = ArrayList<MemoryNodeRec>()
            for ((_, m) in this.memories) {
                match (m.parentId) {
                    case Some(p) => if (p == parentId) {
                        out.add(m)
                    }
                    case None => ()
                }
            }
            return out.toArray()
        }
    }

    // 被授予的：调用者「自己进入」的记忆（没有父节点的那种）
    public func grantedMemories(): Array<MemoryNodeRec> {
        synchronized(this.lock) {
            let out = ArrayList<MemoryNodeRec>()
            for ((_, m) in this.memories) {
                if (m.parentId.isNone()) {
                    out.add(m)
                }
            }
            return out.toArray()
        }
    }

    public func memoryDescendants(id: String): Array<String> {
        synchronized(this.lock) {
            let out = ArrayList<String>()
            out.add(id)
            for ((_, m) in this.memories) {
                if (m.ancestors.contains(id)) {
                    out.add(m.id)
                }
            }
            return out.toArray()
        }
    }

    public func deleteMemoryTree(id: String): Unit {
        synchronized(this.lock) {
            let _ = this.memoryLocked(id)
            let ids = this.memoryDescendants(id)
            for (mid in ids) {
                this.memories.remove(mid)
                let recs = ArrayList<String>()
                for ((rid, r) in this.memRecords) {
                    if (r.memoryId == mid) {
                        recs.add(rid)
                    }
                }
                for (rid in recs) {
                    this.memRecords.remove(rid)
                    this.memLinks.remove(rid)
                }
            }
        }
    }

    // 移动子树；移到自己的后代下会成环 -> 422
    public func moveMemory(id: String, newParentId: String): MemoryNodeRec {
        synchronized(this.lock) {
            let rec = this.memoryLocked(id)
            let _ = this.memoryLocked(newParentId)
            if (newParentId == id || this.memoryDescendants(id).contains(newParentId)) {
                throw EngineError("memory_invalid", UInt16(422), param: Some("parent_id"))
            }
            let parent = this.memoryLocked(newParentId)
            rec.parentId = Some(newParentId)
            let anc = ArrayList<String>()
            for (a in parent.ancestors) {
                anc.add(a)
            }
            anc.add(parent.id)
            rec.ancestors = anc.toArray()
            rec.updatedAt = nowSeconds()
            return rec
        }
    }

    public func createMemoryRecord(p: Principal, mid: String, w: MemoryWrite): MemoryRecordRec {
        synchronized(this.lock) {
            let memory = this.memoryLocked(mid)
            if (w.typeName.size == 0) {
                throw EngineError("memory_invalid", UInt16(422), param: Some("type"))
            }
            let contentJson = normalizeContent(w, FileStoreView(this.files))
            let attributesJson = w.attributesJson ?? "{}"
            let referencesJson = w.referencesJson ?? "[]"
            let timeJson = w.timeJson ?? "{}"
            let writtenBy = memoryWriterJson(p.name)
            let refs = refsOf(referencesJson)
            var searchText = contentSearchText(contentJson)
            match (w.title) {
                case Some(t) => searchText = t + " " + searchText
                case None => ()
            }
            let v = MemoryVersion(1, w.title, contentJson, attributesJson, referencesJson, timeJson,
                writtenBy, searchText, standingOf(attributesJson), refs, None)
            let id = "hmrec_" + this.idSource.session().replace("hsess", "")
            let rec = MemoryRecordRec(id, mid, w.typeName)
            rec.versions.add(v)
            this.memRecords[id] = rec
            // 引用是双向的：contradicts 在两边都留痕（ME-12）
            for ((rel, rid) in refs) {
                this.linkLocked(rec.id, rel, rid)
                if (rel == "contradicts") {
                    this.linkLocked(rid, rel, rec.id)
                    // 引用在两边都留痕：反向引用写进对方的版本（ME-12 从 GET 记录读得到）
                    match (this.memRecords.get(rid)) {
                        case Some(other) =>
                            let ov = other.latest()
                            ov.referencesJson = withReference(ov.referencesJson, rel, rec.id)
                            let all = ArrayList<(String, String)>()
                            for (r0 in ov.references) {
                                all.add(r0)
                            }
                            all.add((rel, rec.id))
                            ov.references = all.toArray()
                        case None => ()
                    }
                }
            }
            memory.updatedAt = nowSeconds()
            this.applyHoldsLocked(rec, p)
            return rec
        }
    }

    // 一个属性只持一个值（Memories §4.4）：新值可能结束旧值、可能只是与它冲突、也可能落进过去
    private func applyHoldsLocked(rec: MemoryRecordRec, p: Principal): Unit {
        let v = rec.latest()
        let attrs = match (tryParseJsonObject(v.attributesJson)) {
            case Some(o) => o
            case None => return
        }
        if ((attrs.str("holds") ?? "") != "one") {
            return
        }
        let predicate = attrs.str("predicate") ?? ""
        let start = match (timeField(v.timeJson, "valid_from")) {
            case Some(t) => t
            case None => return
        }
        // subject 引用
        var subject = ""
        for ((rel, rid) in v.references) {
            if (rel == "subject" && subject.size == 0) {
                subject = rid
            }
        }
        if (subject.size == 0) {
            return
        }
        // 同一 memory 内、同 subject+predicate 的其他 active 事实
        let existing = ArrayList<MemoryRecordRec>()
        for ((rid, r) in this.memRecords) {
            if (rid == rec.id || r.memoryId != rec.memoryId || r.status != "active") {
                continue
            }
            let rv = r.latest()
            let ra = match (tryParseJsonObject(rv.attributesJson)) {
                case Some(o) => o
                case None => continue
            }
            if ((ra.str("holds") ?? "") != "one" || (ra.str("predicate") ?? "") != predicate) {
                continue
            }
            var rsubject = ""
            for ((rel, xid) in rv.references) {
                if (rel == "subject" && rsubject.size == 0) {
                    rsubject = xid
                }
            }
            if (rsubject == subject) {
                existing.add(r)
            }
        }
        let sameStart = ArrayList<String>()
        let active = ArrayList<MemoryRecordRec>()
        var earliestLater: Option<String> = None
        for (f in existing) {
            let fv = f.latest()
            let fs = timeField(fv.timeJson, "valid_from") ?? ""
            let fe = timeField(fv.timeJson, "valid_to")
            if (fs == start) {
                sameStart.add(f.id)
            }
            // 在 start 时刻仍成立：开始 <= start 且没有结束（或结束晚于 start）
            let still = fs <= start && match (fe) {
                case Some(e) => e > start
                case None => true
            }
            if (still) {
                active.add(f)
            }
            if (fs > start) {
                match (earliestLater) {
                    case Some(cur) => if (fs < cur) {
                        earliestLater = Some(fs)
                    }
                    case None => earliestLater = Some(fs)
                }
            }
        }
        let closed = ArrayList<String>()
        let conflicts = ArrayList<String>()
        if (sameStart.size > 0) {
            // 同一时刻的第二个值：不是结束，是分歧
            for (fid in sameStart) {
                conflicts.add(fid)
                this.linkLocked(rec.id, "contradicts", fid)
                this.linkLocked(fid, "contradicts", rec.id)
                match (this.memRecords.get(fid)) {
                    case Some(other) =>
                        let ov = other.latest()
                        ov.referencesJson = withReference(ov.referencesJson, "contradicts", rec.id)
                        let all = ArrayList<(String, String)>()
                        for (r0 in ov.references) {
                            all.add(r0)
                        }
                        all.add(("contradicts", rec.id))
                        ov.references = all.toArray()
                    case None => ()
                }
                // 新值自己的 references 也留痕
                v.referencesJson = withReference(v.referencesJson, "contradicts", fid)
            }
            // 同一时刻的分歧不结束任何一边
        } else {
            // 结束 start 时刻仍成立的那些
            for (f in active) {
                this.closeFactLocked(f, start, p.name)
                closed.add(f.id)
            }
            // 该值自己结束于「下一个更晚的开始」（在它之后先开始的那个）
            match (earliestLater) {
                case Some(t) =>
                    v.timeJson = renderTime(Some(start), Some(t))
                case None => ()
            }
        }
        this.memWriteExtras[rec.id] = (closed.toArray(), conflicts.toArray())
    }

    // 结束一条事实：追加一个 provider 版本（旧版本保留当时的世界，valid_to 只落在新版本上）
    private func closeFactLocked(f: MemoryRecordRec, at: String, who: String): Unit {
        let prev = f.latest()
        let start = timeField(prev.timeJson, "valid_from") ?? ""
        let v = MemoryVersion(prev.version + 1, prev.titleJson, prev.contentJson, prev.attributesJson,
            prev.referencesJson, renderTime(Some(start), Some(at)), providerWriterJson(who),
            prev.searchText, prev.standing, prev.references, Some(0))
        f.versions.add(v)
        f.updatedAt = nowSeconds()
    }

    public func writeExtrasOf(rid: String): (Array<String>, Array<String>) {
        synchronized(this.lock) {
            return match (this.memWriteExtras.get(rid)) {
                case Some(v) => v
                case None => (Array<String>(), Array<String>())
            }
        }
    }

    // 实体图（Memories §6.6）：节点是记录，边是引用；按引用**无向**遍历 hops 跳
    public func memoryGraph(mid: String, aroundId: String, hops: Int64): String {
        synchronized(this.lock) {
            let _ = this.memoryLocked(mid)
            let _ = this.recordLocked(mid, aroundId)
            // 邻接表：引用是无向的，两边都要能走到
            let adj: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
            for ((rid, r) in this.memRecords) {
                if (r.memoryId != mid) {
                    continue
                }
                for ((_, to) in r.latest().references) {
                    this.addNeighbour(adj, rid, to)
                    this.addNeighbour(adj, to, rid)
                }
            }
            let visited = ArrayList<String>()
            visited.add(aroundId)
            var frontier = ArrayList<String>()
            frontier.add(aroundId)
            var hop: Int64 = 0
            while (hop < hops) {
                let next = ArrayList<String>()
                for (rid in frontier) {
                    match (adj.get(rid)) {
                        case Some(list) =>
                            for (other in list) {
                                if (!visited.contains(other)) {
                                    visited.add(other)
                                    next.add(other)
                                }
                            }
                        case None => ()
                    }
                }
                frontier = next
                hop = hop + 1
            }
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("object").writeValue("memory.graph")
            w.writeName("truncated").writeValue(false)
            w.writeName("nodes")
            w.startArray()
            for (rid in visited) {
                match (this.memRecords.get(rid)) {
                    case Some(r) =>
                        w.startObject()
                        w.writeName("record").jsonValue(memoryRecordJson(r))
                        w.writeName("memory")
                        w.startObject()
                        w.writeName("id").writeValue(r.memoryId)
                        w.endObject()
                        w.endObject()
                    case None => ()
                }
            }
            w.endArray()
            w.writeName("edges")
            w.startArray()
            for (rid in visited) {
                match (this.memRecords.get(rid)) {
                    case Some(r) =>
                        for ((rel, to) in r.latest().references) {
                            if (!visited.contains(to)) {
                                continue
                            }
                            w.startObject()
                            w.writeName("rel").writeValue(rel)
                            w.writeName("from")
                            w.startObject()
                            w.writeName("record_id").writeValue(rid)
                            w.endObject()
                            w.writeName("to")
                            w.startObject()
                            w.writeName("record_id").writeValue(to)
                            w.endObject()
                            w.writeName("available").writeValue(true)
                            w.endObject()
                        }
                    case None => ()
                }
            }
            w.endArray()
            w.endObject()
            w.flush()
            return String.fromUtf8(out.bytes())
        }
    }

    private func addNeighbour(adj: HashMap<String, ArrayList<String>>, from: String, to: String): Unit {
        let list = match (adj.get(from)) {
            case Some(l) => l
            case None =>
                let l = ArrayList<String>()
                adj[from] = l
                l
        }
        if (!list.contains(to)) {
            list.add(to)
        }
    }

    private func linkLocked(from: String, rel: String, to: String): Unit {
        let list = match (this.memLinks.get(from)) {
            case Some(l) => l
            case None =>
                let l = ArrayList<(String, String)>()
                this.memLinks[from] = l
                l
        }
        var seen = false
        for ((r0, t0) in list) {
            if (r0 == rel && t0 == to) {
                seen = true
                break
            }
        }
        if (!seen) {
            list.add((rel, to))
        }
    }

    private func recordLocked(mid: String, rid: String): MemoryRecordRec {
        let rec = match (this.memRecords.get(rid)) {
            case Some(r) => r
            case None => throw EngineError("not_found", UInt16(404))
        }
        if (rec.memoryId != mid) {
            // 一个记忆的记录不能从另一个记忆里查到（ME-06）
            throw EngineError("not_found", UInt16(404))
        }
        return rec
    }

    public func getMemoryRecord(mid: String, rid: String): MemoryRecordRec {
        synchronized(this.lock) {
            return this.recordLocked(mid, rid)
        }
    }

    public func listMemoryRecords(mid: String): Array<MemoryRecordRec> {
        synchronized(this.lock) {
            let _ = this.memoryLocked(mid)
            let out = ArrayList<MemoryRecordRec>()
            for ((_, r) in this.memRecords) {
                if (r.memoryId == mid && r.status == "active") {
                    out.add(r)
                }
            }
            // 新的在前（手写选择排序：ArrayList 没有 sort）
            let arr = out.toArray()
            var i = 0
            while (i < arr.size) {
                var best = i
                var j = i + 1
                while (j < arr.size) {
                    if (arr[j].updatedAt > arr[best].updatedAt) {
                        best = j
                    }
                    j = j + 1
                }
                if (best != i) {
                    let tmp = arr[i]
                    arr[i] = arr[best]
                    arr[best] = tmp
                }
                i = i + 1
            }
            return arr
        }
    }

    // 修订：追加版本，旧版本留在 history
    public func patchMemoryRecord(p: Principal, mid: String, rid: String, w: MemoryWrite): MemoryRecordRec {
        synchronized(this.lock) {
            let rec = this.recordLocked(mid, rid)
            let prev = rec.latest()
            let contentJson = match (w.contentJson) {
                case Some(_) => normalizeContent(w, FileStoreView(this.files))
                case None => prev.contentJson
            }
            let titleJson = match (w.title) {
                case Some(t) => Some(t)
                case None => prev.titleJson
            }
            let attributesJson = w.attributesJson ?? prev.attributesJson
            let referencesJson = w.referencesJson ?? prev.referencesJson
            let timeJson = w.timeJson ?? prev.timeJson
            let refs = refsOf(referencesJson)
            var searchText = contentSearchText(contentJson)
            match (titleJson) {
                case Some(t) => searchText = t + " " + searchText
                case None => ()
            }
            let writtenBy = memoryWriterJson(p.name)
            let v = MemoryVersion(prev.version + 1, titleJson, contentJson, attributesJson,
                referencesJson, timeJson, writtenBy, searchText, standingOf(attributesJson), refs, None)
            rec.versions.add(v)
            rec.updatedAt = nowSeconds()
            return rec
        }
    }

    public func forgetMemoryRecord(mid: String, rid: String): MemoryRecordRec {
        synchronized(this.lock) {
            let rec = this.recordLocked(mid, rid)
            rec.status = "forgotten"
            rec.updatedAt = nowSeconds()
            return rec
        }
    }

    public func eraseMemoryRecords(mid: String, ids: Array<String>): (Array<String>, Array<String>) {
        synchronized(this.lock) {
            let _ = this.memoryLocked(mid)
            let erased = ArrayList<String>()
            let unreachable = ArrayList<String>()
            for (rid in ids) {
                match (this.memRecords.get(rid)) {
                    case Some(r) => if (r.memoryId == mid) {
                        this.memRecords.remove(rid)
                        this.memLinks.remove(rid)
                        erased.add(rid)
                    } else {
                        unreachable.add(rid)
                    }
                    case None => unreachable.add(rid)
                }
            }
            return (erased.toArray(), unreachable.toArray())
        }
    }

    public func memoryLinksOf(rid: String): Array<(String, String)> {
        synchronized(this.lock) {
            return match (this.memLinks.get(rid)) {
                case Some(l) => l.toArray()
                case None => Array<(String, String)>()
            }
        }
    }

    // ---------- 召回 / prime ----------

    public func recallMemory(mid: String, queryText: String, useQuery: Bool, useFilters: Bool,
                             depth: Int64, limit: Int64): String {
        synchronized(this.lock) {
            let memory = this.memoryLocked(mid)
            let scope = if (depth == 0) {
                [mid]
            } else {
                this.memoryDescendants(mid)
            }
            let hits = ArrayList<(String, Int64, Int64)>()   // recordId, score, updatedAt
            for ((rid, r) in this.memRecords) {
                if (r.status != "active") {
                    continue
                }
                if (!scope.contains(r.memoryId)) {
                    continue
                }
                let v = r.latest()
                let matched = matchCount(v.searchText, queryText)
                if (matched > 0) {
                    hits.add((rid, matched, r.updatedAt))
                }
            }
            // 手写选择排序：score 高的在前，其次新的在前
            let harr = hits.toArray()
            var hi = 0
            while (hi < harr.size) {
                var best = hi
                var hj = hi + 1
                while (hj < harr.size) {
                    var better = harr[hj][1] > harr[best][1]
                    if (harr[hj][1] == harr[best][1]) {
                        better = harr[hj][2] > harr[best][2]
                    }
                    if (better) {
                        best = hj
                    }
                    hj = hj + 1
                }
                if (best != hi) {
                    let tmp = harr[hi]
                    harr[hi] = harr[best]
                    harr[best] = tmp
                }
                hi = hi + 1
            }
            let results = ArrayList<String>()
            let chosen = ArrayList<String>()
            var taken: Int64 = 0
            for ((rid, score, _) in harr) {
                if (taken >= limit) {
                    break
                }
                chosen.add(rid)
                taken = taken + 1
                results.add(recallEntryJson(rid, this.memRecords[rid], Some(score), Array<String>()))
            }
            // 分歧的另一边随命中一起带到（why=["contradicts"]，无 score）
            for (rid in chosen.toArray()) {
                for ((rel, other) in this.memoryLinksOf(rid)) {
                    if (rel != "contradicts" || chosen.contains(other)) {
                        continue
                    }
                    match (this.memRecords.get(other)) {
                        case Some(or) => if (or.status == "active" && scope.contains(or.memoryId)) {
                            chosen.add(other)
                            results.add(recallEntryJson(other, or, None, ["contradicts"]))
                        }
                        case None => ()
                    }
                }
            }
            return recallJson(memory, results.toArray(), scope, useFilters)
        }
    }

    private func matchCount(text: String, queryText: String): Int64 {
        if (queryText.size == 0) {
            return 0
        }
        var n: Int64 = 0
        for (term in queryText.split(" ")) {
            let t = term.trimAscii()
            if (t.size >= 3 && text.toAsciiLower().contains(t.toAsciiLower())) {
                n = n + 1
            }
        }
        return n
    }

    private func recallEntryJson(rid: String, rec: MemoryRecordRec, score: Option<Int64>,
                                 why: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("record").jsonValue(memoryRecordJson(rec))
        w.writeName("memory")
        w.startObject()
        w.writeName("id").writeValue(rec.memoryId)
        w.endObject()
        match (score) {
            case Some(s) => w.writeName("score").writeValue(s)
            case None => w.writeName("score").writeNullValue()
        }
        if (why.size > 0) {
            w.writeName("why")
            w.startArray()
            for (x in why) {
                w.writeValue(x)
            }
            w.endArray()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(out.bytes())
    }

    private func recallJson(memory: MemoryNodeRec, results: Array<String>, scope: Array<String>,
                            useFilters: Bool): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("object").writeValue("memory.recall")
        match (memory.parentId) {
            case Some(pid) =>
                w.writeName("parent")
                w.startObject()
                w.writeName("id").writeValue(pid)
                w.endObject()
            case None => ()
        }
        w.writeName("children")
        w.startArray()
        for ((_, m) in this.memories) {
            match (m.parentId) {
                case Some(pid) => if (pid == memory.id && scope.contains(m.id)) {
                    w.startObject()
                    w.writeName("id").writeValue(m.id)
                    match (m.description) {
                        case Some(d) => w.writeName("description").writeValue(d)
                        case None => ()
                    }
                    w.endObject()
                }
                case None => ()
            }
        }
        w.endArray()
        w.writeName("results")
        w.startArray()
        for (r in results) {
            w.jsonValue(r)
        }
        w.endArray()
        w.writeName("degraded")
        w.startArray()
        if (useFilters) {
            w.writeValue("filters:not_supported")
        }
        w.endArray()
        w.writeName("abstain").writeValue(results.size == 0)
        w.endObject()
        w.flush()
        return String.fromUtf8(out.bytes())
    }

    public func primeMemory(mid: String, budget: Int64): String {
        synchronized(this.lock) {
            let _ = this.memoryLocked(mid)
            let standing = ArrayList<MemoryRecordRec>()
            for ((_, r) in this.memRecords) {
                if (r.memoryId == mid && r.status == "active" && r.latest().standing) {
                    standing.add(r)
                }
            }
            let sarr = standing.toArray()
            var si = 0
            while (si < sarr.size) {
                var best = si
                var sj = si + 1
                while (sj < sarr.size) {
                    if (sarr[sj].updatedAt > sarr[best].updatedAt) {
                        best = sj
                    }
                    sj = sj + 1
                }
                if (best != si) {
                    let tmp = sarr[si]
                    sarr[si] = sarr[best]
                    sarr[best] = tmp
                }
                si = si + 1
            }
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("object").writeValue("memory.prime")
            w.writeName("records")
            w.startArray()
            var tokens: Int64 = 0
            var included: Int64 = 0
            for (r in sarr) {
                // 一条 standing 记录按 1 个 token 计；预算为 1 时仍保留最新一条
                if (tokens >= budget && included > 0) {
                    break
                }
                w.jsonValue(memoryRecordJson(r))
                tokens = tokens + 1
                included = included + 1
            }
            w.endArray()
            w.writeName("tokens").writeValue(tokens)
            w.writeName("truncated").writeValue(included < Int64(sarr.size))
            w.endObject()
            w.flush()
            return String.fromUtf8(out.bytes())
        }
    }

    // ---------- 环境（Environments） ----------

    public func createEnvironment(p: Principal, name: String, description: Option<String>,
                                  entry: Option<String>): EnvRecord {
        synchronized(this.lock) {
            let id = "henv_" + this.idSource.session().replace("hsess", "")
            var slug = envSlug(name)
            if (slug.size == 0) {
                slug = "env"
            }
            let mount = this.envBase + "/" + slug
            let rec = EnvRecord(id, name, slug, description, entry, mount)
            this.envs[id] = rec
            return rec
        }
    }

    // 包检查：没有注入查询接缝就不提供该端点（规范里它是可选的）
    public func checkEnvironmentPackage(manager: String, spec: String): String {
        match (this.packageChecker) {
            case Some(check) => match (check(manager, spec)) {
                case Some(r) => return envPackageCheckJson(manager, spec, r.exists, r.latest)
                case None => throw EngineError("environment_invalid", UInt16(400), param: Some("manager"))
            }
            case None => throw EngineError("not_found", UInt16(404))
        }
    }

    public func getEnvironment(id: String): EnvRecord {
        synchronized(this.lock) {
            return match (this.envs.get(id)) {
                case Some(e) => e
                case None => throw EngineError("environment_not_found", UInt16(404))
            }
        }
    }

    public func listEnvironments(): Array<EnvRecord> {
        synchronized(this.lock) {
            let out = ArrayList<EnvRecord>()
            for ((_, e) in this.envs) {
                out.add(e)
            }
            return out.toArray()
        }
    }

    public func deleteEnvironment(id: String): Unit {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            this.envs.remove(id)
            try {
                removeIfExists(e.mount, recursive: true)
            } catch (ex: Exception) {
                eprintln("uhp: environment dir removal failed: " + ex.toString())
            }
        }
    }

    public func putEnvFile(id: String, path: String, bytes: Array<UInt8>): Unit {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            checkEnvPath(path)
            if (e.active.isSome()) {
                setEnvWritable(e, true)
            }
            e.files[path] = bytes
            // 真实落盘：driver 要像 agent 一样在 mount 下读
            try {
                let full = e.mount + "/" + path
                let segs = path.split("/")
                var dir = e.mount
                if (!exists(dir)) {
                    Directory.create(dir, recursive: true)
                }
                var i = 0
                while (i < segs.size - 1) {
                    dir = dir + "/" + segs[i]
                    if (!exists(dir)) {
                        Directory.create(dir, recursive: true)
                    }
                    i = i + 1
                }
                FsFile.writeTo(full, bytes)
            } catch (ex: Exception) {
                eprintln("uhp: environment file write failed: " + ex.toString())
            }
            if (e.active.isSome()) {
                setEnvWritable(e, false)
            }
        }
    }

    public func getEnvFile(id: String, path: String): Array<UInt8> {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            checkEnvPath(path)
            return match (e.files.get(path)) {
                case Some(b) => b
                case None => throw EngineError("not_found", UInt16(404))
            }
        }
    }

    // 删文件或整棵目录（套件会删 "probe" 这棵子树）
    public func deleteEnvPath(id: String, path: String): Unit {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            checkEnvPath(path)
            if (e.active.isSome()) {
                setEnvWritable(e, true)
            }
            let gone = ArrayList<String>()
            for ((p, _) in e.files) {
                if (p == path || p.startsWith(path + "/")) {
                    gone.add(p)
                }
            }
            for (p in gone) {
                e.files.remove(p)
            }
            try {
                removeIfExists(e.mount + "/" + path, recursive: true)
            } catch (ex: Exception) {
                eprintln("uhp: environment delete failed: " + ex.toString())
            }
            if (e.active.isSome()) {
                setEnvWritable(e, false)
            }
        }
    }

    public func buildEnvironment(id: String): Int64 {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            let version = e.latestVersion + 1
            let b = EnvBuild(version)
            // 快照：之后改源文件不影响已 build 的版本
            let snap = HashMap<String, Array<UInt8>>()
            var bytes: Int64 = 0
            for ((path, content) in e.files) {
                snap[path] = content
                bytes = bytes + Int64(content.size)
            }
            b.files = Int64(e.files.size)
            b.bytes = bytes
            b.finishedAt = nowSeconds()
            e.builds[version] = b
            e.versions[version] = snap
            e.latestVersion = version
            e.active = Some(version)
            e.status = "ready"
            // build 把这一版真正铺到 mount 上（回滚时再换回来）
            materializeEnv(e, snap)
            return version
        }
    }

    public func envBuild(id: String, version: Int64): EnvBuild {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            return match (e.builds.get(version)) {
                case Some(b) => b
                case None => throw EngineError("not_found", UInt16(404))
            }
        }
    }

    public func activateEnvVersion(id: String, version: Int64): Int64 {
        synchronized(this.lock) {
            let e = this.getEnvironment(id)
            if (!e.builds.contains(version)) {
                throw EngineError("environment_not_ready", UInt16(409))
            }
            e.active = Some(version)
            match (e.versions.get(version)) {
                case Some(files) => materializeEnv(e, files)
                case None => ()
            }
            return version
        }
    }

    // 哪些 harness 指向这个环境（EN-06）
    public func envHarnesses(id: String): Array<String> {
        synchronized(this.lock) {
            let out = ArrayList<String>()
            for ((hid, rec) in this.harnessRecords) {
                match (rec.environment) {
                    case Some(eid) => if (eid == id) {
                        out.add(hid)
                    }
                    case None => ()
                }
            }
            return out.toArray()
        }
    }

    // ---------- harness 管理（Full） ----------

    public func supportedBaseList(): Array<String> {
        return this.supportedBases
    }

    public func createHarness(p: Principal, body: String, idemKey: Option<String>): HarnessRecord {
        synchronized(this.lock) {
            // 幂等键：同 key 返回第一次创建的那个 harness（F-10）
            match (idemKey) {
                case Some(k) => match (this.idemKeys.get(k)) {
                    case Some(existing) =>
                        // 同一 key 携带不同请求 -> 409（规范 §5.1：不能拿第一次的答案应付另一次请求）
                        let prevBody = this.idemBodies.get(k) ?? ""
                        if (prevBody != body) {
                            throw EngineError("idempotency_key_reused", UInt16(409))
                        }
                        // key 指向的 harness 已被删除：按第一次的语义新建（规范 §5.1）
                        match (this.harnessRecords.get(existing)) {
                            case Some(rec) => return rec
                            case None => ()
                        }
                    case None => ()
                }
                case None => ()
            }
            let id = "chrn_" + this.idSource.harness().replace("chrn_", "")
            let rec = parseHarnessCreate(JsonReader(ByteBuffer(body.toArray())), id)
            if (rec.base.size == 0) {
                throw EngineError("invalid_input", UInt16(422), param: Some("base"))
            }
            if (!this.supportedBases.contains(rec.base)) {
                throw EngineError("unsupported_base", UInt16(422), param: Some("base"),
                    reason: Some(quoteJoin(this.supportedBases)))
            }
            if (rec.name.size == 0) {
                // 对象 required 含 name，写体不强制：合成一个稳定名字
                rec.name = rec.base + " harness"
            }
            rec.plugins = resolvePlugins(rec.pluginInputs, [])
            checkComposition(directServerNames(rec), directSkillNames(rec), rec.plugins)
            match (rec.environment) {
                case Some(eid) =>
                    if (!this.envs.contains(eid)) {
                        throw EngineError("environment_not_found", UInt16(404), param: Some("environment"))
                    }
                case None => ()
            }
            this.harnessRecords[id] = rec
            this.harnesses[id] = ConfiguredHarness(id, rec.name, rec.base,
                match (rec.defaultModel) { case Some(m) => m; case None => "scripted-model" },
                match (this.factory) {
                    case Some(f) => f(rec.base)
                    case None => match (this.harnesses.get(this.defaultHarness)) {
                        case Some(h) => h.driver
                        case None => throw EngineError("unsupported_base", UInt16(422))
                    }
                })
            match (idemKey) {
                case Some(k) =>
                    this.idemKeys[k] = id
                    this.idemBodies[k] = body
                case None => ()
            }
            return rec
        }
    }

    public func updateHarness(p: Principal, id: String, body: String): HarnessRecord {
        synchronized(this.lock) {
            let old = match (this.harnessRecords.get(id)) {
                case Some(r) => r
                case None => throw EngineError("harness_not_found", UInt16(404))
            }
            let parsed = parseHarnessCreate(JsonReader(ByteBuffer(body.toArray())), id)
            // base 不可改：PUT 是整替换但 base 仍然 REQUIRED，且必须与现值一致
            if (parsed.base != old.base) {
                throw EngineError("invalid_input", UInt16(422), param: Some("base"))
            }
            old.name = if (parsed.name.size == 0) { old.name } else { parsed.name }
            old.defaultModel = parsed.defaultModel
            old.systemPrompt = parsed.systemPrompt
            old.mcpServersJson = parsed.mcpServersJson
            old.skills = parsed.skills
            old.disabledTools = parsed.disabledTools
            old.maxStep = parsed.maxStep
            old.timeoutSeconds = parsed.timeoutSeconds
            // 「不带 files 的插件条目」= 沿用已装包（PUT 往返/禁用），所以要把旧集合传进去
            old.plugins = resolvePlugins(parsed.pluginInputs, old.plugins)
            checkComposition(directServerNames(old), directSkillNames(old), old.plugins)
            match (parsed.environment) {
                case Some(eid) =>
                    if (!this.envs.contains(eid)) {
                        throw EngineError("environment_not_found", UInt16(404), param: Some("environment"))
                    }
                    old.environment = Some(eid)
                case None => old.environment = None
            }
            match (this.harnesses.get(id)) {
                case Some(h) =>
                    this.harnesses[id] = ConfiguredHarness(id, old.name, old.base,
                        match (old.defaultModel) { case Some(m) => m; case None => h.defaultModel },
                        h.driver)
                case None => ()
            }
            return old
        }
    }

    // 删除 harness：本服务端报 harness_retirement=false，所以**保留**它的会话（F-09）。
    public func deleteHarness(p: Principal, id: String): String {
        synchronized(this.lock) {
            if (!this.harnessRecords.contains(id)) {
                throw EngineError("harness_not_found", UInt16(404))
            }
            this.harnessRecords.remove(id)
            this.harnesses.remove(id)
            return "{\"id\":\"" + id + "\",\"deleted\":true,\"sessions\":\"kept\"}"
        }
    }

    public func harnessRecord(id: String): HarnessRecord {
        synchronized(this.lock) {
            return match (this.harnessRecords.get(id)) {
                case Some(r) => r
                case None => throw EngineError("harness_not_found", UInt16(404))
            }
        }
    }

    public func harnessRecordList(): Array<HarnessRecord> {
        synchronized(this.lock) {
            let out = ArrayList<HarnessRecord>()
            for ((_, r) in this.harnessRecords) {
                out.add(r)
            }
            return out.toArray()
        }
    }

    public func pluginFiles(id: String, pluginName: String): PluginRecord {
        synchronized(this.lock) {
            let rec = this.harnessRecord(id)
            for (p in rec.plugins) {
                if (p.name == pluginName) {
                    return p
                }
            }
            throw EngineError("plugin_not_found", UInt16(404))
        }
    }

    public func exportPlugin(id: String): String {
        synchronized(this.lock) {
            return exportPluginJson(this.harnessRecord(id))
        }
    }

    public func skillFiles(id: String, skillName: String): SkillRecord {
        synchronized(this.lock) {
            let rec = this.harnessRecord(id)
            return match (rec.skill(skillName)) {
                case Some(s) => s
                case None => throw EngineError("file_not_found", UInt16(404))
            }
        }
    }

    // ---------- 会话分享（Full，Sessions §5） ----------

    // 发布：每次 POST 生成一条新链接；吊销按会话进行（R-06 要求所有链接一起失效）
    public func publishShare(p: Principal, sessionId: String): ShareRecord {
        synchronized(this.lock) {
            let rec = this.recordLocked(p, sessionId)
            let share = ShareRecord(this.idSource.share(), this.idSource.shareToken(),
                sessionId, p.name)
            this.shares[share.token] = share
            return share
        }
    }

    public func getShare(p: Principal, sessionId: String): ShareRecord {
        synchronized(this.lock) {
            let _ = this.recordLocked(p, sessionId)
            for ((_, share) in this.shares) {
                if (share.sessionId == sessionId && !share.revoked && share.owner == p.name) {
                    return share
                }
            }
            throw EngineError("session_share_not_found", UInt16(404))
        }
    }

    // 吊销：返回被吊销的链接数（0 也回 200 —— 让重试幂等）
    public func revokeShares(p: Principal, sessionId: String): Int64 {
        synchronized(this.lock) {
            let _ = this.recordLocked(p, sessionId)
            var n = 0
            for ((_, share) in this.shares) {
                if (share.sessionId == sessionId && share.owner == p.name && !share.revoked) {
                    share.revoked = true
                    n = n + 1
                }
            }
            return n
        }
    }

    // 共享视图：**无鉴权**（这就是分享的意义），但只读、只含对话内容、不含任何配置。
    public func sharedView(token: String): String {
        synchronized(this.lock) {
            let share = match (this.shares.get(token)) {
                case Some(s) => s
                case None => throw EngineError("session_share_not_found", UInt16(404))
            }
            if (share.revoked) {
                throw EngineError("session_share_not_found", UInt16(404))
            }
            let rec = match (this.records.get(share.sessionId)) {
                case Some(r) => r
                case None => throw EngineError("session_share_not_found", UInt16(404))
            }
            let turns = ArrayList<TurnItem>()
            for (rid in rec.responseIds) {
                match (this.stored.get(rid)) {
                    case Some(s) =>
                        let t = TurnItem()
                        t.id = rid
                        t.status = s.response.status
                        t.created_at = Some(s.response.created_at)
                        turns.add(t)
                    case None => ()
                }
            }
            return sharedViewJson(rec, turns.toArray(), this.responseTexts)
        }
    }

    // 删除会话：会话、响应、产物一并不可达（Sessions §6）
    public func deleteSession(p: Principal, sessionId: String): Unit {
        synchronized(this.lock) {
            let rec = this.recordLocked(p, sessionId)
            for (rid in rec.responseIds) {
                this.stored.remove(rid)
            }
            let toRemove = ArrayList<String>()
            for ((fid, f) in this.files) {
                if (f.sessionId == sessionId) {
                    toRemove.add(fid)
                }
            }
            for (fid in toRemove) {
                this.files.remove(fid)
            }
            for ((_, share) in this.shares) {
                if (share.sessionId == sessionId) {
                    share.revoked = true
                }
            }
            this.records.remove(sessionId)
            this.sessions.remove(sessionId)
            this.sessionOwners.remove(sessionId)
        }
    }

    // ---------- 会话（Extended） ----------

    public func listSessions(p: Principal, limit: Int64, cursor: Option<String>): (Array<Session>, Option<String>) {
        synchronized(this.lock) {
            let all = ArrayList<Session>()
            for ((_, rec) in this.records) {
                if (rec.owner == p.name) {
                    all.add(toSession(rec))
                }
            }
            // 简单游标：偏移量编码成不透明串；下一页为空时 next_cursor 为 None（规范要求显式报末页）
            let offset = match (cursor) {
                case Some(c) => Int64.parse(c)
                case None => 0
            }
            let out = ArrayList<Session>()
            var i = offset
            while (i < all.size && out.size < limit) {
                out.add(all[i])
                i = i + 1
            }
            let next: Option<String> = if (i < all.size) { Some(i.toString()) } else { None }
            return (out.toArray(), next)
        }
    }

    public func getSession(p: Principal, sessionId: String): Session {
        synchronized(this.lock) {
            return toSession(this.recordLocked(p, sessionId))
        }
    }

    public func sessionTurns(p: Principal, sessionId: String): Array<TurnItem> {
        synchronized(this.lock) {
            let rec = this.recordLocked(p, sessionId)
            let out = ArrayList<TurnItem>()
            for (rid in rec.responseIds) {
                match (this.stored.get(rid)) {
                    case Some(s) =>
                        let t = TurnItem()
                        t.id = rid
                        t.status = s.response.status
                        t.created_at = Some(s.response.created_at)
                        out.add(t)
                    case None => ()
                }
            }
            return out.toArray()
        }
    }

    // ---------- 文件（Extended） ----------

    public func uploadFile(p: Principal, filename: String, content: Array<UInt8>): File {
        synchronized(this.lock) {
            let fid = this.idSource.file()
            // 上传的文件先挂在 principal 专属的「收件箱」容器里；被任务引用时不复制字节。
            let container = "cntr_upload_" + p.name
            this.files[fid] = StoredFile(fid, container, "", p.name, filename, content)
            return toFile(this.files[fid])
        }
    }

    public func sessionFiles(p: Principal, sessionId: String): Array<File> {
        synchronized(this.lock) {
            let rec = this.recordLocked(p, sessionId)
            let out = ArrayList<File>()
            for ((_, f) in this.files) {
                if (f.sessionId == sessionId && f.containerId == rec.containerId) {
                    out.add(toFile(f))
                }
            }
            return out.toArray()
        }
    }

    // 下载：container/file 必须匹配，否则 404（路径穿越探针因此自然失败）
    public func downloadFile(p: Principal, containerId: String, fileId: String): StoredFile {
        synchronized(this.lock) {
            let f = match (this.files.get(fileId)) {
                case Some(v) => v
                case None => throw EngineError("file_not_found", UInt16(404))
            }
            if (f.owner != p.name || f.containerId != containerId) {
                // 跨 principal 与跨容器一律 404，不透露存在性
                throw EngineError("file_not_found", UInt16(404))
            }
            return f
        }
    }

    private func recordLocked(p: Principal, sessionId: String): SessionRecord {
        return match (this.records.get(sessionId)) {
            case Some(r) => if (r.owner == p.name) { r } else { throw EngineError("session_not_found", UInt16(404)) }
            case None => throw EngineError("session_not_found", UInt16(404))
        }
    }

    private func toSession(rec: SessionRecord): Session {
        let s = Session()
        s.id = rec.id
        s.objectKind = Some("session")
        s.harness_id = rec.harnessId
        s.environment = rec.environment
        s.title = rec.title
        s.status = "completed"
        s.created_at = rec.createdAt
        s.updated_at = rec.updatedAt
        return s
    }

    private func toFile(f: StoredFile): File {
        let out = File()
        out.id = f.id
        out.objectKind = Some("file")
        out.filename = f.filename
        out.bytes = Some(f.bytes.size)
        out.created_at = Some(f.createdAt)
        out.extras["container_id"] = "\"" + f.containerId + "\""
        return out
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

    private let artifacts: ArrayList<(String, Array<UInt8>)> = ArrayList<(String, Array<UInt8>)>()

    // 待回答的问题：engine 在任务结束后把它们落成 items 与 incomplete 状态
    private let pending: ArrayList<PendingInputRequest> = ArrayList<PendingInputRequest>()

    private let calls: ArrayList<(String, String, String)> = ArrayList<(String, String, String)>()
    private let results: ArrayList<(String, String)> = ArrayList<(String, String)>()

    public func toolCall(name: String, arguments: String): String {
        let callId = "call_" + this.ids.response()
        this.calls.add((callId, name, arguments))
        return callId
    }

    public func toolResult(callId: String, output: String): Unit {
        this.results.add((callId, output))
    }

    // 一轮 step = 调用 + 结果（套件按配对计数，未回答的调用不算）
    public func rounds(): Int64 {
        var n: Int64 = 0
        for ((cid, _) in this.results) {
            for ((callId, _, _) in this.calls) {
                if (callId == cid) {
                    n = n + 1
                    break
                }
            }
        }
        return n
    }

    public func toolCalls(): Array<(String, String, String)> {
        return this.calls.toArray()
    }

    public func toolResults(): Array<(String, String)> {
        return this.results.toArray()
    }

    public func ask(kind: String, prompt: String, options: Array<(String, String)>): String {
        let id = this.ids.inputRequest()
        this.pending.add(PendingInputRequest(id, "", kind, prompt, options))
        return id
    }

    public func pendingRequests(): Array<PendingInputRequest> {
        return this.pending.toArray()
    }

    public func collectedText(): String {
        let out = StringBuilder()
        for (t in this.texts) {
            out.append(t)
        }
        return out.toString()
    }

    public func producedFile(filename: String, content: Array<UInt8>): Unit {
        this.artifacts.add((filename, content))
    }

    public func producedFiles(): Array<(String, Array<UInt8>)> {
        return this.artifacts.toArray()
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

// 会话标题：取输入首行、截断到 60 个字符（按 rune 切，避免切坏 UTF-8）
func titleOf(input: String): String {
    let runes = input.toRuneArray()
    let limit = if (runes.size > 60) { 60 } else { runes.size }
    let head = String(runes[0..limit])
    // 标题是单行展示：把换行换成空格
    return head.replace("\n", " ")
}

// 环境目录：<cwd>/.uhp-envs（mount 必须是绝对路径；放在进程工作目录下，容器与 CI 都可写）
func envBaseDir(): String {
    return canonicalize(".").toString() + "/.uhp-envs"
}

// 环境内路径：不许绝对、不许 ..（URL 里百分号编码的 ..%2F 也含 ".."，一并拒）
func checkEnvPath(path: String): Unit {
    if (path.size == 0 || path.startsWith("/") || path.contains("..")) {
        throw EngineError("environment_invalid", UInt16(400), param: Some("path"))
    }
    for (seg in path.split("/")) {
        if (seg.size == 0 || seg == ".") {
            throw EngineError("environment_invalid", UInt16(400), param: Some("path"))
        }
    }
}

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
