// 向人提问（Tasks §3.2）。
//
// 契约（套件 T-13/T-14 逐条验证）：
//   * 任务在问题上**结束**：状态 incomplete，incomplete_details.reason = input_required；
//   * 问题本身是 input_request item（id 以 inreq_ 开头，kind ∈ choice/confirm/free_text/secret，
//     有 prompt，choice 带 options[{id,label}]），并且**最后一条 message 的文本里也要有它**
//     （只渲染 message 的客户端是合法客户端）；
//   * 答案是普通续跑（previous_response_id 指回提问那次），选项外 422 input_response_invalid、
//     过期/重复 409 input_not_pending；
//   * secret 的答案只到 driver，**不出现在任何客户端可读的地方**（事件、响应、input_items 都不行）。
package uhp.server

import std.collection.ArrayList
import uhp.types.generated.*

public class PendingInputRequest {
    public let id: String
    public let responseId: String
    public let kind: String
    public let prompt: String
    public let options: Array<(String, String)>
    public var answered: Bool = false

    public init(id: String, responseId: String, kind: String, prompt: String,
                options: Array<(String, String)>) {
        this.id = id
        this.responseId = responseId
        this.kind = kind
        this.prompt = prompt
        this.options = options
    }

    public func isSecret(): Bool {
        return this.kind == "secret"
    }

    public func accepts(answer: String): Bool {
        if (this.kind != "choice") {
            return true
        }
        for ((id, _) in this.options) {
            if (id == answer) {
                return true
            }
        }
        return false
    }

    public func toItem(): OutputItem {
        let item = OutputItem()
        item.id = Some(this.id)
        item.typeName = "input_request"
        item.kind = Some(this.kind)
        item.prompt = Some(this.prompt)
        if (this.options.size > 0) {
            let opts = ArrayList<OutputItemOptions>()
            for ((id, label) in this.options) {
                let o = OutputItemOptions()
                o.id = id
                o.label = label
                opts.add(o)
            }
            item.options = Some(opts.toArray())
        }
        return item
    }

    // harness 调了 ask_user 这个工具：规范要求 output 里看得到这次函数调用
    public func toFunctionCallItem(): OutputItem {
        let item = OutputItem()
        item.id = Some("fc_" + this.id)
        item.typeName = "function_call"
        item.name = Some("ask_user")
        item.call_id = Some("call_" + this.id)
        item.arguments = Some("{\"kind\":\"" + this.kind + "\",\"prompt\":\"" + this.prompt + "\"}")
        item.status = Some("completed")
        return item
    }
}
