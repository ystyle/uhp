// 会话、容器与产物的存储（Extended 类需要）。
//
// 关系（Architecture §3）：Session -> Container -> File。容器是会话的文件命名空间；
// 产物属于容器，删会话即不可达。这里用内存实现，接缝留给宿主替换。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.time.DateTime

public class SessionRecord {
    public let id: String
    public let harnessId: String
    public let owner: String
    public let containerId: String
    public var title: String
    public let createdAt: Int64
    public var updatedAt: Int64
    // 该会话内的响应 id，按时间顺序 —— /turns 的数据来源（不是向 harness 要历史）
    public let responseIds: ArrayList<String> = ArrayList<String>()

    public init(id: String, harnessId: String, owner: String, containerId: String, title: String) {
        this.id = id
        this.harnessId = harnessId
        this.owner = owner
        this.containerId = containerId
        this.title = title
        this.createdAt = nowSeconds()
        this.updatedAt = this.createdAt
    }
}

public class StoredFile {
    public let id: String
    public let containerId: String
    public let sessionId: String
    public let owner: String
    public let filename: String
    public let bytes: Array<UInt8>
    public let createdAt: Int64

    public init(id: String, containerId: String, sessionId: String, owner: String,
                filename: String, bytes: Array<UInt8>) {
        this.id = id
        this.containerId = containerId
        this.sessionId = sessionId
        this.owner = owner
        this.filename = filename
        this.bytes = bytes
        this.createdAt = nowSeconds()
    }

    public func contentType(): String {
        if (this.filename.endsWith(".txt")) {
            return "text/plain; charset=utf-8"
        }
        if (this.filename.endsWith(".json")) {
            return "application/json"
        }
        if (this.filename.endsWith(".md")) {
            return "text/markdown; charset=utf-8"
        }
        return "application/octet-stream"
    }
}
