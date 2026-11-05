// 错误模型（Errors §1–§4）。
//
// 这个文件手写而不是生成，因为规范里有三处形状是 codegen 表达不了的：
//   · type 是封闭的 6 值集合，code 却必须开放（§1）：服务端可为规范未覆盖的条件
//     自定义带厂商前缀（acme_…）的码，客户端遇到未知码必须能解析、能判定重试，
//     不能崩。所以 code 是 String + 常用码常量/规格表，而不是封闭枚举。
//   · message MUST 安全可展示：不得含凭证、内部主机名、文件路径或栈（§1）。
//     本文件在所有入口（本地构造、fromJson）统一 sanitize，调用方拿到的
//     message 默认就是可展示的；sanitizedMessage() 供再次展示前兜底。
//   · 重试按 type + 具体 code 查 §4 的表，而不是只看 HTTP 状态猜：server_error /
//     rate_limited 可重试，quota_exhausted 不可，session_busy 等在途任务到终态后
//     可重试，input_request_expired 不可，认证/权限不可，harness 失败（HTTP 200
//     的 failed 响应）由调用方判断。
//
// 未知字段一律按 codec/extras 的约定逐字节保留。param/detail 缺失按 null 处理；
// 序列化时 6 个键始终写出（§1：param、detail 必填，可为 null）。
package uhp.types.handwritten

import std.collection.ArrayList
import std.collection.HashMap
import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*

// message 的上限（按 Unicode 标量计，不是字节）。规范要求 message 是「一句话」；
// 超长内容多半是上游原始报错或栈，截断比原样透出安全。
public let MAX_ERROR_MESSAGE_RUNES: Int64 = 512

// ---------- §2 错误类型 ----------

// 线的 type（§2）。注意 HarnessError 的 HTTP 是 200：任务失败仍是一次成功的请求，
// 与「请求失败」（非 2xx + 错误信封）是两类事件，不能混（§1）。
public enum ErrorType {
    | InvalidRequestError
    | AuthenticationError
    | PermissionError
    | RateLimitError
    | HarnessError
    | ServerError
    // 兜底变体：服务端可能来自比本 SDK 更新的规范版本。保留原始字符串并按原样
    // 写回（未知枚举值不得 panic / 不得静默改写成某个已知值）。
    | Unknown(String)
}

// 线上表示（§2 的 type 列取值）。
public func errorTypeName(t: ErrorType): String {
    return match (t) {
        case ErrorType.InvalidRequestError => "invalid_request_error"
        case ErrorType.AuthenticationError => "authentication_error"
        case ErrorType.PermissionError => "permission_error"
        case ErrorType.RateLimitError => "rate_limit_error"
        case ErrorType.HarnessError => "harness_error"
        case ErrorType.ServerError => "server_error"
        case ErrorType.Unknown(raw) => raw
    }
}

// 解析 type。未知值落到 Unknown(raw) 而不是抛异常：type 是封闭枚举，但服务端可能
// 来自更新的版本；静默改写会改变状态码与重试决策，丢弃又会破坏往返保真。
public func parseErrorType(name: String): ErrorType {
    return match (name) {
        case "invalid_request_error" => ErrorType.InvalidRequestError
        case "authentication_error" => ErrorType.AuthenticationError
        case "permission_error" => ErrorType.PermissionError
        case "rate_limit_error" => ErrorType.RateLimitError
        case "harness_error" => ErrorType.HarnessError
        case "server_error" => ErrorType.ServerError
        case _ => ErrorType.Unknown(name)
    }
}

// §2 表：一个 type 对应的**一组** HTTP 状态（invalid_request_error 覆盖六种）。
// 判定「某个状态是否属于这个 type」用它；构造响应用 httpStatusOf。
public func httpStatusesOf(t: ErrorType): Array<Int64> {
    return match (t) {
        case ErrorType.InvalidRequestError => [400, 404, 409, 410, 413, 422]
        case ErrorType.AuthenticationError => [401]
        case ErrorType.PermissionError => [403]
        case ErrorType.RateLimitError => [429]
        case ErrorType.HarnessError => [200]
        case ErrorType.ServerError => [500, 502, 503, 504]
        // 未知 type 没有规范映射：空集，调用方按协议错误处理。
        case ErrorType.Unknown(raw) => []
    }
}

