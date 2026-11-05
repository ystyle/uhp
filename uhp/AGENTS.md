# uhp（SDK 成员）级约定

> 本文件约束 SDK 成员（monorepo 的 `uhp/` 目录）。monorepo 布局与产品级命令见 [../AGENTS.md](../AGENTS.md)，
> 工作区通用约定见 [../../AGENTS.md](../../AGENTS.md)；冲突时以本文件为准（成员内更具体）。

## 1. 定位与边界

UHP 是 **HTTP/1.1 + JSON(REST) + SSE** 的协议，不是 JSON-RPC。本仓交付协议面（类型、序列化、错误映射、
能力门控、状态机、SSE 事件通道、存储接缝），**不实现 harness 本身**：

> SDK 负责「说得对、答得对」，不负责「干得好」。agent 循环、模型调用、工具执行属于消费方。

这条边界决定：不要在本成员里塞容器编排、模型 SDK、真实 base 适配器；它们通过 `HarnessDriver` 接缝接入。
真实适配器是**同级 workspace 成员**（`uhp-opencode/`、`uhp-acp/`），不发布、不进 SDK 制品。

## 2. 工具链与命令

仓颉 **1.2.0**（`cjvs` 管理）。每个 shell 先加载环境：

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
```

| 目的 | 命令 |
|---|---|
| 一条命令验证（编译 + 单测） | `bash scripts/test.sh` |
| 等价手工 | `cjpm build -j 8` + `cjpm test -j 8 --no-progress` |
| 生成物是否最新（CI 闸门） | `python3 tools/gen_types.py --check` |
| 制品与 manifest 是否一致（CI 闸门） | `python3 tools/check_schema_sync.py` |
| 跑单个用例 | `cjpm test --filter '*keyword*'`（**通配符不是正则**：顶层 `@Test func` 用 `'*x*'`，`@Test class` 才用 `'Cls.*'`） |

- 判构建成功看日志里的 `cjpm build success` / `cjpm test success`，**不要用管道取 `$?`**（工作区踩过）。
- 本成员是 workspace 的单模块成员：单独验证用 `cjpm test -j 4`；产品级（三成员）用根目录 `bash scripts/test.sh`。
- 并发跑 `cjpm build/test` 会撞坏共享 `target/`（症状是链接错误/包版本不兼容）；先 `rm -rf target/release/<依赖包>` 再试，别改代码。

## 3. 目录与依赖方向（硬规则）

`src/types/` 内部层级（`types.cj` 的注释是权威）：

```
codec  <-  base  <-  generated  <-  handwritten
```

- `codec/`：纯序列化原语（`extras` 未知字段保真、`raw` 自由 JSON 原文）。只依赖 std 与 `stdx.encoding.json.stream`。
- `base/`：生成器跳过、但语义必须手写的基础类型（`Capabilities`：16 键、缺省=false、服务端全写）。
- `generated/`：**只允许 `tools/gen_types.py` 写**。不手改；要改行为就改生成器 + 重跑。
- `handwritten/`：schema 表达不了的手写块（事件联合、OutputItem 联合、错误码映射、mapping、invariants）。
- `root.cj` / `types.cj`：只做 `public import`，不承载实现。

**禁止**：`types`（含其子包）import `stdx.net.http` / `transport` / `server` / `client`；
传输层之后按 `transport → server → types` 单向依赖。用 CI grep 守住这条（拆分触发条件见设计 §3.2）。

## 4. 序列化契约（不可协商）

1. **手写** `toJson(JsonWriter)` / `static fromJson(JsonReader)`，实现
   `JsonSerializable & JsonDeserializable<T>`。仓颉没有 JSON 派生；固定结构不许用 DOM 手工取值。
2. **未知字段必须保真**：一律用 `uhp.types.codec` 的
   `fromJsonObjectWithExtras(r, handlers, extras)` + `writeExtras(w, extras)`；
   `Extras = HashMap<String, String>`（键 → 原始 JSON 文本）。
   契约是 **GET→PUT 不丢未知键**（上游 153 个对象节点全部 `additionalProperties: true`）。
   测试锚点：`src/types/base/capability_test.cj` 的未知能力键往返用例。
3. **未知枚举值 / 未知事件类型必须有兜底变体**（`Unknown(...)` / `Vendor(String)`）。
   用 `match` 穷尽、没有兜底的 enum 会在上游加值时直接 panic。
4. **`absent ≠ null ≠ 空`**：可空字段用 `Option<T>`；协议要求「键必须存在、值可为 null」的字段，`None` 时也要写 `null`；
   「空数组」有语义时（如 `skipped`）必须写 `[]`，不能省略。
5. **手写层不重复生成对象的 JSON 键名**：生成对象（Harness / Response / Memory…）的字段名与序列化只来自 `generated/`。
   目前 `tools/gen_types.py` 的 `SKIP` 集合有三个，理由各不相同，**新增 SKIP 必须在此登记**：
   - `Capabilities`（`base/capability.cj`）：schema 无法表达「16 个布尔必须全部写出 / 缺省 false」；
   - `Event`（`handwritten/event.cj`）：schema 里没有 discriminated union，手写 `UhpEvent` 独占；
   - `ErrorEnvelope`（`handwritten/error.cj`）：信封语义（sanitize、重试分类、6 键必写含 null）属行为，schema 表达不了。
   生成层保留 `ErrorObject` 供 `Response.error` 引用；**同一协议对象不允许两处维护**。
6. **时间单位必须在类型上区分**：Unix 毫秒 / Unix 秒 / ISO 8601 三种形态并存（设计 §4.4），
   用 `UnixMillis` / `UnixSeconds` 之类的 newtype，**禁止裸 `Int64` 混用**。

## 5. 测试

- 单测放在源码同包、文件名 `*_test.cj`（`src/` 下），便于直接测 internal 成员。
- 新行为必须有测试；**测试发现的问题先加一条会红的用例，再修**。
- 表驱动优先：能力键、错误码映射、事件类型、枚举字面量逐项断言，比零散用例更能锁住契约。
- 真实 HTTP server 的测试（未来 `transport/`）：一律 `port(0) + afterBind + 就绪等待`；
  **不要用固定端口**（并行/占用即红），不要 `sleep` 当代替就绪信号。
- 测试不许依赖网络或付费模型；一致性/端到端用 ScriptedHarness。

## 6. 制品与资源

- `resources/schema/` 里的两个文件是**上游原样拷贝，不可修改**；`manifest.json` 记录 sha256 / 来源 URL / 抓取时间 / 协议版本。
  升级版本 = **换制品 + 更新 manifest + 改生成器/手写层**；不是原地打补丁。
- `tools/`、`resources/`、`scripts/` 进 git 但**不进 cjpm 制品**（`cjpm.toml` 的 `exclude` 已配置）。
- `include`/`exclude` 一律**锚定**（`/src`、`/docs`…）。未锚定 = 任意层级同名，会把 `examples/src` 打进制品或误挡 `src/docs`。
- 发版前必须解包核对制品内容（工作区「发版前必须解包看制品」）。

- tools/、resources/、scripts/、examples/ 进 git 但**不进 cjpm 制品**；*_test.cj 也从制品里排除（exclude 已配置）。
- 一致性 SUT 不在本成员源码树里：examples/conformance_sut/ 是独立 cjpm 项目（path 依赖 uhp），scripts/conformance.sh 负责构建它。

## 7. 文档

- 仓内 `docs/` 固定四件套（已落地）：`design.md`（架构 + 取舍 + 有意不做）、
  `support.md`（端点 × 类 × 能力的支持矩阵，**实现边界的单一事实来源**）、`protocol-notes.md`（SSE 建流顺序、
  时间单位、命名边界等易踩点）、`spec-conflicts.md`（规范自相矛盾的裁定，每条带一个测试锚点）。
- 未实现就写「未实现」；不要写「计划支持」冒充现状，也不要把 TODO 留在源码里冒充实现。

## 8. 发版

- 发布范围由 monorepo 的 `workspace.toml` 决定：**只有本成员（uhp）发中心仓**，两个适配器成员在 exclude 里。
  实际执行：根目录 `bash uhp/scripts/bundle-and-publish.sh`（或 `./scripts/workspace-release.sh publish uhp --exclude uhp_acp,uhp_opencode` 预演到私有仓；中心仓手工 `cd uhp && cjpm bundle --skip-lint && cjpm publish`）。
- 遵循工作区 [docs/publish-scope.md](../../docs/publish-scope.md)：**新包默认不发中心仓**，要发必须显式决策并更新该文件。
- 发版前闸门：`bash scripts/test.sh` 绿 + `python3 tools/gen_types.py --check` 绿 +
  `python3 tools/check_schema_sync.py` 绿 + `LICENSE` 文件补齐 + 制品解包核对。
- 库包不得用 `[replace]`（工作区约定）；版本号在单包仓即产品版本。

## 9. 一致性

- **唯一验收判据是官方 `uhp-conformance` 套件**；未跑套件前不写「conformant」。
- 报告带 `suite_version` 入库 `docs/conformance/`（规划）；**skip 从不等于 pass**。
- CI 与套件一律走 ScriptedHarness，不让付费模型成为 CI 依赖。

## 10. 代码风格与仓颉注意

- 中文注释，写**契约与原因**；不写「谁提的需求 / 谁踩的坑」。
- 枚举比较用 `@Derive[Equatable]` 或手写 `operator ==`（多数枚举不支持裸 `==`/`toString()`）。
- `match` 的 `case` 后不写 `{}`；`case 大写常量 =>` 会被当成变量绑定（字符串判别写字面量）。
- `type` 是关键字：字段名写反引号原始标识符。
- `String` 用 `trimAscii()`；`String.size` 是**字节数**，按字符处理先 `toRuneArray()`。
- 诊断走 `stderr`（`eprintln`）；未来 stdio 场景下 stdout 是协议通道，绝不能打日志。

## 11. 禁止事项（一句话清单）

- ❌ 手改 `src/types/generated/` 或 `resources/schema/`。
- ❌ 在 `src/types/` 里 import 网络/传输/服务端/客户端。
- ❌ 引入 `ystyle::jsonrpc` / cjxt / tang（UHP 不是 JSON-RPC；cjxt 是 UI 框架）。
- ❌ 手写层重复生成对象的 JSON 键名/序列化（例外见 §4.5）。
- ❌ 用固定端口起测试服务；用 `sleep` 等就绪。
- ❌ 把「跑通 build」当「功能完成」，把 TODO 当实现。
