// 一致性套件的被测服务端（SUT）。
//
// 用法：conformance_sut [port]     默认 8471；启动后打印 LISTENING <port>，便于脚本等待就绪。
// 认证：Authorization: Bearer dev-token
//
// 这里用 ScriptedHarness：套件检查的是协议行为，不是模型能力。CI 因此不需要付费模型。
package uhp.examples.conformance_sut

import std.collection.HashMap
import std.convert.*
import std.env.*
import stdx.net.http.*
import uhp.server.*

main(): Int64 {
    let port = parsePort(getCommandLine())
    // 每步之间停 150ms：① 让 SSE 的「渐进而非末尾一把刷」可被观测（套件 S-09）；
    // ② 给 background 任务留出被轮询到 in_progress 的窗口（套件 T-11）。
    let driver = ScriptedHarness(
        [
            ScriptStep.Text("This is the UHP conformance SUT. "),
            ScriptStep.Text("It echoes a deterministic reply so that protocol behaviour, "),
            ScriptStep.Text("not model quality, "),
            ScriptStep.Text("is what gets measured. "),
            ScriptStep.Text("Streaming is live, not buffered.")
        ],
        TurnOutcome.Completed(None),
        delayMillis: 150
    )
    let harness = ConfiguredHarness("chrn_sut", "SUT harness", "scripted", "scripted-model", driver)
    let engine = Engine([harness])
    let tokens = HashMap<String, String>()
    tokens["dev-token"] = "conformance"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(port)
        .distributor(uhp.distributor())
        .build()
    println("LISTENING " + server.port.toString())
    server.serve()
    return 0
}

func parsePort(args: Array<String>): UInt16 {
    if (args.size >= 2) {
        match (UInt16.tryParse(args[1])) {
            case Some(p) => return p
            case None => ()
        }
    }
    return UInt16(8471)
}
