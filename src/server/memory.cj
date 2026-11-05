// 记忆（Memories 章）：树形记忆空间 + 记录 + 召回 + 版本 + 遗忘/擦除 + prime。
//
// 契约要点（套件 ME 组逐条验证）：
//   * memory 是**树节点**：parent_id、ancestors（root 在前）、privileges 四项；
//   * record 的 written_by 由服务端盖章（客户端传的不可信），trust 一律 untrusted；
//   * content 是有序 part 列表：text 有 text、file 有 file.id 且由服务端补全；
//   * 修订**追加版本**，旧版本留在 history（时间观点也留在当时）；
//   * 问题只看自己与下面（depth 0 = 只看自己），provider 不支持的信号必须进 degraded；
//   * 遗忘 = 关闭记录（仍可读、状态 forgotten，列表默认不列），擦除 = 真删（404）。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.codec.*

// 上传文件的只读视图（memory 的 file part 由服务端从自己的文件库补全）
public class FileStoreView {
    private let files: HashMap<String, StoredFile>

    public init(files: HashMap<String, StoredFile>) {
        this.files = files
    }

    public func get(id: String): Option<StoredFile> {
        return this.files.get(id)
    }
}

public class MemoryNodeRec {
    public let id: String
    public var name: String
    public var description: Option<String>
    public let provider: String
    public var parentId: Option<String> = None
    public var ancestors: Array<String> = []
    public let createdAt: Int64
    public var updatedAt: Int64

    public init(id: String, name: String, description: Option<String>, provider: String) {
        this.id = id
        this.name = name
        this.description = description
        this.provider = provider
        this.createdAt = nowSeconds()
        this.updatedAt = this.createdAt
    }
}

// 一个版本：内容 / 属性 / 引用都按原文保存（未知字段不丢），另存派生信息供召回与图使用
public class MemoryVersion {
    public let version: Int64
    public let titleJson: Option<String>
    public let contentJson: String
    public let attributesJson: String
    public var referencesJson: String
    public var timeJson: String
    public let writtenByJson: String
    public let createdAt: Int64
    // 派生：搜索文本与 standing（prime 只看 standing 记录）
    public let searchText: String
    public let standing: Bool
    public var references: Array<(String, String)>
    public let validTo: Option<Int64>

    public init(version: Int64, titleJson: Option<String>, contentJson: String, attributesJson: String,
                referencesJson: String, timeJson: String, writtenByJson: String, searchText: String,
                standing: Bool, references: Array<(String, String)>, validTo: Option<Int64>) {
        this.version = version
        this.titleJson = titleJson
        this.contentJson = contentJson
        this.attributesJson = attributesJson
        this.referencesJson = referencesJson
        this.timeJson = timeJson
        this.writtenByJson = writtenByJson
        this.createdAt = nowSeconds()
        this.searchText = searchText
        this.standing = standing
        this.references = references
        this.validTo = validTo
    }
}

public class MemoryRecordRec {
    public let id: String
    public let memoryId: String
    public let recordType: String
    public let versions: ArrayList<MemoryVersion> = ArrayList<MemoryVersion>()
    // active | forgotten
    public var status: String = "active"
    public let createdAt: Int64
    public var updatedAt: Int64

    public init(id: String, memoryId: String, recordType: String) {
        this.id = id
        this.memoryId = memoryId
        this.recordType = recordType
        this.createdAt = nowSeconds()
        this.updatedAt = this.createdAt
    }

    public func latest(): MemoryVersion {
        return this.versions[this.versions.size - 1]
    }
}

// ---------- 解析写体 ----------

public class MemoryWrite {
    public var typeName: String = ""
    public var title: Option<String> = None
    public var contentJson: Option<String> = None
    public var attributesJson: Option<String> = None
    public var referencesJson: Option<String> = None
    public var timeJson: Option<String> = None
    // 客户端传的 written_by 一律丢弃（服务端盖章）
    public var writtenByJson: Option<String> = None
}

