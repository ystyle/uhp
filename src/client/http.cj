// 客户端传输抽象。
//
// 为什么先抽象再实现：协议逻辑（版本协商、错误映射、幂等、流式消费）应当能在
// **没有网络**的情况下穷举测试。真实 HTTP 实现（stdx.net.http）是这一层的适配器，
// 测试与 CI 用内存桩，规范一致性则由外部 SUT 进程验证。
package uhp.client

import std.collection.HashMap

public class HttpRequest {
    public let method: String
    public let path: String
    public let headers: HashMap<String, String>
    public let body: Option<String>

    public init(method: String, path: String, headers: HashMap<String, String>, body: Option<String>) {
        this.method = method
        this.path = path
        this.headers = headers
        this.body = body
    }
}

public class HttpResponse {
    public let status: UInt16
    public let headers: HashMap<String, String>
    public let body: String

    public init(status: UInt16, headers: HashMap<String, String>, body: String) {
        this.status = status
        this.headers = headers
        this.body = body
    }

    public func header(name: String): Option<String> {
        // HTTP 头大小写不敏感
        let lower = name.toAsciiLower()
        for ((k, v) in this.headers) {
            if (k.toAsciiLower() == lower) {
                return Some(v)
            }
        }
        return None
    }

    public func isSuccess(): Bool {
        return this.status >= 200 && this.status < 300
    }
}

// 流式响应的读取端：一次一块原始字节，直到 None（流结束）。
public interface SseStream {
    func nextChunk(): Option<Array<UInt8>>
    func close(): Unit
}

public interface HttpTransport {
    // 非流式请求（用于 discovery / 单次任务 / 读回 / 取消 / 删除）
    func send(req: HttpRequest): HttpResponse
    // 流式请求（Accept: text/event-stream）；返回体按块读取
    func stream(req: HttpRequest): SseStream
}
