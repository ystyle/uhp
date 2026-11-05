// stdx.net.http 适配：把真实 HTTP 包装成 HttpTransport。
//
// 两条实测教训写在这里（改之前先读）：
//   1. **流式请求必须每流独占一个 Client**。共享连接池时，一个没读完的流会污染池里的连接，
//      后续请求拿到半死连接（表现为莫名的 read 超时）。
//   2. 错误响应不是流：4xx/5xx 的体要整体读完再关连接，并交回上层做错误映射。
package uhp.transport

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.net.http.*

public class StdHttpTransport <: HttpTransport {
    private let baseUrl: String

    public init(baseUrl: String) {
        // 去掉末尾斜杠，避免拼出 //v1/uhp
        this.baseUrl = if (baseUrl.endsWith("/")) { baseUrl[0..baseUrl.size - 1] } else { baseUrl }
    }

    public func send(req: UhpRequest): UhpResponse {
        let client = ClientBuilder().readTimeout(Duration.second * 120).build()
        try {
            let rsp = client.send(this.build(req))
            return UhpResponse(rsp.status, headersToMap(rsp.headers), readAll(rsp.body))
        } finally {
            client.close()
        }
    }

    public func stream(req: UhpRequest): StreamStart {
        // 独占 Client：见文件头第 1 条
        let client = ClientBuilder().readTimeout(Duration.second * 600).build()
        try {
            let rsp = client.send(this.build(req))
            if (rsp.status >= 400) {
                let body = readAll(rsp.body)
                client.close()
                return StreamStart.Failed(UhpResponse(rsp.status, headersToMap(rsp.headers), body))
            }
            return StreamStart.Started(StdSseStream(rsp.body, client))
        } catch (e: Exception) {
            client.close()
            throw e
        }
    }

    // 返回 stdx 的 HttpRequest（这里当然指 stdx 的类型，本类的 UhpRequest 是输入）
    private func build(req: UhpRequest): HttpRequest {
        var builder = HttpRequestBuilder().method(req.method).url(this.urlOf(req.path))
        for ((k, v) in req.headers) {
            builder = builder.header(k, v)
        }
        match (req.body) {
            case Some(b) => builder = builder.body(b)
            case None => ()
        }
        return builder.build()
    }

    private func urlOf(path: String): String {
        if (path.startsWith("/")) {
            return this.baseUrl + path
        }
        return this.baseUrl + "/" + path
    }
}

class StdSseStream <: SseStream {
    private let body: InputStream
    private let client: Client
    private var eof: Bool = false

    public init(body: InputStream, client: Client) {
        this.body = body
        this.client = client
    }

    public func nextChunk(): Option<Array<UInt8>> {
        if (this.eof) {
            return None
        }
        let buf = Array<UInt8>(8192, repeat: 0)
        let n = this.body.read(buf)
        if (n <= 0) {
            this.eof = true
            return None
        }
        return Some(buf[0..n])
    }

    public func close(): Unit {
        this.eof = true
        this.client.close()
    }
}

// 响应头转成普通 map（UHP 不需要多值头，同名取第一个）。
func headersToMap(headers: HttpHeaders): HashMap<String, String> {
    let m = HashMap<String, String>()
    for ((name, _) in headers.iterator()) {
        match (headers.getFirst(name)) {
            case Some(v) => m[name] = v
            case None => ()
        }
    }
    return m
}

// 完整读取一个 InputStream（错误体、非流式响应体）。
func readAll(body: InputStream): String {
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
