// Agent Plugins 1.0.0 包解析与派生（Plugins 章）。
//
// 职责边界（设计 §8.2）：UHP **不定义包格式、也不执行插件**。本文件只做
// 「包 -> 派生态（manifest / mcpServers / skills / skipped）」这一层纯函数，
// 真正起 sandbox、跑 MCP、加载技能是 harness 的事。
//
// 关键契约：
//   * 派生字段**每次写入都从包重算**，绝不存客户端回传的派生值；
//   * 单个组件坏了 -> 进 skipped（可忽略，但必须可见）；manifest 坏了 -> 致命拒绝；
//   * 占位符 ${PLUGIN_ROOT}/${PLUGIN_DATA} 原样保留，不展开（那是服务端 sandbox 的路径）。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.codec.*

public let SUPPORTED_PLUGIN_SCHEMAS: Array<String> = [
    "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
]
public let SUPPORTED_MCP_SCHEMAS: Array<String> = [
    "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json"
]

// 一个包成员。保留原始 JSON（content 或 content_b64 的写法都要逐字节回写）。
public class PkgFile {
    public let path: String
    public let rawJson: String
    public let bytes: Array<UInt8>

    public init(path: String, rawJson: String, bytes: Array<UInt8>) {
        this.path = path
        this.rawJson = rawJson
        this.bytes = bytes
    }

    public func text(): String {
        return String.fromUtf8(this.bytes)
    }
}

public class PluginRecord {
    public let name: String
    public var enabled: Bool
    public let files: Array<PkgFile>

    public init(name: String, enabled: Bool, files: Array<PkgFile>) {
        this.name = name
        this.enabled = enabled
        this.files = files
    }

    public func file(path: String): Option<PkgFile> {
        for (f in this.files) {
            if (f.path == path) {
                return Some(f)
            }
        }
        return None
    }
}

public class DerivedPlugin {
    public var name: String = ""
    public let manifestJson: String
    public let mcpServersJson: String
    public let skillsJson: String
    public let skippedJson: String

    public init(name: String, manifestJson: String, mcpServersJson: String, skillsJson: String,
                skippedJson: String) {
        this.name = name
        this.manifestJson = manifestJson
        this.mcpServersJson = mcpServersJson
        this.skillsJson = skillsJson
        this.skippedJson = skippedJson
    }
}

// ---------- 包解析 ----------

public func parsePluginFiles(r: JsonReader): Array<PkgFile> {
    let out = ArrayList<PkgFile>()
    r.startArray()
    while (true) {
        match (r.peek()) {
            case Some(JsonToken.EndArray) => break
            case Some(JsonToken.BeginObject) =>
                out.add(parsePkgFile(r))
            case _ => r.skip()
        }
    }
    r.endArray()
    return out.toArray()
}

func parsePkgFile(r: JsonReader): PkgFile {
    var path = ""
    var raw = ""
    var bytes: Array<UInt8> = []
    let rawStart = r.readValueBytes()
    let rawJson = String.fromUtf8(rawStart)
    let rr = JsonReader(ByteBuffer(rawStart))
    rr.startObject()
    var base64: Option<String> = None
    var content: Option<String> = None
    while (true) {
        let name = match (rr.peek()) {
            case Some(JsonToken.EndObject) => break
            case Some(JsonToken.Name) => rr.readName()
            case _ => throw JsonProtocolException("bad file object")
        }
        match (name) {
            case "path" => path = rr.readValue<String>()
            case "content" => content = Some(rr.readValue<String>())
            case "content_b64" => base64 = Some(rr.readValue<String>())
            case _ => rr.skip()
        }
    }
    rr.endObject()
    checkSafePath(path)
    match (base64) {
        case Some(b) => bytes = decodeBase64(b)
        case None => match (content) {
            case Some(c) => bytes = c.toArray()
            case None => bytes = []
        }
    }
    return PkgFile(path, rawJson, bytes)
}

// 路径安全：绝对路径、.. 逃逸、空段、NUL 一律拒绝（词法归一化后再判）
func checkSafePath(path: String) {
    if (path.size == 0 || path.startsWith("/") || path.contains("\u{0}")) {
        throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
            reason: Some("path"))
    }
    for (seg in path.split("/")) {
        if (seg == ".." || seg == "." || seg.size == 0) {
            throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
                reason: Some("path"))
        }
    }
}

// ---------- 派生 ----------

