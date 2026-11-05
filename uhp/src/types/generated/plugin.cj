// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class Plugin <: JsonSerializable & JsonDeserializable<Plugin> {
    public var name: String = ""
    public var enabled: Option<Bool> = None
    public var files: Option<Array<SkillFile>> = None
    public var blob: Option<String> = None
    public var manifest: Option<PluginManifest> = None
    public var mcpServers: Option<Array<PluginMcpServer>> = None
    public var skills: Option<Array<PluginSkill>> = None
    public var skipped: Option<Array<PluginSkipped>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.enabled) {
                        w.writeName("enabled").writeValue(v)
        }
        if (let Some(v) <- this.files) {
                        w.writeName("files"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.blob) {
                        w.writeName("blob").writeValue(v)
        }
        if (let Some(v) <- this.manifest) {
                        w.writeName("manifest"); v.toJson(w)
        }
        if (let Some(v) <- this.mcpServers) {
                        w.writeName("mcpServers"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.skills) {
                        w.writeName("skills"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.skipped) {
                        w.writeName("skipped"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Plugin {
        let res = Plugin()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("enabled", { => res.enabled = r.readValue<Option<Bool>>() }),
                ("files", { => res.files = r.readValue<Option<Array<SkillFile>>>() }),
                ("blob", { => res.blob = r.readValue<Option<String>>() }),
                ("manifest", { => res.manifest = r.readValue<Option<PluginManifest>>() }),
                ("mcpServers", { => res.mcpServers = r.readValue<Option<Array<PluginMcpServer>>>() }),
                ("skills", { => res.skills = r.readValue<Option<Array<PluginSkill>>>() }),
                ("skipped", { => res.skipped = r.readValue<Option<Array<PluginSkipped>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class PluginManifestAuthor <: JsonSerializable & JsonDeserializable<PluginManifestAuthor> {
    public var name: Option<String> = None
    public var email: Option<String> = None
    public var url: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
        if (let Some(v) <- this.email) {
                        w.writeName("email").writeValue(v)
        }
        if (let Some(v) <- this.url) {
                        w.writeName("url").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PluginManifestAuthor {
        let res = PluginManifestAuthor()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("email", { => res.email = r.readValue<Option<String>>() }),
                ("url", { => res.url = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class PluginManifest <: JsonSerializable & JsonDeserializable<PluginManifest> {
    public var schemaUrl: String = ""
    public var name: String = ""
    public var version: Option<String> = None
    public var description: Option<String> = None
    public var author: Option<PluginManifestAuthor> = None
    public var homepage: Option<String> = None
    public var repository: Option<String> = None
    public var license: Option<String> = None
    public var keywords: Option<Array<String>> = None
    public var extensions: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("$schema").writeValue(this.schemaUrl)
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.author) {
                        w.writeName("author"); v.toJson(w)
        }
        if (let Some(v) <- this.homepage) {
                        w.writeName("homepage").writeValue(v)
        }
        if (let Some(v) <- this.repository) {
                        w.writeName("repository").writeValue(v)
        }
        if (let Some(v) <- this.license) {
                        w.writeName("license").writeValue(v)
        }
        if (let Some(v) <- this.keywords) {
                        w.writeName("keywords").writeValue(v)
        }
        if (let Some(v) <- this.extensions) {
                        w.writeName("extensions").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PluginManifest {
        let res = PluginManifest()
        fromJsonObjectWithExtras(
            r,
            [
                ("$schema", { => res.schemaUrl = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("version", { => res.version = r.readValue<Option<String>>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("author", { => res.author = r.readValue<Option<PluginManifestAuthor>>() }),
                ("homepage", { => res.homepage = r.readValue<Option<String>>() }),
                ("repository", { => res.repository = r.readValue<Option<String>>() }),
                ("license", { => res.license = r.readValue<Option<String>>() }),
                ("keywords", { => res.keywords = r.readValue<Option<Array<String>>>() }),
                ("extensions", { => res.extensions = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class PluginMcpServer <: JsonSerializable & JsonDeserializable<PluginMcpServer> {
    public var name: String = ""
    public var transport: Option<String> = None
    public var url: Option<String> = None
    public var headers: Option<Raw> = None
    public var command: Option<String> = None
    public var args: Option<Array<String>> = None
    public var env: Option<Raw> = None
    public var cwd: Option<String> = None
    public var enabled: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.transport) {
                        w.writeName("transport").writeValue(v)
        }
        if (let Some(v) <- this.url) {
                        w.writeName("url").writeValue(v)
        }
        if (let Some(v) <- this.headers) {
                        w.writeName("headers").jsonValue(v)
        }
        if (let Some(v) <- this.command) {
                        w.writeName("command").writeValue(v)
        }
        if (let Some(v) <- this.args) {
                        w.writeName("args").writeValue(v)
        }
        if (let Some(v) <- this.env) {
                        w.writeName("env").jsonValue(v)
        }
        if (let Some(v) <- this.cwd) {
                        w.writeName("cwd").writeValue(v)
        }
        if (let Some(v) <- this.enabled) {
                        w.writeName("enabled").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PluginMcpServer {
        let res = PluginMcpServer()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("transport", { => res.transport = r.readValue<Option<String>>() }),
                ("url", { => res.url = r.readValue<Option<String>>() }),
                ("headers", { => res.headers = readRaw(r) }),
                ("command", { => res.command = r.readValue<Option<String>>() }),
                ("args", { => res.args = r.readValue<Option<Array<String>>>() }),
                ("env", { => res.env = readRaw(r) }),
                ("cwd", { => res.cwd = r.readValue<Option<String>>() }),
                ("enabled", { => res.enabled = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class PluginSkill <: JsonSerializable & JsonDeserializable<PluginSkill> {
    public var name: String = ""
    public var description: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PluginSkill {
        let res = PluginSkill()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class PluginSkipped <: JsonSerializable & JsonDeserializable<PluginSkipped> {
    public var path: String = ""
    public var reason: String = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("path").writeValue(this.path)
                w.writeName("reason").writeValue(this.reason)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PluginSkipped {
        let res = PluginSkipped()
        fromJsonObjectWithExtras(
            r,
            [
                ("path", { => res.path = r.readValue<String>() }),
                ("reason", { => res.reason = r.readValue<String>() })
            ],
            res.extras
        )
        return res
    }
}
