// 自由形态 JSON（metadata / detail / 未知对象）。
//
// 取舍：不引入 jsonvalue（少一个依赖、少一层 DOM），直接用「原始 JSON 文本」表示。
// 契约：Raw 一定是合法 JSON 文本；写入走 JsonWriter.jsonValue，读取走 readValueBytes。
package uhp.types.codec

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*

public type Raw = String

public func readRaw(r: JsonReader): Raw {
    return String.fromUtf8(r.readValueBytes())
}

public func writeRaw(w: JsonWriter, v: Raw): Unit {
    w.jsonValue(v)
}