public func derivePlugin(files: Array<PkgFile>, enabled: Bool): DerivedPlugin {
    let view = PkgView(files)
    // 1) manifest：缺失或不合法的 manifest 是致命的——没有它就没有「可以在其内部隔离失败」的插件
    let manifestFile = match (view.root("plugin.json")) {
        case Some(f) => f
        case None => throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
            reason: Some("plugin.json"))
    }
    let manifestBytes = manifestFile.bytes
    let manifestText = String.fromUtf8(manifestBytes)
    let manifest = parseJsonObject(manifestText)
    let schema = manifest.str("$schema")
    match (schema) {
        case Some(s) =>
            if (!SUPPORTED_PLUGIN_SCHEMAS.contains(s)) {
                throw EngineError("unsupported_plugin_schema", UInt16(422), param: Some("plugins"),
                    detailJson: Some("{\"supported\":[" + quoteJoin(SUPPORTED_PLUGIN_SCHEMAS) + "]}"))
            }
        case None =>
            throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
                reason: Some("plugin.json#$schema"))
    }
    let name = match (manifest.str("name")) {
        case Some(n) => n
        case None => throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
            reason: Some("plugin.json#name"))
    }
    if (!validPluginName(name)) {
        throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
            reason: Some("plugin.json#name"))
    }

    // 2) mcp.json -> mcpServers（单个条目坏了进 skipped，整份坏了全进 skipped）
    let skipped = ArrayList<(String, String)>()
    let servers = ArrayList<String>()
    match (view.root("mcp.json")) {
        case Some(f) => deriveMcpServers(String.fromUtf8(f.bytes), servers, skipped)
        case None => ()
    }

    // 3) skills/：只看**直接子目录**且含 SKILL.md 普通文件
    let skills = ArrayList<(String, String)>()
    let skillDirs = ArrayList<String>()
    for (f in files) {
        if (!f.path.startsWith("skills/")) {
            continue
        }
        let rest = f.path["skills/".size..f.path.size]
        let segs = rest.split("/")
        if (segs.size != 2 || segs[1] != "SKILL.md") {
            continue
        }
        if (skillDirs.contains(segs[0])) {
            continue
        }
        skillDirs.add(segs[0])
        match (skillFromDir(segs[0], String.fromUtf8(f.bytes))) {
            case Some(s) => skills.add(s)
            case None =>
                skipped.add(("skills/" + segs[0], "SKILL.md frontmatter name does not match directory"))
        }
    }

    return DerivedPlugin(
        name,
        manifestText,
        jsonArray(servers.toArray()),
        jsonSkills(skills.toArray()),
        jsonSkipped(skipped.toArray())
    )
}

class PkgView {
    private let files: Array<PkgFile>

    public init(files: Array<PkgFile>) {
        this.files = files
    }

    public func root(path: String): Option<PkgFile> {
        for (f in this.files) {
            if (f.path == path) {
                return Some(f)
            }
        }
        return None
    }
}

func skillFromDir(dir: String, skillMd: String): Option<(String, String)> {
    let fm = frontmatter(skillMd)
    let name = match (fm.get("name")) {
        case Some(n) => n
        case None => return None
    }
    if (name != dir) {
        return None
    }
    let desc = fm.get("description") ?? ""
    return Some((name, desc))
}

// 极简 frontmatter：取两条 --- 之间的 name/description
func frontmatter(md: String): HashMap<String, String> {
    let out = HashMap<String, String>()
    let lines = md.split("\n")
    var inFm = false
    var closed = false
    for (line in lines) {
        let l = line.trimAscii()
        if (!inFm && l == "---") {
            inFm = true
            continue
        }
        if (inFm && l == "---") {
            closed = true
            break
        }
        if (inFm) {
            let idx = match (l.indexOf(":")) {
                case Some(i) => i
                case None => continue
            }
            let k = l[0..idx].trimAscii()
            let v = l[idx + 1..l.size].trimAscii()
            out[k] = v
        }
    }
    return out
}

func deriveMcpServers(text: String, servers: ArrayList<String>, skipped: ArrayList<(String, String)>): Unit {
    let root = match (tryParseJsonObject(text)) {
        case Some(o) => o
        case None =>
            skipped.add(("mcp.json", "mcp.json is not a JSON object"))
            return
    }
    match (root.str("$schema")) {
        case Some(s) =>
            if (!SUPPORTED_MCP_SCHEMAS.contains(s)) {
                skipped.add(("mcp.json", "mcp.json targets an unsupported Agent Plugins version"))
                return
            }
        case None => ()
    }
    let serverMap = match (root.obj("mcpServers")) {
        case Some(m) => m
        case None =>
            skipped.add(("mcp.json", "mcp.json has no mcpServers object"))
            return
    }
    for ((name, entryJson) in serverMap.entries()) {
        match (mapServer(name, entryJson)) {
            case Some(js) => servers.add(js)
            case None => skipped.add(("mcp.json#/mcpServers/" + name, "unsupported or invalid MCP server entry"))
        }
    }
}

