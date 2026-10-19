import Darwin
import Foundation

/// Builds the DATA.md snapshot every 2 seconds on a background queue.
final class Sampler: @unchecked Sendable {
    let host = HostInfo.read()
    let processes = ProcessSampler()
    let diskScan = DiskScan()
    private let daily = DailyBaseline()
    private let queue = DispatchQueue(label: "vitals.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?

    // Previous counters, for rates.
    private var prevTicks: [[UInt64]] = []
    private var prevDisk: (read: UInt64, written: UInt64)?
    private var prevNet: Network.Counters?
    private var prevNetIface: String?
    private var prevAt: Date?

    // One history point every 30 s, the last hour.
    private static let historyEvery: TimeInterval = 30
    private static let historyLength = 120
    private var history: [String: [Double]] = [:]
    private var bucket: [String: [Double]] = [:]
    private var bucketStart = Date()

    // The strip charts: every sample, the last 5 minutes (DATA.md `live`).
    private static let liveLength = 150
    private var live: [String: [Any]] = [:]

    private var iface: (bsd: String, name: String)?
    private var ifaceCheckedAt = Date.distantPast

    /// Latest snapshot, set on the sampler queue.
    private var latest: [String: Any]? {
        get { latestLock.lock(); defer { latestLock.unlock() }; return _latest }
        set { latestLock.lock(); _latest = newValue; latestLock.unlock() }
    }
    private var _latest: [String: Any]?
    private let latestLock = NSLock()
    var onSnapshot: (([String: Any]) -> Void)?

    /// Process rows are the costly part; while no page shows them only the memory, CPU etc. are sampled.
    private var wantProcesses = true
    private var lastProcs: ProcessSampler.Result?

    func latestSnapshot() -> [String: Any]? { latest }

    func start() {
        diskScan.start()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.sample()
            self.latest = snap
            self.onSnapshot?(snap)
        }
        t.resume()
        timer = t
    }

    func setWantNetwork(_ on: Bool) { queue.async { self.processes.wantNetwork = on } }
    func setWindowOpen(_ on: Bool) {
        setWantNetwork(on)
        diskScan.setRepeating(on)
    }
    func setWantProcesses(_ on: Bool) { queue.async { self.wantProcesses = on } }
    /// One extra sample right away, delivered like a timer tick.
    func kick() {
        queue.async { let s = self.sample(); self.latest = s; self.onSnapshot?(s) }
    }
    func saveState() { queue.sync { daily.save() } }

    /// Takes one sample synchronously (used by --dump; call twice for real rates).
    func sampleNow() -> [String: Any] { queue.sync { let s = sample(); latest = s; return s } }

    // MARK: -

