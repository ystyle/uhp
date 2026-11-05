// L1 结构测试：根对象 JSON -> 对象 -> JSON 幂等，且未知字段保真。
// 独立包（uhp.types.test）而不是放在 generated/ 下：generated/ 归生成器所有。
package uhp.types.test

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.codec.*
import uhp.types.generated.*

func renderObj<T>(v: T): String where T <: JsonSerializable {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    v.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}

func parseObj<T>(s: String): T where T <: JsonDeserializable<T> {
    let r = JsonReader(ByteBuffer(s.toArray()))
    return T.fromJson(r)
}

func roundtrip<T>(s: String): String where T <: JsonSerializable & JsonDeserializable<T> {
    let o = parseObj<T>(s)
    return renderObj<T>(o)
}

@Test
func discovery_roundtrip(): Unit {
    let src = """
    {"object":"uhp.discovery","protocol":"uhp","versions":["2026-10-19"],
     "default_version":"2026-10-19","conformance_class":"full",
     "capabilities":{"streaming":true,"sessions":true},
     "plugin_schemas":[],"implementation":{"name":"t","version":"0"}}
    """
    let out = roundtrip<Discovery>(src)
    @Expect(out.count("uhp.discovery") >= 1, true)
    @Expect(out.count("2026-10-19") >= 2, true)
    @Expect(out.count("streaming") >= 1, true)
}

@Test
func harness_roundtrip(): Unit {
    let src = """
    {"id":"chrn_1","object":"harness","name":"Research agent","base":"cli",
     "defaultModel":"m","createdAt":1786403298205,"disabledTools":["WebSearch"],
     "maxStep":null,"environment":""}
    """
    let out = roundtrip<Harness>(src)
    @Expect(out.count("chrn_1") >= 1, true)
    @Expect(out.count("WebSearch") >= 1, true)
    @Expect(out.count("1786403298205") >= 1, true)
}

@Test
func response_roundtrip(): Unit {
    let src = """
    {"id":"resp_1","object":"response","created_at":1786400000,"status":"completed",
     "error":null,"incomplete_details":null,"output":[],"model":"m","usage":null,
     "metadata":{"session_id":"hsess1"},"previous_response_id":null,"store":true}
    """
    let out = roundtrip<Response>(src)
    @Expect(out.count("resp_1") >= 1, true)
    @Expect(out.count("hsess1") >= 1, true)
    @Expect(out.count("error") >= 1, true)
    @Expect(out.count("store") >= 1, true)
}

@Test
func session_roundtrip(): Unit {
    let src = """
    {"id":"hsess1","object":"session","harness_id":"chrn_1","title":"t",
     "status":"completed","created_at":1786400000,"updated_at":1786400240}
    """
    let out = roundtrip<Session>(src)
    @Expect(out.count("hsess1") >= 1, true)
    @Expect(out.count("chrn_1") >= 1, true)
}

@Test
func generated_unknown_fields_preserved(): Unit {
    let src = """
    {"id":"chrn_2","object":"harness","name":"n","base":"b","createdAt":1,
     "vendorExtension":{"a":1,"b":[true,null]}}
    """
    let h = parseObj<Harness>(src)
    @Expect(h.extras.contains("vendorExtension"), true)
    let out = renderObj<Harness>(h)
    @Expect(out.count("vendorExtension") >= 1, true)
}

@Test
func error_object_roundtrip(): Unit {
    let src = """
    {"type":"invalid_request_error","code":"harness_not_found",
     "message":"No harness.","param":"metadata.harness_id","detail":null}
    """
    let out = roundtrip<ErrorObject>(src)
    @Expect(out.count("harness_not_found") >= 1, true)
    @Expect(out.count("invalid_request_error") >= 1, true)
}
