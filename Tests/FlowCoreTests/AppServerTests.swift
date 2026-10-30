import Foundation
import Testing
import Darwin
@testable import FlowCore

struct AppServerTests {
    @Test func protocolReadsUsageWithoutStartingTurn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("server.sh")
        // This subprocess deliberately rejects every method except the three read-only protocol messages.
        try """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
            *'"method":"initialized"'*) ;;
            *'"method":"account/rateLimits/read"'*) printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":17,"windowDurationMins":10080}}}}' ;;
            *) printf '%s\\n' '{"id":2,"error":{"message":"unexpected mutation"}}' ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        let result = LockedResult()
        let semaphore = DispatchSemaphore(value: 0)
        let client = AppServerClient(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path], home: dir, timeout: 3) { event in
            if case .usage(let usage) = event { result.set(usage.windows.first?.used); semaphore.signal() }
            if case .failure = event { semaphore.signal() }
        }
        client.refresh()
        #expect(semaphore.wait(timeout: .now() + 5) == .success)
        #expect(result.get() == 17)
        client.stop()
    }

    @Test func unresponsiveProcessTimesOut() {
        let semaphore = DispatchSemaphore(value: 0)
        let client = AppServerClient(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], home: FileManager.default.temporaryDirectory, timeout: 0.2) { event in
            if case .failure = event { semaphore.signal() }
        }
        client.refresh()
        #expect(semaphore.wait(timeout: .now() + 3) == .success)
        client.stop()
    }

    @Test func stopDoesNotLeaveHelperThatIgnoresTermination() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("ignore-term.sh")
        let pidFile = dir.appendingPathComponent("helper.pid")
        try """
        #!/bin/sh
        trap '' TERM
        echo $$ > '\(pidFile.path)'
        while IFS= read -r line; do
          case "$line" in
          *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
          *'"method":"account/rateLimits/read"'*) printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300}}}}' ;;
          esac
        done
        while :; do sleep 1; done
        """.write(to: script, atomically: true, encoding: .utf8)
        let semaphore = DispatchSemaphore(value: 0)
        let client = AppServerClient(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path], home: dir) { event in
            if case .usage = event { semaphore.signal() }
        }
        client.refresh()
        #expect(semaphore.wait(timeout: .now() + 5) == .success)
        let pid = Int32(try String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines))!
        defer { kill(pid, SIGKILL) }
        client.stop()
        for _ in 0..<20 { if kill(pid, 0) != 0 { break }; usleep(10000) }
        #expect(kill(pid, 0) == -1)
    }
}

private final class LockedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double?
    func set(_ value: Double?) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func get() -> Double? { lock.lock(); defer { lock.unlock() }; return value }
}
