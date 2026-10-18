import AppKit
import ServiceManagement
import WebKit

/// The menu bar app: status item, popover, main window, Help window, menus and the ⌃⌥⌘V hotkey.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate,
    NSPopoverDelegate, WKNavigationDelegate, PageActions {
    private let sampler = Sampler()
    private lazy var bridge = PageBridge(target: self)
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var popoverWeb: WKWebView?
    private var window: NSWindow?
    private var windowWeb: WKWebView?
    private var helpWindow: NSWindow?
    private var helpWeb: WKWebView?
    private var pendingHelpSection: String?
    private var hotkey: Hotkey?
    private var lastJSON: String?
    private var lastState: StatusIcon.State?
    private var lastWindowOpen = false
    /// Read on the sampler queue: only build the (large) JSON while a page is showing.
    private let live = LockedFlag()

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            StatusIcon.apply(.normal(pressure: 0), to: b)
        }
        hotkey = Hotkey { [weak self] in MainActor.assumeIsolated { self?.toggleWindow() } }

        sampler.onSnapshot = { [weak self, live] snap in
            let state = StatusIcon.state(from: snap)
            let json = live.value ? Self.encode(snap) : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.deliver(state: state, json: json) } }
        }
        sampler.setWantProcesses(false)
        sampler.start()
    }

    func applicationWillTerminate(_ note: Notification) { sampler.saveState() }

    // Closing the window must not quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow() }
        return true
    }

    nonisolated static func encode(_ snap: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: snap) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: snapshots

    private func deliver(state: StatusIcon.State, json: String?) {
        if state != lastState, let b = statusItem.button {
            StatusIcon.apply(state, to: b)
            lastState = state
        }
        guard let json else { return }
        lastJSON = json
        for web in liveViews() { push(json, to: web) }
        if popover?.isShown == true { fitPopover() }
    }

    private func liveViews() -> [WKWebView] {
        var out: [WKWebView] = []
        if popover?.isShown == true, let w = popoverWeb { out.append(w) }
        if showing(window), let w = windowWeb { out.append(w) }
        if showing(helpWindow), let w = helpWeb { out.append(w) }
        return out
    }

    /// Open and at least partly in view (not minimized, covered or on another Space).
    private func showing(_ w: NSWindow?) -> Bool {
        guard let w else { return false }
        return w.isVisible && w.occlusionState.contains(.visible)
    }

    private func updateLive() {
        let any = !liveViews().isEmpty
        let was = live.value
        live.value = any
        sampler.setWantProcesses(any)
        let windowOpen = showing(window)
        if windowOpen != lastWindowOpen { sampler.setWindowOpen(windowOpen); lastWindowOpen = windowOpen }
        if !any { lastJSON = nil }
        if any && !was { sampler.kick() }   // fresh rows now rather than in up to 2 s
    }

    func pageReady(_ web: WKWebView) {
        if let json = lastJSON ?? sampler.latestSnapshot().flatMap(Self.encode) { push(json, to: web) }
        if web === popoverWeb { fitPopover() }
        if web === helpWeb, let s = pendingHelpSection {
            pendingHelpSection = nil
            scrollHelp(to: s)
        }
    }

    // MARK: status item and popover

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover?.performClose(nil)
            statusItem.menu = statusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if let p = popover, p.isShown { p.performClose(nil); return }
        if popover == nil {
            let web = makePageView("popover", bridge: bridge, navigation: self)
            let vc = NSViewController()
            vc.view = web
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true
            p.contentViewController = vc
            p.contentSize = NSSize(width: 356, height: 560)
            p.delegate = self
            popover = p
            popoverWeb = web
        }
        guard let p = popover, let b = statusItem.button else { return }
        NSApp.activate()
        p.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        p.contentViewController?.view.window?.makeKey()
        updateLive()
        if let w = popoverWeb, let json = lastJSON ?? sampler.latestSnapshot().flatMap(Self.encode) {
            push(json, to: w)
            fitPopover()
        }
    }

    func popoverDidClose(_ notification: Notification) { updateLive() }

    /// The page posts no size, so measure where its content ends.
    private func fitPopover() {
        let js = """
        (() => { const b = document.body; if (!b) return 0; let h = 0;
          for (const el of b.children) { const r = el.getBoundingClientRect(); if (r.height > 0) h = Math.max(h, r.bottom + scrollY); }
          const cs = getComputedStyle(b); return Math.ceil(h + parseFloat(cs.paddingBottom || 0) + parseFloat(cs.marginBottom || 0)); })()
        """
        popoverWeb?.evaluateJavaScript(js) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.popover, let h = (result as? NSNumber)?.doubleValue, h > 100 else { return }
                let height = min(820, max(200, h))
                if abs(p.contentSize.height - height) > 1 { p.contentSize = NSSize(width: 356, height: height) }
            }
        }
    }

    // MARK: main window

    @objc func toggleWindow() {
        if let w = window, w.isVisible, NSApp.isActive, w.isKeyWindow { w.performClose(nil) } else { openWindow() }
    }

    @objc func openWindow() {
        popover?.performClose(nil)
        if window == nil {
            let web = makePageView("window", bridge: bridge, navigation: self)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 880),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Vitals"
            w.minSize = NSSize(width: 1100, height: 760)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = web
            w.collectionBehavior = [.fullScreenPrimary, .managed]
            if !w.setFrameUsingName("VitalsMain") { w.center() }
            w.setFrameAutosaveName("VitalsMain")
            window = w
            windowWeb = web
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        updateLive()
    }

    /// Hidden windows get no updates; when one comes back into view it gets the latest numbers at once.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === window || w === helpWindow else { return }
        updateLive()   // also takes a fresh sample if nothing was showing
        if showing(w), let web = w === window ? windowWeb : helpWeb, let json = lastJSON { push(json, to: web) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === window {
            // Drop the page so its web process doesn't sit in memory while only the menu is used.
            w.contentView = nil
            windowWeb = nil
            window = nil
        } else if w === helpWindow {
            w.contentView = nil
            helpWeb = nil
            helpWindow = nil
        }
        DispatchQueue.main.async { MainActor.assumeIsolated {
            self.updateLive()
            if self.window == nil && self.helpWindow == nil { NSApp.setActivationPolicy(.accessory) }
        } }
    }

    // MARK: help

    @objc private func showHelp() { openHelp(section: nil) }

    func openHelp(section: String?) {
        popover?.performClose(nil)
        if helpWindow == nil {
            let web = makePageView("help", bridge: bridge, navigation: self)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 860),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Vitals Help"
            w.minSize = NSSize(width: 520, height: 480)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = web
            if !w.setFrameUsingName("VitalsHelp") { w.center() }
            w.setFrameAutosaveName("VitalsHelp")
            helpWindow = w
            helpWeb = web
            pendingHelpSection = section
        } else if let section {
            scrollHelp(to: section)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        helpWindow?.makeKeyAndOrderFront(nil)
        updateLive()
    }

    private func scrollHelp(to section: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [section]), let arr = String(data: data, encoding: .utf8) else { return }
        helpWeb?.evaluateJavaScript("typeof Vitals !== 'undefined' && Vitals.scrollTo && Vitals.scrollTo(\(arr)[0])")
    }

    // MARK: page actions

    func quitApp() { NSApp.terminate(nil) }

    /// The page has already asked "Quit X?". Polite only: terminate / SIGTERM, never SIGKILL,
    /// and never for root's or other users' processes.
    func quitProcess(pid: Int32, name: String) {
        guard pid > 1, pid != getpid() else { return }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size, bsd.pbi_uid != 0, bsd.pbi_uid == getuid() else {
            NSSound.beep()
            return
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        } else {
            kill(pid, SIGTERM)
        }
    }

    // Links: help.html opens the Help window, window.html the main window, web links the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        guard url.isFileURL else { return .allow }
        let own = webView === helpWeb ? "help.html" : webView === windowWeb ? "window.html" : webView === popoverWeb ? "popover.html" : nil
        let page = url.lastPathComponent
        if page == own || own == nil { return .allow }   // its own page (first load, #anchors, reload)
        if page == "help.html" { openHelp(section: url.fragment); return .cancel }
        if page == "window.html" { openWindow(); return .cancel }
        return .cancel
    }

    // MARK: menus

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About Vitals", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Open Vitals", action: #selector(openWindow), keyEquivalent: "o")
        app.addItem(withTitle: "Vitals Help", action: #selector(showHelp), keyEquivalent: "?")
        app.addItem(.separator())
        app.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Vitals", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Vitals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        // Edit menu so ⌘C / ⌘V / ⌘A work in the process search field.
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Vitals Help", action: #selector(showHelp), keyEquivalent: "?")
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    /// Right-click on the menu bar item.
    private func statusMenu() -> NSMenu {
        let m = NSMenu()
        // Shows the global hotkey; ⌘O only works while Vitals is active.
        let open = m.addItem(withTitle: "Open Vitals", action: #selector(openWindow), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.control, .option, .command]
        open.target = self
        m.addItem(withTitle: "Vitals Help", action: #selector(showHelp), keyEquivalent: "?").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Vitals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleLogin) { item.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        return true
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Open at Login"
            alert.runModal()
        }
    }
}

/// A Bool shared between the main thread and the sampler queue.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}
