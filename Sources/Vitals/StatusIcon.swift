import AppKit

/// The menu bar item's look, from the snapshot. Icon only, never any text, at one fixed width
/// (`fixedLength`), so the menu bar never re-lays out and other icons don't slide in and out from
/// behind the notch.
///   normally: three dials, CPU / GPU / RAM, each with its name under it (needles at CPU %, GPU % and
///             memory used %). All calm: a template image that follows the menu bar's color. A strained
///             dial and its name turn amber, red when critical; several can be colored at once.
///   heat or disk strained (no dial for them): that area's symbol + an amber or red dot, over the dials.
enum StatusIcon {
    enum Area: Int, CaseIterable {
        case memory, heat, disk, cpu, gpu // no battery: the system's own battery icon covers it

        var symbol: String {
            switch self {
            case .memory: "memorychip"
            case .heat: "thermometer.medium"
            case .disk: "internaldrive"
            case .cpu, .gpu: "cpu" // never shown: they have dials
            }
        }

        var name: String {
            switch self {
            case .memory: "memory"
            case .heat: "heat"
            case .disk: "disk space"
            case .cpu: "CPU"
            case .gpu: "GPU"
            }
        }
    }

    enum Severity: Int, Comparable {
        case ok, warn, critical
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    struct State: Equatable {
        /// The needles, in whole % (so a needle that moves less than that doesn't redraw).
        var cpu: Int, gpu: Int, ram: Int
        /// Areas that aren't ok.
        var levels: [Area: Severity] = [:]

        func level(_ a: Area) -> Severity { levels[a] ?? .ok }

        /// Same colors and every needle within 1%: drawn, the two can't be told apart.
        func looksLike(_ o: State) -> Bool {
            levels == o.levels && abs(cpu - o.cpu) < 2 && abs(gpu - o.gpu) < 2 && abs(ram - o.ram) < 2
        }

        /// Drawn as a template image (calm dials): the menu bar recolors it for light and dark by itself.
        var followsMenuBar: Bool { takeover == nil && StatusIcon.labels.allSatisfy { level($0.0) == .ok } }

        /// Heat or disk, whichever is worse (heat on a tie), when either is strained: shown instead of the dials.
        var takeover: Area? {
            let h = level(.heat), d = level(.disk)
            return h == .ok && d == .ok ? nil : h >= d ? .heat : .disk
        }
    }

    static let amber = NSColor(srgbRed: 0xE0 / 255, green: 0x9A / 255, blue: 0x1D / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xD0 / 255, green: 0x34 / 255, blue: 0x2C / 255, alpha: 1)

    /// Turns snapshots into a state. Remembers each area's last severity so a value hovering at a line
    /// doesn't flicker (each line is lower on the way out than on the way in), and how long CPU and GPU
    /// have been busy. Used only from the sampler's queue.
    final class Judge: @unchecked Sendable {
        private var last: [Area: Severity] = [:]
        private var busySince: [Area: Date] = [:]
        private var lastAt: Date?

        func state(from snap: [String: Any], now: Date = Date()) -> State {
            // After a sleep or a resting stretch the "busy for 30 s" clocks start over: time asleep isn't busy time.
            if let lastAt, now.timeIntervalSince(lastAt) > 10 { busySince = [:] }
            lastAt = now
            let mem = snap["memory"] as? [String: Any] ?? [:]
            let total = num(mem["totalBytes"]) ?? 0
            let used = total > 0 ? (num(mem["usedBytes"]) ?? 0) / total * 100 : 0
            let cpu = num((snap["cpu"] as? [String: Any])?["totalPct"]) ?? 0 // null on the first sample
            let gpu = num((snap["gpu"] as? [String: Any])?["pct"]) ?? 0
            var current: [Area: Severity] = [:]
            for area in Area.allCases { current[area] = judge(area, snap, was: last[area] ?? .ok, now: now) }
            last = current
            return State(cpu: step(cpu), gpu: step(gpu), ram: step(used), levels: current.filter { $0.value > .ok })
        }

        private func step(_ pct: Double) -> Int { Int(min(100, max(0, pct)).rounded()) }

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
            case .cpu, .gpu:
                // Strained once it has been at 85% or more for 30 s; leaves under 75%. Never critical.
                let total = area == .cpu ? num((snap["cpu"] as? [String: Any])?["totalPct"]) ?? 0
                    : num((snap["gpu"] as? [String: Any])?["pct"]) ?? 0
                if total >= 85 { busySince[area] = busySince[area] ?? now } else if total < 75 || was == .ok { busySince[area] = nil }
                if was >= .warn { return total >= 75 ? .warn : .ok }
                if let since = busySince[area], now.timeIntervalSince(since) >= 30 { return .warn }
                return .ok
            }
        }

