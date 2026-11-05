// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class MemoryRecords <: JsonSerializable & JsonDeserializable<MemoryRecords> {
    public var count: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.count) {
                        w.writeName("count").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecords {
        let res = MemoryRecords()
        fromJsonObjectWithExtras(
            r,
            [
                ("count", { => res.count = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryChildren <: JsonSerializable & JsonDeserializable<MemoryChildren> {
    public var count: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.count) {
                        w.writeName("count").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryChildren {
        let res = MemoryChildren()
        fromJsonObjectWithExtras(
            r,
            [
                ("count", { => res.count = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Memory <: JsonSerializable & JsonDeserializable<Memory> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var name: String = ""
    public var description: Option<String> = None
    public var parent_id: Option<Raw> = None
    public var ancestors: Option<Array<String>> = None
    public var restricted: Option<Bool> = None
    public var provider: Option<String> = None
    public var privileges: Array<String> = []
    public var records: Option<MemoryRecords> = None
    public var children: Option<MemoryChildren> = None
    public var createdAt: Option<Int64> = None
    public var updatedAt: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.parent_id) {
                        w.writeName("parent_id").jsonValue(v)
        }
        if (let Some(v) <- this.ancestors) {
                        w.writeName("ancestors").writeValue(v)
        }
        if (let Some(v) <- this.restricted) {
                        w.writeName("restricted").writeValue(v)
        }
        if (let Some(v) <- this.provider) {
                        w.writeName("provider").writeValue(v)
        }
                w.writeName("privileges").writeValue(this.privileges)
        if (let Some(v) <- this.records) {
                        w.writeName("records"); v.toJson(w)
        }
        if (let Some(v) <- this.children) {
                        w.writeName("children"); v.toJson(w)
        }
        if (let Some(v) <- this.createdAt) {
                        w.writeName("createdAt").writeValue(v)
        }
        if (let Some(v) <- this.updatedAt) {
                        w.writeName("updatedAt").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Memory {
        let res = Memory()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("parent_id", { => res.parent_id = readRaw(r) }),
                ("ancestors", { => res.ancestors = r.readValue<Option<Array<String>>>() }),
                ("restricted", { => res.restricted = r.readValue<Option<Bool>>() }),
                ("provider", { => res.provider = r.readValue<Option<String>>() }),
                ("privileges", { => res.privileges = r.readValue<Array<String>>() }),
                ("records", { => res.records = r.readValue<Option<MemoryRecords>>() }),
                ("children", { => res.children = r.readValue<Option<MemoryChildren>>() }),
                ("createdAt", { => res.createdAt = r.readValue<Option<Int64>>() }),
                ("updatedAt", { => res.updatedAt = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryConsolidation <: JsonSerializable & JsonDeserializable<MemoryConsolidation> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var memory_id: Option<String> = None
    public var status: String = ""
    public var trigger: Option<String> = None
    public var started_at: Option<Raw> = None
    public var finished_at: Option<Raw> = None
    public var read: Option<Raw> = None
    public var changes: Option<Raw> = None
    public var usage: Option<Raw> = None
    public var budget: Option<Raw> = None
    public var written_by: Option<MemoryWriter> = None
    public var error: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.memory_id) {
                        w.writeName("memory_id").writeValue(v)
        }
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.trigger) {
                        w.writeName("trigger").writeValue(v)
        }
        if (let Some(v) <- this.started_at) {
                        w.writeName("started_at").jsonValue(v)
        }
        if (let Some(v) <- this.finished_at) {
                        w.writeName("finished_at").jsonValue(v)
        }
        if (let Some(v) <- this.read) {
                        w.writeName("read").jsonValue(v)
        }
        if (let Some(v) <- this.changes) {
                        w.writeName("changes").jsonValue(v)
        }
        if (let Some(v) <- this.usage) {
                        w.writeName("usage").jsonValue(v)
        }
        if (let Some(v) <- this.budget) {
                        w.writeName("budget").jsonValue(v)
        }
        if (let Some(v) <- this.written_by) {
                        w.writeName("written_by"); v.toJson(w)
        }
        if (let Some(v) <- this.error) {
                        w.writeName("error").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryConsolidation {
        let res = MemoryConsolidation()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("memory_id", { => res.memory_id = r.readValue<Option<String>>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("trigger", { => res.trigger = r.readValue<Option<String>>() }),
                ("started_at", { => res.started_at = readRaw(r) }),
                ("finished_at", { => res.finished_at = readRaw(r) }),
                ("read", { => res.read = readRaw(r) }),
                ("changes", { => res.changes = readRaw(r) }),
                ("usage", { => res.usage = readRaw(r) }),
                ("budget", { => res.budget = readRaw(r) }),
                ("written_by", { => res.written_by = r.readValue<Option<MemoryWriter>>() }),
                ("error", { => res.error = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryConsolidationList <: JsonSerializable & JsonDeserializable<MemoryConsolidationList> {
    public var data: Option<Array<MemoryConsolidation>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryConsolidationList {
        let res = MemoryConsolidationList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryConsolidation>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryConsolidationStart <: JsonSerializable & JsonDeserializable<MemoryConsolidationStart> {
    public var budget: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.budget) {
                        w.writeName("budget").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryConsolidationStart {
        let res = MemoryConsolidationStart()
        fromJsonObjectWithExtras(
            r,
            [
                ("budget", { => res.budget = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryContentPartFile <: JsonSerializable & JsonDeserializable<MemoryContentPartFile> {
    public var id: String = ""
    public var name: Option<String> = None
    public var media_type: Option<String> = None
    public var bytes: Option<Int64> = None
    public var version: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.media_type) {
                        w.writeName("media_type").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryContentPartFile {
        let res = MemoryContentPartFile()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("media_type", { => res.media_type = r.readValue<Option<String>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() }),
                ("version", { => res.version = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryContentPart <: JsonSerializable & JsonDeserializable<MemoryContentPart> {
    public var typeName: String = ""
    public var text: Option<String> = None
    public var text_source: Option<String> = None
    public var role: Option<String> = None
    public var name: Option<String> = None
    public var file: Option<MemoryContentPartFile> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.text) {
                        w.writeName("text").writeValue(v)
        }
        if (let Some(v) <- this.text_source) {
                        w.writeName("text_source").writeValue(v)
        }
        if (let Some(v) <- this.role) {
                        w.writeName("role").writeValue(v)
        }
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.file) {
                        w.writeName("file"); v.toJson(w)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryContentPart {
        let res = MemoryContentPart()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("text", { => res.text = r.readValue<Option<String>>() }),
                ("text_source", { => res.text_source = r.readValue<Option<String>>() }),
                ("role", { => res.role = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("file", { => res.file = r.readValue<Option<MemoryContentPartFile>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryCreate <: JsonSerializable & JsonDeserializable<MemoryCreate> {
    public var name: String = ""
    public var description: Option<String> = None
    public var parent_id: Option<Raw> = None
    public var restricted: Option<Bool> = None
    public var provider: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.parent_id) {
                        w.writeName("parent_id").jsonValue(v)
        }
        if (let Some(v) <- this.restricted) {
                        w.writeName("restricted").writeValue(v)
        }
        if (let Some(v) <- this.provider) {
                        w.writeName("provider").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryCreate {
        let res = MemoryCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("parent_id", { => res.parent_id = readRaw(r) }),
                ("restricted", { => res.restricted = r.readValue<Option<Bool>>() }),
                ("provider", { => res.provider = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryDeleted <: JsonSerializable & JsonDeserializable<MemoryDeleted> {
    public var id: Option<String> = None
    public var deleted: Option<Bool> = None
    public var memories: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.id) {
                        w.writeName("id").writeValue(v)
        }
        if (let Some(v) <- this.deleted) {
                        w.writeName("deleted").writeValue(v)
        }
        if (let Some(v) <- this.memories) {
                        w.writeName("memories").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryDeleted {
        let res = MemoryDeleted()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<Option<String>>() }),
                ("deleted", { => res.deleted = r.readValue<Option<Bool>>() }),
                ("memories", { => res.memories = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryErase <: JsonSerializable & JsonDeserializable<MemoryErase> {
    public var record_ids: Array<String> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("record_ids").writeValue(this.record_ids)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryErase {
        let res = MemoryErase()
        fromJsonObjectWithExtras(
            r,
            [
                ("record_ids", { => res.record_ids = r.readValue<Array<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryErasure <: JsonSerializable & JsonDeserializable<MemoryErasure> {
    public var erased: Array<String> = []
    public var unreachable: Array<String> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("erased").writeValue(this.erased)
                w.writeName("unreachable").writeValue(this.unreachable)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryErasure {
        let res = MemoryErasure()
        fromJsonObjectWithExtras(
            r,
            [
                ("erased", { => res.erased = r.readValue<Array<String>>() }),
                ("unreachable", { => res.unreachable = r.readValue<Array<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryFilter <: JsonSerializable & JsonDeserializable<MemoryFilter> {
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryFilter {
        let res = MemoryFilter()
        fromJsonObjectWithExtras(
            r,
            [

            ],
            res.extras
        )
        return res
    }
}

public class MemoryFreeQuery <: JsonSerializable & JsonDeserializable<MemoryFreeQuery> {
    public var language: Option<String> = None
    public var statement: String = ""
    public var params: Option<Raw> = None
    public var write: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.language) {
                        w.writeName("language").writeValue(v)
        }
                w.writeName("statement").writeValue(this.statement)
        if (let Some(v) <- this.params) {
                        w.writeName("params").jsonValue(v)
        }
        if (let Some(v) <- this.write) {
                        w.writeName("write").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryFreeQuery {
        let res = MemoryFreeQuery()
        fromJsonObjectWithExtras(
            r,
            [
                ("language", { => res.language = r.readValue<Option<String>>() }),
                ("statement", { => res.statement = r.readValue<String>() }),
                ("params", { => res.params = readRaw(r) }),
                ("write", { => res.write = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGrant <: JsonSerializable & JsonDeserializable<MemoryGrant> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var memory_id: String = ""
    public var principal: String = ""
    public var privileges: Array<String> = []
    public var inherited: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("memory_id").writeValue(this.memory_id)
                w.writeName("principal").writeValue(this.principal)
                w.writeName("privileges").writeValue(this.privileges)
        if (let Some(v) <- this.inherited) {
                        w.writeName("inherited").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGrant {
        let res = MemoryGrant()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("memory_id", { => res.memory_id = r.readValue<String>() }),
                ("principal", { => res.principal = r.readValue<String>() }),
                ("privileges", { => res.privileges = r.readValue<Array<String>>() }),
                ("inherited", { => res.inherited = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGrantCreate <: JsonSerializable & JsonDeserializable<MemoryGrantCreate> {
    public var principal: String = ""
    public var privileges: Array<String> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("principal").writeValue(this.principal)
                w.writeName("privileges").writeValue(this.privileges)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGrantCreate {
        let res = MemoryGrantCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("principal", { => res.principal = r.readValue<String>() }),
                ("privileges", { => res.privileges = r.readValue<Array<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGrantList <: JsonSerializable & JsonDeserializable<MemoryGrantList> {
    public var data: Option<Array<MemoryGrant>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGrantList {
        let res = MemoryGrantList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryGrant>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGraphNodesMemory <: JsonSerializable & JsonDeserializable<MemoryGraphNodesMemory> {
    public var id: String = ""
    public var name: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGraphNodesMemory {
        let res = MemoryGraphNodesMemory()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGraphNodes <: JsonSerializable & JsonDeserializable<MemoryGraphNodes> {
    public var record: MemoryRecord = MemoryRecord()
    public var memory: MemoryGraphNodesMemory = MemoryGraphNodesMemory()
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("record"); this.record.toJson(w)
                w.writeName("memory"); this.memory.toJson(w)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGraphNodes {
        let res = MemoryGraphNodes()
        fromJsonObjectWithExtras(
            r,
            [
                ("record", { => res.record = r.readValue<MemoryRecord>() }),
                ("memory", { => res.memory = r.readValue<MemoryGraphNodesMemory>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGraphEdges <: JsonSerializable & JsonDeserializable<MemoryGraphEdges> {
    public var from: MemoryRecordRef = MemoryRecordRef()
    public var to: MemoryRecordRef = MemoryRecordRef()
    public var rel: Option<String> = None
    public var available: Bool = false
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("from"); this.from.toJson(w)
                w.writeName("to"); this.to.toJson(w)
        if (let Some(v) <- this.rel) {
                        w.writeName("rel").writeValue(v)
        }
                w.writeName("available").writeValue(this.available)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGraphEdges {
        let res = MemoryGraphEdges()
        fromJsonObjectWithExtras(
            r,
            [
                ("from", { => res.from = r.readValue<MemoryRecordRef>() }),
                ("to", { => res.to = r.readValue<MemoryRecordRef>() }),
                ("rel", { => res.rel = r.readValue<Option<String>>() }),
                ("available", { => res.available = r.readValue<Bool>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGraph <: JsonSerializable & JsonDeserializable<MemoryGraph> {
    public var objectKind: Option<String> = None
    public var nodes: Array<MemoryGraphNodes> = []
    public var edges: Array<MemoryGraphEdges> = []
    public var truncated: Bool = false
    public var degraded: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("nodes"); w.startArray();
        for (e in this.nodes) { e.toJson(w) }
        w.endArray()
                w.writeName("edges"); w.startArray();
        for (e in this.edges) { e.toJson(w) }
        w.endArray()
                w.writeName("truncated").writeValue(this.truncated)
        if (let Some(v) <- this.degraded) {
                        w.writeName("degraded").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGraph {
        let res = MemoryGraph()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("nodes", { => res.nodes = r.readValue<Array<MemoryGraphNodes>>() }),
                ("edges", { => res.edges = r.readValue<Array<MemoryGraphEdges>>() }),
                ("truncated", { => res.truncated = r.readValue<Bool>() }),
                ("degraded", { => res.degraded = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryGraphRequest <: JsonSerializable & JsonDeserializable<MemoryGraphRequest> {
    public var around: Option<String> = None
    public var hops: Option<Int64> = None
    public var types: Option<Array<String>> = None
    public var limit: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.around) {
                        w.writeName("around").writeValue(v)
        }
        if (let Some(v) <- this.hops) {
                        w.writeName("hops").writeValue(v)
        }
        if (let Some(v) <- this.types) {
                        w.writeName("types").writeValue(v)
        }
        if (let Some(v) <- this.limit) {
                        w.writeName("limit").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryGraphRequest {
        let res = MemoryGraphRequest()
        fromJsonObjectWithExtras(
            r,
            [
                ("around", { => res.around = r.readValue<Option<String>>() }),
                ("hops", { => res.hops = r.readValue<Option<Int64>>() }),
                ("types", { => res.types = r.readValue<Option<Array<String>>>() }),
                ("limit", { => res.limit = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryJob <: JsonSerializable & JsonDeserializable<MemoryJob> {
    public var objectKind: Option<String> = None
    public var id: String = ""
    public var memory_id: Option<String> = None
    public var status: String = ""
    public var error: Option<String> = None
    public var data: Option<Array<MemoryRecord>> = None
    public var closed: Option<Array<String>> = None
    public var conflicts: Option<Array<String>> = None
    public var usage: Option<Raw> = None
    public var created_at: Option<Int64> = None
    public var started_at: Option<Raw> = None
    public var finished_at: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.memory_id) {
                        w.writeName("memory_id").writeValue(v)
        }
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.error) {
                        w.writeName("error").writeValue(v)
        }
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.closed) {
                        w.writeName("closed").writeValue(v)
        }
        if (let Some(v) <- this.conflicts) {
                        w.writeName("conflicts").writeValue(v)
        }
        if (let Some(v) <- this.usage) {
                        w.writeName("usage").jsonValue(v)
        }
        if (let Some(v) <- this.created_at) {
                        w.writeName("created_at").writeValue(v)
        }
        if (let Some(v) <- this.started_at) {
                        w.writeName("started_at").jsonValue(v)
        }
        if (let Some(v) <- this.finished_at) {
                        w.writeName("finished_at").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryJob {
        let res = MemoryJob()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("id", { => res.id = r.readValue<String>() }),
                ("memory_id", { => res.memory_id = r.readValue<Option<String>>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("error", { => res.error = r.readValue<Option<String>>() }),
                ("data", { => res.data = r.readValue<Option<Array<MemoryRecord>>>() }),
                ("closed", { => res.closed = r.readValue<Option<Array<String>>>() }),
                ("conflicts", { => res.conflicts = r.readValue<Option<Array<String>>>() }),
                ("usage", { => res.usage = readRaw(r) }),
                ("created_at", { => res.created_at = r.readValue<Option<Int64>>() }),
                ("started_at", { => res.started_at = readRaw(r) }),
                ("finished_at", { => res.finished_at = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryList <: JsonSerializable & JsonDeserializable<MemoryList> {
    public var objectKind: Option<String> = None
    public var data: Option<Array<Memory>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryList {
        let res = MemoryList()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("data", { => res.data = r.readValue<Option<Array<Memory>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryNeighbour <: JsonSerializable & JsonDeserializable<MemoryNeighbour> {
    public var id: Option<String> = None
    public var name: Option<String> = None
    public var description: Option<String> = None
    public var records: Option<Raw> = None
    public var children: Option<Raw> = None
    public var privileges: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.id) {
                        w.writeName("id").writeValue(v)
        }
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.records) {
                        w.writeName("records").jsonValue(v)
        }
        if (let Some(v) <- this.children) {
                        w.writeName("children").jsonValue(v)
        }
        if (let Some(v) <- this.privileges) {
                        w.writeName("privileges").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryNeighbour {
        let res = MemoryNeighbour()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("records", { => res.records = readRaw(r) }),
                ("children", { => res.children = readRaw(r) }),
                ("privileges", { => res.privileges = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryObserveEpisodesTime <: JsonSerializable & JsonDeserializable<MemoryObserveEpisodesTime> {
    public var valid_from: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.valid_from) {
                        w.writeName("valid_from").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryObserveEpisodesTime {
        let res = MemoryObserveEpisodesTime()
        fromJsonObjectWithExtras(
            r,
            [
                ("valid_from", { => res.valid_from = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryObserveEpisodes <: JsonSerializable & JsonDeserializable<MemoryObserveEpisodes> {
    public var content: Raw = ""
    public var time: Option<MemoryObserveEpisodesTime> = None
    public var attributes: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("content").jsonValue(this.content)
        if (let Some(v) <- this.time) {
                        w.writeName("time"); v.toJson(w)
        }
        if (let Some(v) <- this.attributes) {
                        w.writeName("attributes").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryObserveEpisodes {
        let res = MemoryObserveEpisodes()
        fromJsonObjectWithExtras(
            r,
            [
                ("content", { => res.content = readRaw(r) }),
                ("time", { => res.time = r.readValue<Option<MemoryObserveEpisodesTime>>() }),
                ("attributes", { => res.attributes = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryObserve <: JsonSerializable & JsonDeserializable<MemoryObserve> {
    public var episodes: Array<MemoryObserveEpisodes> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("episodes"); w.startArray();
        for (e in this.episodes) { e.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryObserve {
        let res = MemoryObserve()
        fromJsonObjectWithExtras(
            r,
            [
                ("episodes", { => res.episodes = r.readValue<Array<MemoryObserveEpisodes>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryOperationResult <: JsonSerializable & JsonDeserializable<MemoryOperationResult> {
    public var name: Option<String> = None
    public var result: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.result) {
                        w.writeName("result").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryOperationResult {
        let res = MemoryOperationResult()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("result", { => res.result = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryPrime <: JsonSerializable & JsonDeserializable<MemoryPrime> {
    public var records: Array<MemoryRecord> = []
    public var tokens: Int64 = 0
    public var truncated: Bool = false
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("records"); w.startArray();
        for (e in this.records) { e.toJson(w) }
        w.endArray()
                w.writeName("tokens").writeValue(this.tokens)
                w.writeName("truncated").writeValue(this.truncated)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryPrime {
        let res = MemoryPrime()
        fromJsonObjectWithExtras(
            r,
            [
                ("records", { => res.records = r.readValue<Array<MemoryRecord>>() }),
                ("tokens", { => res.tokens = r.readValue<Int64>() }),
                ("truncated", { => res.truncated = r.readValue<Bool>() })
            ],
            res.extras
        )
        return res
    }
}

// 上游字符串枚举；未知值落 Other，不抛错（客户端 MUST 容忍未来新增值）。
public enum MemoryPrivilege {
    | Read
    | Write
    | Create
    | Delete
    | Other(String)
}

public func memoryPrivilegeParse(s: String): MemoryPrivilege {
    return match (s) {
        case "read" => MemoryPrivilege.Read
        case "write" => MemoryPrivilege.Write
        case "create" => MemoryPrivilege.Create
        case "delete" => MemoryPrivilege.Delete
        case other => MemoryPrivilege.Other(other)
    }
}

public func memoryPrivilegeName(v: MemoryPrivilege): String {
    return match (v) {
        case MemoryPrivilege.Read => "read"
        case MemoryPrivilege.Write => "write"
        case MemoryPrivilege.Create => "create"
        case MemoryPrivilege.Delete => "delete"
        case MemoryPrivilege.Other(s) => s
    }
}

public class MemoryProviderGraph <: JsonSerializable & JsonDeserializable<MemoryProviderGraph> {
    public var entities: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.entities) {
                        w.writeName("entities").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryProviderGraph {
        let res = MemoryProviderGraph()
        fromJsonObjectWithExtras(
            r,
            [
                ("entities", { => res.entities = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryProviderContent <: JsonSerializable & JsonDeserializable<MemoryProviderContent> {
    public var media: Option<Array<String>> = None
    public var bytes: Option<String> = None
    public var describes: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.media) {
                        w.writeName("media").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        if (let Some(v) <- this.describes) {
                        w.writeName("describes").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryProviderContent {
        let res = MemoryProviderContent()
        fromJsonObjectWithExtras(
            r,
            [
                ("media", { => res.media = r.readValue<Option<Array<String>>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<String>>() }),
                ("describes", { => res.describes = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryProvider <: JsonSerializable & JsonDeserializable<MemoryProvider> {
    public var id: String = ""
    public var isolation: String = ""
    public var derivation: Option<String> = None
    public var prime: Option<Bool> = None
    public var holds: Option<Bool> = None
    public var observe: Option<Raw> = None
    public var recall: Option<Raw> = None
    public var history: Option<Raw> = None
    public var erase: Option<Raw> = None
    public var queries: Option<Raw> = None
    public var graph: Option<MemoryProviderGraph> = None
    public var content: Option<MemoryProviderContent> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
                w.writeName("isolation").writeValue(this.isolation)
        if (let Some(v) <- this.derivation) {
                        w.writeName("derivation").writeValue(v)
        }
        if (let Some(v) <- this.prime) {
                        w.writeName("prime").writeValue(v)
        }
        if (let Some(v) <- this.holds) {
                        w.writeName("holds").writeValue(v)
        }
        if (let Some(v) <- this.observe) {
                        w.writeName("observe").jsonValue(v)
        }
        if (let Some(v) <- this.recall) {
                        w.writeName("recall").jsonValue(v)
        }
        if (let Some(v) <- this.history) {
                        w.writeName("history").jsonValue(v)
        }
        if (let Some(v) <- this.erase) {
                        w.writeName("erase").jsonValue(v)
        }
        if (let Some(v) <- this.queries) {
                        w.writeName("queries").jsonValue(v)
        }
        if (let Some(v) <- this.graph) {
                        w.writeName("graph"); v.toJson(w)
        }
        if (let Some(v) <- this.content) {
                        w.writeName("content"); v.toJson(w)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryProvider {
        let res = MemoryProvider()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("isolation", { => res.isolation = r.readValue<String>() }),
                ("derivation", { => res.derivation = r.readValue<Option<String>>() }),
                ("prime", { => res.prime = r.readValue<Option<Bool>>() }),
                ("holds", { => res.holds = r.readValue<Option<Bool>>() }),
                ("observe", { => res.observe = readRaw(r) }),
                ("recall", { => res.recall = readRaw(r) }),
                ("history", { => res.history = readRaw(r) }),
                ("erase", { => res.erase = readRaw(r) }),
                ("queries", { => res.queries = readRaw(r) }),
                ("graph", { => res.graph = r.readValue<Option<MemoryProviderGraph>>() }),
                ("content", { => res.content = r.readValue<Option<MemoryProviderContent>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryProviderList <: JsonSerializable & JsonDeserializable<MemoryProviderList> {
    public var data: Option<Array<MemoryProvider>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryProviderList {
        let res = MemoryProviderList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryProvider>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryQuery <: JsonSerializable & JsonDeserializable<MemoryQuery> {
    public var name: Option<String> = None
    public var description: Option<String> = None
    public var params: Option<Raw> = None
    public var requires: Option<String> = None
    public var language: Option<String> = None
    public var body: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.params) {
                        w.writeName("params").jsonValue(v)
        }
        if (let Some(v) <- this.requires) {
                        w.writeName("requires").writeValue(v)
        }
        if (let Some(v) <- this.language) {
                        w.writeName("language").writeValue(v)
        }
                w.writeName("body").writeValue(this.body)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryQuery {
        let res = MemoryQuery()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("params", { => res.params = readRaw(r) }),
                ("requires", { => res.requires = r.readValue<Option<String>>() }),
                ("language", { => res.language = r.readValue<Option<String>>() }),
                ("body", { => res.body = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryQueryList <: JsonSerializable & JsonDeserializable<MemoryQueryList> {
    public var data: Option<Array<MemoryQuery>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryQueryList {
        let res = MemoryQueryList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryQuery>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryQueryRun <: JsonSerializable & JsonDeserializable<MemoryQueryRun> {
    public var params: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.params) {
                        w.writeName("params").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryQueryRun {
        let res = MemoryQueryRun()
        fromJsonObjectWithExtras(
            r,
            [
                ("params", { => res.params = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecallResultsMemory <: JsonSerializable & JsonDeserializable<MemoryRecallResultsMemory> {
    public var id: String = ""
    public var name: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecallResultsMemory {
        let res = MemoryRecallResultsMemory()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecallResults <: JsonSerializable & JsonDeserializable<MemoryRecallResults> {
    public var record: MemoryRecord = MemoryRecord()
    public var memory: MemoryRecallResultsMemory = MemoryRecallResultsMemory()
    public var score: Option<Raw> = None
    public var why: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("record"); this.record.toJson(w)
                w.writeName("memory"); this.memory.toJson(w)
        if (let Some(v) <- this.score) {
                        w.writeName("score").jsonValue(v)
        }
        if (let Some(v) <- this.why) {
                        w.writeName("why").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecallResults {
        let res = MemoryRecallResults()
        fromJsonObjectWithExtras(
            r,
            [
                ("record", { => res.record = r.readValue<MemoryRecord>() }),
                ("memory", { => res.memory = r.readValue<MemoryRecallResultsMemory>() }),
                ("score", { => res.score = readRaw(r) }),
                ("why", { => res.why = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecall <: JsonSerializable & JsonDeserializable<MemoryRecall> {
    public var results: Array<MemoryRecallResults> = []
    public var parent: Option<MemoryNeighbour> = None
    public var children: Option<Array<MemoryNeighbour>> = None
    public var degraded: Array<String> = []
    public var abstain: Bool = false
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("results"); w.startArray();
        for (e in this.results) { e.toJson(w) }
        w.endArray()
        if (let Some(v) <- this.parent) {
                        w.writeName("parent"); v.toJson(w)
        }
        if (let Some(v) <- this.children) {
                        w.writeName("children"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
                w.writeName("degraded").writeValue(this.degraded)
                w.writeName("abstain").writeValue(this.abstain)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecall {
        let res = MemoryRecall()
        fromJsonObjectWithExtras(
            r,
            [
                ("results", { => res.results = r.readValue<Array<MemoryRecallResults>>() }),
                ("parent", { => res.parent = r.readValue<Option<MemoryNeighbour>>() }),
                ("children", { => res.children = r.readValue<Option<Array<MemoryNeighbour>>>() }),
                ("degraded", { => res.degraded = r.readValue<Array<String>>() }),
                ("abstain", { => res.abstain = r.readValue<Bool>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecallRequest <: JsonSerializable & JsonDeserializable<MemoryRecallRequest> {
    public var query: Option<String> = None
    public var text: Option<String> = None
    public var filters: Option<MemoryFilter> = None
    public var types: Option<Array<String>> = None
    public var as_of: Option<Raw> = None
    public var include: Option<String> = None
    public var depth: Option<Raw> = None
    public var limit: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.query) {
                        w.writeName("query").writeValue(v)
        }
        if (let Some(v) <- this.text) {
                        w.writeName("text").writeValue(v)
        }
        if (let Some(v) <- this.filters) {
                        w.writeName("filters"); v.toJson(w)
        }
        if (let Some(v) <- this.types) {
                        w.writeName("types").writeValue(v)
        }
        if (let Some(v) <- this.as_of) {
                        w.writeName("as_of").jsonValue(v)
        }
        if (let Some(v) <- this.include) {
                        w.writeName("include").writeValue(v)
        }
        if (let Some(v) <- this.depth) {
                        w.writeName("depth").jsonValue(v)
        }
        if (let Some(v) <- this.limit) {
                        w.writeName("limit").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecallRequest {
        let res = MemoryRecallRequest()
        fromJsonObjectWithExtras(
            r,
            [
                ("query", { => res.query = r.readValue<Option<String>>() }),
                ("text", { => res.text = r.readValue<Option<String>>() }),
                ("filters", { => res.filters = r.readValue<Option<MemoryFilter>>() }),
                ("types", { => res.types = r.readValue<Option<Array<String>>>() }),
                ("as_of", { => res.as_of = readRaw(r) }),
                ("include", { => res.include = r.readValue<Option<String>>() }),
                ("depth", { => res.depth = readRaw(r) }),
                ("limit", { => res.limit = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordTime <: JsonSerializable & JsonDeserializable<MemoryRecordTime> {
    public var valid_from: Option<Raw> = None
    public var valid_to: Option<Raw> = None
    public var written_at: Option<Raw> = None
    public var invalidated_at: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.valid_from) {
                        w.writeName("valid_from").jsonValue(v)
        }
        if (let Some(v) <- this.valid_to) {
                        w.writeName("valid_to").jsonValue(v)
        }
        if (let Some(v) <- this.written_at) {
                        w.writeName("written_at").jsonValue(v)
        }
        if (let Some(v) <- this.invalidated_at) {
                        w.writeName("invalidated_at").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordTime {
        let res = MemoryRecordTime()
        fromJsonObjectWithExtras(
            r,
            [
                ("valid_from", { => res.valid_from = readRaw(r) }),
                ("valid_to", { => res.valid_to = readRaw(r) }),
                ("written_at", { => res.written_at = readRaw(r) }),
                ("invalidated_at", { => res.invalidated_at = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordFollows <: JsonSerializable & JsonDeserializable<MemoryRecordFollows> {
    public var kind: Option<String> = None
    public var id: Option<String> = None
    public var name: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.kind) {
                        w.writeName("kind").writeValue(v)
        }
        if (let Some(v) <- this.id) {
                        w.writeName("id").writeValue(v)
        }
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordFollows {
        let res = MemoryRecordFollows()
        fromJsonObjectWithExtras(
            r,
            [
                ("kind", { => res.kind = r.readValue<Option<String>>() }),
                ("id", { => res.id = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecord <: JsonSerializable & JsonDeserializable<MemoryRecord> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var memory_id: String = ""
    public var typeName: String = ""
    public var title: Option<String> = None
    public var content: Option<Array<MemoryContentPart>> = None
    public var attributes: Option<Raw> = None
    public var version: Option<Int64> = None
    public var status: Option<String> = None
    public var supersedes: Option<Raw> = None
    public var time: Option<MemoryRecordTime> = None
    public var written_by: Option<MemoryWriter> = None
    public var references: Option<Array<MemoryReference>> = None
    public var follows: Option<MemoryRecordFollows> = None
    public var trust: String = ""
    public var closed: Option<Array<String>> = None
    public var conflicts: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("memory_id").writeValue(this.memory_id)
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.title) {
                        w.writeName("title").writeValue(v)
        }
        if (let Some(v) <- this.content) {
                        w.writeName("content"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.attributes) {
                        w.writeName("attributes").jsonValue(v)
        }
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        if (let Some(v) <- this.status) {
                        w.writeName("status").writeValue(v)
        }
        if (let Some(v) <- this.supersedes) {
                        w.writeName("supersedes").jsonValue(v)
        }
        if (let Some(v) <- this.time) {
                        w.writeName("time"); v.toJson(w)
        }
        if (let Some(v) <- this.written_by) {
                        w.writeName("written_by"); v.toJson(w)
        }
        if (let Some(v) <- this.references) {
                        w.writeName("references"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.follows) {
                        w.writeName("follows"); v.toJson(w)
        }
                w.writeName("trust").writeValue(this.trust)
        if (let Some(v) <- this.closed) {
                        w.writeName("closed").writeValue(v)
        }
        if (let Some(v) <- this.conflicts) {
                        w.writeName("conflicts").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecord {
        let res = MemoryRecord()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("memory_id", { => res.memory_id = r.readValue<String>() }),
                ("type", { => res.typeName = r.readValue<String>() }),
                ("title", { => res.title = r.readValue<Option<String>>() }),
                ("content", { => res.content = r.readValue<Option<Array<MemoryContentPart>>>() }),
                ("attributes", { => res.attributes = readRaw(r) }),
                ("version", { => res.version = r.readValue<Option<Int64>>() }),
                ("status", { => res.status = r.readValue<Option<String>>() }),
                ("supersedes", { => res.supersedes = readRaw(r) }),
                ("time", { => res.time = r.readValue<Option<MemoryRecordTime>>() }),
                ("written_by", { => res.written_by = r.readValue<Option<MemoryWriter>>() }),
                ("references", { => res.references = r.readValue<Option<Array<MemoryReference>>>() }),
                ("follows", { => res.follows = r.readValue<Option<MemoryRecordFollows>>() }),
                ("trust", { => res.trust = r.readValue<String>() }),
                ("closed", { => res.closed = r.readValue<Option<Array<String>>>() }),
                ("conflicts", { => res.conflicts = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordCreate <: JsonSerializable & JsonDeserializable<MemoryRecordCreate> {
    public var typeName: Option<String> = None
    public var content: Raw = ""
    public var attributes: Option<Raw> = None
    public var references: Option<Array<MemoryReference>> = None
    public var time: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.typeName) {
                        w.writeName("type").writeValue(v)
        }
                w.writeName("content").jsonValue(this.content)
        if (let Some(v) <- this.attributes) {
                        w.writeName("attributes").jsonValue(v)
        }
        if (let Some(v) <- this.references) {
                        w.writeName("references"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.time) {
                        w.writeName("time").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordCreate {
        let res = MemoryRecordCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<Option<String>>() }),
                ("content", { => res.content = readRaw(r) }),
                ("attributes", { => res.attributes = readRaw(r) }),
                ("references", { => res.references = r.readValue<Option<Array<MemoryReference>>>() }),
                ("time", { => res.time = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordList <: JsonSerializable & JsonDeserializable<MemoryRecordList> {
    public var data: Option<Array<MemoryRecord>> = None
    public var next: Option<Raw> = None
    public var job: Option<MemoryJob> = None
    public var parent: Option<MemoryNeighbour> = None
    public var children: Option<Array<MemoryNeighbour>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.next) {
                        w.writeName("next").jsonValue(v)
        }
        if (let Some(v) <- this.job) {
                        w.writeName("job"); v.toJson(w)
        }
        if (let Some(v) <- this.parent) {
                        w.writeName("parent"); v.toJson(w)
        }
        if (let Some(v) <- this.children) {
                        w.writeName("children"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordList {
        let res = MemoryRecordList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryRecord>>>() }),
                ("next", { => res.next = readRaw(r) }),
                ("job", { => res.job = r.readValue<Option<MemoryJob>>() }),
                ("parent", { => res.parent = r.readValue<Option<MemoryNeighbour>>() }),
                ("children", { => res.children = r.readValue<Option<Array<MemoryNeighbour>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordRef <: JsonSerializable & JsonDeserializable<MemoryRecordRef> {
    public var memory_id: Option<String> = None
    public var record_id: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.memory_id) {
                        w.writeName("memory_id").writeValue(v)
        }
                w.writeName("record_id").writeValue(this.record_id)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordRef {
        let res = MemoryRecordRef()
        fromJsonObjectWithExtras(
            r,
            [
                ("memory_id", { => res.memory_id = r.readValue<Option<String>>() }),
                ("record_id", { => res.record_id = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryRecordRevise <: JsonSerializable & JsonDeserializable<MemoryRecordRevise> {
    public var content: Option<Raw> = None
    public var attributes: Option<Raw> = None
    public var references: Option<Array<MemoryReference>> = None
    public var time: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.content) {
                        w.writeName("content").jsonValue(v)
        }
        if (let Some(v) <- this.attributes) {
                        w.writeName("attributes").jsonValue(v)
        }
        if (let Some(v) <- this.references) {
                        w.writeName("references"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.time) {
                        w.writeName("time").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryRecordRevise {
        let res = MemoryRecordRevise()
        fromJsonObjectWithExtras(
            r,
            [
                ("content", { => res.content = readRaw(r) }),
                ("attributes", { => res.attributes = readRaw(r) }),
                ("references", { => res.references = r.readValue<Option<Array<MemoryReference>>>() }),
                ("time", { => res.time = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryReference <: JsonSerializable & JsonDeserializable<MemoryReference> {
    public var rel: Option<String> = None
    public var memory_id: Option<String> = None
    public var record_id: String = ""
    public var available: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.rel) {
                        w.writeName("rel").writeValue(v)
        }
        if (let Some(v) <- this.memory_id) {
                        w.writeName("memory_id").writeValue(v)
        }
                w.writeName("record_id").writeValue(this.record_id)
        if (let Some(v) <- this.available) {
                        w.writeName("available").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryReference {
        let res = MemoryReference()
        fromJsonObjectWithExtras(
            r,
            [
                ("rel", { => res.rel = r.readValue<Option<String>>() }),
                ("memory_id", { => res.memory_id = r.readValue<Option<String>>() }),
                ("record_id", { => res.record_id = r.readValue<String>() }),
                ("available", { => res.available = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemorySnapshot <: JsonSerializable & JsonDeserializable<MemorySnapshot> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var memory_id: Option<String> = None
    public var name: String = ""
    public var message: Option<String> = None
    public var at: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.memory_id) {
                        w.writeName("memory_id").writeValue(v)
        }
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.message) {
                        w.writeName("message").writeValue(v)
        }
                w.writeName("at").writeValue(this.at)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemorySnapshot {
        let res = MemorySnapshot()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("memory_id", { => res.memory_id = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("message", { => res.message = r.readValue<Option<String>>() }),
                ("at", { => res.at = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemorySnapshotCreate <: JsonSerializable & JsonDeserializable<MemorySnapshotCreate> {
    public var name: String = ""
    public var message: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.message) {
                        w.writeName("message").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemorySnapshotCreate {
        let res = MemorySnapshotCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("message", { => res.message = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemorySnapshotList <: JsonSerializable & JsonDeserializable<MemorySnapshotList> {
    public var data: Option<Array<MemorySnapshot>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemorySnapshotList {
        let res = MemorySnapshotList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemorySnapshot>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryTypeOperations <: JsonSerializable & JsonDeserializable<MemoryTypeOperations> {
    public var name: String = ""
    public var description: Option<String> = None
    public var input: Option<Raw> = None
    public var requires: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.input) {
                        w.writeName("input").jsonValue(v)
        }
                w.writeName("requires").writeValue(this.requires)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryTypeOperations {
        let res = MemoryTypeOperations()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("input", { => res.input = readRaw(r) }),
                ("requires", { => res.requires = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryType <: JsonSerializable & JsonDeserializable<MemoryType> {
    public var typeName: String = ""
    public var core: Option<Bool> = None
    public var description: Option<String> = None
    public var schema: Option<Raw> = None
    public var text: Option<String> = None
    public var operations: Option<Array<MemoryTypeOperations>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
        if (let Some(v) <- this.core) {
                        w.writeName("core").writeValue(v)
        }
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.schema) {
                        w.writeName("schema").jsonValue(v)
        }
        if (let Some(v) <- this.text) {
                        w.writeName("text").writeValue(v)
        }
        if (let Some(v) <- this.operations) {
                        w.writeName("operations"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryType {
        let res = MemoryType()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("core", { => res.core = r.readValue<Option<Bool>>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("schema", { => res.schema = readRaw(r) }),
                ("text", { => res.text = r.readValue<Option<String>>() }),
                ("operations", { => res.operations = r.readValue<Option<Array<MemoryTypeOperations>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryTypeList <: JsonSerializable & JsonDeserializable<MemoryTypeList> {
    public var data: Option<Array<MemoryType>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.data) {
                        w.writeName("data"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryTypeList {
        let res = MemoryTypeList()
        fromJsonObjectWithExtras(
            r,
            [
                ("data", { => res.data = r.readValue<Option<Array<MemoryType>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryUpdate <: JsonSerializable & JsonDeserializable<MemoryUpdate> {
    public var name: Option<String> = None
    public var description: Option<String> = None
    public var restricted: Option<Bool> = None
    public var parent_id: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.restricted) {
                        w.writeName("restricted").writeValue(v)
        }
        if (let Some(v) <- this.parent_id) {
                        w.writeName("parent_id").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryUpdate {
        let res = MemoryUpdate()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("restricted", { => res.restricted = r.readValue<Option<Bool>>() }),
                ("parent_id", { => res.parent_id = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class MemoryWriter <: JsonSerializable & JsonDeserializable<MemoryWriter> {
    public var kind: String = ""
    public var id: String = ""
    public var typeName: Option<String> = None
    public var on_behalf_of: Option<String> = None
    public var consolidation_id: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("kind").writeValue(this.kind)
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.typeName) {
                        w.writeName("type").writeValue(v)
        }
        if (let Some(v) <- this.on_behalf_of) {
                        w.writeName("on_behalf_of").writeValue(v)
        }
        if (let Some(v) <- this.consolidation_id) {
                        w.writeName("consolidation_id").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): MemoryWriter {
        let res = MemoryWriter()
        fromJsonObjectWithExtras(
            r,
            [
                ("kind", { => res.kind = r.readValue<String>() }),
                ("id", { => res.id = r.readValue<String>() }),
                ("type", { => res.typeName = r.readValue<Option<String>>() }),
                ("on_behalf_of", { => res.on_behalf_of = r.readValue<Option<String>>() }),
                ("consolidation_id", { => res.consolidation_id = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}
