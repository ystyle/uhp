// L2 行为测试：会话与文件（Extended 类需要的引擎能力）。
package uhp.server

import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.base.*
import uhp.types.generated.*

func engineExtended(): Engine {
    let h = ScriptedHarness([ScriptStep.Text("ok"), ScriptStep.File("out.txt", "artifact-ok")],
        TurnOutcome.Completed(None))
    return Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)], cls: ConformanceClass.Extended)
}

@Test
func extended_capabilities_match_class(): Unit {
    let e = engineExtended()
    let caps = e.discovery().capabilities
    @Expect(caps.filesInput, true)
    @Expect(caps.filesOutput, true)
    @Expect(caps.sessionListing, true)
    @Expect(e.discovery().conformance_class, "extended")
}

@Test
func sessions_are_listed_with_explicit_end(): Unit {
    let e = engineExtended()
    let p = Principal("alice")
    e.createTask(p, TaskRequest("first task"))
    e.createTask(p, TaskRequest("second task"))
    let (items, next) = e.listSessions(p, 10, None)
    @Expect(items.size, 2)
    // 末页必须显式给 None（规范：不能让客户端靠「本页不满」猜）
    @Expect(next.isNone(), true)
    // 分页：limit=1 时一定有下一页
    let (page1, next1) = e.listSessions(p, 1, None)
    @Expect(page1.size, 1)
    @Expect(next1.isSome(), true)
}

@Test
func session_turns_have_id_and_status(): Unit {
    let e = engineExtended()
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let sid = (r.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let turns = e.sessionTurns(p, sid)
    @Expect(turns.size, 1)
    @Expect(turns[0].id, r.response.id)
    @Expect(turns[0].status, "completed")
}

@Test
func artifacts_are_registered_from_driver(): Unit {
    let e = engineExtended()
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let sid = (r.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let files = e.sessionFiles(p, sid)
    @Expect(files.size, 1)
    @Expect(files[0].filename, "out.txt")
    let cid = files[0].extras.get("container_id") ?? ""
    @Expect(cid.startsWith("\"cntr_"), true)
}

@Test
func file_download_is_scoped_and_container_bound(): Unit {
    let e = engineExtended()
    let alice = Principal("alice")
    let bob = Principal("bob")
    let up = e.uploadFile(alice, "token.txt", "secret".toArray())
    let cid = up.extras.get("container_id") ?? ""
    let cidPlain = cid[1..cid.size - 1]
    // 本人可下
    let f = e.downloadFile(alice, cidPlain, up.id)
    @Expect(String.fromUtf8(f.bytes), "secret")
    // 他人不可下（404，不是 403）
    var code = ""
    try {
        e.downloadFile(bob, cidPlain, up.id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "file_not_found")
    // 容器不匹配也不可下
    var code2 = ""
    try {
        e.downloadFile(alice, "cntr_other", up.id)
    } catch (err: EngineError) {
        code2 = err.code
    }
    @Expect(code2, "file_not_found")
}
