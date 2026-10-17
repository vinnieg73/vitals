import Foundation

/// "Biggest space users": a background size scan every 30 minutes.
///
/// It only walks folders macOS doesn't guard with a privacy prompt. Desktop, Documents, Downloads,
/// Pictures/Photos, Movies, Music, Mail, Messages, other apps' containers and the Trash would each
/// pop up a "Vitals would like to access…" window, so they are left out.
final class DiskScan {
    private let queue = DispatchQueue(label: "vitals.diskscan", qos: .background)
    private let lock = NSLock()
    private var result: [[String: Any]]?
    private var timer: DispatchSourceTimer?

    var bigUsers: [[String: Any]]? {
        lock.lock(); defer { lock.unlock() }
        return result
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 30 * 60, leeway: .seconds(30))
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }

    private static let protected: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", ".Trash",
    ]

    private func targets() -> [(String, URL)] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")
        var list: [(String, URL)] = [
            ("Xcode simulators", lib.appendingPathComponent("Developer/CoreSimulator")),
            ("Xcode build files", lib.appendingPathComponent("Developer/Xcode")),
            ("Claude VM bundle", lib.appendingPathComponent("Application Support/Claude/vm_bundles")),
            ("App caches", lib.appendingPathComponent("Caches")),
        ]
        let items = (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for url in items where !Self.protected.contains(url.lastPathComponent) {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
            list.append((url.lastPathComponent, url))
        }
        return list
    }

    private func scan() {
        var out: [(String, UInt64)] = []
        for (name, url) in targets() {
            let bytes = Self.size(of: url)
            if bytes > 0 { out.append((name, bytes)) }
        }
        let top = out.sorted { $0.1 > $1.1 }.prefix(6).map { ["name": $0.0, "bytes": $0.1] as [String: Any] }
        lock.lock(); result = Array(top); lock.unlock()
    }

    /// Allocated size on disk (sparse VM images count what they really use).
    static func size(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
