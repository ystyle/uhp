// SSE 事件联合（Streaming §1/§2）。
//
// 为什么是手写而不是生成：
//   schema 里 Event 是一个**扁平对象**——type 是自由字符串 + 18 条 examples，没有 enum、
//   没有 oneOf、additionalProperties: true。规范正文（schema.md）却称它是「按 type 的
//   discriminated union」。结构以制品为准，所以联合类型只能手写（设计文档附录 A5）。
//
// 客户端契约（VERSIONING「Client rules」四条中的第 2 条，MUST）：
//   「Ignore unknown event types. Skip and continue reading the stream.」
//   所以 Unknown 变体不是可选项，也不是错误路径——它是正版协议的一部分。
//
// 序号契约（Streaming §1/§3）：
//   每个事件 MUST 带 type 与 sequence_number；sequence_number 从 0 起、每帧严格 +1、无缺口。
//   缺口检测（一致性套件 S-04）是客户端发现「流被丢掉一段」的唯一手段，所以这里对
//   缺失/负值采取**抛异常**而不是静默补 0——补 0 会让两个事件序号相同，把检测变成瞎的。
//   唯一的例外是未知事件类型：那条路不承诺字段，序号缺失按 Option 保留（见 UnknownEvent）。
//
// 载荷策略（本阶段）：
//   response / item / part / annotation 这几个子对象对应的生成类型尚未接入（task-9 范围外），
//   因此按**原始 JSON 文本**保存并在回写时原样输出（用 uhp.types.codec 的 Raw 约定：
//   readRaw 读、writeRaw 写，不在这里另发明一套）。这不是偷懒：终态事件必须携带完整
//   Response（Streaming §4：只靠这一个事件就能渲染结果），在没有类型之前，丢字段比不解析
//   严重得多。uhp.types.generated.Response 现在已经生成出来了，但「终态事件的 response 是否
//   一定完整、status 是否 cancelled」要在服务端装配那一层核对，属于后续任务；届时把
//   *Raw: Option<Raw> 换成 Option<Response> 即可，本文件的 fromJson/toJson 形状不变。
package uhp.types.handwritten

import std.io.ByteBuffer
import stdx.encoding.json.stream.{JsonReader, JsonWriter, JsonToken}
import stdx.encoding.json.stream.*
import uhp.types.codec.*

// ───────────────────────────── 载荷结构 ─────────────────────────────
//
// 每种载荷都带 sequenceNumber（每个事件都有）与 extras（未知字段保真，仓级约定）。
// 字段一律 Option 的情况：schema 没有把它列为 required，服务端可能不写；
// 用 Option 而不是默认值，是为了让调用方能区分「没写」和「写了空串」。

