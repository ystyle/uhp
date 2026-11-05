// HTTP 层：路由、鉴权、版本协商、错误封套、SSE 输出。
//
// 分层原则：这一层只做「协议面」的事——解析请求、认人、认版本、把引擎错误翻成错误封套；
// 业务语义（任务状态机、事件、scope）全在 Engine 里，HTTP 层不许再判断一次。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import stdx.net.http.*
import uhp.types.codec.*
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
            this.writeError(ctx, e.httpStatus, e.code, e.param)
        } catch (e: JsonProtocolException) {
            this.writeError(ctx, UInt16(400), "invalid_input", None)
        } catch (e: Exception) {
            // 不把内部异常文本泄漏给调用方（错误封套的 message 必须安全可展示）
            this.writeError(ctx, UInt16(500), "server_error", None)
        }
    }

    private func route(ctx: HttpContext): Unit {
        let method = ctx.request.method
        let path = ctx.request.url.path

        // discovery 免鉴权：客户端要先知道对面是不是 UHP 服务端，才谈得上给凭证
        if (method == "GET" && path == "/v1/uhp") {
            this.writeJson(ctx, UInt16(200), jsonOf(this.engine.discovery()))
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

        // 版本协商：不认识的版本必须明确失败并列出支持的版本，绝不静默换版本
        let usedVersion = match (this.negotiate(ctx)) {
            case Some(v) => v
            case None =>
                this.writeErrorDetail(ctx, UInt16(400), "unsupported_protocol_version", None,
                    "{\"supported\":[" + quoteJoin(this.versions) + "]}")
                return
        }

        let seg = splitPath(path)
        if (method == "GET" && path == "/v1/harnesses") {
            let list = HarnessList()
            list.harnesses = this.engine.listHarnesses()
            this.writeJson(ctx, UInt16(200), jsonOf(list), version: Some(usedVersion))
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
                this.writeJson(ctx, UInt16(200), jsonOf(this.engine.getHarness(id)), version: Some(usedVersion))
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
        let req = TaskRequest(parsed.input, model: parsed.model, harnessId: parsed.harnessId, previousResponseId: parsed.previousResponseId)
        let result = this.engine.createTask(principal, req)
        if (parsed.stream) {
            this.writeSse(ctx, result, usedVersion)
        } else {
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
        // 注意：引擎当前是同步执行，事件在写之前已经全部产生，所以这里是「按序回放」。
        // 真正边跑边发需要引擎异步执行 + 通道订阅（已列在 M2 剩余项里）。
        for (ev in result.channel.replay(0)) {
            writer.write(("data: " + ev.json + "\n\n").toArray())
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
        let t = if (status >= 500) { ErrorType.ServerError } else { ErrorType.InvalidRequestError }
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
            case Some(EndObject) => break
            case Some(Name) => r.readName()
            case _ => throw JsonProtocolException("bad json")
        }
        match (name) {
            // input 是 string | item[]：M2 只吃 string，数组形式按 items 里的 input_text 拼接
            case "input" => out.input = readInput(r)
            case "model" => out.model = Some(r.readValue<String>())
            case "stream" => out.stream = r.readValue<Bool>()
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
        case Some(String) => return r.readValue<String>()
        case Some(BeginArray) =>
            // item[]：把 input_text 拼起来（其余 item 类型 M2 忽略）
            let parts = ArrayList<String>()
            r.startArray()
            while (true) {
                match (r.peek()) {
                    case Some(EndArray) => break
                    case Some(BeginObject) =>
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
            case Some(EndObject) => break
            case Some(Name) => r.readName()
            case _ =>
                r.skip()
                continue
        }
        match (name) {
            case "content" =>
                match (r.peek()) {
                    case Some(BeginArray) =>
                        r.startArray()
                        while (true) {
                            match (r.peek()) {
                                case Some(EndArray) => break
                                case Some(BeginObject) =>
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
            case Some(EndObject) => break
            case Some(Name) => r.readName()
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
            case Some(EndObject) => break
            case Some(Name) => r.readName()
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
