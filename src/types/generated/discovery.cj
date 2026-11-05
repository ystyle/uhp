// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class DiscoveryImplementation <: JsonSerializable & JsonDeserializable<DiscoveryImplementation> {
    public var name: Option<String> = None
    public var version: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): DiscoveryImplementation {
        let res = DiscoveryImplementation()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("version", { => res.version = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Discovery <: JsonSerializable & JsonDeserializable<Discovery> {
    public var objectKind: String = ""
    public var protocol: String = ""
    public var versions: Array<String> = []
    public var default_version: String = ""
    public var conformance_class: String = ""
    public var capabilities: Capabilities = Capabilities()
    public var plugin_schemas: Option<Array<String>> = None
    public var implementation: Option<DiscoveryImplementation> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("object").writeValue(this.objectKind)
                w.writeName("protocol").writeValue(this.protocol)
                w.writeName("versions").writeValue(this.versions)
                w.writeName("default_version").writeValue(this.default_version)
                w.writeName("conformance_class").writeValue(this.conformance_class)
                w.writeName("capabilities"); this.capabilities.toJson(w)
        if (let Some(v) <- this.plugin_schemas) {
                        w.writeName("plugin_schemas").writeValue(v)
        }
        if (let Some(v) <- this.implementation) {
                        w.writeName("implementation"); v.toJson(w)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Discovery {
        let res = Discovery()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<String>() }),
                ("protocol", { => res.protocol = r.readValue<String>() }),
                ("versions", { => res.versions = r.readValue<Array<String>>() }),
                ("default_version", { => res.default_version = r.readValue<String>() }),
                ("conformance_class", { => res.conformance_class = r.readValue<String>() }),
                ("capabilities", { => res.capabilities = r.readValue<Capabilities>() }),
                ("plugin_schemas", { => res.plugin_schemas = r.readValue<Option<Array<String>>>() }),
                ("implementation", { => res.implementation = r.readValue<Option<DiscoveryImplementation>>() })
            ],
            res.extras
        )
        return res
    }
}
