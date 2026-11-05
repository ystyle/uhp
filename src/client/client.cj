// UHP 客户端：发现、版本协商、任务、会话延续、取消与删除。
//
// 设计要点（见设计文档 §6）：
//   * 任务失败不是异常（Response.status = failed 是成功返回的对象）；
//   * 每个响应必须回显 UHP-Version，缺失即协议违规；
//   * POST /v1/responses 的重试必须带 Idempotency-Key，且键要在第一次尝试前生成。
package uhp.client

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.random.*
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.handwritten.*
import uhp.types.generated.*
import uhp.types.base.*

// 本 SDK 能说哪些协议版本（新→旧）。版本表是运行期数据，不是编译期 feature。
public let KNOWN_VERSIONS: Array<String> = ["2026-10-19"]

public class UhpClient {
    private let baseUrl: String
    private let token: String
    private let transport: HttpTransport
    private var discoveryDoc: Option<Discovery> = None
    private var negotiatedVersion: Option<String> = None

    public init(baseUrl: String, token: String, transport: HttpTransport) {
        this.baseUrl = baseUrl
        this.token = token
        this.transport = transport
    }

    // ---------- 发现与版本协商 ----------

    // GET /v1/uhp 免鉴权：客户端需要先知道对面是不是 UHP 服务端，才谈得上给凭证。
    public func discover(): Discovery {
        match (this.discoveryDoc) {
            case Some(d) => return d
            case None => ()
        }
        let resp = this.transport.send(HttpRequest("GET", "/v1/uhp", HashMap<String, String>(), None))
        if (!resp.isSuccess()) {
            throw errorFromResponse(resp)
        }
        checkVersionHeader(resp)
        let doc = parseDiscovery(resp.body)
        // 协商：取服务端 versions 与本端 KNOWN_VERSIONS 的最大交集；无交集则明确报错，
        // 不允许「静默按老版本说话」（Lifecycle §1）。
        let chosen = negotiate(doc.versions)
        match (chosen) {
            case Some(v) => this.negotiatedVersion = Some(v)
            case None =>
                throw UhpError(ErrorEnvelope(
                    ErrorType.InvalidRequestError,
                    "unsupported_protocol_version",
                    "服务端支持的版本与本 SDK 无交集：" + joinVersions(doc.versions)
                ), UInt16(400))
        }
        this.discoveryDoc = Some(doc)
        return doc
    }

    public func protocolVersion(): String {
        match (this.negotiatedVersion) {
            case Some(v) => return v
            case None =>
                this.discover()
                return this.negotiatedVersion ?? KNOWN_VERSIONS[0]
        }
    }

    public func capabilities(): Capabilities {
        return this.discover().capabilities
    }

    // ---------- harness 与模型 ----------

    public func harnesses(): Array<Harness> {
        return this.getJson<HarnessList>("/v1/harnesses").harnesses
    }

    public func harnessModels(harnessId: String): HarnessModels {
        return this.getJson<HarnessModels>("/v1/harnesses/" + harnessId + "/models")
    }

    // ---------- 任务 ----------

    // idempotencyKey 由调用方给出时必须**跨重试复用**；不给则由本方法生成一次并在内部重试中复用。
    public func createTask(req: CreateResponseRequest, idempotencyKey!: Option<String> = None): Response {
        let key = match (idempotencyKey) {
            case Some(k) => k
            case None => newIdempotencyKey()
        }
        let resp = this.sendAuthed("POST", "/v1/responses", toJsonStringOf(req), Some(key))
        if (!resp.isSuccess()) {
            throw errorFromResponse(resp)
        }
        checkVersionHeader(resp)
        return parseJson<Response>(resp.body)
    }

