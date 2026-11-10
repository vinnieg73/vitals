import Foundation

/// The window's long charts (DATA.md `long`): one point a minute, the average of that minute's samples, for the last
/// 12 hours. Each series is averaged over its own non-null samples (a waking sample has no rates; energy impact is
/// only there while a page shows). Minutes with no sample at all (the Mac asleep) are nulls. The last point is the
/// minute in progress, so the right edge is "now".
/// A level (`worstKeys`: memory strain 0 / 1 / 2) is the minute's worst, not its average.
///
/// The installed app keeps it across restarts: `save(to:)` writes a small versioned file (at most every 5 minutes,
/// on quit and before sleep; the sampler decides when) and `load(from:now:)` reads it back at launch. The time
/// Vitals wasn't running becomes empty minutes like any other stretch nobody sampled, so the charts show a gap.
/// A file that is missing, from another version, damaged or older than 12 hours is ignored.
struct LongHistory {
    /// The saved file's format. Another number is ignored (the charts just start over).
    static let fileVersion = 1
    /// ~/Library/Application Support/Vitals/history.json: only the installed app reads or writes it.
    static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Vitals/history.json")
    }

    private struct Saved: Codable {
        var version: Int
        var lastMinute: Int          // the newest row's minute (minutes since 1970)
        var keys: [String]
        var rows: [[Double?]?]       // oldest first, one per minute; null = no sample that minute; values in `keys` order
    }

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

    init() {}

    // MARK: saving

    /// The history as the saved file holds it, or nil before any sample.
    func saved() -> Data? {
        guard let minute else { return nil }
        let rows = (minutes + [average()]).map { row -> [Double?]? in
            guard let row else { return nil }
            return keys.map { row[$0] }
        }
        return try? JSONEncoder().encode(Saved(version: Self.fileVersion, lastMinute: minute, keys: keys, rows: rows))
    }

    /// The history a file held, as of `now`. nil (start over) if it isn't this format, is damaged, ends in the
    /// future, or ends 12 hours or more ago. The newest saved minute stays open, so the next `add` either carries
    /// on in it (a quick restart) or closes it and leaves empty minutes for the time in between.
    init?(saved data: Data, now: Date) {
        guard let s = try? JSONDecoder().decode(Saved.self, from: data), s.version == Self.fileVersion,
              !s.keys.isEmpty, s.keys.count <= 64, Set(s.keys).count == s.keys.count,
              !s.rows.isEmpty, s.rows.count <= Self.length,
              s.rows.allSatisfy({ $0 == nil || $0!.count == s.keys.count }) else { return nil }
        let nowMinute = Int((now.timeIntervalSince1970 / 60).rounded(.down))
        guard s.lastMinute <= nowMinute + 2, nowMinute - s.lastMinute < Self.length else { return nil }
        var rows = s.rows.map { row -> [String: Double]? in
            guard let row else { return nil }
            var d: [String: Double] = [:]
            for (k, v) in zip(s.keys, row) { if let v, v.isFinite { d[k] = v } }
            return d.isEmpty ? nil : d
        }
        let open = rows.removeLast()
        keys = s.keys
        minutes = rows
        minute = s.lastMinute
        for (k, v) in open ?? [:] { sums[k] = (v, 1, v) }
        trim()
    }

    static func load(from url: URL, now: Date = Date()) -> LongHistory? {
        guard let data = try? Data(contentsOf: url), data.count < 4_000_000 else { return nil }
        return LongHistory(saved: data, now: now)
    }

    /// Writes the file in one step (a temporary file, then a rename), so a crash can't leave half of one.
    @discardableResult
    func save(to url: URL) -> Bool {
        guard let data = saved() else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
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
