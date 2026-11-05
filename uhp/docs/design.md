# uhp-cj 设计

> 状态：**官方一致性套件 core 41/41、extended 50/50、full 104/104 全部 CONFORMANT**（suite `2026.10.19.post5`）。
> 本文是**仓内版**设计：架构、取舍、有意不做。协议来源的调研过程与裁定明细分别见工作区
> `docs/plans/2026-11-05-uhp-cj-sdk.md`（含决策记录 D1–D14）和本仓 `docs/spec-conflicts.md`。

## 1. 我们做哪一半

UHP 是 **HTTP/1.1 + REST/JSON + SSE** 的协议，不是 JSON-RPC。它规定三件事：

1. **协议面**：对象、端点、状态机、能力、错误模型、事件流；
2. **服务端骨架**：谁能做什么、什么时候拒绝、什么状态不可回退；
3. **执行**：真正的 agent 循环、模型调用、工具执行、沙箱。

本仓交付 1 与 2，**不做 3**。执行通过一个显式的 SPI 接进来：

```cangjie
public interface HarnessDriver {
    func base(): String
    func baseLabel(): String
    func models(): Array<Model>
    func capabilities(): HarnessCapabilities
    func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome
}
```

一句话边界：**SDK 负责「说得对、答得对」，不负责「干得好」**。
所以本仓里没有容器编排、没有模型 SDK、没有真实 base 适配器——那些是消费方的事。

## 2. 分层与依赖方向

```
使用者 ──► client/  ◄── 发现/协商/重试/SSE 消费         ┐
        └► server/  ◄── 路由/门控/状态机/事件通道/存储     │ 协议语义
                        ▲                                  │
                  transport/  ◄── stdx.net.http 适配、SSE 解析器、分发器  │ 只有 IO
                        ▲                                  │
                     types/   ◄── 生成对象 + 手写联合 + 保真 codec        ┘ 纯数据
```

硬规则（AGENTS.md §3，评审时看这条）：

- `types` **不得** import `stdx.net.http` / `transport` / `server` / `client`；
- `transport` 可以 import `types`；`client`/`server` 可以 import 两者；
- `root.cj` / `types.cj` 只做 `public import`，不承载实现；
- `types` 内部层级固定：**`codec <- base <- generated <- handwritten`**。

## 3. 为什么是单模块 + 子包，不是 workspace

schema 分析曾建议按 domain 拆 4 个 workspace 成员（types/transport/client/server）。否决理由：

| 维度 | 单模块 + 子包（采用） | workspace 4 成员 |
|---|---|---|
| 版本 | 一个版本号即产品版本 | 4 个成员需要 lockstep，发布流程翻倍 |
| 制品 | 一个 `.cjp`，类型与传输同版本 | 4 个包，下游要同时钉 4 个版本 |
| 循环依赖 | 编译器直接拒绝（子包在同一模块内可见性更严） | 成员间依赖写版本号，容易绕出环 |
| 使用 | `import uhp.*` 一次到位 | 需要逐包 import 与钉版本 |

拆分的唯一好处是「单独发布 types」，但 types 的演进与协议版本绑定，独立发布没有意义。

## 4. 类型层：生成 + 手写 + 保真 codec

### 4.1 生成

`tools/gen_types.py` 读 `resources/schema/uhp-2026-10-19.openapi.yaml` 的 `$defs` 等价物，产出
`src/types/generated/*.cj`：**90 个类 + 2 个枚举**。生成物有文件头标记，**只允许生成器写**；
`--check` 是 CI 闸门（重新生成后逐字节比对）。

生成器的刻意的取舍：

- **未知字段保真**：每个生成类都带 `Extras = HashMap<String, String>`（键 → 原始 JSON 文本），
  序列化末尾 `writeExtras`。契约是 **GET → PUT 不丢未知键**——上游 153 个对象节点全部 `additionalProperties: true`，
  这是设计而不是疏忽。
- **absent ≠ null ≠ 空**：可空字段用 `Option<T>`；协议要求「键必须存在、值可为 null」的（`Response`、`ErrorEnvelope`）
  用 `ALWAYS_EMIT_NULL` 名单强制写 `null`。
- **命名冲突有登记**：`Error` 与 `std.core.Error` 冲突 → 生成名 `ErrorObject`；
  `HttpRequest/HttpResponse` 与 stdx 冲突 → 传输层叫 `UhpRequest/UhpResponse`。

### 4.2 手写（4 块，各有理由）

