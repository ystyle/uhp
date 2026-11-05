// 本地 MCP fixture（进程内）：一致性套件的 P-11 / T-12 需要一个「agent 能调到的 MCP server」。
//
// 为什么自己起而不是连公网 fixture：
//   1. CI 不该依赖外部网络与别人的可用性；
//   2. 套件本身就把 fixture 做成可指向的（--plugin-mcp-url / UHP_PLUGIN_MCP_URL），
//      它验证的是「服务端把插件的 MCP 服务器绑定进任务、driver 真能调到」，不是「公网通不通」。
//
// 协议：streamable-HTTP 的最小实现（POST /mcp，JSON-RPC 2.0，直接回 JSON 而非 SSE）。
package uhp_conformance_sut

import std.collection.{ArrayList, HashMap}
import std.io.ByteBuffer
import stdx.encoding.json.stream.*
import std.io.*
import stdx.net.http.*

public func startMcpFixture(port: UInt16): UInt16 {
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(port)
        .distributor(mcpDistributor())
        .build()
    let actual = server.port
    spawn {
        server.serve()
    }
    return actual
}

// 最小路径分发器（fixture 只有两条路由，不引 SDK 的分发器）
class McpDistributor <: HttpRequestDistributor {
    private let handlers: HashMap<String, (HttpContext) -> Unit> = HashMap<String, (HttpContext) -> Unit>()

    public func register(path: String, handler: HttpRequestHandler): Unit {
        this.handlers[path] = { ctx => handler.handle(ctx) }
    }

    public func register(path: String, handler: (HttpContext) -> Unit): Unit {
        this.handlers[path] = handler
    }

    public func distribute(path: String): HttpRequestHandler {
        match (this.handlers.get(path)) {
            case Some(h) => return ClosureHandler(h)
            case None => return NotFoundHandler()
        }
    }
}

class ClosureHandler <: HttpRequestHandler {
    private let f: (HttpContext) -> Unit

    public init(f: (HttpContext) -> Unit) {
        this.f = f
    }

    public func handle(ctx: HttpContext): Unit {
        this.f(ctx)
    }
}

func mcpDistributor(): HttpRequestDistributor {
    let d = McpDistributor()
    d.register("/mcp", mcpHandler)
    d.register("/health", healthHandler)
    return d
}

func healthHandler(ctx: HttpContext): Unit {
    ctx.responseBuilder.status(UInt16(200)).body("ok")
}

func mcpHandler(ctx: HttpContext): Unit {
    let body = readBodyText(ctx.request.body)
    // 通知没有 id：回 202 空体
    if (body.contains("notifications/initialized")) {
        ctx.responseBuilder.status(UInt16(202))
        return
    }
    let method = stringField(body, "method") ?? ""
    let id = rawField(body, "id") ?? "null"
    let result = match (method) {
        case "initialize" =>
            "{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"tools\":{}}," +
            "\"serverInfo\":{\"name\":\"uhp-local-fixture\",\"version\":\"1.0.0\"}}"
        case "tools/list" =>
            "{\"tools\":[{\"name\":\"uhp_echo\",\"description\":\"Echo text back transformed (reversed).\"," +
            "\"inputSchema\":{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}}," +
            "\"required\":[\"text\"]}}," +
            "{\"name\":\"uhp_steps\",\"description\":\"Count one step of a chain.\"," +
            "\"inputSchema\":{\"type\":\"object\",\"properties\":{\"nonce\":{\"type\":\"string\"}}," +
            "\"required\":[\"nonce\"]}}]}"
        case "tools/call" =>
            let name = stringField(body, "name") ?? ""
            if (name == "uhp_steps") {
                let nonce = stringField(body, "nonce") ?? ""
                stepResultJson(nonce)
            } else if (name == "uhp_echo") {
                let text = stringField(body, "text") ?? ""
                "{\"content\":[{\"type\":\"text\",\"text\":\"UHP-FIXTURE:" + reverse(text) + "\"}],\"isError\":false}"
            } else {
                "{\"content\":[{\"type\":\"text\",\"text\":\"unknown tool\"}],\"isError\":true}"
            }
        case _ => ""
    }
    if (result.size == 0) {
        ctx.responseBuilder.status(UInt16(400)).body("{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32601}}")
        return
    }
    let out = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"result\":" + result + "}"
    ctx.responseBuilder.status(UInt16(200)).body(out)
}

// 链的答案：step N of 3；最后一步说 done（套件按这个格式判断）
var stepCounts: HashMap<String, Int64> = HashMap<String, Int64>()

func stepResultJson(nonce: String): String {
    let text = stepAnswer(nonce)
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("content")
    w.startArray()
    w.startObject()
    w.writeName("type").writeValue("text")
    w.writeName("text").writeValue(text)
    w.endObject()
    w.endArray()
    w.writeName("isError").writeValue(false)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func stepAnswer(nonce: String): String {
    let prev = stepCounts.get(nonce) ?? 0
    let step = prev + 1
    stepCounts[nonce] = step
    let head = "UHP-FIXTURE step " + step.toString() + " of 3"
    if (step < 3) {
        return head + "; call uhp_steps again to continue"
    }
    return head + "; the chain is done"
}

func readBodyText(body: InputStream): String {
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

// 轻量 JSON 取值：fixture 只处理自己关心的几个字段，够用即止（不引依赖）
func stringField(body: String, field: String): Option<String> {
    let marker = "\"" + field + "\""
    let i = match (body.indexOf(marker)) {
        case Some(v) => v + marker.size
        case None => return None
    }
    // 跳过 : 与空白
    var j = i
    let arr = body.toArray()
    while (j < arr.size && (arr[j] == UInt8(58) || arr[j] == UInt8(32) || arr[j] == UInt8(9))) {
        j = j + 1
    }
    if (j >= arr.size || arr[j] != UInt8(34)) {
        return None
    }
    j = j + 1
    var end = j
    while (end < arr.size && arr[end] != UInt8(34)) {
        end = end + 1
    }
    return Some(String.fromUtf8(arr[j..end]))
}

func rawField(body: String, field: String): Option<String> {
    let marker = "\"" + field + "\""
    let i = match (body.indexOf(marker)) {
        case Some(v) => v + marker.size
        case None => return None
    }
    var j = i
    let arr = body.toArray()
    while (j < arr.size && (arr[j] == UInt8(58) || arr[j] == UInt8(32))) {
        j = j + 1
    }
    var end = j
    while (end < arr.size && arr[end] != UInt8(44) && arr[end] != UInt8(125)) {
        end = end + 1
    }
    return Some(String.fromUtf8(arr[j..end]))
}

func reverse(s: String): String {
    let runes = s.toRuneArray()
    let out = StringBuilder()
    var i = runes.size
    while (i > 0) {
        i = i - 1
        out.append(runes[i])
    }
    return out.toString()
}
