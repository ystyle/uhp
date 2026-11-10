# uhp-opencode 使用教程

把 opencode 2.x 接到 UHP：driver 把 opencode 的 session/prompt/event 翻译成 UHP 的 TurnSink / TurnOutcome。

## 1. 前置：起 opencode

```bash
export XDG_CONFIG_HOME=$PWD/.oc/config XDG_CACHE_HOME=$PWD/.oc/cache
export XDG_DATA_HOME=$PWD/.oc/data XDG_STATE_HOME=$PWD/.oc/state
export OPENCODE_SERVER_PASSWORD=splice-token
opencode serve --hostname 127.0.0.1 --port 4765
```

模型可用性取决于本机 opencode 的 provider 配置；用 `GET /api/model` 确认可用模型。

## 2. 起 UHP 服务端

```cangjie
import std.collection.HashMap
import stdx.net.http.*
import uhp.server.*
import uhp_opencode.*

main() {
    let opts = OpencodeOptions(
        "http://127.0.0.1:4765",           // opencode serve 地址
        "/path/to/workspace",              // opencode location.directory
        password: "splice-token",
        model: Some(("deepseek-v4.1-flash-free", "opencode")))  // 可选：钉模型
    let driver = OpencodeDriver(opts)
    let harness = ConfiguredHarness("chrn_opencode", "opencode 2.x", "opencode", "auto", driver)
    let engine = Engine([harness])

    let tokens = HashMap<String, String>()
tokens["dev-token"] = "alice"
    let uhp = UhpHttpServer(engine, Authenticator(tokens))
    ServerBuilder().addr("127.0.0.1").port(8471).distributor(uhp.distributor()).build().serve()
}
```

## 3. 验证

```bash
bash scripts/test.sh          # 11 条测试（同进程假 opencode）
bash scripts/real-smoke.sh    # 真实链路：UHP 任务 → opencode shell 工具 → 探针输出
```

## 4. 映射要点

| opencode | UHP |
|---|---|
| `session.text.delta` / `session.reasoning.delta` | `textDelta` / `reasoningDelta` |
| `session.tool.input.started` + `session.tool.called` | `toolCall`（名字 + 参数） |
| `session.tool.success` / `failed` | `toolResult` |
| `permission.asked` / `form.created` | `ask(...)` → `incomplete(input_required)`，下一轮答案回给 opencode |
| `execution.succeeded` / `failed` / `interrupted` | `Completed` / `Failed` / `Cancelled` |
| 回合成功后的 `/api/session/{id}/diff` | 改动文件 → `producedFile` → UHP 会话产物 |
| 输入文件 `TurnContext.files` | prompt `files[]`（data URI + 文件名） |

## 5. API 参考

`OpencodeOptions(baseUrl, directory, user = "opencode", password = "", model = None, timeoutSeconds = 600, label = "opencode 2.x")`。

`OpencodeDriver(opts)` 实现 `HarnessDriver`：`base/baseLabel/models/capabilities/run`。

已知限制：未接 opencode 的 experimental artifacts 通道；只回传 ≤1 MiB 的普通文件。
