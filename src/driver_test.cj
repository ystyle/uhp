// 适配器测试：用真的 ACP 协议（stdio 子进程）跑假 agent，
// 验证 session/update -> TurnSink 的映射、终态映射、取消。
package uhp_acp

import std.collection.{ArrayList, HashMap}
import std.fs.canonicalize
import std.sync.{AtomicBool, Mutex}
import std.unittest.*
import std.unittest.testmacro.*
import uhp.server.*
import uhp.types.generated.*

func fakeAgentPath(): String {
    let cwd = canonicalize(".").toString()
    return cwd + "/target/release/bin/uhp_acp.examples.fake_agent"
}

func optionsFor(): AcpOptions {
    return AcpOptions(fakeAgentPath(), cwd: "/tmp")
}

class RecordingSink <: TurnSink {
    public var text: String = ""
    public var reasoning: String = ""
    public var calls: ArrayList<(String, String)> = ArrayList<(String, String)>()
    public var results: ArrayList<(String, String)> = ArrayList<(String, String)>()
    private var seq: Int64 = 0

    public func textDelta(delta: String): Unit {
        this.text = this.text + delta
    }

    public func reasoningDelta(delta: String): Unit {
        this.reasoning = this.reasoning + delta
    }

    public func toolCallArgsDelta(delta: String): Unit {
        ()
    }

    public func toolCall(name: String, arguments: String): String {
        this.calls.add((name, arguments))
        this.seq = this.seq + 1
        return "call_" + this.seq.toString()
    }

    public func toolResult(callId: String, output: String): Unit {
        this.results.add((callId, output))
    }

    public func degrade(reason: String): Unit {
        ()
    }

    public func ask(kind: String, prompt: String, options: Array<(String, String)>): String {
        return "inreq_test"
    }

    public func producedFile(filename: String, content: Array<UInt8>): Unit {
        ()
    }
}

class Box {
    public let lock = Mutex()
    public var v: Option<TurnOutcome> = None

    public func set(x: TurnOutcome): Unit {
        synchronized(this.lock) {
            this.v = Some(x)
        }
    }

    public func get(): Option<TurnOutcome> {
        synchronized(this.lock) {
            return this.v
        }
    }
}

@Test
func acp_round_trip_maps_updates(): Unit {
    let driver = AcpDriver(optionsFor())
    let sink = RecordingSink()
    let outcome = driver.run(TurnContext("uhp-acp-1", "hello", "m"), sink, CancelToken())
    var completed = false
    match (outcome) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    @Expect(sink.text, "echo: hello")
    @Expect(sink.reasoning.contains("thinking about hello"), true)
    @Expect(sink.calls.size, 1)
    let c0 = sink.calls[0]
    @Expect(c0[0], "echo")
}

@Test
func acp_stop_reasons_map_to_outcomes(): Unit {
    let driver = AcpDriver(optionsFor())
    let refused = driver.run(TurnContext("uhp-acp-2", "refuse please", "m"), RecordingSink(), CancelToken())
    var failed = false
    match (refused) {
        case TurnOutcome.Failed(_, _) => failed = true
        case _ => ()
    }
    @Expect(failed, true)
    let over = driver.run(TurnContext("uhp-acp-3", "maxturn", "m"), RecordingSink(), CancelToken())
    var incomplete = false
    match (over) {
        case TurnOutcome.Incomplete(_, _) => incomplete = true
        case _ => ()
    }
    @Expect(incomplete, true)
}

@Test
func acp_cancel_sends_session_cancel(): Unit {
    let driver = AcpDriver(optionsFor())
    let cancel = CancelToken()
    let box = Box()
    let t = spawn {
        let outcome = driver.run(TurnContext("uhp-acp-4", "slow", "m"), RecordingSink(), cancel)
        box.set(outcome)
    }
    sleep(Duration.millisecond * 400)
    cancel.cancel()
    let _ = t.get()
    let outcome = box.get()
    var cancelled = false
    match (outcome) {
        case Some(TurnOutcome.Cancelled(_)) => cancelled = true
        case _ => ()
    }
    @Expect(cancelled, true)
}
