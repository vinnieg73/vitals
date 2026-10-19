import AppKit

// Vitals: what Activity Monitor shows, every stat up front, in the menu bar.
//   Vitals                                                  the menu bar app
//   Vitals --dump [--scan]                                  print one snapshot (DATA.md) and exit
//   Vitals --render <page> <out.png> [light|dark] [--scan] [--warm <s>]  page off screen to PNG
//                                                           (page "menubar": every menu bar icon state)
//                                                           (--warm: sample live for <s> seconds first)
//   Vitals --soak <minutes> [page]                          live page off screen; prints memory every 30 s
// --scan waits for the first "biggest space users" scan, which otherwise is null at first.

let args = CommandLine.arguments
if args.contains("--dump") {
    Dump.run(waitForScan: args.contains("--scan"))
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
            FileHandle.standardError.write(Data("usage: Vitals --render <window|popover|help|menubar> <out.png> [light|dark] [--scan]\n".utf8))
            exit(2)
        }
        let theme = args.count > i + 3 ? args[i + 3] : "light"
        if args[i + 1] == "menubar" { exit(MenuBarPreview.render(to: args[i + 2], dark: theme == "dark") ? 0 : 1) }
        let warm = args.firstIndex(of: "--warm").flatMap { args.count > $0 + 1 ? Double(args[$0 + 1]) : nil } ?? 0
        let r = Renderer(page: args[i + 1], out: args[i + 2], dark: theme == "dark", scan: args.contains("--scan"), warm: warm)
        app.delegate = r
        withExtendedLifetime(r) { app.run() }
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
