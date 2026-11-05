// 一层 JSON 读取 + 字符串编码。
//
// 适配器只需要读 opencode 事件里的几个字段，不值得为它引一套 DOM；但**不能手写转义**
// （踩过：转义写错会产出非法 JSON），所以生成字符串一律走 JsonWriter。
package uhp_opencode.client

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.io.ByteBuffer
import stdx.encoding.json.stream.*

public class JsonObj {
    private let pairs: HashMap<String, String>
    private let decoded: HashMap<String, String>

    public init(pairs: HashMap<String, String>, decoded: HashMap<String, String>) {
        this.pairs = pairs
        this.decoded = decoded
    }

    public func str(key: String): Option<String> {
        return this.decoded.get(key)
    }

    public func raw(key: String): Option<String> {
        return this.pairs.get(key)
    }

    public func obj(key: String): Option<JsonObj> {
        return match (this.pairs.get(key)) {
            case Some(v) => ocParseJson(v)
            case None => None
        }
    }

    public func entries(): Array<(String, String)> {
        let out = ArrayList<(String, String)>()
        for ((k, v) in this.pairs) {
            out.add((k, v))
        }
        return out.toArray()
    }

    public func asInt(key: String): Option<Int64> {
        return match (this.pairs.get(key)) {
            case Some(v) => Int64.tryParse(v.trimAscii())
            case None => None
        }
    }
}

public func ocParseJson(text: String): Option<JsonObj> {
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

// 取 JSON 数组里每个对象的某个字符串字段（保留原文）
public func ocJsonStrings(arrayJson: String, field: String): Array<(String, String)> {
    let out = ArrayList<(String, String)>()
    try {
        let r = JsonReader(ByteBuffer(arrayJson.toArray()))
        r.startArray()
        while (true) {
            match (r.peek()) {
                case Some(JsonToken.EndArray) => break
                case Some(JsonToken.BeginObject) =>
                    let obj = String.fromUtf8(r.readValueBytes())
                    match (ocParseJson(obj)) {
                        case Some(o) => match (o.str(field)) {
                            case Some(v) => out.add((v, obj))
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

public func ocJsonQuote(s: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startArray()
    w.writeValue(s)
    w.endArray()
    w.flush()
    let text = String.fromUtf8(out.bytes())
    return text[1..text.size - 1]
}

public func jsonObjectOf(pairs: Array<(String, String)>): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    for ((k, v) in pairs) {
        w.writeName(k).writeValue(v)
    }
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

// 取 JSON 数组里每个对象的原文（form 的 fields、permission 的 resources 之类）
public func ocJsonObjects(arrayJson: String): Array<String> {
    let out = ArrayList<String>()
    try {
        let r = JsonReader(ByteBuffer(arrayJson.toArray()))
        r.startArray()
        while (true) {
            match (r.peek()) {
                case Some(JsonToken.EndArray) => break
                case Some(JsonToken.BeginObject) => out.add(String.fromUtf8(r.readValueBytes()))
                case _ => r.skip()
            }
        }
        r.endArray()
    } catch (e: Exception) {
        ()
    }
    return out.toArray()
}
