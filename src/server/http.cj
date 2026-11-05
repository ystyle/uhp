// HTTP 层：路由、鉴权、版本协商、错误封套、SSE 输出。
//
// 分层原则：这一层只做「协议面」的事——解析请求、认人、认版本、把引擎错误翻成错误封套；
// 业务语义（任务状态机、事件、scope）全在 Engine 里，HTTP 层不许再判断一次。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.io.*
import stdx.encoding.json.stream.*
import stdx.net.http.*
import uhp.types.codec.*
import uhp.types.generated.*
import uhp.types.handwritten.*

// token -> principal 名。签发 token 不在协议范围内（Architecture §5），由宿主决定。
public class Authenticator {
    private let tokens: HashMap<String, String>

    public init(tokens: HashMap<String, String>) {
        this.tokens = tokens
    }

    // None = 未通过（401）。区分「没带」与「带了但无效」由调用方决定要不要分码。
    public func authenticate(headers: HttpHeaders): Option<Principal> {
        let raw = match (headers.getFirst("Authorization")) {
            case Some(v) => v
            case None => return None
        }
        let v = raw.trimAscii()
        if (!v.startsWith("Bearer ")) {
            return None
        }
        let token = v[7..v.size].trimAscii()
        return match (this.tokens.get(token)) {
            case Some(name) => Some(Principal(name))
            case None => None
        }
    }
}

public class UhpHttpServer {
    private let engine: Engine
    private let auth: Authenticator
    private let versions: Array<String>
    private let defaultVersion: String

    public init(engine: Engine, auth: Authenticator, versions!: Array<String> = ["2026-10-19"]) {
        this.engine = engine
        this.auth = auth
        this.versions = versions
        this.defaultVersion = versions[0]
    }

    public func distributor(): HttpRequestDistributor {
        return UhpDistributor(this)
    }

    public func dispatch(ctx: HttpContext): Unit {
        try {
            this.route(ctx)
        } catch (e: EngineError) {
            let fromError = match (e.detailJson) {
                case Some(d) => d
                case None => ""
            }
            let detail = if (fromError.size > 0) { fromError } else { match (e.code) {
                case "unsupported_base" => match (e.reason) {
                    case Some(r) => "{\"supported\":[" + r + "]}"
                    case None => ""
                }
                case _ => ""
            } }
            this.writeErrorDetail(ctx, e.httpStatus, e.code, e.param, detail)
        } catch (e: JsonProtocolException) {
            this.writeError(ctx, UInt16(400), "invalid_input", None)
        } catch (e: Exception) {
            // 不把内部异常文本泄漏给调用方（错误封套的 message 必须安全可展示），
            // 但要写到 stderr 供运维定位——规范要求「扣下的 detail 要记日志」。
            eprintln("uhp: internal error: " + e.toString())
            this.writeError(ctx, UInt16(500), "server_error", None)
        }
    }

