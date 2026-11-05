# 三份真相的裁定表

> 实现 UHP 有三份来源：**prose（13 章正文，行为权威）**、**openapi.yaml（结构权威）**、
> **schema.json（仅 `$defs`，交叉校验用）**，外加**一致性套件（唯一验收判据）**。
> 它们并不总一致。本文是这四者的**单一裁定处**：每条冲突记「裁定 + 落地位置 + 锚点」。
> 新增冲突请按同样格式追加；**裁定必须能被执行**（有代码或测试指向它），否则只是注释。

裁定总原则：**结构看 openapi、行为看 prose、验收看套件；三者冲突时在这里记一条裁定 + 一条测试。**

---

## A. 结构类（schema / openapi 表达不了）

### A1. Event 不是 discriminated union

- **冲突**：prose 说「Event 是按 `type` 的 discriminated union」；制品里 `Event.type` 是自由字符串 + 18 个 examples，没有 `oneOf`。
- **裁定**：手写 `UhpEvent` 联合（18 变体 + `Unknown` 兜底），生成器 `SKIP` 注册 `Event`。
  未知事件类型**必须**能被解析并原样转发，不能 panic。
- **落地**：`src/types/handwritten/event.cj`；`tools/gen_types.py` 的 SKIP 表（AGENTS §4.5）。

### A2. schema.json 只有 `$defs`，缺 19 个匿名信封

- **冲突**：端点响应形状（`HarnessList`、`SessionList`、`ResponseDeleted`…）在 openapi 里是匿名 inline；
  schema.json 里根本不存在，**不能作为生成输入**。
- **裁定**：生成器只吃 `$defs`；信封手写在 `handwritten/envelopes.cj`（13 个端点信封 + 若干小载荷）。
- **落地**：`src/types/handwritten/envelopes.cj`。

### A3. ErrorEnvelope 不在 `$defs` 里

- **冲突**：错误封套有 `type/code/message/param/detail` 语义（6 种 type、49 个 code、重试分类），
  schema 只描述字段名，描述不了「哪种 code 配哪个 HTTP 状态、哪种可重试」。
- **裁定**：手写信封与码表；生成层保留 `ErrorObject` 供 `Response.error` 引用，**同一对象不两处维护**。
- **落地**：`handwritten/error.cj`。

### A4. Capabilities 无法表达「16 键必须全写 / 缺省 false」

- **裁定**：手写 `Capabilities`：16 个布尔、序列化**全写**、反序列化缺省 false、**不用 `Option<Bool>`**
  （Option 会诱导出第三种分支）。一致性类与能力自洽由发现文档校验。
- **落地**：`src/types/base/capability.cj`；套件 **D-05**。

### A5. `GET /v1/harnesses/{id}/events` 只在 prose 出现

- **裁定**：不实现（不是任何一致性类的必需项，也没有测试）。
- **落地**：`docs/support.md` §3。

### A6. 历史别名 `DELETE /v1/traces/{id}`

- **裁定**：只实现规范显式命名的 `DELETE /v1/sessions/{id}`；别名不实现，避免多一条维护面。
- **锚点**：套件 **F-08/R-07**（都优先打显式路径）。

---

## B. 行为类（prose 要求，openapi/schema 缺失或相反）

### B1. `UHP-Version` 头必须出现在**每个**响应上

- **冲突**：openapi 只在成功响应声明；prose 说每个响应（含错误）。
- **裁定**：按 prose；`writeJson` / `writeError` 统一补头。
- **锚点**：套件 **V-01**。

### B2. 版本协商对 discovery 同样生效

- **裁定**：`negotiate()` 在路由最前，discovery 也不例外；不支持版本 → 400 + `detail.supported`。
- **锚点**：套件 **V-03**。

### B3. 401 的错误 `type` 必须是 `authentication_error`，403 是 `permission_error`

- **冲突**：openapi 只声明 5 个操作有 401、0 个有 403；错误 type 封闭集合在 prose。
- **裁定**：先映射凭据/权限失败再谈具体 code；不笼统用 `invalid_request_error`。
- **锚点**：套件 **A-02**。

### B4. `ResponseIncompleteDetails` 没有 `reason` 字段，但 prose 要求有

- **裁定**：用 `Extras` 承载 `"reason": "max_steps" | "input_required"`——结构以 prose 为准，**不发明新字段**。
- **落地**：`Engine.applyOutcome`；锚点 **T-12/T-13**。

### B5. `Response` 的 `error/usage/store/metadata/previous_response_id` 必须写 `null`

- **冲突**：schema 把它们标成可选；prose 要求键存在、值可为 null。
- **裁定**：生成器 `ALWAYS_EMIT_NULL` 名单；同理 `ErrorObject.param/detail`。
- **落地**：`tools/gen_types.py`。

### B6. 取消是独立终态，但事件类型封闭（没有 `response.cancelled`）

- **裁定**：终态事件发 `response.failed`，`response.status = "cancelled"`；**状态是权威**。
- **锚点**：套件 **C-03**。

### B7. 保留字段 `tools`/`include` 必须「接受 + 忽略 + 可观测」

- **裁定**：接受请求、不执行、把字段名写进 `metadata.ignored_fields`（缺一不可）。
- **锚点**：套件 **T-08/T-09/T-10**。

