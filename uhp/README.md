# uhp

仓颉实现的 [UHP（Unified Harness Protocol）](https://unifiedharnessprotocol.org/spec/2026-10-19) SDK：协议面 + 服务端骨架 + `HarnessDriver` 接缝。已发布中心仓 **0.1.0**。

## 特性

- **协议面完整**：类型/序列化、错误模型、能力门控、SSE 事件、任务状态机
- **客户端**：发现与版本协商、建任务/流式/续跑、SSE 消费、错误映射与重试、幂等键
- **服务端骨架**：路由/鉴权、`EventChannel`（序号 + 重放）、存储接缝、`HarnessDriver` SPI
- **可选能力**：plugins、environments、memories、会话分享、input_requests
- **验收**：官方一致性套件 core 41/41 · extended 50/50 · full 104/104，142 条测试
- **纯仓颉**：只依赖 stdx；未知字段保真，未知枚举/事件有兜底

## 示例

```toml
[dependencies]
  "uhp" = "0.1.0"
```

```cangjie
import std.collection.HashMap
import stdx.net.http.*
import uhp.server.*
import uhp.types.generated.*

main() {
    let driver = ScriptedHarness([ScriptStep.Text("hello")], TurnOutcome.Completed(None))
    let harness = ConfiguredHarness("chrn_1", "Scripted", "scripted", "scripted-model", driver)
    let engine = Engine([harness])
    let tokens = HashMap<String, String>()
    tokens["dev-token"] = "alice"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    ServerBuilder().addr("127.0.0.1").port(8471).distributor(uhp.distributor()).build().serve()
}
```

## 文档

- API：[docs/api.md](docs/api.md)
- 使用教程：[docs/guide.md](docs/guide.md)

## 许可证

MulanPSL-2.0。

## 设计文档

[docs/design.md](docs/design.md)
