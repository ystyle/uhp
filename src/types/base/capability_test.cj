package uhp.types.base

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.stream.*
import std.io.*

func render<T>(v: T): String where T <: JsonSerializable {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    v.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}

func parseJson<T>(s: String): T where T <: JsonDeserializable<T> {
    let r = JsonReader(ByteBuffer(s.toArray()))
    return T.fromJson(r)
}

@Test
func capability_absent_keys_default_false(): Unit {
    let c = parseJson<Capabilities>("{\"streaming\":true}")
    @Expect(c.streaming, true)
    @Expect(c.memories, false)
    @Expect(c.plugins, false)
}

@Test
func capability_serializes_all_sixteen_keys(): Unit {
    let c = Capabilities()
    c.streaming = true
    let s = render<Capabilities>(c)
    @Expect(s.count("streaming") >= 1, true)
    // 16 个键全部写出（客户端据此区分「不支持」与「服务端版本旧」）
    let keys = ["streaming", "sessions", "cancellation", "files_input", "files_output", "session_listing",
        "harness_management", "harness_retirement", "session_sharing", "idempotency", "harness_idempotency",
        "input_requests", "input_history", "plugins", "environments", "memories"]
    for (k in keys) {
        @Expect(s.count(k) >= 1, true)
    }
}

@Test
func capability_unknown_key_preserved(): Unit {
    // 未知能力键必须逐字节保真：GET -> 解析 -> 序列化 -> 再解析，值不变。
    let src = "{\"streaming\":true,\"future_cap\":{\"x\":1,\"y\":[1,2]}}"
    let c = parseJson<Capabilities>(src)
    @Expect(c.extras.contains("future_cap"), true)
    let s = render<Capabilities>(c)
    let again = parseJson<Capabilities>(s)
    @Expect(again.extras.contains("future_cap"), true)
    @Expect(again.extras["future_cap"] == c.extras["future_cap"], true)
}

@Test
func class_consistency(): Unit {
    let c = Capabilities()
    @Expect(c.consistentWith(ConformanceClass.Core), true)
    @Expect(c.consistentWith(ConformanceClass.Extended), false)
    c.filesInput = true
    c.filesOutput = true
    c.sessionListing = true
    @Expect(c.consistentWith(ConformanceClass.Extended), true)
}
