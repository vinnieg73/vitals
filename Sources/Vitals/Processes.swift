import AppKit
import Darwin
import Foundation

// Every process on the Mac, Activity Monitor style, then grouped the way DATA.md asks:
// helpers under their app, the Claude desktop VM under Claude, `claude` CLI sessions under one
// synthetic "Claude Code" group.

/// One row of the process table, as sent to the pages.
final class Row {
    var id: String
    var pid: Int32?
    var name: String
    var kind: String
    var user: String?
    var mem: UInt64?
    var cpuPct: Double?
    var cpuTimeSec: Double?
    var threads: Int?
    var energy: Double?
    var diskR: Double?, diskW: Double?, netIn: Double?, netOut: Double?
    var model: String?
    var note: String?
    var children: [Row] = []

    init(id: String, pid: Int32?, name: String, kind: String, user: String?) {
        self.id = id; self.pid = pid; self.name = name; self.kind = kind; self.user = user
    }

    /// A copy of this row's own numbers under a new id (used for "the app itself").
    func copy(id: String) -> Row {
        let r = Row(id: id, pid: pid, name: name, kind: "process", user: user)
        r.mem = mem; r.cpuPct = cpuPct; r.cpuTimeSec = cpuTimeSec; r.threads = threads; r.energy = energy
        r.diskR = diskR; r.diskW = diskW; r.netIn = netIn; r.netOut = netOut
        return r
    }

    /// Sets this row's numbers to the sum of `rows`. A field stays null only if every row has it null.
    func sum(of rows: [Row]) {
        func add<T: AdditiveArithmetic>(_ k: KeyPath<Row, T?>) -> T? {
            let vals = rows.compactMap { $0[keyPath: k] }
            return vals.isEmpty ? nil : vals.reduce(.zero, +)
        }
        mem = add(\.mem); cpuPct = add(\.cpuPct); cpuTimeSec = add(\.cpuTimeSec); threads = add(\.threads)
        energy = add(\.energy); diskR = add(\.diskR); diskW = add(\.diskW); netIn = add(\.netIn); netOut = add(\.netOut)
    }

    func json() -> [String: Any] {
        [
            "id": id, "pid": pid.map { Int($0) as Any } ?? NSNull(), "name": name, "kind": kind,
            "user": user ?? NSNull(), "memBytes": mem.map { $0 as Any } ?? NSNull(),
            "cpuPct": num(cpuPct, 1), "cpuTimeSec": num(cpuTimeSec, 0), "threads": threads ?? NSNull(),
            "energy": num(energy, 1), "diskReadBps": num(diskR, 0), "diskWriteBps": num(diskW, 0),
            "netInBps": num(netIn, 0), "netOutBps": num(netOut, 0),
            "model": model ?? NSNull(), "note": note ?? NSNull(),
            "children": children.map { $0.json() },
        ]
    }
}

/// A number rounded for JSON, or null.
func num(_ v: Double?, _ places: Int) -> Any {
    guard let v, v.isFinite else { return NSNull() }
    let p = pow(10, Double(places))
    return (v * p).rounded() / p
}

private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
/// Private libquarantine call Activity Monitor-alikes use to find which app "owns" a helper
/// (XPC services, the Virtualization VM, renderer processes).
private let responsibleFn: ResponsibleFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
    return unsafeBitCast(sym, to: ResponsibleFn.self)
}()

final class ProcessSampler {
    private struct Prev { let start: UInt64; let cpuNs: UInt64; let diskR: UInt64; let diskW: UInt64; let wakeups: UInt64 }
    private var prev: [pid_t: Prev] = [:]
    private var prevTime: UInt64 = 0
    private var users: [uid_t: String] = [:]
    private let nettop = NetTop()
    private let sessions = SessionModels()
    private let me = getuid()

    /// Per-process network needs `nettop`, which costs a little, so it only runs while a page shows it.
    var wantNetwork = false { didSet { nettop.enabled = wantNetwork } }

    struct Result { let rows: [Row]; let processes: Int; let threads: Int }

    /// For --dump: measure per-process network once, blocking.
    func primeNetwork(interval: TimeInterval) { nettop.primeBlocking(interval: interval) }

