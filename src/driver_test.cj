// 适配器测试：起一个假 opencode（实现 session/prompt/event/interrupt 子集），
// 验证事件 -> TurnSink 的映射、终态判定、中断与失败路径。不依赖公网与真实模型。
package uhp_opencode

import std.collection.{ArrayList, HashMap}
import std.io.*
import std.sync.Mutex
import std.unittest.*
import std.unittest.testmacro.*
import stdx.net.http.*
import uhp.server.*
import uhp.types.generated.*
import uhp_opencode.client.*

class FakeState {
    public let lock = Mutex()
    public var prompted: Bool = false
    public var interrupted: Bool = false
    public var sessions: Int64 = 0
}

const SID: String = "ocses_test_1"

class FakeDistributor <: HttpRequestDistributor {
    private let state: FakeState
    private let mode: String

    public init(state: FakeState, mode: String) {
        this.state = state
        this.mode = mode
    }

    public func register(path: String, h: HttpRequestHandler): Unit {
        ()
    }

    public func register(path: String, h: (HttpContext) -> Unit): Unit {
        ()
    }

    public func distribute(path: String): HttpRequestHandler {
        return FakeHandler(this.state, this.mode)
    }
}

class FakeHandler <: HttpRequestHandler {
    private let state: FakeState
    private let mode: String

    public init(state: FakeState, mode: String) {
        this.state = state
        this.mode = mode
    }

    public func handle(ctx: HttpContext): Unit {
        let path = ctx.request.url.path
        let method = ctx.request.method
        if (method == "POST" && path == "/api/session") {
            synchronized(this.state.lock) {
                this.state.sessions = this.state.sessions + 1
            }
            ctx.responseBuilder.status(UInt16(200)).header("content-type", "application/json")
                .body("{\"data\":{\"id\":" + ocJsonQuote(SID) + "}}")
            return
        }
        if (method == "POST" && path.endsWith("/model")) {
            ctx.responseBuilder.status(UInt16(200)).header("content-type", "application/json").body("{}")
            return
        }
        if (method == "POST" && path.endsWith("/prompt")) {
            synchronized(this.state.lock) {
                this.state.prompted = true
            }
            ctx.responseBuilder.status(UInt16(200)).header("content-type", "application/json").body("{}")
            return
        }
        if (method == "POST" && path.endsWith("/interrupt")) {
            synchronized(this.state.lock) {
                this.state.interrupted = true
            }
            ctx.responseBuilder.status(UInt16(200)).header("content-type", "application/json").body("{}")
            return
        }
        if (method == "GET" && path == "/api/event") {
            this.streamEvents(ctx)
            return
        }
        ctx.responseBuilder.status(UInt16(404)).body("{}")
    }

    private func emit(w: HttpResponseWriter, ty: String, data: String): Unit {
        w.write(("data: {\"type\":" + ocJsonQuote(ty) + ",\"data\":" + data + "}\n\n").toArray())
    }

    private func streamEvents(ctx: HttpContext): Unit {
        ctx.responseBuilder
            .status(UInt16(200))
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("transfer-encoding", "chunked")
            .header("x-accel-buffering", "no")
        let w = HttpResponseWriter(ctx)
        this.emit(w, "server.connected", "{}")
        // 等 prompt
        let deadline = nowMillis() + 10000
        while (nowMillis() < deadline) {
            let prompted = synchronized(this.state.lock) {
                this.state.prompted
            }
            if (prompted) {
                break
            }
            sleep(Duration.millisecond * 10)
        }
        let sidJson = "{\"sessionID\":" + ocJsonQuote(SID) + "}"
        if (this.mode == "fail") {
            this.emit(w, "session.execution.failed", sidJson)
            return
        }
        if (this.mode == "interrupt") {
            // 慢慢吐，等中断
            var i = 0
            while (i < 400) {
                let stop = synchronized(this.state.lock) {
                    this.state.interrupted
                }
                if (stop) {
                    this.emit(w, "session.execution.interrupted", sidJson)
                    return
                }
                this.emit(w, "session.text.delta",
                    "{\"sessionID\":" + ocJsonQuote(SID) + ",\"delta\":\"tick \"}")
                sleep(Duration.millisecond * 10)
                i = i + 1
            }
            this.emit(w, "session.execution.succeeded", sidJson)
            return
        }
        // happy path
        this.emit(w, "session.reasoning.delta",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"delta\":\"think\"}")
        this.emit(w, "session.tool.input.started",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"id\":\"c1\",\"name\":\"shell\"}")
        this.emit(w, "session.tool.called",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"id\":\"c1\",\"input\":{\"command\":\"echo hi\"}}")
        this.emit(w, "session.tool.success",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"id\":\"c1\",\"content\":[{\"type\":\"text\",\"text\":\"hi\\n\"}]}")
        this.emit(w, "session.text.delta",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"delta\":\"Hello \"}")
        this.emit(w, "session.text.delta",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"delta\":\"world\"}")
        this.emit(w, "session.usage.updated",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"tokens\":{\"input\":10,\"output\":2,\"reasoning\":1,\"cache\":{\"read\":5,\"write\":0}}}")
        this.emit(w, "session.execution.succeeded", sidJson)
    }
}

