# 协议实现要点（易踩点速查）

> 写给改这个仓的人：这些点要么是规范里容易读漏的，要么是踩过之后不该再踩的。
> 每条尽量给「锚点」——代码位置或套件检查 id，改之前先看那里。

## 1. 顺序与不变式

### 1.1 版本协商先于一切

包括 discovery：`GET /v1/uhp` 带不认识的 `UHP-Version` 也必须 400 并列出支持版本，
**绝不静默换版本**。原因：客户端要先确认对方说的是哪个版本，才能解释后面的任何响应。

- 锚点：`src/server/http.cj` `negotiate()` 在路由最前；套件 **V-03**。

### 1.2 每个响应都带 `UHP-Version`

**包括 4xx/5xx 错误响应**。openapi 只在成功响应上声明了这个头，prose 说「每个响应」——
按 prose 实现（错误响应由 `writeError` 统一补）。

- 锚点：`writeJson` / `writeError`；套件 **V-01**。

### 1.3 SSE 的顺序契约

1. 第一个事件必须是 `response.created`，`sequence_number = 0`；
2. `sequence_number` 连续无空洞，**只有 `EventChannel` 能分配**（driver 影响不了）；
3. 恰好一个终态事件，且携带**完整** Response；
4. 终态事件之后通道关闭；
5. 服务端 SSE **边产生边发**（不能等任务跑完再一把刷——套件 S-09 会抓），靠通道内的游标增量读。
   **客户端断开后按 cursor 续流未实现**：实时流没有 client-cursor 路径，重连要重新发起任务。

- 锚点：`src/server/channel.cj`、`Engine.executeTask`；套件 **S-04/S-05/S-06/S-07**。

### 1.4 终态不可回退

`completed` / `incomplete` / `failed` / `cancelled` 一旦确定，后续读/取消都不改变它。
`cancelled` 是独立终态：流的终态事件用 `response.failed`（事件类型是封闭集合），
**权威状态看 `response.status`**。

- 锚点：`applyOutcome` + `cancelResponse`；套件 **C-02/C-03**。

### 1.5 被截断/等待的工作绝不报 completed

- `max_step` 超额 → `incomplete` + `incomplete_details.reason = "max_steps"`；
- `ask_user` → `incomplete` + `input_required`，并把问题落成 `input_request` item。

- 锚点：`Engine.finishWithQuestions`、`overBudget` 分支；套件 **T-12/T-13**。

## 2. 错误模型

| 规则 | 说明 | 锚点 |
|---|---|---|
| 错误类型是封闭集合 | 6 种 `type`；**401 必须 `authentication_error`，403 必须 `permission_error`**，不能笼统 `invalid_request_error` | `handwritten/error.cj`；套件 A-02 |
| 跨 principal 一律 404 | 403 会告诉攻击者「对象存在」 | `getStoredLocked`/`recordLocked`；套件 E-02/E-03 |
| 错误 message 必须可安全展示 | 内部异常文本不泄漏；**但服务端要记 stderr**（规范要求「扣下的 detail 要留日志」） | `http.cj` catch 分支 |
| 结构化 detail 该给就给 | `unsupported_base` → `detail.supported`（**数组**）；`plugin_conflict` → `detail.component/name` | 套件 F-02/P-04/P-09 |
| 忽略字段必须点名 | 请求里的 `tools`/`include` 接受但不执行 → `metadata.ignored_fields` | 套件 T-09 |

## 3. 时间单位与 id 前缀

### 3.1 时间

| 场景 | 形态 | 注意 |
|---|---|---|
| `Response.created_at`、会话 `created_at/updated_at`、harness/environment/plugin `createdAt` | Unix **秒** | 全部用 `nowSeconds()` |
| 记忆时序事实 `time.valid_from/valid_to` | **ISO 8601 字符串** | 同格式可直接按字典序比较；输出保留输入拼写 |
| 记忆 `environment` 包检查等其它 | 见 `$defs` | 没有把握就读 schema，不要猜 |

### 3.2 id 前缀（服务端生成，客户端不得解析）

| 前缀 | 对象 | 备注 |
|---|---|---|
| `chrn_` | harness | 规范表如此 |
| `resp_` | response | |
| `hsess` | session | **没有下划线**（规范表唯一特例） |
| `file_` | file | |
| `cntr_` | container | |
| `inreq_` | input_request | 套件会断言这个前缀 |
| `henv_` | environment | 套件会断言 |
| `hmem_` / `hmrec_` | memory / memory record | 本仓约定 |
| `shr_` | share | 分享 id 与 URL token **分开生成**（泄漏一个不顺带泄漏另一个） |

## 4. 序列化：absent ≠ null ≠ 空

- 可空字段用 `Option<T>`，缺省**不写键**；
- 协议要求「键必须存在、值可为 null」的（`Response.error/usage/store/metadata/previous_response_id`、
  `ErrorObject.param/detail`）→ 生成器的 `ALWAYS_EMIT_NULL` 名单强制写 `null`；
- 「空数组有语义」的（插件 `skipped`、记忆 `content`）→ 必须写 `[]`，不能省略；
- **未知字段保真**：所有读写走 `fromJsonObjectWithExtras` + `writeExtras`，GET→PUT 不丢未知键。

