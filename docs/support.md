# 支持矩阵：端点 × 类 × 能力

> **这是实现边界的单一事实来源。** 代码改了先改这张表；表里说「未实现」的不要在外面对人声称支持。
> 一致性状态：suite `2026.10.19.post5`，**core 41/41、extended 50/50、full 104/104 全 CONFORMANT**。

## 1. 能力开关（16 键，服务端全写，缺省 false）

| 能力 | 核心 | 扩展 | 完整 | 本仓 | 说明 |
|---|---|---|---|---|---|
| `streaming` | ✅ 必需 | ✅ | ✅ | ✅ true | SSE 任务流 + `cursor` 重放 |
| `sessions` | ✅ 必需 | ✅ | ✅ | ✅ true | 会话归属与并发（`session_busy`） |
| `cancellation` | ✅ 必需 | ✅ | ✅ | ✅ true | 取消是独立终态 `cancelled` |
| `files_input` | — | ✅ 必需 | ✅ | ✅ true | 任务内联文件 / `file_id` 引用 |
| `files_output` | — | ✅ 必需 | ✅ | ✅ true | 产物登记（driver 声明）与下载 |
| `session_listing` | — | ✅ 必需 | ✅ | ✅ true | `GET /v1/sessions`（显式 `next_cursor`） |
| `harness_management` | — | — | ✅ 必需 | ✅ true | create/update/delete + 技能包 |
| `harness_retirement` | 可选 | 可选 | 可选 | ❌ false | 删除 harness 时**保留**会话（套件 F-09 接受） |
| `session_sharing` | 可选 | 可选 | 可选 | ✅ true | 发布只读视图 + 吊销 |
| `idempotency` | 可选 | 可选 | 可选 | ❌ false | 响应级 `Idempotency-Key` 未实现（harness 级已实现，见下） |
| `harness_idempotency` | 可选 | 可选 | 可选 | ✅ true | 创建 harness 的幂等键（同 key 不同体 → 409） |
| `input_requests` | 可选 | 可选 | 可选 | ✅ true | `ask_user` → `incomplete/input_required` |
| `input_history` | 可选 | 可选 | 可选 | ❌ false | `input_items` 只含客户端提交的输入（不含 secret 答案） |
| `plugins` | 可选 | 可选 | 可选 | ✅ true | Agent Plugins 包校验/派生/组合/导出 |
| `environments` | 可选 | 可选 | 可选 | ✅ true | 环境对象/build/版本/只读挂载/包检查 |
| `memories` | 可选 | 可选 | 可选 | ✅ true | 树/记录/召回/prime/图/时序事实 |

一致性类与能力的自洽由发现文档与套件 D-05 校验；本仓的类是构造参数（`ConformanceClass`），能力按类自动打开。

## 2. 端点矩阵

列含义：**类** = 从哪个一致性类开始要求；**能力** = 额外的能力门槛；**状态** = 本仓实现情况。

### 2.1 发现与协商（全部类）

| 方法 路径 | 类 | 能力 | 状态 | 备注 |
|---|---|---|---|---|
| `GET /v1/uhp` | core | — | ✅ | **免鉴权**；每个响应都带 `UHP-Version` |
| `GET /v1/models` | core | — | ✅ | 全局模型目录 |
| `GET /v1/harnesses` | core | — | ✅ | 列表 + 管理视图（同一渲染） |
| `GET /v1/harnesses/{id}` | core | — | ✅ | 404 `harness_not_found` |
| `GET /v1/harnesses/{id}/models` | core | — | ✅ | 该 harness 的模型 |

### 2.2 任务与响应（全部类）

| 方法 路径 | 类 | 能力 | 状态 | 备注 |
|---|---|---|---|---|
| `POST /v1/responses` | core | — | ✅ | 非流式；`stream:true` 走 SSE；`background:true` 立即回 `in_progress` |
| `POST /v1/responses`（`previous_response_id`） | core | — | ✅ | 会话延续 |
| `POST /v1/responses`（`input_response`） | core | input_requests | ✅ | 回答问题；选项外 422、过期/重复 409 |
| `POST /v1/responses`（`max_step`） | core | — | ✅ | 超额 → `incomplete(max_steps)` |
| `GET /v1/responses/{id}` | core | — | ✅ | 404 `response_not_found` |
| `DELETE /v1/responses/{id}` | core | — | ✅ | 删除存储的响应 |
| `GET /v1/responses/{id}/input_items` | core | — | ✅ | **secret 答案不出现** |
| `POST /v1/responses/{id}/cancel` | core | cancellation | ✅ | 幂等：终态再取消不改状态 |

