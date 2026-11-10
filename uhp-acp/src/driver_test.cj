// 适配器测试：用真的 ACP 协议（stdio 子进程）跑假 agent，
// 验证 session/update -> TurnSink 的映射、终态映射、取消。
package uhp_acp

import std.collection.{ArrayList, HashMap}
import std.fs.{File as FsFile, Path}
import std.fs.canonicalize
import std.sync.{AtomicBool, Mutex}
import std.unittest.*
import std.unittest.testmacro.*
import uhp.server.*
import std.io.{ByteBuffer, InputStream}
import stdx.encoding.json.stream.*
import stdx.net.http.*
import uhp.types.generated.*

// 假 agent 二进制：workspace 根 target 或成员目录 target 都找一下
// （cjpm bundle 会在成员目录里跑测试，产物在 workspace 根 target 下）
func fakeAgentPath(): String {
    let cwd = canonicalize(".").toString()
    let direct = cwd + "/target/release/bin/uhp_acp.examples.fake_agent"
    let parent = cwd + "/../target/release/bin/uhp_acp.examples.fake_agent"
    if (readable(direct)) {
        return direct
    }
    if (readable(parent)) {
        return parent
    }
    return direct
}

func readable(path: String): Bool {
    try {
        let _ = FsFile.readFrom(Path(path))
        return true
    } catch (e: Exception) {
        return false
    }
}

func optionsFor(): AcpOptions {
    return AcpOptions(fakeAgentPath(), cwd: "/tmp")
}

// 测试里创建的 driver 会在下一条用例开始时统一关闭：每个 driver 都持有假 agent 子进程 +
// 一个阻塞读的接收线程，9 条用例全留着就是 9 份常驻资源，在 4 核 runner 上足以把调度拖死。
let liveDrivers = ArrayList<AcpDriver>()

func newDriver(opts: AcpOptions): AcpDriver {
    for (d in liveDrivers) {
        d.close()
    }
    liveDrivers.clear()
    let d = AcpDriver(opts)
    liveDrivers.add(d)
    return d
}

class RecordingSink <: TurnSink {
    public var text: String = ""
    public var reasoning: String = ""
    public var calls: ArrayList<(String, String)> = ArrayList<(String, String)>()
    public var results: ArrayList<(String, String)> = ArrayList<(String, String)>()
    // 多个会话并发时用前缀区分「这个 callId 是哪个 sink 发出去的」
    public var idPrefix: String = ""
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
        return this.idPrefix + "call_" + this.seq.toString()
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

    public var produced: ArrayList<(String, String)> = ArrayList<(String, String)>()

