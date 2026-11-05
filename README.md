# uhp-cj

仓颉（Cangjie）语言实现的 [Unified Harness Protocol (UHP)](https://unifiedharnessprotocol.org/spec/2026-10-19) SDK ——
协议版本 **2026-10-19**。

UHP 定义「产品如何通过 HTTP 驱动一个完整的 agent harness」：选择与配置 harness、发任务、跟随流式进度、
续会话、取消、处理错误与文件、取回结果。本仓交付 **协议面 + 服务端骨架**：

- 说对：类型、序列化、错误映射、能力门控；
- 答对：状态机、SSE 事件通道、幂等、存储接缝。

**不交付 harness 本身**（agent 循环、模型调用、工具执行），那是消费方的职责；
本仓只提供 `HarnessDriver` 接缝与测试/一致性用的 ScriptedHarness（规划中）。

它不是 JSON-RPC 框架：协议是 HTTP/1.1 + JSON(REST) + SSE，与工作区的 mcp-cj / a2a-cj / acp-cj 不同形。

## 当前状态

**M0（骨架 + 类型层）进行中。** 明确区分「已经能用」与「还没写」：

| 部分 | 状态 | 说明 |
|---|---|---|
| cjpm 工程（单模块包 `uhp`） | ✅ | `cjpm build` 可过；制品 `include`/`exclude` 已锚定 |
| 上游制品 vendor + manifest + 校验脚本 | ✅ | `resources/schema/` + `tools/check_schema_sync.py` |
| 类型层 `src/types/` | 🚧 进行中 | `generated/` 由 `tools/gen_types.py` 生成；手写层（事件联合 / 错误码 / 不变量）尚未收口 |
| 未知字段保真 codec（`Extras`） | ✅ | GET→PUT 不丢未知键，有单测锚点 |
| 能力发现（`Capabilities` 16 键 + 一致性类自洽） | ✅ | 缺省=false、服务端全写 16 键 |
| 传输层 / 客户端 / 服务端 | ❌ 未开始 | `src/transport`、`src/client`、`src/server` 尚为规划目录 |
| 官方一致性套件接入 | ❌ 未接入 | 未接入前**不声称 conformant** |

> 目前能做的只有：编译、跑类型层单测。**不可用于任何真实链路。**

## 目录

```
uhp-cj/
├── cjpm.toml               # 单模块包 uhp；static；link-option 带 stdx.crypto.digest
├── cjpm.lock
├── resources/schema/       # 上游制品原样拷贝（不可改）+ manifest.json（sha256/来源/版本）
├── tools/                  # CI 脚本：进 git，不进制品
│   ├── check_schema_sync.py  # 制品 sha256 + $defs/Event 交叉校验
│   ├── gen_types.py          # 生成 src/types/generated/（带 --check）
│   └── overlay/              # 生成器的手写补丁（规划）
├── scripts/test.sh         # 本仓一条命令验证：环境 + build + test
├── docs/                   # 规划：design / support / protocol-notes / spec-conflicts / roadmap
└── src/
    ├── root.cj             # package uhp：只做 public import，不承载实现
    ├── types/
    │   ├── types.cj        # 聚合入口（只做 public import）
    │   ├── codec/          # 序列化原语：extras（未知字段保真）/ raw（自由 JSON 原文）
    │   ├── base/           # 生成器跳过的手写基础类型（如 Capabilities）
    │   ├── generated/      # 生成物：只允许 tools/gen_types.py 写
    │   └── handwritten/    # schema 表达不了的手写块（联合 / 错误码 / 不变量）
    ├── transport/          # 规划：HTTP 装配 / SSE 服务端 / SSE 客户端 / 路由
    ├── server/             # 规划：状态机 / 事件通道 / 存储接口 / 能力门控 / ScriptedHarness
    ├── client/             # 规划：发现 / 调用 / 流消费 / 错误映射 / 重试
    └── examples/           # 规划：可执行 conformance SUT
```

## 构建与测试

前置：仓颉 **1.2.0**（`cjvs` 管理）+ stdx 环境变量。

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
bash scripts/test.sh
```

等价于 `cjpm build -j 8` + `cjpm test -j 8 --no-progress`；任一步失败脚本即非零退出。

CI 闸门（结构漂移，与 build/test 分开跑）：

```bash
python3 tools/check_schema_sync.py    # 制品 sha256 / $defs=92 / Event.type.examples=18
python3 tools/gen_types.py --check    # 生成物是否最新（不一致退出码 1）
```

最近一次本地验证（2026-11-05，本机）：`scripts/test.sh` 绿、`check_schema_sync.py` 退出码 0、
`gen_types.py --check` 退出码 0。

## 协议制品（不可变）

`resources/schema/` 里的两个文件是上游 **原样拷贝**，不得修改：

| 文件 | 上游 URL |
|---|---|
| `uhp-2026-10-19.openapi.yaml` | https://unifiedharnessprotocol.org/schema/uhp-2026-10-19.openapi.yaml |
| `uhp-2026-10-19.schema.json` | https://unifiedharnessprotocol.org/schema/uhp-2026-10-19.schema.json |

`manifest.json` 记录 sha256、来源 URL、抓取时间与协议版本。版本升级的流程是
**换制品 + 更新 manifest + 改生成器/手写层**，不是在原文件上打补丁——
「本仓实现的是 2026-10-19」这句话必须能被 sha256 验证。

## 设计文档

仓内 `docs/` 尚未落地（规划：`design.md` / `support.md` / `protocol-notes.md` /
`spec-conflicts.md` / `roadmap.md` / `conformance/`）。
当前设计稿在工作区：`../docs/plans/2026-11-05-uhp-cj-sdk.md`
（决策 D1–D14、规范裁定表、端点总账、真实 harness 选型）。

## 依赖边界

- 不依赖 `ystyle::jsonrpc`（UHP 不是 JSON-RPC），不依赖 cjxt / tang。
- 传输层（规划）直接用 `stdx.net.http`；`link-option = "-lstdx.crypto.digest"` 是 TLS 链接的硬要求。
- 当前 `cjpm.toml` 无第三方依赖；新增依赖必须先改设计决策（D4）并同步本文件与 AGENTS.md。

## 许可证

`MulanPSL-2.0`（见 `cjpm.toml` 的 `license` 字段）。`LICENSE` 文件尚未加入仓库，发布前补齐。
