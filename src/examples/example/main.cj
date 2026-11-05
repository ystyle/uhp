// 示例：起一个 UHP 服务端，用 opencode 2.x 当执行引擎。
//
// 用法：
//   uhp_opencode.example <port> <opencodeBaseUrl> <workspaceDir> [modelID providerID]
// 例：
//   ./target/release/bin/uhp_opencode.example 8471 http://127.0.0.1:4765 /tmp/ws deepseek-flash deepseek
//
// 认证：UHP 侧固定 Bearer dev-token；opencode 侧用 OPENCODE_SERVER_PASSWORD（默认 splice-token）。
package uhp_opencode.examples.example

import std.collection.HashMap
import std.convert.*
import std.env.*
import stdx.net.http.*
import uhp.server.*
import uhp_opencode.*

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
    let ocBase = if (args.size >= 3) { args[2] } else { "http://127.0.0.1:4765" }
    let workDir = if (args.size >= 4) { args[3] } else { "/tmp" }
    let model: Option<(String, String)> = if (args.size >= 6) {
        Some((args[4], args[5]))
    } else {
        None
    }
    let opts = OpencodeOptions(ocBase, workDir, password: "splice-token", model: model)
    let driver = OpencodeDriver(opts)
    let modelId = match (model) {
        case Some((mid, _)) => mid
        case None => "opencode-default"
    }
    let harness = ConfiguredHarness("chrn_opencode", "opencode 2.x", "opencode", modelId, driver)
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
