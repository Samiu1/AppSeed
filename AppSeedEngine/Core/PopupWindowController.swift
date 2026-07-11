import AppKit
import WebKit

/// Secondary window for window.open() popups (OAuth windows, pickers).
///
/// The web view MUST be created from the WKWebViewConfiguration that WebKit
/// passes to `webView(_:createWebViewWith:...)` — that is what makes it share
/// the parent app's WKWebsiteDataStore/process, so login sessions persist.
final class PopupWindowController: NSWindowController, NSWindowDelegate {
    let webView: WKWebView
    private weak var coordinator: NavigationCoordinator?
    private var titleObservation: NSKeyValueObservation?

    init(configuration: WKWebViewConfiguration,
         coordinator: NavigationCoordinator,
         features: WKWindowFeatures,
         hostWindow: NSWindow?) {
        self.coordinator = coordinator

        let width = features.width?.doubleValue ?? 620
        let height = features.height?.doubleValue ?? 720
        let contentRect = NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 240))

        let webView = WKWebView(frame: contentRect, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        self.webView = webView

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.tabbingMode = .disallowed
        if let hostFrame = hostWindow?.frame {
            window.setFrameOrigin(NSPoint(
                x: hostFrame.midX - contentRect.width / 2,
                y: hostFrame.midY - contentRect.height / 2
            ))
        } else {
            window.center()
        }

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        titleObservation = webView.observe(\.title, options: [.new]) { [weak window] _, change in
            window?.title = (change.newValue ?? nil) ?? ""
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PopupWindowController is created in code only")
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.popupWindowClosed(self)
    }
}
