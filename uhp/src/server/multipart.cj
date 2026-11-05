// multipart/form-data 的极简解析：只取第一个带 filename 的 part。
//
// 范围：Extended 类只要求「上传被接受并可作为任务输入引用」，当前实现覆盖文本附件；
// 二进制与多 part 的完整解析留给需要时再补（不要假装支持）。
package uhp.server

import std.collection.ArrayList
import std.io.InputStream

public class MultipartFile {
    public let filename: String
    public let content: Array<UInt8>

    public init(filename: String, content: Array<UInt8>) {
        this.filename = filename
        this.content = content
    }
}

const QUOTE: String = "\""

public func parseMultipart(raw: Array<UInt8>, contentType: String): Option<MultipartFile> {
    let marker = "boundary="
    let bidx = match (contentType.indexOf(marker)) {
        case Some(i) => i
        case None => return None
    }
    var boundary = contentType[bidx + marker.size..contentType.size].trimAscii()
    // 去掉可选的引号包裹（不引入引号字面量：直接按字节比较）
    let bbytes = boundary.toArray()
    if (bbytes.size >= 2 && bbytes[0] == UInt8(34) && bbytes[bbytes.size - 1] == UInt8(34)) {
        boundary = String.fromUtf8(bbytes[1..bbytes.size - 1])
    }
    let text = String.fromUtf8(raw)
    let delim = "--" + boundary
    for (part in text.split(delim)) {
        if (!part.contains("filename=")) {
            continue
        }
        let fnKey = "filename="
        let fnIdx = match (part.indexOf(fnKey)) {
            case Some(i) => i
            case None => continue
        }
        var rest = part[fnIdx + fnKey.size..part.size]
        // 去掉可能的引号，然后取到下一个引号 / 分号 / CR 为止
        let rbytes = rest.toArray()
        if (rbytes.size > 0 && rbytes[0] == UInt8(34)) {
            rest = String.fromUtf8(rbytes[1..rbytes.size])
        }
        var fnEnd = rest.size
        for (i in 0..rest.size) {
            let b = rest.toArray()[i]
            if (b == UInt8(34) || b == UInt8(59) || b == UInt8(13)) {
                fnEnd = i
                break
            }
        }
        let filename = rest[0..fnEnd]
        let bodyIdx = match (part.indexOf("\r\n\r\n")) {
            case Some(i) => i
            case None => continue
        }
        var content = part[bodyIdx + 4..part.size]
        if (content.endsWith("\r\n")) {
            content = content[0..content.size - 2]
        }
        return Some(MultipartFile(filename, content.toArray()))
    }
    return None
}

public func readAllBytes(body: InputStream): Array<UInt8> {
    let chunks = ArrayList<UInt8>()
    let buf = Array<UInt8>(8192, repeat: 0)
    while (true) {
        let n = body.read(buf)
        if (n <= 0) {
            break
        }
        chunks.add(all: buf[0..n])
    }
    return chunks.toArray()
}
