// L2 测试：向人提问（Tasks §3.2）与 step 预算（§1.1），都不依赖网络。
package uhp.server

import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.base.*
import uhp.types.generated.*

class AskDriver <: HarnessDriver {
    private let secret: Bool

    public init(secret: Bool) {
        this.secret = secret
    }

    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "asks"
    }

    public func models(): Array<Model> {
        return []
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        if (ctx.answers.size > 0) {
            sink.textDelta("ANSWERED " + ctx.answers[0])
            return TurnOutcome.Completed(None)
        }
        if (this.secret) {
            let _ = sink.ask("secret", "The deploy token?", Array<(String, String)>())
        } else {
            let _ = sink.ask("choice", "Which colour?", [("red", "Red"), ("blue", "Blue")])
        }
        return TurnOutcome.Completed(None)
    }
}

class StepDriver <: HarnessDriver {
    public func base(): String {
        return "scripted"
    }

    public func baseLabel(): String {
        return "steps"
    }

    public func models(): Array<Model> {
        return []
    }

    public func capabilities(): HarnessCapabilities {
        return HarnessCapabilities(false, false)
    }

    public func run(ctx: TurnContext, sink: TurnSink, cancel: CancelToken): TurnOutcome {
        // 两轮工具调用：预算 1 时必然超额
        for (_ in 0..2) {
            let callId = sink.toolCall("uhp_steps", "{}")
            sink.toolResult(callId, "UHP-FIXTURE step")
        }
        return TurnOutcome.Completed(None)
    }
}

func engineAsking(secret: Bool): Engine {
    return Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", AskDriver(secret))],
        cls: ConformanceClass.Full)
}

@Test
func question_ends_task_incomplete_with_item(): Unit {
    let e = engineAsking(false)
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("please ask"))
    @Expect(r.response.status, "incomplete")
    let details = r.response.incomplete_details ?? ResponseIncompleteDetails()
    @Expect(details.extras.get("reason"), Some("\"input_required\""))
    var found = false
    var promptInMessage = false
    for (item in r.response.output) {
        if (item.typeName == "input_request") {
            found = true
            @Expect(item.id ?? "", item.id ?? "x")
            @Expect((item.kind ?? ""), "choice")
        }
        if (item.typeName == "message") {
            for (part in item.content ?? []) {
                if ((part.text ?? "").contains("Which colour?")) {
                    promptInMessage = true
                }
            }
        }
    }
    @Expect(found, true)
    @Expect(promptInMessage, true)
}

@Test
func answer_outside_options_is_refused_and_stale_is_409(): Unit {
    let e = engineAsking(false)
    let p = Principal("alice")
    let first = e.createTask(p, TaskRequest("ask"))
    let rid = first.response.output.filter({ i => i.typeName == "input_request" })[0].id ?? ""
    var code = ""
    try {
        e.createTask(p, TaskRequest("", previousResponseId: Some(first.response.id),
            inputResponse: Some((rid, "green"))))
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "input_response_invalid")
    var stale = ""
    try {
        e.createTask(p, TaskRequest("", previousResponseId: Some(first.response.id),
            inputResponse: Some(("inreq_nope", "red"))))
    } catch (err: EngineError) {
        stale = err.code
    }
    @Expect(stale, "input_not_pending")
    // 合法答案：普通续跑，指回提问那次
    let ok = e.createTask(p, TaskRequest("", previousResponseId: Some(first.response.id),
        inputResponse: Some((rid, "red"))))
    @Expect(ok.response.status, "completed")
    @Expect(ok.response.previous_response_id, Some("\"" + first.response.id + "\""))
    // 再答一次 409
    var again = ""
    try {
        e.createTask(p, TaskRequest("", previousResponseId: Some(first.response.id),
            inputResponse: Some((rid, "blue"))))
    } catch (err: EngineError) {
        again = err.code
    }
    @Expect(again, "input_not_pending")
}

@Test
func secret_answer_stays_out_of_input_items(): Unit {
    let e = engineAsking(true)
    let p = Principal("alice")
    let first = e.createTask(p, TaskRequest("ask secret"))
    let rid = first.response.output.filter({ i => i.typeName == "input_request" })[0].id ?? ""
    let secret = "uhp-secret-abc123"
    let ok = e.createTask(p, TaskRequest(secret, previousResponseId: Some(first.response.id),
        inputResponse: Some((rid, secret))))
    @Expect(ok.response.status, "completed")
    let items = e.responseInputItems(p, ok.response.id)
    @Expect(items.contains(secret), false)
    @Expect(items.contains(rid), true)
}

@Test
func step_budget_forces_incomplete(): Unit {
    let e = Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", StepDriver())],
        cls: ConformanceClass.Full)
    let p = Principal("alice")
    let r = e.createTask(p, TaskRequest("chain", maxStep: Some(1)))
    @Expect(r.response.status, "incomplete")
    let d = r.response.incomplete_details ?? ResponseIncompleteDetails()
    @Expect((d.extras.get("reason") ?? "").contains("max_steps"), true)
    // 调用与结果都要落成 items（套件按配对计轮）
    var calls = 0
    var outputs = 0
    for (item in r.response.output) {
        if (item.typeName == "function_call") {
            calls = calls + 1
        }
        if (item.typeName == "function_call_output") {
            outputs = outputs + 1
        }
    }
    @Expect(calls, 2)
    @Expect(outputs, 2)
}
