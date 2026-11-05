// 错误模型单测：§2 的 type→HTTP 映射、§3 的码表、§4 的重试表、往返保真、
// 可选字段缺省，以及 message sanitize 的接缝。
//
// 表驱动优先：规范是逐行表格，测试也逐行断言，规范换版本时改表即可。
package uhp.types.handwritten

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.codec.*

// 与 event_test.cj 同包：helper 名统一加 error 前缀，避免跨文件重名。

func errorRenderJson<T>(v: T): String where T <: JsonSerializable {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    v.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}

func errorParseJson<T>(s: String): T where T <: JsonDeserializable<T> {
    let r = JsonReader(ByteBuffer(s.toArray()))
    return T.fromJson(r)
}

func errorSpecStatus(code: String): Int64 {
    match (errorCodeSpec(code)) {
        case Some(spec) => return spec.httpStatus
        case None => return -1
    }
}

func errorCheckCode(code: String, status: Int64, t: ErrorType): Unit {
    @Expect(errorSpecStatus(code), status)
    @Expect(httpStatusOfCode(code) ?? -1, status)
    match (errorTypeOfCode(code)) {
        case Some(actual) => @Expect(errorTypeName(actual), errorTypeName(t))
        case None => @Expect(false, true)
    }
}

func errorExpectAdvice(typeName: String, code: String, expected: RetryAdvice, canRetry: Bool): Unit {
    let env = ErrorEnvelope(parseErrorType(typeName), code, "test message")
    @Expect(retryAdviceName(retryAdvice(env)), retryAdviceName(expected))
    @Expect(retryable(env), canRetry)
}

// ---------- §2 type → HTTP ----------

@Test
func error_http_status_mapping(): Unit {
    errorCheckStatuses(ErrorType.InvalidRequestError, [400, 404, 409, 410, 413, 422], 400)
    errorCheckStatuses(ErrorType.AuthenticationError, [401], 401)
    errorCheckStatuses(ErrorType.PermissionError, [403], 403)
    errorCheckStatuses(ErrorType.RateLimitError, [429], 429)
    // harness_error 是「HTTP 200 的 failed 响应」，不是非 2xx。
    errorCheckStatuses(ErrorType.HarnessError, [200], 200)
    errorCheckStatuses(ErrorType.ServerError, [500, 502, 503, 504], 500)
}

func errorCheckStatuses(t: ErrorType, expected: Array<Int64>, canonical: Int64): Unit {
    let actual = httpStatusesOf(t)
    @Expect(actual.size, expected.size)
    for (s in expected) {
        @Expect(actual.contains(s), true)
    }
    @Expect(httpStatusOf(t), canonical)
}

@Test
func error_type_name_roundtrip(): Unit {
    let all = [
        ErrorType.InvalidRequestError, ErrorType.AuthenticationError, ErrorType.PermissionError,
        ErrorType.RateLimitError, ErrorType.HarnessError, ErrorType.ServerError
    ]
    for (t in all) {
        let name = errorTypeName(t)
        @Expect(errorTypeName(parseErrorType(name)), name)
    }
    // 未知 type 不允许 panic，也不允许被改写成某个已知值（仓内：未知枚举值必须有兜底）。
    let unknown = parseErrorType("future_error")
    @Expect(errorTypeName(unknown), "future_error")
    @Expect(httpStatusesOf(unknown).size, 0)
}

// ---------- §3 码表 ----------

@Test
func error_code_table_is_complete(): Unit {
    let codes = allErrorCodes()
    // §3.1 37 + §3.2 5 + §3.3 7 = 49
    @Expect(codes.size, 49)
    for (code in codes) {
        @Expect(isKnownErrorCode(code), true)
        @Expect(errorCodeSpec(code).isSome(), true)
    }
    // 厂商自定义码不在表里，但必须能被当作「未知码」处理。
    @Expect(isKnownErrorCode("acme_vendor_code"), false)
    @Expect(errorCodeSpec("acme_vendor_code").isNone(), true)
    @Expect(httpStatusOfCode("acme_vendor_code").isNone(), true)
    @Expect(errorTypeOfCode("acme_vendor_code").isNone(), true)
    // 常量与码表一致（防止常量笔误与表脱节）。
    @Expect(isKnownErrorCode(ErrorCodes.HARNESS_NOT_FOUND), true)
    @Expect(isKnownErrorCode(ErrorCodes.SESSION_BUSY), true)
    @Expect(isKnownErrorCode(ErrorCodes.PREVIEW_FAILED), true)
}

