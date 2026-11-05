# uhp-acp

ACP（Agent Client Protocol）的 UHP HarnessDriver 适配器（消费方代码，不是 UHP SDK 本体）。

- UHP SDK：../uhp-cj
- ACP 库：../acp-cj（Client 侧：AcpClient + SubprocessTransport）
- 本仓：把 ACP 的 session/update 流翻译成 UHP 的 TurnSink / TurnOutcome

## 已验证

| 层 | 证据 |
|---|---|
| 行为测试 | 3 条：往返映射（thought/tool_call/message）、stopReason → 终态、取消（session/cancel）；用**真的 ACP 协议**（stdio 子进程 + 本仓假 agent），不依赖模型 |
| 真实链路 | opencode 2.2.5 的 ACP 模式（opencode acp）+ deepseek-v4.1-flash-free：UHP 任务 completed，输出 ACP-OK |

## 映射表

| ACP | UHP |
|---|---|
| session/new（按 UHP 会话建一次） | TurnContext.sessionId 复用同一个 ACP 会话 |
| session/prompt（内容块 = 一行文本） | TurnContext.input |
| agent_message_chunk | TurnSink.textDelta |
| agent_thought_chunk | TurnSink.reasoningDelta |
| tool_call（title + rawInput） | TurnSink.toolCall(name, args) |
| tool_call_update（content / rawOutput） | TurnSink.toolResult(callId, text) |
| stopReason = end_turn | TurnOutcome.Completed |
| stopReason = cancelled | TurnOutcome.Cancelled |
| stopReason = max_turn_requests | TurnOutcome.Incomplete(max_steps) |
| stopReason = max_tokens | TurnOutcome.Incomplete(max_tokens) |
| stopReason = refusal | TurnOutcome.Failed |
| CancelToken 被触发 | ACP session/cancel（旁路线程发送） |

## 用法

```cangjie
let opts = AcpOptions("opencode", args: ["acp"], cwd: "/path/to/ws", label: "opencode (ACP)")
let driver = AcpDriver(opts)
let harness = ConfiguredHarness("chrn_acp", "ACP agent", "acp", "acp-agent", driver)
let engine = Engine([harness])
```

示例可执行：uhp_acp.examples.uhp_server <port> <cwd> <agentCommand> [agentArgs...]

## 测试与真实冒烟

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
cjpm build && cjpm test -j 4 --no-progress   # 3 条测试，真 ACP 协议 + 假 agent
bash scripts/real-smoke.sh                   # opencode acp 真实链路（需要可用模型）
```

## 已知限制（如实）

1. **session/request_permission 未映射成 UHP input_request**：ACP 的权限请求是**同步回调**
   （Agent 在 prompt 里等 Client 立刻回应），而 UHP 的提问是「本轮结束 + 下一轮续跑」；
   两者模型不同，直接接会死锁。需要把 driver 改成「先结束本轮、下一轮带答案再回 ACP」——
   与 opencode 适配器里的 permission 两轮问答是同一套做法，留作后续。
2. **文件/图片内容块未映射**：UHP 的 files_input 还没进 prompt，ACP 的 image/resource 块被忽略。
3. 会话级 config/mode（model 选择）未暴露成 UHP 侧参数：由 ACP agent 自己的配置决定。
