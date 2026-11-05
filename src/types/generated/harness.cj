// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class Harness <: JsonSerializable & JsonDeserializable<Harness> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var name: String = ""
    public var base: String = ""
    public var baseLabel: Option<String> = None
    public var defaultModel: Option<String> = None
    public var systemPrompt: Option<String> = None
    public var mcpServers: Option<Array<McpServer>> = None
    public var skills: Option<Array<Skill>> = None
    public var plugins: Option<Array<Plugin>> = None
    public var environment: Option<String> = None
    public var disabledTools: Option<Array<String>> = None
    public var maxStep: Option<Raw> = None
    public var timeoutSeconds: Option<Raw> = None
    public var createdAt: Option<Int64> = None
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
                w.writeName("base").writeValue(this.base)
        if (let Some(v) <- this.baseLabel) {
                        w.writeName("baseLabel").writeValue(v)
        }
        if (let Some(v) <- this.defaultModel) {
                        w.writeName("defaultModel").writeValue(v)
        }
        if (let Some(v) <- this.systemPrompt) {
                        w.writeName("systemPrompt").writeValue(v)
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
        if (let Some(v) <- this.plugins) {
                        w.writeName("plugins"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.environment) {
                        w.writeName("environment").writeValue(v)
        }
        if (let Some(v) <- this.disabledTools) {
                        w.writeName("disabledTools").writeValue(v)
        }
        if (let Some(v) <- this.maxStep) {
                        w.writeName("maxStep").jsonValue(v)
        }
        if (let Some(v) <- this.timeoutSeconds) {
                        w.writeName("timeoutSeconds").jsonValue(v)
        }
        if (let Some(v) <- this.createdAt) {
                        w.writeName("createdAt").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Harness {
        let res = Harness()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("base", { => res.base = r.readValue<String>() }),
                ("baseLabel", { => res.baseLabel = r.readValue<Option<String>>() }),
                ("defaultModel", { => res.defaultModel = r.readValue<Option<String>>() }),
                ("systemPrompt", { => res.systemPrompt = r.readValue<Option<String>>() }),
                ("mcpServers", { => res.mcpServers = r.readValue<Option<Array<McpServer>>>() }),
                ("skills", { => res.skills = r.readValue<Option<Array<Skill>>>() }),
                ("plugins", { => res.plugins = r.readValue<Option<Array<Plugin>>>() }),
                ("environment", { => res.environment = r.readValue<Option<String>>() }),
                ("disabledTools", { => res.disabledTools = r.readValue<Option<Array<String>>>() }),
                ("maxStep", { => res.maxStep = readRaw(r) }),
                ("timeoutSeconds", { => res.timeoutSeconds = readRaw(r) }),
                ("createdAt", { => res.createdAt = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class HarnessCreate <: JsonSerializable & JsonDeserializable<HarnessCreate> {
    public var name: Option<String> = None
    public var base: String = ""
    public var default_model: Option<String> = None
    public var system_prompt: Option<String> = None
    public var mcp_servers: Option<Array<McpServer>> = None
    public var skills: Option<Array<Skill>> = None
    public var plugins: Option<Array<Plugin>> = None
    public var environment: Option<String> = None
    public var disabled_tools: Option<Array<String>> = None
    public var max_step: Option<Raw> = None
    public var timeout_seconds: Option<Raw> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
                w.writeName("base").writeValue(this.base)
        if (let Some(v) <- this.default_model) {
                        w.writeName("default_model").writeValue(v)
        }
        if (let Some(v) <- this.system_prompt) {
                        w.writeName("system_prompt").writeValue(v)
        }
        if (let Some(v) <- this.mcp_servers) {
                        w.writeName("mcp_servers"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.skills) {
                        w.writeName("skills"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.plugins) {
                        w.writeName("plugins"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.environment) {
                        w.writeName("environment").writeValue(v)
        }
        if (let Some(v) <- this.disabled_tools) {
                        w.writeName("disabled_tools").writeValue(v)
        }
        if (let Some(v) <- this.max_step) {
                        w.writeName("max_step").jsonValue(v)
        }
        if (let Some(v) <- this.timeout_seconds) {
                        w.writeName("timeout_seconds").jsonValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessCreate {
        let res = HarnessCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("base", { => res.base = r.readValue<String>() }),
                ("default_model", { => res.default_model = r.readValue<Option<String>>() }),
                ("system_prompt", { => res.system_prompt = r.readValue<Option<String>>() }),
                ("mcp_servers", { => res.mcp_servers = r.readValue<Option<Array<McpServer>>>() }),
                ("skills", { => res.skills = r.readValue<Option<Array<Skill>>>() }),
                ("plugins", { => res.plugins = r.readValue<Option<Array<Plugin>>>() }),
                ("environment", { => res.environment = r.readValue<Option<String>>() }),
                ("disabled_tools", { => res.disabled_tools = r.readValue<Option<Array<String>>>() }),
                ("max_step", { => res.max_step = readRaw(r) }),
                ("timeout_seconds", { => res.timeout_seconds = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class HarnessMemoriesData <: JsonSerializable & JsonDeserializable<HarnessMemoriesData> {
    public var id: String = ""
    public var name: Option<String> = None
    public var privileges: Array<String> = []
    public var default: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.name) {
                        w.writeName("name").writeValue(v)
        }
                w.writeName("privileges").writeValue(this.privileges)
        if (let Some(v) <- this.default) {
                        w.writeName("default").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessMemoriesData {
        let res = HarnessMemoriesData()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<Option<String>>() }),
                ("privileges", { => res.privileges = r.readValue<Array<String>>() }),
                ("default", { => res.default = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class HarnessMemories <: JsonSerializable & JsonDeserializable<HarnessMemories> {
    public var objectKind: Option<String> = None
    public var principal: String = ""
    public var default_memory_id: Option<Raw> = None
    public var observe: Option<Bool> = None
    public var data: Array<HarnessMemoriesData> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("principal").writeValue(this.principal)
        if (let Some(v) <- this.default_memory_id) {
                        w.writeName("default_memory_id").jsonValue(v)
        }
        if (let Some(v) <- this.observe) {
                        w.writeName("observe").writeValue(v)
        }
                w.writeName("data"); w.startArray();
        for (e in this.data) { e.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessMemories {
        let res = HarnessMemories()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("principal", { => res.principal = r.readValue<String>() }),
                ("default_memory_id", { => res.default_memory_id = readRaw(r) }),
                ("observe", { => res.observe = r.readValue<Option<Bool>>() }),
                ("data", { => res.data = r.readValue<Array<HarnessMemoriesData>>() })
            ],
            res.extras
        )
        return res
    }
}

public class HarnessMemorySettings <: JsonSerializable & JsonDeserializable<HarnessMemorySettings> {
    public var default_memory_id: Option<Raw> = None
    public var observe: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.default_memory_id) {
                        w.writeName("default_memory_id").jsonValue(v)
        }
        if (let Some(v) <- this.observe) {
                        w.writeName("observe").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessMemorySettings {
        let res = HarnessMemorySettings()
        fromJsonObjectWithExtras(
            r,
            [
                ("default_memory_id", { => res.default_memory_id = readRaw(r) }),
                ("observe", { => res.observe = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class HarnessModels <: JsonSerializable & JsonDeserializable<HarnessModels> {
    public var harness_id: Option<String> = None
    public var backend: Option<String> = None
    public var default: Option<String> = None
    public var fallback: Option<String> = None
    public var models: Array<Model> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.harness_id) {
                        w.writeName("harness_id").writeValue(v)
        }
        if (let Some(v) <- this.backend) {
                        w.writeName("backend").writeValue(v)
        }
        if (let Some(v) <- this.default) {
                        w.writeName("default").writeValue(v)
        }
        if (let Some(v) <- this.fallback) {
                        w.writeName("fallback").writeValue(v)
        }
                w.writeName("models"); w.startArray();
        for (e in this.models) { e.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): HarnessModels {
        let res = HarnessModels()
        fromJsonObjectWithExtras(
            r,
            [
                ("harness_id", { => res.harness_id = r.readValue<Option<String>>() }),
                ("backend", { => res.backend = r.readValue<Option<String>>() }),
                ("default", { => res.default = r.readValue<Option<String>>() }),
                ("fallback", { => res.fallback = r.readValue<Option<String>>() }),
                ("models", { => res.models = r.readValue<Array<Model>>() })
            ],
            res.extras
        )
        return res
    }
}

public class McpServer <: JsonSerializable & JsonDeserializable<McpServer> {
    public var name: String = ""
    public var url: String = ""
    public var transport: Option<String> = None
    public var enabled: Option<Bool> = None
    public var headers: Option<Raw> = None
    public var auth: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
                w.writeName("url").writeValue(this.url)
        if (let Some(v) <- this.transport) {
                        w.writeName("transport").writeValue(v)
        }
        if (let Some(v) <- this.enabled) {
                        w.writeName("enabled").writeValue(v)
        }
        if (let Some(v) <- this.headers) {
                        w.writeName("headers").jsonValue(v)
        }
        if (let Some(v) <- this.auth) {
                        w.writeName("auth").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): McpServer {
        let res = McpServer()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("url", { => res.url = r.readValue<String>() }),
                ("transport", { => res.transport = r.readValue<Option<String>>() }),
                ("enabled", { => res.enabled = r.readValue<Option<Bool>>() }),
                ("headers", { => res.headers = readRaw(r) }),
                ("auth", { => res.auth = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Model <: JsonSerializable & JsonDeserializable<Model> {
    public var id: String = ""
    public var label: Option<String> = None
    public var backend: Option<String> = None
    public var available: Bool = false
    public var default: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.label) {
                        w.writeName("label").writeValue(v)
        }
        if (let Some(v) <- this.backend) {
                        w.writeName("backend").writeValue(v)
        }
                w.writeName("available").writeValue(this.available)
        if (let Some(v) <- this.default) {
                        w.writeName("default").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Model {
        let res = Model()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("label", { => res.label = r.readValue<Option<String>>() }),
                ("backend", { => res.backend = r.readValue<Option<String>>() }),
                ("available", { => res.available = r.readValue<Bool>() }),
                ("default", { => res.default = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class ModelCatalog <: JsonSerializable & JsonDeserializable<ModelCatalog> {
    public var backends: Raw = ""
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("backends").jsonValue(this.backends)
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ModelCatalog {
        let res = ModelCatalog()
        fromJsonObjectWithExtras(
            r,
            [
                ("backends", { => res.backends = readRaw(r) })
            ],
            res.extras
        )
        return res
    }
}

public class Skill <: JsonSerializable & JsonDeserializable<Skill> {
    public var name: String = ""
    public var enabled: Option<Bool> = None
    public var files: Option<Array<SkillFile>> = None
    public var content: Option<String> = None
    public var blob: Option<String> = None
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
        if (let Some(v) <- this.content) {
                        w.writeName("content").writeValue(v)
        }
        if (let Some(v) <- this.blob) {
                        w.writeName("blob").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Skill {
        let res = Skill()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("enabled", { => res.enabled = r.readValue<Option<Bool>>() }),
                ("files", { => res.files = r.readValue<Option<Array<SkillFile>>>() }),
                ("content", { => res.content = r.readValue<Option<String>>() }),
                ("blob", { => res.blob = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class SkillFile <: JsonSerializable & JsonDeserializable<SkillFile> {
    public var path: String = ""
    public var content: Option<String> = None
    public var content_b64: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("path").writeValue(this.path)
        if (let Some(v) <- this.content) {
                        w.writeName("content").writeValue(v)
        }
        if (let Some(v) <- this.content_b64) {
                        w.writeName("content_b64").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): SkillFile {
        let res = SkillFile()
        fromJsonObjectWithExtras(
            r,
            [
                ("path", { => res.path = r.readValue<String>() }),
                ("content", { => res.content = r.readValue<Option<String>>() }),
                ("content_b64", { => res.content_b64 = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}
