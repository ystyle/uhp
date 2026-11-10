# uhp-acp

ACP（Agent Client Protocol）的 UHP `HarnessDriver` 适配器：把 ACP 的 session/update 翻译成 UHP 的 TurnSink / TurnOutcome，一次覆盖 `opencode acp`、dsh、pi、claude-code 这类 agent。

## 特性

- 文本 / 推理流式输出；工具调用与结果；三个终态映射
- 权限请求（`request_permission`）与表单提问（`elicitation/create`）→ UHP 两轮问答
- 取消 → `session/cancel`
- 输入文件 → image / text / resource_link 内容块；diff 内容块 → UHP 产物
- 测试用真实 ACP 协议（本仓内置假 agent 子进程），不依赖网络与模型

## 示例

```cangjie
import uhp_acp.*

let driver = AcpDriver(AcpOptions("opencode", args: ["acp"], cwd: "/path/to/workspace"))
```

```bash
bash scripts/test.sh          # 9 条测试（真 ACP 协议 + 假 agent）
bash scripts/real-smoke.sh    # 真实链路冒烟（默认 opencode acp）
```

## 文档

- 使用教程：[docs/guide.md](docs/guide.md)

## 许可证

MulanPSL-2.0。

## 设计文档

[../uhp/docs/design.md](../uhp/docs/design.md)