        private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    }

    fileprivate static let labels: [(Area, String)] = [(.cpu, "CPU"), (.gpu, "GPU"), (.memory, "RAM")]

    /// Every kind of state the item can show, for measuring and for previews.
    static let allStates: [State] = {
        func st(_ cpu: Int, _ gpu: Int, _ ram: Int, _ levels: [Area: Severity] = [:]) -> State {
            State(cpu: cpu, gpu: gpu, ram: ram, levels: levels)
        }
        return [
            st(38, 10, 80), st(0, 0, 0), st(100, 100, 100),
            st(40, 12, 94, [.memory: .warn]), st(40, 12, 96, [.memory: .critical]),
            st(92, 30, 80, [.cpu: .warn]), st(45, 91, 80, [.gpu: .warn]), st(92, 30, 96, [.cpu: .warn, .memory: .critical]),
            st(38, 10, 80, [.heat: .warn]), st(38, 10, 80, [.heat: .critical]),
            st(38, 10, 80, [.disk: .warn]), st(38, 10, 80, [.disk: .critical]),
        ]
    }()

    /// The states the Help page pictures (`--render menubar`).
    static let helpStates: [State] = [0, 3, 4, 5, 6, 8, 9, 10, 11].map { allStates[$0] }

    /// The widest the button gets, measured over every state on the real button.
    static func fixedLength(for button: NSStatusBarButton) -> CGFloat {
        var widest: CGFloat = 0
        for state in allStates {
            apply(state, to: button)
            widest = max(widest, button.fittingSize.width)
        }
        return ceil(widest)
    }

    /// Draws `state` for the button's current appearance (call again when that changes: a non-template
    /// image's colors are fixed when it's made).
    static func apply(_ state: State, to button: NSStatusBarButton) {
        let appearance = button.effectiveAppearance
        var tip = "Vitals: CPU \(state.cpu)%, GPU \(state.gpu)%, memory \(state.ram)% used"
        let strained = Area.allCases.filter { state.level($0) > .ok }
        if !strained.isEmpty {
            tip += " — " + strained.map { "\($0.name) \(state.level($0) == .critical ? "critical" : "strained")" }
                .joined(separator: ", ")
        }
        if let area = state.takeover {
            button.image = symbol(area, critical: state.level(area) == .critical, appearance: appearance)
        } else {
            button.image = dials(state, appearance: appearance)
        }
        button.title = ""
        button.imagePosition = .imageOnly
        // Setting the tooltip hides one that's showing: only when the words change.
        if button.toolTip != tip { button.toolTip = tip }
        if button.accessibilityLabel() != tip { button.setAccessibilityLabel(tip) }
    }

    /// The three dials with their names under them. Template (follows the menu bar) when nothing is strained.
    static func dials(_ state: State, appearance: NSAppearance) -> NSImage {
        let calm = state.followsMenuBar
        let pcts = [state.cpu, state.gpu, state.ram]
        let img = NSImage(size: NSSize(width: 58, height: 22), flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                for (i, (area, name)) in labels.enumerated() {
                    let sev = state.level(area)
                    let ink: NSColor = calm ? .black : .labelColor
                    let color = sev == .critical ? red : sev == .warn ? amber : ink
                    let label = sev > .ok ? color : calm ? NSColor.black.withAlphaComponent(0.6) : .secondaryLabelColor
                    let cx = 9 + CGFloat(i) * 20
                    drawDial(center: NSPoint(x: cx, y: 10.9), radius: 6.9, pct: Double(pcts[i]), color: color)
                    let font = NSFont.systemFont(ofSize: 7, weight: .semibold)
                    let text = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: label])
                    text.draw(at: NSPoint(x: cx - text.size().width / 2, y: 19.6 - font.ascender))
                }
            }
            return true
        }
        img.isTemplate = calm
        return img
    }

    /// A gauge with the needle at `pct` (0–100), y down: the arc runs from 190° to -10°.
    private static func drawDial(center c: NSPoint, radius r: CGFloat, pct: Double, color: NSColor) {
        color.setStroke()
        color.setFill()
        let arc = NSBezierPath()
        // Flipped: angles go clockwise on screen, so draw the top half from 170° to 370°.
        arc.appendArc(withCenter: c, radius: r, startAngle: 170, endAngle: 370, clockwise: false)
        arc.lineWidth = 1.7
        arc.lineCapStyle = .round
        arc.stroke()
        let angle = (190 - 200 * CGFloat(min(100, max(0, pct))) / 100) * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: c)
        needle.line(to: NSPoint(x: c.x + cos(angle) * (r - 2.1), y: c.y - sin(angle) * (r - 2.1)))
        needle.lineWidth = 1.7
        needle.lineCapStyle = .round
        needle.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
    }

    /// The area's SF Symbol with an amber (or red, when critical) dot after it.
    static func symbol(_ area: Area, critical: Bool, appearance: NSAppearance) -> NSImage {
        let img = NSImage(size: NSSize(width: 28, height: 16), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let color: NSColor = critical ? red : .labelColor
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
                if let sym = NSImage(systemSymbolName: area.symbol, accessibilityDescription: area.name)?
                    .withSymbolConfiguration(config) {
                    let s = sym.size
                    let scale = min(1, 18 / s.width, 16 / s.height)
                    let w = s.width * scale, h = s.height * scale
                    sym.draw(in: NSRect(x: 9 - w / 2, y: 8 - h / 2, width: w, height: h))
                }
                (critical ? red : amber).setFill()
                NSBezierPath(ovalIn: NSRect(x: 21, y: 5.5, width: 5, height: 5)).fill()
            }
            return true
        }
        return img
    }
}
