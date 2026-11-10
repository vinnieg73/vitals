import AppKit
import ServiceManagement

// Vitals: what Activity Monitor shows, every stat up front, in the menu bar.
//   Vitals                                                  the menu bar app
//   Vitals --dump [--bench]                                 print one snapshot (DATA.md) and exit
//   Vitals --render <page> <out.png> [light|dark] [--warm <s>]  page off screen to PNG
//                                                           (page "menubar": every menu bar icon state)
//                                                           (--warm: sample live for <s> seconds first)
//   Vitals --login-status                                   print whether Open at Login is on (read only) and exit
//   Vitals --selftest                                       check the baseline, busy-clock and sampler rules, exit 1 on a failure
//   Vitals --soak <minutes> [page]                          live page off screen; prints memory every 30 s
//   Vitals --status-log [--status-test]                     the menu bar app, printing the icon's width on every change
//                                                           (--status-test: cycle through every icon state)

/// The options Vitals knows. Anything else starting with "--" is refused: before 2026-11-10 an option the build
/// didn't know fell through and started a second menu bar copy (two icons, 2026-11-05).
enum Flags {
    static let known: Set<String> = ["--dump", "--bench", "--render", "--warm", "--login-status", "--selftest", "--soak",
                                     "--status-log", "--status-test"]

    /// The first option in `args` (after the program's own path) that Vitals doesn't know, if any. What macOS
    /// itself may pass starts with one dash and is let through.
    static func unknown(in args: [String]) -> String? {
        args.dropFirst().first { $0.hasPrefix("--") && !known.contains($0) }
    }
}

let args = CommandLine.arguments
if let bad = Flags.unknown(in: args) {
    FileHandle.standardError.write(Data("Vitals: unknown option \(bad). Known: \(Flags.known.sorted().joined(separator: " "))\n".utf8))
    exit(2)
}
if args.contains("--dump") {
    Dump.run()
}
if args.contains("--login-status") {
    print(String(describing: SMAppService.mainApp.status))
    exit(0)
}
if args.contains("--selftest") {
    SelfTest.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if let i = args.firstIndex(of: "--soak") {
        let minutes = args.count > i + 1 ? Double(args[i + 1]) ?? 6 : 6
        let page = args.count > i + 2 ? args[i + 2] : "window"
        let s = Soak(minutes: minutes, page: page)
        app.delegate = s
        withExtendedLifetime(s) { app.run() }
    } else if let i = args.firstIndex(of: "--render") {
        guard args.count > i + 2 else {
            FileHandle.standardError.write(Data("usage: Vitals --render <window|popover|help|menubar> <out.png> [light|dark] [--warm <s>]\n".utf8))
            exit(2)
        }
        let theme = args.count > i + 3 ? args[i + 3] : "light"
        if args[i + 1] == "menubar" { exit(MenuBarPreview.render(to: args[i + 2], dark: theme == "dark") ? 0 : 1) }
        let warm = args.firstIndex(of: "--warm").flatMap { args.count > $0 + 1 ? Double(args[$0 + 1]) : nil } ?? 0
        let r = Renderer(page: args[i + 1], out: args[i + 2], dark: theme == "dark", warm: warm)
        app.delegate = r
        withExtendedLifetime(r) { app.run() }
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
