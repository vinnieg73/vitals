import AppKit
import WebKit

/// `Vitals --render <page> <out.png> [light|dark] [--warm <seconds>]`
///
/// Loads one page in a borderless window parked far off screen (nothing appears on the display,
/// no Dock icon, no menu bar item), feeds it a live snapshot, waits 1.5 s, saves a 2x PNG and exits.
@MainActor
final class Renderer: NSObject, NSApplicationDelegate, PageActions, WKNavigationDelegate {
    private let page: String
    private let out: URL
    private let dark: Bool
    private let warm: Double
    private let sampler = Sampler()
    private lazy var bridge = PageBridge(target: self)
    private var window: NSWindow?
    private var web: WKWebView?
    private var json: String?
    private var shot = false

    /// `warm`: keep sampling every 2 s for this long first, so the live charts have real history.
    init(page: String, out: String, dark: Bool, warm: Double = 0) {
        self.warm = warm
        self.page = page.replacingOccurrences(of: ".html", with: "")
        self.out = URL(fileURLWithPath: out)
        self.dark = dark
    }

    private var size: NSSize {
        switch page {
        case "popover": return NSSize(width: 356, height: 900)
        case "help": return NSSize(width: 760, height: 860)
        default: return NSSize(width: 1280, height: 880)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        // Give up after 30 s (plus the warm-up) whatever happens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30 + warm) {
            FileHandle.standardError.write(Data("render timed out\n".utf8)); exit(1)
        }
        let sampler = self.sampler, warm = self.warm
        DispatchQueue.global(qos: .userInitiated).async {
            _ = sampler.sampleNow()
            sampler.processes.primeNetwork(interval: 2)
            // The last warm-up sample is the one sent, 2 s after the previous one, so its rates are real.
            let start = Date()
            while Date().timeIntervalSince(start) + 2 < warm {
                Thread.sleep(forTimeInterval: 2)
                _ = sampler.sampleNow()
            }
            if warm > 0 { Thread.sleep(forTimeInterval: 2) }
            let json = AppDelegate.encode(sampler.sampleNow())
            DispatchQueue.main.async { MainActor.assumeIsolated { self.load(json: json) } }
        }
    }

    private func load(json: String?) {
        self.json = json
        let web = makePageView(page, bridge: bridge, navigation: self)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -40000, y: -40000), size: size),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = appearance
        web.appearance = appearance
        w.isExcludedFromWindowsMenu = true
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        w.contentView = web
        w.setFrameOrigin(NSPoint(x: -40000, y: -40000))
        w.orderBack(nil)
        window = w
        self.web = web
        // Pages that never post "ready" still get rendered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if let web = self.web { self.pageReady(web) } }
    }

    func pageReady(_ web: WKWebView) {
        guard !shot else { return }
        shot = true
        if let json {
            push(json, to: web) { error in
                if let error { FileHandle.standardError.write(Data("page error in Vitals.update: \(error)\n".utf8)) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.reportErrors(); self.fitAndShoot() }
    }

    private func reportErrors() {
        web?.evaluateJavaScript("(window.__vitalsErrors || []).join('\\n')") { result, _ in
            if let text = result as? String, !text.isEmpty {
                FileHandle.standardError.write(Data("page errors:\n\(text)\n".utf8))
            }
        }
    }

    private func fitAndShoot() {
        guard page == "popover" else { shoot(); return }
        let js = """
        (() => { const b = document.body; let h = 0;
          for (const el of b.children) { const r = el.getBoundingClientRect(); if (r.height > 0) h = Math.max(h, r.bottom + scrollY); }
          const cs = getComputedStyle(b); return Math.ceil(h + parseFloat(cs.paddingBottom || 0) + parseFloat(cs.marginBottom || 0)); })()
        """
        web?.evaluateJavaScript(js) { result, _ in
            MainActor.assumeIsolated {
                if let h = (result as? NSNumber)?.doubleValue, h > 100, let w = self.window {
                    w.setContentSize(NSSize(width: 356, height: min(900, h)))
                    w.setFrameOrigin(NSPoint(x: -40000, y: -40000))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.shoot() }
            }
        }
    }

    private func shoot() {
        guard let web, let window else { exit(1) }
        let pts = web.bounds.size
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        config.snapshotWidth = NSNumber(value: Double(pts.width) * 2)
        let appearance = window.effectiveAppearance
        web.takeSnapshot(with: config) { image, error in
            MainActor.assumeIsolated {
                guard let image else {
                    FileHandle.standardError.write(Data("snapshot failed: \(error?.localizedDescription ?? "?")\n".utf8)); exit(1)
                }
                let pw = Int(pts.width * 2), ph = Int(pts.height * 2)
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
                rep.size = pts
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    NSRect(origin: .zero, size: pts).fill()
                }
                image.draw(in: NSRect(origin: .zero, size: pts))
                NSGraphicsContext.restoreGraphicsState()
                guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
                do {
                    try FileManager.default.createDirectory(at: self.out.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: self.out)
                } catch {
                    FileHandle.standardError.write(Data("couldn't write \(self.out.path): \(error)\n".utf8)); exit(1)
                }
                print("Rendered \(self.page) (\(self.dark ? "dark" : "light")) to \(self.out.path)")
                window.orderOut(nil)
                exit(0)
            }
        }
    }

    // Page actions do nothing while rendering.
    func openWindow() {}
    func openHelp(section: String?) {}
    func quitApp() {}
    func quitProcess(pid: Int32, name: String) {}
}
