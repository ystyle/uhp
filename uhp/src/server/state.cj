// 任务与会话的状态机（Lifecycle §3/§4/§5）。
//
// 三条不可妥协的规则，测试逐条钉住：
//   1. 终态不可迁移：一旦 returned completed，之后读永远是 completed；
//   2. 同一 session 不得并发：第二个任务 → session_busy（409）；
//   3. 不同 harness 不得延续同一 session → harness_mismatch（409），绝不静默开新会话。
package uhp.server

public enum TaskStatus {
    | InProgress
    | Completed
    | Failed
    | Incomplete
    | Cancelled
}

public func taskStatusName(s: TaskStatus): String {
    return match (s) {
        case TaskStatus.InProgress => "in_progress"
        case TaskStatus.Completed => "completed"
        case TaskStatus.Failed => "failed"
        case TaskStatus.Incomplete => "incomplete"
        case TaskStatus.Cancelled => "cancelled"
    }
}

public func isTerminalStatus(s: TaskStatus): Bool {
    return match (s) {
        case TaskStatus.InProgress => false
        case _ => true
    }
}

public class ResponseState {
    private var current: TaskStatus = TaskStatus.InProgress
    private var outcomeProduced: Bool = false

    public init() {}

    public func status(): TaskStatus {
        return this.current
    }

    // 返回 false 表示非法迁移（终态之后又收到迁移请求）。调用方应忽略而不是覆盖。
    public func transition(next: TaskStatus): Bool {
        if (isTerminalStatus(this.current)) {
            return false
        }
        this.current = next
        if (isTerminalStatus(next)) {
            this.outcomeProduced = true
        }
        return true
    }

    // 终态必须保留已产生的输出：这里只记「是否产出过结果」，输出本身在存储里。
    public func hadOutcome(): Bool {
        return this.outcomeProduced
    }
}

public class SessionState {
    public let id: String
    public let harnessId: String
    private var inFlight: Option<String> = None

    public init(id: String, harnessId: String) {
        this.id = id
        this.harnessId = harnessId
    }

    public func isBusy(): Bool {
        return this.inFlight.isSome()
    }

    public func inFlightResponse(): Option<String> {
        return this.inFlight
    }

    // false = 已有在跑的任务（调用方回 409 session_busy）
    public func tryBegin(responseId: String): Bool {
        if (this.inFlight.isSome()) {
            return false
        }
        this.inFlight = Some(responseId)
        return true
    }

    public func finish(): Unit {
        this.inFlight = None
    }

    // false = 用的是另一个 configured harness（调用方回 409 harness_mismatch）
    public func acceptsHarness(harnessId: String): Bool {
        return this.harnessId == harnessId
    }
}
