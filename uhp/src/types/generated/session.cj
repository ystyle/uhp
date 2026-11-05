// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class File <: JsonSerializable & JsonDeserializable<File> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var container_id: Option<String> = None
    public var filename: String = ""
    public var bytes: Option<Int64> = None
    public var created_at: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.container_id) {
                        w.writeName("container_id").writeValue(v)
        }
                w.writeName("filename").writeValue(this.filename)
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        if (let Some(v) <- this.created_at) {
                        w.writeName("created_at").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): File {
        let res = File()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("container_id", { => res.container_id = r.readValue<Option<String>>() }),
                ("filename", { => res.filename = r.readValue<String>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() }),
                ("created_at", { => res.created_at = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class FileList <: JsonSerializable & JsonDeserializable<FileList> {
    public var files: Array<SkillFile> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("files"); w.startArray();
        for (e in this.files) { e.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): FileList {
        let res = FileList()
        fromJsonObjectWithExtras(
            r,
            [
                ("files", { => res.files = r.readValue<Array<SkillFile>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Session <: JsonSerializable & JsonDeserializable<Session> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var harness_id: Option<String> = None
    public var environment: Option<String> = None
    public var title: Option<String> = None
    public var status: Option<String> = None
    public var created_at: Option<Int64> = None
    public var updated_at: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.harness_id) {
                        w.writeName("harness_id").writeValue(v)
        }
        if (let Some(v) <- this.environment) {
                        w.writeName("environment").writeValue(v)
        }
        if (let Some(v) <- this.title) {
                        w.writeName("title").writeValue(v)
        }
        if (let Some(v) <- this.status) {
                        w.writeName("status").writeValue(v)
        }
        if (let Some(v) <- this.created_at) {
                        w.writeName("created_at").writeValue(v)
        }
        if (let Some(v) <- this.updated_at) {
                        w.writeName("updated_at").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Session {
        let res = Session()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("harness_id", { => res.harness_id = r.readValue<Option<String>>() }),
                ("environment", { => res.environment = r.readValue<Option<String>>() }),
                ("title", { => res.title = r.readValue<Option<String>>() }),
                ("status", { => res.status = r.readValue<Option<String>>() }),
                ("created_at", { => res.created_at = r.readValue<Option<Int64>>() }),
                ("updated_at", { => res.updated_at = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class SessionList <: JsonSerializable & JsonDeserializable<SessionList> {
    public var sessions: Array<Session> = []
    public var next_cursor: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("sessions"); w.startArray();
        for (e in this.sessions) { e.toJson(w) }
        w.endArray()
        if (let Some(v) <- this.next_cursor) {
                        w.writeName("next_cursor").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionList {
        let res = SessionList()
        fromJsonObjectWithExtras(
            r,
            [
                ("sessions", { => res.sessions = r.readValue<Array<Session>>() }),
                ("next_cursor", { => res.next_cursor = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class SessionShare <: JsonSerializable & JsonDeserializable<SessionShare> {
    public var id: String = ""
    public var url: String = ""
    public var objectKind: Option<String> = None
    public var enabled: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
                w.writeName("url").writeValue(this.url)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
        if (let Some(v) <- this.enabled) {
                        w.writeName("enabled").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SessionShare {
        let res = SessionShare()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("url", { => res.url = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("enabled", { => res.enabled = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class TurnItem <: JsonSerializable & JsonDeserializable<TurnItem> {
    public var id: String = ""
    public var status: String = ""
    public var user: Option<String> = None
    public var assistant: Option<String> = None
    public var tools: Option<Array<Raw>> = None
    public var files: Option<Array<Raw>> = None
    public var imported: Option<Bool> = None
    public var created_at: Option<Int64> = None
    public var completed_at: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.user) {
                        w.writeName("user").writeValue(v)
        }
        if (let Some(v) <- this.assistant) {
                        w.writeName("assistant").writeValue(v)
        }
        if (let Some(v) <- this.tools) {
                        w.writeName("tools").writeValue(v)
        }
        if (let Some(v) <- this.files) {
                        w.writeName("files").writeValue(v)
        }
        if (let Some(v) <- this.imported) {
                        w.writeName("imported").writeValue(v)
        }
        if (let Some(v) <- this.created_at) {
                        w.writeName("created_at").writeValue(v)
        }
        if (let Some(v) <- this.completed_at) {
                        w.writeName("completed_at").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): TurnItem {
        let res = TurnItem()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("user", { => res.user = r.readValue<Option<String>>() }),
                ("assistant", { => res.assistant = r.readValue<Option<String>>() }),
                ("tools", { => res.tools = r.readValue<Option<Array<Raw>>>() }),
                ("files", { => res.files = r.readValue<Option<Array<Raw>>>() }),
                ("imported", { => res.imported = r.readValue<Option<Bool>>() }),
                ("created_at", { => res.created_at = r.readValue<Option<Int64>>() }),
                ("completed_at", { => res.completed_at = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}
