// 假 ACP agent：给适配器测试当被测子进程。
//
// 行为（由 prompt 文本触发）：
//   * 默认：两条 agent_message_chunk + end_turn
//   * 含 "slow"：持续吐 chunk，收到 cancel 就返回 cancelled
//   * 含 "refuse"：返回 refusal
//   * 含 "maxturn"：返回 max_turn_requests
package uhp_acp.examples.fake_agent

import acp.*
import acp.types.*
import acp.transport.*

main() {
    let agent = AcpAgent(StdioTransport(), "uhp-fake-acp-agent", "0.1.0")
    agent.setPromptHandler({ ctx =>
        let text = ctx.getText()
        if (text.contains("refuse")) {
            return PromptResponse(StopReasonRefusal)
        }
        if (text.contains("maxturn")) {
            return PromptResponse(StopReasonMaxTurnRequests)
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
