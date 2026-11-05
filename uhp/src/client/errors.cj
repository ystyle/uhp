// 客户端错误模型：协议层的错误封套 → 结构化异常。
//
// 分界（规范 Errors §1）：**请求失败**是异常；**任务失败**是正常返回的 Response（HTTP 200 + status=failed）。
// 这两件事绝不能混。
package uhp.client

import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.codec.*
import uhp.types.handwritten.*
import uhp.transport.*

public class UhpError <: Exception {
    public let envelope: ErrorEnvelope
    public let httpStatus: UInt16

    public init(envelope: ErrorEnvelope, httpStatus: UInt16) {
        super(envelope.sanitizedMessage())
        this.envelope = envelope
        this.httpStatus = httpStatus
    }

    public func code(): String {
        return this.envelope.code
    }

    public func errorType(): ErrorType {
        return this.envelope.errorType
    }

    // 重试策略来自错误模型的重试表（按 type + code），不是「看状态码是不是 5xx」。
    public func shouldRetry(): Bool {
        return retryable(this.envelope)
    }

    public func advice(): RetryAdvice {
        return retryAdvice(this.envelope)
    }
}

// 响应违反协议（例如缺 UHP-Version 回显、流畸形）——不是服务端业务错误。
public class ProtocolViolation <: Exception {
    public init(message: String) {
        super(message)
    }
}

// 事件流序号出现缺口：规范要求 sequence_number 从 0 起严格 +1，缺口可检测。
public class StreamGap <: Exception {
    public let expected: Int64
    public let actual: Int64

    public init(expected: Int64, actual: Int64) {
        super("事件流序号缺口：期望 " + expected.toString() + "，实际 " + actual.toString())
        this.expected = expected
        this.actual = actual
    }
}

// 把错误响应体解析成 UhpError。解析不出来时按 HTTP 状态给兜底封套
// （错误体畸形不应让客户端连「失败」都表达不了）。
public func errorFromResponse(resp: UhpResponse): UhpError {
    match (parseErrorEnvelope(resp.body)) {
        case Some(env) => return UhpError(env, resp.status)
        case None =>
            let fallback = ErrorEnvelope(
                ErrorType.ServerError,
                "invalid_response_body",
                "服务端返回了无法解析的错误体（HTTP " + resp.status.toString() + "）"
            )
            return UhpError(fallback, resp.status)
    }
}

// 规范信封是 {"error": {...}}；为兼容旧实现，也接受裸 envelope。
func parseErrorEnvelope(body: String): Option<ErrorEnvelope> {
    if (body.size == 0) {
        return None
    }
    try {
        let r = JsonReader(ByteBuffer(body.toArray()))
        let resp = ErrorResponse.fromJson(r)
        return Some(resp.error)
    } catch (e: Exception) {
        try {
            let r2 = JsonReader(ByteBuffer(body.toArray()))
            return Some(ErrorEnvelope.fromJson(r2))
        } catch (e2: Exception) {
            return None
        }
    }
}
