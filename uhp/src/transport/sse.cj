// SSE 客户端解析器（RFC 8895 / HTML Living Standard 的 event-stream 规则）。
//
// 为什么按**字节**解析：一个 UTF-8 字符可能被 TCP 分块切成两半；
// 按 String 累积再切行会在分块边界上产生替换字符。这里全部在 UInt8 层切行，
// 只有完整的一行才解码成 String。
//
// 与 UHP 相关的两条契约：
//   * 服务端 MAY 发注释行（": keep-alive"）当心跳 → 解析器要识别但不产事件（可通过 onComment 观察）；
//   * 事件数据行只有 data:（UHP 不用 event:/id:/retry:），但解析器按标准支持全部字段，
//     这样将来接 Last-Event-ID 重放不必改解析器。
package uhp.transport

import std.collection.{ArrayList, HashMap}
import std.convert.*

public class SseEvent {
    // SSE 的 id: 字段；UHP 不用，但保留以便支持 Last-Event-ID 重放
    public let id: Option<String>
    // event: 字段；UHP 不用（事件类型在 data 的 JSON 里）
    public let eventType: Option<String>
    // 多行 data: 以换行连接
    public let data: String
    public let retry: Option<Int64>

    public init(id: Option<String>, eventType: Option<String>, data: String, retry: Option<Int64>) {
        this.id = id
        this.eventType = eventType
        this.data = data
        this.retry = retry
    }
}

public class SseParser {
    private static let LF: UInt8 = UInt8(10)
    private static let CR: UInt8 = UInt8(13)
    private static let COLON: UInt8 = UInt8(58)
    private static let SPACE: UInt8 = UInt8(32)

    private var pending: Array<UInt8> = []
    private var dataLines: ArrayList<String> = ArrayList<String>()
    private var eventId: Option<String> = None
    private var eventType: Option<String> = None
    private var eventRetry: Option<Int64> = None
    private var lastEventIdValue: String = ""
    // 上一个 chunk 以 CR 结尾：若下一个 chunk 以 LF 开头，那 LF 属于同一个换行
    private var sawCR: Bool = false
    // 注释行（心跳）计数：测试与诊断用，不产生事件
    public var commentCount: Int64 = 0

    public init() {}

    // 最近一次 seen 的 id: 值（流内 id 不会改变；UHP 不用）
    public func lastEventId(): String {
        return this.lastEventIdValue
    }

    // 喂入一段字节，返回这段里**已经完整**的事件（可能 0 到多个）。
    public func feed(chunk: Array<UInt8>): Array<SseEvent> {
        let out = ArrayList<SseEvent>()
        // 上一块留下的半行必须先拼回来，否则分块边界上的字节会被丢掉
        // （尤其是一个 UTF-8 字符被切成两半时）。
        let buf: Array<UInt8>
        if (this.pending.size == 0) {
            buf = chunk
        } else {
            let merged = ArrayList<UInt8>()
            merged.add(all: this.pending)
            merged.add(all: chunk)
            buf = merged.toArray()
        }
        this.pending = []
        var i = 0
        if (this.sawCR) {
            this.sawCR = false
            if (buf.size > 0 && buf[0] == SseParser.LF) {
                i = 1  // 吃掉跨块 CRLF 的 LF
            }
        }
        var lineStart = i
        while (i < buf.size) {
            let b = buf[i]
            if (b == SseParser.LF || b == SseParser.CR) {
                this.consumeLine(buf[lineStart..i], out)
                if (b == SseParser.CR) {
                    if (i + 1 < buf.size && buf[i + 1] == SseParser.LF) {
                        i = i + 1
                    } else if (i + 1 == buf.size) {
                        this.sawCR = true
                    }
                }
                i = i + 1
                lineStart = i
            } else {
                i = i + 1
            }
        }
        if (lineStart < buf.size) {
            this.pending = buf[lineStart..buf.size]
        }
        return out.toArray()
    }

    // 流结束：处理「最后一帧没有空行结尾」的情况（规范允许）。
    public func finish(): Array<SseEvent> {
        let out = ArrayList<SseEvent>()
        if (this.pending.size > 0) {
            this.consumeLine(this.pending, out)
            this.pending = []
        }
        // 没有以空行收尾的残帧：按已累积内容分发
        this.dispatch(out)
        return out.toArray()
    }

    private func consumeLine(bytes: Array<UInt8>, out: ArrayList<SseEvent>): Unit {
        let line = String.fromUtf8(bytes)
        if (line.size == 0) {
            this.dispatch(out)
            return
        }
        if (bytes.size > 0 && bytes[0] == SseParser.COLON) {
            this.commentCount = this.commentCount + 1
            return
        }
        let field: String
        let value: String
        match (line.indexOf(":")) {
            case Some(idx) =>
                field = line[0..idx]
                let rest = line[idx + 1..line.size]
                value = if (rest.size > 0 && rest[0] == SseParser.SPACE) { rest[1..rest.size] } else { rest }
            case None =>
                field = line
                value = ""
        }
        match (field) {
            case "data" => this.dataLines.add(value)
            case "event" => this.eventType = Some(value)
            case "id" => if (!value.contains("\u{0}")) {
                    this.eventId = Some(value)
                    this.lastEventIdValue = value
                }
            case "retry" =>
                // retry 字段 UHP 不使用；解析失败按规范忽略，不抛
                match (Int64.tryParse(value)) {
                    case Some(n) => if (n >= 0) { this.eventRetry = Some(n) }
                    case None => ()
                }
            case _ => ()  // 未知字段按规范忽略
        }
    }

    private func dispatch(out: ArrayList<SseEvent>): Unit {
        if (this.dataLines.size == 0 && this.eventId.isNone() && this.eventType.isNone() && this.eventRetry.isNone()) {
            return  // 空行空帧（连续空行）不产事件
        }
        let joined = String.join(this.dataLines.toArray(), delimiter: "\n")
        out.add(SseEvent(this.eventId, this.eventType, joined, this.eventRetry))
        this.dataLines = ArrayList<String>()
        this.eventId = None
        this.eventType = None
        this.eventRetry = None
    }
}
