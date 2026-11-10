# uhp

[UHP（Unified Harness Protocol）](https://unifiedharnessprotocol.org/spec/2026-10-19) 的仓颉实现：一个 monorepo，包含 SDK 与两个开箱即用的 harness 适配器。

## 特性

- **完整协议面**：类型/序列化、错误模型、能力门控、SSE 事件、任务状态机
- **官方一致性套件三档全过**：core 41/41 · extended 50/50 · full 104/104（CONFORMANT）
- **HarnessDriver SPI**：接入任意 agent；自带 opencode 2.x 与 ACP 适配器
- **纯仓颉**：只依赖 stdx，无第三方依赖

## 成员

| 成员 | 说明 |
|---|---|
| [uhp/](uhp) | SDK：客户端 + 服务端骨架 + HarnessDriver 接缝（中心仓 `0.1.0`） |
| [uhp-opencode/](uhp-opencode) | opencode 2.x 适配器（HTTP + SSE，中心仓 0.1.0） |
| [uhp-acp/](uhp-acp) | ACP 通用适配器（stdio JSON-RPC，覆盖 dsh / pi / claude-code，中心仓 0.1.0） |

## 示例

```toml
[dependencies]
  "uhp" = "0.1.0"
```

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"

bash scripts/build.sh   # 构建三个成员
bash scripts/test.sh    # 全部测试（162 条）
```

真实链路冒烟（需要本机 opencode v2 与可用模型）：

```bash
bash uhp-opencode/scripts/real-smoke.sh
bash uhp-acp/scripts/real-smoke.sh
```

## 文档

- SDK API：[uhp/docs/api.md](uhp/docs/api.md)
- SDK 使用教程：[uhp/docs/guide.md](uhp/docs/guide.md)
- 适配器用法：[uhp-opencode/docs/guide.md](uhp-opencode/docs/guide.md) · [uhp-acp/docs/guide.md](uhp-acp/docs/guide.md)

## 许可证

MulanPSL-2.0。

## 设计文档

[uhp/docs/design.md](uhp/docs/design.md)