    func sample() -> Result {
        let now = mach_absolute_time()
        let dt = prevTime == 0 ? 0 : Double(now - prevTime) * Mach.ticksToNs / 1e9
        prevTime = now

        var count = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        pids = Array(pids.prefix(Int(max(0, count))))

        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier > 0 {
            if app.activationPolicy == .regular || (app.activationPolicy == .accessory && !(app.bundleURL?.path.hasPrefix("/System/") ?? true)) {
                apps[app.processIdentifier] = app
            }
        }
        let net = nettop.rates()

        var rows: [pid_t: Row] = [:]
        var paths: [pid_t: String] = [:]
        var ppids: [pid_t: pid_t] = [:]
        var seen: [pid_t: Prev] = [:]
        var threads = 0

        for pid in pids {
            var bsd = proc_bsdinfo()
            let gotBSD = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size)
            let path = Self.path(pid)
            if let path { paths[pid] = path }
            if gotBSD { ppids[pid] = pid_t(bsd.pbi_ppid) }

            var name: String
            if let app = apps[pid], let n = app.localizedName { name = n }
            else if let path, !path.isEmpty { name = (path as NSString).lastPathComponent }
            else if gotBSD { name = Self.cString(bsd.pbi_name).nonEmpty ?? Self.cString(bsd.pbi_comm) }
            else if pid == 0 { name = "kernel_task" }
            else { name = "pid \(pid)" }
            if pid == 0 { name = "kernel_task" }

            let uid: uid_t? = gotBSD ? bsd.pbi_uid : nil
            let row = Row(id: "pid:\(pid)", pid: pid, name: name, kind: apps[pid] != nil ? "app" : "process",
                          user: uid.map(userName))

            // Other users' processes (root, _windowserver) refuse these calls without a
            // privileged helper; their numbers stay null.
            var ru = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0
            if ok {
                row.mem = ru.ri_phys_footprint
                let cpuNs = UInt64(Double(ru.ri_user_time + ru.ri_system_time) * Mach.ticksToNs)
                row.cpuTimeSec = Double(cpuNs) / 1e9
                let wake = ru.ri_pkg_idle_wkups + ru.ri_interrupt_wkups
                let cur = Prev(start: ru.ri_proc_start_abstime, cpuNs: cpuNs, diskR: ru.ri_diskio_bytesread,
                               diskW: ru.ri_diskio_byteswritten, wakeups: wake)
                seen[pid] = cur
                if dt > 0, let p = prev[pid], p.start == cur.start {
                    row.cpuPct = Double(cpuNs &- p.cpuNs) / 1e9 / dt * 100
                    row.diskR = Double(cur.diskR &- p.diskR) / dt
                    row.diskW = Double(cur.diskW &- p.diskW) / dt
                    // Rough Activity Monitor-style energy impact: CPU plus a little per wakeup.
                    let wakePerSec = Double(cur.wakeups &- p.wakeups) / dt
                    row.energy = row.cpuPct! + wakePerSec * 0.02
                } else if dt > 0 {
                    row.cpuPct = 0; row.diskR = 0; row.diskW = 0; row.energy = 0
                }
            }
            var task = proc_taskinfo()
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) == Int32(MemoryLayout<proc_taskinfo>.size) {
                row.threads = Int(task.pti_threadnum)
                threads += Int(task.pti_threadnum)
            }
            if let n = net {
                let r = n[pid]
                row.netIn = r?.0 ?? 0
                row.netOut = r?.1 ?? 0
            }
            rows[pid] = row
        }
        prev = seen
        return Result(rows: group(rows, paths: paths, ppids: ppids, apps: apps), processes: pids.count, threads: threads)
    }

    // MARK: grouping

    private static func isClaudeBinary(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == "claude" || path.contains("/claude/versions/")
    }

    private func group(_ rows: [pid_t: Row], paths: [pid_t: String], ppids: [pid_t: pid_t],
                       apps: [pid_t: NSRunningApplication]) -> [Row] {
        var top: [Row] = []
        var kids: [pid_t: [Row]] = [:]
        var sessions: [pid_t: Row] = [:]
        var tools: [pid_t: Row] = [:]
        let appBundles: [(pid_t, String)] = apps.compactMap { pid, app in app.bundleURL.map { (pid, $0.path + "/") } }
        let myName = userName(me)

        // 1. Claude Code CLI sessions, wherever they were started from (Terminal or the desktop app).
        //    The same binary also runs its built-in tools (ugrep and friends) under another argv[0];
        //    those are folded into the session that started them.
        for (pid, row) in rows where row.user == myName && Self.isClaudeBinary(paths[pid] ?? "") {
            let argv0 = Self.argv0(pid).map { ($0 as NSString).lastPathComponent }
            if argv0 == nil || argv0 == "claude" {
                row.kind = "session"
                let cwd = Self.cwd(pid)
                row.name = cwd.map { ($0 as NSString).lastPathComponent } ?? "claude"
                row.model = cwd.flatMap { self.sessions.model(cwd: $0) }
                sessions[pid] = row
            } else {
                if let argv0 { row.name = argv0 }
                tools[pid] = row
            }
        }
        for (pid, row) in tools {
            var p = ppids[pid] ?? 0, hops = 0
            while p > 1, sessions[p] == nil, hops < 8 { p = ppids[p] ?? 0; hops += 1 }
            if let s = sessions[p] { s.sum(of: [s, row]) } else {
                // Its session is gone; it's a leftover tool process.
                row.note = "left over from Claude Code"
                top.append(row)
            }
        }

        // 2. Helpers under their app: the responsible pid, else the app bundle the binary lives in.
        //    Followed to the top, so a helper app's own helpers land under the main app too.
        var owner: [pid_t: pid_t] = [:]
        for (pid, _) in rows where sessions[pid] == nil && tools[pid] == nil {
            let path = paths[pid] ?? ""
            var o: pid_t?
            if let fn = responsibleFn { let r = fn(pid); if r > 0, r != pid, apps[r] != nil { o = r } }
            if o == nil { o = appBundles.first { $0.0 != pid && path.hasPrefix($0.1) }?.0 }
            if let o, rows[o] != nil, sessions[o] == nil { owner[pid] = o }
        }
        for (pid, row) in rows where sessions[pid] == nil && tools[pid] == nil {
            var root = pid, hops = 0
            while let o = owner[root], o != pid, hops < 8 { root = o; hops += 1 }
            guard root != pid else { top.append(row); continue }
            let path = paths[pid] ?? ""
            if path.contains("com.apple.Virtualization.VirtualMachine") {
                if apps[root]?.bundleIdentifier == "com.anthropic.claudefordesktop" { row.name = "Sandbox virtual machine" }
                row.note = "virtual machine"
            }
            row.kind = "process"
            kids[root, default: []].append(row)
        }
        let sessionRows = Array(sessions.values)

        // Apps with helpers become a summed row; the app's own process is listed as one of its children.
        for row in top where row.kind == "app" {
            guard let pid = row.pid, var children = kids[pid], !children.isEmpty else { continue }
            let own = row.copy(id: "pid:\(pid)")
            own.kind = "app"
            own.note = "the app itself"
            children.append(own)
            children.sort(by: Self.byMemory)
            row.id = "group:" + Self.slug(row.name)
            row.children = children
            row.sum(of: children)
        }

        if !sessionRows.isEmpty {
            let g = Row(id: "group:claude-code", pid: nil, name: "Claude Code", kind: "group", user: userName(me))
            g.children = sessionRows.sorted(by: Self.byMemory)
            g.sum(of: g.children)
            g.note = sessionRows.count == 1 ? "1 session" : "\(sessionRows.count) sessions"
            top.append(g)
        }
        return top.sorted(by: Self.byMemory)
    }

    private static func byMemory(_ a: Row, _ b: Row) -> Bool { (a.mem ?? 0) > (b.mem ?? 0) }

    private static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    // MARK: helpers

    private func userName(_ uid: uid_t) -> String {
        if let n = users[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        users[uid] = n
        return n
    }

    private static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// argv[0] of a process, from KERN_PROCARGS2 (only works for your own processes).
    static func argv0(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 8 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Layout: argc (Int32), exec path, NUL padding, argv[0], ...
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }
        while i < size, buf[i] == 0 { i += 1 }
        let start = i
        while i < size, buf[i] != 0 { i += 1 }
        return i > start ? String(decoding: buf[start..<i], as: UTF8.self) : nil
    }

    static func cwd(_ pid: pid_t) -> String? {
        var vpi = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, size) == size else { return nil }
        let s = withUnsafeBytes(of: vpi.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return s.isEmpty ? nil : s
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Which model a Claude Code session in a folder is using: the newest "model" field in that
/// folder's newest transcript under ~/.claude/projects. Cached by file and modification time.
final class SessionModels {
    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    private var cache: [String: (file: String, mtime: Date, model: String?)] = [:]
    private var checked: [String: Date] = [:]
    private let modelRegex = try! NSRegularExpression(pattern: #""model"\s*:\s*"(claude-[a-z]+)"#)

    func model(cwd: String) -> String? {
        // Rescan a folder at most every 20 s.
        if let t = checked[cwd], Date().timeIntervalSince(t) < 20 { return cache[cwd]?.model }
        checked[cwd] = Date()
        let dirName = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let dir = root.appendingPathComponent(dirName)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return cache[cwd]?.model
        }
        let newest = files.filter { $0.pathExtension == "jsonl" }
            .compactMap { u -> (URL, Date)? in
                (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) }
            }
            .max { $0.1 < $1.1 }
        guard let (file, mtime) = newest else { return cache[cwd]?.model }
        if let c = cache[cwd], c.file == file.path, c.mtime == mtime { return c.model }
        let m = Self.readModel(file, regex: modelRegex) ?? (cache[cwd]?.file == file.path ? cache[cwd]?.model : nil)
        cache[cwd] = (file.path, mtime, m)
        return m
    }

    private static func readModel(_ url: URL, regex: NSRegularExpression) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        // Read backwards in 256 KB chunks (up to 2 MB) until a model shows up.
        var offset = end
        let chunk: UInt64 = 256 * 1024
        while offset > 0, end - offset < 2 * 1024 * 1024 {
            let start = offset > chunk ? offset - chunk : 0
            try? h.seek(toOffset: start)
            guard let data = try? h.read(upToCount: Int(offset - start + 200)) else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            let ns = text as NSString
            if let m = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last {
                let id = ns.substring(with: m.range(at: 1))
                for (k, v) in [("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku"), ("fable", "Fable")] where id.contains(k) {
                    return v
                }
            }
            offset = start
        }
        return nil
    }
}