    private func sample() -> [String: Any] {
        let now = Date()
        let dt = prevAt.map { now.timeIntervalSince($0) } ?? 0
        prevAt = now

        let memory = memorySection()
        let cpu = cpuSection()
        let gpuPct = GPU.utilization()
        let procs: ProcessSampler.Result
        let freshProcs = wantProcesses || lastProcs == nil
        if freshProcs { procs = processes.sample(); lastProcs = procs } else { procs = lastProcs! }
        // Energy impact needs the process rows, which are only sampled while a page shows; null otherwise
        // (and on the first sample, which has no rates yet).
        let impact: Any = freshProcs && dt > 0 ? num(procs.rows.reduce(0) { $0 + ($1.energy ?? 0) }, 1) : NSNull()

        record("pressurePct", memory["pressurePct"] as? Double)
        record("swapUsedBytes", (memory["swapUsedBytes"] as? UInt64).map(Double.init), average: false)
        record("cpu", cpu["totalPct"] as? Double)
        record("gpu", gpuPct)
        rollHistory(now)

        var mem = memory
        mem["history"] = ["pressurePct": hist("pressurePct", 0), "swapUsedBytes": hist("swapUsedBytes", 0)]
        var cpuOut = cpu
        cpuOut["history"] = hist("cpu", 1)

        // Disk
        let vol = Disk.volume()
        let diskNow = Disk.counters()
        var readBps: Any = NSNull(), writeBps: Any = NSNull()
        if let d = diskNow, let p = prevDisk, dt > 0 {
            readBps = num(Double(d.read &- p.read) / dt, 0)
            writeBps = num(Double(d.written &- p.written) / dt, 0)
        }
        prevDisk = diskNow

        // Network (primary interface, re-checked every 10 s)
        if now.timeIntervalSince(ifaceCheckedAt) > 10 {
            ifaceCheckedAt = now
            if let bsd = Network.primaryInterface() {
                iface = (bsd, Network.displayName(bsd: bsd) ?? bsd)
            } else { iface = nil }
        }
        let netNow = iface.flatMap { Network.counters(bsd: $0.bsd) }
        var net: [String: Any] = ["iface": iface?.name ?? NSNull(), "inBps": NSNull(), "outBps": NSNull(),
                                  "packetsInPs": NSNull(), "packetsOutPs": NSNull()]
        if let n = netNow, let p = prevNet, prevNetIface == iface?.bsd, dt > 0 {
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
            "bigUsers": diskScan.bigUsers ?? NSNull(),
        ]

        // Energy
        let p = Power.read()
        let energy: [String: Any] = [
            "batteryPct": p.batteryPct ?? NSNull(), "pluggedIn": p.pluggedIn ?? NSNull(),
            "charging": p.charging ?? NSNull(), "fullyCharged": p.fullyCharged ?? NSNull(),
            "adapterWatts": p.adapterWatts ?? NSNull(), "cycles": p.cycles ?? NSNull(),
            "healthPct": p.healthPct ?? NSNull(), "minutesLeft": p.minutesLeft ?? NSNull(),
            "thermal": Power.thermal(), "fanRPM": Fan.rpm().map { Int($0.rounded()) } ?? NSNull(),
            "impact": impact,
        ]

        // Memory Used (app + wired + compressed, as Activity Monitor) as a % of RAM, one decimal.
        let memUsedPct: Any = {
            guard let used = (memory["usedBytes"] as? NSNumber)?.doubleValue,
                  let total = (memory["totalBytes"] as? NSNumber)?.doubleValue, total > 0 else { return NSNull() }
            return (used / total * 1000).rounded() / 10
        }()
        addLive([
            "pressurePct": memory["pressurePct"] ?? NSNull(), "memUsedPct": memUsedPct,
            "swapUsedBytes": memory["swapUsedBytes"] ?? NSNull(),
            "cpuUserPct": cpu["userPct"] ?? NSNull(), "cpuSystemPct": cpu["systemPct"] ?? NSNull(),
            "gpuPct": num(gpuPct, 0), "diskReadBps": readBps, "diskWriteBps": writeBps,
            "netInBps": net["inBps"] ?? NSNull(), "netOutBps": net["outBps"] ?? NSNull(), "energyImpact": impact,
        ])
        var liveOut: [String: Any] = live
        liveOut["stepSec"] = 2

        let uptime = Sysctl.bootTime().map { Int(now.timeIntervalSince($0)) }
        let hostOut: [String: Any] = [
            "model": host.model ?? NSNull(), "chip": host.chip ?? NSNull(), "pCores": host.pCores ?? NSNull(),
            "eCores": host.eCores ?? NSNull(), "gpuCores": host.gpuCores ?? NSNull(), "memBytes": host.memBytes,
            "os": host.os, "uptimeSec": uptime ?? NSNull(),
        ]

        return [
            "time": Self.timeFormatter.string(from: now),
            "host": hostOut,
            "memory": mem,
            "cpu": cpuOut,
            "gpu": ["pct": num(gpuPct, 0), "history": hist("gpu", 0)],
            "energy": energy,
            "disk": disk,
            "network": net,
            "live": liveOut,
            "totals": ["processes": procs.processes, "threads": procs.threads],
            "processes": procs.rows.map { $0.json() },
        ]
    }

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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

    // MARK: history

    private func addLive(_ point: [String: Any]) {
        for (k, v) in point {
            var a = live[k] ?? []
            a.append(v)
            if a.count > Self.liveLength { a.removeFirst(a.count - Self.liveLength) }
            live[k] = a
        }
    }

    private func record(_ key: String, _ value: Double?, average: Bool = true) {
        guard let value else { return }
        if average { bucket[key, default: []].append(value) } else { bucket[key] = [value] }
    }

    private func rollHistory(_ now: Date) {
        // The very first point goes in right away so the charts aren't empty after launch.
        let first = history.isEmpty
        guard first || now.timeIntervalSince(bucketStart) >= Self.historyEvery else { return }
        for (k, vals) in bucket where !vals.isEmpty {
            var h = history[k] ?? []
            h.append(vals.reduce(0, +) / Double(vals.count))
            if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
            history[k] = h
        }
        bucket = [:]
        bucketStart = now
    }

    private func hist(_ key: String, _ places: Int) -> [Any] {
        (history[key] ?? []).map { num($0, places) }
    }
}