public func parseMemoryWrite(r: JsonReader): MemoryWrite {
    let out = MemoryWrite()
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ => throw JsonProtocolException("bad json")
        }
        match (name) {
            case "type" => out.typeName = r.readValue<String>()
            case "title" => out.title = Some(r.readValue<String>())
            case "content" => out.contentJson = Some(String.fromUtf8(r.readValueBytes()))
            case "attributes" => out.attributesJson = Some(String.fromUtf8(r.readValueBytes()))
            case "references" => out.referencesJson = Some(String.fromUtf8(r.readValueBytes()))
            case "time" => out.timeJson = Some(String.fromUtf8(r.readValueBytes()))
            case "written_by" =>
                // 保留原文仅用于「客户端想写什么」的诊断，绝不采用
                let _ = r.readValueBytes()
            case _ => r.skip()
        }
    }
    r.endObject()
    return out
}

// content 校验 + 规范化：string -> [{type:text,text}]；part 形状不对 -> 422
public func normalizeContent(w: MemoryWrite, files: FileStoreView): String {
    match (w.contentJson) {
        case None => return "[]"
        case Some(raw) =>
            let bytes = raw.toArray()
            let r = JsonReader(ByteBuffer(bytes))
            match (r.peek()) {
                case Some(JsonToken.JsonString) =>
                    let text = r.readValue<String>()
                    return "[{\"type\":\"text\",\"text\":" + jsonQuote(text) + "}]"
                case Some(JsonToken.BeginArray) =>
                    return normalizeParts(raw, files)
                case _ => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
            }
    }
}

func normalizeParts(raw: String, files: FileStoreView): String {
    let out = ArrayList<String>()
    let r = JsonReader(ByteBuffer(raw.toArray()))
    r.startArray()
    var i: Int64 = 0
    while (true) {
        match (r.peek()) {
            case Some(JsonToken.EndArray) => break
            case Some(JsonToken.BeginObject) =>
                let part = String.fromUtf8(r.readValueBytes())
                out.add(checkPart(part, files, i))
                i = i + 1
            case _ => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
        }
    }
    r.endArray()
    if (out.size == 0) {
        // 空数组等价于「没有内容」，允许（title-only 记录）
        return "[]"
    }
    var joined = "["
    var first = true
    for (p in out) {
        if (!first) {
            joined = joined + ","
        }
        first = false
        joined = joined + p
    }
    return joined + "]"
}

func checkPart(partJson: String, files: FileStoreView, index: Int64): String {
    let o = match (tryParseJsonObject(partJson)) {
        case Some(v) => v
        case None => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
    }
    let kind = o.str("type") ?? ""
    match (kind) {
        case "text" =>
            let text = o.str("text") ?? ""
            if (text.size == 0) {
                throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
            }
            let role = o.str("role")
            match (role) {
                case Some(v) =>
                    if (!["user", "assistant", "system", "tool"].contains(v)) {
                        throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
                    }
                case None => ()
            }
            return partJson
        case "file" =>
            let fileObj = match (o.raw("file")) {
                case Some(v) => v
                case None => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
            }
            let fo = match (tryParseJsonObject(fileObj)) {
                case Some(v) => v
                case None => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
            }
            let id = fo.str("id") ?? ""
            let file = match (files.get(id)) {
                case Some(f) => f
                case None => throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
            }
            // 声明的 media 是 text/*：图片一律拒绝（memory_unsupported），不静默存储
            if (!file.contentType().startsWith("text/")) {
                throw EngineError("memory_unsupported", UInt16(422), param: Some("content"))
            }
            let w = StringBuilder()
            w.append("{\"type\":\"file\",\"file\":{\"id\":\"")
            w.append(file.id)
            w.append("\",\"name\":\"")
            w.append(file.filename)
            w.append("\",\"media_type\":\"")
            w.append(file.contentType())
            w.append("\",\"bytes\":")
            w.append(file.bytes.size.toString())
            w.append("}")
            match (o.str("text")) {
                case Some(t) =>
                    w.append(",\"text\":")
                    w.append(jsonQuote(t))
                case None => ()
            }
            w.append("}")
            return w.toString()
        case _ =>
            if (kind.startsWith("x.")) {
                return partJson
            }
            throw EngineError("memory_invalid", UInt16(422), param: Some("content"))
    }
}

