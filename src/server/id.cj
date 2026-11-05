// 对象 id：前缀 + 体。
//
// 规范（Architecture §3）要求 id 带类型前缀，让标识符永不含糊；**客户端不得解析前缀**，
// 所以这层只在服务端生成侧使用。注意 hsess 没有下划线（规范表如此），其余都有。
package uhp.server

import std.random.Random

public class IdSource {
    private let rnd: Random = Random()

    public init() {}

    public func harness(): String {
        return "chrn_" + hex()
    }

    public func response(): String {
        return "resp_" + hex()
    }

    public func session(): String {
        return "hsess" + hex()
    }

    public func file(): String {
        return "file_" + hex()
    }

    public func container(): String {
        return "cntr_" + hex()
    }

    public func inputRequest(): String {
        return "inreq_" + hex()
    }

    private func hex(): String {
        let a = this.rnd.nextUInt64().toString()
        let b = this.rnd.nextUInt64().toString()
        return a + b
    }
}
