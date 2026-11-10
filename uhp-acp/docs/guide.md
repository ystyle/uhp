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

`AcpOptions(command, args = [], cwd = "/tmp", label = "ACP agent", clientName = "uhp-cj", timeoutSeconds = 600, permissionTimeoutSeconds = 600, sessionMode = Serial)`。

`AcpDriver(opts)` 实现 `HarnessDriver`：`base/baseLabel/models/capabilities/run`；另有 `close()` 与 `closeSession(uhpSession)`。

**`close()` 必须调用**：driver 持有的是真实 Agent 子进程 + 一个阻塞读的接收线程，不关就一直在。
长跑服务里换 driver、进程退出前收尾，都应当显式 `close()`；可重复调用（幂等）。
关闭后再 `run()` 会重新拉起 Agent，因此也可以用它做「丢掉坏连接重连」。

**`closeSession(uhpSession)` 是会话级回收**：发 ACP `session/close` 让 Agent 释放该会话的作用域（内存随会话数涨的根源），
本地映射一起摘掉，同 id 下次 `run()` 会重建会话。只在该会话的回合结束后调用；Agent 不支持时只记日志，不打断调用方。

## 5. 多个 worker 怎么放

`sessionMode` 决定一个 driver 内能不能并发跑不同会话：

| 模式 | 行为 | 怎么用 |
|---|---|---|
| `Serial`（默认） | 同一 driver 一次只跑一路回合 | 每个并发 worker 一个 driver（= 一个 Agent 进程） |
| `Parallel` | 不同会话并发送中；同一会话仍串行 | 一个 driver 服务多个会话，只对确认支持的 agent 开 |

pi 没有原生 ACP，要走 `pi-acp`（第三方适配层）：`AcpOptions("pi-acp")`。它的会话回收只到进程级（未实现 `session/close`），
所以 pi 一律按 `process-per-worker` 用，任务结束关整个连接；`session/new` 之前需要 pi 已完成认证（`pi --terminal-login` 或配好 API key）。

ACP 规范没有承诺单连接内并发执行回合，所以**默认按最保守的 `Serial` + 每 worker 一进程**；
各 harness 的实测能力见 [support.md](support.md)，没实测过的先当不支持。

已知限制：只声明 `elicitation.form` 能力（url 模式如实不支持）；ACP 没有 usage/cost 字段，不臆造。