@Test
func error_code_status_and_type(): Unit {
    errorCheckCode(ErrorCodes.HARNESS_NOT_FOUND, 404, ErrorType.InvalidRequestError)
    errorCheckCode(ErrorCodes.INPUT_REQUEST_EXPIRED, 410, ErrorType.InvalidRequestError)
    errorCheckCode(ErrorCodes.FILE_TOO_LARGE, 413, ErrorType.InvalidRequestError)
    errorCheckCode(ErrorCodes.HARNESS_MISMATCH, 409, ErrorType.InvalidRequestError)
    errorCheckCode(ErrorCodes.MISSING_CREDENTIAL, 401, ErrorType.AuthenticationError)
    errorCheckCode(ErrorCodes.INSUFFICIENT_SCOPE, 403, ErrorType.PermissionError)
    errorCheckCode(ErrorCodes.MEMORY_FORBIDDEN, 403, ErrorType.PermissionError)
    errorCheckCode(ErrorCodes.RATE_LIMITED, 429, ErrorType.RateLimitError)
    errorCheckCode(ErrorCodes.HARNESS_UNAVAILABLE, 503, ErrorType.ServerError)
    errorCheckCode(ErrorCodes.ENVIRONMENT_UNAVAILABLE, 502, ErrorType.ServerError)
    errorCheckCode(ErrorCodes.MEMORY_UNAVAILABLE, 502, ErrorType.ServerError)
    // 501 不在 §2 的 server_error 状态组里，但服务端能力缺失仍归 server_error。
    errorCheckCode(ErrorCodes.PREVIEW_UNAVAILABLE, 501, ErrorType.ServerError)
    // failed 响应里的码：HTTP 200 + harness_error。
    errorCheckCode(ErrorCodes.HARNESS_ERROR, 200, ErrorType.HarnessError)
    errorCheckCode(ErrorCodes.PROVIDER_ERROR, 200, ErrorType.HarnessError)
    errorCheckCode(ErrorCodes.TIMEOUT, 200, ErrorType.HarnessError)
    errorCheckCode(ErrorCodes.CANCELLED, 200, ErrorType.HarnessError)
}

// ---------- §4 重试表 ----------