    private func route(ctx: HttpContext): Unit {
        let method = ctx.request.method
        let path = ctx.request.url.path

        // 版本协商先于一切（含 discovery）：不认识的版本必须明确失败并列出支持版本，
        // 绝不静默换版本。discovery 请求同样如此（套件 V-03 就是打 /v1/uhp 且不带鉴权）。
        let usedVersion = match (this.negotiate(ctx)) {
            case Some(v) => v
            case None =>
                this.writeErrorDetail(ctx, UInt16(400), "unsupported_protocol_version", None,
                    "{\"supported\":[" + quoteJoin(this.versions) + "]}")
                return
        }

        // discovery 免鉴权：客户端要先知道对面是不是 UHP 服务端，才谈得上给凭证
        if (method == "GET" && path == "/v1/uhp") {
            this.writeJson(ctx, UInt16(200), jsonOf(this.engine.discovery()), version: Some(usedVersion))
            return
        }

        // 共享视图免鉴权：持有链接就能读，这正是 SessionShare 的定义。
        // 但只允许 GET；其它方法落到下面同一张路由表上，因而不会命中任何写路径（R-04）。
        if (path.startsWith("/v1/shared/") && method == "GET") {
            let token = path["/v1/shared/".size..path.size]
            this.writeJson(ctx, UInt16(200), this.engine.sharedView(token), version: Some(usedVersion))
            return
        }

        let principal = match (this.auth.authenticate(ctx.request.headers)) {
            case Some(p) => p
            case None =>
                let code = if (ctx.request.headers.getFirst("Authorization").isNone()) {
                    "missing_credential"
                } else {
                    "invalid_credential"
                }
                this.writeError(ctx, UInt16(401), code, None)
                return
        }

        let seg = splitPath(path)
        if (method == "GET" && path == "/v1/harnesses") {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("harnesses")
            w.startArray()
            for (rec in this.engine.harnessRecordList()) {
                w.jsonValue(harnessJson(rec, rec.base))
            }
            w.endArray()
            w.endObject()
            w.flush()
            this.writeJson(ctx, UInt16(200), String.fromUtf8(out.bytes()), version: Some(usedVersion))
            return
        }
        // harness 管理（Full）：create / update / delete
        if (path == "/v1/harnesses" && method == "POST") {
            let body = readAllText(ctx.request.body)
            let idem = ctx.request.headers.getFirst("Idempotency-Key")
            let rec = this.engine.createHarness(principal, body, idem)
            this.writeJson(ctx, UInt16(200), harnessJson(rec, rec.base), version: Some(usedVersion))
            return
        }
        if (method == "GET" && path == "/v1/models") {
            // 全局模型目录：M2 只给空目录，单 harness 模型走下方端点
            this.writeJson(ctx, UInt16(200), "{\"backends\":{}}", version: Some(usedVersion))
            return
        }
        if (method == "POST" && path == "/v1/responses") {
            this.handleCreateResponse(ctx, principal, usedVersion)
            return
        }
        if (seg.size >= 3 && seg[0] == "v1" && seg[1] == "harnesses") {
            let id = seg[2]
            if (seg.size == 3 && method == "GET") {
                let rec = this.engine.harnessRecord(id)
                this.writeJson(ctx, UInt16(200), harnessJson(rec, rec.base), version: Some(usedVersion))
                return
            }
            if (seg.size == 3 && method == "PUT") {
                let body = readAllText(ctx.request.body)
                let rec = this.engine.updateHarness(principal, id, body)
                this.writeJson(ctx, UInt16(200), harnessJson(rec, rec.base), version: Some(usedVersion))
                return
            }
            if (seg.size == 3 && method == "DELETE") {
                this.writeJson(ctx, UInt16(200), this.engine.deleteHarness(principal, id),
                    version: Some(usedVersion))
                return
            }
            if (seg.size == 4 && seg[3] == "plugin" && method == "GET") {
                this.writeJson(ctx, UInt16(200), this.engine.exportPlugin(id), version: Some(usedVersion))
                return
            }
            if (seg.size == 6 && seg[3] == "plugins" && seg[5] == "files" && method == "GET") {
                let pl = this.engine.pluginFiles(id, seg[4])
                this.writeJson(ctx, UInt16(200), pluginFilesJson(pl), version: Some(usedVersion))
                return
            }
            if (seg.size == 6 && seg[3] == "skills" && seg[5] == "files" && method == "GET") {
                let skill = this.engine.skillFiles(id, seg[4])
                this.writeJson(ctx, UInt16(200), skillFilesJson(skill), version: Some(usedVersion))
                return
            }
            if (seg.size == 4 && seg[3] == "models" && method == "GET") {
                this.writeJson(ctx, UInt16(200), jsonOf(this.engine.harnessModels(id)), version: Some(usedVersion))
                return
            }
        }
        if (seg.size >= 3 && seg[0] == "v1" && seg[1] == "responses") {
            let id = seg[2]
            if (seg.size == 3 && method == "GET") {
                this.writeJson(ctx, UInt16(200), jsonOf(this.engine.getResponse(principal, id)), version: Some(usedVersion))
                return
            }
            if (seg.size == 3 && method == "DELETE") {
                this.engine.deleteResponse(principal, id)
                let d = ResponseDeleted()
                d.id = id
                d.deleted = true
                this.writeJson(ctx, UInt16(200), jsonOf(d), version: Some(usedVersion))
                return
            }
            if (seg.size == 4 && seg[3] == "cancel" && method == "POST") {
                this.writeJson(ctx, UInt16(200), jsonOf(this.engine.cancelResponse(principal, id)), version: Some(usedVersion))
                return
            }
            if (seg.size == 4 && seg[3] == "input_items" && method == "GET") {
                this.writeJson(ctx, UInt16(200), "{\"object\":\"list\",\"data\":[]}", version: Some(usedVersion))
                return
            }
        }
        // ---------- Extended：会话列举 / 检查 / turns / 产物 ----------
        if (seg.size == 2 && seg[0] == "v1" && seg[1] == "sessions" && method == "GET") {
            let limit = queryInt(ctx, "limit", 20)
            let cursor = queryString(ctx, "cursor")
            let (items, next) = this.engine.listSessions(principal, limit, cursor)
            this.writeJson(ctx, UInt16(200), sessionsListJson(items, next), version: Some(usedVersion))
            return
        }
        if (seg.size == 3 && seg[0] == "v1" && seg[1] == "sessions" && method == "GET") {
            this.writeJson(ctx, UInt16(200), jsonOf(this.engine.getSession(principal, seg[2])),
                version: Some(usedVersion))
            return
        }
        if (seg.size == 4 && seg[0] == "v1" && seg[1] == "sessions" && seg[3] == "turns" && method == "GET") {
            let turns = SessionTurns()
            turns.turns = this.engine.sessionTurns(principal, seg[2])
            this.writeJson(ctx, UInt16(200), jsonOf(turns), version: Some(usedVersion))
            return
        }
        if (seg.size == 4 && seg[0] == "v1" && seg[1] == "sessions" && seg[3] == "files" && method == "GET") {
            let list = SessionFileList()
            list.files = this.engine.sessionFiles(principal, seg[2])
            this.writeJson(ctx, UInt16(200), jsonOf(list), version: Some(usedVersion))
            return
        }
        if (path == "/v1/files" && method == "POST") {
            let ct = ctx.request.headers.getFirst("content-type") ?? ""
            let raw = readAllBytes(ctx.request.body)
            let parsed = parseMultipart(raw, ct)
            match (parsed) {
                case Some(p) =>
                    let file = this.engine.uploadFile(principal, p.filename, p.content)
                    this.writeJson(ctx, UInt16(200), jsonOf(file), version: Some(usedVersion))
                case None =>
                    this.writeError(ctx, UInt16(400), "invalid_input", None)
            }
            return
        }
        if (seg.size == 6 && seg[0] == "v1" && seg[1] == "containers" && seg[3] == "files") {
            if (seg[5] == "content" && method == "GET") {
                let f = this.engine.downloadFile(principal, seg[2], seg[4])
                ctx.responseBuilder
                    .status(UInt16(200))
                    .header("content-type", f.contentType())
                    .header("x-content-type-options", "nosniff")
                    .header("content-disposition", "attachment; filename=" + f.filename)
                    .header("UHP-Version", usedVersion)
                    .body(f.bytes)
                return
            }
            if (seg[5] == "pdf" && method == "GET") {
                // 不实现预览：规范要求 501 preview_unavailable，而不是坏的/空的 PDF
                this.writeError(ctx, UInt16(501), "preview_unavailable", None)
                return
            }
        }
        if (seg.size == 4 && seg[0] == "v1" && seg[1] == "sessions" && seg[3] == "share") {
            if (method == "POST") {
                // 体可选：无体 = 发布；{"enabled": false} = 吊销（§5 只说无体=发布，这里是超集）
                let body = readAllText(ctx.request.body)
                let disable = body.contains("\"enabled\"") && body.contains("false")
                if (disable) {
                    let n = this.engine.revokeShares(principal, seg[2])
                    this.writeJson(ctx, UInt16(200), shareRevokedJson(seg[2], n),
                        version: Some(usedVersion))
                    return
                }
                let share = this.engine.publishShare(principal, seg[2])
                this.writeJson(ctx, UInt16(200), share.toJson(), version: Some(usedVersion))
                return
            }
            if (method == "GET") {
                let share = this.engine.getShare(principal, seg[2])
                this.writeJson(ctx, UInt16(200), share.toJson(), version: Some(usedVersion))
                return
            }
            if (method == "DELETE") {
                let n = this.engine.revokeShares(principal, seg[2])
                this.writeJson(ctx, UInt16(200), shareRevokedJson(seg[2], n),
                    version: Some(usedVersion))
                return
            }
        }
        if (seg.size == 3 && seg[0] == "v1" && seg[1] == "sessions" && method == "DELETE") {
            this.engine.deleteSession(principal, seg[2])
            this.writeJson(ctx, UInt16(200), "{\"id\":\"" + seg[2] + "\",\"deleted\":true}",
                version: Some(usedVersion))
            return
        }
        if (seg.size == 4 && seg[0] == "v1" && seg[1] == "sessions" && seg[3] == "cancel" && method == "POST") {
            this.engine.cancelSession(principal, seg[2])
            this.writeJson(ctx, UInt16(200),
                "{\"id\":\"" + seg[2] + "\",\"status\":\"cancelled\"}", version: Some(usedVersion))
            return
        }
        this.writeError(ctx, UInt16(404), "invalid_input", None)
    }

