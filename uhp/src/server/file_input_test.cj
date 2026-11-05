// L2 测试：任务输入里的文件（X-05 内联 file_data / X-09 file_id 引用）→ TurnContext.files。
package uhp.server

import std.collection.ArrayList
import std.io.ByteBuffer
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.stream.*
import uhp.types.base.*
import uhp.types.generated.*

class FileCaptureDriver <: HarnessDriver {
    public var captured: Array<TurnFile> = []

    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "capture"
    }

    public func models(): Array<Model> {
        return []
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        this.captured = ctx.files
        sink.textDelta("ok")
        return TurnOutcome.Completed(None)
    }
}

func taskBodyWithInlineFile(): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("input")
    w.startArray()
    w.startObject()
    w.writeName("role").writeValue("user")
    w.writeName("content")
    w.startArray()
    w.startObject()
    w.writeName("type").writeValue("input_text")
    w.writeName("text").writeValue("read the attached file")
    w.endObject()
    w.startObject()
    w.writeName("type").writeValue("input_file")
    w.writeName("filename").writeValue("token.txt")
    w.writeName("file_data").writeValue("data:text/plain;base64,dGhlIHNlY3JldA==")
    w.endObject()
    w.endArray()
    w.endObject()
    w.endArray()
    w.writeName("stream").writeValue(false)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

@Test
func inline_input_file_reaches_the_driver(): Unit {
    let driver = FileCaptureDriver()
    let h = ConfiguredHarness("chrn_1", "n", "scripted", "m", driver)
    let e = Engine([h])
    let parsed = parseTaskRequest(taskBodyWithInlineFile())
    @Expect(parsed.files.size, 1)
    let req = TaskRequest(parsed.input, files: parsed.files.toArray())
    let _ = e.createTask(Principal("alice"), req)
    @Expect(driver.captured.size, 1)
    @Expect(driver.captured[0].filename, "token.txt")
    @Expect(driver.captured[0].mediaType, "text/plain")
    @Expect(String.fromUtf8(driver.captured[0].bytes), "the secret")
}

@Test
func uploaded_file_id_reaches_the_driver(): Unit {
    let driver = FileCaptureDriver()
    let h = ConfiguredHarness("chrn_1", "n", "scripted", "m", driver)
    let e = Engine([h])
    let p = Principal("alice")
    let up = e.uploadFile(p, "notes.md", "# hi".toArray())
    let req = TaskRequest("read it", files: [TaskFileRef("", "", fileId: Some(up.id))])
    let _ = e.createTask(p, req)
    @Expect(driver.captured.size, 1)
    @Expect(driver.captured[0].filename, "notes.md")
    @Expect(driver.captured[0].mediaType.startsWith("text/markdown"), true)
    @Expect(String.fromUtf8(driver.captured[0].bytes), "# hi")
}

@Test
func another_principals_file_id_is_ignored(): Unit {
    let driver = FileCaptureDriver()
    let h = ConfiguredHarness("chrn_1", "n", "scripted", "m", driver)
    let e = Engine([h])
    let up = e.uploadFile(Principal("bob"), "bob.txt", "secret".toArray())
    let _ = e.createTask(Principal("alice"), TaskRequest("read it",
        files: [TaskFileRef("", "", fileId: Some(up.id))]))
    // 跨 principal：不报错，但文件不会被交给 driver（不泄露存在性）
    @Expect(driver.captured.size, 0)
}
