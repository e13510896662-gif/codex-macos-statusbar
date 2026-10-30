import Foundation
import AppKit
import FlowCore
import Darwin

@main struct Entry {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains("--diagnose") { diagnose(); return }
        if CommandLine.arguments.contains("--quit") {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: "local.codexflow.menubar") where running.processIdentifier != getpid() {
                running.terminate()
            }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.codexflow.menubar").contains(where: { $0.processIdentifier != getpid() }) {
            return
        }
        let controller = AppController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }

    static func diagnose() {
        let home = AppServerClient.codexHome()
        guard let executable = AppServerClient.findExecutable() else {
            print("{\"ok\":false,\"error\":\"未找到 Codex CLI\"}"); exit(1)
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = DiagnosticBox()
        let client = AppServerClient(executable: executable, home: home) { event in
            box.set(event); semaphore.signal()
        }
        client.refresh()
        let waited = semaphore.wait(timeout: .now() + 30)
        client.stop()
        var result: [String: Any] = ["ok": false, "taskScope": "local-last-24h", "refreshSeconds": 60]
        if waited == .success, let event = box.get() {
            switch event {
            case .usage(let usage):
                result["ok"] = true
                result["windows"] = usage.windows.map { ["minutes": $0.minutes, "usedPercent": $0.used, "remainingPercent": $0.remaining, "label": $0.label] as [String: Any] }
            case .failure(let message): result["error"] = message
            }
        } else { result["error"] = "诊断读取超时" }
        do {
            let tasks = try LocalTaskReader(home: home).scan()
            let summary = ActivitySummary(tasks: tasks)
            result["taskMode"] = summary.mode.rawValue
            result["activeTasks"] = summary.activeCount
            result["waitingTasks"] = summary.waitingCount
            result["uncertainTasks"] = summary.uncertainCount
            result["localTaskLogReadable"] = true
        } catch { result["taskError"] = "本机任务日志不可读" }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
        if result["ok"] as? Bool != true { exit(1) }
    }
}

private final class DiagnosticBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ServerEvent?
    func set(_ event: ServerEvent) { lock.lock(); defer { lock.unlock() }; value = event }
    func get() -> ServerEvent? { lock.lock(); defer { lock.unlock() }; return value }
}