    // ---------- 任务创建（流式与非流式同源：都是同一个 Engine.createTask 的结果） ----------

    private func handleCreateResponse(ctx: HttpContext, principal: Principal, usedVersion: String): Unit {
        let body = readAllText(ctx.request.body)
        let parsed = parseTaskRequest(body)
        let req = TaskRequest(parsed.input, model: parsed.model, harnessId: parsed.harnessId,
            previousResponseId: parsed.previousResponseId, background: parsed.background,
            ignoredFields: parsed.ignored.toArray())
        if (parsed.stream) {
            // 流式：立刻建流，事件边产生边发（不能等任务跑完再一把刷，套件 S-09 会抓）
            let started = this.engine.startTask(principal, req)
            this.writeSse(ctx, started, usedVersion)
        } else if (parsed.background) {
            // background：接受即返回 in_progress；轮询 GET 看终态（套件 T-11）
            let started = this.engine.startTask(principal, req)
            this.writeJson(ctx, UInt16(200), jsonOf(started.response), version: Some(usedVersion))
        } else {
            let result = this.engine.createTask(principal, req)
            this.writeJson(ctx, UInt16(200), jsonOf(result.response), version: Some(usedVersion))
        }
    }

    private func writeSse(ctx: HttpContext, result: TaskResult, usedVersion: String): Unit {
        ctx.responseBuilder
            .status(UInt16(200))
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("transfer-encoding", "chunked")
            .header("x-accel-buffering", "no")
            .header("UHP-Version", usedVersion)
        let writer = HttpResponseWriter(ctx)
        // 边产生边发：按游标增量读通道，直到通道关闭且游标追平。
        var cursor: Int64 = 0
        while (true) {
            for (ev in result.channel.replay(cursor)) {
                writer.write(("data: " + ev.json + "\n\n").toArray())
                cursor = ev.seq + 1
            }
            if (result.channel.isClosed() && cursor > result.channel.lastSeq()) {
                break
            }
            sleep(Duration.millisecond * 5)
        }
    }

