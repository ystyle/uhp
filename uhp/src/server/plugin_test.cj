// L2 测试：Agent Plugins 包派生（纯函数，不依赖网络）。
package uhp.server

import std.collection.*
import std.io.*
import std.fs.*
import stdx.encoding.json.stream.*
import std.unittest.*
import std.unittest.testmacro.*

func pkgFile(path: String, content: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("path").writeValue(path)
    w.writeName("content").writeValue(content)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func pluginFiles(files: Array<String>): Array<PkgFile> {
    var json = "["
    var first = true
    for (f in files) {
        if (!first) {
            json = json + ","
        }
        first = false
        json = json + f
    }
    json = json + "]"
    let r = JsonReader(ByteBuffer(json.toArray()))
    return parsePluginFiles(r)
}

const MANIFEST: String = "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"demo-plugin\"}"

@Test
func plugin_derives_manifest_servers_and_skills(): Unit {
    let mcp = "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/mcp.schema.json\",\"mcpServers\":{\"srv\":{\"type\":\"streamable-http\",\"url\":\"http://x/mcp\"},\"cli\":{\"type\":\"stdio\",\"command\":\"./bin/tool\",\"args\":[\"\${PLUGIN_DATA}\"]}}}"
    let files = pluginFiles([
        pkgFile("plugin.json", MANIFEST),
        pkgFile("mcp.json", mcp),
        pkgFile("skills/demo/SKILL.md", "---\nname: demo\ndescription: d\n---\n")
    ])
    let d = derivePlugin(files, true)
    @Expect(d.name, "demo-plugin")
    let servers = jsonStrings(d.mcpServersJson, "name")
    @Expect(servers.size, 2)
    let skills = jsonStrings(d.skillsJson, "name")
    @Expect(skills.size, 1)
    @Expect(d.skippedJson, "[]")
}

@Test
func plugin_without_manifest_is_refused(): Unit {
    var code = ""
    try {
        let _ = derivePlugin(pluginFiles([pkgFile("mcp.json", "{}")]), true)
    } catch (e: EngineError) {
        code = e.code
    }
    @Expect(code, "plugin_invalid")
}

@Test
func plugin_with_unknown_schema_is_refused(): Unit {
    var code = ""
    try {
        let man = "{\"$schema\":\"https://agent-plugins.org/schemas/0.0.1/plugin.schema.json\",\"name\":\"demo-plugin\"}"
        let _ = derivePlugin(pluginFiles([pkgFile("plugin.json", man)]), true)
    } catch (e: EngineError) {
        code = e.code
    }
    @Expect(code, "unsupported_plugin_schema")
}

@Test
func plugin_path_traversal_is_refused(): Unit {
    var code = ""
    try {
        let _ = pluginFiles([pkgFile("../escape.txt", "x")])
    } catch (e: EngineError) {
        code = e.code
    }
    @Expect(code, "plugin_invalid")
}

@Test
func plugin_invalid_server_is_skipped_with_reason(): Unit {
    let mcp = "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/mcp.schema.json\",\"mcpServers\":{\"broken\":{\"type\":\"carrier-pigeon\",\"url\":\"http://x\"}}}"
    let d = derivePlugin(pluginFiles([pkgFile("plugin.json", MANIFEST), pkgFile("mcp.json", mcp)]), true)
    @Expect(jsonStrings(d.mcpServersJson, "name").size, 0)
    @Expect(d.skippedJson.contains("broken"), true)
    @Expect(d.skippedJson.contains("reason"), true)
}

@Test
func plugin_binary_member_round_trips(): Unit {
    let b64 = "{\"path\":\"assets/blob.bin\",\"content_b64\":\"AAECAwQF\"}"
    let files = pluginFiles([pkgFile("plugin.json", MANIFEST), b64])
    @Expect(files.size, 2)
    @Expect(files[1].rawJson.contains("AAECAwQF"), true)
    @Expect(files[1].bytes.size, 6)
}

