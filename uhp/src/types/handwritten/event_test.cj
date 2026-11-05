
// UhpEvent 的单测。
//
// 覆盖四类契约：
//   1. 18 个已知事件类型各自落到正确变体（分派表与规范 §2 词表一一对应）；
//   2. 未知事件类型落 Unknown、不抛、字段不丢（VERSIONING 客户端规则 2，MUST）；
//   3. 序号缺失/为负的明确行为（已知事件抛，未知事件不抛）；
//   4. 终态判定（completed/incomplete/failed 是，error 不是）。
package uhp.types.handwritten

import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.codec.*

// 注意：本包已有 capability_test.cj 定义了 render / parseJson，
// 这里用带前缀的名字避免同包重名。
func eventRender(ev: UhpEvent): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    ev.toJson(w)
    w.flush()
    return String.fromUtf8(out.bytes())
}

func eventParse(s: String): UhpEvent {
    let r = JsonReader(ByteBuffer(s.toArray()))
    return UhpEvent.fromJson(r)
}

// 变体标签：断言「落到了哪个变体」。
// 不用 typeName 代替它——typeName 对 Unknown 返回原名字符串，
// 区分不出「变体错但类型名碰巧对」的情况。
func eventTag(ev: UhpEvent): String {
    return match (ev) {
        case UhpEvent.Created(_) => "Created"
        case UhpEvent.InProgress(_) => "InProgress"
        case UhpEvent.Completed(_) => "Completed"
        case UhpEvent.Incomplete(_) => "Incomplete"
        case UhpEvent.Failed(_) => "Failed"
        case UhpEvent.OutputItemAdded(_) => "OutputItemAdded"
        case UhpEvent.OutputItemDone(_) => "OutputItemDone"
        case UhpEvent.ContentPartAdded(_) => "ContentPartAdded"
        case UhpEvent.ContentPartDone(_) => "ContentPartDone"
        case UhpEvent.OutputTextDelta(_) => "OutputTextDelta"
        case UhpEvent.OutputTextDone(_) => "OutputTextDone"
        case UhpEvent.OutputTextAnnotationAdded(_) => "OutputTextAnnotationAdded"
        case UhpEvent.ReasoningSummaryPartAdded(_) => "ReasoningSummaryPartAdded"
        case UhpEvent.ReasoningSummaryPartDone(_) => "ReasoningSummaryPartDone"
        case UhpEvent.ReasoningSummaryTextDelta(_) => "ReasoningSummaryTextDelta"
        case UhpEvent.FunctionCallArgumentsDelta(_) => "FunctionCallArgumentsDelta"
        case UhpEvent.FunctionCallArgumentsDone(_) => "FunctionCallArgumentsDone"
        case UhpEvent.Error(_) => "Error"
        case UhpEvent.Unknown(_) => "Unknown"
    }
}

