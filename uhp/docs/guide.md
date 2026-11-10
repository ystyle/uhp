# uhp 使用教程

从零跑通一个 UHP 服务端，再接一个客户端；最后接入真实 agent。

## 1. 起一个服务端

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
    let server = ServerBuilder().addr("127.0.0.1").port(8471)
        .distributor(uhp.distributor()).build()
    server.serve()
}
```

`GET /v1/uhp` 免鉴权（用于发现与版本协商）；其余请求带 `Authorization: Bearer <token>`。

## 2. 客户端调用

```cangjie
import uhp.client.*
import uhp.transport.*
import uhp.types.generated.*

main() {
    let client = UhpClient("http://127.0.0.1:8471", "dev-token", StdHttpTransport("http://127.0.0.1:8471"))
    client.discover()

    let req = CreateResponseRequest()
req.input = "\"hello\""
    let resp = client.createTask(req)              // 非流式，阻塞到终态
    let stream = client.createTaskStream(req)      // 流式：SSE 事件 + 终态
}
```

## 3. 实现自己的 HarnessDriver（接真实 agent）

`HarnessDriver` 是 SDK 与 agent 之间唯一的接缝：SDK 负责「说得对、答得对」，driver 负责「干得好」。

```cangjie
class MyDriver <: HarnessDriver {
    public func base(): String { "my-agent" }
    public func baseLabel(): String { "My Agent" }
    public func models(): Array<Model> { [] }
    public func capabilities(): HarnessCapabilities { HarnessCapabilities(false, false) }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        // 把 agent 的输出翻译成 sink 调用：
        sink.textDelta("thinking...")
        let callId = sink.toolCall("shell", "{\"command\":\"ls\"}")
        sink.toolResult(callId, "file.txt")
        // 需要人确认时：sink.ask(...) 后返回 Incomplete(InputRequired)，答案在下一轮 ctx.answers
        TurnOutcome.Completed(None)
    }
}
```

仓库内有两个真实实现可参考：[uhp-opencode](../uhp-opencode)（HTTP+SSE）、[uhp-acp](../uhp-acp)（stdio JSON-RPC）。

## 4. 提问 / 续跑 / 文件 / 产物

| 能力 | 客户端做什么 | driver 做什么 |
|---|---|---|
| 向人提问 | 收到 `incomplete` + `input_request` 后，带 `input_response` 再建任务 | `sink.ask(kind, prompt, options)` 后返回 `Incomplete(InputRequired, ...)`；答案在下一轮 `ctx.answers` |
| 文件输入 | `input_file`（data URL）或已上传文件的 `file_id` | 读 `ctx.files: Array<TurnFile>` |
| 产物 | `GET /v1/sessions/{id}/files` 列举、`GET /v1/containers/{cid}/files/{fid}/content` 下载 | `sink.producedFile(name, bytes)` |
| 取消 | `POST /v1/responses/{id}/cancel` | 轮询 `cancel.isCancelled()`，尽快返回 `TurnOutcome.Cancelled` |
| 流式 | `createTaskStream` 消费 SSE | 按顺序 emit（文本 → 工具 → 终态） |

## 5. 错误处理

客户端抛 `UhpError`：`code()`、`httpStatus`、`envelope.retryable`。任务级失败不是异常，是 `Response.status == "failed"` + `error`。

## 6. 一致性验收

```bash
bash scripts/test.sh                 # 单元/行为测试
bash scripts/conformance.sh full     # 官方套件三档（需要 .uhp-research 里的套件）
```
