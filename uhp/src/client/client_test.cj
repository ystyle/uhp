// L2 行为测试：客户端协议逻辑（发现/协商/错误映射/幂等/流消费），全部离线。
package uhp.client

import std.collection.{ArrayList, HashMap}
import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.handwritten.*
import uhp.types.generated.*
import uhp.transport.*

// ---------- 内存传输桩 ----------

class FakeSseStream <: SseStream {
    private var chunks: ArrayList<Array<UInt8>> = ArrayList<Array<UInt8>>()
    private var idx: Int64 = 0

    public init(chunks: Array<String>) {
        for (c in chunks) {
            this.chunks.add(c.toArray())
        }
    }

    public func nextChunk(): Option<Array<UInt8>> {
        if (this.idx >= this.chunks.size) {
            return None
        }
        let c = this.chunks[this.idx]
        this.idx = this.idx + 1
        return Some(c)
    }

    public func close(): Unit {}
}

class FakeTransport <: HttpTransport {
    public var requests: ArrayList<UhpRequest> = ArrayList<UhpRequest>()
    private var responses: ArrayList<UhpResponse> = ArrayList<UhpResponse>()
    private var streams: ArrayList<Array<String>> = ArrayList<Array<String>>()
    private var streamIdx: Int64 = 0

    public init(responses: Array<UhpResponse>, streams: Array<Array<String>>) {
        for (r in responses) {
            this.responses.add(r)
        }
        for (s in streams) {
            this.streams.add(s)
        }
    }

    public func send(req: UhpRequest): UhpResponse {
        this.requests.add(req)
        return this.responses.remove(at: 0)
    }

    public func stream(req: UhpRequest): StreamStart {
        this.requests.add(req)
        let c = this.streams[this.streamIdx]
        this.streamIdx = this.streamIdx + 1
        return StreamStart.Started(FakeSseStream(c))
    }
}

// ---------- 夹具 ----------

func headers(): HashMap<String, String> {
    let h = HashMap<String, String>()
    h["UHP-Version"] = "2026-10-19"
    h["content-type"] = "application/json"
    return h
}

func ok(body: String): UhpResponse {
    return UhpResponse(UInt16(200), headers(), body)
}

func okNoVersion(body: String): UhpResponse {
    let h = HashMap<String, String>()
    h["content-type"] = "application/json"
    return UhpResponse(UInt16(200), h, body)
}

func err(status: Int64, body: String): UhpResponse {
    return UhpResponse(UInt16(status), headers(), body)
}

func discoveryBody(versions: String): String {
    return "{\"object\":\"uhp.discovery\",\"protocol\":\"uhp\",\"versions\":" + versions +
        ",\"default_version\":\"2026-10-19\",\"conformance_class\":\"core\"," +
        "\"capabilities\":{\"streaming\":true}}"
}

func newClient(t: HttpTransport): UhpClient {
    return UhpClient("https://example.invalid", "tok", t)
}

// ---------- 用例 ----------

@Test
func discovery_negotiates_highest_common_version(): Unit {
    let t = FakeTransport([ok(discoveryBody("[\"2026-09-28\",\"2026-10-19\"]")), ok("{\"harnesses\":[]}")], [])
    let c = newClient(t)
    let d = c.discover()
    @Expect(d.protocol, "uhp")
    @Expect(c.protocolVersion(), "2026-10-19")
    // 后续请求必须带协商后的版本头
    let hs = c.harnesses()
    @Expect(hs.size, 0)
    @Expect(t.requests[1].headers.get("UHP-Version") ?? "", "2026-10-19")
    @Expect(t.requests[1].headers.get("Authorization") ?? "", "Bearer tok")
    // discovery 请求免鉴权
    @Expect(t.requests[0].headers.get("Authorization").isNone(), true)
}

@Test
func discovery_without_common_version_fails_explicitly(): Unit {
    let t = FakeTransport([ok(discoveryBody("[\"2026-01-01\"]"))], [])
    let c = newClient(t)
    var code = ""
    try {
        c.discover()
    } catch (e: UhpError) {
        code = e.code()
    }
    @Expect(code, "unsupported_protocol_version")
}