### 2.3 会话（extended 起的部分）

| 方法 路径 | 类 | 能力 | 状态 | 备注 |
|---|---|---|---|---|
| `GET /v1/sessions` | extended | session_listing | ✅ | `limit` + 显式 `next_cursor`（末页 null） |
| `GET /v1/sessions/{id}` | extended | session_listing | ✅ | 含 `environment`（若任务在环境里跑） |
| `GET /v1/sessions/{id}/turns` | extended | session_listing | ✅ | item 形状：`id` + `status` |
| `DELETE /v1/sessions/{id}` | full | — | ✅ | 级联：响应、产物、分享视图一起失效 |
| `POST /v1/sessions/{id}/cancel` | core | cancellation | ✅ | 取消该会话进行中的响应 |
| `GET /v1/sessions/{id}/files` | extended | files_output | ✅ | 会话产物列表 |
| `POST /v1/sessions/{id}/share` | full | session_sharing | ✅ | **体可选**：无体=发布；`{"enabled":false}`=吊销 |
| `GET /v1/sessions/{id}/share` | full | session_sharing | ✅ | 读回与 POST 一致的 URL |
| `DELETE /v1/sessions/{id}/share` | full | session_sharing | ✅ | 吊销**该会话所有**链接 |
| `GET /v1/shared/{token}` | full | session_sharing | ✅ | **免鉴权、只读**；写方法一律不命中 |

### 2.4 文件与产物

| 方法 路径 | 类 | 能力 | 状态 | 备注 |
|---|---|---|---|---|
| `POST /v1/files` | extended | files_input | ✅ | multipart；文本附件（二进制解析见「已知限制」） |
| `GET /v1/containers/{cid}/files/{fid}/content` | extended | files_output | ✅ | `nosniff`；容器/principal 双键校验，越界 404 |
| `GET /v1/containers/{cid}/files/{fid}/pdf` | extended | files_output | ✅ | 501 `preview_unavailable`（不生成坏 PDF） |

### 2.5 harness 管理（full）

| 方法 路径 | 类 | 能力 | 状态 | 备注 |
|---|---|---|---|---|
| `POST /v1/harnesses` | full | harness_management | ✅ | 未知 base → 422 + `detail.supported`；`Idempotency-Key` |
| `PUT /v1/harnesses/{id}` | full | harness_management | ✅ | **base 不可改**；未知环境 404 |
| `DELETE /v1/harnesses/{id}` | full | harness_management | ✅ | 会话保留（`sessions: "kept"`） |
| `GET /v1/harnesses/{id}/skills/{name}/files` | full | harness_management | ✅ | 嵌套 + `content_b64` 原样 |
| `GET /v1/harnesses/{id}/plugins/{name}/files` | full | plugins | ✅ | 包成员原样 round-trip |
| `GET /v1/harnesses/{id}/plugin` | full | plugins | ✅ | 导出：省略凭证并记 `skipped` |

### 2.6 environments（能力 `environments`）

| 方法 路径 | 状态 | 备注 |
|---|---|---|
| `GET /v1/environments` / `POST /v1/environments` | ✅ | 创建：`henv_` id、slug、mount 绝对路径 |
| `GET /v1/environments/{id}` / `DELETE /v1/environments/{id}` | ✅ | 404 `environment_not_found`；删除连带目录 |
| `PUT/GET/DELETE /v1/environments/{id}/files/{path...}` | ✅ | 路径逃逸（`..`、`..%2F`）400 |
| `GET /v1/environments/{id}/files` | ✅ | 树：`{path, dir, bytes?}`（**`dir` 是布尔**） |
| `POST /v1/environments/{id}/build` | ✅ | `{version}`；build 后 `chmod -R a-w` mount |
| `GET /v1/environments/{id}/builds/{n}` | ✅ | `{status, packages[], files, bytes}` |
| `GET /v1/environments/{id}/versions` | ✅ | `{active, versions:[{version,status}]}` |
| `POST /v1/environments/{id}/versions/{n}/activate` | ✅ | 回滚 = 旧版快照重新铺盘；未知版本 409 |
| `GET /v1/environments/{id}/harnesses` | ✅ | 指向该环境的 harness |
| `GET /v1/environments/packages/check` | ✅（可注入） | 未注入 registry 接缝 → 404（规范允许不实现） |

