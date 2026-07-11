import AppKit
import WebKit

/// The generated app's main window: a hidden-title-bar native window filled
/// edge-to-edge by a WKWebView, with native traffic-light overlays and frame
/// autosave for window-state memory.
final class BrowserWindowController: NSWindowController {
    private static let frameAutosaveKey = "AppSeedEngine.MainWindow"

    let webView: WKWebView
    private let config: AppConfig
    private let navigationCoordinator: NavigationCoordinator

    init(config: AppConfig) {
        self.config = config

        let contentRect = NSRect(x: 0, y: 0, width: config.window.width, height: config.window.height)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = config.appName // shown in Mission Control / Window menu only
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 400, height: 300)

        let webConfiguration = WKWebViewConfiguration()
        // One distinct data store per generated app: the *default* persistent
        // store is siloed per CFBundleIdentifier (~/Library/WebKit/<bundle id>),
        // and the factory assigns each wrapped domain its own deterministic
        // bundle id. Cookies and logins therefore never leak between wrapped
        // apps or Safari, and they survive regeneration of the same app.
        webConfiguration.websiteDataStore = .default()
        // Safari-like UA suffix improves compatibility with sites that sniff
        // for a "real" browser. Hard-blocking identity providers are still
        // routed out to ASWebAuthenticationSession by NavigationCoordinator.
        webConfiguration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true
        ResourceInjector.installUserScripts(into: webConfiguration.userContentController)

        let webView = WKWebView(frame: contentRect, configuration: webConfiguration)
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.webView = webView
        window.contentView = webView

        let host = URL(string: config.url)?.host ?? ""
        navigationCoordinator = NavigationCoordinator(
            appDomain: DomainUtils.registrableDomain(of: host),
            hostWindow: window
        )

        super.init(window: window)

        navigationCoordinator.attach(to: webView)

        // Native window-state memory: restore the last frame if one was saved,
        // otherwise center at the configured initial size.
        if !window.setFrameUsingName(Self.frameAutosaveKey) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveKey)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrowserWindowController is created in code only")
    }

    func loadStartPage() {
        guard let url = URL(string: config.url) else { return }
        webView.load(URLRequest(url: url))
    }
}
