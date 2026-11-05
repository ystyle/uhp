// harness 管理（Full 类）：创建 / 更新 / 删除 / 技能文件列取。
//
// 取舍：配置里 mcpServers 与 skills[].files 是「开放形状」，用**原始 JSON 文本**保存并原样回写，
// 这样未知字段与二进制成员（content_b64）都能逐字节 round-trip（F-03/F-04/F-06 检查的正是这个）。
package uhp.server

import std.collection.{ArrayList, HashMap}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import std.io.*

public class SkillRecord {
    public var name: String = ""
    public var enabled: Bool = true
    // files 数组的原始 JSON；不含 files 时为 None（也可能用 content 简写）
    public var filesJson: Option<String> = None
}

public class HarnessRecord {
    public let id: String
    public var name: String
    public var base: String
    public var defaultModel: Option<String> = None
    public var systemPrompt: Option<String> = None
    public var mcpServersJson: Option<String> = None
    public var skills: Array<SkillRecord> = []
    public var disabledTools: Array<String> = []
    // 插件：包原样保存，派生态每次读时重算
    public var plugins: Array<PluginRecord> = []
    // 指向的环境 id（Environments §5）：创建时必须是存在的环境
    public var environment: Option<String> = None
    // 写体里的插件输入（create/update 时由 engine 解析成 PluginRecord）
    public var pluginInputs: Array<PluginInput> = []
    public var maxStep: Option<Int64> = None
    public var timeoutSeconds: Option<Int64> = None
    public let createdAt: Int64

    public init(id: String, name: String, base: String) {
        this.id = id
        this.name = name
        this.base = base
        this.createdAt = nowSeconds()
    }

    public func skill(name: String): Option<SkillRecord> {
        for (s in this.skills) {
            if (s.name == name) {
                return Some(s)
            }
        }
        return None
    }
}

// 解析 HarnessCreate 写体（snake_case），并做配置期校验。
// 返回 (record, 未知字段名列表)：未知字段按规范拒绝（422），但由调用方决定怎么报。
public func parseHarnessCreate(r: JsonReader, id: String): HarnessRecord {
    var base = ""
    let rec = HarnessRecord(id, "", base)
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ => throw JsonProtocolException("bad json")
        }
        match (name) {
            case "name" => rec.name = r.readValue<String>()
            case "base" => rec.base = r.readValue<String>()
            case "default_model" => rec.defaultModel = Some(r.readValue<String>())
            case "system_prompt" => rec.systemPrompt = Some(r.readValue<String>())
            case "mcp_servers" => rec.mcpServersJson = Some(String.fromUtf8(r.readValueBytes()))
            case "skills" => rec.skills = parseSkills(r)
            case "disabled_tools" => rec.disabledTools = r.readValue<Array<String>>()
            case "environment" => rec.environment = Some(r.readValue<String>())
            case "plugins" => rec.pluginInputs = parsePluginInputs(r)
            case "max_step" => rec.maxStep = Some(r.readValue<Int64>())
            case "timeout_seconds" => rec.timeoutSeconds = Some(r.readValue<Int64>())
            // 只读字段：接受并忽略（否则 GET -> PUT 存不回去）
            case "id" => r.skip()
            case "object" => r.skip()
            case "baseLabel" => r.skip()
            case "createdAt" => r.skip()
            case unknown => throw EngineError("invalid_input", UInt16(422), reason: Some(unknown))
        }
    }
    r.endObject()
    return rec
}

func parseSkills(r: JsonReader): Array<SkillRecord> {
    let out = ArrayList<SkillRecord>()
    r.startArray()
    while (true) {
        match (r.peek()) {
            case Some(JsonToken.EndArray) => break
            case Some(JsonToken.BeginObject) =>
                out.add(parseSkill(r))
            case _ => r.skip()
        }
    }
    r.endArray()
    return out.toArray()
}

func parseSkill(r: JsonReader): SkillRecord {
    let s = SkillRecord()
    var hasSkillManifest = false
    var hasContent = false
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ => throw JsonProtocolException("bad json")
        }
        match (name) {
            case "name" => s.name = r.readValue<String>()
            case "enabled" => s.enabled = r.readValue<Bool>()
            case "files" =>
                let raw = String.fromUtf8(r.readValueBytes())
                s.filesJson = Some(raw)
                if (raw.contains("\"SKILL.md\"")) {
                    hasSkillManifest = true
                }
            case "content" =>
                // 单文件简写：内容就是 SKILL.md
                let _ = r.readValue<String>()
                hasContent = true
                hasSkillManifest = true
            case _ => r.skip()
        }
    }
    r.endObject()
    // 配置期拒绝：没有 SKILL.md 的 bundle 存下来只会在运行期被静默忽略（最难查的失败）
    if (!hasSkillManifest && !hasContent) {
        throw EngineError("invalid_input", UInt16(422), reason: Some("SKILL.md"))
    }
    return s
}

// 渲染 Harness 对象（camelCase）。开放形状原样回写。
public func harnessJson(rec: HarnessRecord, baseLabel: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue(rec.id)
    w.writeName("object").writeValue("harness")
    w.writeName("name").writeValue(rec.name)
    w.writeName("base").writeValue(rec.base)
    w.writeName("baseLabel").writeValue(baseLabel)
    match (rec.defaultModel) {
        case Some(v) => w.writeName("defaultModel").writeValue(v)
        case None => ()
    }
    match (rec.systemPrompt) {
        case Some(v) => w.writeName("systemPrompt").writeValue(v)
        case None => ()
    }
    match (rec.mcpServersJson) {
        case Some(v) =>
            w.writeName("mcpServers")
            w.jsonValue(v)
        case None => w.writeName("mcpServers").jsonValue("[]")
    }
    // skills：数组元素含 name/enabled/files（files 原始 JSON）
    w.writeName("skills")
    w.startArray()
    for (s in rec.skills) {
        w.startObject()
        w.writeName("name").writeValue(s.name)
        w.writeName("enabled").writeValue(s.enabled)
        match (s.filesJson) {
            case Some(v) =>
                w.writeName("files")
                w.jsonValue(v)
            case None => ()
        }
        w.endObject()
    }
    w.endArray()
    w.writeName("disabledTools")
    w.startArray()
    for (t in rec.disabledTools) {
        w.writeValue(t)
    }
    w.endArray()
    w.writeName("plugins")
    w.jsonValue(pluginsJson(rec.plugins))
    // schema 里 environment 是 string：没有就不写（写 null 会违反类型）
    match (rec.environment) {
        case Some(eid) => w.writeName("environment").writeValue(eid)
        case None => ()
    }
    match (rec.maxStep) {
        case Some(v) => w.writeName("maxStep").writeValue(v)
        case None => w.writeName("maxStep").writeNullValue()
    }
    match (rec.timeoutSeconds) {
        case Some(v) => w.writeName("timeoutSeconds").writeValue(v)
        case None => w.writeName("timeoutSeconds").writeNullValue()
    }
    w.writeName("createdAt").writeValue(rec.createdAt)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 技能文件清单：{"files":[ ... ]}
public func skillFilesJson(s: SkillRecord): String {
    let files = match (s.filesJson) {
        case Some(v) => v
        case None => "[]"
    }
    return "{\"files\":" + files + "}"
}