// mcp.json 条目 -> UHP McpServer：streamable-http -> http、sse 保持、stdio 带 command/args/env/cwd
func mapServer(name: String, entryJson: String): Option<String> {
    let o = match (tryParseJsonObject(entryJson)) {
        case Some(v) => v
        case None => return None
    }
    let typ = o.str("type") ?? ""
    let transport = match (typ) {
        case "streamable-http" => "http"
        case "sse" => "sse"
        case "stdio" => "stdio"
        case _ => return None
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("name").writeValue(name)
    w.writeName("transport").writeValue(transport)
    if (transport == "stdio") {
        let cmd = match (o.str("command")) {
            case Some(c) => c
            case None => return None
        }
        w.writeName("command").writeValue(cmd)
        match (o.raw("args")) {
            case Some(a) => w.writeName("args").jsonValue(a)
            case None => ()
        }
        match (o.raw("env")) {
            case Some(a) => w.writeName("env").jsonValue(a)
            case None => ()
        }
        match (o.raw("cwd")) {
            case Some(a) => w.writeName("cwd").jsonValue(a)
            case None => ()
        }
    } else {
        let url = match (o.str("url")) {
            case Some(u) => u
            case None => return None
        }
        w.writeName("url").writeValue(url)
        match (o.raw("headers")) {
            case Some(a) => w.writeName("headers").jsonValue(a)
            case None => ()
        }
    }
    w.writeName("enabled").writeValue(true)
    w.endObject()
    w.flush()
    return Some(String.fromUtf8(out.bytes()))
}

// ---------- JSON 小工具（够用即止，不做通用 DOM） ----------

public class JsonObj {
    private let pairs: HashMap<String, String>
    private let decoded: HashMap<String, String>

    public init(pairs: HashMap<String, String>, decoded: HashMap<String, String>) {
        this.pairs = pairs
        this.decoded = decoded
    }

    // 字符串成员（已解码）；不是字符串时返回 None
    public func str(key: String): Option<String> {
        return this.decoded.get(key)
    }

    // 原始 JSON 片段（嵌入结构用，逐字节保真）
    public func raw(key: String): Option<String> {
        return this.pairs.get(key)
    }

    public func obj(key: String): Option<JsonObj> {
        let rawValue = match (this.pairs.get(key)) {
            case Some(v) => v
            case None => return None
        }
        return tryParseJsonObject(rawValue)
    }

    public func entries(): Array<(String, String)> {
        let out = ArrayList<(String, String)>()
        for ((k, v) in this.pairs) {
            out.add((k, v))
        }
        return out.toArray()
    }
}

public func parseJsonObject(text: String): JsonObj {
    return match (tryParseJsonObject(text)) {
        case Some(o) => o
        case None => throw EngineError("plugin_invalid", UInt16(422), param: Some("plugins"),
            reason: Some("json"))
    }
}

// 抽出对象每个成员的原始 JSON 片段；字符串成员额外解出解码值（交给 JsonReader，不手写转义）
public func tryParseJsonObject(text: String): Option<JsonObj> {
    let pairs = HashMap<String, String>()
    let decoded = HashMap<String, String>()
    try {
        let r = JsonReader(ByteBuffer(text.toArray()))
        r.startObject()
        while (true) {
            let name = match (r.peek()) {
                case Some(JsonToken.EndObject) => break
                case Some(JsonToken.Name) => r.readName()
                case _ => return None
            }
            let rawBytes = r.readValueBytes()
            let raw = String.fromUtf8(rawBytes)
            pairs[name] = raw
            if (raw.size >= 2 && raw.toArray()[0] == UInt8(34)) {
                let sr = JsonReader(ByteBuffer(rawBytes))
                decoded[name] = sr.readValue<String>()
            }
        }
        r.endObject()
        return Some(JsonObj(pairs, decoded))
    } catch (e: Exception) {
        return None
    }
}

func jsonArray(items: Array<String>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    for (i in items) {
        w.jsonValue(i)
    }
    w.endArray()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func jsonSkills(items: Array<(String, String)>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    for ((name, desc) in items) {
        w.startObject()
        w.writeName("name").writeValue(name)
        w.writeName("description").writeValue(desc)
        w.endObject()
    }
    w.endArray()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func jsonSkipped(items: Array<(String, String)>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    for ((path, reason) in items) {
        w.startObject()
        w.writeName("path").writeValue(path)
        w.writeName("reason").writeValue(reason)
        w.endObject()
    }
    w.endArray()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func validPluginName(name: String): Bool {
    if (name.size == 0 || name.size > 64) {
        return false
    }
    let chars = name.toRuneArray()
    for (i in 0..chars.size) {
        let c = chars[i]
        let isLower = c >= r'a' && c <= r'z'
        let isDigit = c >= r'0' && c <= r'9'
        let ok = isLower || isDigit || c == r'-' || c == r'.'
        if (!ok) {
            return false
        }
    }
    return true
}

// ---------- base64 ----------

const B64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

public func decodeBase64(s: String): Array<UInt8> {
    let out = ArrayList<UInt8>()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (c in s.toRuneArray()) {
        let idx = B64.indexOf(String(c))
        if (let Some(i) <- idx) {
            buffer = (buffer << 6) | Int64(i)
            bits = bits + 6
            if (bits >= 8) {
                bits = bits - 8
                out.add(UInt8((buffer >> bits) & 0xFF))
            }
        }
    }
    return out.toArray()
}

public func encodeBase64(bytes: Array<UInt8>): String {
    let chars = B64.toRuneArray()
    let out = StringBuilder()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (b in bytes) {
        buffer = (buffer << 8) | Int64(b)
        bits = bits + 8
        while (bits >= 6) {
            bits = bits - 6
            out.append(chars[Int64((buffer >> bits) & 0x3F)])
        }
    }
    if (bits > 0) {
        out.append(chars[Int64((buffer << (6 - bits)) & 0x3F)])
    }
    return out.toString()
}
