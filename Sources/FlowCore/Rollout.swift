import Foundation

public struct TaskState {
    public let id: String
    public var title: String
    public private(set) var phase: TaskPhase = .idle
    public private(set) var lastActivity = Date.distantPast
    public private(set) var completedAt: Date?
    public private(set) var turnID: String?
    public private(set) var activity = "正在执行"
    private var pendingRequest: String?
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let standard = ISO8601DateFormatter()

    public init(id: String, title: String) { self.id = id; self.title = title }

    public mutating func consume(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let rawTimestamp = obj["timestamp"] as? String,
              let date = Self.fractional.date(from: rawTimestamp) ?? Self.standard.date(from: rawTimestamp) else { return }
        let envelope = obj["type"] as? String ?? ""
        let type = payload["type"] as? String ?? ""
        let turn = payload["turn_id"] as? String

        // Late records from an old turn must never change current work/waiting state.
        guard date >= lastActivity else { return }
        if let turnID, let turn, turnID != turn, !["task_started", "turn_started"].contains(type) { return }

        if envelope == "event_msg" {
            if type == "task_started" || type == "turn_started" {
                guard date >= lastActivity else { return }
                phase = .working; turnID = turn; pendingRequest = nil; completedAt = nil
                activity = "正在思考"; lastActivity = date; return
            }
            if ["task_complete", "turn_complete", "turn_aborted", "task_failed"].contains(type) {
                guard turnID == nil || turn == nil || turn == turnID else { return }
                guard date >= lastActivity else { return }
                phase = ["task_complete", "turn_complete"].contains(type) ? .completed : .interrupted
                completedAt = phase == .completed ? date : nil
                lastActivity = date; pendingRequest = nil; return
            }
            if ["request_user_input", "exec_approval_request", "apply_patch_approval_request"].contains(type) {
                guard date >= lastActivity else { return }
                phase = .waiting; pendingRequest = payload["request_id"] as? String
                lastActivity = date; activity = "等待你操作"; return
            }
            if ["server_request_resolved", "exec_approval_response", "apply_patch_approval_response"].contains(type) {
                if phase == .waiting, pendingRequest == nil || payload["request_id"] as? String == pendingRequest {
                    phase = .working; pendingRequest = nil; activity = "继续执行"
                }
            }
            if type == "item_completed", let item = payload["item"] as? [String: Any] {
                guard turnID == nil || turn == nil || turnID == turn else { return }
                if phase == .idle { phase = .working; turnID = turn }
                switch (item["type"] as? String ?? "").lowercased() {
                case "reasoning": activity = "正在思考"
                case "commandexecution", "command_execution": activity = "正在执行命令"
                case "filechange", "file_change": activity = "正在修改文件"
                case "mcp_tool_call", "mcptoolcall": activity = "正在使用工具"
                default: break
                }
            }
            // On first tail-read the start event may be outside the bounded window.
            // A fresh token event is evidence of model activity, never evidence of idle.
            if type == "token_count", phase == .idle {
                phase = .working; turnID = turn; activity = "正在执行"
            }
        }
        if envelope == "response_item" {
            let isExecutionEvidence = ["function_call", "custom_tool_call", "function_call_output", "custom_tool_call_output", "reasoning"].contains(type)
                || (type == "message" && payload["role"] as? String == "assistant")
            if phase == .idle && isExecutionEvidence {
                phase = .working; turnID = turn; activity = "正在执行"
            }
            let name = payload["name"] as? String ?? ""
            if ["function_call", "custom_tool_call"].contains(type),
               name.split(separator: ".").last == "request_user_input" {
                phase = .waiting; pendingRequest = payload["call_id"] as? String
                activity = "等待你操作"
            }
            if ["function_call_output", "custom_tool_call_output"].contains(type), phase == .waiting,
               let pendingRequest, payload["call_id"] as? String == pendingRequest {
                phase = .working; self.pendingRequest = nil; activity = "继续执行"
            }
        }
        // Ignore context/settings records: they can change without a running task.
        if envelope == "event_msg" || envelope == "response_item" || envelope == "token_usage_record" {
            lastActivity = max(lastActivity, date)
        }
    }
}