⚠️ **`JsonWriter.jsonValue()` 只接受原始 JSON 文本**。把解码后的 `String` 塞进去会写出非法 JSON
（`"title":The ...`）。写字符串用 `writeValue()`；嵌 JSON 片段才用 `jsonValue()`。
这个坑一次打红过三条记忆检查（ME-02/05/13）。

## 5. 文件与容器

- 会话 → 容器 → 产物；下载按「容器 + 文件」双键校验，越界/跨 principal 404；
- 下载带 `X-Content-Type-Options: nosniff`；
- `/pdf` 预览：不实现就 **501 `preview_unavailable`**，绝不返回坏/空 PDF；
- 产物来源是 driver 的 `TurnSink.producedFile`（driver 拥有工作目录，SDK 登记）。

## 6. 插件的四个容易做错的点

1. **派生值每次重算**：manifest / mcpServers / skills / skipped 从包重新派生，客户端回传的一律忽略；
2. **包成员原样保存**：`content` 与 `content_b64` 逐字节 round-trip（二进制也要能回写）；
3. **坏组件进 `skipped` 且必须带 reason**；manifest 坏了才是致命（422）；
4. **导出省略凭证**：`auth/headers` 不写进包，并记进 `skipped`——包会旅行，密钥不会。

- 锚点：`src/server/plugin_pkg.cj`、`plugin_admin.cj`；套件 P-02/03/05/06/07。

## 7. 环境

- `Environment.files` 是 `{count, bytes}` **摘要**，不是条目数组；
- `EnvironmentFileEntry` 用 **`dir: bool`**，不是 `type: string`；
- `Harness.environment` 是 **string**：没有就不写键（写 `null` 违反 schema）；
- build 后 `chmod -R a-w` mount；PUT 前临时 `u+w`——**只读是真的只读**；
- `activate` 是「把旧版快照重新铺盘」，不是只改指针。

## 8. 记忆

- `written_by` 一律服务端盖章（客户端传的丢弃）；`trust = untrusted`；
- 修订**追加版本**，旧版本保留「当时的世界」（第一版没有 `valid_to`）；
- 召回只看自己与子树（`depth: 0` 只看自己），**从不向上**；不支持的信号必须进 `degraded`；
- prime：standing 记录 newest-first；预算按 token（本仓 1 条记 1 token），预算不够也保留最新一条；
- 时序事实（`holds: one`）：
  | 新值相对旧值 | 结果 |
  |---|---|
  | 同一时刻 | `conflicts` + 双向 `contradicts`，不结束任何一边 |
  | 更晚 / 落在区间内 | 结束「T 时刻仍成立」的值（`closed`），被结束者追加 provider 版本（`valid_to`、`on_behalf_of`） |
  | 更早 | 自己结束于下一个开始，不结束任何东西 |
  `closed`/`conflicts` **只出现在写应答**，不存储。

## 9. 一致性套件的脾气

- **skip 从不等于 pass**；`conformant` 要求 skip = 0；
- 检查会**直接遍历 JSON 键名**找凭证形状字段（`auth/headers/env/token/...`）——视图里不要放配置；
- 集合形状要精确：`detail.supported` 必须是数组、`skipped` 必须是 `[]` 不是缺省；
- 报告带 `suite_version`；**失败也要落盘**（`scripts/conformance.sh` 已处理：先吞退出码、落盘、再按套件码退出）；
- SUT 需要的「外部世界」一律本地化：MCP fixture 跑在 SUT 进程内（port+1），registry 走注入——CI 不依赖公网。

## 10. 仓颉实现坑（这个仓真的踩过）

| 坑 | 正确做法 |
|---|---|
| `match (r.peek()) { case Some(String) => ... }` 里大写标识符被当**变量绑定**，分支永远命中 | 用枚举限定名（`JsonToken.JsonString`），字符串判别写字面量 |
| `match (s) { case SOME_CONST => ... }` 里的 `public const String` 同样被当**变量绑定**，首个分支永远命中 | 字符串判别一律 `if (s == SOME_CONST)`；match 只用于枚举/模式 |
| `type` 是关键字 | 字段名改 `recordType` 或用反引号原始标识符 |
| 没有三元运算符 | 用 `if (cond) { a } else { b }` |
| `ArrayList` 没有 `sort` / 对元组的 `contains` | 手写选择排序/比较；或用数组 + 手写循环 |
| `Option` 没有 `unwrapOr` | `match` 或 `.map(...)` 后自己收 |
| `String.fromUtf8` 遇非法 UTF-8 序列会抛 | 二进制不要走字符串路径（multipart 的已知限制） |
| `String.size` 是字节数 | 按字符截断先 `toRuneArray()` |
| import 是**文件级**的 | 新文件要自己 import（同一包也不共享） |
| 子包测试二进制链接 `-lstdx.crypto.digest` 会失败 | 依赖网络的测试放根包（`src/*_test.cj`） |
| `JsonWriter` 结构状态是严格的 | 先 `startObject()` 再 `writeName()`；片段拼接用独立 writer 再拼 |
