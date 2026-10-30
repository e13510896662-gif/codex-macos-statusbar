import AppKit
import FlowCore

func textLabel(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = secondary ? .secondaryLabelColor : .labelColor
    label.lineBreakMode = .byTruncatingTail
    return label
}

final class PanelView: NSView {
    override var isFlipped: Bool { true }
    let water = WaterView()
    let badge = textLabel("连接中", size: 11, weight: .medium)
    let percentage = textLabel("—", size: 42, weight: .medium)
    let quotaTitle = textLabel("读取真实额度…", secondary: true)
    let activityTitle = textLabel("正在检查本机任务", weight: .medium)
    let taskTitle = textLabel("", size: 11, secondary: true)
    let selection = NSSegmentedControl()
    let quotaRows = [textLabel(""), textLabel("")]
    let reset = textLabel("", size: 11, secondary: true)
    let connection = textLabel("正在连接 Codex…", size: 11, secondary: true)
    let notice = NSTextField(wrappingLabelWithString: "")
    let reduceMotion = NSButton(checkboxWithTitle: "减少动画", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    let refresh = NSButton(title: "刷新用量", target: nil, action: nil)
    let openCodex = NSButton(title: "打开 Codex", target: nil, action: nil)
    let quit = NSButton(title: "退出", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let name = textLabel("Codex Mac 状态栏", size: 14, weight: .semibold)
        place(name, 22, 18, 180, 22)
        badge.alignment = .right; place(badge, 204, 22, 116, 18)
        place(water, 22, 58, 92, 92)
        percentage.font = .monospacedDigitSystemFont(ofSize: 42, weight: .medium)
        place(percentage, 137, 56, 182, 54)
        place(quotaTitle, 140, 114, 180, 19)
        place(activityTitle, 24, 169, 296, 20)
        place(taskTitle, 24, 194, 296, 18)
        selection.segmentStyle = .rounded
        selection.trackingMode = .selectOne
        selection.font = .systemFont(ofSize: 11)
        place(selection, 22, 230, 300, 24)
        for (n, row) in quotaRows.enumerated() { place(row, 24, 269 + CGFloat(n * 26), 296, 20) }
        place(reset, 24, 328, 296, 18)
        place(connection, 24, 353, 296, 18)
        notice.font = .systemFont(ofSize: 11)
        notice.textColor = .secondaryLabelColor
        notice.maximumNumberOfLines = 3
        place(notice, 24, 381, 296, 47)
        reduceMotion.font = .systemFont(ofSize: 11)
        login.font = .systemFont(ofSize: 11)
        place(reduceMotion, 22, 440, 130, 22)
        place(login, 181, 440, 141, 22)
        for b in [refresh, openCodex, quit] { b.bezelStyle = .rounded; b.font = .systemFont(ofSize: 11) }
        place(refresh, 17, 482, 98, 28)
        place(openCodex, 116, 482, 120, 28)
        place(quit, 249, 482, 78, 28)
        let note = textLabel("水位＝剩余额度 · 颜色 / 流速＝本机忙碌程度", size: 10, secondary: true)
        note.alignment = .center; place(note, 18, 526, 308, 18)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        view.frame = NSRect(x: x, y: y, width: w, height: h); addSubview(view)
    }
    override func draw(_ dirtyRect: NSRect) {
        FlowPalette.panel.setFill(); bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        for y: CGFloat in [221, 430, 473] {
            let path = NSBezierPath(); path.move(to: NSPoint(x: 24, y: y)); path.line(to: NSPoint(x: bounds.width - 24, y: y)); path.lineWidth = 0.5; path.stroke()
        }
    }

    func update(usage: UsageSnapshot?, selected: UsageWindow?, activity: ActivitySummary?, usageError: String?, taskError: String?, stale: Bool) {
        let color = FlowPalette.color(activity)
        badge.stringValue = taskError != nil ? "状态不可用" : activity?.label ?? "连接中"
        badge.textColor = color
        percentage.stringValue = selected?.percentText ?? "—"
        quotaTitle.stringValue = (selected?.label ?? "额度不可用") + (stale && usage != nil ? " · 上次剩余" : " · 剩余")
        activityTitle.stringValue = taskError != nil ? "本机任务状态暂不可读" : activity?.detail ?? "正在检查本机任务"
        let live = activity?.tasks.filter { $0.phase == .working || $0.phase == .waiting }.sorted { $0.lastActivity > $1.lastActivity }.first
        if let live {
            taskTitle.stringValue = live.activity + " · " + live.title.replacingOccurrences(of: "\n", with: " ")
            taskTitle.toolTip = live.title
        } else { taskTitle.stringValue = "仅监测本机任务 · 不表示任务完成百分比"; taskTitle.toolTip = nil }
        let windows = usage?.windows ?? []
        selection.segmentCount = max(1, windows.count)
        for index in 0..<selection.segmentCount {
            selection.setLabel(index < windows.count ? windows[index].label : "等待额度数据", forSegment: index)
            selection.setWidth(300 / CGFloat(selection.segmentCount), forSegment: index)
        }
        selection.isEnabled = windows.count > 1
        selection.selectedSegment = windows.firstIndex { $0.minutes == selected?.minutes } ?? 0
        for (n, row) in quotaRows.enumerated() {
            if n < windows.count { row.stringValue = windows[n].label + "  ·  剩余 " + windows[n].percentText; row.textColor = .labelColor }
            else { row.stringValue = n == 1 && windows.count == 1 ? "当前账户只提供上述额度周期" : ""; row.textColor = .secondaryLabelColor }
        }
        if let date = selected?.resetsAt {
            if date <= Date() { reset.stringValue = "重置时间已到 · 等待服务器更新" }
            else {
                let remaining = Int(date.timeIntervalSinceNow / 60)
                let days = remaining / 1440, hours = remaining % 1440 / 60, minutes = remaining % 60
                reset.stringValue = "额度重置：" + (days > 0 ? "\(days) 天 " : "") + (hours > 0 ? "\(hours) 小时 " : "") + "\(minutes) 分钟后"
            }
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            reset.toolTip = formatter.string(from: date)
        } else { reset.stringValue = "服务器未提供重置时间"; reset.toolTip = nil }
        if let usage {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            connection.stringValue = (stale ? "上次数据 " : "用量更新 ") + formatter.string(from: usage.fetchedAt) + " · 每分钟刷新"
        } else { connection.stringValue = "正在通过 Codex 登录读取用量" }
        notice.stringValue = usageError ?? taskError ?? (activity?.uncertainCount ?? 0 > 0 ? "部分任务超过 3 分钟未写入日志，状态待确认。" : "任务每 2 秒检查；等待状态仅在日志明确记录时显示。远程与云任务不在监测范围。")
        notice.textColor = usageError != nil || taskError != nil ? .systemOrange : .secondaryLabelColor
        water.remaining = selected?.remaining; water.color = color; water.active = (activity?.activeCount ?? 0) > 0
        water.stale = stale; water.done = activity?.mode == .completed
        water.needsDisplay = true
    }
}
