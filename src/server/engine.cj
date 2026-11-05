// 服务端引擎：把「协议语义」和「HTTP 传输」隔开。
//
// 引擎负责：harness 注册、任务执行（driver -> 事件通道 -> Response 对象）、会话并发控制、
// 对象 scope（跨 principal 一律当作不存在）。HTTP 层只做请求解析、鉴权与错误封套。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.convert.*
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

    public init(input: String, model!: Option<String> = None, harnessId!: Option<String> = None,
                previousResponseId!: Option<String> = None, background!: Bool = false,
                ignoredFields!: Array<String> = []) {
        this.input = input
        this.model = model
        this.harnessId = harnessId
        this.previousResponseId = previousResponseId
        this.background = background
        this.ignoredFields = ignoredFields
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
    private let versions: Array<String>
    private let cls: ConformanceClass
    private let capabilitiesValue: Capabilities

    public init(harnesses: Array<ConfiguredHarness>, versions!: Array<String> = ["2026-10-19"],
                cls!: ConformanceClass = ConformanceClass.Core,
                driverFactory!: Option<(String) -> HarnessDriver> = None,
                supportedBases!: Option<Array<String>> = None) {
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
                let containerId = this.idSource.container()
                this.records[sessionId] = SessionRecord(sessionId, harnessId, p.name, containerId,
                    titleOf(req.input))
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
        if (req.ignoredFields.size > 0) {
            // 规范：服务端忽略请求字段时必须点名（tools/include 是保留字段）
            meta.ignored_fields = Some(req.ignoredFields)
        }
        resp.metadata = Some(meta)
        match (previous) {
            case Some(prev) => resp.previous_response_id = Some("\"" + prev.id + "\"")
            case None => ()
        }

        // 事件 0：response.created（规范：created 必须是流的第一个事件）
        channel.emit("response.created", eventWithResponse("response.created", 0, resp))
        this.stored[responseId] = StoredResponse(p.name, resp, channel)
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
            this.executeTask(harness, req, sessionId, resp, channel, sink)
        }
        return TaskResult(resp, channel)
    }

    private func executeTask(harness: ConfiguredHarness, req: TaskRequest, sessionId: String,
                             resp: Response, channel: EventChannel, sink: EngineSink): Unit {
        let outcome = try {
            harness.driver.run(TurnContext(sessionId, req.input, resp.model), sink, CancelToken())
        } catch (e: Exception) {
            // driver 抛异常 = failed(harness_error)，绝不允许吞成 completed
            TurnOutcome.Failed("harness_error", "harness failed")
        }
        synchronized(this.lock) {
            let finalStatus = this.applyOutcome(resp, outcome, sink)
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
