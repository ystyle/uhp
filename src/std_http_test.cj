// 真实 HTTP 传输的端到端测试（本机回环，port(0) 由系统分配）。
//
// 为什么放在**根包**：cjpm 1.2.0 下子包的测试二进制链接 stdx 会失败（见 cjpm.toml 注释），
// 根包正常。依赖网络的测试集中放这里，子包测试保持纯离线。
package uhp

import std.collection.HashMap
import std.sync.{AtomicBool, AtomicInt64}
import stdx.net.http.*
import std.unittest.*
import std.unittest.testmacro.*
import uhp.transport.*
import uhp.client.*
import uhp.types.handwritten.*

// ---------- 回环测试服务器 ----------

class Loopback {
    public let port: UInt16
    private let server: Server

    public init(discovery: String, taskJson: String, sse: String) {
        let server = ServerBuilder().addr("127.0.0.1").port(0).build()
        server.distributor.register("/v1/uhp", {
            ctx: HttpContext =>
            ctx.responseBuilder
                .status(200)
                .header("content-type", "application/json")
                .header("UHP-Version", "2026-10-19")
                .body(discovery)
        })
        server.distributor.register("/v1/responses", {
            ctx: HttpContext =>
            let accept = match (ctx.request.headers.getFirst("accept")) {
                case Some(v) => v
                case None => ""
            }
            if (accept.contains("text/event-stream")) {
                ctx.responseBuilder
                    .status(200)
                    .header("content-type", "text/event-stream")
                    .header("UHP-Version", "2026-10-19")
                    .body(sse)
            } else {
                ctx.responseBuilder
                    .status(200)
                    .header("content-type", "application/json")
                    .header("UHP-Version", "2026-10-19")
                    .body(taskJson)
            }
        })
        this.server = server
        spawn {
            try {
                server.serve()
            } catch (_: Exception) {
                ()
            }
        }
        // 就绪等待：port=0 时 serve 会先 bind 再回填 port
        var waited = 0
        while (server.port == 0 && waited < 500) {
            sleep(Duration.millisecond * 10)
            waited = waited + 1
        }
        this.port = server.port
    }

    public func url(): String {
        return "http://127.0.0.1:" + this.port.toString()
    }

    public func close(): Unit {
        this.server.close()
    }
}

// ---------- 夹具 ----------

let DiscoveryJson: String = "{\"object\":\"uhp.discovery\",\"protocol\":\"uhp\"," +
    "\"versions\":[\"2026-10-19\"],\"default_version\":\"2026-10-19\"," +
    "\"conformance_class\":\"core\",\"capabilities\":{\"streaming\":true}}"

let TaskJson: String = "{\"id\":\"resp_1\",\"object\":\"response\",\"created_at\":1," +
    "\"status\":\"completed\",\"error\":null,\"incomplete_details\":null,\"output\":[]," +
    "\"model\":\"m\",\"usage\":null,\"metadata\":{\"session_id\":\"hsess1\"}," +
    "\"previous_response_id\":null,\"store\":true}"

let SseBody: String = "data: {\"type\":\"response.created\",\"sequence_number\":0}\n\n" +
    "data: {\"type\":\"response.completed\",\"sequence_number\":1}\n\n"

// ---------- 用例 ----------

@Test
func transport_send_roundtrip(): Unit {
    let srv = Loopback(DiscoveryJson, TaskJson, SseBody)
    try {
        let t = StdHttpTransport(srv.url())
        let resp = t.send(UhpRequest("GET", "/v1/uhp", HashMap<String, String>(), None))
        @Expect(resp.status, UInt16(200))
        @Expect(resp.header("uhp-version") ?? "", "2026-10-19")
        @Expect(resp.body.contains("uhp.discovery"), true)
    } finally {
        srv.close()
    }
}

@Test
func transport_stream_reads_all_chunks(): Unit {
    let srv = Loopback(DiscoveryJson, TaskJson, SseBody)
    try {
        let t = StdHttpTransport(srv.url())
        let h = HashMap<String, String>()
        h["Accept"] = "text/event-stream"
        let start = t.stream(UhpRequest("POST", "/v1/responses", h, Some("{}")))
        match (start) {
            case Failed(resp) =>
                @Fail("不应走到错误分支：HTTP " + resp.status.toString())
            case Started(stream) =>
                let p = SseParser()
                var events: Int64 = 0
                var done = false
                while (!done) {
                    match (stream.nextChunk()) {
                        case Some(chunk) => events = events + p.feed(chunk).size
                        case None =>
                            events = events + p.finish().size
                            done = true
                    }
                }
                stream.close()
                @Expect(events, 2)
        }
    } finally {
        srv.close()
    }
}

@Test
func client_over_real_http_end_to_end(): Unit {
    let srv = Loopback(DiscoveryJson, TaskJson, SseBody)
    try {
        let c = UhpClient(srv.url(), "tok", StdHttpTransport(srv.url()))
        let d = c.discover()
        @Expect(d.protocol, "uhp")
        // 非流式任务
        let r = c.createTask(CreateResponseRequest())
        @Expect(r.status, "completed")
        // 流式任务：拿到 2 个事件、末态是 completed
        let s = c.createTaskStream(CreateResponseRequest())
        var count = 0
        var terminal = false
        while (let Some(ev) <- s.next()) {
            count = count + 1
            if (isTerminal(ev)) {
                terminal = true
            }
        }
        @Expect(count, 2)
        @Expect(terminal, true)
    } finally {
        srv.close()
    }
}