// response.created / in_progress / completed / incomplete / failed 共用。
// 五个变体的区别只在事件类型（生命周期位置），载荷形状相同。
public class ResponseEvent {
    public var sequenceNumber: Int64 = 0
    // 完整 Response 的原始 JSON。终态三个事件（completed/incomplete/failed）必须携带它；
    // created 携带 status=in_progress 的初始 Response；in_progress 可以不携带。
    // 生成类型接入后替换为 Option<Response>。
    public var responseRaw: Option<Raw> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.output_item.added / response.output_item.done。
// added 携带的是一个「壳」item（只有类型与 id），done 携带完整 item。
public class ItemEvent {
    public var sequenceNumber: Int64 = 0
    public var outputIndex: Option<Int64> = None
    public var itemRaw: Option<Raw> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.content_part.added / response.content_part.done（assistant 正文分片）。
// added 打开一个空 part，done 携带写完的 part。
public class ContentPartEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var contentIndex: Option<Int64> = None
    public var partRaw: Option<Raw> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.reasoning_summary_part.added / response.reasoning_summary_part.done。
// 与 ContentPartEvent 的区别只有索引名：推理用 summary_index，正文用 content_index。
// 刻意不共用一个结构：协议把它们放在不同小节，合并会让「哪个索引对这个事件有意义」消失。
public class ReasoningPartEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var summaryIndex: Option<Int64> = None
    public var partRaw: Option<Raw> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.output_text.delta：正文增量。delta 是**片段**，客户端 MUST 按 sequence_number
// 顺序拼接，且 MUST NOT 假设任何分块边界（Streaming §2.3）。
public class TextDeltaEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var contentIndex: Option<Int64> = None
    // 规范要求该事件携带 delta；这里缺省空串而不是 Option：空串本身就是合法分片，
    // 用 Option 会让每个消费方都写一次 getOrElse。不规范的输入被容忍（见文件头策略）。
    public var delta: String = ""
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.output_text.done：该 part 的完整文本（客户端不必再自己拼）。
public class TextDoneEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var contentIndex: Option<Int64> = None
    public var text: String = ""
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.output_text.annotation.added：正文里的一条产物引用（artifact citation）。
public class AnnotationEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var contentIndex: Option<Int64> = None
    public var annotationIndex: Option<Int64> = None
    public var annotationRaw: Option<Raw> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.reasoning_summary_text.delta：推理摘要增量。
// 规范明确：推理是**可选**的（很多 harness/模型不产生），客户端必须能处理完全没有它的情况。
public class ReasoningTextDeltaEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var summaryIndex: Option<Int64> = None
    public var delta: String = ""
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.function_call_arguments.delta：工具调用参数的 JSON 增量。
public class ToolArgsDeltaEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    public var delta: String = ""
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// response.function_call_arguments.done：完整的参数 JSON（字符串形式，不是对象）。
public class ToolArgsDoneEvent {
    public var sequenceNumber: Int64 = 0
    public var itemId: Option<String> = None
    public var outputIndex: Option<Int64> = None
    // JSON 文本，不是解析后的对象：协议就是把它当字符串发（schema: {"type":"string"}）。
    public var arguments: String = ""
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// error 事件：**不是终态**。规范要求它之后 MUST 还有一个终态事件（Streaming §2.6）——
// 只发 error 就断流的服务器不可用，客户端无法区分「任务死了」和「连接断了」。
public class StreamErrorEvent {
    public var sequenceNumber: Int64 = 0
    // code/message 用空串而非 Option：规范要求二者必带，容忍不规范服务端用一个空串
    // 比让整条流抛异常更划算；消费方本来就要对未知 code 做兜底（VERSIONING 第 4 条）。
    public var code: String = ""
    public var message: String = ""
    // param 是 ["string","null"]：null 与缺失等价（都不指向具体字段），两者都落到 None、
    // 回写时不输出。这是本文件唯一的非逐字节行为，已写进契约与测试。
    public var param: Option<String> = None
    public var extras: Extras = newExtras()

    public init() {}
    public init(sequenceNumber: Int64) {
        this.sequenceNumber = sequenceNumber
    }
}

// 未知事件类型的兜底。raw 是**整个事件对象的原始 JSON 文本**，回写时逐字节原样输出——
// 重新拼装会丢字段、改顺序，等于把「忽略未知事件」实现成「丢弃未知事件」。
// sequenceNumber 是 Option：未知类型不承诺任何字段，缺了也不能抛（否则一条未来事件
// 就能毒死整条流）。
public class UnknownEvent {
    public var typeName: String = ""
    public var raw: Raw = ""
    public var sequenceNumber: Option<Int64> = None

    public init() {}
    public init(typeName: String, raw: Raw, sequenceNumber: Option<Int64>) {
        this.typeName = typeName
        this.raw = raw
        this.sequenceNumber = sequenceNumber
    }
}

// ───────────────────────────── 事件联合 ─────────────────────────────
//
// 18 个已知类型（Streaming §2 全部词表）+ Unknown。
// 顺序按规范小节排列：生命周期 5 → 输出项 2 → 正文 5 → 推理 3 → 工具 2 → 错误 1。
public enum UhpEvent <: JsonSerializable & JsonDeserializable<UhpEvent> {
    | Created(ResponseEvent)
    | InProgress(ResponseEvent)
    | Completed(ResponseEvent)
    | Incomplete(ResponseEvent)
    | Failed(ResponseEvent)
    | OutputItemAdded(ItemEvent)
    | OutputItemDone(ItemEvent)
    | ContentPartAdded(ContentPartEvent)
    | ContentPartDone(ContentPartEvent)
    | OutputTextDelta(TextDeltaEvent)
    | OutputTextDone(TextDoneEvent)
    | OutputTextAnnotationAdded(AnnotationEvent)
    | ReasoningSummaryPartAdded(ReasoningPartEvent)
    | ReasoningSummaryPartDone(ReasoningPartEvent)
    | ReasoningSummaryTextDelta(ReasoningTextDeltaEvent)
    | FunctionCallArgumentsDelta(ToolArgsDeltaEvent)
    | FunctionCallArgumentsDone(ToolArgsDoneEvent)
    | Error(StreamErrorEvent)
    | Unknown(UnknownEvent)

