import AppKit
import WebKit
import UserNotifications

/// Bridges the web `Notification` API to native macOS notifications.
///
/// WKWebView does not deliver web notifications on its own. This installs a
/// small JS shim that replaces `window.Notification`: page calls to
/// `new Notification(...)` and `Notification.requestPermission()` are posted
/// over a `WKScriptMessageHandler` to this native object, which schedules
/// `UNUserNotificationCenter` alerts and reports the real OS permission back.
/// Clicking a delivered notification activates the app, brings the originating
/// web view's window to the front, and fires the page's `onclick`.
///
/// Scope (v1): the foreground `Notification` API — what Gmail, Slack, Linear,
/// and WhatsApp Web use while open. The Push API via service workers
/// (`ServiceWorkerRegistration.showNotification`, background push) is NOT
/// bridged — that needs a real push service and VAPID keys AppSeed doesn't
/// own. Sites that only push in the background won't notify while closed.
final class NotificationBridge: NSObject {
    private static let handlerName = "appseedNotify"

    /// Weak refs to the web view each pending notification came from, so a
    /// click can be routed back to the right page.
    private var originWebViews = [String: WeakWebView]()

    private final class WeakWebView {
        weak var value: WKWebView?
        init(_ value: WKWebView) { self.value = value }
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Installs the message handler and the shim user script.
    func install(into controller: WKUserContentController) {
        controller.add(self, name: Self.handlerName)
        addUserScript(to: controller)
    }

    /// Re-adds just the shim user script — used after
    /// `removeAllUserScripts()` on a customization reload, so the bridge
    /// survives even though the message handler registration does not need
    /// re-adding.
    func addUserScript(to controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(
            source: Self.shimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    // MARK: - Authorization

    private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "default"
        @unknown default: return "default"
        }
    }

    private func reportPermission(to webView: WKWebView?) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self, weak webView] settings in
            let value = self?.authorizationStatusString(settings.authorizationStatus) ?? "default"
            DispatchQueue.main.async {
                webView?.evaluateJavaScript("window.__appseedNotify && window.__appseedNotify.setPermission('\(value)')")
            }
        }
    }

    /// Requests authorization (prompting only if not yet determined), then
    /// reports the resulting permission back to the page.
    private func requestPermission(from webView: WKWebView?) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self, weak webView] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    self.reportPermission(to: webView)
                }
            } else {
                self.reportPermission(to: webView)
            }
        }
    }

    /// Ensures authorization, then runs `deliver` if it was granted.
    private func ifAuthorized(from webView: WKWebView?, deliver: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async(execute: deliver)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { DispatchQueue.main.async(execute: deliver) }
                    self.reportPermission(to: webView)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - Delivery

    private func show(id: String, title: String, body: String, from webView: WKWebView?) {
        if let webView { originWebViews[id] = WeakWebView(webView) }
        ifAuthorized(from: webView) {
            let content = UNMutableNotificationContent()
            // Fall back to the app name when the page gives an empty title.
            content.title = title.isEmpty ? (Bundle.main.appDisplayName) : title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension NotificationBridge: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName, let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "queryPermission":
            reportPermission(to: message.webView)
        case "requestPermission":
            requestPermission(from: message.webView)
        case "show":
            let id = body["id"] as? String ?? UUID().uuidString
            show(id: id,
                 title: body["title"] as? String ?? "",
                 body: body["body"] as? String ?? "",
                 from: message.webView)
        case "close":
            if let id = body["id"] as? String {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
                originWebViews[id] = nil
            }
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationBridge: UNUserNotificationCenterDelegate {
    /// Show the banner even while the wrapped app is frontmost — otherwise a
    /// foreground app's own notifications are silently suppressed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A click brings the app + originating window forward and fires the
    /// page's `onclick`, matching native web-notification behavior.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            let webView = self?.originWebViews[id]?.value
            webView?.window?.makeKeyAndOrderFront(nil)
            webView?.evaluateJavaScript("window.__appseedNotify && window.__appseedNotify.clicked('\(id)')")
            self?.originWebViews[id] = nil
            completionHandler()
        }
    }
}

private extension Bundle {
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }
}

// MARK: - JS shim

extension NotificationBridge {
    /// Replaces `window.Notification` with a shim that forwards to the native
    /// bridge. Injected at document start in all frames.
    static let shimSource = #"""
    (function () {
      if (window.__appseedNotify) return;
      var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.appseedNotify;
      if (!mh) return; // no native bridge (e.g. an auth popup) — leave defaults

      var permission = 'default';
      var pending = [];
      var seq = 0;
      var registry = {};

      window.__appseedNotify = {
        setPermission: function (p) {
          permission = p;
          var queue = pending; pending = [];
          queue.forEach(function (resolve) { try { resolve(p); } catch (e) {} });
        },
        clicked: function (id) {
          var n = registry[id];
          if (n && typeof n.onclick === 'function') { try { n.onclick(new Event('click')); } catch (e) {} }
        }
      };

      function Notif(title, options) {
        options = options || {};
        var id = 'n' + (seq++);
        this._id = id;
        this.title = String(title == null ? '' : title);
        this.body = String(options.body || '');
        this.icon = String(options.icon || '');
        this.tag = String(options.tag || '');
        this.data = options.data;
        this.onclick = null; this.onshow = null; this.onclose = null; this.onerror = null;
        registry[id] = this;
        try {
          mh.postMessage({ type: 'show', id: id, title: this.title, body: this.body, icon: this.icon, tag: this.tag });
        } catch (e) {}
        var self = this;
        setTimeout(function () { if (typeof self.onshow === 'function') { try { self.onshow(new Event('show')); } catch (e) {} } }, 0);
      }
      Object.defineProperty(Notif, 'permission', { get: function () { return permission; }, configurable: true });
      Notif.maxActions = 0;
      Notif.requestPermission = function (cb) {
        var p = new Promise(function (resolve) {
          pending.push(resolve);
          try { mh.postMessage({ type: 'requestPermission' }); } catch (e) { resolve('denied'); }
        });
        if (typeof cb === 'function') { p.then(cb); }
        return p;
      };
      Notif.prototype.close = function () { try { mh.postMessage({ type: 'close', id: this._id }); } catch (e) {} };
      Notif.prototype.addEventListener = function (t, fn) {
        if (t === 'click') this.onclick = fn;
        else if (t === 'show') this.onshow = fn;
        else if (t === 'close') this.onclose = fn;
        else if (t === 'error') this.onerror = fn;
      };
      Notif.prototype.removeEventListener = function () {};
      Notif.prototype.dispatchEvent = function () { return true; };

      try {
        Object.defineProperty(window, 'Notification', { value: Notif, writable: true, configurable: true });
      } catch (e) { window.Notification = Notif; }

      try { mh.postMessage({ type: 'queryPermission' }); } catch (e) {}
    })();
    """#
}
