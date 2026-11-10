# uhp-acp 使用教程

把任意 ACP agent（`opencode acp`、dsh、pi、claude-code…）接到 UHP：driver 把 ACP 的 session/update 翻译成 UHP 的 TurnSink / TurnOutcome。

## 1. 起 UHP 服务端

```cangjie
import std.collection.HashMap
import stdx.net.http.*
import uhp.server.*
import uhp_acp.*

main() {
    // command/args 就是拉起 ACP agent 的方式；cwd 是 agent 的工作目录
    let opts = AcpOptions("opencode", args: ["acp"], cwd: "/path/to/workspace")
    let driver = AcpDriver(opts)
    let harness = ConfiguredHarness("chrn_acp", "ACP agent", "acp", "auto", driver)
    let engine = Engine([harness])

    let tokens = HashMap<String, String>()
tokens["dev-token"] = "alice"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    ServerBuilder().addr("127.0.0.1").port(8471).distributor(uhp.distributor()).build().serve()
}
```

## 2. 验证

```bash
bash scripts/test.sh          # 9 条测试（真 ACP 协议 + 假 agent 子进程）
bash scripts/real-smoke.sh    # 真实链路：UHP 任务 → opencode acp → 探针输出
```

## 3. 映射要点

| ACP | UHP |
|---|---|
| `agent_message_chunk` / `agent_thought_chunk` | `textDelta` / `reasoningDelta` |
| `tool_call` / `tool_call_update` | `toolCall` / `toolResult` |
| `session/request_permission` | `ask("choice", …)` → 两轮问答 |
| `elicitation/create`（form） | 单字段 → choice/confirm/free_text；多字段 → 回 JSON 对象 |
| `stopReason` | `Completed` / `Cancelled` / `Incomplete` / `Failed` |
| `CancelToken` | `session/cancel` |
| 输入文件 `TurnContext.files` | image / text / resource_link 内容块 |
| `tool_call_update` 的 diff 内容块 | `producedFile` → UHP 会话产物 |

## 4. API 参考

`AcpOptions(command, args = [], cwd = "/tmp", label = "ACP agent", clientName = "uhp-cj", timeoutSeconds = 600, permissionTimeoutSeconds = 600)`。

`AcpDriver(opts)` 实现 `HarnessDriver`：`base/baseLabel/models/capabilities/run`。

已知限制：只声明 `elicitation.form` 能力（url 模式如实不支持）；ACP 没有 usage/cost 字段，不臆造。