@Test
func error_retry_table_key_branches(): Unit {
    // server_error：指数退避 + 抖动后重试。
    errorExpectAdvice("server_error", ErrorCodes.HARNESS_UNAVAILABLE, RetryAdvice.RetryWithBackoff, true)
    errorExpectAdvice("server_error", ErrorCodes.ENVIRONMENT_UNAVAILABLE, RetryAdvice.RetryWithBackoff, true)
    // rate_limited：等 Retry-After。
    errorExpectAdvice("rate_limit_error", ErrorCodes.RATE_LIMITED, RetryAdvice.RetryAfterCooldown, true)
    // quota_exhausted：配额不变就重试无用。
    errorExpectAdvice("rate_limit_error", ErrorCodes.QUOTA_EXHAUSTED, RetryAdvice.DoNotRetry, false)
    // session_busy：等在途任务到终态。
    errorExpectAdvice("invalid_request_error", ErrorCodes.SESSION_BUSY, RetryAdvice.RetryWhenInFlightTaskTerminal, true)
    // input_response_invalid：换一个合规答案再发。
    errorExpectAdvice("invalid_request_error", ErrorCodes.INPUT_RESPONSE_INVALID, RetryAdvice.RetryWithCorrectedInput, true)
    // input_request_expired：问题已消失，只能发新任务。
    errorExpectAdvice("invalid_request_error", ErrorCodes.INPUT_REQUEST_EXPIRED, RetryAdvice.DoNotRetry, false)
    // 其它 invalid_request_error：改请求，不是重试。
    errorExpectAdvice("invalid_request_error", ErrorCodes.INVALID_INPUT, RetryAdvice.DoNotRetry, false)
    errorExpectAdvice("invalid_request_error", ErrorCodes.FILE_TOO_LARGE, RetryAdvice.DoNotRetry, false)
    // 认证 / 权限：改凭证或改授权。
    errorExpectAdvice("authentication_error", ErrorCodes.MISSING_CREDENTIAL, RetryAdvice.DoNotRetry, false)
    errorExpectAdvice("authentication_error", ErrorCodes.INVALID_CREDENTIAL, RetryAdvice.DoNotRetry, false)
    errorExpectAdvice("permission_error", ErrorCodes.INSUFFICIENT_SCOPE, RetryAdvice.DoNotRetry, false)
    // failed 响应（HTTP 200）：任务消耗了真实资源，由调用方判断。
    errorExpectAdvice("harness_error", ErrorCodes.HARNESS_ERROR, RetryAdvice.CallerJudgment, false)
    errorExpectAdvice("harness_error", ErrorCodes.PROVIDER_ERROR, RetryAdvice.CallerJudgment, false)
    errorExpectAdvice("harness_error", ErrorCodes.TIMEOUT, RetryAdvice.CallerJudgment, false)
    // 501：本服务不渲染预览，重试不会变。
    errorExpectAdvice("server_error", ErrorCodes.PREVIEW_UNAVAILABLE, RetryAdvice.DoNotRetry, false)
}

@Test
func error_retry_unknown_code_falls_back_to_type(): Unit {
    // 未知厂商码：按 §4 的 type 行给缺省策略。
    errorExpectAdvice("server_error", "acme_backend_melting", RetryAdvice.RetryWithBackoff, true)
    errorExpectAdvice("rate_limit_error", "acme_slow_down", RetryAdvice.RetryAfterCooldown, true)
    errorExpectAdvice("invalid_request_error", "acme_bad_field", RetryAdvice.DoNotRetry, false)
    errorExpectAdvice("authentication_error", "acme_bad_token", RetryAdvice.DoNotRetry, false)
    errorExpectAdvice("harness_error", "acme_agent_gave_up", RetryAdvice.CallerJudgment, false)
    // 未知 type 保守处理：不自动重试。
    errorExpectAdvice("future_error", "acme_future", RetryAdvice.DoNotRetry, false)
}

// ---------- 信封：往返保真与可选字段 ----------

@Test
func error_envelope_roundtrip_preserves_unknown_fields(): Unit {
    let src = "{\"type\":\"invalid_request_error\",\"code\":\"harness_not_found\",\"message\":\"No harness with id 'chrn_deadbeef'.\",\"param\":\"metadata.harness_id\",\"detail\":{\"max_bytes\":42},\"request_id\":\"req_abc\"}"
    let env = errorParseJson<ErrorEnvelope>(src)
    @Expect(errorTypeName(env.errorType), "invalid_request_error")
    @Expect(env.code, "harness_not_found")
    @Expect(env.param ?? "", "metadata.harness_id")
    @Expect(env.detail.isSome(), true)
    @Expect(env.extras.contains("request_id"), true)
    let out = errorRenderJson<ErrorEnvelope>(env)
    // detail 与未知字段都按原始 JSON 回写，没有丢结构。
    @Expect(out.count("max_bytes") >= 1, true)
    @Expect(out.count("req_abc") >= 1, true)
    let again = errorParseJson<ErrorEnvelope>(out)
    @Expect(again.extras["request_id"] == env.extras["request_id"], true)
    @Expect(again.detail ?? "", env.detail ?? "")
    @Expect(again.param ?? "", env.param ?? "")
}

