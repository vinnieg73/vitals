import AppKit

/// The menu bar item's look, from the snapshot. Icon only, never any text, at one fixed width
/// (`fixedLength`), so the menu bar never re-lays out and other icons don't slide in and out from
/// behind the notch.
///   calm:     the memory gauge (template, follows the menu bar's color); the dot slot stays empty
///   strained: the strained area's symbol (template) + an amber dot
///   critical: the area's symbol in red + a red dot
/// With several areas strained, the most severe wins; on a tie, the first in `Area`'s order.
enum StatusIcon {
    enum Area: Int, CaseIterable {
        case memory, heat, disk, cpu // tie order (no battery: the system's own battery icon covers it)

        var symbol: String {
            switch self {
            case .memory: "memorychip"
            case .heat: "thermometer.medium"
            case .disk: "internaldrive"
            case .cpu: "cpu"
            }
        }

        var name: String {
            switch self {
            case .memory: "memory"
            case .heat: "heat"
            case .disk: "disk space"
            case .cpu: "CPU"
            }
        }
    }

    enum Severity: Int, Comparable {
        case ok, warn, critical
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    struct State: Equatable {
        var area: Area? // nil: calm
        var severity: Severity
        var pressure: Int // for the calm gauge's needle

        static func calm(_ pressure: Int) -> State { State(area: nil, severity: .ok, pressure: pressure) }
    }

    static let amber = NSColor(srgbRed: 0xE0 / 255, green: 0x9A / 255, blue: 0x1D / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xD0 / 255, green: 0x34 / 255, blue: 0x2C / 255, alpha: 1)

    /// Turns snapshots into a state. Remembers each area's last severity so a value hovering at a line
    /// doesn't flicker (each line is lower on the way out than on the way in), and how long CPU has been
    /// busy. Used only from the sampler's queue.
    final class Judge: @unchecked Sendable {
        private var last: [Area: Severity] = [:]
        private var cpuBusySince: Date?

        func state(from snap: [String: Any], now: Date = Date()) -> State {
            let mem = snap["memory"] as? [String: Any] ?? [:]
            let pressure = num(mem["pressurePct"]) ?? 0
            var current: [Area: Severity] = [:]
            for area in Area.allCases { current[area] = judge(area, snap, was: last[area] ?? .ok, now: now) }
            last = current
            let worst = Area.allCases.max { a, b in
                let sa = current[a] ?? .ok, sb = current[b] ?? .ok
                return sa != sb ? sa < sb : a.rawValue > b.rawValue // ties go to the earlier area
            }
            guard let area = worst, let sev = current[area], sev > .ok else { return .calm(Int(pressure.rounded())) }
            return State(area: area, severity: sev, pressure: Int(pressure.rounded()))
        }

        private func judge(_ area: Area, _ snap: [String: Any], was: Severity, now: Date) -> Severity {
            switch area {
            case .memory:
                // As the pages' memStateAt. Swap by size, not by how full the swap files are: macOS adds a
                // 1 GB file only when the ones it has are nearly full, so "% full" is nearly always high.
                // Strained: level warn, pressure 70+, or swap at max(4 GiB, 45% of RAM). Critical: level
                // critical, or pressure 85+ with swap at 75% of RAM. Strained clears under pressure 65 and
                // 1 GiB under the swap line; critical clears under pressure 80 or 1 GiB under its swap line.
                let m = snap["memory"] as? [String: Any] ?? [:]
                let level = m["level"] as? String
                let p = num(m["pressurePct"]) ?? 0
                let swap = num(m["swapUsedBytes"]) ?? 0
                let gib = 1_073_741_824.0
                let ram = num(m["totalBytes"]).flatMap { $0 > 0 ? $0 : nil } ?? 16 * gib // as the pages, if unknown
                let warnAt = max(4 * gib, 0.45 * ram), critAt = 0.75 * ram
                let crit = was == .critical, held = was >= .warn
                if level == "critical" || (p >= (crit ? 80 : 85) && swap >= (crit ? critAt - gib : critAt)) { return .critical }
                if level == "warn" || p >= (held ? 65 : 70) || swap >= (held ? warnAt - gib : warnAt) { return .warn }
                return .ok
            case .heat:
                switch (snap["energy"] as? [String: Any])?["thermal"] as? String {
                case "critical": return .critical
                case "serious": return .warn
                default: return .ok
                }
            case .disk:
                let d = snap["disk"] as? [String: Any] ?? [:]
                guard let total = num(d["totalBytes"]), total > 0, let free = num(d["freeBytes"]) else { return .ok }
                let frac = free / total
                if frac < (was == .critical ? 0.04 : 0.03) { return .critical }
                if frac < (was >= .warn ? 0.12 : 0.10) { return .warn }
                return .ok
            case .cpu:
                // Strained once it has been at 85% or more for 30 s; leaves under 75%. Never critical.
                let total = num((snap["cpu"] as? [String: Any])?["totalPct"]) ?? 0
                if total >= 85 { cpuBusySince = cpuBusySince ?? now } else if total < 75 || was == .ok { cpuBusySince = nil }
                if was >= .warn { return total >= 75 ? .warn : .ok }
                if let since = cpuBusySince, now.timeIntervalSince(since) >= 30 { return .warn }
                return .ok
            }
        }

        private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    }

    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    /// Every state the item can show, for measuring and for previews.
    static let allStates: [State] = [.calm(52)] + Area.allCases.flatMap { a in
        (a == .cpu ? [Severity.warn] : [.warn, .critical]).map { State(area: a, severity: $0, pressure: 80) }
    }

    /// The widest the button gets (every state is drawn in the same canvas, but measure them all), on the
    /// real button.
    static func fixedLength(for button: NSStatusBarButton) -> CGFloat {
        var widest: CGFloat = 0
        for state in allStates {
            apply(state, to: button)
            widest = max(widest, button.fittingSize.width)
        }
        return ceil(widest)
    }

    static func apply(_ state: State, to button: NSStatusBarButton) {
        let dot: NSColor
        if let area = state.area {
            let critical = state.severity == .critical
            button.image = symbol(area, color: critical ? red : nil)
            dot = critical ? red : amber
            button.toolTip = critical ? "Vitals: \(area.name) is critical" : "Vitals: \(area.name) is strained"
        } else {
            button.image = gauge(pressure: Double(state.pressure), color: .black, template: true)
            dot = .clear
            button.toolTip = "Vitals: all calm (memory pressure \(state.pressure)%)"
        }
        // The dot slot is always there (clear when all's calm), so the width never changes.
        button.attributedTitle = NSAttributedString(string: " ●", attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize * 0.6), .foregroundColor: dot,
            .baselineOffset: font.pointSize * 0.15,
        ])
        button.imagePosition = .imageLeft
        button.setAccessibilityLabel(button.toolTip)
    }

    /// The area's SF Symbol, fitted into a canvas as wide as the gauge (18 pt) so every state has the
    /// same width. `color` nil: a template image that follows the menu bar.
    static func symbol(_ area: Area, color: NSColor?) -> NSImage {
        let canvas = NSSize(width: 18, height: 16)
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let color { config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color])) }
        guard let sym = NSImage(systemSymbolName: area.symbol, accessibilityDescription: area.name)?
            .withSymbolConfiguration(config) else { return gauge(pressure: 80, color: color ?? .black, template: color == nil) }
        let img = NSImage(size: canvas, flipped: false) { rect in
            let s = sym.size
            let scale = min(1, rect.width / s.width, rect.height / s.height)
            let w = s.width * scale, h = s.height * scale
            sym.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
            return true
        }
        img.isTemplate = color == nil
        return img
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
}
