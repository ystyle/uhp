// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
public class EnvironmentFiles <: JsonSerializable & JsonDeserializable<EnvironmentFiles> {
    public var count: Option<Int64> = None
    public var bytes: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.count) {
                        w.writeName("count").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentFiles {
        let res = EnvironmentFiles()
        fromJsonObjectWithExtras(
            r,
            [
                ("count", { => res.count = r.readValue<Option<Int64>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentDeclared <: JsonSerializable & JsonDeserializable<EnvironmentDeclared> {
    public var pip: Option<Array<DeclaredPackage>> = None
    public var npm: Option<Array<DeclaredPackage>> = None
    public var apt: Option<Array<DeclaredPackage>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.pip) {
                        w.writeName("pip"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.npm) {
                        w.writeName("npm"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.apt) {
                        w.writeName("apt"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentDeclared {
        let res = EnvironmentDeclared()
        fromJsonObjectWithExtras(
            r,
            [
                ("pip", { => res.pip = r.readValue<Option<Array<DeclaredPackage>>>() }),
                ("npm", { => res.npm = r.readValue<Option<Array<DeclaredPackage>>>() }),
                ("apt", { => res.apt = r.readValue<Option<Array<DeclaredPackage>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentRuntime <: JsonSerializable & JsonDeserializable<EnvironmentRuntime> {
    public var python: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.python) {
                        w.writeName("python").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentRuntime {
        let res = EnvironmentRuntime()
        fromJsonObjectWithExtras(
            r,
            [
                ("python", { => res.python = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class Environment <: JsonSerializable & JsonDeserializable<Environment> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var name: String = ""
    public var slug: String = ""
    public var description: Option<String> = None
    public var entry: Option<String> = None
    public var status: String = ""
    public var mount: String = ""
    public var version: Option<Raw> = None
    public var latestVersion: Option<Raw> = None
    public var files: Option<EnvironmentFiles> = None
    public var packages: Option<Array<EnvironmentPackage>> = None
    public var declared: Option<EnvironmentDeclared> = None
    public var runtime: Option<EnvironmentRuntime> = None
    public var versions: Option<Array<EnvironmentVersion>> = None
    public var build: Option<EnvironmentVersion> = None
    public var createdAt: Option<Int64> = None
    public var updatedAt: Option<Int64> = None
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
                w.writeName("slug").writeValue(this.slug)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.entry) {
                        w.writeName("entry").writeValue(v)
        }
                w.writeName("status").writeValue(this.status)
                w.writeName("mount").writeValue(this.mount)
        if (let Some(v) <- this.version) {
                        w.writeName("version").jsonValue(v)
        }
        if (let Some(v) <- this.latestVersion) {
                        w.writeName("latestVersion").jsonValue(v)
        }
        if (let Some(v) <- this.files) {
                        w.writeName("files"); v.toJson(w)
        }
        if (let Some(v) <- this.packages) {
                        w.writeName("packages"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.declared) {
                        w.writeName("declared"); v.toJson(w)
        }
        if (let Some(v) <- this.runtime) {
                        w.writeName("runtime"); v.toJson(w)
        }
        if (let Some(v) <- this.versions) {
                        w.writeName("versions"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.build) {
                        w.writeName("build"); v.toJson(w)
        }
        if (let Some(v) <- this.createdAt) {
                        w.writeName("createdAt").writeValue(v)
        }
        if (let Some(v) <- this.updatedAt) {
                        w.writeName("updatedAt").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Environment {
        let res = Environment()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("slug", { => res.slug = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("entry", { => res.entry = r.readValue<Option<String>>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("mount", { => res.mount = r.readValue<String>() }),
                ("version", { => res.version = readRaw(r) }),
                ("latestVersion", { => res.latestVersion = readRaw(r) }),
                ("files", { => res.files = r.readValue<Option<EnvironmentFiles>>() }),
                ("packages", { => res.packages = r.readValue<Option<Array<EnvironmentPackage>>>() }),
                ("declared", { => res.declared = r.readValue<Option<EnvironmentDeclared>>() }),
                ("runtime", { => res.runtime = r.readValue<Option<EnvironmentRuntime>>() }),
                ("versions", { => res.versions = r.readValue<Option<Array<EnvironmentVersion>>>() }),
                ("build", { => res.build = r.readValue<Option<EnvironmentVersion>>() }),
                ("createdAt", { => res.createdAt = r.readValue<Option<Int64>>() }),
                ("updatedAt", { => res.updatedAt = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentBuild <: JsonSerializable & JsonDeserializable<EnvironmentBuild> {
    public var id: String = ""
    public var objectKind: Option<String> = None
    public var version: Int64 = 0
    public var status: String = ""
    public var started_at: Option<Raw> = None
    public var finished_at: Option<Raw> = None
    public var error: Option<String> = None
    public var stage: Option<String> = None
    public var log: Option<String> = None
    public var packages: Option<Array<EnvironmentPackage>> = None
    public var files: Option<Int64> = None
    public var bytes: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("id").writeValue(this.id)
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("version").writeValue(this.version)
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.started_at) {
                        w.writeName("started_at").jsonValue(v)
        }
        if (let Some(v) <- this.finished_at) {
                        w.writeName("finished_at").jsonValue(v)
        }
        if (let Some(v) <- this.error) {
                        w.writeName("error").writeValue(v)
        }
        if (let Some(v) <- this.stage) {
                        w.writeName("stage").writeValue(v)
        }
        if (let Some(v) <- this.log) {
                        w.writeName("log").writeValue(v)
        }
        if (let Some(v) <- this.packages) {
                        w.writeName("packages"); w.startArray();
            for (e in v) { e.toJson(w) }
            w.endArray()
        }
        if (let Some(v) <- this.files) {
                        w.writeName("files").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentBuild {
        let res = EnvironmentBuild()
        fromJsonObjectWithExtras(
            r,
            [
                ("id", { => res.id = r.readValue<String>() }),
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("version", { => res.version = r.readValue<Int64>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("started_at", { => res.started_at = readRaw(r) }),
                ("finished_at", { => res.finished_at = readRaw(r) }),
                ("error", { => res.error = r.readValue<Option<String>>() }),
                ("stage", { => res.stage = r.readValue<Option<String>>() }),
                ("log", { => res.log = r.readValue<Option<String>>() }),
                ("packages", { => res.packages = r.readValue<Option<Array<EnvironmentPackage>>>() }),
                ("files", { => res.files = r.readValue<Option<Int64>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentCreatePackages <: JsonSerializable & JsonDeserializable<EnvironmentCreatePackages> {
    public var pip: Option<Array<String>> = None
    public var npm: Option<Array<String>> = None
    public var apt: Option<Array<String>> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.pip) {
                        w.writeName("pip").writeValue(v)
        }
        if (let Some(v) <- this.npm) {
                        w.writeName("npm").writeValue(v)
        }
        if (let Some(v) <- this.apt) {
                        w.writeName("apt").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentCreatePackages {
        let res = EnvironmentCreatePackages()
        fromJsonObjectWithExtras(
            r,
            [
                ("pip", { => res.pip = r.readValue<Option<Array<String>>>() }),
                ("npm", { => res.npm = r.readValue<Option<Array<String>>>() }),
                ("apt", { => res.apt = r.readValue<Option<Array<String>>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentCreateRuntime <: JsonSerializable & JsonDeserializable<EnvironmentCreateRuntime> {
    public var python: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.python) {
                        w.writeName("python").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentCreateRuntime {
        let res = EnvironmentCreateRuntime()
        fromJsonObjectWithExtras(
            r,
            [
                ("python", { => res.python = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentCreate <: JsonSerializable & JsonDeserializable<EnvironmentCreate> {
    public var name: String = ""
    public var description: Option<String> = None
    public var entry: Option<String> = None
    public var packages: Option<EnvironmentCreatePackages> = None
    public var runtime: Option<EnvironmentCreateRuntime> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) {
                        w.writeName("description").writeValue(v)
        }
        if (let Some(v) <- this.entry) {
                        w.writeName("entry").writeValue(v)
        }
        if (let Some(v) <- this.packages) {
                        w.writeName("packages"); v.toJson(w)
        }
        if (let Some(v) <- this.runtime) {
                        w.writeName("runtime"); v.toJson(w)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentCreate {
        let res = EnvironmentCreate()
        fromJsonObjectWithExtras(
            r,
            [
                ("name", { => res.name = r.readValue<String>() }),
                ("description", { => res.description = r.readValue<Option<String>>() }),
                ("entry", { => res.entry = r.readValue<Option<String>>() }),
                ("packages", { => res.packages = r.readValue<Option<EnvironmentCreatePackages>>() }),
                ("runtime", { => res.runtime = r.readValue<Option<EnvironmentCreateRuntime>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentFileEntry <: JsonSerializable & JsonDeserializable<EnvironmentFileEntry> {
    public var path: String = ""
    public var dir: Bool = false
    public var bytes: Option<Int64> = None
    public var mtime: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("path").writeValue(this.path)
                w.writeName("dir").writeValue(this.dir)
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        if (let Some(v) <- this.mtime) {
                        w.writeName("mtime").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentFileEntry {
        let res = EnvironmentFileEntry()
        fromJsonObjectWithExtras(
            r,
            [
                ("path", { => res.path = r.readValue<String>() }),
                ("dir", { => res.dir = r.readValue<Bool>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() }),
                ("mtime", { => res.mtime = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentFileList <: JsonSerializable & JsonDeserializable<EnvironmentFileList> {
    public var entries: Array<EnvironmentFileEntry> = []
    public var count: Option<Int64> = None
    public var bytes: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("entries"); w.startArray();
        for (e in this.entries) { e.toJson(w) }
        w.endArray()
        if (let Some(v) <- this.count) {
                        w.writeName("count").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentFileList {
        let res = EnvironmentFileList()
        fromJsonObjectWithExtras(
            r,
            [
                ("entries", { => res.entries = r.readValue<Array<EnvironmentFileEntry>>() }),
                ("count", { => res.count = r.readValue<Option<Int64>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentImportGit <: JsonSerializable & JsonDeserializable<EnvironmentImportGit> {
    public var url: String = ""
    public var ref: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("url").writeValue(this.url)
        if (let Some(v) <- this.ref) {
                        w.writeName("ref").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentImportGit {
        let res = EnvironmentImportGit()
        fromJsonObjectWithExtras(
            r,
            [
                ("url", { => res.url = r.readValue<String>() }),
                ("ref", { => res.ref = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentImport <: JsonSerializable & JsonDeserializable<EnvironmentImport> {
    public var git: Option<EnvironmentImportGit> = None
    public var replace: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.git) {
                        w.writeName("git"); v.toJson(w)
        }
        if (let Some(v) <- this.replace) {
                        w.writeName("replace").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentImport {
        let res = EnvironmentImport()
        fromJsonObjectWithExtras(
            r,
            [
                ("git", { => res.git = r.readValue<Option<EnvironmentImportGit>>() }),
                ("replace", { => res.replace = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentImportResult <: JsonSerializable & JsonDeserializable<EnvironmentImportResult> {
    public var written: Option<Int64> = None
    public var skipped: Option<Int64> = None
    public var count: Option<Int64> = None
    public var bytes: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.written) {
                        w.writeName("written").writeValue(v)
        }
        if (let Some(v) <- this.skipped) {
                        w.writeName("skipped").writeValue(v)
        }
        if (let Some(v) <- this.count) {
                        w.writeName("count").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentImportResult {
        let res = EnvironmentImportResult()
        fromJsonObjectWithExtras(
            r,
            [
                ("written", { => res.written = r.readValue<Option<Int64>>() }),
                ("skipped", { => res.skipped = r.readValue<Option<Int64>>() }),
                ("count", { => res.count = r.readValue<Option<Int64>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentList <: JsonSerializable & JsonDeserializable<EnvironmentList> {
    public var environments: Array<Environment> = []
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("environments"); w.startArray();
        for (e in this.environments) { e.toJson(w) }
        w.endArray()
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentList {
        let res = EnvironmentList()
        fromJsonObjectWithExtras(
            r,
            [
                ("environments", { => res.environments = r.readValue<Array<Environment>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentPackage <: JsonSerializable & JsonDeserializable<EnvironmentPackage> {
    public var manager: String = ""
    public var name: String = ""
    public var version: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("manager").writeValue(this.manager)
                w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentPackage {
        let res = EnvironmentPackage()
        fromJsonObjectWithExtras(
            r,
            [
                ("manager", { => res.manager = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("version", { => res.version = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentPackageCheck <: JsonSerializable & JsonDeserializable<EnvironmentPackageCheck> {
    public var objectKind: Option<String> = None
    public var manager: String = ""
    public var name: String = ""
    public var spec: String = ""
    public var exists: Raw = ""
    public var latest: Option<String> = None
    public var version: Option<String> = None
    public var error: Option<String> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.objectKind) {
                        w.writeName("object").writeValue(v)
        }
                w.writeName("manager").writeValue(this.manager)
                w.writeName("name").writeValue(this.name)
                w.writeName("spec").writeValue(this.spec)
        if (this.exists.size > 0) {
            w.writeName("exists").jsonValue(this.exists)
        } else {
            w.writeName("exists").writeNullValue()
        }
        if (let Some(v) <- this.latest) {
                        w.writeName("latest").writeValue(v)
        }
        if (let Some(v) <- this.version) {
                        w.writeName("version").writeValue(v)
        }
        if (let Some(v) <- this.error) {
                        w.writeName("error").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentPackageCheck {
        let res = EnvironmentPackageCheck()
        fromJsonObjectWithExtras(
            r,
            [
                ("object", { => res.objectKind = r.readValue<Option<String>>() }),
                ("manager", { => res.manager = r.readValue<String>() }),
                ("name", { => res.name = r.readValue<String>() }),
                ("spec", { => res.spec = r.readValue<String>() }),
                ("exists", { => res.exists = readRaw(r) }),
                ("latest", { => res.latest = r.readValue<Option<String>>() }),
                ("version", { => res.version = r.readValue<Option<String>>() }),
                ("error", { => res.error = r.readValue<Option<String>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentRuntimesOs <: JsonSerializable & JsonDeserializable<EnvironmentRuntimesOs> {
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
    public static func fromJson(r: JsonReader): EnvironmentRuntimesOs {
        let res = EnvironmentRuntimesOs()
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

public class EnvironmentRuntimes <: JsonSerializable & JsonDeserializable<EnvironmentRuntimes> {
    public var python: Option<Array<String>> = None
    public var node: Option<Array<String>> = None
    public var os: Option<EnvironmentRuntimesOs> = None
    public var apt: Option<Bool> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.python) {
                        w.writeName("python").writeValue(v)
        }
        if (let Some(v) <- this.node) {
                        w.writeName("node").writeValue(v)
        }
        if (let Some(v) <- this.os) {
                        w.writeName("os"); v.toJson(w)
        }
        if (let Some(v) <- this.apt) {
                        w.writeName("apt").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentRuntimes {
        let res = EnvironmentRuntimes()
        fromJsonObjectWithExtras(
            r,
            [
                ("python", { => res.python = r.readValue<Option<Array<String>>>() }),
                ("node", { => res.node = r.readValue<Option<Array<String>>>() }),
                ("os", { => res.os = r.readValue<Option<EnvironmentRuntimesOs>>() }),
                ("apt", { => res.apt = r.readValue<Option<Bool>>() })
            ],
            res.extras
        )
        return res
    }
}

public class EnvironmentVersion <: JsonSerializable & JsonDeserializable<EnvironmentVersion> {
    public var version: Int64 = 0
    public var status: String = ""
    public var started_at: Option<Raw> = None
    public var finished_at: Option<Raw> = None
    public var error: Option<String> = None
    public var files: Option<Int64> = None
    public var bytes: Option<Int64> = None
    public var packages: Option<Int64> = None
    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）
    public var extras: Extras = newExtras()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
                w.writeName("version").writeValue(this.version)
                w.writeName("status").writeValue(this.status)
        if (let Some(v) <- this.started_at) {
                        w.writeName("started_at").jsonValue(v)
        }
        if (let Some(v) <- this.finished_at) {
                        w.writeName("finished_at").jsonValue(v)
        }
        if (let Some(v) <- this.error) {
                        w.writeName("error").writeValue(v)
        }
        if (let Some(v) <- this.files) {
                        w.writeName("files").writeValue(v)
        }
        if (let Some(v) <- this.bytes) {
                        w.writeName("bytes").writeValue(v)
        }
        if (let Some(v) <- this.packages) {
                        w.writeName("packages").writeValue(v)
        }
        writeExtras(w, this.extras)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EnvironmentVersion {
        let res = EnvironmentVersion()
        fromJsonObjectWithExtras(
            r,
            [
                ("version", { => res.version = r.readValue<Int64>() }),
                ("status", { => res.status = r.readValue<String>() }),
                ("started_at", { => res.started_at = readRaw(r) }),
                ("finished_at", { => res.finished_at = readRaw(r) }),
                ("error", { => res.error = r.readValue<Option<String>>() }),
                ("files", { => res.files = r.readValue<Option<Int64>>() }),
                ("bytes", { => res.bytes = r.readValue<Option<Int64>>() }),
                ("packages", { => res.packages = r.readValue<Option<Int64>>() })
            ],
            res.extras
        )
        return res
    }
}
