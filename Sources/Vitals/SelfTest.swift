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

        let d = DailyBaseline(store: store)
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
        let again = DailyBaseline(store: store).today(["diskR": 1000], day: "2026-10-21", boot: 9000)["diskR"]
        check("baseline: relaunch the same day keeps the baseline", again == 300, "got \(again.map(String.init) ?? "nil"), want 300")
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
    }

    /// Small guards: page data survives a NaN, same-named apps get their own row ids, and reading the CPU and
    /// memory counters doesn't pile up port references.
    private static func tidy() {
        let bad: [String: Any] = ["cpu": ["totalPct": Double.nan, "ok": 5.0], "list": [Double.infinity, 1, "a", true]]
        let json = AppDelegate.encode(bad)
        check("page data: a NaN becomes null instead of a crash", json?.contains("null") == true && json?.contains("\"ok\":5") == true, json ?? "nil")
        check("page data: normal numbers and true/false survive", json?.contains("true") == true && json?.contains("\"a\"") == true, json ?? "nil")

        var taken: Set<String> = []
        let ids = ["group:safari", "group:safari", "group:safari", "group:claude-code"].map { ProcessSampler.uniqueID($0, taken: &taken) }
        check("rows: same-named apps get their own ids", ids == ["group:safari", "group:safari-2", "group:safari-3", "group:claude-code-2"], ids.joined(separator: ", "))

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
        check("sampler: the needles still have values", ((snap["cpu"] as? [String: Any])?["totalPct"] as? NSNumber) != nil)

        Thread.sleep(forTimeInterval: 2.5)
        let next = last()
        let rate = (next["disk"] as? [String: Any])?["readBps"]
        check("sampler: rates come back on the next tick", rate is NSNumber, "readBps \(String(describing: rate))")
        let mem = ((next["live"] as? [String: Any])?["memUsedPct"] as? [Any])?.last
        check("sampler: chart points come back on the next tick", mem is NSNumber, "memUsedPct \(String(describing: mem))")
    }
}
