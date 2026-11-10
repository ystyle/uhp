# uhp-acp 支持矩阵

> 这里记录「适配器对 ACP 的依赖面」和「各 harness 的实测能力」。ACP 规范只保证会话可共存，
> 不保证单连接内并发执行回合；所以并发是**按 harness 开的能力**，不是默认假设。

## 1. 用到的 ACP 面

| ACP 方法 / 通知 | 用途 | 是否必需 | 备注 |
|---|---|---|---|
| `initialize` | 握手、版本协商、能力声明 | 必需 | 客户端只声明 `elicitation.form` |
| `session/new` | 建会话（cwd = `AcpOptions.cwd`） | 必需 | |
| `session/prompt` | 一轮任务 | 必需 | |
| `session/update` 通知 | 文本/推理/工具/diff → TurnSink | 必需 | 按 `sessionId` 路由到对应回合 |
| `session/request_permission` | 权限 → UHP 两轮问答 | 可选 | agent 不发就不涉及 |
| `elicitation/create` | 表单提问 → UHP 两轮问答 | 可选 | 仅 form 模式 |
| `session/cancel` | `CancelToken` → 取消 | 可选 | agent 不响应时靠本地超时收口 |
| `session/close` | 会话级回收（`closeSession`） | 可选 | 不支持时只记日志；本地映射照样摘掉 |
| `session/list` / `session/resume` | 跨进程恢复 | **未使用** | 恢复语义留给上层（见文末） |

## 2. 会话执行模式

`AcpOptions.sessionMode`：

| 模式 | 行为 | 适用 |
|---|---|---|
| `Serial`（默认） | 同一 driver 一次只跑一路回合；调用方并发 `run()` 会排队 | 任何 ACP agent |
| `Parallel` | 不同会话的回合并发执行；同一会话仍串行 | 已确认支持并发的 agent（见下表） |

**进程怎么放由上层决定**，适配器不替你开进程：

| 组织方式 | 做法 | 代价 |
|---|---|---|
| `process-per-worker` | 每个并发 worker 一个 driver（= 一个 agent 进程），`Serial` | 通用；N 份进程内存 |
| `shared` | 一个 driver 服务多个 worker 会话，`Parallel` | 省进程；只对支持的 agent |

选型判据：**默认 `process-per-worker` + `Serial`**，遇到已验证的 agent 再切 `shared` + `Parallel`。
不要因为「ACP 有多会话」就假定它能并发。

## 3. 各 harness 实测情况

| harness | 多会话（单连接） | 回合并发 | `session/close` | 实测状态 |
|---|---|---|---|---|
| DSH（`dsh --profile acp`） | ✅ | ✅（官方文档明确「一个连接可以同时运行多个会话，彼此独立」） | ✅ | 文档确认；端到端待接入 starline 后实测 |
| pi | 待实测 | 待实测 | 待实测 | 未测 |
| opencode（`opencode acp`） | 待实测 | 待实测 | 待实测 | 未测 |
| claude-code（ACP 桥） | 待实测 | 待实测 | 待实测 | 未测 |

> 未实测的行按最保守假设处理：`Serial` + `process-per-worker`。测出来支持并发再改这张表。

## 4. 回收与内存

会话是内存随规模增长的主要来源，回收分两级：

1. **会话级**：`closeSession(uhpSession)` → ACP `session/close`，让 agent 释放该会话的 agent 作用域；
   本地映射（会话、回合状态、callId 表、sink）一起摘掉，同 id 下次 `run()` 会重建会话。
   只在该会话回合已结束后调用。
2. **进程级**：`close()` → 关传输 → 终止并回收 agent 子进程（幂等；关闭后可重连）。

## 5. 已知限制

- 只声明 `elicitation.form` 能力；url 模式如实不支持。
- ACP 没有 usage/cost 字段，不臆造。
- `session/list` / `session/resume` 未接入：跨进程续跑目前由上层持有会话 id + UHP 侧历史实现。
- `Parallel` 模式下若 agent 实际串行执行，只是拿不到并发收益，不影响正确性。
