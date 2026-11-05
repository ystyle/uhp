// 插件管理（Full + plugins）：写体解析、组合校验、渲染、导出。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.codec.*

public class PluginInput {
    // 客户端可能只回传 name/enabled（例如禁用），此时沿用已安装的包
    public var files: Option<Array<PkgFile>> = None
    public var enabled: Bool = true
    public var name: Option<String> = None
}

public func parsePluginInputs(r: JsonReader): Array<PluginInput> {
    let out = ArrayList<PluginInput>()
    r.startArray()
    while (true) {
        match (r.peek()) {
            case Some(JsonToken.EndArray) => break
            case Some(JsonToken.BeginObject) =>
                out.add(parsePluginInput(r))
            case _ => r.skip()
        }
    }
    r.endArray()
    return out.toArray()
}

func parsePluginInput(r: JsonReader): PluginInput {
    let pi = PluginInput()
    r.startObject()
    while (true) {
        let name = match (r.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => r.readName()
            case _ => throw JsonProtocolException("bad plugin object")
        }
        match (name) {
            case "files" => pi.files = Some(parsePluginFiles(r))
            case "enabled" => pi.enabled = r.readValue<Bool>()
            case "name" => pi.name = Some(r.readValue<String>())
            // 派生态字段由服务端重算，客户端回传的不可信
            case _ => r.skip()
        }
    }
    r.endObject()
    return pi
}

// 把写体里的插件列表落成存储形态：
//   * 带 files -> 重新派生并校验（配置期拒绝坏包）
//   * 只有 name/enabled -> 在已安装集合里按名匹配（PUT 往返/禁用的场景）
public func resolvePlugins(inputs: Array<PluginInput>, existing: Array<PluginRecord>): Array<PluginRecord> {
    let out = ArrayList<PluginRecord>()
    for (pi in inputs) {
        match (pi.files) {
            case Some(files) =>
                // 配置期校验：manifest 缺失/版本不支持/路径逃逸都在这里失败
                let derived = derivePlugin(files, pi.enabled)
                if (let Some(n) <- pi.name) {
                    if (n != derived.name) {
                        throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
                            reason: Some("plugin.json#name"))
                    }
                }
                out.add(PluginRecord(derived.name, pi.enabled, files))
            case None =>
                let want = match (pi.name) {
                    case Some(n) => n
                    case None => throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
                        reason: Some("plugins#files"))
                }
                var found = false
                for (old in existing) {
                    if (old.name == want) {
                        out.add(PluginRecord(old.name, pi.enabled, old.files))
                        found = true
                        break
                    }
                }
                if (!found) {
                    throw EngineError("plugin_not_found", UInt16(404), param: Some("plugins"))
                }
        }
    }
    return out.toArray()
}

// 直接配置里的 mcp server 名 / 技能名（组合校验的左侧）
public func directServerNames(rec: HarnessRecord): Array<String> {
    let out = ArrayList<String>()
    for ((name, _) in jsonStrings(rec.mcpServersJson ?? "[]", "name")) {
        out.add(name)
    }
    return out.toArray()
}

public func directSkillNames(rec: HarnessRecord): Array<String> {
    let out = ArrayList<String>()
    for (s in rec.skills) {
        out.add(s.name)
    }
    return out.toArray()
}

// 组合校验（Plugins §4.2）：agent 看到的是一个扁平命名空间，冲突必须在配置期拒绝。
// 只按「启用集合」判定：禁用的插件不参与。
public func checkComposition(directServers: Array<String>, directSkills: Array<String>,
                             plugins: Array<PluginRecord>): Unit {
    // 插件重名
    let seen = ArrayList<String>()
    for (p in plugins) {
        if (seen.contains(p.name)) {
            throw EngineError("plugin_conflict", UInt16(409), param: Some("plugins"),
                detailJson: Some(conflictDetail("plugin", p.name)))
        }
        seen.add(p.name)
    }
    let serverNames = ArrayList<String>(directServers)
    let skillNames = ArrayList<String>(directSkills)
    for (p in plugins) {
        if (!p.enabled) {
            continue
        }
        let derived = derivePlugin(p.files, p.enabled)
        for ((name, _) in jsonStrings(derived.mcpServersJson, "name")) {
            if (serverNames.contains(name)) {
                throw EngineError("plugin_conflict", UInt16(409), param: Some("plugins"),
                    detailJson: Some(conflictDetail("mcp_server", name)))
            }
            serverNames.add(name)
        }
        for ((name, _) in jsonStrings(derived.skillsJson, "name")) {
            if (skillNames.contains(name)) {
                throw EngineError("plugin_conflict", UInt16(409), param: Some("plugins"),
                    detailJson: Some(conflictDetail("skill", name)))
            }
            skillNames.add(name)
        }
    }
}