// 18 个事件的最小合法样例（type 与 Streaming §2 词表逐条对应）。
// 用函数返回而不是全局常量：仓颉全局不可变集合的初始化比较绕，而这里每个用例都要用一次。
func minimalEvents(): Array<(String, String, String)> {
    return [
        ("response.created", "Created",
            "{\"type\":\"response.created\",\"sequence_number\":0,\"response\":{\"id\":\"resp_1\",\"status\":\"in_progress\"}}"),
        ("response.in_progress", "InProgress",
            "{\"type\":\"response.in_progress\",\"sequence_number\":1}"),
        ("response.completed", "Completed",
            "{\"type\":\"response.completed\",\"sequence_number\":9,\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}"),
        ("response.incomplete", "Incomplete",
            "{\"type\":\"response.incomplete\",\"sequence_number\":9,\"response\":{\"id\":\"resp_1\",\"status\":\"incomplete\"}}"),
        ("response.failed", "Failed",
            "{\"type\":\"response.failed\",\"sequence_number\":9,\"response\":{\"id\":\"resp_1\",\"status\":\"failed\"}}"),
        ("response.output_item.added", "OutputItemAdded",
            "{\"type\":\"response.output_item.added\",\"sequence_number\":2,\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_1\"}}"),
        ("response.output_item.done", "OutputItemDone",
            "{\"type\":\"response.output_item.done\",\"sequence_number\":3,\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_1\"}}"),
        ("response.content_part.added", "ContentPartAdded",
            "{\"type\":\"response.content_part.added\",\"sequence_number\":4,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\"}}"),
        ("response.content_part.done", "ContentPartDone",
            "{\"type\":\"response.content_part.done\",\"sequence_number\":7,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"hi\"}}"),
        ("response.output_text.delta", "OutputTextDelta",
            "{\"type\":\"response.output_text.delta\",\"sequence_number\":5,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"delta\":\"Sum\"}"),
        ("response.output_text.done", "OutputTextDone",
            "{\"type\":\"response.output_text.done\",\"sequence_number\":6,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"text\":\"Sum of two\"}"),
        ("response.output_text.annotation.added", "OutputTextAnnotationAdded",
            "{\"type\":\"response.output_text.annotation.added\",\"sequence_number\":6,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"annotation_index\":0,\"annotation\":{\"type\":\"container_file_citation\"}}"),
        ("response.reasoning_summary_part.added", "ReasoningSummaryPartAdded",
            "{\"type\":\"response.reasoning_summary_part.added\",\"sequence_number\":1,\"item_id\":\"rs_1\",\"output_index\":1,\"summary_index\":0,\"part\":{\"type\":\"summary_text\"}}"),
        ("response.reasoning_summary_part.done", "ReasoningSummaryPartDone",
            "{\"type\":\"response.reasoning_summary_part.done\",\"sequence_number\":3,\"item_id\":\"rs_1\",\"output_index\":1,\"summary_index\":0,\"part\":{\"type\":\"summary_text\",\"text\":\"thought\"}}"),
        ("response.reasoning_summary_text.delta", "ReasoningSummaryTextDelta",
            "{\"type\":\"response.reasoning_summary_text.delta\",\"sequence_number\":2,\"item_id\":\"rs_1\",\"output_index\":1,\"summary_index\":0,\"delta\":\"thin\"}"),
        ("response.function_call_arguments.delta", "FunctionCallArgumentsDelta",
            "{\"type\":\"response.function_call_arguments.delta\",\"sequence_number\":8,\"item_id\":\"fc_1\",\"output_index\":2,\"delta\":\"par\"}"),
        ("response.function_call_arguments.done", "FunctionCallArgumentsDone",
            "{\"type\":\"response.function_call_arguments.done\",\"sequence_number\":9,\"item_id\":\"fc_1\",\"output_index\":2,\"arguments\":\"{\\\"a\\\":1}\"}"),
        ("error", "Error",
            "{\"type\":\"error\",\"sequence_number\":10,\"code\":\"provider_error\",\"message\":\"upstream failed\"}")
    ]
}

@Test
func event_all_types_dispatch_to_expected_variant(): Unit {
    // 分派表必须与 Streaming §2 的 18 条词表一一对应；错一条这个用例就红。
    for ((wireType, tag, json) in minimalEvents()) {
        let ev = eventParse(json)
        @Expect(eventTag(ev), tag)
        @Expect(typeName(ev), wireType)
    }
}

@Test
func event_sequence_numbers_are_read(): Unit {
    for ((_, _, json) in minimalEvents()) {
        let ev = eventParse(json)
        let seq = sequenceNumberOf(ev)
        @Expect(seq.isSome(), true)
        // 样例里每条都写了 sequence_number，缺失会在解析处抛（另一个用例覆盖）
        @Expect(seq.getOrThrow() >= 0, true)
    }
    let ev = eventParse("{\"type\":\"response.output_text.delta\",\"sequence_number\":42,\"delta\":\"x\"}")
    @Expect(sequenceNumberOf(ev).getOrThrow(), 42)
}

