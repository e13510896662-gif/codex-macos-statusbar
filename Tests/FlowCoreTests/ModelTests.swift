import Foundation
import Testing
@testable import FlowCore

struct ModelTests {
    func parse(_ json: String) throws -> UsageSnapshot {
        try UsageSnapshot.parse(Data(json.utf8), now: Date(timeIntervalSince1970: 1000))
    }

    // Catches treating primary as always a 5-hour bucket, or preferring stale legacy limits.
    @Test func testWeeklyOnlyAndMapTakesPrecedence() throws {
        let s = try parse("""
        {"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":9000}},
        "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":9000},"secondary":null}}}
        """)
        #expect(s.windows.count == 1)
        #expect(s.windows[0].minutes == 10080)
        #expect(s.windows[0].used == 7)
        #expect(s.windows[0].label == "每周额度")
    }

    @Test func testMissingUsageIsNeverZero() {
        for json in ["{}", "{\"rateLimits\":{\"primary\":null}}", "{\"rateLimits\":{\"primary\":{\"windowDurationMins\":300}}}"] {
            #expect(throws: (any Error).self) { try parse(json) }
        }
    }

    @Test func testRejectsInvalidPercentAndSortsByRealDuration() throws {
        let s = try parse("""
        {"rateLimits":{"primary":{"usedPercent":11,"windowDurationMins":10080},"secondary":{"usedPercent":22,"windowDurationMins":300}}}
        """)
        #expect(s.windows.map(\.used) == [22, 11])
        #expect(throws: (any Error).self) { try parse("{\"rateLimits\":{\"primary\":{\"usedPercent\":-2,\"windowDurationMins\":300}}}") }
        #expect(throws: (any Error).self) { try parse("{\"rateLimits\":{\"primary\":{\"usedPercent\":101,\"windowDurationMins\":300}}}") }
    }

    @Test func testExpiredWindowDoesNotInventResetUsage() throws {
        let s = try parse("{\"rateLimits\":{\"primary\":{\"usedPercent\":70,\"windowDurationMins\":300,\"resetsAt\":900}}}")
        #expect(s.windows[0].used == 70)
        #expect(s.windows[0].isExpired(at: Date(timeIntervalSince1970: 1000)))
    }

    func event(_ type: String, turn: String = "A", time: Double = 1000, extra: [String: Any] = [:]) -> Data {
        var payload = extra
        payload["type"] = type
        payload["turn_id"] = turn
        return try! JSONSerialization.data(withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: time)), "type": "event_msg", "payload": payload])
    }

    @Test func testTaskLifecycleAndLateEndFromOldTurn() {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started"))
        #expect(s.phase == .working)
        s.consume(event("task_started", turn: "B", time: 1001))
        s.consume(event("task_complete", turn: "A", time: 1002))
        #expect(s.phase == .working)
        s.consume(event("task_complete", turn: "B", time: 1003))
        #expect(s.phase == .completed)
    }

    @Test func testInterruptedIsNotCompleted() {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started"))
        s.consume(event("turn_aborted", time: 1001))
        #expect(s.phase == .interrupted)
    }

    @Test func testStaleUnfinishedIsUnknownNotIdleOrCompleted() {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started"))
        let a = ActivitySummary(tasks: [s], now: Date(timeIntervalSince1970: 1200))
        #expect(a.mode == .unknown)
        #expect(a.activeCount == 0)
        #expect(a.uncertainCount == 1)
    }

    @Test func testActualParallelTasksDriveBusyState() {
        let tasks = (0..<4).map { n -> TaskState in
            var s = TaskState(id: "\(n)", title: "Task")
            s.consume(event("task_started"))
            return s
        }
        let a = ActivitySummary(tasks: tasks, now: Date(timeIntervalSince1970: 1001))
        #expect(a.mode == .busy)
        #expect(a.activeCount == 4)
    }

    @Test func testExplicitWaitingAndResolution() {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started"))
        s.consume(event("request_user_input", extra: ["request_id": "r1"]))
        #expect(s.phase == .waiting)
        s.consume(event("token_count", time: 1001))
        #expect(s.phase == .waiting)
        s.consume(event("server_request_resolved", time: 1002, extra: ["request_id": "r1"]))
        #expect(s.phase == .working)
    }

    @Test func testMalformedRecordDoesNotEraseState() {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started"))
        s.consume(Data("{bad".utf8))
        #expect(s.phase == .working)
    }

    @Test func oldWaitingRequestCannotOverrideNewTurn() throws {
        var s = TaskState(id: "thread", title: "Task")
        s.consume(event("task_started", turn: "B", time: 1010))
        let request: [String: Any] = ["timestamp": "1970-01-01T00:16:45Z", "type": "response_item", "payload": ["type": "function_call", "name": "request_user_input", "call_id": "old"]]
        s.consume(try JSONSerialization.data(withJSONObject: request))
        #expect(s.phase == .working)
    }

    @Test func displayShowsRemainingQuotaIncludingBothBoundaries() throws {
        for (used, remaining, text) in [(8, 92, "92%"), (0, 100, "100%"), (100, 0, "0%")] {
            let s = try parse("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(used),\"windowDurationMins\":10080}}}")
            #expect(s.windows[0].remaining == Double(remaining))
            #expect(s.windows[0].percentText == text)
        }
    }
}