// JSON 字符串编码（转义走 JsonWriter，避免手写错）
public func jsonQuote(s: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    w.writeValue(s)
    w.endArray()
    w.flush()
    let text = String.fromUtf8(out.bytes())
    // 去掉首尾的 []
    return text[1..text.size - 1]
}

// ---------- 派生 ----------

public func contentSearchText(contentJson: String): String {
    let texts = jsonStrings(contentJson, "text")
    let out = StringBuilder()
    for ((t, _) in texts) {
        out.append(t)
        out.append(" ")
    }
    return out.toString()
}

public func refsOf(referencesJson: String): Array<(String, String)> {
    let out = ArrayList<(String, String)>()
    // 每个引用对象里同时有 rel 与 record_id：逐个对象解析
    try {
        let r = JsonReader(ByteBuffer(referencesJson.toArray()))
        r.startArray()
        while (true) {
            match (r.peek()) {
                case Some(JsonToken.EndArray) => break
                case Some(JsonToken.BeginObject) =>
                    let obj = String.fromUtf8(r.readValueBytes())
                    match (tryParseJsonObject(obj)) {
                        case Some(o) =>
                            let rel = o.str("rel") ?? ""
                            let rid = o.str("record_id") ?? ""
                            if (rel.size > 0 && rid.size > 0) {
                                out.add((rel, rid))
                            }
                        case None => ()
                    }
                case _ => r.skip()
            }
        }
        r.endArray()
    } catch (e: Exception) {
        ()
    }
    return out.toArray()
}

public func standingOf(attributesJson: String): Bool {
    match (tryParseJsonObject(attributesJson)) {
        case Some(o) => return (o.raw("standing") ?? "") == "true"
        case None => return false
    }
}

// ---------- 渲染 ----------