// 构造响应时的缺省状态（该组的主状态）。具体 code 有更精确的状态时用
// httpStatusOf(envelope)——例如 invalid_request_error 下的 file_too_large 是 413。
// harness_error 的 200 是刻意的：failed 响应是 HTTP 200（§1）。
public func httpStatusOf(t: ErrorType): Int64 {
    return match (t) {
        case ErrorType.InvalidRequestError => 400
        case ErrorType.AuthenticationError => 401
        case ErrorType.PermissionError => 403
        case ErrorType.RateLimitError => 429
        case ErrorType.HarnessError => 200
        case ErrorType.ServerError => 500
        // 无法分类时按服务端错误处理；未知 type 不应被服务端用于构造响应。
        case ErrorType.Unknown(raw) => 500
    }
}

// ---------- §4 重试分类 ----------

// 重试不是布尔：§4 里「可重试」有三种带前提的形态，另有「调用方判断」。
// 把这些形态显式建模，调用方就不必自己解析 code 字符串。
public enum RetryAdvice {
    // server_error：指数退避 + 抖动后重试。
    | RetryWithBackoff
    // rate_limited：等 Retry-After（或同等退避）后重试。
    | RetryAfterCooldown
    // session_busy：等在途任务到达终态后重试。
    | RetryWhenInFlightTaskTerminal
    // input_response_invalid：换一个符合请求 kind/options 的答案再发。
    | RetryWithCorrectedInput
    // harness 失败（failed 响应）：任务消耗了真实资源，由调用方判断。
    | CallerJudgment
    // 不改现状重试必然再失败：改请求 / 改凭证 / 换配额。
    | DoNotRetry
}

public func retryAdviceName(a: RetryAdvice): String {
    return match (a) {
        case RetryAdvice.RetryWithBackoff => "retry_with_backoff"
        case RetryAdvice.RetryAfterCooldown => "retry_after_cooldown"
        case RetryAdvice.RetryWhenInFlightTaskTerminal => "retry_when_in_flight_task_terminal"
        case RetryAdvice.RetryWithCorrectedInput => "retry_with_corrected_input"
        case RetryAdvice.CallerJudgment => "caller_judgment"
        case RetryAdvice.DoNotRetry => "do_not_retry"
    }
}

// 是否值得重试（含「满足前提后重试」）。CallerJudgment 返回 false：SDK 不替调用方
// 决定是否重跑一个已经消耗过资源的任务；需要时调用方自己按业务判断。
public func isRetryableAdvice(a: RetryAdvice): Bool {
    return match (a) {
        case RetryAdvice.DoNotRetry => false
        case RetryAdvice.CallerJudgment => false
        case _ => true
    }
}

// 未知厂家码的缺省策略（按 §4 的 type 行）。未知 type 保守处理：不自动重试——
// 连错误类别都认不出时，重试可能放大故障而不是恢复。
public func defaultRetryAdvice(t: ErrorType): RetryAdvice {
    return match (t) {
        case ErrorType.ServerError => RetryAdvice.RetryWithBackoff
        case ErrorType.RateLimitError => RetryAdvice.RetryAfterCooldown
        case ErrorType.HarnessError => RetryAdvice.CallerJudgment
        case ErrorType.InvalidRequestError => RetryAdvice.DoNotRetry
        case ErrorType.AuthenticationError => RetryAdvice.DoNotRetry
        case ErrorType.PermissionError => RetryAdvice.DoNotRetry
        case ErrorType.Unknown(raw) => RetryAdvice.DoNotRetry
    }
}

// ---------- §3 错误码 ----------

// 单个规范码的规格：它的 HTTP 状态、所属 type、§4 的重试建议。
public struct ErrorCodeSpec {
    public let httpStatus: Int64
    public let errorType: ErrorType
    public let retryAdvice: RetryAdvice

    public init(httpStatus: Int64, errorType: ErrorType, retryAdvice: RetryAdvice) {
        this.httpStatus = httpStatus
        this.errorType = errorType
        this.retryAdvice = retryAdvice
    }
}