/// Per-process network rates from `nettop`, which reports cumulative bytes per process.
/// Runs on its own queue every 10 s while enabled; rates are deltas between runs.
final class NetTop {
    private let queue = DispatchQueue(label: "vitals.nettop", qos: .utility)
    private let lock = NSLock()
    private var last: [pid_t: (UInt64, UInt64)] = [:]
    private var lastAt: Date?
    private var current: [pid_t: (Double, Double)]?
    private var timer: DispatchSourceTimer?

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { start() } else { stop() }
        }
    }

    func rates() -> [pid_t: (Double, Double)]? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Runs nettop twice, `interval` apart, and blocks until the rates are known (for --dump).
    func primeBlocking(interval: TimeInterval) {
        queue.sync { run() }
        Thread.sleep(forTimeInterval: interval)
        queue.sync { run() }
    }

    private func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 10, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.run() }
        t.resume()
        timer = t
    }

    private func stop() {
        timer?.cancel(); timer = nil
        lock.lock(); current = nil; last = [:]; lastAt = nil; lock.unlock()
    }

    private func run() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -n skips hostname lookups, which otherwise make each run take ~5 s.
        p.arguments = ["-P", "-n", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        let now = Date()
        var totals: [pid_t: (UInt64, UInt64)] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3, let dot = cols[0].lastIndex(of: "."),
                  let pid = pid_t(cols[0][cols[0].index(after: dot)...]),
                  let i = UInt64(cols[1]), let o = UInt64(cols[2]) else { continue }
            let t = totals[pid] ?? (0, 0)
            totals[pid] = (t.0 + i, t.1 + o)
        }
        lock.lock()
        if let lastAt {
            let dt = now.timeIntervalSince(lastAt)
            var r: [pid_t: (Double, Double)] = [:]
            for (pid, t) in totals {
                let p = last[pid] ?? t   // new process: no rate until the next run
                r[pid] = (Double(t.0 >= p.0 ? t.0 - p.0 : 0) / dt, Double(t.1 >= p.1 ? t.1 - p.1 : 0) / dt)
            }
            current = r
        }
        last = totals
        lastAt = now
        lock.unlock()
    }
}
