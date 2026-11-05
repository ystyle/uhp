// 最小 MCP 客户端（streamable HTTP），只用于一致性 SUT 证明「插件里的 MCP server 真的能被 agent 调到」。
//
// 这是 **harness 侧** 的行为（UHP 不执行 MCP）：SDK 只负责把本轮可用的服务器并集通过 TurnContext 交给 driver，
// driver 自己去连。这里的实现够 P-11 用：initialize -> notifications/initialized -> tools/call。
package uhp.examples.conformance_sut

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.{JsonReader, JsonWriter, JsonToken}
import uhp.transport.*
import uhp.server.*

public class McpClient {
    private let url: String
    private var sessionId: Option<String> = None
    private var nextId: Int64 = 1

    public init(url: String) {
        this.url = url
    }

    // 调一个工具，返回结果里的第一段文本。失败返回 None（调用方决定降级）。
    public func callTool(name: String, argumentsJson: String): Option<String> {
        if (!this.initialize()) {
            return None
        }
        let payload = "{\"jsonrpc\":\"2.0\",\"id\":" + this.nextId.toString() +
            ",\"method\":\"tools/call\",\"params\":{\"name\":\"" + name +
            "\",\"arguments\":" + argumentsJson + "}}"
        this.nextId = this.nextId + 1
        match (this.post(payload)) {
            case Some(body) => return firstContentText(body)
            case None => return None
        }
    }

    private func initialize(): Bool {
        let payload = "{\"jsonrpc\":\"2.0\",\"id\":" + this.nextId.toString() +
            ",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"," +
            "\"capabilities\":{},\"clientInfo\":{\"name\":\"uhp-cj-sut\",\"version\":\"0.1.0\"}}}"
        this.nextId = this.nextId + 1
        match (this.post(payload)) {
            case Some(body) =>
                if (!body.contains("result")) {
                    return false
                }
            case None => return false
        }
        // 通知：JSON-RPC notification，没有 id，服务端通常回 202 + 空体
        let note = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
        this.post(note)
        return true
    }

    private func post(payload: String): Option<String> {
        let headers = HashMap<String, String>()
        headers["content-type"] = "application/json"
        headers["accept"] = "application/json, text/event-stream"
        match (this.sessionId) {
            case Some(sid) => headers["mcp-session-id"] = sid
            case None => ()
        }
        try {
            let rsp = rawHttpPost(this.url, headers, payload)
            eprintln("mcp: post status=" + rsp.status.toString() + " body=" + rsp.body[0..min(160, rsp.body.size)])
            match (rsp.header("mcp-session-id")) {
                case Some(sid) => this.sessionId = Some(sid)
                case None => ()
            }
            if (rsp.status >= 400 && rsp.body.size == 0) {
                return None
            }
            return Some(rsp.body)
        } catch (e: Exception) {
            eprintln("mcp: post threw " + e.toString())
            return None
        }
    }
}

func min(a: Int64, b: Int64): Int64 {
    if (a < b) {
        return a
    }
    return b
}

func readAllText(body: InputStream): String {
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

// 从 JSON-RPC 响应（可能是 JSON，也可能是 SSE 帧）里取 result.content[0].text
func firstContentText(body: String): Option<String> {
    let messages = ArrayList<String>()
    if (body.contains("data:")) {
        for (line in body.split("\n")) {
            let l = line.trimAscii()
            if (l.startsWith("data:")) {
                messages.add(l["data:".size..l.size].trimAscii())
            }
        }
    } else {
        messages.add(body.trimAscii())
    }
    for (msg in messages) {
        match (tryParseJsonObject(msg)) {
            case Some(o) => match (o.raw("result")) {
                case Some(resultRaw) =>
                    match (tryParseJsonObject(resultRaw)) {
                        case Some(result) => match (result.raw("content")) {
                            case Some(contentRaw) =>
                                let texts = jsonStrings(contentRaw, "text")
                                if (texts.size > 0) {
                                    return Some(texts[0][0])
                                }
                            case None => ()
                        }
                        case None => ()
                    }
                case None => ()
            }
            case None => ()
        }
    }
    return None
}
