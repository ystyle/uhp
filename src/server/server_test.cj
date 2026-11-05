// L2 行为测试：服务端核心（事件通道 / 状态机 / driver 接缝），全部离线。
package uhp.server

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.generated.*

// ---------- 事件通道 ----------

@Test
func channel_assigns_strictly_increasing_sequence(): Unit {
    let ch = EventChannel()
    @Expect(ch.emit("response.created", "{}"), 0)
    @Expect(ch.emit("response.output_text.delta", "{}"), 1)
    @Expect(ch.emit("response.completed", "{}"), 2)
    @Expect(ch.lastSeq(), 2)
    @Expect(ch.count(), 3)
}

@Test
func channel_replay_from_seq_is_inclusive(): Unit {
    let ch = EventChannel()
    ch.emit("a", "{}")
    ch.emit("b", "{}")
    ch.emit("c", "{}")
    // 重连语义：客户端说「我收到 0」，就从 1 开始给（Last-Event-ID 是已收到的最大序号）
    let rest = ch.replay(1)
    @Expect(rest.size, 2)
    @Expect(rest[0].seq, 1)
    @Expect(rest[1].seq, 2)
    @Expect(ch.replay(0).size, 3)
    @Expect(ch.replay(3).size, 0)
}

@Test
func channel_closed_rejects_emit(): Unit {
    let ch = EventChannel()
    ch.emit("a", "{}")
    ch.close()
    @Expect(ch.isClosed(), true)
    @Expect(ch.emit("b", "{}"), -1)
    @Expect(ch.count(), 1)
}

// ---------- 任务状态机 ----------

@Test
func terminal_status_is_immutable(): Unit {
    let s = ResponseState()
    @Expect(s.transition(TaskStatus.Completed), true)
    // 终态之后任何迁移都被拒绝，不覆盖已有结果
    @Expect(s.transition(TaskStatus.Failed), false)
    @Expect(taskStatusName(s.status()), "completed")
    @Expect(s.hadOutcome(), true)
}

@Test
func cancelled_is_terminal_and_not_failed(): Unit {
    let s = ResponseState()
    @Expect(s.transition(TaskStatus.Cancelled), true)
    @Expect(taskStatusName(s.status()), "cancelled")
}

@Test
func incomplete_is_terminal(): Unit {
    let s = ResponseState()
    @Expect(isTerminalStatus(TaskStatus.Incomplete), true)
    @Expect(isTerminalStatus(TaskStatus.InProgress), false)
}

// ---------- 会话并发 ----------

@Test
func session_rejects_second_task_while_busy(): Unit {
    let sess = SessionState("hsess1", "chrn_1")
    @Expect(sess.tryBegin("resp_1"), true)
    @Expect(sess.tryBegin("resp_2"), false)   // 调用方据此回 409 session_busy
    @Expect(sess.isBusy(), true)
    sess.finish()
    @Expect(sess.tryBegin("resp_2"), true)
}

@Test
func session_rejects_different_harness(): Unit {
    let sess = SessionState("hsess1", "chrn_1")
    @Expect(sess.acceptsHarness("chrn_1"), true)
    @Expect(sess.acceptsHarness("chrn_2"), false)   // 调用方据此回 409 harness_mismatch
}

// ---------- driver 接缝 ----------

class RecordingSink <: TurnSink {
    public var texts: ArrayList<String> = ArrayList<String>()
    public var reasonings: ArrayList<String> = ArrayList<String>()
    public var tools: ArrayList<String> = ArrayList<String>()
    public var degraded: ArrayList<String> = ArrayList<String>()

    public func textDelta(delta: String): Unit {
        this.texts.add(delta)
    }

    public func reasoningDelta(delta: String): Unit {
        this.reasonings.add(delta)
    }

    public func toolCallArgsDelta(delta: String): Unit {
        this.tools.add(delta)
    }

    public func degrade(reason: String): Unit {
        this.degraded.add(reason)
    }
}

@Test
func scripted_harness_emits_all_step_kinds(): Unit {
    let h = ScriptedHarness(
        [ScriptStep.Text("hel"), ScriptStep.Text("lo"), ScriptStep.Reasoning("think"), ScriptStep.ToolArgs("{\"a\":1}")],
        TurnOutcome.Completed(None)
    )
    let sink = RecordingSink()
    let outcome = h.run(TurnContext("hsess1", "hi", "scripted-model"), sink, CancelToken())
    match (outcome) {
        case Completed(_) => ()
        case _ => @Fail("应为 Completed")
    }
    @Expect(sink.texts.size, 2)
    @Expect(sink.reasonings.size, 1)
    @Expect(sink.tools.size, 1)
}

@Test
func cancelled_turn_returns_cancelled_and_keeps_partial(): Unit {
    // 跑完第 1 步后把自己取消：driver 必须在下一步前停住并返回 Cancelled
    let h = ScriptedHarness(
        [ScriptStep.Text("a"), ScriptStep.Text("b"), ScriptStep.Text("c")],
        TurnOutcome.Completed(None),
        cancelledAfter: 1
    )
    let sink = RecordingSink()
    let outcome = h.run(TurnContext("hsess1", "hi", "scripted-model"), sink, CancelToken())
    match (outcome) {
        case Cancelled(_) => ()
        case _ => @Fail("应为 Cancelled")
    }
    @Expect(sink.texts.size, 2)   // 已产出的部分保留
}

@Test
func budget_stop_must_be_incomplete_not_completed(): Unit {
    let h = ScriptedHarness([ScriptStep.Text("x")], TurnOutcome.Incomplete(IncompleteReason.MaxSteps, None))
    let sink = RecordingSink()
    let outcome = h.run(TurnContext("hsess1", "hi", "scripted-model"), sink, CancelToken())
    match (outcome) {
        case Incomplete(r, _) => @Expect(incompleteReasonName(r), "max_steps")
        case Completed(_) => @Fail("预算截断不允许报 completed")
        case _ => @Fail("应为 Incomplete")
    }
}

// ---------- id 前缀 ----------

@Test
func ids_carry_type_prefix(): Unit {
    let ids = IdSource()
    @Expect(ids.harness().startsWith("chrn_"), true)
    @Expect(ids.response().startsWith("resp_"), true)
    @Expect(ids.session().startsWith("hsess"), true)
    @Expect(ids.file().startsWith("file_"), true)
    @Expect(ids.container().startsWith("cntr_"), true)
    // 不重复
    @Expect(ids.response() != ids.response(), true)
}
