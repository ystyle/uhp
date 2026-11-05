// 环境（Environments 章）：项目级文件 + 依赖，build 一次、所有会话只读挂载。
//
// 存储：每个环境一个真实目录（mount），文件写到盘上——这样 driver 能像 agent 一样在 mount 下读文件；
// build 之后把目录置为只读（chmod a-w），让「只读挂载」是真的只读，而不是文档里的一句承诺。
package uhp.server

import std.collection.{ArrayList, HashMap}
import std.fs.*
import std.fs.{File as FsFile}
import std.process.*
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.generated.*

// 一次包检查的结果：registry 查询是宿主的事（服务端只负责如实转述，绝不编造版本）
public class PackageCheckResult {
    public let exists: Bool
    public let latest: Option<String>

    public init(exists: Bool, latest: Option<String>) {
        this.exists = exists
        this.latest = latest
    }
}

public class EnvBuild {
    public let version: Int64
    public var status: String = "ready"
    public var error: Option<String> = None
    public let startedAt: Int64
    public var finishedAt: Int64 = 0
    public var files: Int64 = 0
    public var bytes: Int64 = 0
    public var packages: Array<String> = []

    public init(version: Int64) {
        this.version = version
        this.startedAt = nowSeconds()
    }
}

public class EnvRecord {
    public let id: String
    public let name: String
    public let slug: String
    public let description: Option<String>
    public let entry: Option<String>
    public let mount: String
    public let createdAt: Int64
    // 源文件（path -> 内容）；build 时快照成版本
    public let files: HashMap<String, Array<UInt8>> = HashMap<String, Array<UInt8>>()
    // 每个 build 版本的文件快照：rollback 是把某一版重新铺到 mount 上，不是改指针文案
    public let versions: HashMap<Int64, HashMap<String, Array<UInt8>>> = HashMap<Int64, HashMap<String, Array<UInt8>>>()
    public let builds: HashMap<Int64, EnvBuild> = HashMap<Int64, EnvBuild>()
    public var latestVersion: Int64 = 0
    public var active: Option<Int64> = None
    public var status: String = "empty"

    public init(id: String, name: String, slug: String, description: Option<String>,
                entry: Option<String>, mount: String) {
        this.id = id
        this.name = name
        this.slug = slug
        this.description = description
        this.entry = entry
        this.mount = mount
        this.createdAt = nowSeconds()
    }
}

func envSlug(name: String): String {
    let out = StringBuilder()
    var lastDash = false
    for (c in name.toAsciiLower().toRuneArray()) {
        let keep = (c >= r'a' && c <= r'z') || (c >= r'0' && c <= r'9') || c == r'.'
        if (keep) {
            out.append(c)
            lastDash = false
        } else if (!lastDash) {
            out.append(r'-')
            lastDash = true
        }
    }
    var slug = out.toString()
    while (slug.size > 0 && (slug.startsWith("-") || slug.startsWith("."))) {
        slug = slug[1..slug.size]
    }
    while (slug.size > 0 && (slug.endsWith("-") || slug.endsWith("."))) {
        slug = slug[0..slug.size - 1]
    }
    if (slug.size == 0) {
        slug = "env"
    }
    return slug
}

