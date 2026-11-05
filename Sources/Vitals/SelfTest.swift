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
        baseline()
        judge()
        deadband()
        menus()
        tidy()
        gaps()
        nettop()
        scripts()
        longHistory()
        kicks()
        sampler()
        print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
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

    /// The dials redraw only when a needle moves 2% or more, or a color changes.
    private static func deadband() {
        let a = StatusIcon.State(cpu: 40, gpu: 10, ram: 70)
        check("dials: a 1% move doesn't redraw", a.looksLike(StatusIcon.State(cpu: 41, gpu: 9, ram: 71)))
        check("dials: a 2% move redraws", !a.looksLike(StatusIcon.State(cpu: 42, gpu: 10, ram: 70)))
        check("dials: a color change redraws", !a.looksLike(StatusIcon.State(cpu: 40, gpu: 10, ram: 70, levels: [.memory: .warn])))
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
        Thread.sleep(forTimeInterval: 0.4)
        s.kick()
        Thread.sleep(forTimeInterval: 0.6)
        check("kick: samples when the last one is over 0.5 s old", count() == 1, "\(count()) samples")
        // The unlock order: the end of the rest samples before the window is back (no page, stale rows), then the
        // window asks a moment later. It gets fresh rows, but CPU, disk and network aren't measured over those few ms.
        s.setWantProcesses(false)
        _ = s.sampleNow()
        Thread.sleep(forTimeInterval: 0.6)
        let restEnd = s.sampleNow()
        s.setWantProcesses(true)
        s.kick()
        Thread.sleep(forTimeInterval: 0.6)
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
        let cw = (e["chargerW"] as? NSNumber)?.doubleValue
        check("kick: ...and the charger's watts only while plugged in", e["pluggedIn"] as? Bool == true
              ? (cw.map { $0 > 0.3 && $0 < 400 } ?? (Power.telemetry().fromCharger == nil)) : e["chargerW"] is NSNull,
              "pluggedIn \(String(describing: e["pluggedIn"])), chargerW \(String(describing: e["chargerW"]))")
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
        let history = ["memory", "cpu", "gpu"].filter { (snap0[$0] as? [String: Any])?["history"] != nil }
        check("sampler: no unused 1-hour history in the snapshot", history.isEmpty, history.joined(separator: ", "))
        let energy = snap0["energy"] as? [String: Any] ?? [:]
        check("sampler: battery and fan read once even with no page", energy["thermal"] is String && energy.keys.contains("fanRPM"))
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
