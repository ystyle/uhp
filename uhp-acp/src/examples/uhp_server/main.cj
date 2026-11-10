// 示例：起一个 UHP 服务端，用 ACP driver 驱动任意 ACP agent 子进程。
//
// 用法：
//   uhp_acp.examples.uhp_server <port> <cwd> <agentCommand> [agentArgs...]
// 例：
//   ./target/release/bin/uhp_acp.examples.uhp_server 8471 /tmp "opencode" acp
//
// 环境变量 UHP_ACP_SESSION_MODE=parallel 打开「一个连接多会话并发」；
// 默认 serial（任何 ACP agent 都能用），并发只对确认支持的 agent 开。
package uhp_acp.examples.uhp_server

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.env.{getCommandLine, getVariable}
import stdx.net.http.*
import uhp.server.*
import uhp_acp.*

main(): Int64 {
    let args = getCommandLine()
    let port = if (args.size >= 2) {
        match (UInt16.tryParse(args[1])) {
            case Some(v) => v
            case None => UInt16(8471)
        }
    } else {
        UInt16(8471)
    }
    let cwd = if (args.size >= 3) { args[2] } else { "/tmp" }
    let command = if (args.size >= 4) { args[3] } else { "opencode" }
    let agentArgs = ArrayList<String>()
    var i = 4
    while (i < args.size) {
        agentArgs.add(args[i])
        i = i + 1
    }
    let mode = match (getVariable("UHP_ACP_SESSION_MODE")) {
        case Some(v) => if (v == "parallel") { AcpSessionMode.Parallel } else { AcpSessionMode.Serial }
        case None => AcpSessionMode.Serial
    }
    let opts = AcpOptions(command, args: agentArgs.toArray(), cwd: cwd, label: "ACP agent",
        sessionMode: mode)
    let driver = AcpDriver(opts)
    let harness = ConfiguredHarness("chrn_acp", "ACP agent", "acp", "acp-agent", driver)
    let engine = Engine([harness])
    let tokens = HashMap<String, String>()
    tokens["dev-token"] = "dev"
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
