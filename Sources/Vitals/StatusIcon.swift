import AppKit

/// The menu bar item's look, from the snapshot. The item has one fixed width (`fixedLength`), so the
/// menu bar never re-lays out and other icons don't slide in and out from behind the notch.
///   normal:   gauge + "RAM 52%" (template, follows the menu bar's color); the dot slot stays empty
///   warn:     the same + an amber dot
///   critical: red rounded pill with a white gauge and "Out of RAM"
enum StatusIcon {
    enum State: Equatable {
        case normal(pressure: Int)
        case warn(pressure: Int)
        case critical(pressure: Int)

        var isWarn: Bool { if case .warn = self { return true } else { return false } }
    }

    static let amber = NSColor(srgbRed: 0xE0 / 255, green: 0x9A / 255, blue: 0x1D / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xD0 / 255, green: 0x34 / 255, blue: 0x2C / 255, alpha: 1)

    /// `wasWarn`: swap must drop under 72% to leave warn after going over 75%, so the dot doesn't flicker
    /// while swap hovers at the line.
    static func state(from snap: [String: Any], wasWarn: Bool) -> State {
        let mem = snap["memory"] as? [String: Any] ?? [:]
        let pressure = Int(((mem["pressurePct"] as? Double) ?? 0).rounded())
        let level = mem["level"] as? String
        let used = (mem["swapUsedBytes"] as? NSNumber)?.doubleValue ?? 0
        let total = (mem["swapTotalBytes"] as? NSNumber)?.doubleValue ?? 0
        let swapFull = total > 0 && used / total > (wasWarn ? 0.72 : 0.75)
        if level == "critical" { return .critical(pressure: pressure) }
        if level == "warn" || swapFull { return .warn(pressure: pressure) }
        return .normal(pressure: pressure)
    }

    /// Tabular digits, padded to three with figure spaces, and a dot slot that's always there: every
    /// value takes the same width.
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    private static func title(pressure: Int, dot: NSColor) -> NSAttributedString {
        let digits = String(min(100, max(0, pressure)))
        let padded = String(repeating: "\u{2007}", count: 3 - digits.count) + digits
        let t = NSMutableAttributedString(string: " RAM \(padded)%", attributes: [.font: font])
        t.append(NSAttributedString(string: " ●", attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize * 0.6), .foregroundColor: dot,
            .baselineOffset: font.pointSize * 0.15,
        ]))
        return t
    }

    /// The widest the button gets (100% with the dot, or the critical pill), measured on the real button.
    static func fixedLength(for button: NSStatusBarButton) -> CGFloat {
        var widest: CGFloat = 0
        for state in [State.warn(pressure: 100), .critical(pressure: 100)] {
            apply(state, to: button)
            widest = max(widest, button.fittingSize.width)
        }
        return ceil(widest)
    }

    static func apply(_ state: State, to button: NSStatusBarButton) {
        switch state {
        case .normal(let p), .warn(let p):
            let warn = state.isWarn
            button.image = gauge(pressure: Double(p), color: .black, template: true)
            button.attributedTitle = title(pressure: p, dot: warn ? amber : .clear)
            button.imagePosition = .imageLeft
            button.toolTip = warn ? "Vitals: your Mac is short on memory (pressure \(p)%)" : "Vitals: memory pressure \(p)%"
        case .critical(let p):
            button.image = criticalPill(pressure: Double(p))
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.toolTip = "Vitals: out of memory"
        }
        button.setAccessibilityLabel(button.toolTip)
    }

    /// A half-circle gauge with the needle at `pressure` (0–100).
    static func gauge(pressure: Double, color: NSColor, template: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let img = NSImage(size: size, flipped: false) { _ in
            drawGauge(in: NSRect(origin: .zero, size: size), pressure: pressure, color: color)
            return true
        }
        img.isTemplate = template
        return img
    }

    private static func drawGauge(in r: NSRect, pressure: Double, color: NSColor) {
        let c = NSPoint(x: r.midX, y: r.minY + 3.5)
        let radius: CGFloat = 7.2
        color.setStroke()
        color.setFill()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: radius, startAngle: 195, endAngle: -15, clockwise: true)
        arc.lineWidth = 1.7
        arc.lineCapStyle = .round
        arc.stroke()
        let angle = (195 - 210 * min(100, max(0, pressure)) / 100) * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: c)
        needle.line(to: NSPoint(x: c.x + cos(angle) * (radius - 2.2), y: c.y + sin(angle) * (radius - 2.2)))
        needle.lineWidth = 1.7
        needle.lineCapStyle = .round
        needle.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
    }

    private static func criticalPill(pressure: Double) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let text = NSAttributedString(string: "Out of RAM", attributes: [.font: font, .foregroundColor: NSColor.white])
        let tw = ceil(text.size().width)
        let size = NSSize(width: 7 + 18 + 4 + tw + 8, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            red.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            drawGauge(in: NSRect(x: 7, y: 2, width: 18, height: 14), pressure: pressure, color: .white)
            text.draw(at: NSPoint(x: 7 + 18 + 4, y: (rect.height - text.size().height) / 2 + 0.5))
            return true
        }
    }
}
