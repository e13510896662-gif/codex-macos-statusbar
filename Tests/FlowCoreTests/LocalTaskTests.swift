import Foundation
import Testing
import SQLite3
@testable import FlowCore

struct LocalTaskTests {
    // Broken buffering would interpret an unfinished JSON line as an empty/no-task state.
    @Test func splitLinesAndMalformedLineRecovery() {
        var decoder = JSONLines()
        #expect(decoder.append(Data("{\"id\":".utf8)).isEmpty)
        let records = decoder.append(Data("1}\n{bad}\n{\"id\":2}\n".utf8))
        #expect(records.map { String(decoding: $0, as: UTF8.self) } == ["{\"id\":1}", "{bad}", "{\"id\":2}"])
    }

    func fixture() throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("rollout.jsonl")
        var db: OpaquePointer?
        guard sqlite3_open(dir.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK else { throw FlowError.unavailable("fixture failed") }
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE threads(id TEXT, title TEXT, rollout_path TEXT, updated_at INTEGER, archived INTEGER); INSERT INTO threads VALUES('thread','Example','\(log.path)',1000,0);"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FlowError.unavailable("fixture SQL failed") }
        return (dir, log)
    }

    func line(_ type: String, at seconds: Int) -> String {
        "{\"timestamp\":\"\(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(seconds))))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"A\"}}\n"
    }

    @Test func incrementalRealFilesPreservePartialLastLineAndFinish() throws {
        let (dir, log) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = line("task_started", at: 1000)
        let complete = line("task_complete", at: 1002)
        try (start + String(complete.prefix(40))).write(to: log, atomically: true, encoding: .utf8)
        let reader = LocalTaskReader(home: dir)
        let before = try reader.scan(now: Date(timeIntervalSince1970: 1001))
        #expect(before.count == 1)
        #expect(before.first?.phase == .working)
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(complete.dropFirst(40).utf8))
        try handle.close()
        let after = try reader.scan(now: Date(timeIntervalSince1970: 1003))
        #expect(after.first?.phase == .completed)
        #expect(try reader.scan(now: Date(timeIntervalSince1970: 1004)).first?.phase == .completed)
    }

    @Test func fileReplacementDoesNotRetainOldBusyState() throws {
        let (dir, log) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        try line("task_started", at: 1000).write(to: log, atomically: true, encoding: .utf8)
        let reader = LocalTaskReader(home: dir)
        #expect(try reader.scan(now: Date(timeIntervalSince1970: 1001)).first?.phase == .working)
        try line("task_complete", at: 1002).write(to: log, atomically: true, encoding: .utf8)
        #expect(try reader.scan(now: Date(timeIntervalSince1970: 1003)).first?.phase == .completed)
    }

    @Test func missingDatabaseReportsFailureRatherThanIdle() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: (any Error).self) { try LocalTaskReader(home: dir).scan() }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func startingInMiddleOfLargeRunningLogRecoversActivity() throws {
        let (dir, log) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The lifecycle event is outside the initial tail. Large tool output is skipped safely.
        let tool = "{\"timestamp\":\"1970-01-01T00:16:41Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call_output\",\"output\":\"" + String(repeating: "x", count: 1100000) + "\"}}\n"
        let tokens = line("token_count", at: 1002)
        try (line("task_started", at: 1000) + tool + tokens).write(to: log, atomically: true, encoding: .utf8)
        let tasks = try LocalTaskReader(home: dir).scan(now: Date(timeIntervalSince1970: 1003))
        #expect(ActivitySummary(tasks: tasks, now: Date(timeIntervalSince1970: 1003)).activeCount == 1)
    }

    @Test func usesUserAssignedThreadNameWhenLegacyTitleIsEmpty() throws {
        let (dir, log) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var db: OpaquePointer?
        #expect(sqlite3_open(dir.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "ALTER TABLE threads ADD COLUMN name TEXT; UPDATE threads SET name='Menu bar tool', title='';", nil, nil, nil) == SQLITE_OK)
        try line("task_started", at: 1000).write(to: log, atomically: true, encoding: .utf8)
        let tasks = try LocalTaskReader(home: dir).scan(now: Date(timeIntervalSince1970: 1001))
        #expect(tasks.first?.title == "Menu bar tool")
    }
}
