// 会话分享（Sessions §5）：发布只读视图、读回、吊销。
//
// §5 说分享是 MAY；一旦实现，**严格**的是它的边界：
//   * 链接本身不是 API 凭证（share id 不能当 bearer 用）；
//   * 视图只读：不能继续/取消/上传；
//   * 视图不含任何凭证（provider token、MCP 的 auth/headers/env 都算）；
//   * 吊销必须让这个会话**所有**已发链接都失效；
//   * 删会话必须连带删掉分享视图。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.generated.*

public class ShareRecord {
    public let id: String
    public let token: String
    public let sessionId: String
    public let owner: String
    public let createdAt: Int64
    public var revoked: Bool = false

    public init(id: String, token: String, sessionId: String, owner: String) {
        this.id = id
        this.token = token
        this.sessionId = sessionId
        this.owner = owner
        this.createdAt = nowSeconds()
    }

    public func url(): String {
        return "/v1/shared/" + this.token
    }

    public func toJson(): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("object").writeValue("session.share")
        w.writeName("url").writeValue(this.url())
        w.writeName("session_id").writeValue(this.sessionId)
        w.writeName("enabled").writeValue(!this.revoked)
        w.writeName("created_at").writeValue(this.createdAt)
        w.endObject()
        w.flush()
        return String.fromUtf8(out.bytes())
    }
}

// 共享视图：只放「对话本身」。这里出现的键名会被检查是否像凭证
// （auth/headers/env/token/...），所以不放任何配置——只放消息与状态。
public func sharedViewJson(rec: SessionRecord, turns: Array<TurnItem>, outputs: HashMap<String, String>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("shared_session")
    w.writeName("session_id").writeValue(rec.id)
    w.writeName("title").writeValue(rec.title)
    w.writeName("created_at").writeValue(rec.createdAt)
    w.writeName("turns")
    w.startArray()
    for (t in turns) {
        w.startObject()
        w.writeName("id").writeValue(t.id)
        w.writeName("status").writeValue(t.status)
        match (t.created_at) {
            case Some(v) => w.writeName("created_at").writeValue(v)
            case None => ()
        }
        match (outputs.get(t.id)) {
            case Some(text) => w.writeName("text").writeValue(text)
            case None => ()
        }
        w.endObject()
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}