    // 反序列化：先整体取原始字节，再分派。
    //
    // 为什么不在单趟里分派：type 可能出现在对象任意位置，而 Reader 是前向的；
    // 先 readValueBytes() 拿到整个对象，既解决了「不知道 type 时怎么读」，
    // 又顺手为 Unknown 保留了逐字节原文。代价是一次小对象的重复扫描——
    // 事件都很小，这点开销换「未知事件不丢数据」是值得的。
    public static func fromJson(r: JsonReader): UhpEvent {
        let rawBytes = r.readValueBytes()
        let raw = String.fromUtf8(rawBytes)
        let fields = EventFields()
        let inner = JsonReader(ByteBuffer(rawBytes))
        fromJsonObjectWithExtras(inner, eventHandlers(inner, fields), fields.extras)
        let kind = match (fields.typeName) {
            case Some(t) => t
            case None => throw JsonProtocolException("事件缺少必填字段 type（Streaming §1）")
        }
        return match (kind) {
            case "response.created" => UhpEvent.Created(buildResponseEvent(fields))
            case "response.in_progress" => UhpEvent.InProgress(buildResponseEvent(fields))
            case "response.completed" => UhpEvent.Completed(buildResponseEvent(fields))
            case "response.incomplete" => UhpEvent.Incomplete(buildResponseEvent(fields))
            case "response.failed" => UhpEvent.Failed(buildResponseEvent(fields))
            case "response.output_item.added" => UhpEvent.OutputItemAdded(buildItemEvent(fields))
            case "response.output_item.done" => UhpEvent.OutputItemDone(buildItemEvent(fields))
            case "response.content_part.added" => UhpEvent.ContentPartAdded(buildContentPartEvent(fields))
            case "response.content_part.done" => UhpEvent.ContentPartDone(buildContentPartEvent(fields))
            case "response.output_text.delta" => UhpEvent.OutputTextDelta(buildTextDeltaEvent(fields))
            case "response.output_text.done" => UhpEvent.OutputTextDone(buildTextDoneEvent(fields))
            case "response.output_text.annotation.added" => UhpEvent.OutputTextAnnotationAdded(buildAnnotationEvent(fields))
            case "response.reasoning_summary_part.added" => UhpEvent.ReasoningSummaryPartAdded(buildReasoningPartEvent(fields))
            case "response.reasoning_summary_part.done" => UhpEvent.ReasoningSummaryPartDone(buildReasoningPartEvent(fields))
            case "response.reasoning_summary_text.delta" => UhpEvent.ReasoningSummaryTextDelta(buildReasoningTextDeltaEvent(fields))
            case "response.function_call_arguments.delta" => UhpEvent.FunctionCallArgumentsDelta(buildToolArgsDeltaEvent(fields))
            case "response.function_call_arguments.done" => UhpEvent.FunctionCallArgumentsDone(buildToolArgsDoneEvent(fields))
            case "error" => UhpEvent.Error(buildStreamErrorEvent(fields))
            // 未知类型：不抛、不丢，原样兜住（VERSIONING 客户端规则 2）。
            case _ => UhpEvent.Unknown(UnknownEvent(kind, raw, fields.sequenceNumber))
        }
    }