    // ---------- 版本 ----------

    private func negotiate(ctx: HttpContext): Option<String> {
        let raw = match (ctx.request.headers.getFirst("UHP-Version")) {
            case Some(v) => v
            case None => return Some(this.defaultVersion)
        }
        let v = raw.trimAscii()
        for (known in this.versions) {
            if (known == v) {
                return Some(v)
            }
        }
        return None
    }

    // ---------- 输出 ----------

    private func writeJson(ctx: HttpContext, status: UInt16, body: String, version!: Option<String> = None): Unit {
        let v = match (version) {
            case Some(x) => x
            case None => this.defaultVersion
        }
        ctx.responseBuilder
            .status(status)
            .header("content-type", "application/json")
            .header("UHP-Version", v)
            .body(body)
    }

    private func writeError(ctx: HttpContext, status: UInt16, code: String, param: Option<String>): Unit {
        this.writeErrorDetail(ctx, status, code, param, "")
    }

    private func writeErrorDetail(ctx: HttpContext, status: UInt16, code: String, param: Option<String>,
                                  detailJson: String): Unit {
        // 错误 type 是封闭集合（Errors §2）：401 必须是 authentication_error，403 是 permission_error，
        // 其余请求错误（400/404/409/410/413/422）是 invalid_request_error。
        let t = match (status) {
            case 401 => ErrorType.AuthenticationError
            case 403 => ErrorType.PermissionError
            case s => if (s >= 500) { ErrorType.ServerError } else { ErrorType.InvalidRequestError }
        }
        let env = ErrorEnvelope(t, code, messageFor(code))
        env.param = param
        if (detailJson.size > 0) {
            env.detail = Some(detailJson)
        }
        let wrapper = ErrorResponse()
        wrapper.error = env
        this.writeJson(ctx, status, jsonOf(wrapper))
    }
}