func conflictDetail(component: String, name: String): String {
    return "{\"component\":\"" + component + "\",\"name\":\"" + name + "\"}"
}

// 从一个 JSON 数组里取每项的某个字符串字段
public func jsonStrings(arrayJson: String, field: String): Array<(String, String)> {
    let out = ArrayList<(String, String)>()
    try {
        let r = JsonReader(ByteBuffer(arrayJson.toArray()))
        r.startArray()
        while (true) {
            match (r.peek()) {
                case Some(JsonToken.EndArray) => break
                case Some(JsonToken.BeginObject) =>
                    let raw = String.fromUtf8(r.readValueBytes())
                    match (tryParseJsonObject(raw)) {
                        case Some(o) => match (o.str(field)) {
                            case Some(v) => out.add((v, raw))
                            case None => ()
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

// 渲染插件数组：派生字段每次重算 + files 原样（PUT 往返靠它）
public func pluginsJson(plugins: Array<PluginRecord>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    for (p in plugins) {
        let d = derivePlugin(p.files, p.enabled)
        w.startObject()
        w.writeName("name").writeValue(d.name)
        w.writeName("object").writeValue("plugin")
        w.writeName("enabled").writeValue(p.enabled)
        w.writeName("manifest").jsonValue(d.manifestJson)
        w.writeName("mcpServers").jsonValue(d.mcpServersJson)
        w.writeName("skills").jsonValue(d.skillsJson)
        w.writeName("skipped").jsonValue(d.skippedJson)
        w.writeName("files")
        w.startArray()
        for (f in p.files) {
            w.jsonValue(f.rawJson)
        }
        w.endArray()
        w.endObject()
    }
    w.endArray()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func pluginFilesJson(p: PluginRecord): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("files")
    w.startArray()
    for (f in p.files) {
        w.jsonValue(f.rawJson)
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// ---------- 导出（P-06） ----------

public func deriveExportName(harnessName: String, harnessId: String): String {
    let lowered = harnessName.toAsciiLower()
    let out = StringBuilder()
    var lastDash = false
    for (c in lowered.toRuneArray()) {
        let keep = (c >= r'a' && c <= r'z') || (c >= r'0' && c <= r'9') || c == r'.'
        if (keep) {
            out.append(c)
            lastDash = false
        } else {
            if (!lastDash) {
                out.append(r'-')
                lastDash = true
            }
        }
    }
    var name = out.toString()
    // 收敛：连续点折叠成一个；去首尾的 - 和 .
    while (name.contains("..")) {
        name = name.replace("..", ".")
    }
    while (name.size > 0 && (name.startsWith("-") || name.startsWith("."))) {
        name = name[1..name.size]
    }
    while (name.size > 0 && (name.endsWith("-") || name.endsWith("."))) {
        name = name[0..name.size - 1]
    }
    if (name.size == 0) {
        return deriveExportName(harnessId, "uhp")
    }
    return name
}

// 把 harness 的直接配置导出成一个 Agent Plugins 包。
// 凭证（auth/headers）**必须省略**并记进 skipped：包会旅行，operator 的密钥不会。
public func exportPluginJson(rec: HarnessRecord): String {
    let name = deriveExportName(rec.name, rec.id)
    let files = ArrayList<String>()
    let skipped = ArrayList<(String, String)>()
    let exportedServers = ArrayList<String>()

    // plugin.json
    let manifestOut = ByteBuffer()
    let mw0 = JsonWriter(manifestOut)
    mw0.startObject()
    mw0.writeName("$schema").writeValue(SUPPORTED_PLUGIN_SCHEMAS[0])
    mw0.writeName("name").writeValue(name)
    mw0.endObject()
    mw0.flush()
    let manifestText = String.fromUtf8(manifestOut.bytes())
    files.add(pkgFileText("plugin.json", manifestText))

    // mcp.json：只含启用的直接服务器；http -> streamable-http，sse 保持；auth/headers 必须省略
    let mcpOut = ByteBuffer()
    let mw = JsonWriter(mcpOut)
    mw.startObject()
    mw.writeName("$schema").writeValue(SUPPORTED_MCP_SCHEMAS[0])
    mw.writeName("mcpServers")
    mw.startObject()
    var anyServer = false
    for ((sname, raw) in jsonStrings(rec.mcpServersJson ?? "[]", "name")) {
        let o = match (tryParseJsonObject(raw)) {
            case Some(v) => v
            case None => continue
        }
        let enabled = o.raw("enabled").map({ v => v == "true" }) ?? true
        if (!enabled) {
            continue
        }
        let transport = o.str("transport") ?? "http"
        let url = o.str("url") ?? ""
        let apType = if (transport == "sse") { "sse" } else { "streamable-http" }
        mw.writeName(sname)
        mw.startObject()
        mw.writeName("type").writeValue(apType)
        mw.writeName("url").writeValue(url)
        mw.endObject()
        anyServer = true
        // 导出对象里的 mcpServers 也只报导出后的形态（不带凭证）
        let eOut = ByteBuffer()
        let ew = JsonWriter(eOut)
        ew.startObject()
        ew.writeName("name").writeValue(sname)
        ew.writeName("transport").writeValue(transport)
        ew.writeName("url").writeValue(url)
        ew.writeName("enabled").writeValue(true)
        ew.endObject()
        ew.flush()
        exportedServers.add(String.fromUtf8(eOut.bytes()))
        if (o.raw("headers").isSome() || o.raw("auth").isSome()) {
            skipped.add(("mcp.json#/mcpServers/" + sname, "credentials omitted on export"))
        }
    }
    mw.endObject()
    mw.endObject()
    mw.flush()
    if (anyServer) {
        files.add(pkgFileText("mcp.json", String.fromUtf8(mcpOut.bytes())))
    }

    // skills/<name>/...：直接配置的技能按原样整体导出（保留 content / content_b64 写法）
    for (sk in rec.skills) {
        if (!sk.enabled) {
            continue
        }
        match (sk.filesJson) {
            case Some(rawArr) =>
                for (objRaw in splitFileObjects(rawArr)) {
                    match (copySkillFile(sk.name, objRaw)) {
                        case Some(f) => files.add(f)
                        case None => ()
                    }
                }
            case None => ()
        }
    }

    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("plugin")
    w.writeName("name").writeValue(name)
    w.writeName("enabled").writeValue(true)
    w.writeName("manifest").jsonValue(manifestText)
    w.writeName("mcpServers")
    w.startArray()
    for (srv in exportedServers) {
        w.jsonValue(srv)
    }
    w.endArray()
    w.writeName("skills")
    w.startArray()
    for (sk in rec.skills) {
        if (!sk.enabled) {
            continue
        }
        w.startObject()
        w.writeName("name").writeValue(sk.name)
        w.endObject()
    }
    w.endArray()
    w.writeName("skipped").jsonValue(jsonSkipped(skipped.toArray()))
    w.writeName("files")
    w.startArray()
    for (f in files.toArray()) {
        w.jsonValue(f)
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 生成一个包成员对象：{path, content: text}
func pkgFileText(path: String, text: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("path").writeValue(path)
    w.writeName("content").writeValue(text)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 复制一个技能成员到导出包的 skills/<name>/<rel>
func copySkillFile(skillName: String, objRaw: String): Option<String> {
    let o = match (tryParseJsonObject(objRaw)) {
        case Some(v) => v
        case None => return None
    }
    let rel = match (o.str("path")) {
        case Some(p) => p
        case None => return None
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("path").writeValue("skills/" + skillName + "/" + rel)
    match (o.raw("content_b64")) {
        case Some(b64) =>
            w.writeName("content_b64").jsonValue(b64)
        case None => match (o.raw("content")) {
            case Some(c) => w.writeName("content").jsonValue(c)
            case None => ()
        }
    }
    w.endObject()
    w.flush()
    return Some(String.fromUtf8(out.bytes()))
}

func fileJson(path: String, body: String): String {
    return "{\"path\":\"" + path + "\"," + body + "}"
}

func mcpServersOf(rec: HarnessRecord): String {
    // 导出对象里的 mcpServers 用派生视图里同形（只含启用项）
    let out = ArrayList<String>()
    for ((sname, raw) in jsonStrings(rec.mcpServersJson ?? "[]", "name")) {
        let o = match (tryParseJsonObject(raw)) {
            case Some(v) => v
            case None => continue
        }
        let enabled = o.raw("enabled").map({ v => v == "true" }) ?? true
        if (!enabled) {
            continue
        }
        out.add(raw)
    }
    return jsonArray(out.toArray())
}

// 把 skills[].files 原始数组里的对象逐个切出来（保留原文）
func splitFileObjects(arrayJson: String): Array<String> {
    let out = ArrayList<String>()
    try {
        let r = JsonReader(ByteBuffer(arrayJson.toArray()))
        r.startArray()
        while (true) {
            match (r.peek()) {
                case Some(JsonToken.EndArray) => break
                case Some(JsonToken.BeginObject) =>
                    out.add(String.fromUtf8(r.readValueBytes()))
                case _ => r.skip()
            }
        }
        r.endArray()
    } catch (e: Exception) {
        ()
    }
    return out.toArray()
}
