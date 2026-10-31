import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

// Battery, GPU, disk and network readers.

enum Power {
    struct Reading {
        var batteryPct: Int?
        var pluggedIn: Bool?
        var charging: Bool?
        var fullyCharged: Bool?
        var adapterWatts: Int?
        var cycles: Int?
        var healthPct: Int?
        var minutesLeft: Int?
    }

    /// The whole Mac's power draw right now in W (battery telemetry SystemLoad, on battery or plugged in; on battery
    /// it matches |Amperage| × Voltage). nil on Macs without a battery. Reads one property, not the whole battery,
    /// so it's cheap enough for every tick.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var battery: io_service_t = 0
    nonisolated(unsafe) private static var batteryLooked = false
    static func watts() -> Double? {
        lock.lock(); defer { lock.unlock() }
        if !batteryLooked { batteryLooked = true; battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")) }
        guard battery != 0, let tele = Registry.property(battery, "PowerTelemetryData") as? [String: Any],
              let mW = tele["SystemLoad"] as? Int, mW > 0, mW < 1_000_000 else { return nil }
        return (Double(mW) / 100).rounded() / 10
    }

    static func read() -> Reading {
        var r = Reading()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for src in list {
                guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
                      (d["Type"] as? String) == "InternalBattery" else { continue }
                if let cur = d["Current Capacity"] as? Int, let max = d["Max Capacity"] as? Int, max > 0 {
                    r.batteryPct = Int((Double(cur) / Double(max) * 100).rounded())
                }
                r.pluggedIn = (d["Power Source State"] as? String) == "AC Power"
                r.charging = d["Is Charging"] as? Bool
                r.fullyCharged = d["Is Charged"] as? Bool ?? false
                if r.pluggedIn == false, let t = d["Time to Empty"] as? Int, t > 0 { r.minutesLeft = t }
            }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            r.adapterWatts = adapter["Watts"] as? Int
        }
        if let b = Registry.first("AppleSmartBattery") {
            r.cycles = b["CycleCount"] as? Int
            let data = b["BatteryData"] as? [String: Any] ?? [:]
            // On Apple Silicon "MaxCapacity" is already a percent; health is the real mAh capacity
            // over design capacity, the same number System Settings calls "Maximum Capacity".
            let design = (b["DesignCapacity"] as? Int) ?? (data["DesignCapacity"] as? Int)
            let full = (b["AppleRawMaxCapacity"] as? Int) ?? (data["NominalChargeCapacity"] as? Int)
                ?? (data["FullChargeCapacity"] as? Int)
            if let design, let full, design > 0 { r.healthPct = min(100, Int((Double(full) / Double(design) * 100).rounded())) }
            if r.batteryPct == nil, let c = b["CurrentCapacity"] as? Int { r.batteryPct = c }
            // Plugged in: how long the battery would last at the Mac's current draw.
            if r.pluggedIn == true {
                let tele = b["PowerTelemetryData"] as? [String: Any] ?? [:]
                let remaining = (b["AppleRawCurrentCapacity"] as? Int) ?? (data["RemainingCapacity"] as? Int)
                if let mAh = remaining, let mV = b["Voltage"] as? Int, let loadMW = tele["SystemLoad"] as? Int, loadMW > 500 {
                    let wh = Double(mAh) * Double(mV) / 1e6
                    r.minutesLeft = Int((wh / (Double(loadMW) / 1000) * 60).rounded())
                }
            }
        }
        return r
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }
}

enum GPU {
    /// IOAccelerator PerformanceStatistics: how busy the GPU is overall, its two halves (renderer: pixels and
    /// shading; tiler: shapes and geometry), and the memory it has in use (part of the Mac's shared RAM).
    struct Stats { var pct, rendererPct, tilerPct: Double?; var memBytes: UInt64? }

    static func stats() -> Stats {
        var out = Stats()
        var found = false
        Registry.forEach("IOAccelerator") { obj in
            guard !found, let stats = Registry.property(obj, "PerformanceStatistics") as? [String: Any],
                  let v = stats["Device Utilization %"] as? Int else { return }
            found = true
            out.pct = Double(v)
            out.rendererPct = (stats["Renderer Utilization %"] as? Int).map(Double.init)
            out.tilerPct = (stats["Tiler Utilization %"] as? Int).map(Double.init)
            out.memBytes = (stats["In use system memory"] as? NSNumber)?.uint64Value
        }
        return out
    }
    static func utilization() -> Double? { stats().pct }
}

enum Disk {
    /// Bytes read and written since boot by internal drives. Disk images ("File") are skipped
    /// so their traffic isn't counted twice.
    static func counters() -> (read: UInt64, written: UInt64)? {
        var read: UInt64 = 0, written: UInt64 = 0, found = false
        Registry.forEach("IOBlockStorageDriver") { drv in
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(drv, kIOServicePlane, &parent) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(parent) }
            let proto = Registry.property(parent, "Protocol Characteristics") as? [String: Any]
            guard (proto?["Physical Interconnect Location"] as? String) == "Internal",
                  let stats = Registry.property(drv, "Statistics") as? [String: Any] else { return }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? (read, written) : nil
    }

    /// Finder-style numbers for the startup volume: free includes purgeable space.
    static func volume() -> (name: String?, total: UInt64?, free: UInt64?) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (nil, nil, nil) }
        return (v.volumeLocalizedName, v.volumeTotalCapacity.map(UInt64.init),
                v.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) })
    }
}

enum Network {
    struct Counters { var inBytes: UInt64 = 0, outBytes: UInt64 = 0, inPackets: UInt64 = 0, outPackets: UInt64 = 0 }

