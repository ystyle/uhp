// 一致性套件的被测服务端（SUT）。
//
// 用法：conformance_sut [port]     默认 8471
// 认证：Authorization: Bearer dev-token
//
// 用确定性的 driver 而不是真实模型：套件检查的是协议行为，不是模型能力，CI 因此不需要付费模型。
// 它会识别「Create a file named X containing exactly: Y」这类输入并真的产出文件，
// 好让 Extended 类的产物检查（X-06/07/08）测到东西而不是全程 skip。
package uhp.examples.conformance_sut

import std.collection.HashMap
import std.convert.*
import std.env.*
import stdx.net.http.*
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
    let engine = Engine([harness], cls: ConformanceClass.Extended)
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
