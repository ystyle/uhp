package uhp.transport

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

func bytesOf(s: String): Array<UInt8> {
    return s.toArray()
}

func feedAll(p: SseParser, chunks: Array<String>): Array<SseEvent> {
    let out = ArrayList<SseEvent>()
    for (c in chunks) {
        for (e in p.feed(bytesOf(c))) { out.add(e) }
    }
    return out.toArray()
}

@Test
func sse_single_event(): Unit {
    let p = SseParser()
    let evs = feedAll(p, ["data: {\"type\":\"response.created\"}\n\n"])
    @Expect(evs.size, 1)
    @Expect(evs[0].data, "{\"type\":\"response.created\"}")
}

@Test
func sse_multiline_data_joined_by_lf(): Unit {
    let p = SseParser()
    let evs = feedAll(p, ["data: line1\ndata: line2\n\n"])
    @Expect(evs.size, 1)
    @Expect(evs[0].data, "line1\nline2")
}

@Test
func sse_comment_heartbeat_does_not_emit(): Unit {
    let p = SseParser()
    let evs = feedAll(p, [": keep-alive\n\n", "data: x\n\n"])
    @Expect(evs.size, 1)
    @Expect(evs[0].data, "x")
    @Expect(p.commentCount, 1)
}

@Test
func sse_crlf_and_cr_terminators(): Unit {
    let p = SseParser()
    let evs = feedAll(p, ["data: a\r\n\r\n", "data: b\r\r"])
    @Expect(evs.size, 2)
    @Expect(evs[0].data, "a")
    @Expect(evs[1].data, "b")
}

@Test
func sse_crlf_split_across_chunks(): Unit {
    // 关键边界：CR 与 LF 落在两个 chunk 里，不能被当成两个换行（否则会多出空行/空帧）
    let p = SseParser()
    let out = ArrayList<SseEvent>()
    for (e in p.feed(bytesOf("data: hello\r"))) { out.add(e) }
    for (e in p.feed(bytesOf("\n\r\n"))) { out.add(e) }
    @Expect(out.size, 1)
    @Expect(out[0].data, "hello")
}

@Test
func sse_utf8_split_across_chunks(): Unit {
    // 关键边界：一个汉字（3 字节）被切在块边界上，按字节缓冲不能坏
    let src = "data: 你好\n\n".toArray()
    let p = SseParser()
    let out = ArrayList<SseEvent>()
    for (e in p.feed(src[0..9])) { out.add(e) }   // "data: 你" 的最后一个字节前切
    for (e in p.feed(src[9..src.size])) { out.add(e) }
    @Expect(out.size, 1)
    @Expect(out[0].data, "你好")
}

@Test
func sse_no_trailing_blank_line_needs_finish(): Unit {
    let p = SseParser()
    let out = ArrayList<SseEvent>()
    for (e in p.feed(bytesOf("data: last"))) { out.add(e) }
    @Expect(out.size, 0)
    for (e in p.finish()) { out.add(e) }
    @Expect(out.size, 1)
    @Expect(out[0].data, "last")
}

@Test
func sse_ignores_unknown_fields_and_handles_retry(): Unit {
    let p = SseParser()
    let evs = feedAll(p, ["foo: bar\nretry: 3000\ndata: x\n\n"])
    @Expect(evs.size, 1)
    @Expect(evs[0].retry ?? -1, 3000)
    @Expect(evs[0].data, "x")
}

@Test
func sse_blank_data_line_is_preserved(): Unit {
    // data: 后面没有空格时值就是空串；多行时保留空行
    let p = SseParser()
    let evs = feedAll(p, ["data:\ndata: tail\n\n"])
    @Expect(evs.size, 1)
    @Expect(evs[0].data, "\ntail")
}
