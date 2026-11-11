// 客户端新增能力的端到端：会话列举/详情/历史/产物、产物字节下载、回答问题（input_response）。
//
// 放根包的原因同 std_http_test：子包测试二进制链接 stdx 有问题，依赖网络/起服务的测试集中在根包。
package uhp

import std.collection.{ArrayList, HashMap}
import stdx.net.http.*
import std.unittest.*
import std.unittest.testmacro.*
import uhp.client.*
import uhp.server.*
import uhp.transport.*
import uhp.types.base.*
import uhp.types.generated.*

// 产出文件并可能反问的 driver：一个类覆盖两条链路，避免测试里堆小类。
class SessionDriver <: HarnessDriver {
    private let asks: Bool

    public init(asks: Bool) {
        this.asks = asks
    }

    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "session-driver"
    }

    public func models(): Array<Model> {
        return []
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, true)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        if (ctx.answers.size > 0) {
            sink.textDelta("answered: " + ctx.answers[0])
            return TurnOutcome.Completed(None)
        }
        if (this.asks) {
            let _ = sink.ask("choice", "Which colour?", [("red", "Red"), ("blue", "Blue")])
            return TurnOutcome.Completed(None)
        }
        sink.textDelta("done")
        // 产物：二进制内容，专门验证「按字节下载」不经过 UTF-8 解码
        sink.producedFile("artifact.bin", [0, 255, 1, 254, 2])
        return TurnOutcome.Completed(None)
    }
}

class ClientServer {
    public let port: UInt16
    public let client: UhpClient
    private let server: Server

    public init(driver: HarnessDriver) {
        let engine = Engine([ConfiguredHarness("s", "s", "scripted", "auto", driver)])
        let tokens = HashMap<String, String>()
        tokens["t"] = "alice"
        let uhpServer = UhpHttpServer(engine, Authenticator(tokens))
        this.server = ServerBuilder().addr("127.0.0.1").port(0).distributor(uhpServer.distributor()).build()
        let s = this.server
        spawn {
            s.serve()
        }
        var bound: UInt16 = 0
        for (_ in 0..500) {
            bound = this.server.port
            if (bound != 0) {
                break
            }
            sleep(Duration.millisecond * 10)
        }
        this.port = bound
        let url = "http://127.0.0.1:" + bound.toString()
        this.client = UhpClient(url, "t", StdHttpTransport(url))
        var ready = false
        for (_ in 0..200) {
            try {
                let _ = this.client.discover()
                ready = true
                break
            } catch (e: Exception) {
                sleep(Duration.millisecond * 20)
            }
        }
        if (!ready) {
            throw Exception("测试 server 未就绪")
        }
    }

    public func close(): Unit {
        this.server.close()
    }
}

func sessionIdOf(r: Response): String {
    return match (r.metadata) {
        case Some(m) => m.session_id ?? ""
        case None => ""
    }
}

func inputRequestIdOf(r: Response): String {
    for (item in r.output) {
        if (item.typeName == "input_request") {
            return item.id ?? ""
        }
    }
    return ""
}

@Test
func client_session_list_and_detail(): Unit {
    let cs = ClientServer(SessionDriver(false))
    try {
        let created = cs.client.createTaskWithInput("hello", harnessId: Some("s"))
        let sid = sessionIdOf(created)
        @Expect(sid.size > 0, true)

        let page = cs.client.sessions()
        @Expect(page.sessions.size, 1)
        @Expect(page.sessions[0].id, sid)

        let one = cs.client.getSession(sid)
        @Expect(one.id, sid)
        @Expect(one.harness_id ?? "", "s")

        let turns = cs.client.sessionTurns(sid)
        @Expect(turns.size, 1)
        @Expect(turns[0].status, "completed")
    } finally {
        cs.close()
    }
}

@Test
func client_lists_and_downloads_artifact_bytes(): Unit {
    let cs = ClientServer(SessionDriver(false))
    try {
        let created = cs.client.createTaskWithInput("make a file", harnessId: Some("s"))
        let sid = sessionIdOf(created)
        @Expect(created.status, "completed")

        let files = cs.client.sessionFiles(sid)
        @Expect(files.size, 1)
        @Expect(files[0].filename, "artifact.bin")
        let containerId = files[0].container_id ?? ""
        @Expect(containerId.size > 0, true)

        // 字节必须原样回来：0x00/0xFF 这类值一旦当文本读就会坏
        let bytes = cs.client.downloadFile(containerId, files[0].id)
        @Expect(bytes.size, 5)
        @Expect(bytes[0], 0)
        @Expect(bytes[1], 255)
        @Expect(bytes[2], 1)
        @Expect(bytes[3], 254)
        @Expect(bytes[4], 2)
    } finally {
        cs.close()
    }
}

@Test
func client_answers_input_request(): Unit {
    let cs = ClientServer(SessionDriver(true))
    try {
        let first = cs.client.createTaskWithInput("ask me", harnessId: Some("s"))
        @Expect(first.status, "incomplete")
        let requestId = inputRequestIdOf(first)
        @Expect(requestId.startsWith("inreq_"), true)

        // 第二轮：把答案链在上一轮响应上，driver 收到 answers 后走完成分支
        let second = cs.client.answerInput(first.id, requestId, "red")
        @Expect(second.status, "completed")
        var text = ""
        for (item in second.output) {
            if (let Some(content) <- item.content) {
                for (part in content) {
                    if (let Some(t) <- part.text) {
                        text = text + t
                    }
                }
            }
        }
        @Expect(text, "answered: red")
        // 同一个会话：回答问题不会开新会话
        @Expect(sessionIdOf(second), sessionIdOf(first))
    } finally {
        cs.close()
    }
}