@Test
func event_payload_fields_are_parsed(): Unit {
    let d = eventParse("{\"type\":\"response.output_text.delta\",\"sequence_number\":5,\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":2,\"delta\":\"Sum\"}")
    match (d) {
        case UhpEvent.OutputTextDelta(e) =>
            @Expect(e.sequenceNumber, 5)
            @Expect(e.itemId.getOrThrow(), "msg_1")
            @Expect(e.outputIndex.getOrThrow(), 0)
            @Expect(e.contentIndex.getOrThrow(), 2)
            @Expect(e.delta, "Sum")
        case _ => @Fail("应为 OutputTextDelta")
    }
    // 工具调用参数是 JSON 文本，不是对象：进出一趟必须原样
    let t = eventParse("{\"type\":\"response.function_call_arguments.done\",\"sequence_number\":9,\"item_id\":\"fc_1\",\"output_index\":2,\"arguments\":\"{\\\"a\\\":1}\"}")
    match (t) {
        case UhpEvent.FunctionCallArgumentsDone(e) =>
            @Expect(e.arguments, "{\"a\":1}")
        case _ => @Fail("应为 FunctionCallArgumentsDone")
    }
    // 子对象按原始文本保存（生成类型接入后再改），至少不能被写成字符串
    let c = eventParse("{\"type\":\"response.content_part.done\",\"sequence_number\":7,\"part\":{\"type\":\"output_text\",\"text\":\"hi\"}}")
    match (c) {
        case UhpEvent.ContentPartDone(e) =>
            @Expect(e.partRaw.getOrThrow(), "{\"type\":\"output_text\",\"text\":\"hi\"}")
        case _ => @Fail("应为 ContentPartDone")
    }
}

@Test
func event_unknown_type_falls_to_unknown_not_throw(): Unit {
    // 客户端 MUST 忽略未知事件类型并继续读流：不能抛，也不能丢字段。
    let src = "{\"type\":\"response.made.up\",\"sequence_number\":3,\"future\":{\"a\":[1,2]}}"
    let ev = eventParse(src)
    @Expect(eventTag(ev), "Unknown")
    @Expect(typeName(ev), "response.made.up")
    @Expect(sequenceNumberOf(ev).getOrThrow(), 3)
}

@Test
func event_unknown_type_without_sequence_number_is_tolerated(): Unit {
    // 未知类型不承诺任何字段：缺 sequence_number 也不能抛（否则一条未来事件毒死整条流）。
    let ev = eventParse("{\"type\":\"response.made.up\"}")
    @Expect(eventTag(ev), "Unknown")
    @Expect(sequenceNumberOf(ev).isNone(), true)
}

@Test
func event_unknown_roundtrip_is_byte_exact(): Unit {
    let src = "{\"type\":\"response.made.up\",\"sequence_number\":3,\"future\":{\"a\":[1,2]}}"
    @Expect(eventRender(eventParse(src)), src)
}

@Test
func event_unknown_type_and_sequence_number_preserved_in_roundtrip(): Unit {
    let ev = eventParse("{\"type\":\"x.vendor.thing\",\"sequence_number\":11}")
    let again = eventParse(eventRender(ev))
    @Expect(eventTag(again), "Unknown")
    @Expect(typeName(again), "x.vendor.thing")
    @Expect(sequenceNumberOf(again).getOrThrow(), 11)
}

@Test
func event_roundtrip_all_types_keeps_variant(): Unit {
    for ((wireType, tag, json) in minimalEvents()) {
        let rendered = eventRender(eventParse(json))
        let again = eventParse(rendered)
        @Expect(eventTag(again), tag)
        @Expect(typeName(again), wireType)
        // 类型名必须在输出里，否则服务端重放这段流会变成另一种事件
        @Expect(rendered.count(wireType) >= 1, true)
    }
}

@Test
func event_unknown_fields_are_preserved(): Unit {
    // 仓级约定：未知字段必须保真（153 个对象节点全部 additionalProperties: true）。
    let src = "{\"type\":\"response.output_text.delta\",\"sequence_number\":5,\"delta\":\"x\",\"vendor_note\":{\"a\":1}}"
    let ev = eventParse(src)
    match (ev) {
        case UhpEvent.OutputTextDelta(e) =>
            @Expect(e.extras.contains("vendor_note"), true)
            @Expect(e.extras["vendor_note"], "{\"a\":1}")
        case _ => @Fail("应为 OutputTextDelta")
    }
    let again = eventParse(eventRender(ev))
    match (again) {
        case UhpEvent.OutputTextDelta(e) =>
            @Expect(e.extras.contains("vendor_note"), true)
            @Expect(e.extras["vendor_note"], "{\"a\":1}")
        case _ => @Fail("round-trip 后应为 OutputTextDelta")
    }
}

