// L2 行为测试：引擎（任务执行 / 会话延续 / scope / 错误映射），全部离线。
package uhp.server

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.base.*
import uhp.types.generated.*

func scripted(id: String): ConfiguredHarness {
    let h = ScriptedHarness(
        [ScriptStep.Text("hel"), ScriptStep.Text("lo")],
        TurnOutcome.Completed(None)
    )
    return ConfiguredHarness(id, "scripted " + id, "scripted", "scripted-model", h)
}

func engineWith(harnesses: Array<ConfiguredHarness>): Engine {
    return Engine(harnesses)
}

class ThrowingHarness <: HarnessDriver {
    public func base(): String {
        return "boom"
    }
    public func baseLabel(): String {
        return "Boom"
    }
    public func models(): Array<Model> {
        return []
    }
    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }
    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        throw Exception("driver exploded")
    }
}

// ---------- 用例 ----------

@Test
func engine_runs_task_and_emits_ordered_events(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let p = Principal("alice")
    let result = e.createTask(p, TaskRequest("hi"))
    @Expect(result.response.status, "completed")
    // 输出项里有聚合后的文本
    @Expect(result.response.output.size, 1)
    @Expect(result.response.output[0].typeName, "message")
    let parts = result.response.output[0].content ?? []
    @Expect(parts.size, 1)
    @Expect(parts[0].text ?? "", "hello")
    // 事件：created 第一个、终态最后一个、序号 0 起连续
    let evs = result.channel.replay(0)
    @Expect(evs.size >= 3, true)
    @Expect(evs[0].eventType, "response.created")
    @Expect(evs[0].seq, 0)
    var expected: Int64 = 0
    for (ev in evs) {
        @Expect(ev.seq, expected)
        expected = expected + 1
    }
    // 终态事件必须存在且带完整 response
    let last = evs[evs.size - 1]
    @Expect(last.eventType, "response.completed")
    @Expect(last.json.contains("\"status\":\"completed\""), true)
}

@Test
func engine_continues_session_by_previous_response(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let p = Principal("alice")
    let first = e.createTask(p, TaskRequest("hi"))
    let second = e.createTask(p, TaskRequest("again", previousResponseId: Some(first.response.id)))
    let s1 = (first.response.metadata ?? ResponseMetadata()).session_id ?? ""
    let s2 = (second.response.metadata ?? ResponseMetadata()).session_id ?? ""
    @Expect(s1.size > 0, true)
    @Expect(s2, s1)
    @Expect(second.response.previous_response_id.isSome(), true)
}

@Test
func engine_rejects_different_harness_on_session(): Unit {
    let e = engineWith([scripted("chrn_1"), scripted("chrn_2")])
    let p = Principal("alice")
    let first = e.createTask(p, TaskRequest("hi", harnessId: Some("chrn_1")))
    var code = ""
    try {
        e.createTask(p, TaskRequest("again", harnessId: Some("chrn_2"),
            previousResponseId: Some(first.response.id)))
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "harness_mismatch")
}

@Test
func engine_unknown_harness_is_404(): Unit {
    let e = engineWith([scripted("chrn_1")])
    var code = ""
    var status: UInt16 = 0
    try {
        e.createTask(Principal("alice"), TaskRequest("hi", harnessId: Some("chrn_nope")))
    } catch (err: EngineError) {
        code = err.code
        status = err.httpStatus
    }
    @Expect(code, "harness_not_found")
    @Expect(status, UInt16(404))
}

@Test
func engine_object_scope_is_404_for_other_principal(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let alice = Principal("alice")
    let bob = Principal("bob")
    let r = e.createTask(alice, TaskRequest("hi"))
    @Expect(e.getResponse(alice, r.response.id).id, r.response.id)
    var code = ""
    var status: UInt16 = 0
    try {
        e.getResponse(bob, r.response.id)
    } catch (err: EngineError) {
        code = err.code
        status = err.httpStatus
    }
    // 越权必须是 404 而不是 403（403 会确认 id 存在）
    @Expect(code, "response_not_found")
    @Expect(status, UInt16(404))
}

@Test
func engine_budget_stop_maps_to_incomplete_with_reason(): Unit {
    let h = ScriptedHarness([ScriptStep.Text("partial")], TurnOutcome.Incomplete(IncompleteReason.MaxSteps, None))
    let e = engineWith([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)])
    let r = e.createTask(Principal("alice"), TaskRequest("hi"))
    @Expect(r.response.status, "incomplete")
    let details = r.response.incomplete_details ?? ResponseIncompleteDetails()
    @Expect(details.extras.get("reason") ?? "", "\"max_steps\"")
    // 已产出的部分必须保留
    @Expect(r.response.output.size, 1)
    // 终态事件是 response.incomplete（不是 completed）
    let evs = r.channel.replay(0)
    @Expect(evs[evs.size - 1].eventType, "response.incomplete")
}

@Test
func engine_driver_exception_maps_to_failed_not_completed(): Unit {
    let e = engineWith([ConfiguredHarness("chrn_1", "n", "boom", "m", ThrowingHarness())])
    let r = e.createTask(Principal("alice"), TaskRequest("hi"))
    @Expect(r.response.status, "failed")
    @Expect((r.response.error ?? ErrorObject()).code, "harness_error")
}

@Test
func engine_cancel_on_terminal_task_is_noop_success(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    let c = e.cancelResponse(p, r.response.id)
    @Expect(c.status, "completed")
}

@Test
func engine_delete_response_then_read_is_404(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("hi"))
    @Expect(e.deleteResponse(p, r.response.id), true)
    var code = ""
    try {
        e.getResponse(p, r.response.id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "response_not_found")
}

@Test
func engine_discovery_matches_conformance_class(): Unit {
    let e = engineWith([scripted("chrn_1")])
    let d = e.discovery()
    @Expect(d.protocol, "uhp")
    @Expect(d.versions[0], "2026-10-19")
    @Expect(d.default_version, "2026-10-19")
    @Expect(d.conformance_class, "core")
    // 服务端 MUST 报 false 而不是省略 → 16 个能力键都要在序列化结果里
    let s = jsonOf(d)
    @Expect(s.contains("harness_management"), true)
    @Expect(s.contains("streaming"), true)
}
