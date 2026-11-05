package uhp.types.test

import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.handwritten.*

@Test
func harness_deleted_kept(): Unit {
    // sessions 省略 = kept（规范：省略即 kept，不是「未知」）
    let d = parseObj<HarnessDeleted>("{\"id\":\"chrn_1\",\"deleted\":true}")
    @Expect(d.deleted, true)
    @Expect(d.sessions.isNone(), true)
    let s = renderObj<HarnessDeleted>(d)
    @Expect(s.count("chrn_1") >= 1, true)
    @Expect(s.count("sessions") == 0, true)
}

@Test
func harness_deleted_retired_with_seconds(): Unit {
    let d = parseObj<HarnessDeleted>("{\"id\":\"chrn_1\",\"deleted\":true,\"sessions\":\"retired\",\"restorableUntil\":1760000000}")
    @Expect(d.sessions ?? "", "retired")
    @Expect(d.restorableUntil ?? 0, 1760000000)
}

@Test
func session_turns_roundtrip(): Unit {
    let src = "{\"turns\":[{\"id\":\"resp_1\",\"status\":\"completed\"}]}"
    let t = parseObj<SessionTurns>(src)
    @Expect(t.turns.size, 1)
    let s = renderObj<SessionTurns>(t)
    @Expect(s.count("resp_1") >= 1, true)
}

@Test
func deleted_envelope(): Unit {
    let d = parseObj<Deleted>("{\"id\":\"hsess1\",\"deleted\":true}")
    @Expect(d.id, "hsess1")
}
