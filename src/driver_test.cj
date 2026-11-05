// 适配器测试：起一个假 opencode（实现 session/prompt/event/interrupt 子集），
// 验证事件 -> TurnSink 的映射、终态判定、中断与失败路径。不依赖公网与真实模型。
package uhp_opencode

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import std.sync.Mutex
import std.unittest.*
import std.unittest.testmacro.*
import stdx.net.http.*
import uhp.server.*
import uhp.transport.*
import uhp.types.generated.*
import uhp_opencode.client.*

class FakeState {
    public let lock = Mutex()
    public var prompted: Bool = false
    public var interrupted: Bool = false
    public var sessions: Int64 = 0
    public var permissionReplied: Option<String> = None
    public var formReplied: Option<String> = None
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
        if (method == "POST" && path.contains("/permission/") && path.endsWith("/reply")) {
            let body = ocReadAllText(ctx.request.body)
            let decision = match (ocParseJson(body)) {
                case Some(o) => o.str("decision") ?? ""
                case None => ""
            }
            synchronized(this.state.lock) {
                this.state.permissionReplied = Some(decision)
            }
            ctx.responseBuilder.status(UInt16(204))
            return
        }
        if (method == "POST" && path.contains("/form/") && path.endsWith("/reply")) {
            let body = ocReadAllText(ctx.request.body)
            synchronized(this.state.lock) {
                this.state.formReplied = Some(body)
            }
            ctx.responseBuilder.status(UInt16(204))
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
        if (this.mode == "form" || this.mode == "formtext") {
            this.emit(w, "form.created", formCreatedJson(this.mode == "form"))
            let deadline3 = nowMillis() + 10000
            var replied = false
            while (nowMillis() < deadline3) {
                let r3 = synchronized(this.state.lock) {
                    this.state.formReplied
                }
                match (r3) {
                    case Some(_) =>
                        replied = true
                        break
                    case None => ()
                }
                sleep(Duration.millisecond * 10)
            }
            if (!replied) {
                this.emit(w, "session.execution.failed", sidJson)
                return
            }
            this.emit(w, "session.text.delta", textDeltaJson("form answered"))
            this.emit(w, "session.execution.succeeded", sidJson)
            return
        }
        if (this.mode == "permission") {
            this.emit(w, "permission.asked", permissionAskedJson())
            let deadline2 = nowMillis() + 10000
            var decision = ""
            while (nowMillis() < deadline2) {
                let d2 = synchronized(this.state.lock) {
                    this.state.permissionReplied
                }
                match (d2) {
                    case Some(v) =>
                        decision = v
                        break
                    case None => ()
                }
                sleep(Duration.millisecond * 10)
            }
            this.emit(w, "session.text.delta", textDeltaJson("decided " + decision))
            this.emit(w, "session.execution.succeeded", sidJson)
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
                this.emit(w, "session.text.delta", textDeltaJson("tick "))
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
        this.emit(w, "session.text.delta", textDeltaJson("Hello "))
        this.emit(w, "session.text.delta", textDeltaJson("world"))
        this.emit(w, "session.usage.updated",
            "{\"sessionID\":" + ocJsonQuote(SID) + ",\"tokens\":{\"input\":10,\"output\":2,\"reasoning\":1,\"cache\":{\"read\":5,\"write\":0}}}")
        this.emit(w, "session.execution.succeeded", sidJson)
    }
}

func formCreatedJson(withOptions: Bool): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("sessionID").writeValue(SID)
    w.writeName("id").writeValue("frm_1")
    w.writeName("title").writeValue(if (withOptions) { "Pick a size" } else { "Your name" })
    w.writeName("fields")
    w.startArray()
    w.startObject()
    w.writeName("key").writeValue(if (withOptions) { "size" } else { "name" })
    w.writeName("type").writeValue("string")
    w.writeName("title").writeValue(if (withOptions) { "Pick a size" } else { "Your name" })
    if (withOptions) {
        w.writeName("options")
        w.startArray()
        w.startObject()
        w.writeName("value").writeValue("s")
        w.writeName("label").writeValue("Small")
        w.endObject()
        w.startObject()
        w.writeName("value").writeValue("l")
        w.writeName("label").writeValue("Large")
        w.endObject()
        w.endArray()
    }
    w.endObject()
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func permissionAskedJson(): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("sessionID").writeValue(SID)
    w.writeName("id").writeValue("per_1")
    w.writeName("action").writeValue("shell")
    w.writeName("resources")
    w.startArray()
    w.writeValue("echo hi")
    w.endArray()
    w.writeName("message").writeValue("Allow shell command?")
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func textDeltaJson(delta: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("sessionID").writeValue(SID)
    w.writeName("delta").writeValue(delta)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
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

    public var asks: ArrayList<(String, String, Array<(String, String)>)> = ArrayList<(String, String, Array<(String, String)>)>()

    public func ask(kind: String, prompt: String, options: Array<(String, String)>): String {
        this.asks.add((kind, prompt, options))
        return "inreq_test"
    }

    public func producedFile(filename: String, content: Array<UInt8>): Unit {
        ()
    }
}


@Test
func permission_becomes_input_request_and_resumes(): Unit {
    let (server, state) = startFake("permission")
    let driver = OpencodeDriver(optionsFor(server))
    let sink1 = RecordingSink()
    let first = driver.run(TurnContext("uhp-perm", "run it", "m"), sink1, CancelToken())
    var incomplete = false
    match (first) {
        case TurnOutcome.Incomplete(reason, _) =>
            incomplete = true
            @Expect(incompleteReasonName(reason), "input_required")
        case _ => ()
    }
    @Expect(incomplete, true)
    @Expect(sink1.asks.size, 1)
    let ask1 = sink1.asks[0]
    @Expect(ask1[0], "confirm")
    @Expect(ask1[1].contains("Allow"), true)
    @Expect(ask1[2].size, 3)
    // 续跑：答案作为权限决定回给 opencode，然后继续读事件
    let sink2 = RecordingSink()
    let second = driver.run(TurnContext("uhp-perm", "", "m", answers: ["once"]), sink2, CancelToken())
    var completed = false
    match (second) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    @Expect(sink2.text.contains("decided once"), true)
    let decision = synchronized(state.lock) {
        state.permissionReplied
    }
    @Expect(decision, Some("once"))
    server.close()
}


// ---- 全栈：UHP 服务端（Engine + OpencodeDriver）-> 假 opencode ----
func firstTaskBody(): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("input").writeValue("run it")
    w.writeName("metadata")
    w.startObject()
    w.writeName("harness_id").writeValue("chrn_oc")
    w.endObject()
    w.writeName("stream").writeValue(false)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func answerTaskBody(prev: String, requestId: String, answer: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("previous_response_id").writeValue(prev)
    w.writeName("input")
    w.startArray()
    w.startObject()
    w.writeName("type").writeValue("input_response")
    w.writeName("input_request_id").writeValue(requestId)
    w.writeName("answer").writeValue(answer)
    w.endObject()
    w.endArray()
    w.writeName("stream").writeValue(false)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func httpJson(url: String, body: String, token: String): String {
    let client = ClientBuilder().noProxy().readTimeout(Duration.second * 60).build()
    try {
        let req = HttpRequestBuilder()
            .method("POST")
            .url(url)
            .header("authorization", "Bearer " + token)
            .header("UHP-Version", "2026-10-19")
            .header("content-type", "application/json")
            .body(body)
            .build()
        let rsp = client.send(req)
        return ocReadAllText(rsp.body)
    } finally {
        client.close()
    }
}

@Test
func full_stack_question_flows_through_uhp_server(): Unit {
    let (ocServer, _) = startFake("permission")
    let driver = OpencodeDriver(optionsFor(ocServer))
    let harness = ConfiguredHarness("chrn_oc", "opencode", "opencode", "m", driver)
    let engine = Engine([harness])
    let tokens = HashMap<String, String>()
    tokens["t"] = "p"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(0)
        .distributor(uhp.distributor())
        .build()
    let s = server
    spawn {
        s.serve()
    }
    let port = waitPort(server)
    let url = "http://127.0.0.1:" + port.toString()
    // 1) 第一次：opencode 要工具批准 -> UHP 必须是 incomplete + input_request
    let first = httpJson(url + "/v1/responses", firstTaskBody(), "t")
    let firstObj = match (ocParseJson(first)) {
        case Some(o) => o
        case None => throw Exception("bad first response")
    }
    @Expect(firstObj.str("status"), Some("incomplete"))
    let firstId = firstObj.str("id") ?? ""
    var requestId = ""
    for ((_, itemRaw) in ocJsonStrings(firstObj.raw("output") ?? "[]", "type")) {
        match (ocParseJson(itemRaw)) {
            case Some(item) =>
                if ((item.str("type") ?? "") == "input_request") {
                    requestId = item.str("id") ?? ""
                }
            case None => ()
        }
    }
    @Expect(requestId.startsWith("inreq_"), true)
    // 2) 第二次：回答问题 -> 服务端把答案当权限决定回给 opencode -> completed
    let answerBody = answerTaskBody(firstId, requestId, "once")
    let second = httpJson(url + "/v1/responses", answerBody, "t")
    let secondObj = match (ocParseJson(second)) {
        case Some(o) => o
        case None => throw Exception("bad second response")
    }
    @Expect(secondObj.str("status"), Some("completed"))
    @Expect(second.contains("decided once"), true)
    server.close()
    ocServer.close()
}


@Test
func form_choice_becomes_input_request(): Unit {
    let (server, state) = startFake("form")
    let driver = OpencodeDriver(optionsFor(server))
    let sink1 = RecordingSink()
    let first = driver.run(TurnContext("uhp-form", "ask", "m"), sink1, CancelToken())
    var incomplete = false
    match (first) {
        case TurnOutcome.Incomplete(_, _) => incomplete = true
        case _ => ()
    }
    @Expect(incomplete, true)
    @Expect(sink1.asks.size, 1)
    let ask1 = sink1.asks[0]
    @Expect(ask1[0], "choice")
    @Expect(ask1[2].size, 2)
    let sink2 = RecordingSink()
    let second = driver.run(TurnContext("uhp-form", "", "m", answers: ["l"]), sink2, CancelToken())
    var completed = false
    match (second) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    let reply = synchronized(state.lock) {
        state.formReplied
    }
    match (reply) {
        case Some(body) => @Expect(body.contains(ocJsonQuote("size") + ":" + ocJsonQuote("l")), true)
        case None => @Expect(false, true)
    }
    server.close()
}

@Test
func form_text_becomes_free_text(): Unit {
    let (server, state) = startFake("formtext")
    let driver = OpencodeDriver(optionsFor(server))
    let sink1 = RecordingSink()
    let _ = driver.run(TurnContext("uhp-form2", "ask", "m"), sink1, CancelToken())
    @Expect(sink1.asks.size, 1)
    let ask1 = sink1.asks[0]
    @Expect(ask1[0], "free_text")
    let sink2 = RecordingSink()
    let second = driver.run(TurnContext("uhp-form2", "", "m", answers: ["Ada"]), sink2, CancelToken())
    var completed = false
    match (second) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    let reply = synchronized(state.lock) {
        state.formReplied
    }
    match (reply) {
        case Some(body) => @Expect(body.contains(ocJsonQuote("name") + ":" + ocJsonQuote("Ada")), true)
        case None => @Expect(false, true)
    }
    server.close()
}
