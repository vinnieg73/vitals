import Foundation
import IOKit

/// Fan speed from the SMC (the Mac's system management controller). Read-only; needs no
/// permission. Returns nil if the Mac has no fan or the SMC can't be read, and 0 when the fan is off.
enum Fan {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var conn: io_connect_t = 0
    nonisolated(unsafe) private static var opened = false

    static func rpm() -> Double? {
        lock.lock(); defer { lock.unlock() }
        if !opened {
            opened = true
            let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            if svc != 0 {
                if IOServiceOpen(svc, mach_task_self_, 0, &conn) != KERN_SUCCESS { conn = 0 }
                IOObjectRelease(svc)
            }
        }
        guard conn != 0, let count = read("FNum").flatMap({ $0.bytes.first }), count > 0 else { return nil }
        var fastest: Double?   // stays nil when no fan could be read: that's "unknown", not "off"
        for i in 0..<Int(count) {
            guard let v = read("F\(i)Ac"), let rpm = decode(v) else { continue }
            fastest = max(fastest ?? 0, rpm)
        }
        return fastest
    }

    // SMCKeyData_t is 80 bytes: key@0, keyInfo.dataSize@28, keyInfo.dataType@32, data8@42, bytes@48.
    private static func call(_ input: [UInt8]) -> [UInt8]? {
        var inp = input
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, &inp, 80, &out, &outSize)
        guard kr == KERN_SUCCESS, out[40] == 0 else { return nil }
        return out
    }

    private static func put32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
        buf[off] = UInt8(v & 0xff); buf[off + 1] = UInt8((v >> 8) & 0xff)
        buf[off + 2] = UInt8((v >> 16) & 0xff); buf[off + 3] = UInt8(v >> 24)
    }

    private static func get32(_ buf: [UInt8], _ off: Int) -> UInt32 {
        UInt32(buf[off]) | UInt32(buf[off + 1]) << 8 | UInt32(buf[off + 2]) << 16 | UInt32(buf[off + 3]) << 24
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var info = [UInt8](repeating: 0, count: 80)
        put32(&info, 0, fourCC(key))
        info[42] = 9 // read key info
        guard let i = call(info) else { return nil }
        let size = Int(get32(i, 28))
        let type = get32(i, 32)
        guard size > 0, size <= 32 else { return nil }
        var req = [UInt8](repeating: 0, count: 80)
        put32(&req, 0, fourCC(key))
        put32(&req, 28, UInt32(size))
        req[42] = 5 // read bytes
        guard let r = call(req) else { return nil }
        let typeStr = String(bytes: [24, 16, 8, 0].map { UInt8((type >> $0) & 0xff) }, encoding: .ascii) ?? ""
        return (typeStr, Array(r[48..<(48 + size)]))
    }

    private static func decode(_ v: (type: String, bytes: [UInt8])) -> Double? {
        switch v.type {
        case "flt " where v.bytes.count >= 4:
            return Double(Float(bitPattern: UInt32(v.bytes[0]) | UInt32(v.bytes[1]) << 8 | UInt32(v.bytes[2]) << 16 | UInt32(v.bytes[3]) << 24))
        case "fpe2" where v.bytes.count >= 2:
            return Double(UInt16(v.bytes[0]) << 8 | UInt16(v.bytes[1])) / 4
        default:
            return nil
        }
    }
}