// §3 常用码的字符串常量。code 保持 String（规范允许厂商前缀自定义码），
// 这些常量只是让服务端/调用方不必手写字符串字面量。
public class ErrorCodes {
    // §3.1 请求与路由
    public static const UNSUPPORTED_PROTOCOL_VERSION: String = "unsupported_protocol_version"
    public static const INVALID_INPUT: String = "invalid_input"
    public static const HARNESS_NOT_FOUND: String = "harness_not_found"
    public static const RESPONSE_NOT_FOUND: String = "response_not_found"
    public static const SESSION_NOT_FOUND: String = "session_not_found"
    public static const PLUGIN_NOT_FOUND: String = "plugin_not_found"
    public static const FILE_NOT_FOUND: String = "file_not_found"
    public static const SESSION_EXPIRED: String = "session_expired"
    public static const HARNESS_MISMATCH: String = "harness_mismatch"
    public static const SESSION_BUSY: String = "session_busy"
    public static const HARNESS_BUSY: String = "harness_busy"
    public static const PLUGIN_CONFLICT: String = "plugin_conflict"
    public static const IDEMPOTENCY_KEY_REUSED: String = "idempotency_key_reused"
    public static const INPUT_NOT_PENDING: String = "input_not_pending"
    public static const INPUT_REQUEST_EXPIRED: String = "input_request_expired"
    public static const INPUT_RESPONSE_INVALID: String = "input_response_invalid"
    public static const FILE_TOO_LARGE: String = "file_too_large"
    public static const MODEL_UNAVAILABLE: String = "model_unavailable"
    public static const MODEL_NOT_AVAILABLE: String = "model_not_available"
    public static const UNSUPPORTED_BASE: String = "unsupported_base"
    public static const ENVIRONMENT_NOT_FOUND: String = "environment_not_found"
    public static const ENVIRONMENT_NOT_READY: String = "environment_not_ready"
    public static const ENVIRONMENT_BUSY: String = "environment_busy"
    public static const ENVIRONMENT_EXISTS: String = "environment_exists"
    public static const ENVIRONMENT_INVALID: String = "environment_invalid"
    public static const ENVIRONMENT_UNAVAILABLE: String = "environment_unavailable"
    public static const MEMORY_NOT_FOUND: String = "memory_not_found"
    public static const MEMORY_FORBIDDEN: String = "memory_forbidden"
    public static const MEMORY_RECORD_NOT_FOUND: String = "memory_record_not_found"
    public static const MEMORIES_NOT_ATTACHED: String = "memories_not_attached"
    public static const MEMORY_INVALID: String = "memory_invalid"
    public static const MEMORY_UNSUPPORTED: String = "memory_unsupported"
    public static const MEMORY_BUSY: String = "memory_busy"
    public static const MEMORY_UNAVAILABLE: String = "memory_unavailable"
    public static const PLUGIN_INVALID: String = "plugin_invalid"
    public static const UNSUPPORTED_PLUGIN_SCHEMA: String = "unsupported_plugin_schema"
    public static const UNSUPPORTED_TRANSPORT: String = "unsupported_transport"
    // §3.2 认证与限额
    public static const MISSING_CREDENTIAL: String = "missing_credential"
    public static const INVALID_CREDENTIAL: String = "invalid_credential"
    public static const INSUFFICIENT_SCOPE: String = "insufficient_scope"
    public static const RATE_LIMITED: String = "rate_limited"
    public static const QUOTA_EXHAUSTED: String = "quota_exhausted"
    // §3.3 执行（前四个出现在 failed/cancelled 响应里，HTTP 200）
    public static const HARNESS_ERROR: String = "harness_error"
    public static const HARNESS_UNAVAILABLE: String = "harness_unavailable"
    public static const PROVIDER_ERROR: String = "provider_error"
    public static const TIMEOUT: String = "timeout"
    public static const CANCELLED: String = "cancelled"
    public static const PREVIEW_UNAVAILABLE: String = "preview_unavailable"
    public static const PREVIEW_FAILED: String = "preview_failed"
}

