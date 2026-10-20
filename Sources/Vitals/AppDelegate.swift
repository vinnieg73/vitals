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
    private var popoverDrop: DispatchWorkItem?
    private var restReasons: Set<String> = []
    private var window: NSWindow?
    private var windowWeb: WKWebView?
    private var helpWindow: NSWindow?
    private var helpWeb: WKWebView?
    private var pendingHelpSection: String?
    private var hotkey: Hotkey?
    private var lastJSON: String?
    private var lastState: StatusIcon.State?
    private var lastWindowOpen = false
    private let judge = StatusIcon.Judge()
    private var appearanceWatch: NSKeyValueObservation?
    private var barLook: NSAppearance.Name?

    /// Light or dark, as the status item's button sees the menu bar.
    private static func look(_ b: NSStatusBarButton) -> NSAppearance.Name? {
        b.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    }
    /// `--status-log`: print the item's length and button width on every change (for checking it never moves).
    /// `--status-test`: cycle through test states instead of the real one.
    private let statusLog = CommandLine.arguments.contains("--status-log")
    private let statusTest = CommandLine.arguments.contains("--status-test")
    /// Read on the sampler queue: only build the (large) JSON while a page is showing.
    private let live = LockedFlag()

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Vitals" // so a ⌘-drag to a new spot sticks across relaunches
        if let b = statusItem.button {
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // One width for every state, so the menu bar never re-lays out.
            statusItem.length = StatusIcon.fixedLength(for: b)
            StatusIcon.apply(StatusIcon.State(cpu: 0, gpu: 0, ram: 0), to: b)
            logStatus("launch")
            // A strained icon isn't a template, so its colors are drawn for one appearance: redraw when the
            // menu bar flips between light and dark. Only on a real flip: setting the image re-fires this
            // observer, and redrawing on every call looped forever (~95% of a core, 2026-10-19).
            barLook = Self.look(b)
            appearanceWatch = b.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self, let b = self.statusItem.button else { return }
                    let look = Self.look(b)
                    let redraw = look != self.barLook && self.lastState.map { !$0.followsMenuBar } == true
                    self.logStatus("appearance \(look?.rawValue ?? "?")\(look == self.barLook ? " (same)" : "")\(redraw ? ", redrawn" : "")")
                    guard look != self.barLook else { return }
                    self.barLook = look
                    if redraw, let state = self.lastState { StatusIcon.apply(state, to: b) }
                } }
            }
        }
        hotkey = Hotkey { [weak self] in MainActor.assumeIsolated { self?.toggleWindow() } }

        let drawn = DrawnState()
        sampler.onSnapshot = { [weak self, live, judge, statusTest, drawn] snap in
            var state = judge.state(from: snap)
            if statusTest { state = Self.testState() }
            // At this size a needle that moved under 2% looks the same (1% is a third of a pixel at its tip): no redraw.
            let redraw = drawn.state.map { !state.looksLike($0) } ?? true
            if redraw { drawn.state = state }
            let json = live.value ? Self.encode(snap) : nil
            // Nothing to draw and no page to feed: don't wake the main thread at all.
            guard redraw || json != nil else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.deliver(state: redraw ? state : nil, json: json) } }
        }
        sampler.setWantProcesses(false)
        sampler.start()
        watchForRest()
    }

    /// Nobody can see the menu bar while the screens sleep (also lid closed with the Mac kept awake), the screen
    /// is locked, or another user's session is in front: the sampler slows to once a minute until all of that ends.
    private func watchForRest() {
        let ws = NSWorkspace.shared.notificationCenter
        let rules: [(NSNotification.Name, String, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, "screens", true), (NSWorkspace.screensDidWakeNotification, "screens", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true), (NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
        ]
        for (name, reason, on) in rules {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setRest(reason, on) }
            }
        }
        let dist = DistributedNotificationCenter.default()
        for (name, on) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            dist.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setRest("locked", on) }
            }
        }
    }

    private func setRest(_ reason: String, _ on: Bool) {
        if on { restReasons.insert(reason) } else { restReasons.remove(reason) }
        logStatus("rest \(reason) \(on ? "on" : "off") → \(restReasons.isEmpty ? "every 2 s" : "once a minute")")
        sampler.setResting(!restReasons.isEmpty)
    }

    func applicationWillTerminate(_ note: Notification) { sampler.saveState() }

    // Closing the window must not quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow() }
        return true
    }

    private func logStatus(_ what: String) {
        guard statusLog, let b = statusItem.button else { return }
        let f = b.window?.frame ?? .zero // in screen coordinates
        print(String(format: "%@  length %.1f  button %.1f  fits %.1f  window x %.1f w %.1f  %@", ISO8601DateFormatter().string(from: Date()),
                     statusItem.length, b.frame.width, b.fittingSize.width, f.minX, f.width, what))
        fflush(stdout)
    }

    private nonisolated static let testStates: [StatusIcon.State] = StatusIcon.allStates
    private nonisolated(unsafe) static var testIndex = 0
    private nonisolated static func testState() -> StatusIcon.State {
        testIndex += 1
        return testStates[testIndex % testStates.count]
    }

    nonisolated static func encode(_ snap: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: snap) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: snapshots

    private func deliver(state: StatusIcon.State?, json: String?) {
        if let state, state != lastState, let b = statusItem.button {
            StatusIcon.apply(state, to: b)
            lastState = state
            logStatus("\(state)")
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
        // Only a snapshot taken while a page was showing: an older one has stale process rows. If there's none
        // yet, the fresh sample asked for on open arrives in a moment.
        if let json = lastJSON { push(json, to: web) }
        if web === popoverWeb { fitPopover() }
        if web === helpWeb, let s = pendingHelpSection {
            pendingHelpSection = nil
            scrollHelp(to: s)
        }
    }

    // MARK: status item and popover

    @objc private func statusClicked() {
        // Right-click or ⌃-click (the trackpad habit) opens the menu.
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
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
        popoverDrop?.cancel()
        popoverDrop = nil
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
        if let w = popoverWeb, let json = lastJSON {
            push(json, to: w)
            fitPopover()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        updateLive()
        // Like the windows, don't keep the page's web process in memory while only the menu bar is used.
        // A minute's grace keeps a quick reopen instant.
        popoverDrop?.cancel()
        let drop = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.dropPopover() } }
        popoverDrop = drop
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: drop)
    }

    private func dropPopover() {
        popoverDrop = nil
        guard let p = popover, !p.isShown else { return }
        p.contentViewController = nil
        popover = nil
        popoverWeb = nil
        logStatus("popover page released")
    }

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
    func quitProcess(pid: Int32, name: String, started: UInt64?) {
        guard pid > 1, pid != getpid() else { return }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size, bsd.pbi_uid != 0, bsd.pbi_uid == getuid() else {
            NSSound.beep()
            return
        }
        // The sheet can sit open a while: if X quit and macOS gave its pid to a new process, leave that one alone.
        guard Self.sameProcess(pid: pid, started: started) else {
            NSSound.beep()
            return
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        } else {
            kill(pid, SIGTERM)
        }
    }

    /// True only if `pid` is still the process that started at `started`.
    nonisolated static func sameProcess(pid: Int32, started: UInt64?) -> Bool {
        guard let started else { return false }
        return ProcessSampler.startTime(pid) == started
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

    /// Right-click or ⌃-click on the menu bar item.
    private func statusMenu() -> NSMenu {
        let m = NSMenu()
        // Shows the global hotkey (⌘O only works while Vitals is active), or says another app has it.
        let shortcut = hotkey?.registered == true
        let open = m.addItem(withTitle: "Open Vitals", action: #selector(openWindow), keyEquivalent: shortcut ? "v" : "")
        if shortcut { open.keyEquivalentModifierMask = [.control, .option, .command] }
        open.target = self
        if !shortcut { m.addItem(withTitle: "⌃⌥⌘V is taken by another app", action: nil, keyEquivalent: "") }
        m.addItem(withTitle: "Vitals Help", action: #selector(showHelp), keyEquivalent: "?").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Vitals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleLogin) {
            let (title, state) = Self.loginItem(SMAppService.mainApp.status)
            item.title = title
            item.state = state
        }
        return true
    }

    /// "Open at Login" as the menu shows it. Turned on but not yet allowed in System Settings shows as a dash.
    nonisolated static func loginItem(_ status: SMAppService.Status) -> (String, NSControl.StateValue) {
        switch status {
        case .enabled: return ("Open at Login", .on)
        case .requiresApproval: return ("Open at Login (allow in Settings…)", .mixed)
        default: return ("Open at Login", .off)
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        // Waiting on the user: the switch is in System Settings → General → Login Items.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); return }
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); return }
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Open at Login"
            alert.runModal()
            return
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

/// The icon state last sent to be drawn. Used only on the sampler queue.
final class DrawnState: @unchecked Sendable {
    var state: StatusIcon.State?
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
