import AppKit
import WebKit

/// The generated app's main window: a hidden-title-bar native window filled
/// edge-to-edge by a WKWebView, with native traffic-light overlays and frame
/// autosave for window-state memory.
final class BrowserWindowController: NSWindowController {
    private static let frameAutosaveKey = "AppSeedEngine.MainWindow"
    private static let pageZoomKey = "AppSeedEngine.PageZoom"
    private static let floatOnTopKey = "AppSeedEngine.FloatOnTop"

    let webView: WKWebView
    private let containerView: EngineContentView
    private let progressBar = ProgressBarView()
    private let toolbar = FloatingToolbar()
    private var loadingObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var toolbarHideTimer: Timer?
    private let config: AppConfig
    private let navigationCoordinator: NavigationCoordinator
    private let notificationBridge = NotificationBridge()
    private var pageColorObservation: NSKeyValueObservation?

    init(config: AppConfig) {
        self.config = config

        let contentRect = NSRect(x: 0, y: 0, width: config.window.width, height: config.window.height)
        // Deliberately NOT .fullSizeContentView: the web view sits below the
        // (hidden, transparent) title bar. With full-size content the web view
        // swallows mouse events in the title-bar strip — the window can't be
        // dragged — and the traffic lights overlap the site's own header.
        // The strip is tinted to the page's background color below, so the
        // window still reads as seamless.
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        // for a "real" browser — and is what clears Google's
        // disallowed_useragent check so OAuth can complete in-window.
        webConfiguration.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true
        ResourceInjector.installUserScripts(into: webConfiguration.userContentController)

        let webView = WKWebView(frame: contentRect, configuration: webConfiguration)
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.webView = webView
        let containerView = EngineContentView(frame: contentRect)
        containerView.autoresizesSubviews = true
        webView.frame = containerView.bounds   // autoresizingMask [.width,.height] already set
        containerView.addSubview(webView)
        progressBar.frame = NSRect(
            x: 0, y: containerView.bounds.height - ProgressBarView.barHeight,
            width: containerView.bounds.width, height: ProgressBarView.barHeight
        )
        progressBar.autoresizingMask = [.width, .minYMargin]  // stays pinned to the top edge
        containerView.addSubview(progressBar)
        toolbar.frame.origin = NSPoint(
            x: (containerView.bounds.width - FloatingToolbar.size.width) / 2,
            y: 16
        )
        toolbar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]  // bottom-center on resize
        containerView.addSubview(toolbar)
        self.containerView = containerView
        window.contentView = containerView

        let host = URL(string: config.url)?.host ?? ""
        navigationCoordinator = NavigationCoordinator(
            appDomain: DomainUtils.registrableDomain(of: host),
            hostWindow: window
        )

        super.init(window: window)

        navigationCoordinator.attach(to: webView)
        // Bridge the web Notification API to native notifications. Added after
        // super.init (needs self) but before the first load, so the shim
        // injects at document start and the handler is present.
        notificationBridge.install(into: webView.configuration.userContentController)

