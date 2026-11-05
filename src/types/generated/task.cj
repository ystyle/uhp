// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class Annotation <: JsonSerializable & JsonDeserializable<Annotation> {
    public var typeName: String = ""
    public var container_id: Option<String> = None
    public var file_id: Option<String> = None
    public var filename: Option<String> = None
    public var download_url: Option<String> = None
    public var start_index: Option<Int64> = None
    public var end_index: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.container_id) {
                        w.writeName("container_id").writeValue(v)
        }
        if (let Some(v) <- this.file_id) {
                        w.writeName("file_id").writeValue(v)
        }
        if (let Some(v) <- this.filename) {
                        w.writeName("filename").writeValue(v)
        }
        if (let Some(v) <- this.download_url) {
                        w.writeName("download_url").writeValue(v)
        }
        if (let Some(v) <- this.start_index) {
                        w.writeName("start_index").writeValue(v)
        }
        if (let Some(v) <- this.end_index) {
                        w.writeName("end_index").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Annotation {
        let res = Annotation()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("container_id", { => res.container_id = r.readValue<Option<String>>() }),
                ("file_id", { => res.file_id = r.readValue<Option<String>>() }),
                ("filename", { => res.filename = r.readValue<Option<String>>() }),
                ("download_url", { => res.download_url = r.readValue<Option<String>>() }),
                ("start_index", { => res.start_index = r.readValue<Option<Int64>>() }),
                ("end_index", { => res.end_index = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class ContentPart <: JsonSerializable & JsonDeserializable<ContentPart> {
    public var typeName: String = ""
    public var text: Option<String> = None
    public var annotations: Option<Array<Annotation>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.text) {
                        w.writeName("text").writeValue(v)
        }
        if (let Some(v) <- this.annotations) {
                        w.writeName("annotations"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ContentPart {
        let res = ContentPart()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("text", { => res.text = r.readValue<Option<String>>() }),
                ("annotations", { => res.annotations = r.readValue<Option<Array<Annotation>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class CreateResponseRequestMetadata <: JsonSerializable & JsonDeserializable<CreateResponseRequestMetadata> {
    public var harness_id: Option<String> = None
    public var environment: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.harness_id) {
                        w.writeName("harness_id").writeValue(v)
        }
        if (let Some(v) <- this.environment) {
                        w.writeName("environment").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): CreateResponseRequestMetadata {
        let res = CreateResponseRequestMetadata()
        fromJsonObjectWithExtras(
            r,
            [
                ("harness_id", { => res.harness_id = r.readValue<Option<String>>() }),
                ("environment", { => res.environment = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class CreateResponseRequest <: JsonSerializable & JsonDeserializable<CreateResponseRequest> {
    public var input: Raw = ""
    public var model: Option<String> = None
    public var metadata: Option<CreateResponseRequestMetadata> = None
    public var stream: Option<Bool> = None
    public var previous_response_id: Option<Raw> = None
    public var instructions: Option<String> = None
    public var store: Option<Bool> = None
    public var max_output_tokens: Option<Raw> = None
    public var max_step: Option<Raw> = None
    public var timeout_seconds: Option<Raw> = None
    public var tools: Option<Array<Raw>> = None
    public var include: Option<Array<String>> = None
    public var background: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("input").jsonValue(this.input)
        if (let Some(v) <- this.model) {
                        w.writeName("model").writeValue(v)
        }
        if (let Some(v) <- this.metadata) {
                        w.writeName("metadata"); v.toJson(w)
        }
        if (let Some(v) <- this.stream) {
                        w.writeName("stream").writeValue(v)
        }
        if (let Some(v) <- this.previous_response_id) {
                        w.writeName("previous_response_id").jsonValue(v)
        }
        if (let Some(v) <- this.instructions) {
                        w.writeName("instructions").writeValue(v)
        }
        if (let Some(v) <- this.store) {
                        w.writeName("store").writeValue(v)
        }
        if (let Some(v) <- this.max_output_tokens) {
                        w.writeName("max_output_tokens").jsonValue(v)
        }
        if (let Some(v) <- this.max_step) {
                        w.writeName("max_step").jsonValue(v)
        }
        if (let Some(v) <- this.timeout_seconds) {
                        w.writeName("timeout_seconds").jsonValue(v)
        }
        if (let Some(v) <- this.tools) {
                        w.writeName("tools").writeValue(v)
        }
        if (let Some(v) <- this.include) {
                        w.writeName("include").writeValue(v)
        }
        if (let Some(v) <- this.background) {
                        w.writeName("background").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): CreateResponseRequest {
        let res = CreateResponseRequest()
        fromJsonObjectWithExtras(
            r,
            [
                ("input", { => res.input = readRaw(r) }),
                ("model", { => res.model = r.readValue<Option<String>>() }),
                ("metadata", { => res.metadata = r.readValue<Option<CreateResponseRequestMetadata>>() }),
                ("stream", { => res.stream = r.readValue<Option<Bool>>() }),
                ("previous_response_id", { => res.previous_response_id = readRaw(r) }),
                ("instructions", { => res.instructions = r.readValue<Option<String>>() }),
                ("store", { => res.store = r.readValue<Option<Bool>>() }),
                ("max_output_tokens", { => res.max_output_tokens = readRaw(r) }),
                ("max_step", { => res.max_step = readRaw(r) }),
                ("timeout_seconds", { => res.timeout_seconds = readRaw(r) }),
                ("tools", { => res.tools = r.readValue<Option<Array<Raw>>>() }),
                ("include", { => res.include = r.readValue<Option<Array<String>>>() }),
                ("background", { => res.background = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class ErrorObject <: JsonSerializable & JsonDeserializable<ErrorObject> {
    public var typeName: String = ""
    public var code: String = ""
    public var message: String = ""
    public var param: Option<Raw> = None
    public var detail: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
                w.writeName("code").writeValue(this.code)
                w.writeName("message").writeValue(this.message)
        if (let Some(v) <- this.param) {
                        w.writeName("param").jsonValue(v)
        } else {
            w.writeName("param").writeNullValue()
        }
        if (let Some(v) <- this.detail) {
                        w.writeName("detail").jsonValue(v)
        } else {
            w.writeName("detail").writeNullValue()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ErrorObject {
        let res = ErrorObject()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("code", { => res.code = r.readValue<String>() }),
                ("message", { => res.message = r.readValue<String>() }),
                ("param", { => res.param = readRaw(r) }),
                ("detail", { => res.detail = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class ErrorEnvelope <: JsonSerializable & JsonDeserializable<ErrorEnvelope> {
    public var error: ErrorObject = ErrorObject()
    public var detail: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("error"); this.error.toJson(w)
        if (let Some(v) <- this.detail) {
                        w.writeName("detail").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ErrorEnvelope {
        let res = ErrorEnvelope()
        fromJsonObjectWithExtras(
            r,
            [
                ("error", { => res.error = r.readValue<ErrorObject>() }),
                ("detail", { => res.detail = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class InputResponse <: JsonSerializable & JsonDeserializable<InputResponse> {
    public var typeName: String = ""
    public var input_request_id: String = ""
    public var answer: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
                w.writeName("input_request_id").writeValue(this.input_request_id)
                w.writeName("answer").writeValue(this.answer)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): InputResponse {
        let res = InputResponse()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("input_request_id", { => res.input_request_id = r.readValue<String>() }),
                ("answer", { => res.answer = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class OutputItemOptions <: JsonSerializable & JsonDeserializable<OutputItemOptions> {
    public var id: String = ""
    public var label: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
                w.writeName("label").writeValue(this.label)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): OutputItemOptions {
        let res = OutputItemOptions()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("label", { => res.label = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class OutputItem <: JsonSerializable & JsonDeserializable<OutputItem> {
    public var id: Option<String> = None
    public var typeName: String = ""
    public var status: Option<String> = None
    public var role: Option<String> = None
    public var content: Option<Array<ContentPart>> = None
    public var summary: Option<Array<Raw>> = None
    public var call_id: Option<String> = None
    public var name: Option<String> = None
    public var arguments: Option<String> = None
    public var output: Option<String> = None
    public var kind: Option<String> = None
    public var prompt: Option<String> = None
    public var options: Option<Array<OutputItemOptions>> = None
    public var expires_at: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.id) {
                        w.writeName("id").writeValue(v)
        }
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.status) {
                        w.writeName("status").writeValue(v)
        }
        if (let Some(v) <- this.role) {
                        w.writeName("role").writeValue(v)
        }
        if (let Some(v) <- this.content) {
                        w.writeName("content"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.summary) {
                        w.writeName("summary").writeValue(v)
        }
        if (let Some(v) <- this.call_id) {
                        w.writeName("call_id").writeValue(v)
        }
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.arguments) {
                        w.writeName("arguments").writeValue(v)
        }
        if (let Some(v) <- this.output) {
                        w.writeName("output").writeValue(v)
        }
        if (let Some(v) <- this.kind) {
                        w.writeName("kind").writeValue(v)
        }
        if (let Some(v) <- this.prompt) {
                        w.writeName("prompt").writeValue(v)
        }
        if (let Some(v) <- this.options) {
                        w.writeName("options"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.expires_at) {
                        w.writeName("expires_at").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): OutputItem {
        let res = OutputItem()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<Option<String>>() }),
                ("type", { => res.typeName = r.readValue<String>() }),
                ("status", { => res.status = r.readValue<Option<String>>() }),
                ("role", { => res.role = r.readValue<Option<String>>() }),
                ("content", { => res.content = r.readValue<Option<Array<ContentPart>>>() }),
                ("summary", { => res.summary = r.readValue<Option<Array<Raw>>>() }),
                ("call_id", { => res.call_id = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("arguments", { => res.arguments = r.readValue<Option<String>>() }),
                ("output", { => res.output = r.readValue<Option<String>>() }),
                ("kind", { => res.kind = r.readValue<Option<String>>() }),
                ("prompt", { => res.prompt = r.readValue<Option<String>>() }),
                ("options", { => res.options = r.readValue<Option<Array<OutputItemOptions>>>() }),
                ("expires_at", { => res.expires_at = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class ResponseIncompleteDetails <: JsonSerializable & JsonDeserializable<ResponseIncompleteDetails> {
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResponseIncompleteDetails {
        let res = ResponseIncompleteDetails()
        fromJsonObjectWithExtras(
            r,
            [

            ],
            res.extras
        )
        return res
    }
}

public class ResponseMetadata <: JsonSerializable & JsonDeserializable<ResponseMetadata> {
    public var session_id: Option<String> = None
    public var environment: Option<String> = None
    public var requested_model: Option<String> = None
    public var model_fallback: Option<Bool> = None
    public var model_fallback_reason: Option<String> = None
    public var ignored_fields: Option<Array<String>> = None
    public var voided_input_requests: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.session_id) {
                        w.writeName("session_id").writeValue(v)
        }
        if (let Some(v) <- this.environment) {
                        w.writeName("environment").writeValue(v)
        }
        if (let Some(v) <- this.requested_model) {
                        w.writeName("requested_model").writeValue(v)
        }
        if (let Some(v) <- this.model_fallback) {
                        w.writeName("model_fallback").writeValue(v)
        }
        if (let Some(v) <- this.model_fallback_reason) {
                        w.writeName("model_fallback_reason").writeValue(v)
        }
        if (let Some(v) <- this.ignored_fields) {
                        w.writeName("ignored_fields").writeValue(v)
        }
        if (let Some(v) <- this.voided_input_requests) {
                        w.writeName("voided_input_requests").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResponseMetadata {
        let res = ResponseMetadata()
        fromJsonObjectWithExtras(
            r,
            [
                ("session_id", { => res.session_id = r.readValue<Option<String>>() }),
                ("environment", { => res.environment = r.readValue<Option<String>>() }),
                ("requested_model", { => res.requested_model = r.readValue<Option<String>>() }),
                ("model_fallback", { => res.model_fallback = r.readValue<Option<Bool>>() }),
                ("model_fallback_reason", { => res.model_fallback_reason = r.readValue<Option<String>>() }),
                ("ignored_fields", { => res.ignored_fields = r.readValue<Option<Array<String>>>() }),
                ("voided_input_requests", { => res.voided_input_requests = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Response <: JsonSerializable & JsonDeserializable<Response> {
    public var id: String = ""
    public var objectKind: String = ""
    public var created_at: Int64 = 0
    public var status: String = ""
    public var error: Option<ErrorObject> = None
    public var incomplete_details: Option<ResponseIncompleteDetails> = None
    public var previous_response_id: Option<Raw> = None
    public var model: String = ""
    public var output: Array<OutputItem> = []
    public var store: Option<Bool> = None
    public var usage: Option<Usage> = None
    public var metadata: Option<ResponseMetadata> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
                w.writeName("object").writeValue(this.objectKind)
                w.writeName("created_at").writeValue(this.created_at)
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.error) {
                        w.writeName("error"); v.toJson(w)
        } else {
            w.writeName("error").writeNullValue()
        }
        if (let Some(v) <- this.incomplete_details) {
                        w.writeName("incomplete_details"); v.toJson(w)
        } else {
            w.writeName("incomplete_details").writeNullValue()
        }
        if (let Some(v) <- this.previous_response_id) {
                        w.writeName("previous_response_id").jsonValue(v)
        } else {
            w.writeName("previous_response_id").writeNullValue()
        }
                w.writeName("model").writeValue(this.model)
                w.writeName("output"); w.startArray();
        for (e in this.output) { e.toJson(w) }
        w.endArray()
        if (let Some(v) <- this.store) {
                        w.writeName("store").writeValue(v)
        } else {
            w.writeName("store").writeNullValue()
        }
        if (let Some(v) <- this.usage) {
                        w.writeName("usage"); v.toJson(w)
        } else {
            w.writeName("usage").writeNullValue()
        }
        if (let Some(v) <- this.metadata) {
                        w.writeName("metadata"); v.toJson(w)
        } else {
            w.writeName("metadata").writeNullValue()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Response {
        let res = Response()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<String>() }),
                ("created_at", { => res.created_at = r.readValue<Int64>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("error", { => res.error = r.readValue<Option<ErrorObject>>() }),
                ("incomplete_details", { => res.incomplete_details = r.readValue<Option<ResponseIncompleteDetails>>() }),
                ("previous_response_id", { => res.previous_response_id = readRaw(r) }),
                ("model", { => res.model = r.readValue<String>() }),
                ("output", { => res.output = r.readValue<Array<OutputItem>>() }),
                ("store", { => res.store = r.readValue<Option<Bool>>() }),
                ("usage", { => res.usage = r.readValue<Option<Usage>>() }),
                ("metadata", { => res.metadata = r.readValue<Option<ResponseMetadata>>() })
            ],
            res.extras
        )
        return res
    }
}

// 上游字符串枚举；未知值落 Other，不抛错（客户端 MUST 容忍未来新增值）。
public enum ResponseStatus {
    | InProgress
    | Completed
    | Failed
    | Incomplete
    | Cancelled
    | Other(String)
}

public func responseStatusParse(s: String): ResponseStatus {
    return match (s) {
        case "in_progress" => ResponseStatus.InProgress
        case "completed" => ResponseStatus.Completed
        case "failed" => ResponseStatus.Failed
        case "incomplete" => ResponseStatus.Incomplete
        case "cancelled" => ResponseStatus.Cancelled
        case other => ResponseStatus.Other(other)
    }
}

public func responseStatusName(v: ResponseStatus): String {
    return match (v) {
        case ResponseStatus.InProgress => "in_progress"
        case ResponseStatus.Completed => "completed"
        case ResponseStatus.Failed => "failed"
        case ResponseStatus.Incomplete => "incomplete"
        case ResponseStatus.Cancelled => "cancelled"
        case ResponseStatus.Other(s) => s
    }
}

public class Usage <: JsonSerializable & JsonDeserializable<Usage> {
    public var input_tokens: Option<Int64> = None
    public var output_tokens: Option<Int64> = None
    public var total_tokens: Option<Int64> = None
    public var cache_read_tokens: Option<Int64> = None
    public var cache_write_tokens: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.input_tokens) {
                        w.writeName("input_tokens").writeValue(v)
        }
        if (let Some(v) <- this.output_tokens) {
                        w.writeName("output_tokens").writeValue(v)
        }
        if (let Some(v) <- this.total_tokens) {
                        w.writeName("total_tokens").writeValue(v)
        }
        if (let Some(v) <- this.cache_read_tokens) {
                        w.writeName("cache_read_tokens").writeValue(v)
        }
        if (let Some(v) <- this.cache_write_tokens) {
                        w.writeName("cache_write_tokens").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Usage {
        let res = Usage()
        fromJsonObjectWithExtras(
            r,
            [
                ("input_tokens", { => res.input_tokens = r.readValue<Option<Int64>>() }),
                ("output_tokens", { => res.output_tokens = r.readValue<Option<Int64>>() }),
                ("total_tokens", { => res.total_tokens = r.readValue<Option<Int64>>() }),
                ("cache_read_tokens", { => res.cache_read_tokens = r.readValue<Option<Int64>>() }),
                ("cache_write_tokens", { => res.cache_write_tokens = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}
