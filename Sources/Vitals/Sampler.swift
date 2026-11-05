import Darwin
import Foundation

/// Builds the DATA.md snapshot every 2 seconds on a background queue.
final class Sampler: @unchecked Sendable {
    let host = HostInfo.read()
    let processes = ProcessSampler()
    private let daily = DailyBaseline()
    private let queue = DispatchQueue(label: "vitals.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?   // queue only
    private var resting = false     // queue only

    // Previous counters, for rates.
    private var prevTicks: [[UInt64]] = []
    private var prevDisk: (read: UInt64, written: UInt64)?
    private var prevNet: Network.Counters?
    private var prevNetIface: String?
    private var prevAt: Date?

    // The strip charts: every sample, the last 5 minutes (DATA.md `live`).
    private static let liveLength = 150
    private var live: [String: [Any]] = [:]
    // The window's long charts: one point a minute, 12 hours (LongHistory). Filled every tick; sent only while the
    // window shows, since the popover doesn't draw it.
    private var longHist = LongHistory()
    private var wantLong = false   // queue only

    private var iface: (bsd: String, name: String)?
    private var ifaceCheckedAt = Date.distantPast
    // Free space asks CacheDelete for purgeable space, which is slow-ish: once a minute is plenty.
    private var vol: (name: String?, total: UInt64?, free: UInt64?) = (nil, nil, nil)
    private var volCheckedAt = Date.distantPast
    // Battery and fan only show in the window and popover: read while a page shows, else keep the last reading.
    private var power: Power.Reading?
    private var fanRPM: Any = NSNull()

    /// Latest snapshot, set on the sampler queue.
    private var latest: [String: Any]? {
        get { latestLock.lock(); defer { latestLock.unlock() }; return _latest }
        set { latestLock.lock(); _latest = newValue; latestLock.unlock() }
    }
    private var _latest: [String: Any]?
    private let latestLock = NSLock()
    var onSnapshot: (([String: Any]) -> Void)?

    /// A page is showing. Process rows (and battery / fan) are only sampled then; with just the menu bar, only
    /// what the dials and the charts' history need.
    private var wantProcesses = true
    private var lastProcs: ProcessSampler.Result?
    private var lastForPage = false   // queue only: the last sample was taken while a page showed (fresh rows)

    func latestSnapshot() -> [String: Any]? { latest }

    func start() {
        // On the queue, so the timer and the settings it's scheduled from are only ever touched there.
        queue.async { [weak self] in
            guard let self else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.setEventHandler { [weak self] in self?.sampleIfDue() }
            self.timer = t
            self.reschedule(now: true)
            t.resume()
        }
    }

    func setWantNetwork(_ on: Bool) { queue.async { self.processes.wantNetwork = on } }
    func setWindowOpen(_ on: Bool) { setWantNetwork(on); queue.async { self.wantLong = on } }
    func setWantProcesses(_ on: Bool) {
        queue.async {
            guard on != self.wantProcesses else { return }
            self.wantProcesses = on
            self.reschedule(now: false)
        }
    }
    /// One extra sample right away, delivered like a timer tick (unless one just ran, see `sampleIfDue`).
    func kick() {
        queue.async { self.sampleIfDue() }
    }

    /// A sample, delivered. Not a full one under half a second after the last (an unlock with the window open asks
    /// twice, the end of the rest and the window coming back, in either order): that would measure CPU, disk and
    /// network over a few ms, a spike that flattens a chart's scale for 5 minutes. Then the last snapshot stands, and
    /// if it was taken without a page (stale process rows) and a page now wants them, it gets fresh rows only.
    private func sampleIfDue() {
        let ago = prevAt.map { Date().timeIntervalSince($0) }
        if let ago, ago >= 0, ago < 0.5 {
            guard wantProcesses && !lastForPage, let snap = latest else { return }
            let s = withFreshRows(snap)
            latest = s
            onSnapshot?(s)
            return
        }
        let s = sample()
        latest = s
        onSnapshot?(s)
    }

    /// `snap` with process rows (and energy impact) sampled now. Their rates run from the last time rows were
    /// sampled, not over the last few ms.
    private func withFreshRows(_ snap: [String: Any]) -> [String: Any] {
        let procs = processes.sample()
        lastProcs = procs
        lastForPage = true
        var out = snap
        out["processes"] = procs.rows.map { $0.json() }
        out["totals"] = ["processes": procs.processes, "threads": procs.threads]
        // The battery and fan too: the snapshot's were read when a page last showed, maybe hours ago.
        out["energy"] = energySection(fresh: true, impact: num(procs.rows.reduce(0) { $0 + ($1.energy ?? 0) }, 1))
        if wantLong { out["long"] = longHist.json() }
        return out
    }

    /// The energy block. The battery's details and the fan are read when `fresh` (a page shows, or the first sample);
    /// the watts (the Mac's and the charger's) every time (one property), so the Energy chart is full when a page opens, like the others.
    private func energySection(fresh: Bool, impact: Any) -> [String: Any] {
        if fresh || power == nil {
            power = Power.read()
            if let rpm = Fan.rpm(), rpm.isFinite, rpm < 100_000 { fanRPM = Int(rpm.rounded()) } else { fanRPM = NSNull() }
        }
        let p = power ?? Power.Reading(), tele = Power.telemetry()
        return [
            "batteryPct": p.batteryPct ?? NSNull(), "pluggedIn": p.pluggedIn ?? NSNull(),
            "charging": p.charging ?? NSNull(), "fullyCharged": p.fullyCharged ?? NSNull(),
            "adapterWatts": p.adapterWatts ?? NSNull(), "cycles": p.cycles ?? NSNull(),
            "healthPct": p.healthPct ?? NSNull(), "minutesLeft": p.minutesLeft ?? NSNull(),
            "thermal": Power.thermal(), "fanRPM": fanRPM,
            "impact": impact, "watts": num(tele.load, 1),
            "chargerW": p.pluggedIn == true ? num(tele.fromCharger, 1) : NSNull(),
        ]
    }
    func saveState() { queue.sync { daily.save() } }

    /// Screens asleep, screen locked or another user's session: nobody can see the menu bar, so sample once a
    /// minute (enough for the midnight baseline and the strain levels) instead of every 2 s. Waking takes a
    /// fresh sample at once and goes back to every 2 s.
    func setResting(_ on: Bool) {
        queue.async {
            guard on != self.resting else { return }
            self.resting = on
            self.reschedule(now: !on)
        }
    }

    /// Every 2 s, or once a minute while resting. The slack lets macOS fold the wakeup in with others: a
    /// second with only the menu bar showing, 0.2 s while a page shows (its charts step every 2 s).
    private func reschedule(now: Bool) {
        guard let t = timer else { return }
        let every: Double = resting ? 60 : 2
        let leeway: DispatchTimeInterval = resting ? .seconds(5) : wantProcesses ? .milliseconds(200) : .seconds(1)
        t.schedule(deadline: .now() + (now ? 0 : every), repeating: every, leeway: leeway)
    }

    /// Takes one sample synchronously (used by --dump; call twice for real rates).
    func sampleNow() -> [String: Any] { queue.sync { let s = sample(); latest = s; return s } }

    // MARK: -

    private func sample() -> [String: Any] {
        let now = Date()
        let dt = prevAt.map { now.timeIntervalSince($0) } ?? 0
        prevAt = now
        // More than 10 s since the last sample (the Mac slept, or Vitals was resting at one sample a minute):
        // no disk / network rates across it, and a gap in the 5-minute charts rather than a fake dip.
        let gap = dt > 10

        let memory = memorySection()
        let cpu = cpuSection()
        let gpu = GPU.stats(), gpuPct = gpu.pct
        let procs: ProcessSampler.Result
        let freshProcs = wantProcesses || lastProcs == nil
        lastForPage = wantProcesses
        if freshProcs { procs = processes.sample(); lastProcs = procs } else { procs = lastProcs! }
        // Energy impact needs the process rows, which are only sampled while a page shows; null otherwise
        // (and on the first sample, which has no rates yet).
        let impact: Any = freshProcs && dt > 0 ? num(procs.rows.reduce(0) { $0 + ($1.energy ?? 0) }, 1) : NSNull()

        // Disk
        if Date().timeIntervalSince(volCheckedAt) >= 60 {
            vol = Disk.volume()
            volCheckedAt = Date()
            // Foundation caches the system time zone; once a minute, look again (travel, or a change in Settings),
            // so "today" rolls over at the right midnight.
            NSTimeZone.resetSystemTimeZone()
        }
        let diskNow = Disk.counters()
        var readBps: Any = NSNull(), writeBps: Any = NSNull()
        if let d = diskNow, let p = prevDisk, dt > 0, !gap {
            readBps = num(Double(d.read &- p.read) / dt, 0)
            writeBps = num(Double(d.written &- p.written) / dt, 0)
        }
        prevDisk = diskNow

        // Network (primary interface, re-checked every 10 s)
        if now.timeIntervalSince(ifaceCheckedAt) > 10 {
            ifaceCheckedAt = now
            if let bsd = Network.primaryInterface() {
                // The display name ("Wi-Fi") asks SystemConfiguration for every interface: only when it changes.
                if bsd != iface?.bsd { iface = (bsd, Network.displayName(bsd: bsd) ?? bsd) }
            } else { iface = nil }
        }
        let netNow = iface.flatMap { Network.counters(bsd: $0.bsd) }
        var net: [String: Any] = ["iface": iface?.name ?? NSNull(), "inBps": NSNull(), "outBps": NSNull(),
                                  "packetsInPs": NSNull(), "packetsOutPs": NSNull()]
        if let n = netNow, let p = prevNet, prevNetIface == iface?.bsd, dt > 0, !gap {
            net["inBps"] = num(Double(n.inBytes &- p.inBytes) / dt, 0)
            net["outBps"] = num(Double(n.outBytes &- p.outBytes) / dt, 0)
            net["packetsInPs"] = num(Double(n.inPackets &- p.inPackets) / dt, 0)
            net["packetsOutPs"] = num(Double(n.outPackets &- p.outPackets) / dt, 0)
        }
        prevNet = netNow
        prevNetIface = iface?.bsd

        var counters: [String: UInt64] = [:]
        if let d = diskNow { counters["diskR"] = d.read; counters["diskW"] = d.written }
        if let n = netNow, let bsd = iface?.bsd { counters["netI." + bsd] = n.inBytes; counters["netO." + bsd] = n.outBytes }
        let today = daily.today(counters)
        net["inTodayBytes"] = iface.flatMap { today["netI." + $0.bsd] } ?? NSNull()
        net["outTodayBytes"] = iface.flatMap { today["netO." + $0.bsd] } ?? NSNull()

        let used: Any = (vol.total != nil && vol.free != nil) ? vol.total! - min(vol.total!, vol.free!) : NSNull()
        let disk: [String: Any] = [
            "volume": vol.name ?? NSNull(), "totalBytes": vol.total ?? NSNull(), "usedBytes": used,
            "freeBytes": vol.free ?? NSNull(), "readBps": readBps, "writeBps": writeBps,
            "readTodayBytes": today["diskR"] ?? NSNull(), "writtenTodayBytes": today["diskW"] ?? NSNull(),
        ]

        let energy = energySection(fresh: wantProcesses, impact: impact)

        // Memory Used (app + wired + compressed, as Activity Monitor) as a % of RAM, one decimal.
        let memUsedPct: Any = {
            guard let used = (memory["usedBytes"] as? NSNumber)?.doubleValue,
                  let total = (memory["totalBytes"] as? NSNumber)?.doubleValue, total > 0 else { return NSNull() }
            return (used / total * 1000).rounded() / 10
        }()
        let point: [String: Any] = [
            "pressurePct": memory["pressurePct"] ?? NSNull(), "memUsedPct": memUsedPct,
            "swapUsedBytes": memory["swapUsedBytes"] ?? NSNull(),
            "cpuUserPct": cpu["userPct"] ?? NSNull(), "cpuSystemPct": cpu["systemPct"] ?? NSNull(),
            "gpuPct": num(gpuPct, 0), "diskReadBps": readBps, "diskWriteBps": writeBps,
            "netInBps": net["inBps"] ?? NSNull(), "netOutBps": net["outBps"] ?? NSNull(), "energyImpact": impact,
            "powerW": energy["watts"] ?? NSNull(),
        ]
        if gap {
            // The charts place points by index, one slot per 2 s: fill the time away with empty slots so what came
            // before slides back to where it really was (or off the 5 minutes), instead of sitting next to "now".
            let empty = point.mapValues { _ -> Any in NSNull() }
            for _ in 0..<Self.gapSlots(dt) { addLive(empty) }
        } else {
            addLive(point)
        }
        var liveOut: [String: Any] = live
        liveOut["stepSec"] = 2
        longHist.add(point, at: now)

        let uptime = Sysctl.bootTime().map { Int(now.timeIntervalSince($0)) }
        let hostOut: [String: Any] = [
            "model": host.model ?? NSNull(), "chip": host.chip ?? NSNull(), "pCores": host.pCores ?? NSNull(),
            "eCores": host.eCores ?? NSNull(), "gpuCores": host.gpuCores ?? NSNull(), "memBytes": host.memBytes,
            "os": host.os, "uptimeSec": uptime ?? NSNull(),
        ]

        var out: [String: Any] = [
            "time": Self.timeString(now),
            "host": hostOut,
            "memory": memory,
            "cpu": cpu,
            "gpu": ["pct": num(gpuPct, 0), "rendererPct": num(gpu.rendererPct, 0), "tilerPct": num(gpu.tilerPct, 0),
                    "memBytes": gpu.memBytes.map { $0 as Any } ?? NSNull()],
            "energy": energy,
            "disk": disk,
            "network": net,
            "live": liveOut,
            "totals": ["processes": procs.processes, "threads": procs.threads],
            "processes": procs.rows.map { $0.json() },
        ]
        if wantLong { out["long"] = longHist.json() }
        return out
    }

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The snapshot time with the current time zone's offset (followed if the Mac changes zones).
    static func timeString(_ date: Date, zone: TimeZone = .current) -> String {
        if timeFormatter.timeZone?.identifier != zone.identifier { timeFormatter.timeZone = zone }
        return timeFormatter.string(from: date)
    }

    // MARK: memory

    private func memorySection() -> [String: Any] {
        let total = host.memBytes
        var out: [String: Any] = ["totalBytes": total]
        let page = Mach.pageSize
        if let vm = VMCounters.read() {
            // Activity Monitor's split: App = anonymous memory not marked purgeable, Cached = file-backed + purgeable.
            let app = (vm.internalPages &- min(vm.internalPages, vm.purgeablePages)) * page
            let wired = vm.wiredPages * page
            let compressed = vm.compressorPages * page
            let cached = (vm.externalPages + vm.purgeablePages) * page
            let used = app + wired + compressed
            out["appBytes"] = app
            out["wiredBytes"] = wired
            out["compressedBytes"] = compressed
            out["cachedBytes"] = cached
            out["usedBytes"] = used
            out["freeBytes"] = total > used + cached ? total - used - cached : 0
            out["swapOutBytesSinceBoot"] = vm.swapouts * page
        } else {
            for k in ["appBytes", "wiredBytes", "compressedBytes", "cachedBytes", "usedBytes", "freeBytes", "swapOutBytesSinceBoot"] {
                out[k] = NSNull()
            }
        }
        if let level = Sysctl.number("kern.memorystatus_level") {
            out["pressurePct"] = Double(100 - level)
        } else { out["pressurePct"] = NSNull() }
        switch Sysctl.number("kern.memorystatus_vm_pressure_level") {
        case 4?: out["level"] = "critical"
        case 2?: out["level"] = "warn"
        case 1?: out["level"] = "normal"
        default: out["level"] = NSNull()
        }
        if let s = Sysctl.swap() {
            out["swapUsedBytes"] = s.used
            out["swapTotalBytes"] = s.total
        } else { out["swapUsedBytes"] = NSNull(); out["swapTotalBytes"] = NSNull() }
        return out
    }

    // MARK: cpu

    private func cpuSection() -> [String: Any] {
        let ticks = CPUTicks.read()
        defer { prevTicks = ticks }
        var load = [Double](repeating: 0, count: 3)
        let loadOK = getloadavg(&load, 3) == 3
        var out: [String: Any] = ["load": loadOK ? load.map { num($0, 2) } : NSNull()]
        guard ticks.count == prevTicks.count, !ticks.isEmpty else {
            for k in ["totalPct", "userPct", "systemPct", "idlePct"] { out[k] = NSNull() }
            out["cores"] = host.coreKinds.sorted { $0 == "P" && $1 == "E" }.map { ["kind": $0, "pct": NSNull()] }
            return out
        }
        var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0
        var cores: [(kind: String, pct: Double)] = []
        for (i, t) in ticks.enumerated() {
            let p = prevTicks[i]
            let u = (t[Int(CPU_STATE_USER)] &- p[Int(CPU_STATE_USER)]) + (t[Int(CPU_STATE_NICE)] &- p[Int(CPU_STATE_NICE)])
            let s = t[Int(CPU_STATE_SYSTEM)] &- p[Int(CPU_STATE_SYSTEM)]
            let id = t[Int(CPU_STATE_IDLE)] &- p[Int(CPU_STATE_IDLE)]
            user += u; sys += s; idle += id
            let all = u + s + id
            let kind = i < host.coreKinds.count ? host.coreKinds[i] : "E"
            cores.append((kind, all > 0 ? Double(u + s) / Double(all) * 100 : 0))
        }
        let all = Double(user + sys + idle)
        if all > 0 {
            out["userPct"] = num(Double(user) / all * 100, 1)
            out["systemPct"] = num(Double(sys) / all * 100, 1)
            out["idlePct"] = num(Double(idle) / all * 100, 1)
            out["totalPct"] = (Double(user + sys) / all * 1000).rounded() / 10
        } else {
            for k in ["totalPct", "userPct", "systemPct", "idlePct"] { out[k] = NSNull() }
        }
        // Performance cores first, each group in logical-cpu order.
        let ordered = cores.filter { $0.kind == "P" } + cores.filter { $0.kind != "P" }
        out["cores"] = ordered.map { ["kind": $0.kind, "pct": num($0.pct, 0)] as [String: Any] }
        return out
    }

    // MARK: live

    /// How many empty 2 s chart slots stand for `dt` seconds away (the last one is this sample's own, empty point):
    /// none for a normal tick, at most a full chart.
    static func gapSlots(_ dt: Double) -> Int {
        guard dt > 10 else { return 0 }
        return Int(min(Double(liveLength), (dt / 2).rounded()))   // dt can be huge after a clock change: clamp before Int
    }

    private func addLive(_ point: [String: Any]) {
        for (k, v) in point {
            var a = live[k] ?? []
            a.append(v)
            if a.count > Self.liveLength { a.removeFirst(a.count - Self.liveLength) }
            live[k] = a
        }
    }

}