    public func producedFile(filename: String, content: Array<UInt8>): Unit {
        this.produced.add((filename, String.fromUtf8(content)))
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
    let driver = newDriver(optionsFor())
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
    let driver = newDriver(optionsFor())
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
    let driver = newDriver(optionsFor())
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


@Test
func acp_permission_becomes_input_request(): Unit {
    let opts = AcpOptions(fakeAgentPath(), cwd: "/tmp", timeoutSeconds: 60,
        permissionTimeoutSeconds: 60)
    let driver = newDriver(opts)
    let sink1 = RecordingSink()
    let first = driver.run(TurnContext("uhp-acp-perm", "perm please", "m"), sink1, CancelToken())
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
    @Expect(ask1[0], "choice")
    @Expect(ask1[1].contains("Run shell command"), true)
    @Expect(ask1[2].size, 2)
    // 续跑：答案回到挂起的权限请求，Agent 继续，本轮完成
    let sink2 = RecordingSink()
    let second = driver.run(TurnContext("uhp-acp-perm", "", "m", answers: ["once"]), sink2, CancelToken())
    var completed = false
    match (second) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    @Expect(sink2.text.contains("perm answered: once"), true)
}


// ---- 全栈：UHP 服务端（Engine + AcpDriver） -> 假 ACP agent ----
func acpTaskBody(input: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("input").writeValue(input)
    w.writeName("metadata")
    w.startObject()
    w.writeName("harness_id").writeValue("chrn_acp")
    w.endObject()
    w.writeName("stream").writeValue(false)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func acpAnswerBody(prev: String, requestId: String, answer: String): String {
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

func acpHttpJson(url: String, body: String): String {
    let client = ClientBuilder().noProxy().readTimeout(Duration.second * 120).build()
    try {
        let req = HttpRequestBuilder()
            .method("POST")
            .url(url)
            .header("authorization", "Bearer t")
            .header("UHP-Version", "2026-10-19")
            .header("content-type", "application/json")
            .body(body)
            .build()
        let rsp = client.send(req)
        return readAllText2(rsp.body)
    } finally {
        client.close()
    }
}

func readAllText2(body: InputStream): String {
    let chunks = ArrayList<UInt8>()
    let buf = Array<UInt8>(8192, repeat: 0)
    while (true) {
        let n = body.read(buf)
        if (n <= 0) {
            break
        }
        chunks.add(all: buf[0..n])
    }
    return String.fromUtf8(chunks.toArray())
}

func jsonStr(text: String, key: String): String {
    let q = "\""
    let marker = q + key + q
    let i = match (text.indexOf(marker)) {
        case Some(v) => v + marker.size
        case None => return ""
    }
    var j = i
    let arr = text.toArray()
    while (j < arr.size && (arr[j] == UInt8(58) || arr[j] == UInt8(32))) {
        j = j + 1
    }
    if (j >= arr.size || arr[j] != UInt8(34)) {
        return ""
    }
    j = j + 1
    var end = j
    while (end < arr.size && arr[end] != UInt8(34)) {
        end = end + 1
    }
    return String.fromUtf8(arr[j..end])
}

func waitPort2(server: Server): UInt16 {
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

@Test
func full_stack_acp_question_flows_through_uhp_server(): Unit {
    let opts = AcpOptions(fakeAgentPath(), cwd: "/tmp", timeoutSeconds: 120,
        permissionTimeoutSeconds: 120)
    let driver = newDriver(opts)
    let harness = ConfiguredHarness("chrn_acp", "ACP agent", "acp", "acp-agent", driver)
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
    let url = "http://127.0.0.1:" + waitPort2(server).toString()
    let first = acpHttpJson(url + "/v1/responses", acpTaskBody("perm please"))
    @Expect(jsonStr(first, "status"), "incomplete")
    let firstId = jsonStr(first, "id")
    let requestId = jsonStr(first, "input_request_id")
    // input_request item 里是 "id":"inreq_..."，这里用更稳的方式：直接找 inreq_ 前缀串
    var rid = requestId
    if (!rid.startsWith("inreq_")) {
        let idx = match (first.indexOf("inreq_")) {
            case Some(v) => v
            case None => 0
        }
        if (idx > 0) {
            var end = idx
            let arr = first.toArray()
            while (end < arr.size && arr[end] != UInt8(34)) {
                end = end + 1
            }
            rid = String.fromUtf8(arr[idx..end])
        }
    }
    @Expect(rid.startsWith("inreq_"), true)
    let second = acpHttpJson(url + "/v1/responses", acpAnswerBody(firstId, rid, "once"))
    @Expect(jsonStr(second, "status"), "completed")
    @Expect(second.contains("perm answered: once"), true)
    server.close()
}


@Test
func input_files_are_mapped_to_acp_content_blocks(): Unit {
    let driver = newDriver(optionsFor())
    let sink = RecordingSink()
    let files = [
        TurnFile("notes.txt", "text/plain", "alpha".toArray()),
        TurnFile("pic.png", "image/png", [0x89, 0x50, 0x4e, 0x47])
    ]
    let ctx = TurnContext("uhp-acp-files", "files please", "m", files: files)
    let outcome = driver.run(ctx, sink, CancelToken())
    var completed = false
    match (outcome) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    // 1 个文本块 + 2 个文件块（txt 走 text 块、png 走 image 块）
    @Expect(sink.text.contains("files: 3 images: 1"), true)
}


@Test
func acp_diff_update_becomes_produced_file(): Unit {
    let driver = newDriver(optionsFor())
    let sink = RecordingSink()
    let outcome = driver.run(TurnContext("uhp-acp-write", "writefile please", "m"), sink, CancelToken())
    var completed = false
    match (outcome) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    @Expect(sink.produced.size, 1)
    let f0 = sink.produced[0]
    @Expect(f0[0], "out.txt")
    @Expect(f0[1], "artifact-ok")
}

func acpHttpGet(url: String): String {
    let client = ClientBuilder().noProxy().readTimeout(Duration.second * 60).build()
    try {
        let req = HttpRequestBuilder()
            .method("GET")
            .url(url)
            .header("authorization", "Bearer t")
            .header("UHP-Version", "2026-10-19")
            .build()
        let rsp = client.send(req)
        return readAllText2(rsp.body)
    } finally {
        client.close()
    }
}

@Test
func full_stack_artifact_is_listed_and_downloadable(): Unit {
    let driver = newDriver(optionsFor())
    let harness = ConfiguredHarness("chrn_acp", "ACP agent", "acp", "acp-agent", driver)
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
    let url = "http://127.0.0.1:" + waitPort2(server).toString()
    let first = acpHttpJson(url + "/v1/responses", acpTaskBody("writefile please"))
    @Expect(jsonStr(first, "status"), "completed")
    let sid = jsonStr(first, "session_id")
    @Expect(sid.size > 0, true)
    let listBody = acpHttpGet(url + "/v1/sessions/" + sid + "/files")
    let fid = jsonStr(listBody, "id")
    let cid = jsonStr(listBody, "container_id")
    @Expect(fid.size > 0, true)
    @Expect(cid.size > 0, true)
    let content = acpHttpGet(url + "/v1/containers/" + cid + "/files/" + fid + "/content")
    @Expect(content, "artifact-ok")
    server.close()
}


@Test
func acp_elicitation_becomes_input_request(): Unit {
    let driver = newDriver(optionsFor())
    let sink1 = RecordingSink()
    let first = driver.run(TurnContext("uhp-acp-elicit", "elicit please", "m"), sink1, CancelToken())
    var incomplete = false
    match (first) {
        case TurnOutcome.Incomplete(_, _) => incomplete = true
        case _ => ()
    }
    @Expect(incomplete, true)
    @Expect(sink1.asks.size, 1)
    let ask1 = sink1.asks[0]
    @Expect(ask1[0], "free_text")
    @Expect(ask1[1].contains("Your name"), true)
    let sink2 = RecordingSink()
    let second = driver.run(TurnContext("uhp-acp-elicit", "", "m", answers: ["Ada"]), sink2, CancelToken())
    var completed = false
    match (second) {
        case TurnOutcome.Completed(_) => completed = true
        case _ => ()
    }
    @Expect(completed, true)
    @Expect(sink2.text.contains("elicitation: accept"), true)
    @Expect(sink2.text.contains("Ada"), true)
}


@Test
func acp_close_releases_agent_and_allows_reconnect(): Unit {
    // close() 是适配器的生命周期出口：Agent 子进程与接收线程都在 driver 上，
    // 不关就常驻（每条用例/每次换 driver 留一份，积到 CPU 核数就把调度拖死）。
    // 锚点：幂等 + 关掉之后还能重新拉起 Agent 继续跑。
    let driver = newDriver(optionsFor())
    let first = driver.run(TurnContext("uhp-acp-close-1", "hello", "m"), RecordingSink(), CancelToken())
    var ok1 = false
    match (first) {
        case TurnOutcome.Completed(_) => ok1 = true
        case _ => ()
    }
    @Expect(ok1, true)
    driver.close()
    driver.close()
    let sink = RecordingSink()
    let second = driver.run(TurnContext("uhp-acp-close-2", "hello", "m"), sink, CancelToken())
    var ok2 = false
    match (second) {
        case TurnOutcome.Completed(_) => ok2 = true
        case _ => ()
    }
    @Expect(ok2, true)
    @Expect(sink.text, "echo: hello")
}



// ---- 会话执行模式：Serial（默认）/ Parallel ----

@Test
func parallel_sessions_keep_sinks_apart(): Unit {
    // Parallel 的前提是 agent 支持「同一连接内不同会话并发执行回合」（DSH ACP profile 明确支持）。
    // 锚点：两个会话同时在吐各自的 tick；互相看不到对方的输出。
    let opts = AcpOptions(fakeAgentPath(), cwd: "/tmp", timeoutSeconds: 60,
        sessionMode: AcpSessionMode.Parallel)
    let driver = newDriver(opts)
    let sinkA = RecordingSink()
    let sinkB = RecordingSink()
    let cancelA = CancelToken()
    let cancelB = CancelToken()
    let d = driver
    let ta = spawn {
        d.run(TurnContext("uhp-acp-par-a", "slow a", "m"), sinkA, cancelA)
    }
    let tb = spawn {
        d.run(TurnContext("uhp-acp-par-b", "slow b", "m"), sinkB, cancelB)
    }
    var bothTicking = false
    var waited = 0
    while (waited < 3000) {
        if (sinkA.text.contains("slow a") && sinkB.text.contains("slow b")) {
            bothTicking = true
            break
        }
        sleep(Duration.millisecond * 20)
        waited = waited + 20
    }
    @Expect(bothTicking, true)
    cancelA.cancel()
    cancelB.cancel()
    let _ = ta.get()
    let _ = tb.get()
    @Expect(sinkA.text.contains("slow b"), false)
    @Expect(sinkB.text.contains("slow a"), false)
}

@Test
func serial_mode_queues_overlapping_calls(): Unit {
    // Serial（默认）：调用方并发调 run 也只是排队，不会互相覆盖 sink。
    let driver = newDriver(optionsFor())
    let sinkA = RecordingSink()
    let sinkB = RecordingSink()
    let d = driver
    let ta = spawn {
        d.run(TurnContext("uhp-acp-ser-a", "hello a", "m"), sinkA, CancelToken())
    }
    let tb = spawn {
        d.run(TurnContext("uhp-acp-ser-b", "hello b", "m"), sinkB, CancelToken())
    }
    let oa = ta.get()
    let ob = tb.get()
    var okA = false
    var okB = false
    match (oa) {
        case TurnOutcome.Completed(_) => okA = true
        case _ => ()
    }
    match (ob) {
        case TurnOutcome.Completed(_) => okB = true
        case _ => ()
    }
    @Expect(okA, true)
    @Expect(okB, true)
    @Expect(sinkA.text, "echo: hello a")
    @Expect(sinkB.text, "echo: hello b")
}

@Test
func parallel_tool_calls_do_not_cross_sessions(): Unit {
    // 两个会话的 ACP toolCallId 都是 call_write：按会话分开映射，toolResult 不能串到对方回合。
    let opts = AcpOptions(fakeAgentPath(), cwd: "/tmp", timeoutSeconds: 60,
        sessionMode: AcpSessionMode.Parallel)
    let driver = newDriver(opts)
    let sinkA = RecordingSink()
    let sinkB = RecordingSink()
    sinkA.idPrefix = "a-"
    sinkB.idPrefix = "b-"
    let d = driver
    let ta = spawn {
        d.run(TurnContext("uhp-acp-par-tool-a", "writefile a", "m"), sinkA, CancelToken())
    }
    let tb = spawn {
        d.run(TurnContext("uhp-acp-par-tool-b", "writefile b", "m"), sinkB, CancelToken())
    }
    let _ = ta.get()
    let _ = tb.get()
    @Expect(sinkA.produced.size, 1)
    @Expect(sinkB.produced.size, 1)
    @Expect(sinkA.results.size, 1)
    @Expect(sinkB.results.size, 1)
    @Expect(sinkA.results[0][0], "a-call_1")
    @Expect(sinkB.results[0][0], "b-call_1")
    @Expect(sinkA.results[0][1].contains("wrote-out writefile a"), true)
    @Expect(sinkB.results[0][1].contains("wrote-out writefile b"), true)
}

@Test
func close_session_releases_and_recreates(): Unit {
    // closeSession 是会话级回收：Agent 侧作用域释放，本地映射摘掉，同 id 再跑会重新建会话。
    let driver = newDriver(optionsFor())
    let first = driver.run(TurnContext("uhp-acp-close-sess", "hello", "m"), RecordingSink(), CancelToken())
    var ok1 = false
    match (first) {
        case TurnOutcome.Completed(_) => ok1 = true
        case _ => ()
    }
    @Expect(ok1, true)
    driver.closeSession("uhp-acp-close-sess")
    driver.closeSession("uhp-acp-unknown")
    let sink = RecordingSink()
    let second = driver.run(TurnContext("uhp-acp-close-sess", "hello again", "m"), sink, CancelToken())
    var ok2 = false
    match (second) {
        case TurnOutcome.Completed(_) => ok2 = true
        case _ => ()
    }
    @Expect(ok2, true)
    @Expect(sink.text, "echo: hello again")
}

