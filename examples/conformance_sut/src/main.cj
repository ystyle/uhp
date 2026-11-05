// 一致性套件的被测服务端（SUT）。
//
// 用法：conformance_sut [port]     默认 8471
// 认证：Authorization: Bearer dev-token
//
// 用确定性的 driver 而不是真实模型：套件检查的是协议行为，不是模型能力，CI 因此不需要付费模型。
// 它会识别「Create a file named X containing exactly: Y」这类输入并真的产出文件，
// 好让 Extended 类的产物检查（X-06/07/08）测到东西而不是全程 skip。
package uhp_conformance_sut

import std.collection.HashMap
import std.convert.*
import std.env.*
import stdx.net.http.*
import std.fs.{File as FsFile}
import std.io.*
import stdx.encoding.json.stream.*
import uhp.server.*
import uhp.types.base.*
import uhp.types.generated.*

class SutHarness <: HarnessDriver {
    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "UHP conformance SUT"
    }

    public func models(): Array<Model> {
        let m = Model()
        m.id = "scripted-model"
        m.available = true
        return [m]
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        // 续跑（回答问题）：把答案回话。secret 永远不回显。
        if (ctx.answers.size > 0) {
            let answer = ctx.answers[0]
            if (answer.startsWith("uhp-secret-")) {
                sink.textDelta("RECEIVED")
            } else {
                sink.textDelta("ANSWERED " + answer)
            }
            return TurnOutcome.Completed(None)
        }
        // 提问场景：prompt 里点名了 ask_user 与 kind
        if (ctx.input.contains("ask_user")) {
            if (ctx.input.contains("kind \"secret\"")) {
                let _ = sink.ask("secret", "The deploy token?", Array<(String, String)>())
                return TurnOutcome.Completed(None)
            }
            if (ctx.input.contains("kind \"choice\"")) {
                let _ = sink.ask("choice", "Which colour?",
                    [("red", "Red"), ("blue", "Blue")])
                return TurnOutcome.Completed(None)
            }
        }
        // 环境场景（EN-07）：在 mount 下读文件，并真的试一次写（应当失败——只读）
        if (let Some(mount) <- ctx.environmentMount) {
            if (ctx.input.contains("cat ")) {
                var content = ""
                try {
                    content = String.fromUtf8(FsFile.readFrom(mount + "/data/hello.txt"))
                } catch (e: Exception) {
                    content = "(unreadable)"
                }
                var writeNote = "write denied (read-only)"
                try {
                    let f = FsFile.create(mount + "/write-probe")
                    f.close()
                    writeNote = "write succeeded"
                } catch (e: Exception) {
                    writeNote = "write denied (read-only)"
                }
                sink.textDelta(content.trimAscii() + " WRITE: " + writeNote)
                return TurnOutcome.Completed(None)
            }
        }
        // step 预算场景：链式调 uhp_steps，每轮一次；到预算就结束本轮为 incomplete
        if (ctx.input.contains("uhp_steps")) {
            return runStepChain(ctx, sink)
        }
        // 插件场景：要求调用 MCP 工具并把返回值原样回话（P-11 的判据是 fixture 的答案）。
        // 这是 harness 侧行为：SDK 只把本轮可用的 MCP 服务器并集交给我们。
        if (ctx.input.contains("Call the tool ")) {
            match (callToolFromInput(ctx, sink)) {
                case Some(outcome) => return outcome
                case None => ()   // 连不上就退回普通回话，别让整个任务失败
            }
        }
        // 产物场景：Create a file named <name> containing exactly: <content>
        if (ctx.input.contains("Create a file named")) {
            let name = between(ctx.input, "Create a file named", "containing exactly:")
            var content = after(ctx.input, "containing exactly:")
            content = content.trimAscii()
            if (name.size > 0) {
                sink.producedFile(name.trimAscii(), content.toArray())
                sink.textDelta("Created " + name.trimAscii() + " with " + content.size.toString() + " bytes.")
                return TurnOutcome.Completed(None)
            }
        }
        // 普通场景：分段输出，步间 150ms —— 让 SSE 渐进可观测（S-09），
        // 也给 background 轮询留窗口（T-11）。
        let chunks = [
            "This is the UHP conformance SUT. ",
            "It echoes a deterministic reply so that protocol behaviour, ",
            "not model quality, ",
            "is what gets measured. ",
            "Streaming is live, not buffered."
        ]
        for (c in chunks) {
            if (cancel.isCancelled()) {
                return TurnOutcome.Cancelled(None)
            }
            sink.textDelta(c)
            sleep(Duration.millisecond * 150)
        }
        return TurnOutcome.Completed(None)
    }
}

