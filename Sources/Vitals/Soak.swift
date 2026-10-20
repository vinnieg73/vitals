import AppKit
import WebKit

/// `Vitals --soak <minutes> [page]`
///
/// Leak check: a page in a borderless window parked off screen (like --render), fed a live snapshot
/// every 2 s like the app, printing Vitals' and the page's web process memory every 30 s.
/// Caveat: WebKit may skip painting a window that's off screen, so drawing costs are understated.
@MainActor
final class Soak: NSObject, NSApplicationDelegate, PageActions, WKNavigationDelegate {
    private let minutes: Double
    private let page: String
    private let sampler = Sampler()
    private lazy var bridge = PageBridge(target: self)
    private var window: NSWindow?
    private var web: WKWebView?
    private var ready = false
    private var pushes = 0
    private let start = Date()

    init(minutes: Double, page: String) {
        self.minutes = minutes
        self.page = page.replacingOccurrences(of: ".html", with: "")
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let web = makePageView(page, bridge: bridge, navigation: self)
        let w = NSWindow(contentRect: NSRect(x: -40000, y: -40000, width: 1280, height: 880),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isExcludedFromWindowsMenu = true
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        w.contentView = web
        w.setFrameOrigin(NSPoint(x: -40000, y: -40000))
        w.orderBack(nil)
        window = w
        self.web = web

        sampler.setWantProcesses(true)
        sampler.setWantNetwork(true)
        sampler.onSnapshot = { [weak self] snap in
            let json = AppDelegate.encode(snap)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.ready, let json, let web = self.web else { return }
                self.pushes += 1
                push(json, to: web)
            } }
        }
        sampler.start()
        print("soak: \(page) page, \(Int(minutes)) min, memory = phys_footprint (Activity Monitor's Memory column)")
        tick()
    }

    private func tick() {
        let t = Date().timeIntervalSince(start)
        let webPid = (web?.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value ?? 0
        func mb(_ pid: Int32) -> String { Self.footprint(pid).map { String(format: "%6.1f MB", Double($0) / 1_048_576) } ?? "     –   " }
        print(String(format: "t=%4.0fs", t) + "  app \(mb(getpid()))  page \(mb(webPid))  (pid \(webPid), \(pushes) updates)")
        fflush(stdout)
        if t >= minutes * 60 { exit(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.tick() }
    }

    static func footprint(_ pid: Int32) -> UInt64? {
        guard pid > 0 else { return nil }
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        } == 0
        return ok ? ru.ri_phys_footprint : nil
    }

    func pageReady(_ web: WKWebView) { ready = true }
    func openWindow() {}
    func openHelp(section: String?) {}
    func quitApp() {}
    func quitProcess(pid: Int32, name: String, started: UInt64?) {}
}
