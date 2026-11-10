# uhp API

常用公开 API 速查。完整类型定义见 `src/types/`（`generated/` 由协议 schema 生成）。

## 客户端（`uhp.client`）

```cangjie
import uhp.client.*
import uhp.transport.*

let transport = StdHttpTransport("http://127.0.0.1:8471")
let client = UhpClient("http://127.0.0.1:8471", "dev-token", transport)

client.discover()            // GET /v1/uhp（免鉴权），同时完成版本协商
let caps = client.capabilities()
let harnesses = client.harnesses()

let req = CreateResponseRequest()
req.input = "\"hello\""
let resp = client.createTask(req)          // 非流式
let stream = client.createTaskStream(req)  // 流式（SSE）
```

| 方法 | 说明 |
|---|---|
| `discover()` | 发现文档 + 版本协商（结果缓存） |
| `protocolVersion()` / `capabilities()` | 协商出的版本 / 服务端能力 |
| `harnesses()` / `harnessModels(id)` | harness 列表 / 某 harness 的模型 |
| `createTask(req)` / `createTaskWithInput(req, input)` | 建任务（非流式）；后者支持续跑与 `input_response` |
| `createTaskStream(req)` / `createTaskStreamWithInput(req, input)` | 同上，返回 `TaskStream` |
| `getResponse(id)` / `cancelResponse(id)` / `deleteResponse(id)` | 读回 / 取消 / 删除 |

`HttpTransport` 是客户端可替换的传输接口（`send` / `stream`）；`StdHttpTransport` 是 stdx.net.http 实现。
出错抛 `UhpError`：`code()` / `httpStatus` / `envelope`（含 `type`、`detail`、`retryable`）。

## 服务端（`uhp.server`）

```cangjie
import uhp.server.*
import uhp.types.generated.*

let driver = ScriptedHarness([ScriptStep.Text("hello")], TurnOutcome.Completed(None))
let harness = ConfiguredHarness("chrn_1", "Scripted", "scripted", "scripted-model", driver)
let engine = Engine([harness])

let tokens = HashMap<String, String>()
tokens["dev-token"] = "alice"
let uhp = UhpHttpServer(engine, Authenticator(tokens))
let server = ServerBuilder().addr("127.0.0.1").port(8471)
    .distributor(uhp.distributor()).build()
server.serve()
```

| 类型 | 作用 |
|---|---|
| `Engine(harnesses, versions)` | 协议引擎：状态机、事件通道、能力门控、存储 |
| `ConfiguredHarness(id, name, base, defaultModel, driver)` | 一个可被调用的 harness |
| `UhpHttpServer(engine, auth)` + `distributor()` | HTTP 层：路由、鉴权、版本、SSE |
| `Authenticator(HashMap<String,String>)` | Bearer token → principal；`authenticate(headers)` 返回 `Option<Principal>` |
| `HarnessDriver` | 消费方实现的 agent 接缝（见下） |
| `ScriptedHarness(steps, outcome)` | 测试/一致性用确定性 harness |
| `EngineError(code, httpStatus, param, detailJson)` | 引擎级错误（HTTP 层翻译成错误封套） |

### HarnessDriver（实现这个就能接任意 agent）

```cangjie
public interface HarnessDriver {
    func base(): String
    func baseLabel(): String
    func models(): Array<Model>
    func capabilities(): HarnessCapabilities
    func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome
}
```

| 类型 | 字段 / 方法 |
|---|---|
| `TurnContext` | `sessionId`、`input`、`model`、`maxStep`、`mcpServers`、`answers`、`environment` + `environmentMount`、`files: Array<TurnFile>` |
| `TurnFile` | `filename`、`mediaType`、`bytes` |
| `TurnSink` | `textDelta`、`reasoningDelta`、`toolCallArgsDelta`、`toolCall` / `toolResult`、`ask(kind, prompt, options)`、`producedFile(name, bytes)`、`degrade(reason)` |
| `TurnOutcome` | `Completed(usage)` / `Incomplete(reason, usage)` / `Failed(code, message)` / `Cancelled(usage)` |
| `CancelToken` | `cancel()` / `isCancelled()` |
| `HarnessCapabilities` | `hardToolBlock`、`inputRequests`（是否支持向人提问） |

## 类型（`uhp.types`）

- `types.generated`：协议对象（`Response`、`Session`、`File`、`Harness`、`Memory`、`Event`…），由 `tools/gen_types.py` 从上游 OpenAPI 生成。
- `types.handwritten`：事件联合 `UhpEvent`、错误 `ErrorEnvelope`、输出 item 联合等 schema 表达不了的块。
- `types.codec`：`Extras`（未知字段保真，GET→PUT 不丢键）与 `Raw`（自由 JSON 原文）。
- 未知枚举值 / 未知事件有兜底变体（`Unknown(...)` / `Vendor(String)`），不会 panic。

## 传输（`uhp.transport`）

- `HttpTransport`：`send(UhpRequest): UhpResponse`、`stream(UhpRequest): StreamStart`。
- `StdHttpTransport(baseUrl)`：基于 `stdx.net.http` 的实现（TLS 需要 `-lstdx.crypto.digest`）。
