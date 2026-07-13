import AppKit
import WebKit

/// The engine's navigation policy. Decides, for every load, whether it stays
/// in-window, opens a popup, or hands off to the default browser:
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
///  - Third-party identity providers (Google, Microsoft, Apple) are kept
///    IN the app's WebView — either in-window or in a shared-store popup —
///    NOT ejected to ASWebAuthenticationSession. See the note below.
///  - Downloads land in ~/Downloads via WKDownloadDelegate.
///  - Camera/microphone prompts are forwarded (v1: in scope). Web
///    notifications are a deliberate v1 cut — WKWebView has no native bridge
///    for them, and we do not fake one.
///
/// OAuth design note (learned on-device): an earlier version routed Google &
/// co. through `ASWebAuthenticationSession`. That FAILS for wrapped sites,
/// because the site starts the flow in this WebView (setting an OAuth `state`
/// against a cookie in our WKWebsiteDataStore) but the auth session runs in a
/// separate Safari context. The provider redirects back into that Safari
/// context, so the site sees a missing/mismatched `state`
/// ("Invalid OAuth state"), and the resulting cookies land in Safari's jar,
/// not our data store — so the login never persists either. The wrapped site
/// owns its own OAuth client and redirect URI (AppSeed does not), so there is
/// no custom callback scheme for us to catch. Keeping the whole flow in one
/// context — this WebView, which already sends a desktop-Safari User-Agent to
/// clear Google's `disallowed_useragent` check — keeps `state` and cookies
/// consistent. Do not reintroduce the ASWebAuthenticationSession hand-off.
final class NavigationCoordinator: NSObject {
    private let appDomain: String
    private weak var hostWindow: NSWindow?
    private weak var mainWebView: WKWebView?
    private var popups: [PopupWindowController] = []

    /// Registrable domains of third-party identity providers. Navigations here
    /// are kept inside the app's WebView (in-window or shared-store popup) so
    /// the OAuth flow completes in the same context that started it.
    private static let authProviders: Set<String> = [
        "google.com", "youtube.com",
        "microsoftonline.com", "live.com", "microsoft.com", "office.com",
        "apple.com", "icloud.com",
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

    private func isAuthProvider(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return Self.authProviders.contains(DomainUtils.registrableDomain(of: host))
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

        // Subframes (embeds, SSO iframes, Google One Tap) load freely
        // regardless of origin.
        if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
            decisionHandler(.allow)
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

        // Third-party identity providers stay in-window so the OAuth flow
        // completes in the same context (and data store) that began it —
        // ejecting them breaks `state` validation and cookie persistence.
        if isAuthProvider(url) {
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
            // New-window requests to unrelated domains open in the default
            // browser — EXCEPT identity providers, whose popups must stay
            // in-app and share the data store (Google/Microsoft commonly open
            // their consent screen via window.open).
            if !isSameSite(url) && !isAuthProvider(url) {
                openExternally(url)
                return nil
            }
        }
        // Same-site, auth-provider, or initially-blank scripted popup: a real
        // secondary window built from the configuration WebKit provided,
        // sharing this app's WKWebsiteDataStore so the session persists.
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