@Test
func error_envelope_missing_optional_fields_written_as_null(): Unit {
    // param/detail 缺失 = null（§1 要求键存在，值可为 null）。
    let env = errorParseJson<ErrorEnvelope>("{\"type\":\"server_error\",\"code\":\"harness_unavailable\",\"message\":\"try later\"}")
    @Expect(env.param.isNone(), true)
    @Expect(env.detail.isNone(), true)
    let out = errorRenderJson<ErrorEnvelope>(env)
    @Expect(out.count("\"param\":null") >= 1, true)
    @Expect(out.count("\"detail\":null") >= 1, true)
    @Expect(out.count("\"type\":\"server_error\"") >= 1, true)
}

@Test
func error_envelope_explicit_nulls_parse_as_absent(): Unit {
    let env = errorParseJson<ErrorEnvelope>("{\"type\":\"rate_limit_error\",\"code\":\"rate_limited\",\"message\":\"slow down\",\"param\":null,\"detail\":null}")
    @Expect(env.param.isNone(), true)
    @Expect(env.detail.isNone(), true)
    @Expect(env.code, "rate_limited")
}

@Test
func error_envelope_unknown_code_does_not_crash(): Unit {
    let env = errorParseJson<ErrorEnvelope>("{\"type\":\"server_error\",\"code\":\"acme_backend_melting\",\"message\":\"backend melting\"}")
    @Expect(env.code, "acme_backend_melting")
    // 未知码：状态/重试都退回 type 的缺省策略。
    @Expect(httpStatusOf(env), 500)
    @Expect(retryable(env), true)
    // 往返仍保留厂商码。
    let out = errorRenderJson<ErrorEnvelope>(env)
    @Expect(out.count("acme_backend_melting") >= 1, true)
}

@Test
func error_envelope_unknown_type_roundtrips(): Unit {
    let env = errorParseJson<ErrorEnvelope>("{\"type\":\"future_error\",\"code\":\"acme_future\",\"message\":\"from the future\"}")
    @Expect(errorTypeName(env.errorType), "future_error")
    let out = errorRenderJson<ErrorEnvelope>(env)
    @Expect(out.count("\"type\":\"future_error\"") >= 1, true)
    // 未知 type 不 panic、不自动重试。
    @Expect(retryable(env), false)
}

@Test
func error_envelope_missing_required_field_throws(): Unit {
    // §1：type/code/message 必填，缺失是协议错误而不是「可忽略」。
    var thrown = false
    try {
        let env = errorParseJson<ErrorEnvelope>("{\"type\":\"server_error\",\"code\":\"harness_unavailable\"}")
        @Expect(env.code.size, 0)
    } catch (e: JsonProtocolException) {
        thrown = true
    }
    @Expect(thrown, true)
}

@Test
func error_envelope_http_status_uses_code(): Unit {
    // 同一个 invalid_request_error 下，具体码决定精确状态。
    let tooLarge = errorParseJson<ErrorEnvelope>("{\"type\":\"invalid_request_error\",\"code\":\"file_too_large\",\"message\":\"too big\",\"param\":null,\"detail\":null}")
    @Expect(httpStatusOf(tooLarge), 413)
    // 未知码退回 type 的缺省状态。
    let vendor = ErrorEnvelope(ErrorType.RateLimitError, "acme_throttle", "slow down")
    @Expect(httpStatusOf(vendor), 429)
}

// ---------- 线上响应体 ----------

@Test
func error_response_wrapper_roundtrip(): Unit {
    let src = "{\"error\":{\"type\":\"rate_limit_error\",\"code\":\"rate_limited\",\"message\":\"slow down\",\"param\":null,\"detail\":{\"retry_after_ms\":1000}},\"detail\":\"slow down\",\"trace_id\":\"t-1\"}"
    let resp = errorParseJson<ErrorResponse>(src)
    @Expect(resp.error.code, "rate_limited")
    // 顶层 detail 是弃用别名：保留原样，不作为语义来源。
    @Expect(resp.legacyDetail ?? "", "slow down")
    @Expect(resp.extras.contains("trace_id"), true)
    let out = errorRenderJson<ErrorResponse>(resp)
    @Expect(out.count("\"error\"") >= 1, true)
    @Expect(out.count("retry_after_ms") >= 1, true)
    @Expect(out.count("trace_id") >= 1, true)
    let again = errorParseJson<ErrorResponse>(out)
    @Expect(again.error.code, "rate_limited")
    @Expect(again.extras["trace_id"] == resp.extras["trace_id"], true)
}

