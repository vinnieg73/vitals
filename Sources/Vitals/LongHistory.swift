import Foundation

/// The window's long charts (DATA.md `long`): one point a minute, the average of that minute's samples, for the last
/// 12 hours. Each series is averaged over its own non-null samples (a waking sample has no rates; energy impact is
/// only there while a page shows). Minutes with no sample at all (the Mac asleep) are nulls. The last point is the
/// minute in progress, so the right edge is "now". Kept in memory only: it starts over when Vitals does.
/// A level (`worstKeys`: memory strain 0 / 1 / 2) is the minute's worst, not its average.
struct LongHistory {
    static let length = 720
    static let worstKeys: Set<String> = ["memStrain"]
    private var minutes: [[String: Double]?] = []      // finished minutes, oldest first; nil = no sample that minute
    private var minute: Int?                            // the minute in progress (minutes since 1970)
    private var sums: [String: (sum: Double, n: Int, worst: Double)] = [:]
    private var keys: [String] = []

    mutating func add(_ point: [String: Any], at date: Date) {
        let m = Int((date.timeIntervalSince1970 / 60).rounded(.down))
        if let cur = minute, m != cur {
            close()
            // Minutes nobody sampled become gaps; a clock that went back just starts a new minute.
            if m > cur { for _ in 0..<min(m - cur - 1, Self.length) { minutes.append(nil) } }
            trim()
        }
        minute = m
        for (k, v) in point {
            if !keys.contains(k) { keys.append(k) }
            guard let x = (v as? NSNumber)?.doubleValue, x.isFinite else { continue }
            let s = sums[k] ?? (0, 0, x)
            sums[k] = (s.sum + x, s.n + 1, max(s.worst, x))
        }
    }

    private func average() -> [String: Double]? {
        var out: [String: Double] = [:]
        for (k, s) in sums where s.n > 0 { out[k] = Self.worstKeys.contains(k) ? s.worst : s.sum / Double(s.n) }
        return out.isEmpty ? nil : out
    }
    private mutating func close() {
        minutes.append(average())
        sums = [:]
    }
    private mutating func trim() {
        if minutes.count > Self.length - 1 { minutes.removeFirst(minutes.count - (Self.length - 1)) }
    }

    /// Points so far, the minute in progress included.
    var count: Int { minute == nil ? 0 : minutes.count + 1 }

    func json() -> [String: Any] {
        var out: [String: Any] = ["stepSec": 60]
        guard minute != nil else { return out }
        let all = minutes + [average()]
        for k in keys {
            out[k] = all.map { row -> Any in
                guard let v = row?[k] else { return NSNull() }
                return v >= 100 ? v.rounded() : (v * 10).rounded() / 10
            }
        }
        return out
    }
}