public func environmentJson(e: EnvRecord): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue(e.id)
    w.writeName("object").writeValue("environment")
    w.writeName("name").writeValue(e.name)
    w.writeName("slug").writeValue(e.slug)
    match (e.description) {
        case Some(v) => w.writeName("description").writeValue(v)
        case None => ()
    }
    match (e.entry) {
        case Some(v) => w.writeName("entry").writeValue(v)
        case None => ()
    }
    w.writeName("status").writeValue(e.status)
    w.writeName("mount").writeValue(e.mount)
    match (e.active) {
        case Some(v) => w.writeName("version").writeValue(v)
        case None => w.writeName("version").writeNullValue()
    }
    if (e.latestVersion > 0) {
        w.writeName("latestVersion").writeValue(e.latestVersion)
    }
    // files 是 {count, bytes} 的摘要（不是条目数组）
    var totalBytes: Int64 = 0
    for ((_, content) in e.files) {
        totalBytes = totalBytes + Int64(content.size)
    }
    w.writeName("files")
    w.startObject()
    w.writeName("count").writeValue(Int64(e.files.size))
    w.writeName("bytes").writeValue(totalBytes)
    w.endObject()
    w.writeName("created_at").writeValue(e.createdAt)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func envBuildJson(b: EnvBuild): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue("henvb_" + b.version.toString())
    w.writeName("object").writeValue("environment.build")
    w.writeName("version").writeValue(b.version)
    w.writeName("status").writeValue(b.status)
    w.writeName("started_at").writeValue(b.startedAt)
    w.writeName("finished_at").writeValue(b.finishedAt)
    match (b.error) {
        case Some(v) => w.writeName("error").writeValue(v)
        case None => ()
    }
    w.writeName("files").writeValue(b.files)
    w.writeName("bytes").writeValue(b.bytes)
    w.writeName("packages")
    w.startArray()
    for (p in b.packages) {
        w.writeValue(p)
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func envVersionsJson(e: EnvRecord): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("environment.versions")
    match (e.active) {
        case Some(v) => w.writeName("active").writeValue(v)
        case None => w.writeName("active").writeNullValue()
    }
    w.writeName("versions")
    w.startArray()
    for (v in 1..=e.latestVersion) {
        match (e.builds.get(v)) {
            case Some(b) =>
                w.startObject()
                w.writeName("version").writeValue(v)
                w.writeName("status").writeValue(b.status)
                w.endObject()
            case None => ()
        }
    }
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 目录树：文件本身 + 它的所有祖先目录都要出现（套件检查 probe/nested 与 probe/nested/blob.bin）
public func envFilesJson(e: EnvRecord): String {
    let dirs = ArrayList<String>()
    let files = ArrayList<String>()
    for ((path, _) in e.files) {
        files.add(path)
        let segs = path.split("/")
        var acc = ""
        var i = 0
        while (i < segs.size - 1) {
            acc = if (acc.size == 0) { segs[i] } else { acc + "/" + segs[i] }
            if (!dirs.contains(acc)) {
                dirs.add(acc)
            }
            i = i + 1
        }
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("environment.files")
    w.writeName("entries")
    w.startArray()
    for (d in dirs) {
        w.startObject()
        w.writeName("path").writeValue(d)
        w.writeName("dir").writeValue(true)
        w.endObject()
    }
    for (f in files) {
        w.startObject()
        w.writeName("path").writeValue(f)
        w.writeName("dir").writeValue(false)
        w.writeName("bytes").writeValue(Int64((e.files.get(f) ?? []).size))
        w.endObject()
    }
    w.endArray()
    w.writeName("count").writeValue(Int64(files.size))
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 把环境的源文件同步到 mount 目录（真实文件，driver 才能像 agent 那样去读）
public func syncEnvToDisk(e: EnvRecord): Unit {
    try {
        if (!exists(e.mount)) {
            Directory.create(e.mount, recursive: true)
        }
        for ((path, bytes) in e.files) {
            let full = e.mount + "/" + path
            let segs = path.split("/")
            var dir = e.mount
            var i = 0
            while (i < segs.size - 1) {
                dir = dir + "/" + segs[i]
                if (!exists(dir)) {
                    Directory.create(dir, recursive: true)
                }
                i = i + 1
            }
            FsFile.writeTo(full, bytes)
        }
    } catch (ex: Exception) {
        // 磁盘问题不该让协议层崩：mount 只是给 driver 的便利视图，文件仍保存在内存里
        eprintln("uhp: environment sync failed: " + ex.toString())
    }
}

// 把某一版快照铺到 mount（先放开写、清空、重写、再只读）。
public func materializeEnv(e: EnvRecord, files: HashMap<String, Array<UInt8>>): Unit {
    setEnvWritable(e, true)
    try {
        removeIfExists(e.mount, recursive: true)
        Directory.create(e.mount, recursive: true)
        for ((path, bytes) in files) {
            let full = e.mount + "/" + path
            let segs = path.split("/")
            var dir = e.mount
            var i = 0
            while (i < segs.size - 1) {
                dir = dir + "/" + segs[i]
                if (!exists(dir)) {
                    Directory.create(dir, recursive: true)
                }
                i = i + 1
            }
            FsFile.writeTo(full, bytes)
        }
    } catch (ex: Exception) {
        eprintln("uhp: environment materialize failed: " + ex.toString())
    }
    setEnvWritable(e, false)
}

// 只读语义：build 之后把 mount 置为不可写；PUT 前临时放开。
// （没有可移植的 chmod API，直接调用系统 chmod——这正是 POSIX 上「只读挂载」的实现方式。）
public func setEnvWritable(e: EnvRecord, writable: Bool): Unit {
    let mode = if (writable) { "u+w" } else { "a-w" }
    try {
        let _ = execute("chmod", ["-R", mode, e.mount], stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe)
    } catch (ex: Exception) {
        eprintln("uhp: chmod on environment failed: " + ex.toString())
    }
}

// 小载荷统一用 JsonWriter 拼，避免手写转义出错
public func envDeletedJson(id: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("id").writeValue(id)
    w.writeName("deleted").writeValue(true)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func envFileWrittenJson(path: String, bytes: Int64): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("path").writeValue(path)
    w.writeName("bytes").writeValue(bytes)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func envPathDeletedJson(path: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("path").writeValue(path)
    w.writeName("deleted").writeValue(true)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

public func envVersionJson(version: Int64): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("version").writeValue(version)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// EnvironmentPackageCheck 应答
public func envPackageCheckJson(manager: String, spec: String, exists: Bool,
                                latest: Option<String>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("object").writeValue("environment.package")
    w.writeName("manager").writeValue(manager)
    w.writeName("name").writeValue(spec)
    w.writeName("spec").writeValue(spec)
    w.writeName("exists").writeValue(exists)
    match (latest) {
        case Some(v) => w.writeName("latest").writeValue(v)
        case None => ()
    }
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}
