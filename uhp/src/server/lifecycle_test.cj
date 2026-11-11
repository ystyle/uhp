// 宿主侧生命周期与动态 harness：close() / closeSession() 的可选契约、add/removeHarness 的边界。
// 这些不是协议端点——协议不规定 driver 生命周期，所以行为全由这里钉住。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.generated.*

// 记录生命周期的 driver：既跑脚本，又声明自己持有需要回收的资源
class LifecycleDriver <: HarnessDriver & HarnessLifecycle {
    private let lock = Mutex()
    public var closed: Int64 = 0
    public var closedSessions: ArrayList<String> = ArrayList<String>()
    private let reply: String

    public init(reply: String) {
        this.reply = reply
    }

    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "lifecycle"
    }

    public func models(): Array<Model> {
        let m = Model()
        m.id = "lifecycle-model"
        m.label = "lifecycle"
        m.available = true
        return [m]
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, true)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        sink.textDelta(this.reply)
        return TurnOutcome.Completed(None)
    }

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = this.closed + 1
        }
    }

    public func closeSession(sessionId: String): Unit {
        synchronized(this.lock) {
            this.closedSessions.add(sessionId)
        }
    }

    public func closeCount(): Int64 {
        synchronized(this.lock) {
            return this.closed
        }
    }

    public func sessionCloses(): Array<String> {
        synchronized(this.lock) {
            return this.closedSessions.toArray()
        }
    }
}

func principalOf(): Principal {
    return Principal("alice")
}

func taskReq(harnessId: String, input: String): TaskRequest {
    return TaskRequest(input, harnessId: Some(harnessId))
}

func sessionIdOf(r: Response): String {
    return match (r.metadata) {
        case Some(m) => m.session_id ?? ""
        case None => ""
    }
}

@Test
func add_harness_makes_it_usable_and_rejects_duplicate(): Unit {
    let engine = Engine([ConfiguredHarness("base", "base", "scripted", "auto",
        ScriptedHarness([ScriptStep.Text("from base")], TurnOutcome.Completed(None)))])
    let extra = LifecycleDriver("from extra")
    engine.addHarness(ConfiguredHarness("extra", "extra", "acp", "auto", extra))

    // 新 harness 能接任务
    let r = engine.createTask(principalOf(), taskReq("extra", "hi"))
    @Expect(r.response.status, "completed")
    // base 列表也跟着变（createHarness 的校验用它）
    @Expect(engine.supportedBaseList().contains("acp"), true)

    // id 重复必须拒绝：否则两个 driver 抢同一个 id，行为不可预期
    var threw = false
    try {
        engine.addHarness(ConfiguredHarness("extra", "dup", "acp", "auto", extra))
    } catch (e: EngineError) {
        threw = true
        @Expect(e.code, "invalid_input")
    }
    @Expect(threw, true)
}

@Test
func remove_harness_refused_while_session_bound_then_closes_driver(): Unit {
    let driver = LifecycleDriver("hi")
    let engine = Engine([ConfiguredHarness("only", "only", "scripted", "auto", driver)])
    let r = engine.createTask(principalOf(), taskReq("only", "hello"))
    let sid = sessionIdOf(r.response)
    @Expect(sid.size > 0, true)

    // 有会话绑着就不许卸载——静默丢会话比报错更难查
    var refused = false
    try {
        engine.removeHarness("only")
    } catch (e: EngineError) {
        refused = true
        @Expect(e.code, "harness_in_use")
    }
    @Expect(refused, true)
    @Expect(driver.closeCount(), 0)

    // 会话释放之后才能卸载，并且卸载要关掉 driver
    @Expect(engine.releaseSession(sid), true)
    engine.removeHarness("only")
    @Expect(driver.closeCount(), 1)
    @Expect(driver.sessionCloses().size, 1)
    @Expect(driver.sessionCloses()[0], sid)

    // 卸载之后同一个 id 指不到 harness 了
    var gone = false
    try {
        let _ = engine.createTask(principalOf(), taskReq("only", "again"))
    } catch (e: EngineError) {
        gone = true
        @Expect(e.code, "harness_not_found")
    }
    @Expect(gone, true)
}

@Test
func release_session_is_idempotent_and_reports_missing(): Unit {
    let driver = LifecycleDriver("hi")
    let engine = Engine([ConfiguredHarness("only", "only", "scripted", "auto", driver)])
    @Expect(engine.releaseSession("hsess_does_not_exist"), false)
    let r = engine.createTask(principalOf(), taskReq("only", "hello"))
    let sid = sessionIdOf(r.response)
    @Expect(engine.releaseSession(sid), true)
    // 再释放一次：已经没了，返回 false，且不能重复调 closeSession
    @Expect(engine.releaseSession(sid), false)
    @Expect(driver.sessionCloses().size, 1)
}

@Test
func engine_close_closes_every_lifecycle_driver_once(): Unit {
    let a = LifecycleDriver("a")
    let b = LifecycleDriver("b")
    let engine = Engine([
        ConfiguredHarness("a", "a", "scripted", "auto", a),
        ConfiguredHarness("b", "b", "scripted", "auto", b)])
    engine.close()
    engine.close()   // 幂等：宿主退出路径可能被走两遍
    @Expect(a.closeCount(), 2)
    @Expect(b.closeCount(), 2)
}

@Test
func driver_without_lifecycle_is_left_alone(): Unit {
    // ScriptedHarness 没有实现 HarnessLifecycle：Engine 直接跳过，不许因为「没实现」报错
    let engine = Engine([ConfiguredHarness("s", "s", "scripted", "auto",
        ScriptedHarness([ScriptStep.Text("x")], TurnOutcome.Completed(None)))])
    let r = engine.createTask(principalOf(), taskReq("s", "hi"))
    let sid = sessionIdOf(r.response)
    @Expect(engine.releaseSession(sid), true)
    engine.close()
}
