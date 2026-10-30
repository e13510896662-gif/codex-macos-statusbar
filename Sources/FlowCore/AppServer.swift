import Foundation
import Darwin

public enum ServerEvent { case usage(UsageSnapshot), failure(String) }

/// Uses Codex's official read-only JSON-RPC interface, keeping auth inside the Codex process.
public final class AppServerClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.codexflow.app-server", qos: .utility)
    private let executable: URL
    private let arguments: [String]
    private let home: URL
    private let timeout: TimeInterval
    private let onEvent: (ServerEvent) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var decoder = JSONLines()
    private var generation = UUID()
    private var initialized = false
    private var pending: Int?
    private var nextID = 2
    private var stopped = false

    public init(executable: URL, arguments: [String] = ["app-server", "--stdio"], home: URL, timeout: TimeInterval = 25, onEvent: @escaping (ServerEvent) -> Void) {
        self.executable = executable; self.arguments = arguments; self.home = home
        self.timeout = timeout; self.onEvent = onEvent
    }

    public static func codexHome() -> URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    public static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_FLOW_CLI"] ?? "",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func refresh() {
        queue.async { [weak self] in
            guard let self, !self.stopped, self.pending == nil else { return }
            if self.process == nil { self.start() }
            else if self.initialized { self.requestUsage() }
        }
    }

    public func stop() {
        queue.sync {
            stopped = true
            cleanup(force: true)
        }
    }

    private func start() {
        generation = UUID(); let token = generation
        decoder = JSONLines(); initialized = false; nextID = 2
        let child = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe()
        child.executableURL = executable; child.arguments = arguments
        child.standardInput = stdinPipe; child.standardOutput = stdoutPipe; child.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = home.path
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        child.environment = env
        child.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == token, !self.stopped else { return }
                self.fail("Codex 数据连接已断开，将自动重连")
            }
        }
        process = child; input = stdinPipe.fileHandleForWriting; output = stdoutPipe.fileHandleForReading
        do { try child.run() }
        catch { fail("无法启动 Codex 数据连接，请确认 Codex 已安装"); return }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { [weak self] in
                guard let self, self.generation == token, !self.stopped else { return }
                if data.isEmpty { return }
                for line in self.decoder.append(data) { self.receive(line) }
            }
        }
        pending = 1
        send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_flow", "version": "0.0.1"], "capabilities": ["experimentalApi": true]]])
        armTimeout(id: 1, token: token)
    }

    private func send(_ message: [String: Any]) {
        guard let input else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
            data.append(10); try input.write(contentsOf: data)
        } catch { fail("Codex 数据通道不可写，将自动重连") }
    }

    private func requestUsage() {
        let id = nextID; nextID += 1; pending = id
        send(["id": id, "method": "account/rateLimits/read"])
        armTimeout(id: id, token: generation)
    }

    private func armTimeout(id: Int, token: UUID) {
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.stopped, self.generation == token, self.pending == id else { return }
            self.fail("读取 Codex 用量超时，将自动重试")
        }
    }

    private func receive(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let id = message["id"] as? Int, id == pending {
            if message["error"] != nil { fail("Codex 未能提供用量，请确认登录和网络连接"); return }
            if id == 1 {
                guard message["result"] != nil else { return }
                pending = nil; initialized = true
                send(["method": "initialized"])
                requestUsage()
            } else {
                pending = nil
                do { onEvent(.usage(try UsageSnapshot.parse(data))) }
                catch { onEvent(.failure(error.localizedDescription)) }
            }
        } else if message["method"] as? String == "account/rateLimits/updated",
                  let params = message["params"], let payload = try? JSONSerialization.data(withJSONObject: params) {
            if let usage = try? UsageSnapshot.parse(payload) { onEvent(.usage(usage)) }
        }
    }

    private func fail(_ text: String) {
        cleanup()
        if !stopped { onEvent(.failure(text)) }
    }

    private func cleanup(force: Bool = false) {
        generation = UUID()
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            let pid = process.processIdentifier
            if force {
                // stop() is also called during applicationWillTerminate: a delayed
                // fallback cannot run after the main process exits. This helper
                // owns no model tasks; terminate it immediately without blocking UI.
                kill(pid, SIGKILL)
            } else {
                process.terminate()
                // A misbehaving helper must not be left behind after a timeout.
                queue.asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
        process = nil; pending = nil; initialized = false
    }
}
