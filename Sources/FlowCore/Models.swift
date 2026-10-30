import Foundation
import CoreFoundation

public enum FlowError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

public struct UsageWindow: Codable, Equatable {
    public let used: Double
    public let minutes: Int
    public let resetsAt: Date?
    public var label: String {
        switch minutes {
        case 10080: return "每周额度"
        case 300: return "5 小时额度"
        case 1440: return "每日额度"
        default: return minutes % 60 == 0 ? "\(minutes / 60) 小时额度" : "\(minutes) 分钟额度"
        }
    }
    public var remaining: Double { 100 - used }
    public var percentText: String { "\(Int(remaining.rounded()))%" }
    public func isExpired(at date: Date) -> Bool { resetsAt.map { $0 <= date } ?? false }
}

public struct UsageSnapshot: Codable {
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    public let plan: String?

    public static func parse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlowError.unavailable("用量响应格式无法识别")
        }
        let body = object["result"] as? [String: Any] ?? object
        let map = body["rateLimitsByLimitId"] as? [String: Any]
        let bucket = map?["codex"] as? [String: Any] ?? body["rateLimits"] as? [String: Any]
        guard let bucket, (bucket["limitId"] as? String).map({ $0 == "codex" }) ?? true else {
            throw FlowError.unavailable("账户未返回 Codex 额度，请在 Codex 中确认登录")
        }
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = bucket[key] as? [String: Any],
                  let n = w["usedPercent"] as? NSNumber,
                  CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, (0...100).contains(n.doubleValue),
                  let mins = w["windowDurationMins"] as? NSNumber,
                  CFGetTypeID(mins) != CFBooleanGetTypeID(), mins.doubleValue > 0,
                  mins.doubleValue <= 525600, mins.doubleValue.rounded() == mins.doubleValue else { continue }
            let reset = (w["resetsAt"] as? NSNumber).flatMap { n -> Date? in
                n.doubleValue.isFinite && n.doubleValue > 0 ? Date(timeIntervalSince1970: n.doubleValue) : nil
            }
            windows.append(UsageWindow(used: n.doubleValue, minutes: mins.intValue, resetsAt: reset))
        }
        guard !windows.isEmpty else { throw FlowError.unavailable("账户尚未提供可用的额度数据") }
        return UsageSnapshot(windows: windows.sorted { $0.minutes < $1.minutes }, fetchedAt: now, plan: bucket["planType"] as? String)
    }
}

public enum TaskPhase: String { case idle, working, waiting, completed, interrupted }
public enum ActivityMode: String { case idle, working, busy, waiting, completed, unknown }

public struct ActivitySummary {
    public let mode: ActivityMode
    public let activeCount: Int
    public let waitingCount: Int
    public let uncertainCount: Int
    public let tasks: [TaskState]
    public let latestCompletedAt: Date?

    public init(tasks: [TaskState], now: Date = Date()) {
        self.tasks = tasks
        let open = tasks.filter { $0.phase == .working || $0.phase == .waiting }
        let live = open.filter { now.timeIntervalSince($0.lastActivity) < 180 }
        activeCount = live.filter { $0.phase == .working }.count
        waitingCount = live.filter { $0.phase == .waiting }.count
        uncertainCount = open.count - live.count
        latestCompletedAt = tasks.filter { $0.phase == .completed }.compactMap(\.completedAt).max()
        if activeCount >= 4 { mode = .busy }
        else if activeCount > 0 { mode = .working }
        else if waitingCount > 0 { mode = .waiting }
        else if uncertainCount > 0 { mode = .unknown }
        else if let date = latestCompletedAt, now.timeIntervalSince(date) < 15 { mode = .completed }
        else { mode = .idle }
    }

    public var label: String {
        switch mode {
        case .idle: return "空闲"
        case .working: return "执行中"
        case .busy: return "繁忙"
        case .waiting: return "等待你"
        case .completed: return "已完成"
        case .unknown: return "状态待确认"
        }
    }
    public var detail: String {
        if activeCount > 0 {
            return "\(activeCount) 个本机任务执行中" + (waitingCount > 0 ? " · \(waitingCount) 个等待" : "")
        }
        switch mode {
        case .waiting: return "\(waitingCount) 个任务等待操作"
        case .unknown: return "\(uncertainCount) 个未结束任务暂未更新日志"
        case .completed: return "最近的任务已完成"
        default: return "等待新的本机任务"
        }
    }
}