// ---------- 全路径分发器 ----------
// stdx 内置 distributor 的 register 是精确匹配，/v1/responses/{id} 这类带参路径没法逐个注册，
// 所以统一交给 UhpHttpServer.route 自己按段匹配。
class UhpDistributor <: HttpRequestDistributor {
    private let server: UhpHttpServer

    public init(server: UhpHttpServer) {
        this.server = server
    }

    public func register(path: String, h: HttpRequestHandler): Unit {
        ()
    }

    public func register(path: String, h: (HttpContext) -> Unit): Unit {
        ()
    }

    public func distribute(path: String): HttpRequestHandler {
        return UhpHandler(this.server)
    }
}

class UhpHandler <: HttpRequestHandler {
    private let server: UhpHttpServer

    public init(server: UhpHttpServer) {
        this.server = server
    }

    public func handle(ctx: HttpContext): Unit {
        this.server.dispatch(ctx)
    }
}

// ---------- 请求解析 ----------

public class ParsedTaskRequest {
    public var input: String = ""
    public var model: Option<String> = None
    public var harnessId: Option<String> = None
    public var previousResponseId: Option<String> = None
    public var stream: Bool = false
    public var background: Bool = false
    // 客户端发了但服务端不执行的字段（规范 §1.4 的两个保留字段）
    public var ignored: ArrayList<String> = ArrayList<String>()
}

func parseTaskRequest(body: String): ParsedTaskRequest {
    let out = ParsedTaskRequest()
    if (body.size == 0) {
        throw JsonProtocolException("empty body")
    }
    let r = JsonReader(ByteBuffer(body.toArray()))
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ => throw JsonProtocolException("bad json")
        }
        match (name) {
            // input 是 string | item[]：M2 只吃 string，数组形式按 items 里的 input_text 拼接
            case "input" => out.input = readInput(r)
            case "model" => out.model = Some(r.readValue<String>())
            case "stream" => out.stream = r.readValue<Bool>()
            case "background" => out.background = r.readValue<Bool>()
            // 保留字段：接受、不执行，但必须点名（否则「静默忽略」不可观测）
            case "tools" =>
                r.skip()
                out.ignored.add("tools")
            case "include" =>
                r.skip()
                out.ignored.add("include")
            case "previous_response_id" => out.previousResponseId = Some(r.readValue<String>())
            case "metadata" => out.harnessId = readHarnessId(r)
            case _ => r.skip()
        }
    }
    r.endObject()
    return out
}