    public func createTaskStream(req: CreateResponseRequest, idempotencyKey!: Option<String> = None): TaskStream {
        let key = match (idempotencyKey) {
            case Some(k) => k
            case None => newIdempotencyKey()
        }
        let headers = this.commonHeaders()
        headers["Accept"] = "text/event-stream"
        headers["Idempotency-Key"] = key
        let body = toJsonStringOf(req)
        let stream = this.transport.stream(HttpRequest("POST", "/v1/responses", headers, Some(body)))
        return TaskStream(stream)
    }

    public func getResponse(responseId: String): Response {
        return this.getJson<Response>("/v1/responses/" + responseId)
    }

    public func cancelResponse(responseId: String): Response {
        return this.postJson<Response>("/v1/responses/" + responseId + "/cancel", None)
    }

    public func deleteResponse(responseId: String): ResponseDeleted {
        let resp = this.sendAuthed("DELETE", "/v1/responses/" + responseId, None, None)
        if (!resp.isSuccess()) {
            throw errorFromResponse(resp)
        }
        checkVersionHeader(resp)
        return parseJson<ResponseDeleted>(resp.body)
    }

    // ---------- 内部 ----------

    private func commonHeaders(): HashMap<String, String> {
        let h = HashMap<String, String>()
        h["Authorization"] = "Bearer " + this.token
        h["Content-Type"] = "application/json"
        h["UHP-Version"] = this.protocolVersion()
        return h
    }

    private func sendAuthed(method: String, path: String, body: Option<String>, idemKey: Option<String>): HttpResponse {
        let headers = this.commonHeaders()
        match (idemKey) {
            case Some(k) => headers["Idempotency-Key"] = k
            case None => ()
        }
        return this.transport.send(HttpRequest(method, path, headers, body))
    }

    private func getJson<T>(path: String): T where T <: JsonDeserializable<T> {
        let resp = this.sendAuthed("GET", path, None, None)
        if (!resp.isSuccess()) {
            throw errorFromResponse(resp)
        }
        checkVersionHeader(resp)
        return parseJson<T>(resp.body)
    }

    private func postJson<T>(path: String, body: Option<String>): T where T <: JsonDeserializable<T> {
        let resp = this.sendAuthed("POST", path, body, None)
        if (!resp.isSuccess()) {
            throw errorFromResponse(resp)
        }
        checkVersionHeader(resp)
        return parseJson<T>(resp.body)
    }
}

// ---------- 辅助 ----------

// 规范要求**每个**响应（含错误）都回显 UHP-Version；缺失即协议违规，
// 不静默接受（否则客户端无法发现自己在跟一个不守约的实现说话）。
public func checkVersionHeader(resp: HttpResponse): Unit {
    match (resp.header("UHP-Version")) {
        case Some(v) => if (v.size == 0) {
                throw ProtocolViolation("响应带了空的 UHP-Version 头")
            }
        case None => throw ProtocolViolation("响应缺少 UHP-Version 头（HTTP " + resp.status.toString() + "）")
    }
}

func negotiate(serverVersions: Array<String>): Option<String> {
    for (v in KNOWN_VERSIONS) {
        if (serverVersions.contains(v)) {
            return Some(v)
        }
    }
    return None
}

func joinVersions(vs: Array<String>): String {
    return String.join(vs, delimiter: ", ")
}

func parseDiscovery(body: String): Discovery {
    return parseJson<Discovery>(body)
}

public func parseJson<T>(body: String): T where T <: JsonDeserializable<T> {
    let r = JsonReader(ByteBuffer(body.toArray()))
    return T.fromJson(r)
}

// 幂等键：客户端生成、跨重试复用。不需要密码学强度（服务端按 principal 作用域去重）。
public func newIdempotencyKey(): String {
    let rnd = Random()
    return "uhp-" + rnd.nextUInt64().toString(radix: 16) + "-" + rnd.nextUInt64().toString(radix: 16)
}

// 把对象序列化成 JSON 文本（请求体）。
public func toJsonStringOf<T>(value: T): String where T <: JsonSerializable {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    value.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}
