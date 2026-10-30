import AppKit
import ServiceManagement
import FlowCore

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let panel = PanelView(frame: NSRect(x: 0, y: 0, width: 344, height: 558))
    private var animationTimer: Timer?
    private var usageTimer: Timer?
    private var taskTimer: DispatchSourceTimer?
    private var server: AppServerClient?
    private let worker = DispatchQueue(label: "local.codexflow.tasks", qos: .utility)
    private let reader = LocalTaskReader(home: AppServerClient.codexHome())
    private var usage: UsageSnapshot?
    private var activity: ActivitySummary?
    private var taskError: String?
    private var usageError: String?
    private var settingsNotice: String?
    private var phase = 0.0
    private var displayedUsage: Double?
    private var displayedColor = NSColor.systemGray
    private var tick = 0
    private var selectedMinutes: Int { UserDefaults.standard.integer(forKey: "selectedMinutes") }
    private var selectedWindow: UsageWindow? {
        usage?.windows.first { $0.minutes == selectedMinutes } ?? usage?.windows.first
    }
    private var stale: Bool {
        guard let usage else { return true }
        return usageError != nil || Date().timeIntervalSince(usage.fetchedAt) > 150 || selectedWindow?.isExpired(at: Date()) == true
    }
    private var reducedMotion: Bool { UserDefaults.standard.bool(forKey: "reduceMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.title = " — "
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.imagePosition = .imageLeading
        button.target = self; button.action = #selector(togglePopover)
        let controller = NSViewController(); controller.view = panel
        popover.contentViewController = controller
        popover.contentSize = panel.frame.size
        popover.behavior = .transient
        popover.animates = !reducedMotion
        panel.selection.target = self; panel.selection.action = #selector(selectWindow)
        panel.refresh.target = self; panel.refresh.action = #selector(refreshUsage)
        panel.openCodex.target = self; panel.openCodex.action = #selector(openCodex)
        panel.quit.target = self; panel.quit.action = #selector(quit)
        panel.reduceMotion.target = self; panel.reduceMotion.action = #selector(toggleMotion)
        panel.reduceMotion.state = reducedMotion ? .on : .off
        panel.login.target = self; panel.login.action = #selector(toggleLogin)
        panel.login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if let executable = AppServerClient.findExecutable() {
            server = AppServerClient(executable: executable, home: AppServerClient.codexHome()) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch event {
                    case .usage(let snapshot): self.usage = snapshot; self.usageError = nil
                    case .failure(let text): self.usageError = text
                    }
                    self.updatePanel(); self.renderIndicator()
                }
            }
            server?.refresh()
        } else { usageError = "未找到 Codex CLI，请先安装或打开 Codex" }
        let taskTimer = DispatchSource.makeTimerSource(queue: worker)
        taskTimer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
        taskTimer.setEventHandler { [weak self] in self?.scanTasks() }
        taskTimer.resume(); self.taskTimer = taskTimer
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.server?.refresh() }
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(timer, forMode: .common); animationTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        updatePanel(); renderIndicator()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showPopover() }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.saveSnapshot(to: path) }
        }
    }

    private func scanTasks() {
        do {
            let tasks = try reader.scan()
            let summary = ActivitySummary(tasks: tasks)
            DispatchQueue.main.async { [weak self] in
                self?.activity = summary; self?.taskError = nil; self?.updatePanel()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.activity = nil; self?.taskError = error.localizedDescription; self?.updatePanel()
            }
        }
    }

    private func updatePanel() {
        panel.update(usage: usage, selected: selectedWindow, activity: activity, usageError: usageError, taskError: taskError, stale: stale)
        if let settingsNotice { panel.notice.stringValue = settingsNotice; panel.notice.textColor = .systemOrange }
        panel.refresh.isEnabled = server != nil
        statusItem?.button?.toolTip = "Codex Mac 状态栏 · \(selectedWindow?.label ?? "额度连接中")剩余 \(selectedWindow?.percentText ?? "未知")\n\(activity?.detail ?? "任务状态不可用")" + (stale ? "\n用量尚未更新，橙色点表示旧数据" : "")
    }

    private func animate() {
        tick += 1
        let speed = FlowPalette.speed(activity)
        let target = selectedWindow?.remaining
        let color = FlowPalette.color(activity)
        let moving = !reducedMotion && speed > 0
        let transitioning = (target != nil && abs((displayedUsage ?? target!) - target!) > 0.05) || displayedColor != color
        if tick % 3 != 0 && (activity?.activeCount ?? 0) == 0 && !transitioning { return }
        if moving { phase += speed / 15 * ((activity?.activeCount ?? 0) > 0 ? 1 : 3) }
        if let target {
            displayedUsage = reducedMotion ? target : (displayedUsage ?? target) + (target - (displayedUsage ?? target)) * 0.16
        } else { displayedUsage = nil }
        displayedColor = reducedMotion ? color : displayedColor.blended(withFraction: 0.16, of: color) ?? color
        if !moving && !transitioning && tick % 15 != 0 { return }
        renderIndicator()
        if popover.isShown {
            panel.water.phase = phase; panel.water.remaining = displayedUsage; panel.water.color = displayedColor
            panel.water.needsDisplay = true
        }
    }

    private func renderIndicator() {
        guard let button = statusItem?.button else { return }
        let text = selectedWindow?.percentText ?? "—"
        button.title = " " + text + " "
        button.image = WaterDrawing.image(remaining: displayedUsage ?? selectedWindow?.remaining, phase: phase, color: displayedColor, active: (activity?.activeCount ?? 0) > 0, stale: stale, done: activity?.mode == .completed)
        button.setAccessibilityLabel("Codex，\(selectedWindow?.label ?? "额度未知")剩余 \(text)，\(activity?.label ?? "状态未知")" + (stale ? "，用量数据待更新" : ""))
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        updatePanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func selectWindow() {
        let index = panel.selection.selectedSegment
        guard let windows = usage?.windows, windows.indices.contains(index) else { return }
        UserDefaults.standard.set(windows[index].minutes, forKey: "selectedMinutes")
        updatePanel(); renderIndicator()
    }
    @objc private func refreshUsage() { server?.refresh() }
    @objc private func wake() { server?.refresh(); worker.async { [weak self] in self?.scanTasks() } }
    @objc private func toggleMotion() {
        UserDefaults.standard.set(panel.reduceMotion.state == .on, forKey: "reduceMotion")
        popover.animates = !reducedMotion
        renderIndicator()
    }
    @objc private func toggleLogin() {
        settingsNotice = nil
        do {
            if panel.login.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                settingsNotice = "请在系统设置 → 通用 → 登录项中允许 Codex Mac 状态栏。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            panel.login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            settingsNotice = "登录启动设置失败：请将应用移至 Applications 后重试。"
        }
        updatePanel()
    }
    @objc private func openCodex() {
        let id = activity?.tasks.filter { $0.phase == .working || $0.phase == .waiting }.max { $0.lastActivity < $1.lastActivity }?.id
        let address = id.map { "codex://threads/\($0)" } ?? "codex://"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        popover.performClose(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func saveSnapshot(to path: String) {
        updatePanel()
        guard let rep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else { return }
        panel.cacheDisplay(in: panel.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate(); usageTimer?.invalidate(); taskTimer?.cancel(); server?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