@Test
func event_missing_type_throws(): Unit {
    // 没有 type 就无法分派；规范要求必带，按结构错误抛。
    @ExpectThrows[JsonProtocolException](eventParse("{\"sequence_number\":1}"))
}

@Test
func event_missing_sequence_number_on_known_type_throws(): Unit {
    // 静默补 0 会让两个事件序号相同，S-04 的缺口检测失效；宁可解析处失败。
    @ExpectThrows[JsonProtocolException](eventParse("{\"type\":\"response.in_progress\"}"))
}

@Test
func event_negative_sequence_number_throws(): Unit {
    @ExpectThrows[JsonProtocolException](eventParse("{\"type\":\"response.in_progress\",\"sequence_number\":-1}"))
}

@Test
func event_missing_delta_is_tolerated_as_empty(): Unit {
    // 规范要求 delta 事件带 delta；不规范的服务端不该让整条流断掉。
    let ev = eventParse("{\"type\":\"response.output_text.delta\",\"sequence_number\":5}")
    match (ev) {
        case UhpEvent.OutputTextDelta(e) => @Expect(e.delta, "")
        case _ => @Fail("应为 OutputTextDelta")
    }
}

@Test
func event_error_param_null_equals_absent(): Unit {
    // param 是 ["string","null"]：null 与缺失等价，两者都落 None、都不回写。
    let withNull = eventParse("{\"type\":\"error\",\"sequence_number\":1,\"code\":\"timeout\",\"message\":\"m\",\"param\":null}")
    match (withNull) {
        case UhpEvent.Error(e) =>
            @Expect(e.param.isNone(), true)
            @Expect(e.code, "timeout")
        case _ => @Fail("应为 Error")
    }
    let rendered = eventRender(withNull)
    @Expect(rendered.count("param") == 0, true)
    let withParam = eventParse("{\"type\":\"error\",\"sequence_number\":1,\"code\":\"invalid_input\",\"message\":\"m\",\"param\":\"metadata.x\"}")
    match (withParam) {
        case UhpEvent.Error(e) => @Expect(e.param.getOrThrow(), "metadata.x")
        case _ => @Fail("应为 Error")
    }
}

@Test
func event_terminal_classification(): Unit {
    // 终态恰为 completed / incomplete / failed（Streaming §4）。
    @Expect(isTerminal(eventParse("{\"type\":\"response.completed\",\"sequence_number\":9}")), true)
    @Expect(isTerminal(eventParse("{\"type\":\"response.incomplete\",\"sequence_number\":9}")), true)
    @Expect(isTerminal(eventParse("{\"type\":\"response.failed\",\"sequence_number\":9}")), true)
    // error 不是终态：§2.6 要求它之后 MUST 还有一个终态事件。
    @Expect(isTerminal(eventParse("{\"type\":\"error\",\"sequence_number\":1}")), false)
    // 其它过程事件都不是终态
    @Expect(isTerminal(eventParse("{\"type\":\"response.created\",\"sequence_number\":0}")), false)
    @Expect(isTerminal(eventParse("{\"type\":\"response.output_text.delta\",\"sequence_number\":5}")), false)
    // 未知事件不替它下结论
    @Expect(isTerminal(eventParse("{\"type\":\"response.made.up\",\"sequence_number\":1}")), false)
}

@Test
func event_terminal_events_carry_object_payload_verbatim(): Unit {
    // 终态事件必须携带完整 Response（§4：只靠这一个事件就能渲染结果）。
    // 生成类型接入前，载荷按原始文本保真——不能被写成带引号的字符串。
    let src = "{\"type\":\"response.completed\",\"sequence_number\":9,\"response\":{\"id\":\"resp_1\",\"status\":\"completed\",\"output\":[{\"type\":\"message\"}]}}"
    let rendered = eventRender(eventParse(src))
    @Expect(rendered.count("\"response\":{\"id\":\"resp_1\",\"status\":\"completed\",\"output\":[{\"type\":\"message\"}]}"), 1)
}

