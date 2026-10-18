import AppKit
import WebKit

/// Where the pages live: Vitals.app/Contents/Resources/web, or ./Resources when run from the
/// build folder during development.
enum Pages {
    static var dir: URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("window.html").path) { return r }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }

    static func url(_ page: String) -> URL { dir.appendingPathComponent(page.hasSuffix(".html") ? page : page + ".html") }
}

/// What the pages can ask of the app (DATA.md "Pages talk back").
@MainActor
protocol PageActions: AnyObject {
    func openWindow()
    func openHelp(section: String?)
    func quitApp()
    func quitProcess(pid: Int32, name: String)
    func pageReady(_ web: WKWebView)
}

/// Receives `window.webkit.messageHandlers.vitals.postMessage({action, ...})`.
/// Held weakly by the actions target so the content controller doesn't keep the app alive.
final class PageBridge: NSObject, WKScriptMessageHandler {
    weak var target: PageActions?
    init(target: PageActions) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        MainActor.assumeIsolated {
            guard let target else { return }
            switch action {
            case "openWindow": target.openWindow()
            case "openHelp": target.openHelp(section: body["section"] as? String)
            case "quitApp": target.quitApp()
            case "quitProcess":
                if let pid = (body["pid"] as? NSNumber)?.int32Value {
                    target.quitProcess(pid: pid, name: body["name"] as? String ?? "")
                }
            case "ready":
                if let web = message.webView { target.pageReady(web) }
            default: break
            }
        }
    }
}

/// A WKWebView set up for one of the pages.
@MainActor
func makePageView(_ page: String, bridge: PageBridge, navigation: WKNavigationDelegate?) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(bridge, name: "vitals")
    // Keeps page errors in window.__vitalsErrors so `--render` can print them.
    config.userContentController.addUserScript(WKUserScript(source: """
        window.__vitalsErrors = [];
        addEventListener('error', e => __vitalsErrors.push(`${e.message} (${(e.filename || '').split('/').pop()}:${e.lineno})`));
        addEventListener('unhandledrejection', e => __vitalsErrors.push(`unhandled rejection: ${e.reason}`));
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = navigation
    web.setValue(false, forKey: "drawsBackground")
    let url = Pages.url(page)
    web.loadFileURL(url, allowingReadAccessTo: Pages.dir)
    return web
}

@MainActor
func push(_ json: String, to web: WKWebView, done: ((Error?) -> Void)? = nil) {
    // One fixed script with the JSON passed in as an argument. Inlining the JSON made WebKit compile a
    // new ~300 KB script every 2 s. `typeof` also finds a page-level `const Vitals`.
    web.callAsyncJavaScript("if (typeof Vitals !== 'undefined' && Vitals.update) Vitals.update(JSON.parse(s));",
                            arguments: ["s": json], in: nil, in: .page) { result in
        if case .failure(let error) = result { done?(error) } else { done?(nil) }
    }
}
