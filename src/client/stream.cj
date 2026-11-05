// 流式任务的事件消费。
//
// 必须遵守的三条（Streaming §1/§3/§4）：
//   1. sequence_number 从 0 起严格 +1 → 发现缺口就报错，不静默渲染；
//   2. 未知事件类型要容忍并继续读（UhpEvent.Unknown）；
//   3. 终态事件恰好一个且最后。
package uhp.client

import std.collection.ArrayList
import stdx.encoding.json.stream.*
import std.io.*
import uhp.types.handwritten.*
import uhp.transport.*

public class TaskStream {
    private let source: SseStream
    private let parser: SseParser
    private let pending: ArrayList<UhpEvent> = ArrayList<UhpEvent>()
    private var expectedSeq: Int64 = 0
    private var sawTerminal: Bool = false
    private var closed: Bool = false

    public init(source: SseStream) {
        this.source = source
        this.parser = SseParser()
    }

    // 下一个事件；None = 流结束。序号缺口抛 StreamGap（可由调用方决定重连或读回响应）。
    public func next(): Option<UhpEvent> {
        while (this.pending.isEmpty()) {
            if (this.closed) {
                return None
            }
            match (this.source.nextChunk()) {
                case Some(chunk) =>
                    for (ev in this.parser.feed(chunk)) {
                        this.accept(ev)
                    }
                case None =>
                    for (ev in this.parser.finish()) {
                        this.accept(ev)
                    }
                    this.closed = true
            }
        }
        let ev = this.pending[0]
        this.pending.remove(at: 0)
        return Some(ev)
    }

    public func finished(): Bool {
        return this.closed && this.pending.isEmpty()
    }

    // 是否已收到终态事件（completed/incomplete/failed）
    public func hasTerminal(): Bool {
        return this.sawTerminal
    }

    public func close(): Unit {
        this.closed = true
        this.source.close()
    }

    private func accept(raw: SseEvent): Unit {
        let ev = parseEvent(raw.data)
        match (sequenceNumberOf(ev)) {
            case Some(n) =>
                if (n != this.expectedSeq) {
                    throw StreamGap(this.expectedSeq, n)
                }
                this.expectedSeq = n + 1
            case None =>
                // 未知事件允许不带序号（否则一条未来事件会毒死整条流）
                ()
        }
        if (isTerminal(ev)) {
            this.sawTerminal = true
        }
        this.pending.add(ev)
    }
}

func parseEvent(data: String): UhpEvent {
    let r = JsonReader(ByteBuffer(data.toArray()))
    return UhpEvent.fromJson(r)
}