    public func toJson(w: JsonWriter): Unit {
        let t = typeName(this)
        match (this) {
            case UhpEvent.Created(e) => writeResponseEvent(w, t, e)
            case UhpEvent.InProgress(e) => writeResponseEvent(w, t, e)
            case UhpEvent.Completed(e) => writeResponseEvent(w, t, e)
            case UhpEvent.Incomplete(e) => writeResponseEvent(w, t, e)
            case UhpEvent.Failed(e) => writeResponseEvent(w, t, e)
            case UhpEvent.OutputItemAdded(e) => writeItemEvent(w, t, e)
            case UhpEvent.OutputItemDone(e) => writeItemEvent(w, t, e)
            case UhpEvent.ContentPartAdded(e) => writeContentPartEvent(w, t, e)
            case UhpEvent.ContentPartDone(e) => writeContentPartEvent(w, t, e)
            case UhpEvent.OutputTextDelta(e) => writeTextDeltaEvent(w, t, e)
            case UhpEvent.OutputTextDone(e) => writeTextDoneEvent(w, t, e)
            case UhpEvent.OutputTextAnnotationAdded(e) => writeAnnotationEvent(w, t, e)
            case UhpEvent.ReasoningSummaryPartAdded(e) => writeReasoningPartEvent(w, t, e)
            case UhpEvent.ReasoningSummaryPartDone(e) => writeReasoningPartEvent(w, t, e)
            case UhpEvent.ReasoningSummaryTextDelta(e) => writeReasoningTextDeltaEvent(w, t, e)
            case UhpEvent.FunctionCallArgumentsDelta(e) => writeToolArgsDeltaEvent(w, t, e)
            case UhpEvent.FunctionCallArgumentsDone(e) => writeToolArgsDoneEvent(w, t, e)
            case UhpEvent.Error(e) => writeStreamErrorEvent(w, t, e)
            case UhpEvent.Unknown(u) => writeUnknownEvent(w, u)
        }
    }
}

// ───────────────────────────── 分派中间态 ─────────────────────────────

// 一次事件对象里可能出现的全部键（schema Event.properties 的 17 个）。
// 先全部收下来再按 type 解释：type 的位置不固定，而 Reader 只能前向读。
class EventFields {
    var typeName: Option<String> = None
    var sequenceNumber: Option<Int64> = None
    var responseRaw: Option<String> = None
    var itemRaw: Option<String> = None
    var partRaw: Option<String> = None
    var annotationRaw: Option<String> = None
    var delta: Option<String> = None
    var text: Option<String> = None
    var arguments: Option<String> = None
    var itemId: Option<String> = None
    var outputIndex: Option<Int64> = None
    var contentIndex: Option<Int64> = None
    var summaryIndex: Option<Int64> = None
    var annotationIndex: Option<Int64> = None
    var code: Option<String> = None
    var message: Option<String> = None
    var param: Option<String> = None
    var extras: Extras = newExtras()
}

// 键 -> 读取动作。未知键由 fromJsonObjectWithExtras 收进 extras（逐字节保真）。
func eventHandlers(r: JsonReader, f: EventFields): Array<(String, () -> Unit)> {
    return [
        ("type", { => f.typeName = Some(r.readValue<String>()) }),
        ("sequence_number", { => f.sequenceNumber = Some(r.readValue<Int64>()) }),
        // 子对象按原始 JSON 文本保存：生成类型未接入，丢字段比不解析严重。
        ("response", { => f.responseRaw = Some(readRaw(r)) }),
        ("item", { => f.itemRaw = Some(readRaw(r)) }),
        ("part", { => f.partRaw = Some(readRaw(r)) }),
        ("annotation", { => f.annotationRaw = Some(readRaw(r)) }),
        ("delta", { => f.delta = Some(r.readValue<String>()) }),
        ("text", { => f.text = Some(r.readValue<String>()) }),
        ("arguments", { => f.arguments = Some(r.readValue<String>()) }),
        ("item_id", { => f.itemId = Some(r.readValue<String>()) }),
        ("output_index", { => f.outputIndex = Some(r.readValue<Int64>()) }),
        ("content_index", { => f.contentIndex = Some(r.readValue<Int64>()) }),
        ("summary_index", { => f.summaryIndex = Some(r.readValue<Int64>()) }),
        ("annotation_index", { => f.annotationIndex = Some(r.readValue<Int64>()) }),
        ("code", { => f.code = Some(r.readValue<String>()) }),
        ("message", { => f.message = Some(r.readValue<String>()) }),
        // param 是 ["string","null"]：null 与缺失等价，消费掉不保留（见 StreamErrorEvent）。
        ("param", { =>
            match (r.peek()) {
                case Some(JsonNull) => r.skip()
                case _ => f.param = Some(r.readValue<String>())
            }
        })
    ]
}

// 已知事件缺 sequence_number 时的行为：抛。
// 理由见文件头。只对**已知**事件生效——未知事件走 Unknown，不经过这里。
func requireSequenceNumber(f: EventFields): Int64 {
    let n = match (f.sequenceNumber) {
        case Some(v) => v
        case None => throw JsonProtocolException("事件缺少必填字段 sequence_number（Streaming §1）")
    }
    if (n < 0) {
        throw JsonProtocolException("sequence_number 不能为负（schema minimum: 0）")
    }
    return n
}

// ───────────────────────────── 载荷构造 ─────────────────────────────
// 每个构造器：取必填序号 + 搬可空字段 + 把 extras 交出去（extras 由本事件独占）。

func buildResponseEvent(f: EventFields): ResponseEvent {
    let e = ResponseEvent(requireSequenceNumber(f))
    e.responseRaw = f.responseRaw
    e.extras = f.extras
    return e
}

func buildItemEvent(f: EventFields): ItemEvent {
    let e = ItemEvent(requireSequenceNumber(f))
    e.outputIndex = f.outputIndex
    e.itemRaw = f.itemRaw
    e.extras = f.extras
    return e
}

func buildContentPartEvent(f: EventFields): ContentPartEvent {
    let e = ContentPartEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.contentIndex = f.contentIndex
    e.partRaw = f.partRaw
    e.extras = f.extras
    return e
}

func buildReasoningPartEvent(f: EventFields): ReasoningPartEvent {
    let e = ReasoningPartEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.summaryIndex = f.summaryIndex
    e.partRaw = f.partRaw
    e.extras = f.extras
    return e
}

func buildTextDeltaEvent(f: EventFields): TextDeltaEvent {
    let e = TextDeltaEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.contentIndex = f.contentIndex
    e.delta = f.delta.getOrDefault({ => "" })
    e.extras = f.extras
    return e
}

func buildTextDoneEvent(f: EventFields): TextDoneEvent {
    let e = TextDoneEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.contentIndex = f.contentIndex
    e.text = f.text.getOrDefault({ => "" })
    e.extras = f.extras
    return e
}

func buildAnnotationEvent(f: EventFields): AnnotationEvent {
    let e = AnnotationEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.contentIndex = f.contentIndex
    e.annotationIndex = f.annotationIndex
    e.annotationRaw = f.annotationRaw
    e.extras = f.extras
    return e
}

func buildReasoningTextDeltaEvent(f: EventFields): ReasoningTextDeltaEvent {
    let e = ReasoningTextDeltaEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.summaryIndex = f.summaryIndex
    e.delta = f.delta.getOrDefault({ => "" })
    e.extras = f.extras
    return e
}

func buildToolArgsDeltaEvent(f: EventFields): ToolArgsDeltaEvent {
    let e = ToolArgsDeltaEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.delta = f.delta.getOrDefault({ => "" })
    e.extras = f.extras
    return e
}

func buildToolArgsDoneEvent(f: EventFields): ToolArgsDoneEvent {
    let e = ToolArgsDoneEvent(requireSequenceNumber(f))
    e.itemId = f.itemId
    e.outputIndex = f.outputIndex
    e.arguments = f.arguments.getOrDefault({ => "" })
    e.extras = f.extras
    return e
}

func buildStreamErrorEvent(f: EventFields): StreamErrorEvent {
    let e = StreamErrorEvent(requireSequenceNumber(f))
    e.code = f.code.getOrDefault({ => "" })
    e.message = f.message.getOrDefault({ => "" })
    e.param = f.param
    e.extras = f.extras
    return e
}

// ───────────────────────────── 回写原语 ─────────────────────────────

// 事件公共头：type + sequence_number（Streaming §1 要求两者必带）。
func startEvent(w: JsonWriter, t: String, seq: Int64): Unit {
    w.startObject()
    w.writeName("type").writeValue(t)
    w.writeName("sequence_number").writeValue(seq)
}

// 子对象字段：值本来就是合法 JSON 文本，用 jsonValue 原样写。
// 若改用 writeValue 会被当成字符串再编码一次（变成带引号的文本），形状就变了。
func writeRawField(w: JsonWriter, name: String, v: Option<Raw>): Unit {
    match (v) {
        case Some(raw) =>
            w.writeName(name)
            writeRaw(w, raw)
        case None => ()
    }
}

func writeStringField(w: JsonWriter, name: String, v: Option<String>): Unit {
    match (v) {
        case Some(s) => w.writeName(name).writeValue(s)
        case None => ()
    }
}

func writeIntField(w: JsonWriter, name: String, v: Option<Int64>): Unit {
    match (v) {
        case Some(n) => w.writeName(name).writeValue(n)
        case None => ()
    }
}

// ───────────────────────────── 各变体回写 ─────────────────────────────
// 只写「这个事件真的有」的字段：None 的字段省略而不是写 null，
// 这样服务端→客户端→服务端的往返不会凭空长出字段。

func writeResponseEvent(w: JsonWriter, t: String, e: ResponseEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeRawField(w, "response", e.responseRaw)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeItemEvent(w: JsonWriter, t: String, e: ItemEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeIntField(w, "output_index", e.outputIndex)
    writeRawField(w, "item", e.itemRaw)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeContentPartEvent(w: JsonWriter, t: String, e: ContentPartEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "content_index", e.contentIndex)
    writeRawField(w, "part", e.partRaw)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeReasoningPartEvent(w: JsonWriter, t: String, e: ReasoningPartEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "summary_index", e.summaryIndex)
    writeRawField(w, "part", e.partRaw)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeTextDeltaEvent(w: JsonWriter, t: String, e: TextDeltaEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "content_index", e.contentIndex)
    w.writeName("delta").writeValue(e.delta)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeTextDoneEvent(w: JsonWriter, t: String, e: TextDoneEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "content_index", e.contentIndex)
    w.writeName("text").writeValue(e.text)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeAnnotationEvent(w: JsonWriter, t: String, e: AnnotationEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "content_index", e.contentIndex)
    writeIntField(w, "annotation_index", e.annotationIndex)
    writeRawField(w, "annotation", e.annotationRaw)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeReasoningTextDeltaEvent(w: JsonWriter, t: String, e: ReasoningTextDeltaEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    writeIntField(w, "summary_index", e.summaryIndex)
    w.writeName("delta").writeValue(e.delta)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeToolArgsDeltaEvent(w: JsonWriter, t: String, e: ToolArgsDeltaEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    w.writeName("delta").writeValue(e.delta)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeToolArgsDoneEvent(w: JsonWriter, t: String, e: ToolArgsDoneEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    writeStringField(w, "item_id", e.itemId)
    writeIntField(w, "output_index", e.outputIndex)
    w.writeName("arguments").writeValue(e.arguments)
    writeExtras(w, e.extras)
    w.endObject()
}

func writeStreamErrorEvent(w: JsonWriter, t: String, e: StreamErrorEvent): Unit {
    startEvent(w, t, e.sequenceNumber)
    w.writeName("code").writeValue(e.code)
    w.writeName("message").writeValue(e.message)
    writeStringField(w, "param", e.param)
    writeExtras(w, e.extras)
    w.endObject()
}

// 未知事件：把收到的原始 JSON 原样写回（逐字节），而不是重新拼装——
// 重新拼装会丢字段、改顺序，等于把「忽略未知事件」实现成「丢弃未知事件」。
// raw 为空只可能是手工构造的 Unknown（没经过 fromJson），此时至少保证输出是合法 JSON。
func writeUnknownEvent(w: JsonWriter, u: UnknownEvent): Unit {
    if (!u.raw.isEmpty()) {
        writeRaw(w, u.raw)
        return
    }
    w.startObject()
    w.writeName("type").writeValue(u.typeName)
    match (u.sequenceNumber) {
        case Some(n) => w.writeName("sequence_number").writeValue(n)
        case None => ()
    }
    w.endObject()
}

// ───────────────────────────── 公共查询 ─────────────────────────────

// 事件在线上使用的类型名。toJson 与 fromJson 都以它为准，避免字面量在两处漂移。
public func typeName(ev: UhpEvent): String {
    return match (ev) {
        case UhpEvent.Created(_) => "response.created"
        case UhpEvent.InProgress(_) => "response.in_progress"
        case UhpEvent.Completed(_) => "response.completed"
        case UhpEvent.Incomplete(_) => "response.incomplete"
        case UhpEvent.Failed(_) => "response.failed"
        case UhpEvent.OutputItemAdded(_) => "response.output_item.added"
        case UhpEvent.OutputItemDone(_) => "response.output_item.done"
        case UhpEvent.ContentPartAdded(_) => "response.content_part.added"
        case UhpEvent.ContentPartDone(_) => "response.content_part.done"
        case UhpEvent.OutputTextDelta(_) => "response.output_text.delta"
        case UhpEvent.OutputTextDone(_) => "response.output_text.done"
        case UhpEvent.OutputTextAnnotationAdded(_) => "response.output_text.annotation.added"
        case UhpEvent.ReasoningSummaryPartAdded(_) => "response.reasoning_summary_part.added"
        case UhpEvent.ReasoningSummaryPartDone(_) => "response.reasoning_summary_part.done"
        case UhpEvent.ReasoningSummaryTextDelta(_) => "response.reasoning_summary_text.delta"
        case UhpEvent.FunctionCallArgumentsDelta(_) => "response.function_call_arguments.delta"
        case UhpEvent.FunctionCallArgumentsDone(_) => "response.function_call_arguments.done"
        case UhpEvent.Error(_) => "error"
        case UhpEvent.Unknown(u) => u.typeName
    }
}

// 事件序号。已知事件必为 Some（缺失已在 fromJson 处抛）；未知事件可能为 None。
// SSE 消费方用它做缺口检测：每帧必须比上一帧 +1（Streaming §3 / 套件 S-04）。
public func sequenceNumberOf(ev: UhpEvent): Option<Int64> {
    return match (ev) {
        case UhpEvent.Created(e) => Some(e.sequenceNumber)
        case UhpEvent.InProgress(e) => Some(e.sequenceNumber)
        case UhpEvent.Completed(e) => Some(e.sequenceNumber)
        case UhpEvent.Incomplete(e) => Some(e.sequenceNumber)
        case UhpEvent.Failed(e) => Some(e.sequenceNumber)
        case UhpEvent.OutputItemAdded(e) => Some(e.sequenceNumber)
        case UhpEvent.OutputItemDone(e) => Some(e.sequenceNumber)
        case UhpEvent.ContentPartAdded(e) => Some(e.sequenceNumber)
        case UhpEvent.ContentPartDone(e) => Some(e.sequenceNumber)
        case UhpEvent.OutputTextDelta(e) => Some(e.sequenceNumber)
        case UhpEvent.OutputTextDone(e) => Some(e.sequenceNumber)
        case UhpEvent.OutputTextAnnotationAdded(e) => Some(e.sequenceNumber)
        case UhpEvent.ReasoningSummaryPartAdded(e) => Some(e.sequenceNumber)
        case UhpEvent.ReasoningSummaryPartDone(e) => Some(e.sequenceNumber)
        case UhpEvent.ReasoningSummaryTextDelta(e) => Some(e.sequenceNumber)
        case UhpEvent.FunctionCallArgumentsDelta(e) => Some(e.sequenceNumber)
        case UhpEvent.FunctionCallArgumentsDone(e) => Some(e.sequenceNumber)
        case UhpEvent.Error(e) => Some(e.sequenceNumber)
        case UhpEvent.Unknown(u) => u.sequenceNumber
    }
}

// 终态判定（Streaming §4）：恰好 completed / incomplete / failed 三者之一，且 MUST 是流的
// 最后一个事件。注意三点：
//   1. error 事件**不是**终态——§2.6 要求它之后还有终态事件；
//   2. 被取消的任务终态是 failed（response.status == "cancelled"），没有独立的 cancelled 事件；
//   3. Unknown 一律不是终态：对未知事件不能替它下结论，流是否结束由连接状态决定。
public func isTerminal(ev: UhpEvent): Bool {
    return match (ev) {
        case UhpEvent.Completed(_) => true
        case UhpEvent.Incomplete(_) => true
        case UhpEvent.Failed(_) => true
        case _ => false
    }
}