func startFake(mode: String): (Server, FakeState) {
    let state = FakeState()
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(0)
        .distributor(FakeDistributor(state, mode))
        .build()
    let s = server
    spawn {
        s.serve()
    }
    return (server, state)
}

func waitPort(server: Server): UInt16 {
    let deadline = nowMillis() + 5000
    while (nowMillis() < deadline) {
        let p = server.port
        if (p != UInt16(0)) {
            return p
        }
        sleep(Duration.millisecond * 10)
    }
    return server.port
}

func optionsFor(server: Server): OpencodeOptions {
    return OpencodeOptions("http://127.0.0.1:" + waitPort(server).toString(), "/tmp", password: "x")
}

class OutcomeBox {
    public let lock = Mutex()
    public var value: Option<TurnOutcome> = None

    public func set(v: TurnOutcome): Unit {
        synchronized(this.lock) {
            this.value = Some(v)
        }
    }

    public func get(): Option<TurnOutcome> {
        synchronized(this.lock) {
            return this.value
        }
    }
}

@Test
func happy_path_maps_events(): Unit {
    let (server, _) = startFake("happy")
    let driver = OpencodeDriver(optionsFor(server))
    let sink = RecordingSink()
    let outcome = driver.run(TurnContext("uhp-s1", "hi", "m"), sink, CancelToken())
    match (outcome) {
        case TurnOutcome.Completed(u) =>
            @Expect(u.isSome(), true)
        case _ => @Expect(false, true)
    }
    @Expect(sink.text, "Hello world")
    @Expect(sink.reasoning, "think")
    @Expect(sink.calls.size, 1)
    let c0 = sink.calls[0]
    @Expect(c0[0], "shell")
    @Expect(c0[1].contains("echo hi"), true)
    @Expect(sink.results.size, 1)
    let r0 = sink.results[0]
    @Expect(r0[1].contains("hi"), true)
    server.close()
}

@Test
func same_uhp_session_reuses_opencode_session(): Unit {
    let (server, state) = startFake("happy")
    let driver = OpencodeDriver(optionsFor(server))
    let _ = driver.run(TurnContext("uhp-same", "one", "m"), RecordingSink(), CancelToken())
    let _ = driver.run(TurnContext("uhp-same", "two", "m"), RecordingSink(), CancelToken())
    let n = synchronized(state.lock) {
        state.sessions
    }
    @Expect(n, 1)
    server.close()
}

@Test
func failure_path_reports_failed(): Unit {
    let (server, _) = startFake("fail")
    let driver = OpencodeDriver(optionsFor(server))
    let outcome = driver.run(TurnContext("uhp-s2", "hi", "m"), RecordingSink(), CancelToken())
    var failed = false
    match (outcome) {
        case TurnOutcome.Failed(_, _) => failed = true
        case _ => ()
    }
    @Expect(failed, true)
    server.close()
}

@Test
func cancel_interrupts_the_session(): Unit {
    let (server, state) = startFake("interrupt")
    let driver = OpencodeDriver(optionsFor(server))
    let cancel = CancelToken()
    let box = OutcomeBox()
    let t = spawn {
        let outcome = driver.run(TurnContext("uhp-s3", "hi", "m"), RecordingSink(), cancel)
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
    let interrupted = synchronized(state.lock) {
        state.interrupted
    }
    @Expect(interrupted, true)
    server.close()
}

// 记录 sink：断言映射结果
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