| 手写块 | 为什么不能生成 |
|---|---|
| `UhpEvent`（18 变体 + `Unknown`） | schema 里 `Event.type` 是自由字符串，**没有 discriminated union**；prose 却写「Event 是按 type 的联合」——见 spec-conflicts #1 |
| `ErrorType` / `ErrorCodes` / `RetryAdvice` / `ErrorEnvelope` | 信封语义（sanitize、重试分类、6 键必写含 null）是行为，schema 表达不了 |
| `Capabilities`（16 键） | schema 无法表达「16 个布尔必须全部写出 / 缺省 false / 不用 Option」 |
| `OutputItem` 联合 / 信封类型（13 个端点响应） | 与 Event 同理；端点信封在 schema 里是 19 个匿名形状 |

### 4.3 时间单位

协议里三种时间形态并存，**必须在类型上区分**，禁止裸 `Int64` 混用：
Unix 秒（`created_at` 一类）、Unix 毫秒（记忆 `valid_from` 的毫秒形态）、ISO 8601 字符串（时序事实的 `valid_from/valid_to`）。
本仓目前按字段逐个处理并在 `protocol-notes.md` 标注，未引入 newtype——这是**已知的还不理想处**，见 §9。

## 5. 传输层

- **HTTP**：`stdx.net.http`。服务端用 `ServerBuilder` + 自定义 `UhpDistributor`（按路径分发、返回 404 兜底）；
  客户端每个 SSE 流**独占一个 `Client`**（共享连接池时，未读完的流会污染池里的连接，表现为随机 read 超时——实测踩过）。
- **SSE 解析**：字节级增量解析器，跨 chunk 的半行必须拼回去（`events` 字段、`retry`、注释行都要处理）。
  这是纯函数，单测覆盖「UTF-8 被 chunk 边界切开」的场景。
- **服务端 SSE**：`EventChannel` 负责分配 `sequence_number`（**只有它分配**），内部按游标增量推事件（**客户端 cursor 续流未实现**），关闭后拒绝再发。终态事件关闭通道。
- **就绪**：测试与 SUT 一律 `port(0)` + 轮询 discovery，**不用固定端口、不用 sleep 等就绪**。

## 6. 客户端

`UhpClient` 的 API 形状对齐「一次调用 = 一个语义动作」：`discovery()`、`listHarnesses()`、
`createTask()`、`createTaskStream()`、`getResponse()`、`cancel()`、`listSessions()`…

- **版本协商**：请求带 `UHP-Version`；不认识就明确失败并列出支持版本，绝不静默降级（套件 V-03 正是打这个）。
- **错误映射**：HTTP 状态 + 错误封套 → `UhpError`（带 `code`/`type`/`retry`）；流内的 `response.failed` 也映射成错误，而不是异常。
- **幂等**：创建类请求可带 `Idempotency-Key`；同 key 不同请求体 → 409，而不是拿第一次的答案应付第二次。
- **流消费**：`TaskStream` 暴露事件迭代 + 终态响应；断线由调用方决定是否用 `cursor` 重连（协议给了 `sequence_number` 与 `cursor`）。

## 7. 服务端

### 7.1 装配

```cangjie
let engine = Engine([harness], cls: ConformanceClass.Full, driverFactory: ..., packageChecker: ...)
let server = UhpHttpServer(engine, Authenticator(tokens))
```

`Engine` 是协议状态机；`UhpHttpServer` 只做 HTTP 翻译（路由、Body、SSE 头、错误映射）。
两者之间没有隐藏全局状态：`Engine` 内的存储是一组 `HashMap`（会话/响应/文件/环境/记忆/分享/幂等键），
接缝留在 `Engine` 的构造参数与 `HarnessDriver` 上。

### 7.2 任务与会话状态机

- 会话（session）内**同时只允许一个进行中的响应**；第二个任务 → 409 `session_busy`。
- 任务状态：`in_progress` → `completed` / `incomplete` / `failed` / `cancelled`。**终态不可回退**。
- `cancelled` 是独立终态，不折叠进 `failed`（但流的终态事件仍是 `response.failed`——事件类型封闭，
  权威状态在 `response.status`；见 spec-conflicts）。
- **被预算截断或等人回答的工作绝不报 `completed`**：`max_step` 超额 → `incomplete(max_steps)`；
  `ask_user` → `incomplete(input_required)` 并把问题落成 `input_request` item。

### 7.3 事件通道

事件顺序是契约：`response.created`（seq 0）→ 增量事件 → **恰好一个**终态事件（携带完整 Response）。
`sequence_number` 连续无空洞；`EventChannel` 是唯一分配者，driver 无法影响它。

### 7.4 文件与容器

会话 → 容器 → 产物。`POST /v1/files`（multipart）上传的文件挂在 principal 的收件箱容器；
产物由 driver 通过 `TurnSink.producedFile` 声明，SDK 登记进会话容器。
下载按「容器 + 文件」双键校验：**跨 principal 或跨容器一律 404**（不透露存在性），并带 `X-Content-Type-Options: nosniff`。

