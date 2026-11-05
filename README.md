# uhp

[UHP（Unified Harness Protocol）](https://unifiedharnessprotocol.org/spec/2026-10-19) 的仓颉 SDK 与真实 harness 适配器。

这是**一个产品、三个成员**的 monorepo：

| 成员 | 角色 | 发布 |
|---|---|---|
| [uhp/](uhp) | UHP SDK：协议面（类型/序列化/错误/能力/事件）+ 服务端骨架 + `HarnessDriver` SPI；Client；可选能力（plugins/environments/memories） | ✅ 中心仓 |
| [uhp-opencode/](uhp-opencode) | opencode 2.x 的 `HarnessDriver` 参考实现（HTTP + SSE） | ❌ 不发布 |
| [uhp-acp/](uhp-acp) | ACP（Agent Client Protocol）通用 `HarnessDriver` 参考实现（stdio JSON-RPC），一次覆盖 dsh / pi / claude-code 这类 agent | ❌ 不发布 |

两个适配器是**参考实现**：它们验证 SDK 的 `HarnessDriver` 接缝对真实 agent 可用；社区可以按同一接缝维护自己的适配器，不需要改 SDK。

## 结论一句话

SDK 是 **HTTP/1.1 + REST/JSON + SSE** 的协议库，**不是 JSON-RPC 框架**。
官方一致性套件是三档唯一验收判据：core 41/41、extended 50/50、**full 104/104，全部 CONFORMANT**。

## 快速开始

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"

bash scripts/build.sh        # 构建三个成员
bash scripts/test.sh         # 构建 + 全部测试（SDK 142 + opencode 11 + ACP 9 = 162）
bash uhp/scripts/conformance.sh full   # 官方一致性套件（需要 .uhp-research 里的套件）
```

真实链路冒烟（需要本机 opencode v2 与可用模型）：

```bash
bash uhp-opencode/scripts/real-smoke.sh   # UHP 任务 -> opencode 用 shell 工具 -> 输出探针
bash uhp-acp/scripts/real-smoke.sh        # UHP 任务 -> opencode acp -> 输出 ACP-OK
```

## 文档

- SDK 支持矩阵 / 实现边界（单一事实来源）：[uhp/docs/support.md](uhp/docs/support.md)
- SDK 架构与取舍：[uhp/docs/design.md](uhp/docs/design.md)
- 规范自相矛盾裁定（每条带测试锚点）：[uhp/docs/spec-conflicts.md](uhp/docs/spec-conflicts.md)
- 一致性报告：[uhp/docs/conformance/](uhp/docs/conformance/)
- 各适配器的映射表与「已知限制（如实）」：成员目录下的 README

## 发布

只有 SDK 成员返回中心仓（" + Q + "uhp" + Q + "）；两个适配器是参考实现，不发布。

## 发布

只有 SDK 成员发中心仓（uhp）；两个适配器是参考实现，不发布。

## 仓库约定

- 根 `AGENTS.md`：monorepo 布局与命令；
- `uhp/AGENTS.md`：SDK 成员的硬规则（生成器只写 generated、类型层分层、序列化契约、发版闸门）；
- `workspace.toml`：产品版本（lockstep，当前只有 `uhp` 发布）与发布成员清单。
