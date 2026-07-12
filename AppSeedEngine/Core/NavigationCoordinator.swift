import AppKit
import WebKit
import AuthenticationServices

/// The engine's navigation policy. Decides, for every load, whether it stays
/// in-window, opens a popup, hands off to the default browser, or runs
/// through a trusted system auth session:
///
///  - Same-registrable-domain loads — including SPA route changes via
///    pushState/replaceState, which never even reach the delegate — stay
///    in-window.
///  - Only genuine *user-initiated* cross-domain navigations (link clicks,
///    target="_blank" to another domain) open in the default browser.
///    Redirect chains and form submissions are allowed through, because OAuth
///    return legs and payment flows bounce across domains mid-login.
///  - window.open() popups get a real secondary window created from the
///    WKWebViewConfiguration WebKit hands us, so they share this app's
///    WKWebsiteDataStore and the session persists.
///  - Known identity providers are routed through ASWebAuthenticationSession:
///    Google hard-blocks embedded WKWebView logins (403: disallowed_useragent).
///  - Downloads land in ~/Downloads via WKDownloadDelegate.
///  - Camera/microphone prompts are forwarded (v1: in scope). Web
///    notifications are a deliberate v1 cut — WKWebView has no native bridge
///    for them, and we do not fake one.
final class NavigationCoordinator: NSObject {
    private let appDomain: String
    private weak var hostWindow: NSWindow?
    private weak var mainWebView: WKWebView?
    private var popups: [PopupWindowController] = []
    private var authSession: ASWebAuthenticationSession?

    /// Identity providers that refuse to complete auth inside an embedded
    /// WKWebView. Navigations here run in an ASWebAuthenticationSession.
    private static let authDomains: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
        "login.microsoftonline.com",
        "login.live.com",
        "appleid.apple.com",
    ]

    init(appDomain: String, hostWindow: NSWindow) {
        self.appDomain = appDomain
        self.hostWindow = hostWindow
    }

    func attach(to webView: WKWebView) {
        mainWebView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    // MARK: - Classification helpers

    private func isPopup(_ webView: WKWebView) -> Bool {
        popups.contains { $0.webView === webView }
    }

    private func isAuthURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.authDomains.contains(host)
    }

    private func isSameSite(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return DomainUtils.registrableDomain(of: host) == appDomain
    }

    private func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func popupWindowClosed(_ controller: PopupWindowController) {
        popups.removeAll { $0 === controller }
    }

    // MARK: - ASWebAuthenticationSession

    /// Completes a login at a hard-blocking identity provider in a trusted
    /// Safari web context. AppSeed does not own the wrapped site's OAuth
    /// client or redirect URIs, so there is no custom callback scheme to
    /// capture — the goal is that the provider redirects back to the wrapped
    /// site *inside* the session and the resulting cookies land in the shared
    /// (non-ephemeral) cookie store, after which the main web view reloads
    /// and picks the session up.
    private func startAuthSession(with url: URL) {
        authSession?.cancel()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.authSession = nil
                self?.mainWebView?.reload()
            }
        }
        session.prefersEphemeralWebBrowserSession = false // share cookies — required for the session to persist
        session.presentationContextProvider = self
        authSession = session
        session.start()
    }
}

// MARK: - WKNavigationDelegate

extension NavigationCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Non-web schemes (mailto:, facetime:, app deep links) go to the system.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                openExternally(url)
                decisionHandler(.cancel)
            }
            return
        }

        // Subframes (embeds, SSO iframes) load freely regardless of origin —
        // and this check MUST come before the identity-provider intercept:
        // sites like LinkedIn embed Google One Tap in accounts.google.com
        // iframes, and intercepting those would fire an endless stream of
        // ASWebAuthenticationSession consent dialogs.
        if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
            decisionHandler(.allow)
            return
        }

        // Hard-blocking identity providers (main frame / new window only)
        // → trusted system auth session.
        if isAuthURL(url) {
            startAuthSession(with: url)
            decisionHandler(.cancel)
            return
        }

        // Popups may navigate anywhere: OAuth chains bounce across several
        // domains before returning to the opener.
        if isPopup(webView) {
            decisionHandler(.allow)
            return
        }

        if isSameSite(url) {
            decisionHandler(.allow)
            return
        }

        // Cross-domain in the main frame: hand off only genuine user
        // navigations. A cross-domain redirect or form submission must stay
        // in-window or logins and checkout flows break.
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Anything the web view can't render (file exports, attachments)
        // becomes a download instead of silently failing.
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension NavigationCoordinator: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme?.lowercased().hasPrefix("http") == true {
            if isAuthURL(url) {
                startAuthSession(with: url)
                return nil
            }
            // New-window requests to other domains are treated like external
            // navigations and open in the default browser.
            if !isSameSite(url) {
                openExternally(url)
                return nil
            }
        }
        // Same-site (or initially-blank scripted) popup: a real secondary
        // window built from the configuration WebKit provided, sharing this
        // app's WKWebsiteDataStore so the session persists.
        let popup = PopupWindowController(
            configuration: configuration,
            coordinator: self,
            features: windowFeatures,
            hostWindow: hostWindow
        )
        popups.append(popup)
        popup.showWindow(nil)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let index = popups.firstIndex(where: { $0.webView === webView }) else { return }
        let popup = popups.remove(at: index)
        popup.close()
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Forward to WebKit's prompt, which triggers the native macOS
        // camera/microphone consent (usage strings are in Info.plist), so
        // video-call sites work. In scope for v1.
        decisionHandler(.prompt)
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }
}

// MARK: - WKDownloadDelegate

extension NavigationCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(nil)
            return
        }
        completionHandler(Self.uniqueDestination(in: downloads, filename: suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) {
        // Subtle completion signal — bounce the Dock icon once.
        NSApp.requestUserAttention(.informationalRequest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Download failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// WKDownload refuses to overwrite; append " 2", " 3", … before the
    /// extension until the name is free.
    private static func uniqueDestination(in directory: URL, filename: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(next)
            counter += 1
        }
        return candidate
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NavigationCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        hostWindow ?? NSApp.keyWindow ?? NSWindow()
    }
}
