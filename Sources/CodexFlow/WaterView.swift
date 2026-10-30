import AppKit
import FlowCore

enum FlowPalette {
    static var panel: NSColor { NSColor(name: "FlowPanel") { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.23, alpha: 1) : NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1) } }
    static func color(_ summary: ActivitySummary?) -> NSColor {
        guard let summary else { return .systemGray }
        switch summary.mode {
        case .idle, .completed: return NSColor(calibratedRed: 0.29, green: 0.73, blue: 0.53, alpha: 1)
        case .working, .busy:
            let t = min(1, Double(max(0, summary.activeCount - 1)) / 3)
            let green = NSColor(calibratedRed: 0.55, green: 0.76, blue: 0.31, alpha: 1)
            let yellow = NSColor(calibratedRed: 0.93, green: 0.69, blue: 0.24, alpha: 1)
            let red = NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.26, alpha: 1)
            return t < 0.5 ? green.blended(withFraction: t * 2, of: yellow)! : yellow.blended(withFraction: (t - 0.5) * 2, of: red)!
        case .waiting: return .systemOrange
        case .unknown: return .systemGray
        }
    }
    static func speed(_ summary: ActivitySummary?) -> Double {
        guard let summary else { return 0.3 }
        switch summary.mode {
        case .waiting, .unknown: return 0
        case .idle, .completed: return 0.4
        default: return 1 + Double(min(5, summary.activeCount)) * 0.65
        }
    }
}

enum WaterDrawing {
    static func draw(in rect: NSRect, remaining: Double?, phase: Double, color: NSColor, active: Bool, stale: Bool, done: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
        color.withAlphaComponent(0.10).setFill(); circle.fill()
        circle.addClip()
        if let remaining, remaining > 0 {
            let level = rect.minY + rect.height * CGFloat(min(100, max(0, remaining)) / 100)
            let amplitude = remaining >= 99.5 ? 0 : rect.height * (active ? 0.038 : 0.02)
            for layer in 0..<2 {
                let wave = NSBezierPath()
                wave.move(to: NSPoint(x: rect.minX, y: rect.minY))
                wave.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                for n in stride(from: 64, through: 0, by: -1) {
                    let x = CGFloat(n) / 64
                    let offset = sin(Double(x) * .pi * 2 + phase * (layer == 0 ? 1 : -0.75) + Double(layer) * 1.9)
                    wave.line(to: NSPoint(x: rect.minX + x * rect.width, y: level + CGFloat(offset) * amplitude))
                }
                wave.close()
                color.withAlphaComponent(layer == 0 ? 0.40 : 0.90).setFill(); wave.fill()
            }
        }
        let sheen = NSGradient(starting: NSColor.white.withAlphaComponent(0.27), ending: NSColor.white.withAlphaComponent(0))
        sheen?.draw(in: circle, angle: -45)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        circle.lineWidth = max(0.7, rect.width / 140); circle.stroke()
        if done, let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "任务已完成") {
            let size = rect.width * 0.43
            image.draw(in: NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size))
        }
        if stale {
            let diameter = max(4, rect.width * 0.12)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)).fill()
        }
    }

    static func image(remaining: Double?, phase: Double, color: NSColor, active: Bool, stale: Bool, done: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            draw(in: rect.insetBy(dx: 1, dy: 1), remaining: remaining, phase: phase, color: color, active: active, stale: stale, done: done)
            return true
        }
        image.isTemplate = false
        return image
    }
}

final class WaterView: NSView {
    var remaining: Double?
    var phase: Double = 0
    var color = NSColor.systemGray
    var active = false
    var stale = false
    var done = false
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        WaterDrawing.draw(in: bounds.insetBy(dx: 3, dy: 3), remaining: remaining, phase: phase, color: color, active: active, stale: stale, done: done)
    }
}