// §3 两张表（请求/路由 + 认证/限额 + 执行）的机器可读形式：码 -> (状态, type, 重试)。
// 顺序与规范正文一致，便于逐行对照。
let ERROR_CODE_SPECS: Array<(String, Int64, ErrorType, RetryAdvice)> = [
    // §3.1 请求与路由
    (ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION, 400, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.INVALID_INPUT, 400, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.HARNESS_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.RESPONSE_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.SESSION_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.PLUGIN_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.FILE_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.SESSION_EXPIRED, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.HARNESS_MISMATCH, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    // §4：session_busy 是唯一被点名「等在途任务终态后重试」的 invalid_request_error。
    (ErrorCodes.SESSION_BUSY, 409, ErrorType.InvalidRequestError, RetryAdvice.RetryWhenInFlightTaskTerminal),
    // 其余 *_busy（harness/environment/memory）虽然现实里也是暂时态，但 §4 的
    // 「Any other invalid_request_error → No」覆盖了它们，这里遵从规范不做自动重试。
    (ErrorCodes.HARNESS_BUSY, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.PLUGIN_CONFLICT, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.IDEMPOTENCY_KEY_REUSED, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.INPUT_NOT_PENDING, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.INPUT_REQUEST_EXPIRED, 410, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    // §4：换一个符合 kind/options 的答案可以再发。
    (ErrorCodes.INPUT_RESPONSE_INVALID, 422, ErrorType.InvalidRequestError, RetryAdvice.RetryWithCorrectedInput),
    (ErrorCodes.FILE_TOO_LARGE, 413, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MODEL_UNAVAILABLE, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MODEL_NOT_AVAILABLE, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.UNSUPPORTED_BASE, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_NOT_READY, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_BUSY, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_EXISTS, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_INVALID, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.ENVIRONMENT_UNAVAILABLE, 502, ErrorType.ServerError, RetryAdvice.RetryWithBackoff),
    (ErrorCodes.MEMORY_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORY_FORBIDDEN, 403, ErrorType.PermissionError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORY_RECORD_NOT_FOUND, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORIES_NOT_ATTACHED, 404, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORY_INVALID, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORY_UNSUPPORTED, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.MEMORY_BUSY, 409, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    // 规范写「502 或 503」；这里取 502，服务端两值都合法。
    (ErrorCodes.MEMORY_UNAVAILABLE, 502, ErrorType.ServerError, RetryAdvice.RetryWithBackoff),
    (ErrorCodes.PLUGIN_INVALID, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.UNSUPPORTED_PLUGIN_SCHEMA, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    (ErrorCodes.UNSUPPORTED_TRANSPORT, 422, ErrorType.InvalidRequestError, RetryAdvice.DoNotRetry),
    // §3.2 认证与限额
    (ErrorCodes.MISSING_CREDENTIAL, 401, ErrorType.AuthenticationError, RetryAdvice.DoNotRetry),
    (ErrorCodes.INVALID_CREDENTIAL, 401, ErrorType.AuthenticationError, RetryAdvice.DoNotRetry),
    (ErrorCodes.INSUFFICIENT_SCOPE, 403, ErrorType.PermissionError, RetryAdvice.DoNotRetry),
    (ErrorCodes.RATE_LIMITED, 429, ErrorType.RateLimitError, RetryAdvice.RetryAfterCooldown),
    (ErrorCodes.QUOTA_EXHAUSTED, 429, ErrorType.RateLimitError, RetryAdvice.DoNotRetry),
    // §3.3 执行：failed/cancelled 响应（HTTP 200），是否重跑由调用方判断。
    (ErrorCodes.HARNESS_ERROR, 200, ErrorType.HarnessError, RetryAdvice.CallerJudgment),
    (ErrorCodes.HARNESS_UNAVAILABLE, 503, ErrorType.ServerError, RetryAdvice.RetryWithBackoff),
    (ErrorCodes.PROVIDER_ERROR, 200, ErrorType.HarnessError, RetryAdvice.CallerJudgment),
    (ErrorCodes.TIMEOUT, 200, ErrorType.HarnessError, RetryAdvice.CallerJudgment),
    (ErrorCodes.CANCELLED, 200, ErrorType.HarnessError, RetryAdvice.CallerJudgment),
    // 501 不在 §2 的 server_error 状态组里（那组是 500/502/503/504）；「本服务不渲染
    // 预览」重试也不会变，故 type 归 server_error（服务端能力缺失）但重试建议为否。
    (ErrorCodes.PREVIEW_UNAVAILABLE, 501, ErrorType.ServerError, RetryAdvice.DoNotRetry),
    (ErrorCodes.PREVIEW_FAILED, 502, ErrorType.ServerError, RetryAdvice.RetryWithBackoff)
]

func buildErrorCodeTable(): HashMap<String, ErrorCodeSpec> {
    let table = HashMap<String, ErrorCodeSpec>()
    for ((code, status, t, advice) in ERROR_CODE_SPECS) {
        table[code] = ErrorCodeSpec(status, t, advice)
    }
    return table
}

let ERROR_CODE_TABLE: HashMap<String, ErrorCodeSpec> = buildErrorCodeTable()

// 规范码查表；未知（含厂商自定义码）返回 None。
public func errorCodeSpec(code: String): Option<ErrorCodeSpec> {
    return ERROR_CODE_TABLE.get(code)
}

public func isKnownErrorCode(code: String): Bool {
    return ERROR_CODE_TABLE.contains(code)
}

// §3 全部规范码（顺序即规范正文顺序）。
public func allErrorCodes(): Array<String> {
    let out = ArrayList<String>()
    for ((code, status, t, advice) in ERROR_CODE_SPECS) {
        out.add(code)
    }
    return out.toArray()
}

// 由 code 反推规范规定的 type / HTTP 状态（服务端构造错误信封时用）。
public func errorTypeOfCode(code: String): Option<ErrorType> {
    match (errorCodeSpec(code)) {
        case Some(spec) => return Some(spec.errorType)
        case None => return None
    }
}

public func httpStatusOfCode(code: String): Option<Int64> {
    match (errorCodeSpec(code)) {
        case Some(spec) => return Some(spec.httpStatus)
        case None => return None
    }
}

// ---------- 错误信封 ----------

// 错误对象本身（Errors §1 的 error 成员）。值语义的线上形态是 ErrorResponse。
//
// param 是出问题字段的 dotted path（没有则为 null）；detail 是开放对象——这里保留
// **原始 JSON 文本**（契约：合法 JSON），写入走 JsonWriter.jsonValue，因此内层结构
// 不丢，也不需要为它建 DOM。
public class ErrorEnvelope <: JsonSerializable & JsonDeserializable<ErrorEnvelope> {
    // 字段名是 errorType 而不是 type：type 是仓颉关键字（线上 JSON 键仍是 "type"）。
    public var errorType: ErrorType = ErrorType.ServerError
    public var code: String = ""
    public var message: String = ""
    public var param: Option<String> = None
    public var detail: Option<String> = None
    // 未知字段：保真回写（协议所有对象节点都是开放的）。
    public var extras: Extras = newExtras()

    // 无参构造供 fromJson 逐字段填充。
    public init() {}

    // 本地构造：message 在这里统一 sanitize（§1：MUST 安全可展示）。
    // 之后若直接改 this.message，展示前请再调 sanitizedMessage()。
    public init(errorType: ErrorType, code: String, message: String, param!: Option<String> = None, detail!: Option<String> = None) {
        this.errorType = errorType
        this.code = code
        this.message = sanitizeErrorMessage(message)
        this.param = param
        this.detail = detail
    }

    // 展示前的兜底：幂等（干净消息原样返回）。
    public func sanitizedMessage(): String {
        return sanitizeErrorMessage(this.message)
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(errorTypeName(this.errorType))
        w.writeName("code").writeValue(this.code)
        w.writeName("message").writeValue(this.message)
        match (this.param) {
            case Some(v) => w.writeName("param").writeValue(v)
            case None => w.writeName("param").writeNullValue()
        }
        match (this.detail) {
            case Some(v) => w.writeName("detail").jsonValue(v)
            case None => w.writeName("detail").writeNullValue()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ErrorEnvelope {
        let res = ErrorEnvelope()
        let seen = HashMap<String, Bool>()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => readEnvelopeType(r, res, seen) }),
                ("code", { => readEnvelopeCode(r, res, seen) }),
                ("message", { => readEnvelopeMessage(r, res, seen) }),
                ("param", { => res.param = readNullableString(r) }),
                ("detail", { => res.detail = readRawOrNone(r) })
            ],
            res.extras
        )
        requireErrorFields(seen, "错误信封")
        return res
    }
}

// §1 的线上响应体：{"error": {...}, "detail": "..."}。
// 顶层 detail 是给旧实现的弃用别名（字符串），保留原样但不解释（§1 Compatibility note）。
public class ErrorResponse <: JsonSerializable & JsonDeserializable<ErrorResponse> {
    public var error: ErrorEnvelope = ErrorEnvelope()
    public var legacyDetail: Option<String> = None
    public var extras: Extras = newExtras()

    public init() {}

    public init(error: ErrorEnvelope) {
        this.error = error
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("error")
        this.error.toJson(w)
        match (this.legacyDetail) {
            case Some(v) => w.writeName("detail").writeValue(v)
            case None => ()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ErrorResponse {
        let res = ErrorResponse()
        let seen = HashMap<String, Bool>()
        fromJsonObjectWithExtras(
            r,
            [
                ("error", { => readResponseError(r, res, seen) }),
                ("detail", { => res.legacyDetail = readNullableString(r) })
            ],
            res.extras
        )
        if (!seen.contains("error")) {
            throw JsonProtocolException("错误响应缺少必填对象: error")
        }
        return res
    }
}

// 按 code 与 type 判定：已知码用码表里的精确状态，未知（厂商）码退回 type 的缺省状态。
public func httpStatusOf(e: ErrorEnvelope): Int64 {
    match (errorCodeSpec(e.code)) {
        case Some(spec) => return spec.httpStatus
        case None => return httpStatusOf(e.errorType)
    }
}

// 重试建议：先按具体 code 查 §4 表，未知码退回 type 的缺省策略。
public func retryAdvice(e: ErrorEnvelope): RetryAdvice {
    match (errorCodeSpec(e.code)) {
        case Some(spec) => return spec.retryAdvice
        case None => return defaultRetryAdvice(e.errorType)
    }
}

public func retryable(e: ErrorEnvelope): Bool {
    return isRetryableAdvice(retryAdvice(e))
}

// ---------- fromJson 辅助 ----------

func readEnvelopeType(r: JsonReader, res: ErrorEnvelope, seen: HashMap<String, Bool>): Unit {
    // 未知 type 由 parseErrorType 落到 Unknown(raw)，不中断解析、往返保真。
    res.errorType = parseErrorType(r.readValue<String>())
    seen["type"] = true
}

func readEnvelopeCode(r: JsonReader, res: ErrorEnvelope, seen: HashMap<String, Bool>): Unit {
    res.code = r.readValue<String>()
    seen["code"] = true
}

func readEnvelopeMessage(r: JsonReader, res: ErrorEnvelope, seen: HashMap<String, Bool>): Unit {
    // 反序列化入口同样 sanitize：服务端给的 message 不可信（可能就是一段栈）。
    res.message = sanitizeErrorMessage(r.readValue<String>())
    seen["message"] = true
}

func readResponseError(r: JsonReader, res: ErrorResponse, seen: HashMap<String, Bool>): Unit {
    res.error = ErrorEnvelope.fromJson(r)
    seen["error"] = true
}

func requireErrorFields(seen: HashMap<String, Bool>, what: String): Unit {
    for (k in ["type", "code", "message"]) {
        if (!seen.contains(k)) {
            throw JsonProtocolException(what + "缺少必填字段: " + k)
        }
    }
}

// param：string | null。缺失由调用方处理（键不存在时不调用本函数）。
func readNullableString(r: JsonReader): Option<String> {
    return match (r.peek()) {
        case Some(JsonNull) =>
            r.skip()
            None
        case Some(JsonString) => Some(r.readValue<String>())
        case Some(_) => throw JsonProtocolException("字段应为字符串或 null")
        case None => throw JsonProtocolException("JSON 提前结束，期望字符串或 null")
    }
}

// detail：开放对象。保留原始 JSON 文本（含嵌套结构），null 归一成 None。
func readRawOrNone(r: JsonReader): Option<String> {
    return match (r.peek()) {
        case Some(JsonNull) =>
            r.skip()
            None
        case Some(_) => Some(String.fromUtf8(r.readValueBytes()))
        case None => throw JsonProtocolException("JSON 提前结束，期望 JSON 值")
    }
}

// ---------- message sanitize ----------
//
// 契约：sanitize 后的 message 可安全展示——不含凭证、内部主机名、文件路径、栈。
// 实现不是通用 DLP：按词分类，覆盖规范点名的四类明显违规形态；宁可多遮蔽，
// 不追求逐字节保留（原样文本不在 ErrorEnvelope 里保存）。

let REDACTED = "<redacted>"
let REDACTED_URL = "<url>"
let REDACTED_HOST = "<host>"
let REDACTED_PATH = "<path>"

// 已知凭证头/键：词尾冒号视为「下一个词是值」。
let CREDENTIAL_HEADER_KEYS: Array<String> = [
    "authorization", "proxy-authorization", "cookie", "set-cookie",
    "token", "access_token", "refresh_token", "password", "passwd", "secret",
    "api_key", "apikey", "api-key", "x-api-key", "credential", "credentials"
]

// 凭证 token 的常见前缀；后面还需至少 8 个字符才判定为 token（避免误伤普通词）。
let CREDENTIAL_PREFIXES: Array<String> = [
    "sk-", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_", "xoxb-", "xoxp-", "akia"
]

let URL_PREFIXES: Array<String> = ["http://", "https://", "ws://", "wss://", "file://", "ftp://"]

// 只认明确的内网/本机后缀，避免把 "node.js" 这类普通词当主机名。
let INTERNAL_HOST_SUFFIXES: Array<String> = [".internal", ".local", ".localdomain", ".lan", ".corp", ".intranet"]

// key=value 中敏感键名的后缀（token= / api_key= / password= …）。
let CREDENTIAL_KEY_SUFFIXES: Array<String> = ["token", "key", "secret", "password", "credential"]

let ASCII_UPPER: Array<Rune> = [
    r'A', r'B', r'C', r'D', r'E', r'F', r'G', r'H', r'I', r'J', r'K', r'L', r'M',
    r'N', r'O', r'P', r'Q', r'R', r'S', r'T', r'U', r'V', r'W', r'X', r'Y', r'Z'
]

let ASCII_LOWER: Array<Rune> = [
    r'a', r'b', r'c', r'd', r'e', r'f', r'g', r'h', r'i', r'j', r'k', r'l', r'm',
    r'n', r'o', r'p', r'q', r'r', r's', r't', r'u', r'v', r'w', r'x', r'y', r'z'
]

public func sanitizeErrorMessage(raw: String): String {
    // 1) 只留第一行（栈/多行原始报错在这一步截断，§1「no stack trace」）；
    // 2) 按空白切词、压缩空白，逐词判定是否敏感。
    let words = splitMessageWords(raw.toRuneArray())
    let out = StringBuilder()
    var redactNext = false
    for (w in words) {
        let lower = toLowerRunes(w)
        var text = ""
        if (redactNext) {
            // 上一个词是凭证头，这个词就是值；Bearer 还会再带一个 token。
            text = REDACTED
            redactNext = isBearerWord(lower)
        } else {
            (text, redactNext) = classifyMessageWord(w, lower)
        }
        if (out.size > 0) {
            out.append(" ")
        }
        out.append(text)
    }
    return truncateRunes(out.toString(), MAX_ERROR_MESSAGE_RUNES)
}

// 返回：(这个词写出去的形式, 下一个词是否也要遮蔽)。
func classifyMessageWord(word: Array<Rune>, lower: Array<Rune>): (String, Bool) {
    if (isCredentialHeaderWord(lower)) {
        return (REDACTED, true)
    }
    if (isBearerWord(lower)) {
        return (REDACTED, true)
    }
    if (isCredentialWord(word, lower)) {
        return (REDACTED, false)
    }
    if (isUrlWord(lower)) {
        return (REDACTED_URL, false)
    }
    if (isIpv4Word(word)) {
        return (REDACTED_HOST, false)
    }
    if (isPathWord(word)) {
        return (REDACTED_PATH, false)
    }
    if (isInternalHostname(lower)) {
        return (REDACTED_HOST, false)
    }
    return (runesToString(word), false)
}

// 第一行 + 按空白切词（连续空白压缩成一个）。
func splitMessageWords(src: Array<Rune>): Array<Array<Rune>> {
    let words = ArrayList<Array<Rune>>()
    var i = 0
    while (i < src.size) {
        let r = src[i]
        if (r == r'\n' || r == r'\r') {
            break
        }
        if (r == r' ' || r == r'\t') {
            i = i + 1
            continue
        }
        var j = i
        while (j < src.size && src[j] != r' ' && src[j] != r'\t' && src[j] != r'\n' && src[j] != r'\r') {
            j = j + 1
        }
        words.add(sliceRunes(src, i, j))
        i = j
    }
    return words.toArray()
}

func isBearerWord(lower: Array<Rune>): Bool {
    return lower.size == 6 && runesToString(lower) == "bearer"
}

func isCredentialHeaderWord(lower: Array<Rune>): Bool {
    var end = lower.size
    if (end > 0 && lower[end - 1] == r':') {
        end = end - 1
    }
    return CREDENTIAL_HEADER_KEYS.contains(runesToString(sliceRunes(lower, 0, end)))
}

func isCredentialWord(word: Array<Rune>, lower: Array<Rune>): Bool {
    for (p in CREDENTIAL_PREFIXES) {
        if (runesStartsWith(lower, p) && word.size >= p.toRuneArray().size + 8) {
            return true
        }
    }
    match (indexOfRune(lower, r'=')) {
        case Some(eq) =>
            let key = sliceRunes(lower, 0, eq)
            for (suffix in CREDENTIAL_KEY_SUFFIXES) {
                if (runesEndsWith(key, suffix)) {
                    return true
                }
            }
            return false
        case None => return false
    }
}

func isUrlWord(lower: Array<Rune>): Bool {
    for (p in URL_PREFIXES) {
        if (runesStartsWith(lower, p)) {
            return true
        }
    }
    return false
}

// IPv4（可带 :port）。逐段判数字且长度 1–3；不要求 ≤255——遮蔽判定不需要精确值。
func isIpv4Word(word: Array<Rune>): Bool {
    var end = word.size
    match (indexOfRune(word, r':')) {
        case Some(colon) =>
            if (colon + 1 < end) {
                var portIsDigits = true
                for (k in (colon + 1)..end) {
                    if (!isDigitRune(word[k])) {
                        portIsDigits = false
                    }
                }
                if (portIsDigits) {
                    end = colon
                }
            }
        case None => ()
    }
    let parts = splitRunesBy(word, 0, end, r'.')
    if (parts.size != 4) {
        return false
    }
    for (p in parts) {
        if (p.size < 1 || p.size > 3) {
            return false
        }
        for (c in p) {
            if (!isDigitRune(c)) {
                return false
            }
        }
    }
    return true
}

// 文件路径：绝对路径 / 家目录 / Windows 盘符 / 带扩展名的相对路径。
// 纯相对目录（如 "src/types"）不误伤——错误文案里更需要它的可读性。
func isPathWord(word: Array<Rune>): Bool {
    if (word.size == 0) {
        return false
    }
    let first = word[0]
    if (first == r'/' || first == r'\\') {
        return true
    }
    if (first == r'~' && word.size >= 2 && word[1] == r'/') {
        return true
    }
    if (word.size >= 3 && isAsciiLetterRune(first) && word[1] == r':' && (word[2] == r'\\' || word[2] == r'/')) {
        return true
    }
    if (containsRune(word, r'/') || containsRune(word, r'\\')) {
        let last = lastPathSegment(word)
        return last.size >= 2 && containsRune(last, r'.')
    }
    return false
}

func isInternalHostname(lower: Array<Rune>): Bool {
    if (runesStartsWith(lower, "localhost")) {
        return true
    }
    for (suffix in INTERNAL_HOST_SUFFIXES) {
        if (runesEndsWith(lower, suffix)) {
            return true
        }
    }
    return false
}

func lastPathSegment(word: Array<Rune>): Array<Rune> {
    var start = 0
    var i = 0
    while (i < word.size) {
        if (word[i] == r'/' || word[i] == r'\\') {
            start = i + 1
        }
        i = i + 1
    }
    return sliceRunes(word, start, word.size)
}

// 按 Unicode 标量截断（String.size 是字节数，直接切会切坏汉字）。
func truncateRunes(s: String, max: Int64): String {
    let rs = s.toRuneArray()
    if (rs.size <= max) {
        return s
    }
    return runesToString(sliceRunes(rs, 0, max - 1)).trimAscii() + "…"
}

// ---------- rune 工具 ----------

func isDigitRune(r: Rune): Bool {
    return r >= r'0' && r <= r'9'
}

func isAsciiLetterRune(r: Rune): Bool {
    return (r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z')
}

func asciiLower(r: Rune): Rune {
    match (ASCII_UPPER.indexOf(r)) {
        case Some(i) => return ASCII_LOWER[i]
        case None => return r
    }
}

func toLowerRunes(rs: Array<Rune>): Array<Rune> {
    let out = ArrayList<Rune>()
    for (r in rs) {
        out.add(asciiLower(r))
    }
    return out.toArray()
}

func runesToString(rs: Array<Rune>): String {
    let sb = StringBuilder()
    for (r in rs) {
        sb.append(r)
    }
    return sb.toString()
}

func sliceRunes(src: Array<Rune>, from: Int64, to: Int64): Array<Rune> {
    let out = ArrayList<Rune>()
    var i = from
    while (i < to) {
        out.add(src[i])
        i = i + 1
    }
    return out.toArray()
}

func splitRunesBy(src: Array<Rune>, from: Int64, to: Int64, sep: Rune): Array<Array<Rune>> {
    let parts = ArrayList<Array<Rune>>()
    var start = from
    var i = from
    while (i < to) {
        if (src[i] == sep) {
            parts.add(sliceRunes(src, start, i))
            start = i + 1
        }
        i = i + 1
    }
    parts.add(sliceRunes(src, start, to))
    return parts.toArray()
}

func runesStartsWith(rs: Array<Rune>, prefix: String): Bool {
    let p = prefix.toRuneArray()
    if (rs.size < p.size) {
        return false
    }
    var i = 0
    while (i < p.size) {
        if (rs[i] != p[i]) {
            return false
        }
        i = i + 1
    }
    return true
}

func runesEndsWith(rs: Array<Rune>, suffix: String): Bool {
    let s = suffix.toRuneArray()
    if (rs.size < s.size) {
        return false
    }
    let offset = rs.size - s.size
    var i = 0
    while (i < s.size) {
        if (rs[offset + i] != s[i]) {
            return false
        }
        i = i + 1
    }
    return true
}

func indexOfRune(rs: Array<Rune>, target: Rune): Option<Int64> {
    var i = 0
    while (i < rs.size) {
        if (rs[i] == target) {
            return Some(i)
        }
        i = i + 1
    }
    return None
}

func containsRune(rs: Array<Rune>, target: Rune): Bool {
    return indexOfRune(rs, target).isSome()
}
