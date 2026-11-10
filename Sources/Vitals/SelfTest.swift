import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement

/// `Vitals --selftest`: checks the rules that can't be seen from a single `--dump`, without any window or
/// menu bar item. About 25 s (it waits out a real resting stretch). Prints PASS / FAIL per check; exit 1 on any FAIL.
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)\(ok ? "" : "  (\(detail()))")")
        fflush(stdout)
    }

    static func run() -> Never {
        flags()
        baseline()
        judge()
        strain()
        deadband()
        menus()
        tidy()
        gaps()
        nettop()
        scripts()
        users()
        sessionModels()
        longHistory()
        savedHistory()
        kicks()
        sampler()
        icon()   // last: it makes a real status bar button, and AppKit then naps the timers the checks above wait on
        print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// An option Vitals doesn't know is refused, so a typo (or a flag from a newer build) can't start a second
    /// menu bar copy.
    private static func flags() {
        check("flags: every real option is known", Flags.unknown(in: ["Vitals"]) == nil
              && Flags.unknown(in: ["Vitals", "--dump", "--bench"]) == nil
              && Flags.unknown(in: ["Vitals", "--render", "window", "out.png", "dark", "--warm", "40"]) == nil
              && Flags.unknown(in: ["Vitals", "--soak", "6", "window"]) == nil
              && Flags.unknown(in: ["Vitals", "--status-log", "--status-test"]) == nil
              && Flags.unknown(in: ["Vitals", "--selftest"]) == nil && Flags.unknown(in: ["Vitals", "--login-status"]) == nil)
        check("flags: an unknown option is refused", Flags.unknown(in: ["Vitals", "--login-staus"]) == "--login-staus"
              && Flags.unknown(in: ["Vitals", "--dump", "--scan"]) == "--scan")
        check("flags: what macOS itself passes (one dash) is let through",
              Flags.unknown(in: ["Vitals", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    }

    /// "Today" totals: a boot time that moves a second is not a reboot; a real reboot, a new day, an interface
    /// that's down at midnight, and a relaunch the same day.
    private static func baseline() {
        let suite = "com.vinnie.vitals.selftest"
        guard let store = UserDefaults(suiteName: suite) else { check("baseline store", false, "no suite"); return }
        store.removePersistentDomain(forName: suite)
        defer { store.removePersistentDomain(forName: suite) }

        let d = DailyBaseline(store: store, bootSession: nil)   // no boot session id: the boot time rule
        check("baseline: first run counts since boot", d.today(["diskR": 1000], day: "2026-10-19", boot: 1000)["diskR"] == 1000)
        _ = d.today(["diskR": 1500], day: "2026-10-19", boot: 1000)
        check("baseline: new day starts from the last value", d.today(["diskR": 2000], day: "2026-10-20", boot: 1000)["diskR"] == 500)
        let shifted = d.today(["diskR": 2600], day: "2026-10-20", boot: 1001)["diskR"]
        check("baseline: boot time 1 s later is not a reboot", shifted == 1100, "got \(shifted.map(String.init) ?? "nil"), want 1100")
        let shiftedBack = d.today(["diskR": 2700], day: "2026-10-20", boot: 1000)["diskR"]
        check("baseline: boot time 1 s earlier is not a reboot", shiftedBack == 1200, "got \(shiftedBack.map(String.init) ?? "nil")")
        check("baseline: a real reboot counts since boot", d.today(["diskR": 300], day: "2026-10-20", boot: 9000)["diskR"] == 300)

        _ = d.today(["diskR": 400, "netI.en0": 5000], day: "2026-10-20", boot: 9000)
        _ = d.today(["diskR": 700], day: "2026-10-20", boot: 9000)             // en0 down before midnight
        _ = d.today(["diskR": 800], day: "2026-10-21", boot: 9000)             // midnight, en0 still down
        let net = d.today(["diskR": 900, "netI.en0": 5050], day: "2026-10-21", boot: 9000)["netI.en0"]
        check("baseline: interface down at midnight keeps its baseline", net == 50, "got \(net.map(String.init) ?? "nil"), want 50")
        let restarted = d.today(["diskR": 950, "netI.en0": 20], day: "2026-10-21", boot: 9000)["netI.en0"]
        let after = d.today(["diskR": 960, "netI.en0": 70], day: "2026-10-21", boot: 9000)["netI.en0"]
        check("baseline: a restarted counter counts from zero", restarted == 20 && after == 70,
              "got \(restarted.map(String.init) ?? "nil") then \(after.map(String.init) ?? "nil")")

        d.save()
        let again = DailyBaseline(store: store, bootSession: nil).today(["diskR": 1000], day: "2026-10-21", boot: 9000)["diskR"]
        check("baseline: relaunch the same day keeps the baseline", again == 300, "got \(again.map(String.init) ?? "nil"), want 300")

        // With a boot session id (kern.bootsessionuuid), only a new id is a reboot: changing the clock by hand
        // moves the boot time by as much, and mustn't reset "today".
        store.removePersistentDomain(forName: suite)
        let s = DailyBaseline(store: store, bootSession: "A")
        _ = s.today(["diskR": 1000], day: "2026-10-20", boot: 1000)
        _ = s.today(["diskR": 1600], day: "2026-10-21", boot: 1000)            // midnight: baseline 1000
        let moved = s.today(["diskR": 1700], day: "2026-10-21", boot: 1000 + 2 * 3600)["diskR"]
        check("baseline: a clock moved 2 hours on is not a reboot", moved == 700, "got \(moved.map(String.init) ?? "nil"), want 700")
        let back = s.today(["diskR": 1800], day: "2026-10-21", boot: 1000 - 5 * 3600)["diskR"]
        check("baseline: a clock moved 5 hours back is not a reboot", back == 800, "got \(back.map(String.init) ?? "nil"), want 800")
        let reboot = s.today(["diskR": 40], day: "2026-10-21", boot: 1000 - 5 * 3600, session: "B")["diskR"]
        check("baseline: a new boot session is a reboot", reboot == 40, "got \(reboot.map(String.init) ?? "nil"), want 40")
        s.save()
        let relaunch = DailyBaseline(store: store, bootSession: "B").today(["diskR": 90], day: "2026-10-21", boot: 77777)["diskR"]
        check("baseline: relaunch in the same boot keeps the baseline", relaunch == 90, "got \(relaunch.map(String.init) ?? "nil"), want 90")

        // A baseline saved by an older Vitals has no session id: the boot time decides once, then the id is kept.
        store.removePersistentDomain(forName: suite)
        let old = DailyBaseline(store: store, bootSession: nil)
        _ = old.today(["diskR": 1000], day: "2026-10-21", boot: 5000)
        _ = old.today(["diskR": 1200], day: "2026-10-22", boot: 5000)
        old.save()
        let upgraded = DailyBaseline(store: store, bootSession: "C")
        let up1 = upgraded.today(["diskR": 1300], day: "2026-10-22", boot: 5001)["diskR"]
        let up2 = upgraded.today(["diskR": 1400], day: "2026-10-22", boot: 5001 + 3600)["diskR"]
        check("baseline: an older saved baseline carries over, then a clock change is ignored", up1 == 300 && up2 == 400,
              "got \(up1.map(String.init) ?? "nil") then \(up2.map(String.init) ?? "nil"), want 300 then 400")
        check("baseline: this Mac has a boot session id", Sysctl.string("kern.bootsessionuuid")?.isEmpty == false)

        // "Today" and the snapshot time follow a time zone change (12:00 UTC is the 21st at UTC+14, the 20th at UTC-11).
        let noon = Date(timeIntervalSince1970: 1_792_497_600)   // 2026-10-20 12:00 UTC
        let east = TimeZone(identifier: "Pacific/Kiritimati")!, west = TimeZone(identifier: "Pacific/Pago_Pago")!
        let days = [DailyBaseline.dayString(noon, zone: east), DailyBaseline.dayString(noon, zone: west)]
        check("today: the day follows a time zone change", days == ["2026-10-21", "2026-10-20"], days.joined(separator: ", "))
        let times = [Sampler.timeString(noon, zone: east), Sampler.timeString(noon, zone: west)]
        check("today: the snapshot time follows a time zone change", times[0].hasSuffix("+14:00") && times[1].hasSuffix("-11:00"), times.joined(separator: ", "))
        _ = DailyBaseline.dayString(noon)   // back to this Mac's zone for the rest of the run
        _ = Sampler.timeString(noon)
    }

    /// CPU "busy for 30 s": still flags a steady 30 s, but time asleep doesn't count toward it.
    private static func judge() {
        func snap(_ cpu: Double) -> [String: Any] {
            ["cpu": ["totalPct": cpu], "gpu": ["pct": 0.0],
             "memory": ["totalBytes": 16 * 1_073_741_824.0, "usedBytes": 8 * 1_073_741_824.0, "pressurePct": 30.0, "level": "normal"]]
        }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var j = StatusIcon.Judge()
        var s = StatusIcon.State(cpu: 0, gpu: 0, ram: 0)
        for t in stride(from: 0.0, through: 28, by: 2) { s = j.state(from: snap(90), now: t0 + t) }
        check("judge: 28 s busy is still calm", s.level(.cpu) == .ok)
        s = j.state(from: snap(90), now: t0 + 32)
        check("judge: 32 s busy turns the CPU dial amber", s.level(.cpu) == .warn)

        j = StatusIcon.Judge()
        for t in stride(from: 0.0, through: 20, by: 2) { s = j.state(from: snap(90), now: t0 + t) }
        // 60 s asleep, then busy again right after waking
        for t in stride(from: 80.0, through: 104, by: 2) { s = j.state(from: snap(90), now: t0 + t) }
        check("judge: time asleep doesn't count as busy", s.level(.cpu) == .ok)
        for t in stride(from: 106.0, through: 112, by: 2) { s = j.state(from: snap(90), now: t0 + t) }
        check("judge: 30 s busy after waking turns amber", s.level(.cpu) == .warn)
    }

    /// One verdict for the menu bar item and the pages: the judge's, with its hysteresis, sent in the snapshot's
    /// `strain` block. (The pages used to work it out again with plain lines and could disagree.)
    private static func strain() {
        let gib = 1_073_741_824.0
        func snap(_ pressure: Double, swap: Double = 0, level: String = "normal") -> [String: Any] {
            ["cpu": ["totalPct": 10.0], "gpu": ["pct": 0.0],
             "memory": ["totalBytes": 16 * gib, "usedBytes": 8 * gib, "pressurePct": pressure, "level": level, "swapUsedBytes": swap * gib]]
        }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let j = StatusIcon.Judge()
        var t = 0.0
        /// The memory and swap words after one more sample, plus whether the icon's state says the same.
        func step(_ s: [String: Any]) -> (mem: String, swap: String, icon: StatusIcon.Severity) {
            t += 2
            let state = j.state(from: s, now: t0 + t)
            return (j.block["memory"] as? String ?? "?", j.block["swap"] as? String ?? "?", state.level(.memory))
        }
        var r = step(snap(69))
        check("strain: pressure 69 is calm", r.mem == "ok" && r.icon == .ok, "\(r)")
        r = step(snap(71))
        check("strain: pressure 71 is strained", r.mem == "warn" && r.icon == .warn, "\(r)")
        r = step(snap(67))
        check("strain: back at 67 the icon holds amber, and the pages are told the same", r.mem == "warn" && r.icon == .warn, "\(r)")
        r = step(snap(64))
        check("strain: under 65 both let go", r.mem == "ok" && r.icon == .ok && r.swap == "ok", "\(r)")
        // 16 GB of RAM: the swap line is 7.2 GB, let go at 6.2; critical is pressure 85 with swap at 12 GB.
        r = step(snap(30, swap: 7.3))
        check("strain: swap over its line colors memory and the swap number", r.mem == "warn" && r.swap == "warn", "\(r)")
        r = step(snap(30, swap: 6.5))
        check("strain: swap just under its line is held, for both", r.mem == "warn" && r.swap == "warn", "\(r)")
        r = step(snap(30, swap: 6.0))
        check("strain: 1 GB under the swap line both let go", r.mem == "ok" && r.swap == "ok", "\(r)")
        r = step(snap(86, swap: 12.1))
        check("strain: pressure 86 with swap at 75% of RAM is critical, the swap number too", r.mem == "crit" && r.swap == "crit" && r.icon == .critical, "\(r)")
        r = step(snap(82, swap: 11.5))
        check("strain: critical is held down to pressure 80", r.mem == "crit" && r.swap == "crit", "\(r)")
        r = step(snap(78, swap: 11.5))
        check("strain: under 80 it's strained, not critical", r.mem == "warn" && r.swap == "warn" && r.icon == .warn, "\(r)")
        r = step(snap(30, level: "critical"))
        check("strain: macOS saying critical is critical; the swap number stays calm with little swap", r.mem == "crit" && r.swap == "ok", "\(r)")

        let keys = Set(j.block.keys)
        check("strain: the block names every area and the swap number", keys == ["memory", "swap", "cpu", "gpu", "heat", "disk"], "\(keys.sorted())")
        // The menu bar item is drawn from the block alone: same colors as the judge's own state.
        var full = snap(71)
        let judged = j.state(from: full, now: t0 + t + 2)
        full["strain"] = j.block
        check("strain: the icon drawn from a snapshot matches the judge", StatusIcon.State(snapshot: full) == judged && judged.level(.memory) == .warn,
              "\(judged) vs \(StatusIcon.State(snapshot: full))")
        var noBlock = snap(99, swap: 15, level: "critical")
        noBlock["strain"] = nil
        check("strain: without the block the icon colors nothing by itself", StatusIcon.State(snapshot: noBlock).levels.isEmpty)
    }

    /// The dials redraw only when a needle moves 2% or more, or a color changes.
    private static func deadband() {
        let a = StatusIcon.State(cpu: 40, gpu: 10, ram: 70)
        check("dials: a 1% move doesn't redraw", a.looksLike(StatusIcon.State(cpu: 41, gpu: 9, ram: 71)))
        check("dials: a 2% move redraws", !a.looksLike(StatusIcon.State(cpu: 42, gpu: 10, ram: 70)))
        check("dials: a color change redraws", !a.looksLike(StatusIcon.State(cpu: 40, gpu: 10, ram: 70, levels: [.memory: .warn])))
    }

    /// Heat and low disk space: the symbol itself is amber or red (no dot beside it), and the item is one width
    /// whatever it shows.
    private static func icon() {
        // Every solid pixel of the drawn image, as (red, green, blue) 0-255.
        func solid(_ img: NSImage) -> [(Int, Int, Int)] {
            let w = Int(img.size.width) * 3, h = Int(img.size.height) * 3
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { return [] }
            rep.size = img.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            img.draw(in: NSRect(origin: .zero, size: img.size))
            NSGraphicsContext.restoreGraphicsState()
            var out: [(Int, Int, Int)] = []
            for y in 0..<h { for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.6 else { continue }
                out.append((Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255)))
            } }
            return out
        }
        func isAmber(_ p: (Int, Int, Int)) -> Bool { p.0 > 190 && (110...200).contains(p.1) && p.2 < 90 }
        func isRed(_ p: (Int, Int, Int)) -> Bool { p.0 > 170 && p.1 < 100 && p.2 < 100 }
        for area in [StatusIcon.Area.heat, .disk] {
            let warn = solid(StatusIcon.symbol(area, critical: false)), crit = solid(StatusIcon.symbol(area, critical: true))
            check("icon: strained \(area.name) is an amber symbol, nothing else", warn.count > 30 && warn.allSatisfy(isAmber),
                  "\(warn.count) solid pixels, \(warn.filter { !isAmber($0) }.count) not amber")
            check("icon: critical \(area.name) is a red symbol, nothing else", crit.count > 30 && crit.allSatisfy(isRed),
                  "\(crit.count) solid pixels, \(crit.filter { !isRed($0) }.count) not red")
        }
        // The same button the menu bar uses, off screen: no state is wider than the dials, and none has text.
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let widths = StatusIcon.allStates.map { state -> CGFloat in
            StatusIcon.apply(state, to: button)
            return button.fittingSize.width
        }
        let titles = StatusIcon.allStates.map { state -> String in StatusIcon.apply(state, to: button); return button.title }
        let fixed = StatusIcon.fixedLength(for: button), dials = StatusIcon.dials(StatusIcon.allStates[0], appearance: button.effectiveAppearance)
        check("icon: one width whatever it shows (the dials', a 58 pt picture)", dials.size.width == 58 && widths[0] == fixed
              && widths.allSatisfy { $0 <= fixed }, "fixed \(fixed), widths \(widths)")
        check("icon: never any text", titles.allSatisfy { $0.isEmpty }, "\(titles)")
    }

    /// Quit only ever reaches the process the sheet asked about; Open at Login shows "needs approval";
    /// a shortcut another app already holds is reported, not silently dead.
    private static func menus() {
        let me = getpid()
        let started = ProcessSampler.startTime(me)
        check("quit: reads a process's start time", started != nil)
        check("quit: the same process passes", AppDelegate.sameProcess(pid: me, started: started))
        check("quit: a new process with the same pid is left alone", !AppDelegate.sameProcess(pid: me, started: started.map { $0 &+ 1 }))
        check("quit: no start time, no quit", !AppDelegate.sameProcess(pid: me, started: nil))
        // The page gets the start time on every row, as a string it hands back unchanged.
        func find(_ rows: [Row]) -> Row? {
            for r in rows { if r.pid == me && r.id == "pid:\(me)" { return r }; if let k = find(r.children) { return k } }
            return nil
        }
        let row = find(ProcessSampler().sample().rows)
        let sent = row?.json()["started"] as? String
        check("quit: the page gets the start time", sent != nil && sent.flatMap { UInt64($0) } == started, "\(sent ?? "nil")")

        typealias R = AppDelegate
        check("rest: an awake, unlocked session doesn't rest at launch",
              R.restingAtLaunch(session: ["CGSSessionScreenIsLocked": false, "kCGSSessionOnConsoleKey": true], displaysAsleep: false).isEmpty)
        check("rest: started while locked rests at once",
              R.restingAtLaunch(session: ["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true], displaysAsleep: false) == ["locked"])
        check("rest: started with the screens asleep rests at once",
              R.restingAtLaunch(session: ["kCGSSessionOnConsoleKey": true], displaysAsleep: true) == ["screens"])
        check("rest: started behind another user's session rests at once",
              R.restingAtLaunch(session: ["kCGSSessionOnConsoleKey": false], displaysAsleep: false) == ["session"])
        check("rest: no session info counts as awake", R.restingAtLaunch(session: nil, displaysAsleep: false).isEmpty)
        check("rest: lid shut or locked keeps sampling every 2 s", !R.slowsSampling(["screens", "locked"]) && !R.slowsSampling([]))
        check("rest: another user's session in front slows to once a minute", R.slowsSampling(["session"]) && R.slowsSampling(["session", "screens"]))
        let realSession = CGSessionCopyCurrentDictionary() as? [String: Any]
        check("rest: the login session's state can be read", realSession != nil, "CGSessionCopyCurrentDictionary gave nil (run from a logged-in session)")

        check("login: on shows a check", AppDelegate.loginItem(.enabled) == ("Open at Login", .on))
        check("login: off shows no check", AppDelegate.loginItem(.notRegistered) == ("Open at Login", .off))
        let pending = AppDelegate.loginItem(.requiresApproval)
        check("login: opens by itself when it's not registered", AppDelegate.shouldRegisterLogin(.notRegistered, turnedOffByUser: false))
        check("login: a never-registered copy (notFound) counts as not registered", AppDelegate.shouldRegisterLogin(.notFound, turnedOffByUser: false))
        check("login: ...but not after he turned it off", !AppDelegate.shouldRegisterLogin(.notRegistered, turnedOffByUser: true))
        check("login: ...and leaves a pending or enabled one alone", !AppDelegate.shouldRegisterLogin(.enabled, turnedOffByUser: false)
              && !AppDelegate.shouldRegisterLogin(.requiresApproval, turnedOffByUser: false))
        check("login: waiting on Settings says so", pending.1 == .mixed && pending.0.contains("Settings"), pending.0)

        // An odd shortcut nobody uses (⌃⌥⇧⌘F19), taken twice by this process.
        let mods = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let a = Hotkey(keyCode: UInt32(kVK_F19), modifiers: mods) {}
        let b = Hotkey(keyCode: UInt32(kVK_F19), modifiers: mods) {}
        check("hotkey: a free shortcut registers", a.registered)
        check("hotkey: a shortcut that's already taken says so", !b.registered)
        // The system list's modifiers may be Carbon or Cocoa flags: both read the same.
        let ctrlOptCmd = UInt32(cmdKey | optionKey | controlKey)
        check("hotkey: Carbon modifiers read as themselves", Hotkey.carbonModifiers(ctrlOptCmd) == ctrlOptCmd)
        check("hotkey: Cocoa modifiers (⌃⌥⌘ = 0x1C0000) read as Carbon", Hotkey.carbonModifiers(0x1C_0000) == ctrlOptCmd,
              "\(Hotkey.carbonModifiers(0x1C_0000))")
        check("hotkey: fn and caps lock bits don't count", Hotkey.carbonModifiers(0x80_0000 | 0x1_0000 | 0x10_0000) == UInt32(cmdKey)
              && Hotkey.carbonModifiers(UInt32(cmdKey | alphaLock)) == UInt32(cmdKey))
        // macOS's own shortcuts (Spotlight's ⌘Space and the like) hold a key without any app registering it.
        let system = Hotkey.systemShortcuts()
        check("hotkey: macOS's own shortcuts can be read", !system.isEmpty, "CopySymbolicHotKeys gave none")
        check("hotkey: the odd test shortcut isn't one of macOS's", !a.takenBySystem)
        // macOS's Space shortcuts (Spotlight ⌘Space, input sources ⌃Space…) never have no modifiers: reading none
        // would mean the units are wrong.
        let space = system.filter { $0.code == 49 }.map { Hotkey.carbonModifiers($0.mods) }
        if !space.isEmpty {
            check("hotkey: macOS's Space shortcuts read with modifiers", !space.contains(0),
                  "raw \(system.filter { $0.code == 49 }.map { String($0.mods) }.joined(separator: ", "))")
        }
        if let s = system.first {   // matched, not registered: the test mustn't grab a real shortcut
            check("hotkey: one of macOS's own shortcuts shows as taken", Hotkey.isSystemShortcut(keyCode: s.code, modifiers: s.mods),
                  "code \(s.code) mods \(s.mods)")
        }
    }

    /// Small guards: page data survives a NaN, same-named apps get their own row ids, and reading the CPU and
    /// memory counters doesn't pile up port references.
    private static func tidy() {
        let bad: [String: Any] = ["cpu": ["totalPct": Double.nan, "ok": 5.0], "list": [Double.infinity, 1, "a", true]]
        let json = AppDelegate.encode(bad)
        check("page data: a NaN becomes null instead of a crash", json?.contains("null") == true && json?.contains("\"ok\":5") == true, json ?? "nil")
        check("page data: normal numbers and true/false survive", json?.contains("true") == true && json?.contains("\"a\"") == true, json ?? "nil")
        let dumped = AppDelegate.encodeData(bad, options: [.prettyPrinted, .sortedKeys]).map { String(decoding: $0, as: UTF8.self) }
        check("--dump: a NaN becomes null instead of a crash", dumped?.contains("null") == true && dumped?.contains("\"ok\" : 5") == true, dumped ?? "nil")

        var taken: Set<String> = []
        let ids = ["group:safari", "group:safari", "group:safari", "group:claude-code"].map { ProcessSampler.uniqueID($0, taken: &taken) }
        check("rows: same-named apps get their own ids", ids == ["group:safari", "group:safari-2", "group:safari-3", "group:claude-code-2"], ids.joined(separator: ", "))
        // Two copies of Foo (pids 100 and 200): when the first quits, the second keeps its own row id.
        let first = ProcessSampler.groupIDs([(100, "group:foo"), (200, "group:foo")], previous: [:])
        let afterQuit = ProcessSampler.groupIDs([(200, "group:foo")], previous: first)
        let renewed = ProcessSampler.groupIDs([(200, "group:foo"), (300, "group:foo")], previous: first)
        func show(_ m: [pid_t: (base: String, id: String)]) -> String { m.keys.sorted().map { "\($0)=\(m[$0]!.id)" }.joined(separator: " ") }
        check("rows: the oldest copy gets the plain id", first[100]?.id == "group:foo" && first[200]?.id == "group:foo-2", show(first))
        check("rows: when it quits, the other copy keeps its own id", afterQuit[200]?.id == "group:foo-2", show(afterQuit))
        check("rows: a new copy never takes the id of one that just quit", renewed[200]?.id == "group:foo-2" && renewed[300]?.id == "group:foo-3", show(renewed))

        func refs() -> mach_port_urefs_t {
            var r: mach_port_urefs_t = 0
            let host = mach_host_self()
            _ = mach_port_get_refs(mach_task_self_, host, MACH_PORT_RIGHT_SEND, &r)
            mach_port_deallocate(mach_task_self_, host)
            return r
        }
        let before = refs()
        for _ in 0..<50 { _ = VMCounters.read(); _ = CPUTicks.read() }
        let after = refs()
        check("counters: reading CPU and memory 50 times keeps no port references", after <= before + 1, "\(before) -> \(after)")
        check("counters: CPU and memory still read", VMCounters.read() != nil && !CPUTicks.read().isEmpty)
    }

    /// Per-process Net in/out: rates nettop worked out over 30 s ago (the window was covered a long while) are
    /// never handed out, so the column can't show old numbers as current.
    private static func nettop() {
        let n = NetTop()
        check("nettop: no rates before any run", n.rates() == nil)
        let at = Date()
        n.seed([1: (500, 60)], at: at)
        check("nettop: fresh rates are handed out", n.rates(now: at + 29)?[1]?.0 == 500)
        check("nettop: rates over 30 s old are not", n.rates(now: at + 31) == nil)
        n.seed([1: (500, 60)], at: at - 3600)
        check("nettop: rates from an hour ago are not", n.rates() == nil)
    }

    /// The User column: every process has its owner's name, root's and other users' too (their numbers stay
    /// unknown without admin rights). Only the name of the user Vitals runs as makes a row quittable on the page.
    private static func users() {
        let table = ProcessSampler.owners()
        let own = table[getpid()], launchd = table[1]
        check("users: the kernel's table gives this process's owner and parent", own?.uid == getuid() && own?.ppid == getppid(),
              "\(String(describing: own))")
        check("users: ...and root's processes' owner too (launchd)", launchd?.uid == 0, "\(String(describing: launchd))")
        check("users: the table holds every process, and no pid that doesn't exist", table.count > 50 && table[99_999_999] == nil, "\(table.count)")
        var rows: [Row] = []
        func walk(_ list: [Row]) { for r in list { rows.append(r); walk(r.children) } }
        walk(ProcessSampler().sample().rows)
        let real = rows.filter { $0.pid != nil }
        let root = real.first { $0.pid == 1 }
        check("users: launchd's row says root", root?.user == "root", "\(root?.user ?? "nil")")
        let nameless = real.filter { $0.user == nil }
        check("users: every process row has a user", real.count > 50 && nameless.count <= 3,   // a process can exit mid-sample
              "\(nameless.count) of \(real.count) without: \(nameless.prefix(5).map { $0.name })")
        let others = real.filter { $0.user != nil && $0.user != Sampler.userName }
        check("users: other users' processes are listed with their owner", others.count > 20 && Set(others.compactMap(\.user)).count > 1,
              "\(others.count) rows, users \(Set(others.compactMap(\.user)).sorted().prefix(6))")
        let me = real.first { $0.pid == getpid() && $0.id == "pid:\(getpid())" }
        check("users: this process's row is the current user's", me?.user == Sampler.userName && !Sampler.userName.isEmpty, "\(me?.user ?? "nil")")
    }

    /// A runtime ("node", "python3") is named after the script it runs.
    private static func scripts() {
        let cases: [([String], String?)] = [
            (["node", "/Users/v/pf/node_modules/.bin/vite", "--port", "5181"], "vite"),
            (["node", "--experimental-import-meta-resolve", "--require", "/x/suppress-warnings.cjs", "--conditions", "node",
              "/x/node_modules/vitest/dist/workers/forks.js"], "vitest"),
            (["node", "/x/node_modules/@scope/tool/bin/run.js"], "tool"),
            (["python3", "-m", "http.server", "8000"], "http.server"),
            (["python3", "manage.py", "runserver"], "manage"),
            (["node", "server/index.js"], "server"),
            (["deno", "run", "-A", "./tools/build.ts"], "build"),
            (["node", "-e", "console.log(1)"], nil),
            (["python3", "-"], nil),
            (["node"], nil),
        ]
        for (args, want) in cases {
            let got = ProcessSampler.scriptName(args)
            check("script name: \(args.joined(separator: " ")) → \(want ?? "none")", got == want, "got \(got ?? "none")")
        }
        check("script name: runtimes are spotted", ["node", "python3", "python3.12", "Python", "bun"].allSatisfy(ProcessSampler.isRuntime)
              && !["nodemon", "vite", "zsh"].contains(where: ProcessSampler.isRuntime))
    }

    /// Claude Code model dots: each session's own transcript decides, never the newest one in a shared folder.
    /// Runs on made-up files in a temporary folder (never the real ~/.claude).
    private static func sessionModels() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vitals-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let t0 = Date(timeIntervalSince1970: 1_794_268_304)
        let t0Text = "Mon Nov  9 23:51:44 2026"   // t0 the way `ps -o lstart` prints it in UTC
        var starts: [pid_t: Date] = [:]
        let m = SessionModels(root: root, processStart: { starts[$0] })

        func line(_ type: String, model: String? = nil, sidechain: Bool = false, text: String = "hi") -> String {
            var msg: [String: Any] = ["role": type, "content": [["type": "text", "text": text]]]
            if let model { msg["model"] = model }
            let o: [String: Any] = ["type": type, "isSidechain": sidechain, "uuid": UUID().uuidString, "message": msg]
            return String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), as: UTF8.self) + "\n"
        }
        func transcript(_ folder: String, _ id: String) -> URL {
            root.appendingPathComponent("projects/\(SessionModels.folderName(folder))/\(id).jsonl")
        }
        func write(_ folder: String, _ id: String, _ text: String, mtime: Date? = nil) {
            let u = transcript(folder, id)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: u)
            if let mtime { try? fm.setAttributes([.modificationDate: mtime], ofItemAtPath: u.path) }
        }
        func append(_ folder: String, _ id: String, _ text: String) {
            guard let h = try? FileHandle(forWritingTo: transcript(folder, id)) else { return }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(text.utf8)); try? h.close()
        }
        func pidFile(_ pid: pid_t, id: String, cwd: String, procStart: String) {
            let u = root.appendingPathComponent("sessions/\(pid).json")
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            let o: [String: Any] = ["pid": Int(pid), "sessionId": id, "cwd": cwd, "procStart": procStart, "startedAt": 1_794_268_307_843]
            try? JSONSerialization.data(withJSONObject: o).write(to: u)
        }
        func show(_ r: [pid_t: String]) -> String { r.keys.sorted().map { "\($0)=\(r[$0]!)" }.joined(separator: " ") }

        let alpha = "/fixture/alpha app", beta = "/fixture/beta", gamma = "/fixture/gamma", delta = "/fixture/delta"
        check("sessions: a folder's transcripts are found the way Claude Code names them",
              SessionModels.folderName("/Users/x/My Code/app_1.2") == "-Users-x-My-Code-app-1-2")
        check("sessions: a start time reads in UTC, a wrong or broken one doesn't", SessionModels.sameStart(t0Text, t0 + 0.4)
              && !SessionModels.sameStart(t0Text, t0 + 3600) && !SessionModels.sameStart("yesterday", t0))

        // Two sessions share a folder. The second's transcript is the newest and ends with a subagent's line, a
        // synthetic one and a user line that quotes a model: none of those is its model.
        write(alpha, "sess-a", line("user") + line("assistant", model: "claude-sonnet-9-9"))
        write(alpha, "sess-b", line("user") + line("assistant", model: "claude-fable-9-9")
              + line("assistant", model: "claude-haiku-9-9", sidechain: true) + line("assistant", model: "<synthetic>")
              + line("user", text: #"{"type":"assistant","message":{"model":"claude-opus-9-9"}}"#))
        write(alpha, "sess-r", line("assistant", model: "claude-haiku-9-9"))
        for pid in [101, 102, 103, 104, 105, 106, 107] as [pid_t] { starts[pid] = t0 + 0.3 }
        pidFile(101, id: "sess-a", cwd: alpha, procStart: t0Text)
        pidFile(102, id: "sess-b", cwd: alpha, procStart: t0Text)
        pidFile(103, id: "sess-a", cwd: alpha, procStart: "Mon Nov  9 22:51:44 2026")   // left by an earlier process with this pid
        // 104: no session file, in the shared folder. 105: no session file, alone in its folder; the only
        // transcript there is from before it started.
        write(beta, "old", line("assistant", model: "claude-opus-9-9"), mtime: t0 - 3600)
        // 106: the model's line, then 700 KB of other lines, one line over the length limit, and a line still being written.
        let filler = String(repeating: line("user", text: String(repeating: "x", count: 900)), count: 700)
        write(gamma, "sess-long", line("assistant", model: "claude-fable-9-9") + filler
              + line("user", text: String(repeating: "y", count: SessionModels.longestLine + 1000)) + filler
              + line("assistant", model: "claude-opus-9-9").dropLast())
        pidFile(106, id: "sess-long", cwd: gamma, procStart: t0Text)
        // 107: its latest answer came from a model the pages have no color for.
        write(delta, "sess-u", line("assistant", model: "claude-sonnet-9-9") + line("assistant", model: "claude-nova-1"))
        pidFile(107, id: "sess-u", cwd: delta, procStart: t0Text)

        let all: [SessionModels.Session] = [.init(pid: 101, cwd: alpha), .init(pid: 102, cwd: alpha), .init(pid: 103, cwd: alpha),
                                             .init(pid: 104, cwd: alpha), .init(pid: 105, cwd: beta), .init(pid: 106, cwd: gamma),
                                             .init(pid: 107, cwd: delta)]
        var now = t0 + 100
        var r = m.models(for: all, now: now)
        check("sessions: two sessions in one folder each get their own model", r[101] == "Sonnet" && r[102] == "Fable", show(r))
        check("sessions: subagent, synthetic and quoted lines are ignored", r[102] == "Fable", show(r))
        check("sessions: a session file left by an earlier process with the same pid is ignored", r[103] == nil, show(r))
        check("sessions: no session file in a shared folder is unknown, not a guess", r[104] == nil, show(r))
        check("sessions: alone in a folder, a transcript from before it started is not its own", r[105] == nil, show(r))
        check("sessions: found behind 1.4 MB of later lines and one over-long line; an unfinished last line waits",
              r[106] == "Fable", show(r))
        check("sessions: a latest model the pages don't know is unknown, not the one before it", r[107] == nil, show(r))

        // The session switches model, the unfinished line gets finished, and the lone session writes its transcript.
        append(alpha, "sess-a", line("user") + line("assistant", model: "claude-opus-9-9"))
        append(gamma, "sess-long", "\n")
        write(beta, "new", line("assistant", model: "claude-haiku-9-9"), mtime: t0 + 60)
        now += 5
        r = m.models(for: all, now: now)
        check("sessions: files are not read again within 20 s", r[101] == "Sonnet" && r[106] == "Fable" && r[105] == nil, show(r))
        now += 16
        r = m.models(for: all, now: now)
        check("sessions: a switch of model mid-run shows (the latest answer wins)", r[101] == "Opus" && r[102] == "Fable", show(r))
        check("sessions: a line that got finished counts", r[106] == "Opus", show(r))
        check("sessions: alone in its folder with a transcript written since it started, that one is used", r[105] == "Haiku", show(r))

        // More lines without a model keep the answer; a resumed session's file names the resumed transcript.
        append(alpha, "sess-b", line("user") + line("assistant", model: "claude-haiku-9-9", sidechain: true))
        pidFile(101, id: "sess-r", cwd: alpha, procStart: t0Text)
        now += 21
        r = m.models(for: all, now: now)
        check("sessions: new lines without a model keep the answer", r[102] == "Fable", show(r))
        check("sessions: a resumed session reads the transcript its file names", r[101] == "Haiku", show(r))
        // The session file caught halfway through a rewrite: the answer from before stands.
        try? Data("{\"pid\": 10".utf8).write(to: root.appendingPathComponent("sessions/102.json"))
        now += 21
        r = m.models(for: all, now: now)
        check("sessions: a session file caught mid-rewrite keeps the answer", r[102] == "Fable" && r[101] == "Haiku", show(r))
        // A session that's gone is forgotten at once, and a new pid is looked up at once.
        r = m.models(for: Array(all.prefix(2)), now: now + 1)
        check("sessions: a changed set of sessions is looked up at once", r.count == 2 && r[101] == "Haiku" && r[102] == "Fable", show(r))
    }

    /// The window's 12-hour charts: a point a minute, averaged per series, gaps for minutes nobody sampled.
    private static func longHistory() {
        func arr(_ h: LongHistory, _ k: String) -> [Any] { h.json()[k] as? [Any] ?? [] }
        func val(_ a: [Any], _ i: Int) -> Double? { i < a.count ? (a[i] as? NSNumber)?.doubleValue : nil }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // on a minute boundary
        var h = LongHistory()
        h.add(["cpu": 10, "rate": NSNull()], at: t0)
        h.add(["cpu": 20, "rate": 4], at: t0 + 30)
        check("long: one minute so far is one point, its average", h.count == 1 && val(arr(h, "cpu"), 0) == 15)
        check("long: each series averages its own samples (a null rate isn't a zero)", val(arr(h, "rate"), 0) == 4)
        h.add(["cpu": 50, "rate": 8], at: t0 + 61)
        check("long: the next minute closes the last one", h.count == 2 && val(arr(h, "cpu"), 0) == 15 && val(arr(h, "cpu"), 1) == 50)
        h.add(["cpu": 70, "rate": 8], at: t0 + 3 * 3600 + 61)
        let a = arr(h, "cpu")
        check("long: 3 hours asleep are 179 empty minutes", h.count == 2 + 179 + 1 && a[2] is NSNull && a[180] is NSNull && val(a, 181) == 70,
              "\(h.count) points")
        h.add(["cpu": 1, "rate": 1], at: t0 + 30 * 3600)
        check("long: never more than 12 hours", h.count == LongHistory.length && arr(h, "cpu").count == LongHistory.length, "\(h.count)")
        let before = h.count
        h.add(["cpu": 2, "rate": 1], at: t0 + 29 * 3600)
        check("long: a clock that went back starts a new minute, no padding", h.count == min(before + 1, LongHistory.length)
              && val(arr(h, "cpu"), h.count - 1) == 2)
        check("long: empty before any sample", LongHistory().count == 0 && LongHistory().json()["cpu"] == nil)
        var w = LongHistory()
        w.add(["memStrain": 0, "cpu": 10], at: t0)
        w.add(["memStrain": 2, "cpu": 20], at: t0 + 10)
        w.add(["memStrain": 1, "cpu": 30], at: t0 + 20)
        check("long: a minute's memory strain is its worst, not its average", val(arr(w, "memStrain"), 0) == 2 && val(arr(w, "cpu"), 0) == 20)
    }

    /// The long charts across a restart: what was saved comes back, the time Vitals wasn't running is a gap, and a
    /// file that's missing, damaged, from another version or too old is ignored. On made-up data in a temporary
    /// folder: the real file (~/Library/Application Support/Vitals/history.json) is the installed app's alone.
    private static func savedHistory() {
        func arr(_ h: LongHistory, _ k: String) -> [Any] { h.json()[k] as? [Any] ?? [] }
        func val(_ a: [Any], _ i: Int) -> Double? { i >= 0 && i < a.count ? (a[i] as? NSNumber)?.doubleValue : nil }
        func same(_ a: LongHistory, _ b: LongHistory) -> Bool {
            (try? JSONSerialization.data(withJSONObject: a.json(), options: [.sortedKeys])) == (try? JSONSerialization.data(withJSONObject: b.json(), options: [.sortedKeys]))
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // on a minute boundary
        var h = LongHistory()
        h.add(["cpu": 10, "rate": NSNull(), "memStrain": 0], at: t0)
        h.add(["cpu": 30, "rate": 4, "memStrain": 2], at: t0 + 60)
        h.add(["cpu": 50, "rate": 8, "memStrain": 1], at: t0 + 5 * 60)        // 3 minutes nobody sampled
        h.add(["cpu": 70, "rate": 8, "memStrain": 1], at: t0 + 5 * 60 + 20)   // the minute in progress: average 60
        let data = h.saved() ?? Data()
        check("history: there is something to save", !data.isEmpty && LongHistory().saved() == nil)

        // Back in the same minute (a quick restart): every point as it was.
        let back = LongHistory(saved: data, now: t0 + 5 * 60 + 40)
        check("history: saved and loaded, the charts are the same", back.map { same($0, h) } == true && back?.count == 6,
              "\(back?.count ?? -1) points")
        check("history: gaps and levels survive", back.map { arr($0, "cpu")[2] is NSNull && val(arr($0, "memStrain"), 1) == 2 && val(arr($0, "rate"), 0) == nil } == true)
        // The same minute goes on: its saved average counts as one sample.
        if var again = back {
            again.add(["cpu": 0, "rate": 8, "memStrain": 0], at: t0 + 5 * 60 + 50)
            check("history: a restart inside a minute carries on in that minute", again.count == 6 && val(arr(again, "cpu"), 5) == 30
                  && val(arr(again, "memStrain"), 5) == 1, "\(arr(again, "cpu"))")
        }
        // Vitals wasn't running for 40 minutes: a gap of empty minutes, not a line from the old point to the new.
        if var later = LongHistory(saved: data, now: t0 + 45 * 60) {
            later.add(["cpu": 5, "rate": 1, "memStrain": 0], at: t0 + 45 * 60 + 2)
            let cpu = arr(later, "cpu")
            check("history: the time Vitals wasn't running is a gap", later.count == 46 && val(cpu, 5) == 60 && (6..<45).allSatisfy { cpu[$0] is NSNull }
                  && val(cpu, 45) == 5, "\(later.count) points")
        } else { check("history: the time Vitals wasn't running is a gap", false, "didn't load") }
        // 11 hours later the old points are still on the chart; 12 hours or more later they're gone.
        if var late = LongHistory(saved: data, now: t0 + 11 * 3600) {
            late.add(["cpu": 5], at: t0 + 11 * 3600)
            check("history: points under 12 hours old are kept", late.count == 661 && val(arr(late, "cpu"), 0) == 10, "\(late.count)")
        } else { check("history: points under 12 hours old are kept", false, "didn't load") }
        check("history: a file 12 hours old or more is dropped", LongHistory(saved: data, now: t0 + 5 * 60 + 12 * 3600) == nil
              && LongHistory(saved: data, now: t0 + 30 * 3600) == nil)
        check("history: a file from the future is ignored", LongHistory(saved: data, now: t0 - 3600) == nil)

        // Damaged, another version, or not this file at all.
        func edited(_ change: (inout [String: Any]) -> Void) -> Data {
            var o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            change(&o)
            return (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        }
        let now = t0 + 6 * 60
        let bad: [(String, Data)] = [
            ("cut short", data.prefix(data.count / 2)), ("empty", Data()), ("not JSON", Data("history".utf8)),
            ("another version", edited { $0["version"] = 2 }), ("no version", edited { $0["version"] = nil }),
            ("no rows", edited { $0["rows"] = [Any]() }), ("a row of the wrong width", edited { $0["rows"] = [[1.0]] }),
            ("too many rows", edited { $0["rows"] = [Any](repeating: NSNull(), count: 721) }),
            ("no keys", edited { $0["keys"] = [String]() }), ("words for numbers", edited { $0["rows"] = [["a", "b", "c"]] }),
        ]
        let loaded = bad.filter { LongHistory(saved: $0.1, now: now) != nil }.map(\.0)
        check("history: a damaged or other-version file is ignored", loaded.isEmpty && LongHistory(saved: data, now: now) != nil, "loaded: \(loaded)")

        // On disk, through the sampler, in a temporary folder.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("vitals-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Vitals/history.json")
        check("history: no file is no history", LongHistory.load(from: file) == nil)
        check("history: written in one step, folder made as needed", h.save(to: file) && (try? fm.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) == ["history.json"])
        check("history: read back from disk", LongHistory.load(from: file, now: now).map { same($0, h) } == true)
        try? Data("{\"version\":1,".utf8).write(to: file)
        let s = Sampler(historyFile: file)   // starts over a damaged file without complaint
        s.setWantProcesses(false)
        _ = s.sampleNow()
        s.saveState()
        let kept = LongHistory.load(from: file)
        check("history: the sampler replaces a damaged file with its own on quit", kept?.count == 1, "\(kept?.count ?? -1) points")
        let s2 = Sampler(historyFile: file)
        s2.setWantProcesses(false)
        s2.setWindowOpen(true)
        let long = s2.sampleNow()["long"] as? [String: Any] ?? [:]
        check("history: the next launch starts from the saved charts", ((long["memUsedPct"] as? [Any])?.count ?? 0) >= 1 && (long["memUsedPct"] as? [Any])?.last is NSNumber)

        // Only the installed app, started the normal way, uses the real file.
        typealias A = AppDelegate
        check("history: the installed app keeps its charts in Application Support",
              A.historyFile(bundlePath: "/Applications/Vitals.app", args: ["Vitals"])?.path.hasSuffix("/Library/Application Support/Vitals/history.json") == true)
        check("history: a test build, or any run with an option, never touches that file",
              A.historyFile(bundlePath: "/Users/x/Library/Caches/VitalsBuild/Vitals.app", args: ["Vitals"]) == nil
              && A.historyFile(bundlePath: "/Applications/Vitals.app", args: ["Vitals", "--status-log"]) == nil
              && Sampler().historyFile == nil)
    }

    /// Time away becomes empty chart slots, one per 2 s, never more than the 5-minute chart.
    private static func gaps() {
        let cases: [(Double, Int)] = [(2, 0), (10, 0), (11, 6), (60, 30), (299, 150), (8 * 3600, 150), (1e300, 150), (.nan, 0), (-50, 0)]
        let bad = cases.filter { Sampler.gapSlots($0.0) != $0.1 }.map { "\($0.0) s → \(Sampler.gapSlots($0.0)), want \($0.1)" }
        check("charts: time away becomes one empty slot per 2 s, at most 150", bad.isEmpty, bad.joined(separator: "; "))
    }

    /// Opening a page asks for a sample at once, but not within half a second of one taken for a page (an unlock
    /// with the window open asks twice): rates over a few ms would spike the charts.
    private static func kicks() {
        let lock = NSLock()
        var n = 0
        var delivered: [String: Any] = [:]
        let s = Sampler()   // process rows on, as while a page shows
        s.onSnapshot = { snap in lock.lock(); n += 1; delivered = snap; lock.unlock() }
        func count() -> Int { lock.lock(); defer { lock.unlock() }; return n }
        func lastDelivered() -> [String: Any] { lock.lock(); defer { lock.unlock() }; return delivered }
        _ = s.sampleNow()
        s.kick()
        Thread.sleep(forTimeInterval: 0.3)
        check("kick: skipped right after a sample", count() == 0, "\(count()) extra samples")
        // A busy Mac can take a few hundred ms over one sample: wait for it (up to 3 s), then make sure it was just one.
        func settle(_ want: Int) {
            let until = Date() + 3
            while count() < want, Date() < until { Thread.sleep(forTimeInterval: 0.05) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.4)
        s.kick()
        settle(1)
        check("kick: samples when the last one is over 0.5 s old", count() == 1, "\(count()) samples")
        // The unlock order: the end of the rest samples before the window is back (no page, stale rows), then the
        // window asks a moment later. It gets fresh rows, but CPU, disk and network aren't measured over those few ms.
        s.setWantProcesses(false)
        _ = s.sampleNow()
        Thread.sleep(forTimeInterval: 0.6)
        let restEnd = s.sampleNow()
        s.setWantProcesses(true)
        s.kick()
        settle(2)
        let got = lastDelivered()
        func read(_ snap: [String: Any]) -> NSNumber? { (snap["disk"] as? [String: Any])?["readBps"] as? NSNumber }
        func points(_ snap: [String: Any]) -> Int? { ((snap["live"] as? [String: Any])?["memUsedPct"] as? [Any])?.count }
        func impact(_ snap: [String: Any]) -> Any? { (snap["energy"] as? [String: Any])?["impact"] }
        check("kick: right after a sample without a page, the page still gets a snapshot", count() == 2, "\(count()) samples")
        check("kick: ...with fresh process rows", impact(restEnd) is NSNull && impact(got) is NSNumber,
              "impact \(String(describing: impact(restEnd))) -> \(String(describing: impact(got)))")
        let e = got["energy"] as? [String: Any] ?? [:], w = (e["watts"] as? NSNumber)?.doubleValue
        check("kick: ...and the whole Mac's watts, where there's a battery", !(e["batteryPct"] is NSNumber) || (w.map { $0 > 0.3 && $0 < 400 } ?? false),
              "watts \(String(describing: e["watts"]))")
        let bw = (e["batteryW"] as? NSNumber)?.doubleValue
        check("kick: ...and the watts going into the battery, only while plugged in", e["pluggedIn"] as? Bool == true
              ? (bw.map { $0 >= 0 && $0 < 400 } ?? (Power.telemetry().load == nil)) : e["batteryW"] is NSNull,
              "pluggedIn \(String(describing: e["pluggedIn"])), batteryW \(String(describing: e["batteryW"]))")
        check("kick: ...but no rates over a few ms", got["time"] as? String == restEnd["time"] as? String && read(got) != nil
              && read(got) == read(restEnd) && points(got) == points(restEnd),
              "readBps \(String(describing: read(restEnd))) -> \(String(describing: read(got))), points \(points(restEnd) ?? -1) -> \(points(got) ?? -1)")
    }

    /// The real sampler: ticks every 2 s, goes quiet while resting, takes a fresh sample on waking, and leaves a
    /// gap (nulls, no disk / network rates) across a stretch over 10 s. No folder scan in the snapshot.
    private static func sampler() {
        let lock = NSLock()
        var got: [(Date, [String: Any])] = []
        let s = Sampler()
        s.setWantProcesses(false)
        s.onSnapshot = { snap in lock.lock(); got.append((Date(), snap)); lock.unlock() }
        func count() -> Int { lock.lock(); defer { lock.unlock() }; return got.count }
        func last() -> [String: Any] { lock.lock(); defer { lock.unlock() }; return got.last?.1 ?? [:] }

        s.start()
        Thread.sleep(forTimeInterval: 6.5)   // every 2 s, up to 1 s late with no page showing
        let awake = count()
        check("sampler: samples every 2 s", awake >= 3, "\(awake) samples in 6.5 s")
        let snap0 = last()
        check("sampler: no folder scan in the snapshot", (snap0["disk"] as? [String: Any])?["bigUsers"] == nil)
        check("sampler: the snapshot names the user Vitals runs as (the only one whose processes can be quit)",
              (snap0["host"] as? [String: Any])?["user"] as? String == NSUserName())
        let history = ["memory", "cpu", "gpu"].filter { (snap0[$0] as? [String: Any])?["history"] != nil }
        check("sampler: no unused 1-hour history in the snapshot", history.isEmpty, history.joined(separator: ", "))
        let energy = snap0["energy"] as? [String: Any] ?? [:]
        check("sampler: battery and fan read once even with no page", energy["thermal"] is String && energy.keys.contains("fanRPM"))
        let firstRow = (snap0["processes"] as? [[String: Any]])?.first ?? [:]
        check("sampler: nothing in the snapshot that no page reads", energy["chargerW"] == nil && firstRow["idleWakeupsPs"] == nil
              && !firstRow.isEmpty, "chargerW \(String(describing: energy["chargerW"])), row keys \(firstRow.keys.sorted())")
        let block = snap0["strain"] as? [String: Any] ?? [:]
        let words = block.values.compactMap { $0 as? String }
        let live0 = snap0["live"] as? [String: Any] ?? [:]
        let levels = live0["memStrain"] as? [Any] ?? [], usedPts = live0["memUsedPct"] as? [Any] ?? []
        check("sampler: the snapshot carries the verdict the icon and the pages both draw", block.count == 6 && words.count == 6
              && words.allSatisfy { ["ok", "warn", "crit"].contains($0) }, "\(block)")
        check("sampler: ...and a memory level for every chart point, the last one the current verdict", !levels.isEmpty
              && levels.count == usedPts.count
              && (levels.last as? NSNumber)?.intValue == StatusIcon.State(snapshot: snap0).level(.memory).rawValue
              && StatusIcon.State(snapshot: snap0).level(.memory).word == block["memory"] as? String,
              "\(levels.count) levels, \(usedPts.count) points, last \(String(describing: levels.last)), block \(block)")
        let watts = ((snap0["live"] as? [String: Any])?["powerW"] as? [Any])?.filter { $0 is NSNumber }.count ?? 0
        check("sampler: watts every tick even with no page, where there's a battery", Power.watts() == nil || watts >= 3,
              "\(watts) points")

        s.setResting(true)
        Thread.sleep(forTimeInterval: 0.3)
        let before = count()
        Thread.sleep(forTimeInterval: 11)
        check("sampler: resting takes no samples for 11 s", count() == before, "\(count() - before) samples while resting")

        let woke = Date()
        s.setResting(false)
        Thread.sleep(forTimeInterval: 1)
        let fresh: (Date, [String: Any])? = { lock.lock(); defer { lock.unlock() }; return got.last }()
        let first = count() > before && fresh.map { $0.0 >= woke } == true
        check("sampler: waking takes a sample at once", first, "\(count() - before) samples within 1 s of waking")
        let snap = fresh?.1 ?? [:]
        let live = snap["live"] as? [String: Any] ?? [:]
        let lastPoints = live.filter { $0.key != "stepSec" }.compactMap { ($0.value as? [Any])?.last }
        check("sampler: the stretch shows as a gap in the charts",
              !lastPoints.isEmpty && lastPoints.allSatisfy { $0 is NSNull }, "\(lastPoints.count) series")
        check("sampler: no disk rate across the stretch", (snap["disk"] as? [String: Any])?["readBps"] is NSNull)
        // ~12–15 s away = 6–7 empty 2 s slots, so the points from before slide back to where they really were.
        let mem = live["memUsedPct"] as? [Any] ?? []
        let empty = mem.reversed().prefix { $0 is NSNull }.count
        check("sampler: the stretch is padded to its real length", (5...8).contains(empty) && mem.dropLast(empty).last is NSNumber,
              "\(empty) empty slots at the end of \(mem.count)")
        check("sampler: the needles still have values", ((snap["cpu"] as? [String: Any])?["totalPct"] as? NSNumber) != nil)

        Thread.sleep(forTimeInterval: 2.5)
        let next = last()
        let rate = (next["disk"] as? [String: Any])?["readBps"]
        check("sampler: rates come back on the next tick", rate is NSNumber, "readBps \(String(describing: rate))")
        let memNext = ((next["live"] as? [String: Any])?["memUsedPct"] as? [Any])?.last
        check("sampler: chart points come back on the next tick", memNext is NSNumber, "memUsedPct \(String(describing: memNext))")
    }
}
