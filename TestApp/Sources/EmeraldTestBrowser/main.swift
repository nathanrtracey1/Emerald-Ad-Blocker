/// Emerald Ad Blocker — Test Browser
///
/// Build & run (requires only Swift CLI tools, not Xcode IDE):
///
///   cd TestApp && swift run
///
/// Web Inspector:
///   1. In Safari: Settings → Advanced → "Show features for web developers" (or
///      "Show Develop menu in menu bar" on older macOS)
///   2. In Safari's Develop menu → [your Mac name] → Emerald Ad Blocker
///   3. Full Web Inspector including Console, Network, Elements tabs.

import AppKit
import WebKit

// ---------------------------------------------------------------------------
// Locate project root (output/ dir lives there)
// ---------------------------------------------------------------------------

func findProjectRoot() -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for candidate in [cwd, cwd.deletingLastPathComponent()] {
        if FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("output/adblock.json").path
        ) { return candidate }
    }
    return cwd
}

let ROOT = findProjectRoot()

// ---------------------------------------------------------------------------
// AppDelegate
// ---------------------------------------------------------------------------

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
        windowController = BrowserWindowController()
        windowController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func buildMenu() {
        let bar = NSMenu()

        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu(title: "App")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        let navItem = NSMenuItem(title: "Navigation", action: nil, keyEquivalent: "")
        bar.addItem(navItem)
        let navMenu = NSMenu(title: "Navigation")
        navItem.submenu = navMenu
        navMenu.addItem(withTitle: "Reload",           action: #selector(BrowserWindowController.reload),   keyEquivalent: "r")
        navMenu.addItem(withTitle: "Go Home (Tests)",  action: #selector(BrowserWindowController.goHome),   keyEquivalent: "h")
        navMenu.addItem(withTitle: "Back",             action: #selector(BrowserWindowController.goBack),   keyEquivalent: "[")
        navMenu.addItem(withTitle: "Forward",          action: #selector(BrowserWindowController.goForward),keyEquivalent: "]")

        NSApp.mainMenu = bar
    }
}

// ---------------------------------------------------------------------------
// Browser window
// ---------------------------------------------------------------------------

class BrowserWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {

    private let wkConfig  = WKWebViewConfiguration()
    private var webView:   WKWebView!
    private var urlField:  NSTextField!
    private var statusBar: NSTextField!
    private var spinner:   NSProgressIndicator!

    private var rulesCompiled = 0
    private var rulesFailed   = 0
    private var pendingCompile = 0

    // domain → [filter list display names], loaded from output/block_sources.json
    private var blockSources: [String: [String]] = [:]

    // -----------------------------------------------------------------------
    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Emerald Ad Blocker — Test Browser"
        win.center()
        super.init(window: win)
        buildUI()
        loadAdblocker()
    }
    required init?(coder: NSCoder) { fatalError() }

    // -----------------------------------------------------------------------
    // MARK: UI
    // -----------------------------------------------------------------------

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(toolbar)

        let backBtn    = navBtn("◀", #selector(goBack))
        let fwdBtn     = navBtn("▶", #selector(goForward))
        let reloadBtn  = navBtn("↺",  #selector(reload))
        let homeBtn    = navBtn("⌂",  #selector(goHome))

        urlField = NSTextField()
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.font = .systemFont(ofSize: 13)
        urlField.placeholderString = "https://…  (YouTube, Spotify, GitHub, etc.)"
        urlField.target = self
        urlField.action = #selector(navigate)

        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning; spinner.isIndeterminate = true
        spinner.isHidden = true; spinner.controlSize = .small

        for v: NSView in [backBtn, fwdBtn, reloadBtn, homeBtn, urlField, spinner] {
            toolbar.addSubview(v)
        }

        let sep = NSBox(); sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator

        // WKWebView — Web Inspector enabled via isInspectable
        webView = WKWebView(frame: .zero, configuration: wkConfig)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        // Identify as Safari so sites (e.g. Google) serve their modern UI.
        // Without Version/X.X Safari/... some sites fall back to basic-HTML mode.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        if #available(macOS 13.3, *) {
            webView.isInspectable = true   // enables Safari Develop → [Mac] → Emerald
        }

        statusBar = NSTextField()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.isEditable = false; statusBar.isBezeled = false
        statusBar.backgroundColor = .clear
        statusBar.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusBar.textColor = .secondaryLabelColor
        statusBar.stringValue = "  Loading ad-blocking rules…"

        for v: NSView in [toolbar, sep, webView, statusBar] {
            cv.addSubview(v)
        }

        let m: CGFloat = 8
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: cv.topAnchor, constant: m),
            toolbar.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: m),
            toolbar.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -m),
            toolbar.heightAnchor.constraint(equalToConstant: 30),

            backBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            backBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 28),

            fwdBtn.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 4),
            fwdBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fwdBtn.widthAnchor.constraint(equalToConstant: 28),

            reloadBtn.leadingAnchor.constraint(equalTo: fwdBtn.trailingAnchor, constant: 4),
            reloadBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            reloadBtn.widthAnchor.constraint(equalToConstant: 28),

            homeBtn.leadingAnchor.constraint(equalTo: reloadBtn.trailingAnchor, constant: 4),
            homeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            homeBtn.widthAnchor.constraint(equalToConstant: 28),

            spinner.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -4),
            spinner.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            urlField.leadingAnchor.constraint(equalTo: homeBtn.trailingAnchor, constant: 8),
            urlField.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),
            urlField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            sep.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: m),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            webView.topAnchor.constraint(equalTo: sep.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -4),

            statusBar.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4),
            statusBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func navBtn(_ t: String, _ a: Selector) -> NSButton {
        let b = NSButton(title: t, target: self, action: a)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 13)
        return b
    }

    // -----------------------------------------------------------------------
    // MARK: Adblocker loading
    // -----------------------------------------------------------------------

    private func loadAdblocker() {
        // Load domain → [filter list] mapping for blocked URL notifications
        let blockSourcesPath = ROOT.appendingPathComponent("output/block_sources.json")
        if let data = try? Data(contentsOf: blockSourcesPath),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
            blockSources = dict
            print("[TestBrowser] Loaded block_sources.json (\(blockSources.count) domains)")
        } else {
            print("[TestBrowser] ⚠ Could not load block_sources.json")
        }

        let ucc = wkConfig.userContentController

        // ── WKUserScripts (document_start, same order as Emerald) ─────────────
        let scripts = ["scriptlets.js", "websocket_block.js", "cosmetic.js", "ytadblock.js"]
        var injectedKB = 0
        for name in scripts {
            let path = ROOT.appendingPathComponent("output/\(name)")
            guard let src = try? String(contentsOf: path, encoding: .utf8) else {
                print("[TestBrowser] ⚠ Missing: \(name)")
                continue
            }
            // All scripts run in main frame only. WebKit tries to inject subframe
            // scripts into YouTube's sandboxed about:blank iframes and the sandbox
            // blocks execution before JS runs, producing console errors. Network
            // blocking (WKContentRuleList) covers subframe requests independently.
            let mainOnly = true
            let us = WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: mainOnly)
            ucc.addUserScript(us)
            injectedKB += src.utf8.count / 1024
        }
        print("[TestBrowser] WKUserScripts injected (\(injectedKB) KB total)")

        // ── WKContentRuleList compilation ──────────────────────────────────────
        let ruleSets: [(String, String)] = [
            ("emerald.adblock",  "output/adblock.json"),
            ("emerald.trackers", "output/trackers.json"),
        ]
        pendingCompile = ruleSets.count
        var totalRules = 0
        var statsEntries: [(String, Int, Int)] = []

        for (id, rel) in ruleSets {
            let file = ROOT.appendingPathComponent(rel)
            guard let json = try? String(contentsOf: file, encoding: .utf8) else {
                print("[TestBrowser] ⚠ Cannot read \(rel)")
                rulesFailed += 1
                pendingCompile -= 1
                if pendingCompile == 0 { compileDone(stats: statsEntries, total: totalRules) }
                continue
            }
            if let arr = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] {
                let kb = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
                statsEntries.append((id, arr.count, kb / 1024))
                totalRules += arr.count
            }
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { [weak self] list, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let e = error {
                        print("[TestBrowser] ✗ \(id): \(e.localizedDescription)")
                        self.rulesFailed += 1
                    } else if let list {
                        self.wkConfig.userContentController.add(list)
                        self.rulesCompiled += 1
                        print("[TestBrowser] ✓ \(id)")
                    }
                    self.pendingCompile -= 1
                    if self.pendingCompile == 0 { self.compileDone(stats: statsEntries, total: totalRules) }
                }
            }
        }
    }

    private func compileDone(stats: [(String, Int, Int)], total: Int) {
        // Inject stats for the test page
        let statsBody = stats.map { "\"\($0.0)\": {\"count\": \($0.1), \"kb\": \($0.2)}" }.joined(separator: ", ")
        let statsJS = "window.__EMERALD_RULE_STATS__ = { \(statsBody) };"
        wkConfig.userContentController.addUserScript(
            WKUserScript(source: statsJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let fmt = NumberFormatter(); fmt.numberStyle = .decimal
        let n = fmt.string(from: NSNumber(value: total)) ?? "\(total)"

        if rulesFailed == 0 {
            statusBar.stringValue = "  ✅ \(rulesCompiled)/2 rule lists active · \(n) rules · Ad blocking ON  |  Web Inspector: Safari → Develop → [Mac] → Emerald Ad Blocker"
        } else {
            statusBar.stringValue = "  ⚠ \(rulesCompiled)/2 compiled (\(rulesFailed) failed) — see terminal"
        }
        goHome()
    }

    // -----------------------------------------------------------------------
    // MARK: Navigation
    // -----------------------------------------------------------------------

    @objc func navigate() {
        var s = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        webView.load(URLRequest(url: url))
    }

    @objc func goBack()    { webView.goBack() }
    @objc func goForward() { webView.goForward() }
    @objc func reload()    { webView.reload() }

    @objc func goHome() {
        let page = ROOT.appendingPathComponent("TestApp/TestPage/index.html")
        if FileManager.default.fileExists(atPath: page.path) {
            webView.loadFileURL(page, allowingReadAccessTo: ROOT)
            urlField.stringValue = "  Test Suite"
        } else {
            webView.load(URLRequest(url: URL(string: "https://example.com")!))
        }
    }

    // -----------------------------------------------------------------------
    // MARK: Block-page helpers
    // -----------------------------------------------------------------------

    /// Check a hostname (and its parent domains) against the block-sources map.
    private func findBlockLists(for host: String) -> [String]? {
        var parts = host.lowercased().components(separatedBy: ".")
        while parts.count >= 2 {
            let domain = parts.joined(separator: ".")
            if let lists = blockSources[domain] { return lists }
            parts.removeFirst()
        }
        return nil
    }

    private func showBlockPage(url: URL, lists: [String]) {
        let urlString = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let listItems = lists.map { "<li>\($0)</li>" }.joined(separator: "\n            ")
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width">
        <title>Page Blocked — Emerald</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
             background:#1a1a2e;color:#eee;display:flex;align-items:center;
             justify-content:center;min-height:100vh;padding:2rem}
        .card{background:#16213e;border:1px solid #0f3460;border-radius:12px;
              max-width:620px;width:100%;padding:2.5rem;text-align:center}
        .shield{font-size:3.5rem;margin-bottom:1rem}
        h1{font-size:1.4rem;color:#e94560;margin-bottom:1rem}
        .blocked-url{font-family:monospace;font-size:.85rem;background:#0f3460;
                     padding:.75rem 1rem;border-radius:6px;word-break:break-all;
                     color:#a8d8ea;margin-bottom:1.5rem;text-align:left}
        p{color:#aaa;margin-bottom:1rem;font-size:.9rem}
        ul{list-style:none;margin-bottom:1.5rem}
        ul li{background:#0f3460;border-left:3px solid #e94560;padding:.5rem 1rem;
              margin:.35rem 0;text-align:left;border-radius:0 6px 6px 0;
              font-size:.88rem;color:#ccc}
        .brand{font-size:.75rem;color:#445;margin-top:1.5rem}
        </style>
        </head>
        <body>
        <div class="card">
          <div class="shield">🛡</div>
          <h1>Page Blocked by Emerald</h1>
          <div class="blocked-url">\(urlString)</div>
          <p>Emerald Ad Blocker has prevented this page from loading because it appears in:</p>
          <ul>
            \(listItems)
          </ul>
          <div class="brand">Emerald Ad Blocker</div>
        </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        urlField.stringValue = url.absoluteString
    }

    // -----------------------------------------------------------------------
    // MARK: WKNavigationDelegate
    // -----------------------------------------------------------------------

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Intercept main-frame navigations to known blocked domains and show
        // a uBlock Origin-style block page instead of a generic error.
        guard navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url,
              let host = url.host,
              let lists = findBlockLists(for: host) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        showBlockPage(url: url, lists: lists)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        spinner.isHidden = false; spinner.startAnimation(nil)
    }
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        spinner.isHidden = true; spinner.stopAnimation(nil)
        if let url = webView.url, url.scheme != "file" { urlField.stringValue = url.absoluteString }
    }
    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError e: Error) {
        spinner.isHidden = true; spinner.stopAnimation(nil)
        statusBar.stringValue = "  ✗ \(e.localizedDescription)"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError e: Error) {
        spinner.isHidden = true; spinner.stopAnimation(nil)
        statusBar.stringValue = "  ✗ \(e.localizedDescription)"
    }
    // Open target=_blank links in the same webview
    func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