@Test
func error_response_without_error_throws(): Unit {
    var thrown = false
    try {
        let resp = errorParseJson<ErrorResponse>("{\"detail\":\"oops\"}")
        @Expect(resp.legacyDetail ?? "", "unreachable")
    } catch (e: JsonProtocolException) {
        thrown = true
    }
    @Expect(thrown, true)
}

// ---------- message sanitize ----------

@Test
func error_sanitize_keeps_clean_message(): Unit {
    let msg = "No harness with id 'chrn_deadbeef'."
    @Expect(sanitizeErrorMessage(msg), msg)
    // 幂等：重复 sanitize 不再变化。
    @Expect(sanitizeErrorMessage(sanitizeErrorMessage(msg)), msg)
}

@Test
func error_sanitize_drops_stack_trace(): Unit {
    // 多行 = 栈/上游原始报错，只保留第一句。
    let msg = "harness crashed\n    at Acme.run (/home/ystyle/work/acme.cj:42)"
    let out = sanitizeErrorMessage(msg)
    @Expect(out, "harness crashed")
    @Expect(out.count("\n") == 0, true)
}

@Test
func error_sanitize_redacts_credentials(): Unit {
    let msg = "auth failed: Bearer sk-live-9f8e7d6c token=abc123secret"
    let out = sanitizeErrorMessage(msg)
    @Expect(out.count("sk-live-9f8e7d6c") == 0, true)
    @Expect(out.count("abc123secret") == 0, true)
    @Expect(out.count("<redacted>") >= 1, true)
    // 非敏感部分保留，message 仍然可读。
    @Expect(out.count("auth failed:") >= 1, true)
}

@Test
func error_sanitize_redacts_paths_and_hosts(): Unit {
    let msg = "failed to read /home/ystyle/secret/config.cj via http://10.0.0.5:8080/v1/x and 192.168.3.6"
    let out = sanitizeErrorMessage(msg)
    @Expect(out.count("/home/") == 0, true)
    @Expect(out.count("10.0.0.5") == 0, true)
    @Expect(out.count("192.168.3.6") == 0, true)
    @Expect(out.count("<path>") >= 1, true)
    @Expect(out.count("<url>") >= 1, true)
    @Expect(out.count("<host>") >= 1, true)
    // Windows 盘符路径与内网主机名同样遮蔽。
    let win = sanitizeErrorMessage("cannot open C:\\Users\\alice\\keys.txt on db.internal")
    @Expect(win.count("alice") == 0, true)
    @Expect(win.count("db.internal") == 0, true)
}

@Test
func error_sanitize_truncates_by_runes(): Unit {
    // String.size 是字节数；截断必须按 Unicode 标量，不能切坏汉字。
    let sb = StringBuilder()
    for (i in 0..600) {
        sb.append("错")
    }
    let out = sanitizeErrorMessage(sb.toString())
    let len = out.toRuneArray().size
    @Expect(len <= MAX_ERROR_MESSAGE_RUNES, true)
    @Expect(len > MAX_ERROR_MESSAGE_RUNES - 8, true)
}

@Test
func error_constructor_and_fromjson_both_sanitize(): Unit {
    // 本地构造入口 sanitize。
    let built = ErrorEnvelope(ErrorType.ServerError, ErrorCodes.HARNESS_UNAVAILABLE, "boom\n    at Acme.run (/tmp/acme.cj:1)")
    @Expect(built.message, "boom")
    @Expect(built.sanitizedMessage(), "boom")
    // 反序列化入口也 sanitize：服务端给的 message 不可信。
    let parsed = errorParseJson<ErrorEnvelope>("{\"type\":\"server_error\",\"code\":\"harness_unavailable\",\"message\":\"boom\\n    at Acme.run (/tmp/acme.cj:1)\"}")
    @Expect(parsed.message, "boom")
}
