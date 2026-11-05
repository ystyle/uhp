// 19 个匿名响应/请求信封。
//
// 为什么手写：上游 schema.json 的生成链只搬 components.schemas -> $defs，
// **完全不碰 paths**，所以列表/删除/取消这类「端点级信封」在 schema.json 里根本不存在，
// 只能按 openapi.yaml 的 paths 手写（见 docs/spec-conflicts.md、调研报告 §2.4）。
package uhp.types.handwritten

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.generated.*

// ---------- Core ----------

// GET /v1/harnesses
public class HarnessList <: JsonSerializable & JsonDeserializable<HarnessList> {
    public var harnesses: Array<Harness> = []
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("harnesses")
        w.startArray()
        for (h in this.harnesses) { h.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessList {
        let res = HarnessList()
        fromJsonObjectWithExtras(r, [("harnesses", { => res.harnesses = r.readValue<Array<Harness>>() })], res.extras)
        return res
    }
}

// DELETE /v1/responses/{id}
public class ResponseDeleted <: JsonSerializable & JsonDeserializable<ResponseDeleted> {
    public var id: String = ""
    public var deleted: Bool = false
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("deleted").writeValue(this.deleted)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResponseDeleted {
        let res = ResponseDeleted()
        fromJsonObjectWithExtras(r, [
            ("id", { => res.id = r.readValue<String>() }),
            ("deleted", { => res.deleted = r.readValue<Bool>() })
        ], res.extras)
        return res
    }
}

// GET /v1/responses/{id}/input_items（object 固定为 "list"，data 是原始 item 数组）
public class ResponseInputItems <: JsonSerializable & JsonDeserializable<ResponseInputItems> {
    public var objectKind: String = "list"
    public var data: Array<Raw> = []
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("object").writeValue(this.objectKind)
        w.writeName("data")
        w.startArray()
        for (v in this.data) { w.jsonValue(v) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResponseInputItems {
        let res = ResponseInputItems()
        fromJsonObjectWithExtras(r, [
            ("object", { => res.objectKind = r.readValue<String>() }),
            ("data", { => res.data = r.readValue<Array<String>>() })
        ], res.extras)
        return res
    }
}

// POST /v1/sessions/{id}/cancel
public class SessionCancelResult <: JsonSerializable & JsonDeserializable<SessionCancelResult> {
    public var id: String = ""
    public var status: String = ""
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("status").writeValue(this.status)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionCancelResult {
        let res = SessionCancelResult()
        fromJsonObjectWithExtras(r, [
            ("id", { => res.id = r.readValue<String>() }),
            ("status", { => res.status = r.readValue<String>() })
        ], res.extras)
        return res
    }
}

// ---------- Extended ----------

// GET /v1/sessions/{id}/turns
public class SessionTurns <: JsonSerializable & JsonDeserializable<SessionTurns> {
    public var turns: Array<TurnItem> = []
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("turns")
        w.startArray()
        for (t in this.turns) { t.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionTurns {
        let res = SessionTurns()
        fromJsonObjectWithExtras(r, [("turns", { => res.turns = r.readValue<Array<TurnItem>>() })], res.extras)
        return res
    }
}

// GET /v1/sessions/{id}/files
public class SessionFileList <: JsonSerializable & JsonDeserializable<SessionFileList> {
    public var files: Array<File> = []
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("files")
        w.startArray()
        for (f in this.files) { f.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionFileList {
        let res = SessionFileList()
        fromJsonObjectWithExtras(r, [("files", { => res.files = r.readValue<Array<File>>() })], res.extras)
        return res
    }
}

// ---------- Full ----------

// DELETE /v1/harnesses/{id}
// sessions 是 "kept"/"retired" 的枚举（规范里唯一的内联枚举）；省略即 kept。
// restorableUntil 是 **Unix 秒**（注意 createdAt 是毫秒，两者不可混用）。
public class HarnessDeleted <: JsonSerializable & JsonDeserializable<HarnessDeleted> {
    public var id: String = ""
    public var deleted: Bool = false
    public var sessions: Option<String> = None
    public var restorableUntil: Option<Int64> = None
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("deleted").writeValue(this.deleted)
        if (let Some(v) <- this.sessions) { w.writeName("sessions").writeValue(v) }
        if (let Some(v) <- this.restorableUntil) { w.writeName("restorableUntil").writeValue(v) }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessDeleted {
        let res = HarnessDeleted()
        fromJsonObjectWithExtras(r, [
            ("id", { => res.id = r.readValue<String>() }),
            ("deleted", { => res.deleted = r.readValue<Bool>() }),
            ("sessions", { => res.sessions = r.readValue<Option<String>>() }),
            ("restorableUntil", { => res.restorableUntil = r.readValue<Option<Int64>>() })
        ], res.extras)
        return res
    }
}

// POST/GET /v1/sessions/{id}/share；body 可空（无 body = publish）
public class SessionShareRequest <: JsonSerializable & JsonDeserializable<SessionShareRequest> {
    public var enabled: Option<Bool> = None
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.enabled) { w.writeName("enabled").writeValue(v) }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionShareRequest {
        let res = SessionShareRequest()
        fromJsonObjectWithExtras(r, [("enabled", { => res.enabled = r.readValue<Option<Bool>>() })], res.extras)
        return res
    }
}

// DELETE /v1/sessions/{id}（规范里存在但 openapi 完全缺失的那个端点，见 spec-conflicts A1）
public class Deleted <: JsonSerializable & JsonDeserializable<Deleted> {
    public var id: String = ""
    public var deleted: Bool = false
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("deleted").writeValue(this.deleted)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Deleted {
        let res = Deleted()
        fromJsonObjectWithExtras(r, [
            ("id", { => res.id = r.readValue<String>() }),
            ("deleted", { => res.deleted = r.readValue<Bool>() })
        ], res.extras)
        return res
    }
}
