// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class DeclaredPackage <: JsonSerializable & JsonDeserializable<DeclaredPackage> {
    public var spec: String = ""
    public var name: Option<String> = None
    public var version: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("spec").writeValue(this.spec)
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): DeclaredPackage {
        let res = DeclaredPackage()
        fromJsonObjectWithExtras(
            r,
            [
                ("spec", { => res.spec = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("version", { => res.version = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Deleted <: JsonSerializable & JsonDeserializable<Deleted> {
    public var id: Option<String> = None
    public var deleted: Option<Bool> = None
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
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Deleted {
        let res = Deleted()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<Option<String>>() }),
                ("deleted", { => res.deleted = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Event <: JsonSerializable & JsonDeserializable<Event> {
    public var typeName: String = ""
    public var sequence_number: Int64 = 0
    public var response: Option<Response> = None
    public var item: Option<OutputItem> = None
    public var part: Option<ContentPart> = None
    public var annotation: Option<Annotation> = None
    public var delta: Option<String> = None
    public var text: Option<String> = None
    public var arguments: Option<String> = None
    public var item_id: Option<String> = None
    public var output_index: Option<Int64> = None
    public var content_index: Option<Int64> = None
    public var summary_index: Option<Int64> = None
    public var annotation_index: Option<Int64> = None
    public var code: Option<String> = None
    public var message: Option<String> = None
    public var param: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("type").writeValue(this.typeName)
                w.writeName("sequence_number").writeValue(this.sequence_number)
        if (let Some(v) <- this.response) {
                        w.writeName("response"); v.toJson(w)
        }
        if (let Some(v) <- this.item) {
                        w.writeName("item"); v.toJson(w)
        }
        if (let Some(v) <- this.part) {
                        w.writeName("part"); v.toJson(w)
        }
        if (let Some(v) <- this.annotation) {
                        w.writeName("annotation"); v.toJson(w)
        }
        if (let Some(v) <- this.delta) {
                        w.writeName("delta").writeValue(v)
        }
        if (let Some(v) <- this.text) {
                        w.writeName("text").writeValue(v)
        }
        if (let Some(v) <- this.arguments) {
                        w.writeName("arguments").writeValue(v)
        }
        if (let Some(v) <- this.item_id) {
                        w.writeName("item_id").writeValue(v)
        }
        if (let Some(v) <- this.output_index) {
                        w.writeName("output_index").writeValue(v)
        }
        if (let Some(v) <- this.content_index) {
                        w.writeName("content_index").writeValue(v)
        }
        if (let Some(v) <- this.summary_index) {
                        w.writeName("summary_index").writeValue(v)
        }
        if (let Some(v) <- this.annotation_index) {
                        w.writeName("annotation_index").writeValue(v)
        }
        if (let Some(v) <- this.code) {
                        w.writeName("code").writeValue(v)
        }
        if (let Some(v) <- this.message) {
                        w.writeName("message").writeValue(v)
        }
        if (let Some(v) <- this.param) {
                        w.writeName("param").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Event {
        let res = Event()
        fromJsonObjectWithExtras(
            r,
            [
                ("type", { => res.typeName = r.readValue<String>() }),
                ("sequence_number", { => res.sequence_number = r.readValue<Int64>() }),
                ("response", { => res.response = r.readValue<Option<Response>>() }),
                ("item", { => res.item = r.readValue<Option<OutputItem>>() }),
                ("part", { => res.part = r.readValue<Option<ContentPart>>() }),
                ("annotation", { => res.annotation = r.readValue<Option<Annotation>>() }),
                ("delta", { => res.delta = r.readValue<Option<String>>() }),
                ("text", { => res.text = r.readValue<Option<String>>() }),
                ("arguments", { => res.arguments = r.readValue<Option<String>>() }),
                ("item_id", { => res.item_id = r.readValue<Option<String>>() }),
                ("output_index", { => res.output_index = r.readValue<Option<Int64>>() }),
                ("content_index", { => res.content_index = r.readValue<Option<Int64>>() }),
                ("summary_index", { => res.summary_index = r.readValue<Option<Int64>>() }),
                ("annotation_index", { => res.annotation_index = r.readValue<Option<Int64>>() }),
                ("code", { => res.code = r.readValue<Option<String>>() }),
                ("message", { => res.message = r.readValue<Option<String>>() }),
                ("param", { => res.param = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class FreeObject <: JsonSerializable & JsonDeserializable<FreeObject> {
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): FreeObject {
        let res = FreeObject()
        fromJsonObjectWithExtras(
            r,
            [

            ],
            res.extras
        )
        return res
    }
}
