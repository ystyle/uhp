// opencode 的 HTTP 客户端：同步请求 + 事件流（SSE）。
//
// 两个实测约束（opencode 2.2.5）：
//   1. 鉴权是 **HTTP Basic**（auth 用户固定 opencode，密码是 server 启动时给的）；
//   2. 事件流是**全局**的（/api/event），要按 data.sessionID 过滤——不能指望 per-session 订阅。
package uhp_opencode.client

import std.collection.{ArrayList, HashMap}
import std.io.*
import std.sync.Mutex
import stdx.net.http.*
import stdx.net.tls.*

public class OcHttp {
    private let baseUrl: String
    private let auth: String

    public init(baseUrl: String, user: String, password: String) {
        var base = baseUrl
        if (base.endsWith("/")) {
            base = base[0..base.size - 1]
        }
        this.baseUrl = base
        this.auth = "Basic " + ocBase64((user + ":" + password).toArray())
    }

    public func urlOf(path: String): String {
        return this.baseUrl + path
    }

    public func authHeader(): String {
        return this.auth
    }

    public func post(path: String, body: String): (UInt16, String) {
        let client = newClient()
        try {
            let req = HttpRequestBuilder()
                .method("POST")
                .url(this.urlOf(path))
                .header("authorization", this.auth)
                .header("content-type", "application/json")
                .body(body)
                .build()
            let rsp = client.send(req)
            return (rsp.status, ocReadAllText(rsp.body))
        } finally {
            client.close()
        }
    }

    public func get(path: String): (UInt16, String) {
        let client = newClient()
        try {
            let req = HttpRequestBuilder()
                .method("GET")
                .url(this.urlOf(path))
                .header("authorization", this.auth)
                .build()
            let rsp = client.send(req)
            return (rsp.status, ocReadAllText(rsp.body))
        } finally {
            client.close()
        }
    }

    func newClient(): Client {
        return ClientBuilder()
            .tlsConfig(TlsClientConfig())
            .noProxy()
            .readTimeout(Duration.second * 600)
            .build()
    }
}

// 事件泵：后台线程读全局事件流，主线程按需取。读与取之间用锁 + 轮询（事件量小）。
public class EventPump {
    private let lock = Mutex()
    private let frames: ArrayList<String> = ArrayList<String>()
    private var closed: Bool = false
    private let http: OcHttp

    public init(http: OcHttp) {
        this.http = http
        spawn {
            this.run()
        }
    }

    public func drain(): Array<String> {
        synchronized(this.lock) {
            let out = this.frames.toArray()
            this.frames.clear()
            return out
        }
    }

    public func isClosed(): Bool {
        synchronized(this.lock) {
            return this.closed
        }
    }

    private func push(data: String): Unit {
        synchronized(this.lock) {
            this.frames.add(data)
        }
    }

    private func run(): Unit {
        let client = this.http.newClient()
        try {
            let req = HttpRequestBuilder()
                .method("GET")
                .url(this.http.urlOf("/api/event"))
                .header("authorization", this.http.authHeader())
                .header("accept", "text/event-stream")
                .build()
            let rsp = client.send(req)
            if (rsp.status != UInt16(200)) {
                synchronized(this.lock) {
                    this.closed = true
                }
                return
            }
            let parser = SseParser()
            let buf = Array<UInt8>(8192, repeat: 0)
            while (true) {
                let n = rsp.body.read(buf)
                if (n <= 0) {
                    break
                }
                for (frame in parser.feed(buf[0..n])) {
                    if (frame.data.size > 0) {
                        this.push(frame.data)
                    }
                }
            }
        } catch (e: Exception) {
            ()
        } finally {
            synchronized(this.lock) {
                this.closed = true
            }
            client.close()
        }
    }
}

public func ocReadAllText(body: InputStream): String {
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

const B64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

public func ocBase64(bytes: Array<UInt8>): String {
    let chars = B64.toRuneArray()
    let out = StringBuilder()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (b in bytes) {
        buffer = (buffer << 8) | Int64(b)
        bits = bits + 8
        while (bits >= 6) {
            bits = bits - 6
            out.append(chars[Int64((buffer >> bits) & 0x3F)])
        }
    }
    if (bits > 0) {
        out.append(chars[Int64((buffer << (6 - bits)) & 0x3F)])
    }
    return out.toString()
}