// 服务端盖章的 written_by：客户端传的值一律丢弃
public func memoryWriterJson(who: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("kind").writeValue("member")
    w.writeName("type").writeValue("agent")
    w.writeName("id").writeValue(who)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func memoryProvidersJson(providerJson: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("data")
    w.startArray()
    w.jsonValue(providerJson)
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func memoryJson(m: MemoryNodeRec): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue(m.id)
    w.writeName("object").writeValue("memory")
    w.writeName("name").writeValue(m.name)
    match (m.description) {
        case Some(d) => w.writeName("description").writeValue(d)
        case None => ()
    }
    match (m.parentId) {
        case Some(p) => w.writeName("parent_id").writeValue(p)
        case None => w.writeName("parent_id").writeNullValue()
    }
    w.writeName("ancestors")
    w.startArray()
    for (a in m.ancestors) {
        w.writeValue(a)
    }
    w.endArray()
    w.writeName("restricted").writeValue(false)
    w.writeName("provider").writeValue(m.provider)
    w.writeName("privileges")
    w.startArray()
    for (p in ["read", "write", "create", "delete"]) {
        w.writeValue(p)
    }
    w.endArray()
    w.writeName("createdAt").writeValue(m.createdAt)
    w.writeName("updatedAt").writeValue(m.updatedAt)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 在引用数组上追加一条（保留原有对象原文）
public func withReference(refsJson: String, rel: String, recordId: String): String {
    let body = refsJson.trimAscii()
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    if (body.size > 2) {
        // 去掉首尾方括号后把已有元素原样搬进去
        let inner = body[1..body.size - 1].trimAscii()
        if (inner.size > 0) {
            w.jsonValue(inner)
        }
    }
    w.startObject()
    w.writeName("rel").writeValue(rel)
    w.writeName("record_id").writeValue(recordId)
    w.endObject()
    w.endArray()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// POST 记录的应答：除记录本身外，带本次写入的 closed / conflicts（规范要求，且**不存储**）
public func memoryRecordWriteJson(rec: MemoryRecordRec, closed: Array<String>,
                                  conflicts: Array<String>): String {
    let base = memoryRecordJson(rec)
    let cut = base[0..base.size - 1]   // 去掉结尾的 }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("closed")
    w.startArray()
    for (c in closed) {
        w.writeValue(c)
    }
    w.endArray()
    w.writeName("conflicts")
    w.startArray()
    for (c in conflicts) {
        w.writeValue(c)
    }
    w.endArray()
    w.endObject()
    w.flush()
    let frag = String.fromUtf8(out.bytes())
    return cut + "," + frag[1..frag.size - 1] + "}"
}

// 版本里的时间：valid_from / valid_to 都是 ISO 字符串（同格式可直接按字典序比较）
public func timeField(timeJson: String, field: String): Option<String> {
    return match (tryParseJsonObject(timeJson)) {
        case Some(o) => o.str(field)
        case None => None
    }
}

public func renderTime(start: Option<String>, end: Option<String>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    match (start) {
        case Some(v) => w.writeName("valid_from").writeValue(v)
        case None => ()
    }
    match (end) {
        case Some(v) => w.writeName("valid_to").writeValue(v)
        case None => ()
    }
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// provider 自己动手的版本（例如「结束上一条事实」），on_behalf_of 是被代表的人
public func providerWriterJson(who: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("kind").writeValue("provider")
    w.writeName("on_behalf_of")
    let inner = memoryWriterJson(who)
    w.jsonValue(inner)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func memoryRecordJson(rec: MemoryRecordRec): String {
    let v = rec.latest()
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue(rec.id)
    w.writeName("object").writeValue("memory.record")
    w.writeName("memory_id").writeValue(rec.memoryId)
    w.writeName("type").writeValue(rec.recordType)
    match (v.titleJson) {
        case Some(t) => w.writeName("title").writeValue(t)
        case None => ()
    }
    w.writeName("content").jsonValue(v.contentJson)
    w.writeName("attributes").jsonValue(v.attributesJson)
    w.writeName("version").writeValue(v.version)
    w.writeName("status").writeValue(if (rec.status == "active") { "active" } else { "forgotten" })
    w.writeName("trust").writeValue("untrusted")
    w.writeName("time").jsonValue(v.timeJson)
    w.writeName("written_by").jsonValue(v.writtenByJson)
    let refsText = v.referencesJson.trimAscii()
    if (refsText.size > 2) {
        w.writeName("references").jsonValue(refsText)
    } else {
        w.writeName("references")
        w.startArray()
        w.endArray()
    }
    w.writeName("created_at").writeValue(rec.createdAt)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func memoryHistoryJson(rec: MemoryRecordRec): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("memory.record.history")
    w.writeName("data")
    w.startArray()
    var idx: Int64 = 0
    for (v in rec.versions) {
        w.startObject()
        w.writeName("version").writeValue(v.version)
        w.writeName("status").writeValue(if (idx == Int64(rec.versions.size) - 1) { "active" } else { "superseded" })
        w.writeName("content").jsonValue(v.contentJson)
        w.writeName("attributes").jsonValue(v.attributesJson)
        w.writeName("time").jsonValue(v.timeJson)
        w.writeName("written_by").jsonValue(v.writtenByJson)
        w.writeName("created_at").writeValue(v.createdAt)
        w.endObject()
        idx = idx + 1
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func memoryProviderJson(): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue("uhp-local")
    w.writeName("isolation").writeValue("shared")
    w.writeName("derivation").writeValue("none")
    w.writeName("prime").writeValue(true)
    // holds=true：实现「一个属性只持一个值」的时序事实（valid_from/valid_to/closed/conflicts）
    w.writeName("holds").writeValue(true)
    w.writeName("recall")
    w.startObject()
    w.writeName("signals")
    w.startArray()
    for (s in ["query", "text"]) {
        w.writeValue(s)
    }
    w.endArray()
    w.endObject()
    w.writeName("history")
    w.startObject()
    w.writeName("content").writeValue("versions")
    w.endObject()
    w.writeName("erase")
    w.startObject()
    w.writeName("supported").writeValue(true)
    w.endObject()
    // graph.entities=records：实体与引用按记录保存，图由引用推导
    w.writeName("graph")
    w.startObject()
    w.writeName("entities").writeValue("records")
    w.endObject()
    w.writeName("content")
    w.startObject()
    w.writeName("media")
    w.startArray()
    w.writeValue("text/*")
    w.endArray()
    w.endObject()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}
