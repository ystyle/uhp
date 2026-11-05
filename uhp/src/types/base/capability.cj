// 能力发现（Lifecycle §2）。
//
// 规范的两条硬规则决定了这个类型的形状：
//   1. 服务端 MUST 报 false 而不是省略 → 序列化时 16 个键**全部写**；
//   2. 客户端 MUST 把缺失键当 false → 反序列化缺省 = false。
// 所以字段是 Bool（不是 Option<Bool>）：Option 会诱导调用方写出第三种分支。
package uhp.types.base

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*

public class Capabilities <: JsonSerializable & JsonDeserializable<Capabilities> {
    // Core
    public var streaming: Bool = false
    public var sessions: Bool = false
    public var cancellation: Bool = false
    // Extended
    public var filesInput: Bool = false
    public var filesOutput: Bool = false
    public var sessionListing: Bool = false
    // Full
    public var harnessManagement: Bool = false
    public var harnessRetirement: Bool = false
    public var sessionSharing: Bool = false
    // 可选行为
    public var idempotency: Bool = false
    public var harnessIdempotency: Bool = false
    public var inputRequests: Bool = false
    public var inputHistory: Bool = false
    // 章级可选能力
    public var plugins: Bool = false
    public var environments: Bool = false
    public var memories: Bool = false
    // 未知能力键（未来版本新增）按原始 JSON 保留，回写时不丢
    public var extras: Extras = newExtras()

    public init() {}

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("streaming").writeValue(this.streaming)
        w.writeName("sessions").writeValue(this.sessions)
        w.writeName("cancellation").writeValue(this.cancellation)
        w.writeName("files_input").writeValue(this.filesInput)
        w.writeName("files_output").writeValue(this.filesOutput)
        w.writeName("session_listing").writeValue(this.sessionListing)
        w.writeName("harness_management").writeValue(this.harnessManagement)
        w.writeName("harness_retirement").writeValue(this.harnessRetirement)
        w.writeName("session_sharing").writeValue(this.sessionSharing)
        w.writeName("idempotency").writeValue(this.idempotency)
        w.writeName("harness_idempotency").writeValue(this.harnessIdempotency)
        w.writeName("input_requests").writeValue(this.inputRequests)
        w.writeName("input_history").writeValue(this.inputHistory)
        w.writeName("plugins").writeValue(this.plugins)
        w.writeName("environments").writeValue(this.environments)
        w.writeName("memories").writeValue(this.memories)
        writeExtras(w, this.extras)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): Capabilities {
        let res = Capabilities()
        fromJsonObjectWithExtras(
            r,
            [
                ("streaming", { => res.streaming = r.readValue<Bool>() }),
                ("sessions", { => res.sessions = r.readValue<Bool>() }),
                ("cancellation", { => res.cancellation = r.readValue<Bool>() }),
                ("files_input", { => res.filesInput = r.readValue<Bool>() }),
                ("files_output", { => res.filesOutput = r.readValue<Bool>() }),
                ("session_listing", { => res.sessionListing = r.readValue<Bool>() }),
                ("harness_management", { => res.harnessManagement = r.readValue<Bool>() }),
                ("harness_retirement", { => res.harnessRetirement = r.readValue<Bool>() }),
                ("session_sharing", { => res.sessionSharing = r.readValue<Bool>() }),
                ("idempotency", { => res.idempotency = r.readValue<Bool>() }),
                ("harness_idempotency", { => res.harnessIdempotency = r.readValue<Bool>() }),
                ("input_requests", { => res.inputRequests = r.readValue<Bool>() }),
                ("input_history", { => res.inputHistory = r.readValue<Bool>() }),
                ("plugins", { => res.plugins = r.readValue<Bool>() }),
                ("environments", { => res.environments = r.readValue<Bool>() }),
                ("memories", { => res.memories = r.readValue<Bool>() })
            ],
            res.extras
        )
        return res
    }

    // 一致性类与能力必须自洽（Lifecycle §2；一致性套件 D-04/D-05 会查）。
    public func consistentWith(cls: ConformanceClass): Bool {
        return match (cls) {
            case ConformanceClass.Core => true
            case ConformanceClass.Extended => this.filesInput && this.filesOutput && this.sessionListing
            case ConformanceClass.Full => this.filesInput && this.filesOutput && this.sessionListing
        }
    }
}

public enum ConformanceClass {
    | Core
    | Extended
    | Full
}

public func conformanceClassName(c: ConformanceClass): String {
    return match (c) {
        case ConformanceClass.Core => "core"
        case ConformanceClass.Extended => "extended"
        case ConformanceClass.Full => "full"
    }
}