### B8. `max_step` 预算截断必须 `incomplete`，且 reason 要能看出是预算

- **裁定**：driver 越过或引擎发现轮数超额 → `incomplete(max_steps)`，**绝不 `completed`**；
  轮数以「调用 + 结果」配对计。
- **锚点**：套件 **T-12**。

### B9. `ask_user` 的问题必须**同时**是 item 与 message 文本

- **裁定**：`output` 里落三样：`function_call(ask_user)`、承载问题文本的 `message`、`input_request` item；
  答案走 `input_response` 续跑；选项外 422、过期/重复 409。
- **锚点**：套件 **T-13**。

### B10. secret 答案不得出现在任何客户端可读位置

- **裁定**：只进 `TurnContext.answers`；`input_items` 里对 secret 省略 `answer`。
- **锚点**：套件 **T-14**。

### B11. 会话分享：openapi 没有 DELETE，prose §5 有；且 §5 说「体可选，无体即发布」

- **裁定**：实现 `POST/GET/DELETE /v1/sessions/{id}/share`；POST 体可选（无体=发布，`{"enabled":false}`=吊销是超集）。
  吊销按**会话**（该会话所有已发链接一起失效）；删会话连带失效。
- **锚点**：套件 **R-01..R-08**。

### B12. 会话列表必须有显式「末页」标记

- **裁定**：`GET /v1/sessions` 总带 `next_cursor`（末页为 `null`），不让客户端靠「本页不满」猜。
- **锚点**：套件 **X-02**。

### B13. `/pdf` 预览不实现时必须是 501 `preview_unavailable`

- **裁定**：返回结构化 501，**不返回坏/空 PDF**。
- **落地**：`http.cj` 容器文件路由。

---

## C. 可选能力章节的裁定

### C1. 插件派生值不是客户端的输入

- **冲突**：schema 的 Plugin 带 manifest/mcpServers/skills/skipped 字段，看起来像可写；prose 说这些是**服务端派生**。
- **裁定**：每次写/读都从包重算；客户端回传的派生值一律忽略（PUT 往返只信 `files`，或按 name 匹配已装包）。
- **锚点**：套件 **P-02/P-05**。

### C2. 插件导出必须省略凭证且记进 `skipped`

- **裁定**：导出包里的 `mcp.json` 不含 `auth/headers`，但要在 `skipped` 里点名被省略的服务器。
- **锚点**：套件 **P-06**。

### C3. `Environment.files` 是摘要对象，不是条目数组；条目用 `dir: bool`

- **冲突**：直觉会写成数组/字符串类型；schema 明确是 `{count,bytes}` 与 `dir: bool`。
- **裁定**：按 schema（两处都曾写错、被套件当场抓住）。
- **锚点**：套件 **EN-01/EN-02**。

### C4. `Harness.environment` 是 string：没有就不写键

- **裁定**：写 `null` 违反 schema；缺省 = 不写。
- **锚点**：套件 **EN-05**。

### C5. 未 build 的环境必须在任务开始**前**拒绝

- **裁定**：`409 environment_not_ready`，而不是让任务跑一半才失败。
- **锚点**：套件 **EN-05**。

### C6. 记忆 `content` 输入可以是 string，但存储与输出永远是 part 列表

- **裁定**：写时把 string 规范化成 `[{type:"text",text}]`；读永远是列表。
- **锚点**：套件 **ME-02**。

### C7. 记忆 `written_by` 由服务端盖章

- **裁定**：客户端传的值丢弃；盖章成 `{kind:"member",type:"agent",id:<principal>}`。
- **锚点**：套件 **ME-02**。

### C8. 记忆 `closed`/`conflicts` 只在写应答出现，**不存储**

- **裁定**：存储的记录里不得有这两个键；GET 记录不出现。
- **锚点**：套件 **ME-11**。

### C9. 记忆 provider 的能力声明是契约，不是装饰

- **裁定**：`holds`、`graph.entities`、`recall.signals`、`content.media` 声明什么就实现什么；
  不实现的如实声明（套件据此跳过），**不做假数据**。本仓最终三项都实现（holds/graph/query+text），
  只有文件媒体声明为 `text/*`（二进制 multipart 未支持，见 support.md §4）。
- **锚点**：套件 **ME-04/ME-10/ME-11/ME-09**。

### C10. prime 的预算单位没有规定

- **裁定**：本仓按「一条 standing 记录 = 1 token」计；预算再小也保留最新一条并标 `truncated`。
- **锚点**：套件 **ME-13**。

### C11. 包检查（EN-09）是可选端点，需要外部 registry

- **裁定**：SDK 只提供**可注入的查询接缝**，由宿主回答；未注入时按根路径 404（规范允许不实现）。
  SUT 注入本地 registry，使该检查在**不依赖公网**的前提下被真实测到。
- **落地**：`Engine(packageChecker: ...)`；锚点 **EN-09**。

---

## D. 一致性与文档纪律

1. **skip 从不等于 pass**；`conformant` 要求 skip = 0。本仓三档均零 skip。
2. 报告必须带 `suite_version` 入库 `docs/conformance/`；**失败也要落盘**。
3. 新增裁定必须同时更新：本文、`support.md`（若涉及边界）、以及至少一条测试或套件检查锚点。
