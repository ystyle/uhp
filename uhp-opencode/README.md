# uhp-opencode

opencode 2.x 的 UHP HarnessDriver 适配器（消费方代码，不是 UHP SDK 本体）。

- UHP SDK：../uhp-cj（协议面 + 服务端骨架）
- 本仓：把 opencode 的 session / prompt / event 模型翻译成 UHP 的 TurnContext / TurnSink / TurnOutcome

## 已验证

| 层 | 证据 |
|---|---|
| 单元/行为 | 7 条：事件映射、会话复用、失败路径、取消中断、permission 两轮问答、form.choice、form.free_text（假 opencode） |
| 全栈 | 1 条：UHP 服务端（Engine + OpencodeDriver）→ 假 opencode，任务以 incomplete+input_request 结束，回答后续跑为 completed |
| 真实链路 | opencode 2.2.5 + deepseek-v4.1-flash-free：一个 UHP 任务跑通，返回 uhp-opencode-42，output 含 message + function_call + function_call_output（工具调用经 opencode 的 shell 工具真实执行），usage 映射到 UHP Usage |

## 映射表

| opencode 事件 / API | UHP 侧 |
|---|---|
| POST /api/session | 按 UHP 会话 id 建立一次（同一 UHP 会话的后续任务复用同一个 opencode 会话） |
| POST /api/session/{id}/model | 钉模型（可选；OpencodeOptions.model） |
| POST /api/session/{id}/prompt | TurnContext.input；TurnContext.files → files[]（data URI + 文件名） |
| GET /api/event（全局流） | 按 data.sessionID 过滤后消费 |
| session.text.delta / session.reasoning.delta | TurnSink.textDelta / reasoningDelta |
| session.tool.input.started（含工具名）+ session.tool.called（含参数） | TurnSink.toolCall(name, args) |
| session.tool.success / session.tool.error | TurnSink.toolResult(callId, text) |
| session.step.ended / session.usage.updated | Usage（input/output/cache；total 由适配器相加） |
| session.execution.succeeded | TurnOutcome.Completed(usage) |
| session.execution.failed | TurnOutcome.Failed("harness_error", ...) |
| session.execution.interrupted | TurnOutcome.Cancelled(usage) |
| POST /api/session/{id}/interrupt | CancelToken 被触发时调用 |
| permission.asked（工具批准） | TurnSink.ask("confirm", 提示, once/always/reject) → 本轮 incomplete(input_required) |
| POST /api/session/{id}/permission/{requestID}/reply | 下一轮续跑的答案（input_response）作为决定回给 opencode，然后继续读事件 |
| form.created（结构化提问） | 单字段：choice（带 options 的 string）/ confirm（boolean）/ free_text；多字段：free_text 要求回 JSON 对象，key 列表写进提示 |
| POST /api/session/{id}/form/{formID}/reply | 下一轮答案按字段类型编码成 Form.Value（string/number/boolean/array），多字段直接把对象原文作为 answer |

## 用法

```cangjie
let opts = OpencodeOptions(
    baseUrl: "http://127.0.0.1:4765",   // opencode serve 的地址
    directory: "/path/to/workspace",     // opencode 的 location.directory
    password: "splice-token",            // OPENCODE_SERVER_PASSWORD
    model: Some(("deepseek-v4.1-flash-free", "opencode")))
let driver = OpencodeDriver(opts)
let harness = ConfiguredHarness("chrn_opencode", "opencode 2.x", "opencode", "deepseek-v4.1-flash-free", driver)
let engine = Engine([harness])            // UHP 服务端（Core 类）
```

示例可执行：uhp_opencode.examples.example <port> <opencodeBaseUrl> <workspaceDir> [modelID providerID]

## 测试与真实冒烟

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
cjpm build && cjpm test -j 4 --no-progress     # 4 条测试，假 opencode
bash scripts/real-smoke.sh                     # 需要本机有 opencode v2 与可用模型
```

real-smoke.sh 会：起 opencode serve（隔离的 XDG 目录 + 固定密码）→ 起示例 UHP 服务端 →
POST 一个要求跑 shell 的任务 → 断言输出包含探针串。

## 已知限制（如实）

1. permission 与 form 事件都已接（input_requests=true，含完整的两轮问答测试）。
   form 的映射是「单字段映射成 UHP 的 kind；多字段要求回答一个 JSON 对象」——
   UHP 的 input_request 一次只承载一个答案，所以多字段表单的转换是有损的（已在提示里说明 key 列表）。
2. 没有做工具级预算（max_step 由 UHP 层判定；opencode 侧不截断）。
3. 文件输入已映射（files[] 收 data URI）；输出方向尚未处理（agent 生成的产物不会回传成 UHP 文件）。
4. 模型可用性取决于本机 opencode 的 provider 配置与地区——实测部分免费模型返回 RegionError，
   这是环境问题；适配器只如实把 execution.failed 翻成 UHP 的 failed。
5. 事件流是全局的：每个 driver 都在读同一流并按 sessionID 过滤；量大时应考虑共享一个订阅器。