        // Blend the title-bar strip with the page: track WebKit's
        // under-page background color so the strip matches light and dark
        // sites alike instead of showing system-gray chrome.
        window.backgroundColor = webView.underPageBackgroundColor
        pageColorObservation = webView.observe(\.underPageBackgroundColor, options: [.new]) { [weak window] webView, _ in
            window?.backgroundColor = webView.underPageBackgroundColor
        }

        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            if webView.isLoading {
                self?.progressBar.beginLoading()
            } else {
                self?.progressBar.finishLoading()
            }
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.progressBar.setProgress(webView.estimatedProgress)
        }

        containerView.onMouseMoved = { [weak self] in self?.showToolbar() }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = DragHintView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        window.addTitlebarAccessoryViewController(accessory)

        // Native window-state memory: restore the last frame if one was saved,
        // otherwise center at the configured initial size.
        if !window.setFrameUsingName(Self.frameAutosaveKey) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveKey)

        // Restore per-app zoom and float-on-top from the last session.
        let savedZoom = UserDefaults.standard.double(forKey: Self.pageZoomKey)
        if savedZoom >= 0.5 && savedZoom <= 3.0 {
            webView.pageZoom = CGFloat(savedZoom)
        }
        if UserDefaults.standard.bool(forKey: Self.floatOnTopKey) {
            window.level = .floating
        }
    }

    deinit {
        toolbarHideTimer?.invalidate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrowserWindowController is created in code only")
    }

    func loadStartPage() {
        guard let url = URL(string: config.url) else { return }
        webView.load(URLRequest(url: url))
    }

    /// Re-reads inject.js / custom.css from the customization folder and
    /// reloads, so edits apply without relaunching the app.
    func reloadCustomizations() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        ResourceInjector.installUserScripts(into: controller)
        // removeAllUserScripts() also dropped the notification shim — re-add it
        // (the message handler registration survives and isn't re-added).
        notificationBridge.addUserScript(to: controller)
        webView.reload()
    }

    // MARK: - Menu actions
    // Reached as nil-target selectors via the responder chain
    // (webView → contentView → window → this controller). Names deliberately
    // differ from WKWebView's own goBack:/goForward:/reload: so the web view
    // can't intercept them ahead of our validation.
    // Known tradeoff: while an OAuth popup (PopupWindowController) is key,
    // these items disable — the popup has no BrowserWindowController.

    @objc func navigateBack(_ sender: Any?) { webView.goBack() }
    @objc func navigateForward(_ sender: Any?) { webView.goForward() }
    @objc func reloadPage(_ sender: Any?) { webView.reload() }
    @objc func goHome(_ sender: Any?) { loadStartPage() }

    @objc func copyCurrentURL(_ sender: Any?) {
        guard let url = webView.url else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    @objc func zoomIn(_ sender: Any?) { setPageZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setPageZoom(webView.pageZoom / 1.1) }
    @objc func zoomActualSize(_ sender: Any?) { setPageZoom(1.0) }

    /// pageZoom (not magnification): reflows content like Safari's ⌘+/⌘−.
    /// magnification is a pinch-scale transform that clips instead of reflowing;
    /// allowsMagnification stays on for trackpad gestures.
    private func setPageZoom(_ value: CGFloat) {
        let clamped = min(max(value, 0.5), 3.0)
        webView.pageZoom = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.pageZoomKey)
    }

    @objc func toggleFloatOnTop(_ sender: Any?) {
        guard let window else { return }
        let floating = window.level != .floating
        window.level = floating ? .floating : .normal
        UserDefaults.standard.set(floating, forKey: Self.floatOnTopKey)
    }

    /// Caches only — cookies and logins untouched, so no confirmation needed.
    @objc func clearCache(_ sender: Any?) {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache,
        ]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.webView.reload()
        }
    }

    /// Destructive: deletes cookies/logins, which the product otherwise promises
    /// to preserve — the confirmation alert is mandatory, and the confirm button
    /// says exactly what happens.
    @objc func clearAllWebsiteData(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all website data?"
        alert.informativeText = "This signs you out of \(config.appName) and removes all cookies and site data for this app. Your other apps are not affected."
        alert.addButton(withTitle: "Clear and Sign Out")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            self?.loadStartPage()
        }
    }

    // MARK: - Floating toolbar autohide

    private func showToolbar() {
        toolbar.backButton.isEnabled = webView.canGoBack
        toolbar.forwardButton.isEnabled = webView.canGoForward
        if toolbar.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                toolbar.animator().alphaValue = 1
            }
        }
        scheduleToolbarHide()
    }

    private func scheduleToolbarHide() {
        toolbarHideTimer?.invalidate()
        toolbarHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.toolbar.isHovered {
                self.scheduleToolbarHide()  // check again later; don't hide under the pointer
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                self.toolbar.animator().alphaValue = 0
            }
        }
    }
}

extension BrowserWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(navigateBack(_:)):
            return webView.canGoBack
        case #selector(navigateForward(_:)):
            return webView.canGoForward
        case #selector(copyCurrentURL(_:)):
            return webView.url != nil
        case #selector(toggleFloatOnTop(_:)):
            menuItem.state = (window?.level == .floating) ? .on : .off
            return true
        default:
            return true
        }
    }
}
