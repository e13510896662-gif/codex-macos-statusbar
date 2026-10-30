import Foundation
import SQLite3

/// A bounded JSONL decoder. Incomplete records remain buffered until the next read.
public struct JSONLines {
    private var buffer = Data()
    private var discarding = false
    private let limit = 4 * 1024 * 1024
    public init() {}
    public mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var result: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            if !discarding, !line.isEmpty, line.count <= limit { result.append(Data(line)) }
            discarding = false
            buffer.removeSubrange(...newline)
        }
        if buffer.count > limit { buffer.removeAll(keepingCapacity: false); discarding = true }
        return result
    }
}

public final class LocalTaskReader {
    private let home: URL
    private struct Cursor {
        var path: String
        var inode: UInt64
        var offset: UInt64 = 0
        var decoder = JSONLines()
        var task: TaskState
    }
    private var cursors: [String: Cursor] = [:]
    public init(home: URL) { self.home = home }

    public func scan(now: Date = Date()) throws -> [TaskState] {
        let names = try FileManager.default.contentsOfDirectory(atPath: home.path)
        let databases = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (version, name)
        }.sorted { $0.0 > $1.0 }
        guard let database = databases.first else { throw FlowError.unavailable("未找到 Codex 本机任务索引") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(home.appendingPathComponent(database.1).path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw FlowError.unavailable("Codex 任务索引暂时无法读取")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        var statement: OpaquePointer?
        let hasName = sqlite3_table_column_metadata(db, nil, "threads", "name", nil, nil, nil, nil, nil) == SQLITE_OK
        let titleExpression = hasName ? "COALESCE(NULLIF(name,''),title)" : "title"
        let query = "SELECT id, \(titleExpression), rollout_path FROM threads WHERE archived=0 AND updated_at >= ? ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw FlowError.unavailable("Codex 任务索引格式已变化") }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(now.timeIntervalSince1970 - 86400))
        var seen = Set<String>()
        var result: [TaskState] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            func column(_ n: Int32) -> String { sqlite3_column_text(statement, n).map { String(cString: $0) } ?? "" }
            let id = column(0), rawTitle = column(1), path = column(2)
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "任务 \(id.prefix(8))" : rawTitle
            seen.insert(id)
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: path) }
            catch { throw FlowError.unavailable("部分任务日志暂不可读，稍后将自动重试") }
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            var cursor = cursors[id]
            if cursor == nil || cursor?.path != path || cursor?.inode != inode || (cursor?.offset ?? 0) > size {
                cursor = Cursor(path: path, inode: inode, task: TaskState(id: id, title: title))
                if size > 1024 * 1024 {
                    cursor!.offset = size - 1024 * 1024
                    // Discard the first, potentially partial line at the tail boundary.
                    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                    defer { try? handle.close() }
                    try handle.seek(toOffset: cursor!.offset)
                    let tail = try handle.read(upToCount: 1024 * 1024) ?? Data()
                    cursor!.offset += UInt64(tail.count)
                    if let newline = tail.firstIndex(of: 10) {
                        for line in cursor!.decoder.append(Data(tail[tail.index(after: newline)...])) { cursor!.task.consume(line) }
                    }
                }
            }
            guard var current = cursor else { break }
            current.task.title = title
            if size > current.offset {
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                defer { try? handle.close() }
                try handle.seek(toOffset: current.offset)
                // Bound each read; multiple chunks allow logs larger than the buffer ceiling.
                while current.offset < size {
                    let count = min(256 * 1024, Int(size - current.offset))
                    let data = try handle.read(upToCount: count) ?? Data()
                    if data.isEmpty { break }
                    current.offset += UInt64(data.count)
                    for line in current.decoder.append(data) { current.task.consume(line) }
                }
            }
            cursors[id] = current
            if current.task.phase != .idle { result.append(current.task) }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw FlowError.unavailable("Codex 任务索引繁忙，稍后自动重试") }
        cursors = cursors.filter { seen.contains($0.key) }
        return result
    }
}
