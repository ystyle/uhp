# uhp-opencode

opencode 2.x 的 UHP `HarnessDriver` 适配器：把 opencode 的 session/prompt/event 翻译成 UHP 的 TurnSink / TurnOutcome。

## 特性

- 文本 / 推理流式输出；工具调用与结果；用量统计
- 工具批准（permission）与结构化提问（form）→ UHP 两轮问答
- 取消 → opencode interrupt；三个终态映射
- 输入文件 → prompt `files[]`；改动文件（session diff）→ UHP 产物
- 测试不依赖网络与模型；真实链路可一键冒烟

## 示例

```cangjie
import uhp_opencode.*

let driver = OpencodeDriver(OpencodeOptions(
    "http://127.0.0.1:4765",          // opencode serve 地址
    "/path/to/workspace",             // opencode location.directory
    password: "splice-token",
    model: Some(("deepseek-v4.1-flash-free", "opencode"))))
```

```bash
bash scripts/test.sh          # 11 条测试（同进程假 opencode）
bash scripts/real-smoke.sh    # 真实链路冒烟
```

## 文档

- 使用教程：[docs/guide.md](docs/guide.md)

## 许可证

MulanPSL-2.0。

## 设计文档

[../uhp/docs/design.md](../uhp/docs/design.md)
