// L2 测试：会话分享（Sessions §5）的引擎行为。
package uhp.server

import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.base.*
import uhp.types.generated.*

func engineFull(): Engine {
    let h = ScriptedHarness([ScriptStep.Text("shared text")], TurnOutcome.Completed(None))
    return Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)], cls: ConformanceClass.Full)
}

@Test
func share_publishes_and_reads_back(): Unit {
    let e = engineFull()
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let sid = (r.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let share = e.publishShare(p, sid)
    @Expect(share.url().startsWith("/v1/shared/"), true)
    let again = e.getShare(p, sid)
    @Expect(again.id, share.id)
    // 视图免鉴权可读，且带的是对话内容
    let view = e.sharedView(share.token)
    @Expect(view.contains(sid), true)
    @Expect(view.contains("shared text"), true)
    // 视图里不该出现凭证形状的键
    @Expect(view.contains("\"auth\""), false)
    @Expect(view.contains("\"token\""), false)
}

@Test
func revocation_kills_every_link_of_the_session(): Unit {
    let e = engineFull()
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let sid = (r.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let a = e.publishShare(p, sid)
    let b = e.publishShare(p, sid)
    @Expect(a.token != b.token, true)
    @Expect(e.revokeShares(p, sid), 2)
    var code = ""
    try {
        e.sharedView(a.token)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "session_share_not_found")
}

@Test
func deleting_a_session_takes_its_view(): Unit {
    let e = engineFull()
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let sid = (r.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let share = e.publishShare(p, sid)
    e.deleteSession(p, sid)
    var code = ""
    try {
        e.sharedView(share.token)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "session_share_not_found")
}
