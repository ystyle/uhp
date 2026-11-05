// SSE 帧解析：字节级增量，跨 chunk 的半行必须拼回去。
package uhp_opencode.client

import std.collection.ArrayList

public class SseFrame {
    public let event: String
    public let data: String

    public init(event: String, data: String) {
        this.event = event
        this.data = data
    }
}

public class SseParser {
    private var pending: String = ""

    public init() {}

    // 喂一段字节，吐出已经完整的帧
    public func feed(bytes: Array<UInt8>): Array<SseFrame> {
        this.pending = this.pending + String.fromUtf8(bytes)
        let frames = ArrayList<SseFrame>()
        while (true) {
            let idx = match (this.pending.indexOf("\n\n")) {
                case Some(v) => v
                case None => break
            }
            let block = this.pending[0..idx]
            this.pending = this.pending[idx + 2..this.pending.size]
            var event = ""
            var data = ""
            for (line in block.split("\n")) {
                let l = line.trimAscii()
                if (l.startsWith("event:")) {
                    event = l[6..l.size].trimAscii()
                } else if (l.startsWith("data:")) {
                    let d = l[5..l.size].trimAscii()
                    data = if (data.size == 0) { d } else { data + "\n" + d }
                }
            }
            if (data.size > 0) {
                frames.add(SseFrame(event, data))
            }
        }
        return frames.toArray()
    }
}
