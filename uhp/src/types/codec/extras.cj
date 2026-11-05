// 未知字段保真（规范：153 个对象节点全部 additionalProperties: true；
// 客户端 MUST 忽略未知字段，服务端 MAY 新增字段）。
//
// 实现选择：把未消费的 JSON 值连同其名字**按原始字节保存**，
// 序列化时原样写回（JsonWriter.jsonValue）。零第三方依赖，且能保证
// 「GET → PUT」不丢数据——这是 UHP 里最容易造成静默数据损坏的一处。
package uhp.types.codec

import std.collection.HashMap
import stdx.encoding.json.stream.{JsonReader, JsonWriter, JsonToken}
import stdx.encoding.json.stream.*

// 未知字段：JSON 键 -> 该值对应的原始 JSON 文本（已规范化到合法 JSON，不做语义解析）。
public type Extras = HashMap<String, String>

public func newExtras(): Extras {
    return HashMap<String, String>()
}

// 读取对象，按 handlers 分发已知键；未知键的原始值收进 extras。
// 契约：调用时 reader 位于 BeginObject 之前；返回时已消费整个对象。
public func fromJsonObjectWithExtras(r: JsonReader, handlers: Array<(String, () -> Unit)>, extras: Extras): Unit {
    let refs = HashMap<String, () -> Unit>(handlers)
    match (r.peek()) {
        case Some(BeginObject) =>
            r.startObject()
            while (true) {
                let name = match (r.peek()) {
                    case Some(EndObject) => break
                    case Some(Name) => r.readName()
                    case _ => throw JsonProtocolException("对象成员应为字符串键")
                }
                if (refs.contains(name)) {
                    refs[name]()
                } else {
                    let raw = String.fromUtf8(r.readValueBytes())
                    extras[name] = raw
                }
            }
            r.endObject()
        case _ =>
            throw JsonProtocolException("期望 JSON 对象")
    }
}

// 把保留下来的未知字段原样写回（在已知字段之后调用）。
public func writeExtras(w: JsonWriter, extras: Extras): Unit {
    for ((k, v) in extras) {
        w.writeName(k)
        w.jsonValue(v)
    }
}

// JSON 结构不符合协议时抛出（不是业务错误：业务错误走 UhpError）。
public class JsonProtocolException <: Exception {
    public JsonProtocolException(message: String) {
        super(message)
    }
}