// 链式工具调用：每轮严格「调用 + 结果」成一对（套件按配对计 step），到预算立刻停。
func runStepChain(ctx: TurnContext, sink: TurnSink): TurnOutcome {
    let nonce = match (markerValue(ctx.input, "set to ")) {
        case Some(v) => v
        case None => ""
    }
    if (nonce.size == 0) {
        return TurnOutcome.Completed(None)
    }
    var client: Option<McpClient> = None
    for (server in ctx.mcpServers) {
        match (httpUrlOf(server)) {
            case Some(u) => client = Some(McpClient(u))
            case None => ()
        }
        if (client.isSome()) {
            break
        }
    }
    let c = match (client) {
        case Some(v) => v
        case None => return TurnOutcome.Failed("harness_error", "no http MCP server")
    }
    let limit = match (ctx.maxStep) {
        case Some(n) => n
        case None => 100
    }
    var step: Int64 = 0
    while (true) {
        if (step >= limit) {
            // 到预算：本轮以 incomplete 结束（服务端会把 reason 落成 max_steps）
            return TurnOutcome.Incomplete(IncompleteReason.MaxSteps, None)
        }
        let argOut = ByteBuffer()
        let aw = JsonWriter(argOut)
        aw.startObject()
        aw.writeName("nonce").writeValue(nonce)
        aw.endObject()
        aw.flush()
        let args = String.fromUtf8(argOut.bytes())
        let callId = sink.toolCall("uhp_steps", args)
        let answer = match (c.callTool("uhp_steps", args)) {
            case Some(v) => v
            case None => "uhp_steps failed"
        }
        sink.toolResult(callId, answer)
        step = step + 1
        if (answer.contains("the chain is done")) {
            sink.textDelta("DONE")
            return TurnOutcome.Completed(None)
        }
    }
    return TurnOutcome.Completed(None)
}

// 从 prompt 里认出工具名与参数，连上第一个 http MCP server 调一次，把答案回话。
func callToolFromInput(ctx: TurnContext, sink: TurnSink): Option<TurnOutcome> {
    let toolName = between(ctx.input, "Call the tool ", " with")
    if (toolName.size == 0) {
        return None
    }
    // 参数：fixture 的 echo 工具收 text；从 prompt 的 "with the text <nonce>" 里取
    let nonce = match (markerValue(ctx.input, "with the text ")) {
        case Some(v) => v
        case None => ""
    }
    if (nonce.size == 0) {
        return None
    }
    eprintln("mcp: servers=" + ctx.mcpServers.size.toString() + " tool=" + toolName + " nonce=" + nonce)
    for (server in ctx.mcpServers) {
        let url = httpUrlOf(server)
        match (url) {
            case Some(u) =>
                let client = McpClient(u)
                let argOut = ByteBuffer()
                let aw = JsonWriter(argOut)
                aw.startObject()
                aw.writeName("text").writeValue(nonce)
                aw.endObject()
                aw.flush()
                let args = String.fromUtf8(argOut.bytes())
                match (client.callTool(toolName.trimAscii(), args)) {
                    case Some(answer) =>
                        sink.textDelta(answer)
                        return Some(TurnOutcome.Completed(None))
                    case None => eprintln("mcp: call failed")
                }
            case None => ()
        }
    }
    return None
}

// 从 JSON 服务器条目里取 http(s) url（stdio 不走网络）
func httpUrlOf(serverJson: String): Option<String> {
    match (tryParseJsonObject(serverJson)) {
        case Some(o) =>
            let transport = o.str("transport") ?? ""
            if (transport == "http" || transport == "sse") {
                return o.str("url")
            }
            return None
        case None => return None
    }
}

// 取某个标记之后的第一个词
func markerValue(s: String, marker: String): Option<String> {
    let i = match (s.indexOf(marker)) {
        case Some(v) => v + marker.size
        case None => return None
    }
    let rest = s[i..s.size].trimAscii()
    let arr = rest.toRuneArray()
    var end = arr.size
    for (k in 0..arr.size) {
        if (arr[k] == r' ' || arr[k] == r',' || arr[k] == r'.') {
            end = k
            break
        }
    }
    if (end == 0) {
        return None
    }
    return Some(String(arr[0..end]))
}

func between(s: String, start: String, end: String): String {
    let i = match (s.indexOf(start)) {
        case Some(v) => v + start.size
        case None => return ""
    }
    let rest = s[i..s.size]
    let j = match (rest.indexOf(end)) {
        case Some(v) => v
        case None => return rest.trimAscii()
    }
    return rest[0..j]
}

func after(s: String, marker: String): String {
    let i = match (s.indexOf(marker)) {
        case Some(v) => v + marker.size
        case None => return ""
    }
    return s[i..s.size]
}

main(): Int64 {
    let port = parsePort(getCommandLine())
    let harness = ConfiguredHarness("chrn_sut", "SUT harness", "scripted", "scripted-model", SutHarness())
    // Extended 类：files_input / files_output / session_listing 由引擎按类自动打开
    // Full 类：再打开 harness_management（本服务端支持一个 base：scripted）
    let engine = Engine([harness], cls: ConformanceClass.Full,
        packageChecker: Some({ manager: String, spec: String => localRegistryLookup(manager, spec) }),
        driverFactory: Some({ b: String => SutHarness() }),
        supportedBases: Some(["scripted"]))
    let tokens = HashMap<String, String>()
    tokens["dev-token"] = "conformance"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(port)
        .distributor(uhp.distributor())
        .build()
    // MCP fixture 跑在 port+1：套件用 --plugin-mcp-url 指向它（本地即可，CI 不依赖公网）
    let mcpPort = startMcpFixture(port + 1)
    println("MCP-LISTENING " + mcpPort.toString())
    println("LISTENING " + server.port.toString())
    server.serve()
    return 0
}

// 一致性 SUT 的本地 registry：只回答 pip 生态，pip 已知、其它名字如实说不存在。
// 这是宿主侧实现（真实部署里换成 PyPI/私有源），SDK 只负责把结果原样转述。
func localRegistryLookup(manager: String, spec: String): Option<PackageCheckResult> {
    if (manager != "pip") {
        return None
    }
    if (spec == "pip") {
        return Some(PackageCheckResult(true, Some("26.0.0")))
    }
    return Some(PackageCheckResult(false, None))
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
