// 假 ACP agent：给适配器测试当被测子进程。
//
// 行为（由 prompt 文本触发）：
//   * 默认：两条 agent_message_chunk + end_turn
//   * 含 "slow"：持续吐 chunk，收到 cancel 就返回 cancelled
//   * 含 "refuse"：返回 refusal
//   * 含 "maxturn"：返回 max_turn_requests
package uhp_acp.examples.fake_agent

import acp.*
import std.collection.ArrayList
import ystyle::jsonrpc.Result
import acp.types.*
import acp.transport.*

main() {
    let agent = AcpAgent(StdioTransport(), "uhp-fake-acp-agent", "0.1.0")
    agent.setPromptHandler({ ctx =>
        let text = ctx.getText()
        if (text.contains("writefile")) {
            let items = ArrayList<ToolCallContent>()
            items.add(ToolCallContent.diff("out.txt", "artifact-ok"))
            ctx.emit(SessionUpdate.toolCall("call_write", "write out.txt"))
            ctx.emit(SessionUpdate.toolCallUpdate("call_write", status: "completed", content: items))
            ctx.emit(SessionUpdate.agentMessage("wrote out.txt"))
            return PromptResponse(StopReasonEndTurn)
        }
        if (text.contains("files")) {
            var images = 0
            for (b in ctx.prompt) {
                match (b.mimeType) {
                    case Some(_) => images = images + 1
                    case None => ()
                }
            }
            ctx.emit(SessionUpdate.agentMessage("files: " + ctx.prompt.size.toString() +
                " images: " + images.toString()))
            return PromptResponse(StopReasonEndTurn)
        }
        if (text.contains("refuse")) {
            return PromptResponse(StopReasonRefusal)
        }
        if (text.contains("maxturn")) {
            return PromptResponse(StopReasonMaxTurnRequests)
        }
        if (text.contains("elicit")) {
            let pfield = ElicitationPropertySchema()
            pfield.`type` = PropTypeString
            pfield.title = Some("Your name")
            let schema = ElicitationSchema.of([("name", pfield)])
            let req = CreateElicitationRequest.form(ctx.sessionId, "Please tell me your name", schema)
            match (agent.createElicitation(req)) {
                case Result.Ok(r) =>
                    let c = match (r.content) {
                        case Some(v) => v.stringify()
                        case None => ""
                    }
                    ctx.emit(SessionUpdate.agentMessage("elicitation: " + r.action + " content=" + c))
                case Result.Err(e) =>
                    ctx.emit(SessionUpdate.agentMessage("elicitation error: " + e))
            }
            return PromptResponse(StopReasonEndTurn)
        }
        if (text.contains("perm")) {
            let tc = ToolCallUpdate()
            tc.toolCallId = "call_perm"
            tc.title = Some("Run shell command")
            let opts = ArrayList<PermissionOption>()
            opts.add(PermissionOption("once", "Allow once", "allow_once"))
            opts.add(PermissionOption("reject", "Reject", "reject_once"))
            ctx.emit(SessionUpdate.agentMessage("need permission"))
            match (agent.requestPermission(ctx.sessionId, tc, opts)) {
                case Result.Ok(r) =>
                    let picked = r.outcome.optionId ?? r.outcome.outcome
                    ctx.emit(SessionUpdate.agentMessage("perm answered: " + picked))
                case Result.Err(e) =>
                    ctx.emit(SessionUpdate.agentMessage("perm error: " + e))
            }
            return PromptResponse(StopReasonEndTurn)
        }
        if (text.contains("slow")) {
            var i = 0
            while (i < 300) {
                if (ctx.isCancelled()) {
                    return PromptResponse(StopReasonCancelled)
                }
                ctx.emit(SessionUpdate.agentMessage("tick "))
                sleep(Duration.millisecond * 10)
                i = i + 1
            }
            return PromptResponse(StopReasonEndTurn)
        }
        ctx.emit(SessionUpdate.agentThought("thinking about " + text))
        ctx.emit(SessionUpdate.toolCall("call_1", "echo", rawInput: None))
        ctx.emit(SessionUpdate.agentMessage("echo: " + text))
        PromptResponse(StopReasonEndTurn)
    })
    agent.serve()
}