    /// BSD name of the interface carrying the default route, e.g. "en0".
    /// One connection to configd for the app's life, not a new one every check.
    private static let store = SCDynamicStoreCreate(nil, "Vitals" as CFString, nil, nil)

    static func primaryInterface() -> String? {
        guard let store else { return nil }
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let d = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               let name = d["PrimaryInterface"] as? String { return name }
        }
        return nil
    }

    /// "Wi-Fi", "Ethernet", "Thunderbolt Bridge"…
    static func displayName(bsd: String) -> String? {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for i in all where (SCNetworkInterfaceGetBSDName(i) as String?) == bsd {
            return SCNetworkInterfaceGetLocalizedDisplayName(i) as String?
        }
        return nil
    }

    /// 64-bit counters from the routing sysctl (getifaddrs' if_data counters are 32-bit and wrap at 4 GB).
    static func counters(bsd: String) -> Counters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
        guard let wanted = Optional(if_nametoindex(bsd)), wanted != 0 else { return nil }
        return buf.withUnsafeBytes { raw -> Counters? in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                    let m = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    if UInt32(m.ifm_index) == wanted {
                        let d = m.ifm_data
                        return Counters(inBytes: d.ifi_ibytes, outBytes: d.ifi_obytes,
                                        inPackets: d.ifi_ipackets, outPackets: d.ifi_opackets)
                    }
                }
                guard hdr.ifm_msglen > 0 else { break }
                off += Int(hdr.ifm_msglen)
            }
            return nil
        }
    }
}

/// "Today" totals for disk and network. The counters run since boot, so this keeps a baseline
/// taken at local midnight, persisted so a relaunch the same day keeps it. When the baseline is
/// unknown (first launch today, Vitals wasn't running at midnight) it falls back to the last
/// value Vitals saw yesterday, and failing that to zero (= since boot), as DATA.md allows.
final class DailyBaseline {
    private let key = "dailyBaseline"
    private var day: String
    private var boot: Int
    private var session: String?          // the boot session id the baseline belongs to
    private let bootSession: String?      // this boot's (kern.bootsessionuuid), read once
    private var base: [String: UInt64]
    private var lastSeen: [String: UInt64]
    private var lastSaved = Date.distantPast
    private let store: UserDefaults

    init(store: UserDefaults = .standard, bootSession: String? = Sysctl.string("kern.bootsessionuuid")) {
        self.store = store
        self.bootSession = bootSession
        let d = store.dictionary(forKey: key) ?? [:]
        day = d["day"] as? String ?? ""
        boot = d["boot"] as? Int ?? 0
        session = (d["session"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        base = (d["base"] as? [String: NSNumber])?.mapValues(\.uint64Value) ?? [:]
        lastSeen = (d["lastSeen"] as? [String: NSNumber])?.mapValues(\.uint64Value) ?? [:]
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The local day in the time zone in force now: the Mac may have moved time zones since launch, and a formatter
    /// made once keeps the zone it was made in.
    static func dayString(_ date: Date, zone: TimeZone = .current) -> String {
        if dayFormat.timeZone?.identifier != zone.identifier { dayFormat.timeZone = zone }
        return dayFormat.string(from: date)
    }

    private static func today() -> String { dayString(Date()) }

    /// Returns counter - baseline for each value, and records the values. `day`, `boot` and `session` are for --selftest.
    func today(_ current: [String: UInt64], day dayNow: String? = nil, boot bootIn: Int? = nil, session sessionIn: String? = nil) -> [String: UInt64] {
        let now = dayNow ?? Self.today()
        let bootNow = bootIn ?? Int(Sysctl.bootTime()?.timeIntervalSince1970 ?? 0)
        let sessionNow = sessionIn ?? bootSession
        // A reboot gets a new boot session id. kern.boottime is no good for this: it moves by as much as the clock
        // moves (a second when macOS corrects it, hours when the date or time is changed by hand). Without an id
        // on both sides (a baseline saved by an older Vitals, or the sysctl fails), only a boot time move over
        // 60 s is a reboot; follow the small moves so they can't add up.
        let rebooted: Bool
        if let sessionNow, let session { rebooted = sessionNow != session } else { rebooted = abs(bootNow - boot) > 60 }
        if rebooted {
            // Rebooted (or first run): counters restarted at zero.
            base = [:]; lastSeen = [:]; day = now
        } else if day != now {
            // A new day with the same boot: the last values seen before midnight are the baseline.
            base = lastSeen; day = now
        }
        boot = bootNow
        if let sessionNow { session = sessionNow }
        // A counter below its last value restarted (an interface that went away and came back): count from zero.
        for (k, v) in current where v < (lastSeen[k] ?? 0) { base[k] = 0 }
        // Merge, so an interface that's down at midnight still has a baseline when it comes back.
        lastSeen.merge(current) { $1 }
        // Saved every 5 minutes (and on quit): a crash loses at most that much of "since the last value".
        if Date().timeIntervalSince(lastSaved) > 300 { save() }
        var out: [String: UInt64] = [:]
        for (k, v) in current {
            let b = base[k] ?? 0
            out[k] = v >= b ? v - b : v
        }
        return out
    }

    func save() {
        lastSaved = Date()
        store.set([
            "day": day, "boot": boot, "session": session ?? "",
            "base": base.mapValues { NSNumber(value: $0) },
            "lastSeen": lastSeen.mapValues { NSNumber(value: $0) },
        ] as [String: Any], forKey: key)
    }
}