### 2.7 memories（能力 `memories`）

| 方法 路径 | 状态 | 备注 |
|---|---|---|
| `GET /v1/memories/providers` | ✅ | 声明 `recall.signals=[query,text]`、`graph.entities=records`、`holds=true` |
| `GET /v1/memories`（`?parent`/`?granted=true`） | ✅ | 树浏览；granted = 自己进入的记忆 |
| `POST /v1/memories` | ✅ | parent 存在性校验、ancestors 继承、provider 继承 |
| `GET/PUT/DELETE /v1/memories/{id}` | ✅ | PUT 移动子树；移到后代下 422 |
| `POST/GET /v1/memories/{id}/records` | ✅ | 写：`written_by` 盖章、`trust=untrusted`、part 校验 |
| `GET/PATCH/DELETE /v1/memories/{id}/records/{rid}` | ✅ | PATCH 追加版本；DELETE = 遗忘（仍可读） |
| `GET /v1/memories/{id}/records/{rid}/history` | ✅ | 旧版 `superseded`、新版 `active` |
| `POST /v1/memories/{id}/erase` | ✅ | `{erased, unreachable}`；擦除后 404 |
| `POST /v1/memories/{id}/recall` | ✅ | 子树/depth 0/degraded/contradicts 双带 |
| `GET /v1/memories/{id}/prime` | ✅ | standing newest-first、token 预算、truncated |
| `POST /v1/memories/{id}/graph` | ✅ | 无向遍历 hops；节点带 `record`+`memory` |

## 3. 明确不实现

| 端点/能力 | 理由 |
|---|---|
| `GET /v1/harnesses/{id}/events` | 只在 prose 出现过一次，非任何一致性类必需（spec-conflicts #5） |
| `DELETE /v1/traces/{id}` 等历史别名 | 规范另给了显式路径；实现别名只增加维护面 |
| 响应级 `Idempotency-Key`（`idempotency` 能力） | 未实现；发现文档如实报 false，套件不测 |
| `harness_retirement` | 未实现；发现文档如实报 false，删除 harness 保留会话 |
| 断线后按 cursor 续流 | 未实现；实时流由服务端通道按游标推完，重连需重新发起任务 |
| 二进制 multipart 的严格解析 | 当前解析走 UTF-8 文本路径；文本附件够用，二进制需要字节级 parser（见 §4） |

## 4. 已知限制（不影响一致性结论，但影响使用）

1. **multipart 只可靠处理文本附件**：`POST /v1/files` 对二进制（如 PNG）会 500（`String.fromUtf8` 遇到非法序列）。
   套件 ME-09 因此走「media=text/*」分支（文件上传 500 → 该项按文本路径判定），我们**没有假装支持二进制**。
2. **存储全内存**：进程重启即丢。接缝在 `Engine`，落盘是宿主选择。
3. **环境 mount 在 `<cwd>/.uhp-envs/`**：生产部署应换成持久卷并只读挂载。
4. **插件运行时 MCP 调用依赖 driver**：SUT 内置本地 fixture；真实 base 由适配器实现（opencode 2.x 待接）。

## 5. 怎么验证这张表

```bash
bash scripts/test.sh                    # 139 条单测/行为测试
bash scripts/conformance.sh core        # 41/41
bash scripts/conformance.sh extended    # 50/50
bash scripts/conformance.sh full        # 104/104
```

报告落在 `docs/conformance/<suite_version>-<class>.json`；**失败也会落盘**。
