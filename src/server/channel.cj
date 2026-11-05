// 事件通道：一次任务一条有序事件缓冲 + 多个订阅者游标 + 按序号重放。
//
// 三条契约（Streaming §1/§3）：
//   1. sequence_number 从 0 起、步长 1 —— **只在这里分配**，handler 不得各自自增；
//   2. 订阅者断开只影响它自己，不影响任务、也不影响其它订阅者；
//   3. 任务终态后缓冲保留到响应被删除（GET /v1/responses/{id} 与 Last-Event-ID 重放都靠它）。
package uhp.server

import std.collection.ArrayList
import std.sync.Mutex

public class StoredEvent {
    public let seq: Int64
    // UHP 事件类型名（如 response.output_text.delta）
    public let eventType: String
    // 事件的 JSON 文本（含 type 与 sequence_number）
    public let json: String

    public init(seq: Int64, eventType: String, json: String) {
        this.seq = seq
        this.eventType = eventType
        this.json = json
    }
}

public class EventChannel {
    private let lock = Mutex()
    private let events: ArrayList<StoredEvent> = ArrayList<StoredEvent>()
    private var nextSeq: Int64 = 0
    private var closed: Bool = false

    public init() {}

    // 分配序号并保存事件；返回分配的序号。通道关闭后返回 -1（调用方应停止发送）。
    public func emit(eventType: String, json: String): Int64 {
        synchronized(this.lock) {
            if (this.closed) {
                return -1
            }
            let seq = this.nextSeq
            this.nextSeq = this.nextSeq + 1
            this.events.add(StoredEvent(seq, eventType, json))
            return seq
        }
    }

    // 从 fromSeq（含）开始重放已保存的事件——重连与 Last-Event-ID 用。
    public func replay(fromSeq: Int64): Array<StoredEvent> {
        synchronized(this.lock) {
            let out = ArrayList<StoredEvent>()
            for (e in this.events) {
                if (e.seq >= fromSeq) {
                    out.add(e)
                }
            }
            return out.toArray()
        }
    }

    public func lastSeq(): Int64 {
        synchronized(this.lock) {
            return this.nextSeq - 1
        }
    }

    public func count(): Int64 {
        synchronized(this.lock) {
            return this.events.size
        }
    }

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
        }
    }

    public func isClosed(): Bool {
        synchronized(this.lock) {
            return this.closed
        }
    }
}