@Test
func error_envelope_is_mapped_with_retry_classification(): Unit {
    // 404 harness_not_found：不可重试
    let t404 = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]")),
        err(404, "{\"error\":{\"type\":\"invalid_request_error\",\"code\":\"harness_not_found\",\"message\":\"no such harness\",\"param\":\"metadata.harness_id\",\"detail\":null}}")], [])
    let c = newClient(t404)
    c.discover()
    var gotCode = ""
    var gotStatus: UInt16 = 0
    var gotRetry = true
    try {
        c.getResponse("resp_x")
    } catch (e: UhpError) {
        gotCode = e.code()
        gotStatus = e.httpStatus
        gotRetry = e.shouldRetry()
    }
    @Expect(gotCode, "harness_not_found")
    @Expect(gotStatus, UInt16(404))
    @Expect(gotRetry, false)

    // 503 harness_unavailable：可重试
    let t503 = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]")),
        err(503, "{\"error\":{\"type\":\"server_error\",\"code\":\"harness_unavailable\",\"message\":\"busy\",\"param\":null,\"detail\":null}}")], [])
    let c2 = newClient(t503)
    c2.discover()
    var retry2 = false
    try {
        c2.getResponse("resp_x")
    } catch (e: UhpError) {
        retry2 = e.shouldRetry()
    }
    @Expect(retry2, true)
}

@Test
func failed_task_is_a_value_not_an_exception(): Unit {
    let failedBody = "{\"id\":\"resp_1\",\"object\":\"response\",\"created_at\":1,\"status\":\"failed\"," +
        "\"error\":{\"type\":\"harness_error\",\"code\":\"harness_error\",\"message\":\"boom\",\"param\":null,\"detail\":null}," +
        "\"incomplete_details\":null,\"output\":[],\"model\":\"m\",\"usage\":null,\"metadata\":{\"session_id\":\"hsess1\"}," +
        "\"previous_response_id\":null,\"store\":true}"
    let t = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]")), ok(failedBody)], [])
    let c = newClient(t)
    c.discover()
    let r = c.createTask(CreateResponseRequest())
    @Expect(r.status, "failed")
    @Expect(r.id, "resp_1")
}

@Test
func create_task_sends_idempotency_key(): Unit {
    let taskBody = "{\"id\":\"resp_1\",\"object\":\"response\",\"created_at\":1,\"status\":\"completed\"," +
        "\"error\":null,\"incomplete_details\":null,\"output\":[],\"model\":\"m\",\"usage\":null," +
        "\"metadata\":{\"session_id\":\"hsess1\"},\"previous_response_id\":null,\"store\":true}"
    let t = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]")), ok(taskBody), ok(taskBody)], [])
    let c = newClient(t)
    c.discover()
    c.createTask(CreateResponseRequest())
    let autoKey = t.requests[1].headers.get("Idempotency-Key") ?? ""
    @Expect(autoKey.size > 0, true)
    // 调用方给出的键必须原样使用（跨重试复用是同一条键）
    c.createTask(CreateResponseRequest(), idempotencyKey: Some("fixed-key"))
    @Expect(t.requests[2].headers.get("Idempotency-Key") ?? "", "fixed-key")
}

@Test
func missing_version_header_is_a_protocol_violation(): Unit {
    let t = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]")), okNoVersion("{\"harnesses\":[]}")], [])
    let c = newClient(t)
    c.discover()
    var violated = false
    try {
        c.harnesses()
    } catch (e: ProtocolViolation) {
        violated = true
    }
    @Expect(violated, true)
}

// ---------- 流 ----------

func sseOf(payload: String): String {
    return "data: " + payload + "\n\n"
}

@Test
func stream_detects_sequence_gap(): Unit {
    let chunks = [
        sseOf("{\"type\":\"response.created\",\"sequence_number\":0}"),
        sseOf("{\"type\":\"response.in_progress\",\"sequence_number\":1}"),
        sseOf("{\"type\":\"response.completed\",\"sequence_number\":3}")
    ]
    let t = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]"))], [chunks])
    let c = newClient(t)
    let s = c.createTaskStream(CreateResponseRequest())
    var gap = -1
    try {
        while (let Some(_) <- s.next()) {}
    } catch (e: StreamGap) {
        gap = 1  // 期望 2、实际 3
    }
    @Expect(gap, 1)
}

@Test
func stream_tolerates_unknown_events_and_stops_at_terminal(): Unit {
    let chunks = [
        sseOf("{\"type\":\"response.made.up\",\"sequence_number\":0}"),
        sseOf("{\"type\":\"response.completed\",\"sequence_number\":1}")
    ]
    let t = FakeTransport([ok(discoveryBody("[\"2026-10-19\"]"))], [chunks])
    let c = newClient(t)
    let s = c.createTaskStream(CreateResponseRequest())
    var count = 0
    var unknownSeen = false
    while (let Some(ev) <- s.next()) {
        count = count + 1
        match (ev) {
            case Unknown(_) => unknownSeen = true
            case _ => ()
        }
    }
    @Expect(count, 2)
    @Expect(unknownSeen, true)
    @Expect(s.hasTerminal(), true)
}