### 7.5 鉴权与 scope

Bearer token → `Principal`；所有对象读取先过 owner 检查。
**跨 principal 永远 404 而不是 403**——403 会告诉攻击者「这个对象存在」。
401 的错误 `type` 必须是 `authentication_error`，403 必须是 `permission_error`（错误类型是封闭集合）。

## 8. 可选能力：三个章节，同一套原则

plugins / environments / memories 在**每个类里都是可选的**；本仓在 Full 类全开。
三章共同的三条原则：

1. **要么整章实现，要么整章 404**，不允许半章；
2. **派生值是算出来的，不是存下来的**：插件的 manifest/mcpServers/skills/skipped 每次读都从包重算，
   客户端回传的派生值一律忽略；
3. **能力声明必须如实**：provider 声明 `holds/graph.entities/recall.signals` 等，
   不做的就声明不做（套件据此跳过），**不伪装成通过**。

### 8.1 environments

环境 = 项目级文件 + 依赖，build 一次、所有会话只读挂载。
本仓把每个环境做成**真实目录**（`<cwd>/.uhp-envs/<slug>`）：文件写到盘上、build 后 `chmod -R a-w`，
所以「只读挂载」是真的只读（套件 EN-07 会在 mount 下真写一次）。
版本是快照：`activate` 把旧版快照重新铺盘，不是只改指针。

### 8.2 plugins

只做**包 → 派生态**这一层纯函数（Agent Plugins 1.0.0）：manifest 校验、`mcp.json` → `mcpServers`
（`streamable-http → http`、stdio 带 command/args/env/cwd）、`skills/` 直接子目录发现、`skipped` 契约。
不执行插件：运行时把 enabled 的服务器并集通过 `TurnContext.mcpServers` 交给 driver。
导出（`GET /v1/harnesses/{id}/plugin`）**必须省略凭证**并记进 `skipped`——包会旅行，operator 的密钥不会。

### 8.3 memories

树形记忆空间 + 记录 + 召回 + 版本 + 遗忘/擦除 + 实体图 + 时序事实。
关键语义：`written_by` 由服务端盖章、`trust=untrusted`、修订**追加版本**（旧版本保留「当时的世界」）、
召回只看自己与子树、不支持的能力必须进 `degraded`、
`holds=one` 的事实会真的结束旧值并写 provider 版本（`valid_to` + `on_behalf_of`）。

## 9. 有意不做 / 已知不足

| 项 | 现状 | 理由 / 后续 |
|---|---|---|
| 真实 base 适配 | 靠 `HarnessDriver` 接 | opencode 2.x 的调研结论已在工作区设计文档 D.5，适配器不在本仓 |
| 持久化存储 | 全内存 | 接缝在 `Engine`；协议本身不规定存储。落盘是宿主选择 |
| 多租户隔离 | 单进程内存 + owner 字段 | 跨 principal 已按 404 约束；真正的隔离（进程/沙箱）属部署面 |
| registry 查询（包检查） | 可注入接缝，SUT 注入本地实现 | 外部世界（PyPI/私有源）不该进 SDK |
| 时间单位的 newtype | 按字段处理并文档化 | 见 §4.3；类型化收益低于改动面 |
| `GET /v1/harnesses/{id}/events` | 不实现 | prose-only、非任何类必需（spec-conflicts #?） |

## 10. 测试策略

四层，任何人改动后按这个顺序验证：

| 层 | 内容 | 命令 |
|---|---|---|
| L1 单元 | 类型往返、错误映射、SSE 解析、状态机、派生纯函数、引擎行为 | `cjpm test` |
| L2 行为 | 引擎级：会话/文件/环境/记忆/插件的语义（不发网络） | `cjpm test`（同包 `*_test.cj`） |
| L3 端到端 | 根包内起真实 `UhpHttpServer` 打自己的 `UhpClient`（loopback） | `cjpm test`（`src/*_test.cj`） |
| L4 一致性 | 官方套件跑 SUT，报告入库 | `bash scripts/conformance.sh full` |

铁律：**skip 从不等于 pass**；报告必须带 `suite_version`；报告在失败时也要落盘（脚本已处理）。

## 11. 文档分工

| 文件 | 回答什么 |
|---|---|
| `design.md`（本文） | 为什么这样分层、取舍、有意不做 |
| `support.md` | **实现边界的单一事实来源**：端点 × 类 × 能力 |
| `protocol-notes.md` | 写实现时最容易踩的点（顺序、单位、命名、不变式） |
| `spec-conflicts.md` | 三份真相冲突时的裁定，每条带测试锚点 |
| `conformance/*.json` | 「我是哪个套件测的」的证据 |
