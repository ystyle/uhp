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
