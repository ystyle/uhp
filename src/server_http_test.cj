// 端到端：真实 UHP 服务端（本机回环）+ 真实客户端。
//
// 这是 M2 的验收面：代理请求 -> 鉴权 -> 版本 -> 路由 -> 引擎 -> 事件 -> SSE/JSON。
package uhp

import std.collection.{ArrayList, HashMap}
import stdx.net.http.*
import std.unittest.*
import std.unittest.testmacro.*
import uhp.server.*
import uhp.client.*
import uhp.transport.*
import uhp.types.generated.*
import uhp.types.handwritten.*

class TestUhpServer {
    public let port: UInt16
    private let server: Server

    public init() {
        let driver = ScriptedHarness(
            [ScriptStep.Text("hello "), ScriptStep.Text("world")],
            TurnOutcome.Completed(None)
        )
        let harness = ConfiguredHarness("chrn_1", "Scripted", "scripted", "scripted-model", driver)
        let engine = Engine([harness])
        let tokens = HashMap<String, String>()
        tokens["tok-1"] = "alice"
        let uhp = UhpHttpServer(engine, Authenticator(tokens))
        let server = ServerBuilder()
            .addr("127.0.0.1")
            .port(0)
            .distributor(uhp.distributor())
            .build()
        this.server = server
        spawn {
            try {
                server.serve()
            } catch (_: Exception) {
                ()
            }
        }
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

func clientOf(srv: TestUhpServer, token!: String = "tok-1"): UhpClient {
    return UhpClient(srv.url(), token, StdHttpTransport(srv.url()))
}

// ---------- 用例 ----------

@Test
func http_discovery_and_harness_listing(): Unit {
    let srv = TestUhpServer()
    try {
        let c = clientOf(srv)
        let d = c.discover()
        @Expect(d.protocol, "uhp")
        @Expect(d.conformance_class, "core")
        let hs = c.harnesses()
        @Expect(hs.size, 1)
        @Expect(hs[0].id, "chrn_1")
        let models = c.harnessModels("chrn_1")
        @Expect(models.default ?? "", "scripted-model")
    } finally {
        srv.close()
    }
}

@Test
func http_create_task_returns_completed_response(): Unit {
    let srv = TestUhpServer()
    try {
        let c = clientOf(srv)
        let r = c.createTaskWithInput("hi")
        @Expect(r.status, "completed")
        @Expect(r.output.size, 1)
        @Expect(r.output[0].typeName, "message")
        @Expect((r.metadata ?? ResponseMetadata()).session_id.isSome(), true)
    } finally {
        srv.close()
    }
}

@Test
func http_stream_delivers_ordered_events(): Unit {
    let srv = TestUhpServer()
    try {
        let c = clientOf(srv)
        let s = c.createTaskStreamWithInput("hi")
        var seqs: ArrayList<Int64> = ArrayList<Int64>()
        var firstType = ""
        var lastType = ""
        while (let Some(ev) <- s.next()) {
            if (seqs.size == 0) {
                firstType = typeName(ev)
            }
            lastType = typeName(ev)
            match (sequenceNumberOf(ev)) {
                case Some(n) => seqs.add(n)
                case None => ()
            }
        }
        @Expect(firstType, "response.created")
        @Expect(lastType, "response.completed")
        // 序号 0 起连续
        var expected: Int64 = 0
        for (n in seqs) {
            @Expect(n, expected)
            expected = expected + 1
        }
        @Expect(seqs.size >= 3, true)
    } finally {
        srv.close()
    }
}

@Test
func http_session_continuation_keeps_same_session(): Unit {
    let srv = TestUhpServer()
    try {
        let c = clientOf(srv)
        let first = c.createTaskWithInput("hi")
        let sid1 = (first.metadata ?? ResponseMetadata()).session_id ?? ""
        // 用原始请求体表达 previous_response_id：这里借助 client 的低层接口
        let h = HashMap<String, String>()
        h["Authorization"] = "Bearer tok-1"
        h["Content-Type"] = "application/json"
        h["UHP-Version"] = c.protocolVersion()
        let body = "{\"input\":\"again\",\"previous_response_id\":\"" + first.id + "\"}"
        let t = StdHttpTransport(srv.url())
        let resp = t.send(UhpRequest("POST", "/v1/responses", h, Some(body)))
        @Expect(resp.status, UInt16(200))
        let second = parseJson<Response>(resp.body)
        let sid2 = (second.metadata ?? ResponseMetadata()).session_id ?? ""
        @Expect(sid2, sid1)
    } finally {
        srv.close()
    }
}

@Test
func http_unauthorized_without_token(): Unit {
    let srv = TestUhpServer()
    try {
        let t = StdHttpTransport(srv.url())
        let resp = t.send(UhpRequest("GET", "/v1/harnesses", HashMap<String, String>(), None))
        @Expect(resp.status, UInt16(401))
        @Expect(resp.body.contains("missing_credential"), true)
        // 错误响应也必须带版本头
        @Expect(resp.header("UHP-Version").isSome(), true)
    } finally {
        srv.close()
    }
}

@Test
func http_unsupported_version_is_400_with_supported_list(): Unit {
    let srv = TestUhpServer()
    try {
        let h = HashMap<String, String>()
        h["Authorization"] = "Bearer tok-1"
        h["UHP-Version"] = "1999-01-01"
        let t = StdHttpTransport(srv.url())
        let resp = t.send(UhpRequest("GET", "/v1/harnesses", h, None))
        @Expect(resp.status, UInt16(400))
        @Expect(resp.body.contains("unsupported_protocol_version"), true)
        @Expect(resp.body.contains("2026-10-19"), true)
    } finally {
        srv.close()
    }
}

@Test
func http_delete_then_get_is_404(): Unit {
    let srv = TestUhpServer()
    try {
        let c = clientOf(srv)
        let r = c.createTaskWithInput("hi")
        let d = c.deleteResponse(r.id)
        @Expect(d.deleted, true)
        var code = ""
        try {
            c.getResponse(r.id)
        } catch (e: UhpError) {
            code = e.code()
        }
        @Expect(code, "response_not_found")
    } finally {
        srv.close()
    }
}

@Test
func http_unknown_path_is_404_error_envelope(): Unit {
    let srv = TestUhpServer()
    try {
        let h = HashMap<String, String>()
        h["Authorization"] = "Bearer tok-1"
        h["UHP-Version"] = "2026-10-19"
        let t = StdHttpTransport(srv.url())
        let resp = t.send(UhpRequest("GET", "/v1/nope", h, None))
        @Expect(resp.status, UInt16(404))
        @Expect(resp.body.contains("\"error\""), true)
    } finally {
        srv.close()
    }
}
