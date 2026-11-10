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
    /// For a loose process at the top of the list: who started it ("Claude Code · folder", or an app's name).
    var startedBy: String?
    /// When the process started (mach ticks), so Quit can tell it apart from a later process with the same pid.
    var started: UInt64?
    var children: [Row] = []

    init(id: String, pid: Int32?, name: String, kind: String, user: String?) {
        self.id = id; self.pid = pid; self.name = name; self.kind = kind; self.user = user
    }

    /// A copy of this row's own numbers under a new id (used for "the app itself").
    func copy(id: String) -> Row {
        let r = Row(id: id, pid: pid, name: name, kind: "process", user: user)
        r.mem = mem; r.cpuPct = cpuPct; r.cpuTimeSec = cpuTimeSec; r.threads = threads; r.energy = energy
        r.diskR = diskR; r.diskW = diskW; r.netIn = netIn; r.netOut = netOut
        r.started = started
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
            "energy": num(energy, 1),
            "diskReadBps": num(diskR, 0), "diskWriteBps": num(diskW, 0),
            "netInBps": num(netIn, 0), "netOutBps": num(netOut, 0),
            "model": model ?? NSNull(), "note": note ?? NSNull(), "startedBy": startedBy ?? NSNull(),
            // A string, so the page passes it back exactly.
            "started": started.map { String($0) as Any } ?? NSNull(),
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
    private var lastGroupIDs: [pid_t: (base: String, id: String)] = [:]
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
                row.started = ru.ri_proc_start_abstime
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
        var sessionFolders: [SessionModels.Session] = []
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
                sessionFolders.append(SessionModels.Session(pid: pid, cwd: cwd))
                sessions[pid] = row
            } else {
                if let argv0 { row.name = argv0 }
                tools[pid] = row
            }
        }
        // Each session's own model (its own transcript), never a guess from the folder it shares with others.
        let models = self.sessions.models(for: sessionFolders)
        for (pid, row) in sessions { row.model = models[pid] }
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
        // Two apps with the same name get "group:name" and "group:name-2" (oldest pid first), and each keeps its id
        // while it runs: when the first quits, the second doesn't take over its row (the page's selection and open
        // groups go by id).
        let groups = top.sorted(by: { ($0.pid ?? 0) < ($1.pid ?? 0) }).filter { row in
            row.kind == "app" && row.pid.flatMap { kids[$0] }?.isEmpty == false
        }
        let ids = Self.groupIDs(groups.map { (pid: $0.pid!, base: "group:" + Self.slug($0.name)) }, previous: lastGroupIDs)
        lastGroupIDs = ids
        for row in groups {
            guard let pid = row.pid, var children = kids[pid], let id = ids[pid]?.id else { continue }
            let own = row.copy(id: "pid:\(pid)")
            own.kind = "app"
            own.note = "the app itself"
            children.append(own)
            children.sort(by: Self.byMemory)
            row.id = id
            row.children = children
            row.sum(of: children)
        }

        // 3. Loose processes: say who started them (the nearest Claude Code session or app up the parent chain),
        //    and name a script runtime ("node", "python3") after the script it runs, so "node" reads "vite".
        for row in top where row.kind == "process" {
            guard let pid = row.pid else { continue }
            var p = ppids[pid] ?? 0, hops = 0
            while p > 1, hops < 12 {
                if let s = sessions[p] { row.startedBy = "Claude Code · " + s.name; break }
                if let app = apps[p] { row.startedBy = app.localizedName; break }
                p = ppids[p] ?? 0; hops += 1
            }
            if row.user == myName, Self.isRuntime(row.name), let args = Self.argv(pid), let script = Self.scriptName(args) {
                row.note = "runs on " + row.name
                row.name = script
            }
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

    /// Group ids for apps with helpers, oldest pid first: a pid keeps the id it had last sample; a new one gets the
    /// first free id, never one another pid had last sample.
    static func groupIDs(_ apps: [(pid: pid_t, base: String)], previous: [pid_t: (base: String, id: String)]) -> [pid_t: (base: String, id: String)] {
        var out: [pid_t: (base: String, id: String)] = [:]
        var taken = Set(previous.values.map { $0.id })
        for a in apps { if let p = previous[a.pid], p.base == a.base { out[a.pid] = p } }
        for a in apps where out[a.pid] == nil { out[a.pid] = (a.base, uniqueID(a.base, taken: &taken)) }
        return out
    }

    /// `base`, or `base-2`, `base-3`… if that id is already taken (or is the Claude Code group's).
    static func uniqueID(_ base: String, taken: inout Set<String>) -> String {
        var id = base, n = 2
        while taken.contains(id) || id == "group:claude-code" { id = "\(base)-\(n)"; n += 1 }
        taken.insert(id)
        return id
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    // MARK: helpers

    /// When `pid` started (mach ticks), or nil if it's gone or not ours to read.
    static func startTime(_ pid: pid_t) -> UInt64? {
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        } == 0
        return ok ? ru.ri_proc_start_abstime : nil
    }

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
    static func argv0(_ pid: pid_t) -> String? { argv(pid)?.first.flatMap { $0.isEmpty ? nil : $0 } }

    /// A process's arguments, from KERN_PROCARGS2 (only works for your own processes).
    static func argv(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 8 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Layout: argc (Int32), exec path, NUL padding, argv[0], argv[1], ... (NUL-separated), then the environment.
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }
        while i < size, buf[i] == 0 { i += 1 }
        var out: [String] = []
        while out.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            out.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return out.isEmpty ? nil : out
    }

    static func isRuntime(_ name: String) -> Bool {
        name.range(of: #"^(node|python[0-9.]*|Python|ruby|bun|deno)$"#, options: .regularExpression) != nil
    }

    /// What a runtime is running, from its arguments: `node …/.bin/vite --port 5181` → "vite" (a package's own file
    /// is named after the package),
    /// `python3 -m http.server` → "http.server", `node server/index.js` → "server". nil if there's no script.
    static func scriptName(_ args: [String]) -> String? {
        var rest = args.dropFirst()
        while let a = rest.first {
            rest = rest.dropFirst()
            if a == "-m" { return rest.first }
            if ["-e", "-p", "-c", "--eval", "--print"].contains(a) { return nil }   // inline code, no script
            if ["-r", "--require", "--import", "--loader", "--experimental-loader", "-W", "-X"].contains(a) { rest = rest.dropFirst(); continue }
            if a.hasPrefix("-") { continue }
            // A bare word is a flag's value ("--conditions node") or a subcommand ("deno run"): the script is a path.
            let ext = (a as NSString).pathExtension.lowercased()
            guard a.contains("/") || ["js", "mjs", "cjs", "ts", "mts", "py", "rb"].contains(ext) else { continue }
            // Inside node_modules it's a package's own file: name it after the package (".bin/vite" → vite).
            let parts = a.split(separator: "/").map(String.init)
            if let k = parts.lastIndex(of: "node_modules"), k + 1 < parts.count {
                var pkg = parts[k + 1]
                if (pkg == ".bin" || pkg.hasPrefix("@")), k + 2 < parts.count { pkg = parts[k + 2] }
                return (pkg as NSString).deletingPathExtension
            }
            var url = URL(fileURLWithPath: a)
            var name = url.deletingPathExtension().lastPathComponent
            // index.js and friends say nothing: use the folder, skipping the usual build folders
            while ["index", "main", "cli", "dist", "bin", "src", "lib"].contains(name.lowercased()) {
                url = url.deletingLastPathComponent()
                let up = url.lastPathComponent
                guard !up.isEmpty, up != "/" else { return nil }
                name = up
            }
            return name.isEmpty ? nil : name
        }
        return nil
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

/// Which model each running Claude Code session is using, from that session's own transcript.
///
/// Every live session keeps `~/.claude/sessions/<pid>.json` (pid, sessionId, cwd, procStart = when the process
/// started, as `ps -o lstart` prints it in UTC). Its transcript is `~/.claude/projects/<encoded cwd>/<sessionId>.jsonl`,
/// and its model is the latest line there with type "assistant" that is not a subagent's ("isSidechain") and whose
/// model is not "<synthetic>". A session with no such file (or none that is really its own: a reused pid) is only
/// guessed from its folder's newest transcript when it is the one session in that folder and the transcript was
/// written after it started; otherwise its model is unknown (nil) and the pages draw a gray dot.
///
/// Everything is rechecked at most every 20 s, and a transcript that grew is only read from where the last read
/// ended, so the cost stays flat however long the transcripts get (hundreds of MB).
final class SessionModels {
    struct Session { let pid: pid_t; let cwd: String? }

    static let rescan: TimeInterval = 20
    /// How far back the first read of a transcript looks for a model before calling it unknown.
    static let firstReadLimit: UInt64 = 64 * 1024 * 1024
    /// A line longer than this is skipped unread (a pasted image, a huge tool result); a model's own line is far shorter.
    static let longestLine = 8 * 1024 * 1024

    private let root: URL
    private let processStart: (pid_t) -> Date?
    private struct Transcript { var size: UInt64; var mtime: Date; var offset: UInt64; var model: String? }
    private var transcripts: [String: Transcript] = [:]
    private var answers: [pid_t: String] = [:]
    private var scannedAt: Date?
    private var scannedPids: Set<pid_t> = []
    private var lastOwn: [pid_t: (started: Date, cwd: String, transcript: URL?)] = [:]

    /// `root` is the `.claude` folder; `processStart` says when a pid really started (both swapped out by --selftest).
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
         processStart: @escaping (pid_t) -> Date? = SessionModels.startDate) {
        self.root = root
        self.processStart = processStart
    }

    /// The model family ("Opus", "Sonnet", "Haiku", "Fable") per pid; a pid that's missing is unknown.
    func models(for sessions: [Session], now: Date = Date()) -> [pid_t: String] {
        let pids = Set(sessions.map(\.pid))
        if let t = scannedAt, pids == scannedPids, now >= t, now.timeIntervalSince(t) < Self.rescan { return answers }
        scannedAt = now
        scannedPids = pids

        // How many sessions live in each folder (the one the process is in, and the one its session file names).
        // A session file caught halfway through being rewritten keeps what it said last time (same process only).
        let owns = sessions.map { s -> (cwd: String, transcript: URL?)? in
            let started = processStart(s.pid)
            if let o = own(s, started: started) {
                if let started { lastOwn[s.pid] = (started, o.cwd, o.transcript) }
                return o
            }
            if let l = lastOwn[s.pid], l.started == started, unreadable(s.pid) { return (l.cwd, l.transcript) }
            lastOwn[s.pid] = nil
            return nil
        }
        lastOwn = lastOwn.filter { pids.contains($0.key) }
        var perFolder: [String: Int] = [:]
        for (s, o) in zip(sessions, owns) {
            for folder in Set([s.cwd, o?.cwd].compactMap { $0 }) { perFolder[folder, default: 0] += 1 }
        }

        var out: [pid_t: String] = [:]
        var used: Set<String> = []
        for (s, o) in zip(sessions, owns) {
            var file = o?.transcript
            if file == nil, let folder = o?.cwd ?? s.cwd, perFolder[folder] == 1, let started = processStart(s.pid) {
                file = newestTranscript(in: folder, since: started)
            }
            guard let file else { continue }
            used.insert(file.path)
            if let m = latest(in: file) { out[s.pid] = m }
        }
        transcripts = transcripts.filter { used.contains($0.key) }
        answers = out
        return out
    }

    // MARK: the session's own files

    /// What `sessions/<pid>.json` says, if that file is really this process's: its folder, and its transcript if
    /// that exists yet.
    private func own(_ s: Session, started: Date?) -> (cwd: String, transcript: URL?)? {
        guard let started, let d = sessionFile(s.pid),
              (d["pid"] as? NSNumber)?.int32Value == s.pid,
              let id = d["sessionId"] as? String, !id.isEmpty,
              id.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }),
              let cwd = d["cwd"] as? String, !cwd.isEmpty else { return nil }
        // A pid gets reused: the file must be from the process that has it now.
        if let text = d["procStart"] as? String {
            guard Self.sameStart(text, started) else { return nil }
        } else if let ms = (d["startedAt"] as? NSNumber)?.doubleValue {
            guard ms / 1000 >= started.timeIntervalSince1970 - 2 else { return nil }
        } else {
            return nil
        }
        for folder in [cwd, s.cwd].compactMap({ $0 }) {
            let t = root.appendingPathComponent("projects/\(Self.folderName(folder))/\(id).jsonl")
            if FileManager.default.fileExists(atPath: t.path) { return (cwd, t) }
        }
        return (cwd, nil)
    }

    private func sessionFile(_ pid: pid_t) -> [String: Any]? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("sessions/\(pid).json")), data.count < 1_000_000 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The session file is there but can't be read as JSON right now (it's being rewritten).
    private func unreadable(_ pid: pid_t) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions/\(pid).json").path) && sessionFile(pid) == nil
    }

    /// The folder's newest transcript, if it was written after `since` (so it isn't an earlier session's).
    private func newestTranscript(in folder: String, since: Date) -> URL? {
        let dir = root.appendingPathComponent("projects/\(Self.folderName(folder))")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let newest = files.filter { $0.pathExtension == "jsonl" }
            .compactMap { u -> (URL, Date)? in
                (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) }
            }
            .max { $0.1 < $1.1 }
        guard let (file, mtime) = newest, mtime >= since - 2 else { return nil }
        return file
    }

    /// How Claude Code names a folder under projects/: every character that isn't an ASCII letter or digit is "-".
    static func folderName(_ cwd: String) -> String {
        String(String.UnicodeScalarView(cwd.utf16.map { u -> Unicode.Scalar in
            let ok = (48...57).contains(u) || (65...90).contains(u) || (97...122).contains(u)
            return ok ? Unicode.Scalar(UInt8(u)) : "-"
        }))
    }

    /// When a process started, to the microsecond (works for your own processes).
    static func startDate(_ pid: pid_t) -> Date? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size, bsd.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1e6)
    }

    /// Does "Mon Nov  9 23:51:44 2026" (`ps -o lstart`, whole seconds; UTC as Claude Code writes it, local time
    /// accepted too) name the moment `started`?
    static func sameStart(_ text: String, _ started: Date) -> Bool {
        let parts = text.split(whereSeparator: { $0 == " " }).map(String.init)
        guard parts.count == 5, let day = Int(parts[2]), let year = Int(parts[4]),
              let month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].firstIndex(of: parts[1]) else { return false }
        let hms = parts[3].split(separator: ":").compactMap { Int($0) }
        guard hms.count == 3 else { return false }
        for zone in [TimeZone(identifier: "UTC")!, TimeZone.current] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = DateComponents(year: year, month: month + 1, day: day, hour: hms[0], minute: hms[1], second: hms[2])
            if let d = cal.date(from: c), abs(d.timeIntervalSince(started)) <= 2 { return true }
        }
        return false
    }

    // MARK: reading a transcript

    /// The latest model in a transcript. Unchanged file: the answer from last time. Grown file: only the new lines
    /// are read (none with a model = still the old answer). New file: read backwards from the end.
    private func latest(in file: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value, let mtime = attrs[.modificationDate] as? Date else {
            return transcripts[file.path]?.model
        }
        let known = transcripts[file.path]
        if let known, known.size == size, known.mtime == mtime { return known.model }
        let grown = known.map { size >= $0.offset } ?? false
        guard let r = Self.scan(file, from: grown ? known!.offset : 0, limit: grown ? nil : Self.firstReadLimit) else {
            return known?.model
        }
        let model = r.hit ? r.model : (grown ? known!.model : nil)
        transcripts[file.path] = Transcript(size: size, mtime: mtime, offset: r.end, model: model)
        return model
    }

    /// Reads `url` backwards from its last finished line down to byte `from` (the start of a line) and stops at the
    /// first line that carries a main-chain model. `hit` is false if there was none; `end` is where the last
    /// finished line ends (the next read starts there). nil if the file can't be read.
    static func scan(_ url: URL, from lower: UInt64, limit: UInt64?) -> (hit: Bool, model: String?, end: UInt64)? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd(), size >= lower else { return nil }
        let chunk: UInt64 = 256 * 1024
        var pos = size
        var end: UInt64?            // set at the newest newline: everything after it is a line still being written
        var tail = Data()           // the later part of a line that starts before the bytes read so far
        var tooLong = false
        while pos > lower {
            if let limit, size - pos >= limit { break }
            let start = pos - lower > chunk ? pos - chunk : lower
            guard (try? h.seek(toOffset: start)) != nil, let data = try? h.read(upToCount: Int(pos - start)),
                  data.count == Int(pos - start) else { return nil }
            var hi = data.count
            while let nl = lastNewline(in: data, before: hi) {
                if end == nil {
                    end = start + UInt64(nl) + 1
                } else if !tooLong, let model = mainChainModel(data.subdata(in: (nl + 1)..<hi) + tail) {
                    return (true, model.family, end!)
                }
                tail = Data()
                tooLong = false
                hi = nl
            }
            if end != nil {
                if start == lower {
                    if !tooLong, let model = mainChainModel(data.subdata(in: 0..<hi) + tail) { return (true, model.family, end!) }
                } else if !tooLong {
                    if tail.count + hi > longestLine { tooLong = true; tail = Data() } else { tail = data.subdata(in: 0..<hi) + tail }
                }
            }
            pos = start
        }
        return (false, nil, end ?? lower)
    }

    private static func lastNewline(in data: Data, before hi: Int) -> Int? {
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int? in
            var i = hi - 1
            while i >= 0 { if buf[i] == 0x0A { return i }; i -= 1 }
            return nil
        }
    }

    private static let assistantMark = Data("\"assistant\"".utf8), modelMark = Data("\"model\"".utf8)

    /// If `line` is a main-chain assistant message, its model family (nil inside = a model the pages don't know).
    /// nil outside = not such a line (a user or tool line, a subagent's, a synthetic one, or not JSON).
    static func mainChainModel(_ line: Data) -> (family: String?, id: String)? {
        guard line.count > 2, line.range(of: assistantMark) != nil, line.range(of: modelMark) != nil,
              let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              o["type"] as? String == "assistant", (o["isSidechain"] as? Bool) != true,
              let message = o["message"] as? [String: Any], let id = message["model"] as? String,
              !id.isEmpty, !id.hasPrefix("<") else { return nil }
        return (family(id), id)
    }

    /// "claude-fable-…" → "Fable": the families the pages have a dot color for.
    static func family(_ id: String) -> String? {
        let s = id.lowercased()
        for (k, v) in [("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku"), ("fable", "Fable")] where s.contains(k) { return v }
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
    private var currentAt: Date?
    private var timer: DispatchSourceTimer?
    /// Rates older than this (nettop stopped while the window was hidden) are stale: hand out none.
    static let maxAge: TimeInterval = 30

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            if enabled { start() } else { stop() }
        }
    }

    /// Only while enabled (or primed for --dump), and only rates from the last 30 s: right after the window comes
    /// back from a long cover-up, the kept ones are from the last run before it and could be hours old.
    func rates(now: Date = Date()) -> [pid_t: (Double, Double)]? {
        lock.lock(); defer { lock.unlock() }
        guard enabled || primed, let at = currentAt, now.timeIntervalSince(at) < Self.maxAge else { return nil }
        return current
    }

    /// For --selftest: rates as if a run had worked them out at `at`.
    func seed(_ r: [pid_t: (Double, Double)], at: Date) {
        lock.lock(); current = r; currentAt = at; primed = true; lock.unlock()
    }
    private var primed = false

    /// Runs nettop twice, `interval` apart, and blocks until the rates are known (for --dump).
    func primeBlocking(interval: TimeInterval) {
        queue.sync { run() }
        Thread.sleep(forTimeInterval: interval)
        queue.sync { run() }
        lock.lock(); primed = true; lock.unlock()
    }

    private func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 10, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.run() }
        t.resume()
        timer = t
    }

    /// Keeps the last totals: a window that's covered for a moment picks up its rates on the first run back.
    private func stop() {
        timer?.cancel(); timer = nil
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
        // Rates need the previous run; one from over 30 s ago (stopped while the window was hidden) would average
        // the whole time away, so then there are no rates until the next run.
        if let lastAt, now.timeIntervalSince(lastAt) < Self.maxAge {
            let dt = now.timeIntervalSince(lastAt)
            var r: [pid_t: (Double, Double)] = [:]
            for (pid, t) in totals {
                let p = last[pid] ?? t   // new process: no rate until the next run
                r[pid] = (Double(t.0 >= p.0 ? t.0 - p.0 : 0) / dt, Double(t.1 >= p.1 ? t.1 - p.1 : 0) / dt)
            }
            current = r
            currentAt = now
        } else {
            current = nil
            currentAt = nil
        }
        last = totals
        lastAt = now
        lock.unlock()
    }
}
