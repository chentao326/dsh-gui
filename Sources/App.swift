import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var server: ServerManager?
    private var currentURL: URL?
    private var reconnectAttempts = 0
    private let maxReconnect = 2

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
        buildWindow()
        boot()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        server?.shutdown()
    }

    // MARK: - Boot orchestration

    private func boot() {
        let settings = loadSettings()
        showStatus("正在连接 DSH 服务…")
        DispatchQueue.global(qos: .userInitiated).async {
            for port in discoverPorts(settings: settings) where probePort(port) {
                DispatchQueue.main.async {
                    self.connected(url: URL(string: "http://127.0.0.1:\(port)/")!)
                }
                return
            }
            DispatchQueue.main.async { self.spawnServer(settings: settings) }
        }
    }

    private func spawnServer(settings: GuiSettings) {
        showStatus("未发现运行中的 DSH，正在启动服务…")
        let cwd = settings.cwd ?? NSHomeDirectory()
        let mgr = ServerManager()
        mgr.onUrl = { [weak self] url in
            self?.reconnectAttempts = 0
            self?.connected(url: url)
        }
        mgr.onExit = { [weak self] in
            guard let self else { return }
            self.showStatus("DSH 服务已退出，正在重连…")
            if self.reconnectAttempts < self.maxReconnect {
                self.reconnectAttempts += 1
                self.boot()
            } else {
                self.showError("DSH 服务意外退出。日志：~/Library/Logs/dsh-gui.log")
            }
        }
        let port = portReachable(3080) ? 0 : 3080
        guard mgr.start(settings: settings, cwd: cwd, port: port) else {
            showError("未找到 dsh 命令。请先安装：npm install -g @deepseek-ai/dsh；或在设置文件（~/Library/Application Support/DSH GUI/settings.json）中配置 dshPath。")
            return
        }
        server = mgr
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak mgr] in
            guard let self, let mgr, self.server === mgr, self.currentURL == nil else { return }
            mgr.shutdown()
            self.showError("DSH 服务 30 秒内未能就绪。日志：~/Library/Logs/dsh-gui.log")
        }
    }

    private func connected(url: URL) {
        currentURL = url
        GuiLog.shared.write("connected to \(url.absoluteString)")
        webView.load(URLRequest(url: url))
    }

    // MARK: - Window & webview

    private func buildWindow() {
        let settings = loadSettings()
        let rect = NSRect(x: 0, y: 0, width: settings.windowWidth ?? 1280, height: settings.windowHeight ?? 800)
        let w = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "DeepSeek Harness"
        w.minSize = NSSize(width: 800, height: 600)
        w.center()
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: w.contentView!.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        w.contentView?.addSubview(web)
        webView = web
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menus

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 DeepSeek Harness",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DeepSeek Harness",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // 编辑菜单：选择器走响应链（target=nil），让 WKWebView 内的
        // 剪切/拷贝/粘贴/全选可用——没有它 Cmd+C/V/X 无法路由。
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        let reload = viewMenu.addItem(withTitle: "重新加载", action: #selector(reloadPage), keyEquivalent: "r")
        reload.target = self
        let open = viewMenu.addItem(withTitle: "在浏览器中打开",
                                    action: #selector(openInBrowser), keyEquivalent: "o")
        open.target = self
        open.keyEquivalentModifierMask = [.command, .shift]
        viewItem.submenu = viewMenu

        NSApp.mainMenu = main
    }

    @objc private func reloadPage() {
        if currentURL != nil { webView.reload() } else { boot() }
    }

    @objc private func openInBrowser() {
        if let url = currentURL { NSWorkspace.shared.open(url) }
    }

    // MARK: - Status / error pages

    private func showStatus(_ text: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
             background:#0b0e14;color:#d7dde8;font-family:-apple-system,"PingFang SC",sans-serif}
        .box{text-align:center}
        .spinner{width:36px;height:36px;margin:0 auto 18px;border:3px solid #2a3140;border-top-color:#4d7cfe;
                 border-radius:50%;animation:spin 0.9s linear infinite}
        @keyframes spin{to{transform:rotate(360deg)}}
        </style></head><body><div class="box">
        <div class="spinner"></div><p>\(text)</p></div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showError(_ message: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
             background:#0b0e14;color:#d7dde8;font-family:-apple-system,"PingFang SC",sans-serif}
        .box{text-align:center;max-width:520px;padding:24px}
        a{display:inline-block;margin-top:16px;padding:8px 22px;border-radius:8px;
          background:#4d7cfe;color:#fff;text-decoration:none}
        </style></head><body><div class="box">
        <p style="font-size:17px">\(message)</p>
        <a href="dshgui://retry">重试</a>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.request.url?.scheme == "dshgui" {
            decisionHandler(.cancel)
            boot()
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            showError("无法连接 DSH 服务（\(error.localizedDescription)）。日志：~/Library/Logs/dsh-gui.log")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            showError("页面加载失败（\(error.localizedDescription)）。日志：~/Library/Logs/dsh-gui.log")
        }
    }
}