func readInput(r: JsonReader): String {
    match (r.peek()) {
        case Some(JsonToken.JsonString) => return r.readValue<String>()
        case Some(JsonToken.BeginArray) =>
            // item[]：把 input_text 拼起来（其余 item 类型 M2 忽略）
            let parts = ArrayList<String>()
            r.startArray()
            while (true) {
                match (r.peek()) {
                    case Some(JsonToken.EndArray) => break
                    case Some(JsonToken.BeginObject) =>
                        let text = readItemText(r)
                        if (text.size > 0) {
                            parts.add(text)
                        }
                    case _ =>
                        r.skip()
                }
            }
            r.endArray()
            return String.join(parts.toArray(), delimiter: "\n")
        case _ =>
            r.skip()
            return ""
    }
}

func readItemText(r: JsonReader): String {
    var found = ""
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ =>
                r.skip()
                continue
        }
        match (name) {
            case "content" =>
                match (r.peek()) {
                    case Some(JsonToken.BeginArray) =>
                        r.startArray()
                        while (true) {
                            match (r.peek()) {
                                case Some(JsonToken.EndArray) => break
                                case Some(JsonToken.BeginObject) =>
                                    let t = readPartText(r)
                                    if (t.size > 0) {
                                        found = if (found.size == 0) { t } else { found + t }
                                    }
                                case _ => r.skip()
                            }
                        }
                        r.endArray()
                    case _ => r.skip()
                }
            case _ => r.skip()
        }
    }
    r.endObject()
    return found
}

func readPartText(r: JsonReader): String {
    var text = ""
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ =>
                r.skip()
                continue
        }
        match (name) {
            case "text" => text = r.readValue<String>()
            case _ => r.skip()
        }
    }
    r.endObject()
    return text
}

func readHarnessId(r: JsonReader): Option<String> {
    var hid: Option<String> = None
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ =>
                r.skip()
                continue
        }
        match (name) {
            case "harness_id" => hid = Some(r.readValue<String>())
            case _ => r.skip()
        }
    }
    r.endObject()
    return hid
}

// ---------- 杂项 ----------

func splitPath(path: String): Array<String> {
    let out = ArrayList<String>()
    for (seg in path.split("/")) {
        if (seg.size > 0) {
            out.add(seg)
        }
    }
    return out.toArray()
}

func quoteJoin(items: Array<String>): String {
    let quoted = ArrayList<String>()
    for (i in items) {
        quoted.add("\"" + i + "\"")
    }
    return String.join(quoted.toArray(), delimiter: ",")
}

// 会话列表载荷：{sessions:[...], next_cursor: string|null}
// 规范要求末页显式给 null，不能让客户端靠「本页不满」来猜。
// 吊销应答：session_id + 本次吊销了几条链接
func shareRevokedJson(sessionId: String, n: Int64): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("session.share")
    w.writeName("session_id").writeValue(sessionId)
    w.writeName("enabled").writeValue(false)
    w.writeName("revoked").writeValue(n)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func sessionsListJson(items: Array<Session>, next: Option<String>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("sessions")
    w.startArray()
    for (s in items) {
        w.jsonValue(jsonOf(s))
    }
    w.endArray()
    match (next) {
        case Some(n) => w.writeName("next_cursor").writeValue(n)
        case None => w.writeName("next_cursor").writeNullValue()
    }
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func queryString(ctx: HttpContext, name: String): Option<String> {
    let q = match (ctx.request.url.query) {
        case Some(v) => v
        case None => return None
    }
    for (pair in q.split("&")) {
        let idx = match (pair.indexOf("=")) {
            case Some(i) => i
            case None => continue
        }
        if (pair[0..idx] == name) {
            return Some(pair[idx + 1..pair.size])
        }
    }
    return None
}

func queryInt(ctx: HttpContext, name: String, fallback: Int64): Int64 {
    return match (queryString(ctx, name)) {
        case Some(v) => match (Int64.tryParse(v)) {
            case Some(n) => if (n > 0) { n } else { fallback }
            case None => fallback
        }
        case None => fallback
    }
}

func readAllText(body: InputStream): String {
    let chunks = ArrayList<UInt8>()
    let buf = Array<UInt8>(8192, repeat: 0)
    while (true) {
        let n = body.read(buf)
        if (n <= 0) {
            break
        }
        chunks.add(all: buf[0..n])
    }
    return String.fromUtf8(chunks.toArray())
}
