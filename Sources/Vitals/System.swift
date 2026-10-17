import Darwin
import Foundation
import IOKit

// Small readers for sysctl, Mach and the IORegistry. Everything here is cheap and safe to call
// from the sampler's background queue.

enum Mach {
    /// 16 KB on Apple Silicon; never assume 4096.
    static let pageSize = UInt64(vm_kernel_page_size)
    /// Mach absolute-time ticks to nanoseconds (125/3 on Apple Silicon, 1 on Intel).
    static let ticksToNs: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()
}

enum Sysctl {
    static func number(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 8 else { return nil }
        var buf = [UInt8](repeating: 0, count: 8)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return buf.withUnsafeBytes { raw -> Int64 in
            switch size {
            case 4: return Int64(raw.load(as: Int32.self))
            case 8: return raw.load(as: Int64.self)
            case 2: return Int64(raw.load(as: Int16.self))
            default: return Int64(raw[0])
            }
        }
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func swap() -> (used: UInt64, total: UInt64)? {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 else { return nil }
        return (xsw.xsu_used, xsw.xsu_total)
    }

    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }
}

enum Registry {
    /// All properties of one IOKit object as a Swift dictionary.
    static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Calls `body` for every service of a class; the iterator and objects are released for you.
    static func forEach(_ className: String, _ body: (io_object_t) -> Void) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        while case let obj = IOIteratorNext(iter), obj != 0 {
            body(obj)
            IOObjectRelease(obj)
        }
    }

    static func first(_ className: String) -> [String: Any]? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return properties(svc)
    }

    static func string(fromData value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let d = value as? Data else { return nil }
        return String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// Host facts that don't change while running.
struct HostInfo {
    let model: String?
    let chip: String?
    let pCores: Int?
    let eCores: Int?
    let gpuCores: Int?
    let memBytes: UInt64
    let os: String
    /// Kind of each logical CPU ("P"/"E"), indexed by logical cpu id.
    let coreKinds: [String]

    static func read() -> HostInfo {
        var model: String?
        let product = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if product != 0 {
            // "MacBook Pro (14-inch, Nov 2023)" -> "MacBook Pro"
            if let name = Registry.string(fromData: Registry.property(product, "product-name")) {
                model = name.components(separatedBy: " (").first
            }
            IOObjectRelease(product)
        }
        if model == nil, let hw = Sysctl.string("hw.model") { model = hw }

        var gpuCores: Int?
        Registry.forEach("IOAccelerator") { obj in
            if gpuCores == nil, let n = Registry.property(obj, "gpu-core-count") as? Int { gpuCores = n }
        }

        let p = Sysctl.number("hw.perflevel0.physicalcpu").map(Int.init)
        let e = Sysctl.number("hw.perflevel1.physicalcpu").map(Int.init)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")

        return HostInfo(model: model, chip: Sysctl.string("machdep.cpu.brand_string"),
                        pCores: p, eCores: e, gpuCores: gpuCores,
                        memBytes: UInt64(Sysctl.number("hw.memsize") ?? 0), os: os,
                        coreKinds: coreKinds(p: p, e: e))
    }

    /// Reads each CPU's cluster type from the device tree. On this M3 Pro logical CPUs 0-5 are E
    /// and 6-10 are P, so the order can't be assumed from the perflevel counts.
    private static func coreKinds(p: Int?, e: Int?) -> [String] {
        var kinds: [Int: String] = [:]
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            var iter: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iter) == KERN_SUCCESS {
                while case let cpu = IOIteratorNext(iter), cpu != 0 {
                    if let id = Registry.property(cpu, "logical-cpu-id") as? Int,
                       let t = Registry.string(fromData: Registry.property(cpu, "cluster-type")) {
                        kinds[id] = t.hasPrefix("P") ? "P" : "E"
                    }
                    IOObjectRelease(cpu)
                }
                IOObjectRelease(iter)
            }
            IOObjectRelease(cpus)
        }
        let n = Int(Sysctl.number("hw.ncpu") ?? 0)
        if kinds.count == n, n > 0 { return (0..<n).map { kinds[$0]! } }
        // Fallback: Apple Silicon lists efficiency cores first.
        return Array(repeating: "E", count: e ?? 0) + Array(repeating: "P", count: p ?? max(0, n - (e ?? 0)))
    }
}

/// Mach VM counters, in pages unless noted.
struct VMCounters {
    let internalPages, purgeablePages, externalPages, wiredPages, compressorPages: UInt64
    let freePages, speculativePages: UInt64
    let swapouts: UInt64

    static func read() -> VMCounters? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return VMCounters(internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
                          externalPages: UInt64(stats.external_page_count), wiredPages: UInt64(stats.wire_count),
                          compressorPages: UInt64(stats.compressor_page_count), freePages: UInt64(stats.free_count),
                          speculativePages: UInt64(stats.speculative_count), swapouts: stats.swapouts)
    }
}

/// Per-CPU tick counters (user, system, idle, nice).
enum CPUTicks {
    static func read() -> [[UInt64]] {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpus: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpus)).map { c in
            (0..<states).map { UInt64(UInt32(bitPattern: info[c * states + $0])) }
        }
    }
}
