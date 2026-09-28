# Spec H1 — Engine Main Menu Completion

**Status:** ready to implement
**Targets:** `AppSeedEngine` (wrapped-app runtime) + `Shared/EngineVersion.swift`
**Depends on:** nothing. **Blocks:** H2 (`docs/specs/wrapped-app-chrome.md`) reuses the actions added here.

## Context

Every generated wrapped app gets a minimal main menu today
(`AppSeedEngine/Core/EngineAppDelegate.swift`, `makeMainMenu` at line 64):
App / Edit / View / Window only. This spec completes it to a full native menu
bar. The original requirements came from a Tauri-oriented PRD — this spec is
the AppKit translation: instead of string-ID dispatch (`handle_menu_click`)
and `window.eval()`, we use target/action selectors, the responder chain, and
native `WKWebView` APIs.

### Routing convention (follow exactly)

- **Web / window-state actions** → `@objc` methods on `BrowserWindowController`,
  wired as **nil-target** menu items. The responder chain resolves them:
  webView → contentView → window → windowController. Enabled state and
  checkmarks come from one `NSMenuItemValidation` extension on the controller.
- **App-level actions** (customizations) → stay on `EngineAppDelegate` with
  explicit `#selector(EngineAppDelegate.…)`, exactly as today.
- **Standard AppKit/system actions** (hide, quit, close, minimize, full screen,
  undo/copy/paste) → nil-target system selectors, as today.
- Use **distinct selector names** (`navigateBack(_:)`, NOT `goBack(_:)`).
  WKWebView itself implements `goBack:`/`goForward:`/`reload:` — reusing those
  names would let the web view swallow the action before our controller sees
  it, bypassing our validation.

### Do NOT

- Do not touch `NavigationCoordinator.swift` (OAuth design note at its top).
- Do not change window style: keep `titleVisibility = .hidden`,
  `titlebarAppearsTransparent = true`, and NOT `.fullSizeContentView`
  (load-bearing comment in `BrowserWindowController.swift:20-25`).
- Do not add a Help menu. Deliberately deferred — there is no stable public
  help URL yet (the GitHub repo may go private; see ROADMAP section C).
- Do not modify `Scripts/build.sh` — it globs `AppSeedEngine/Core/*.swift`,
  so the new file below is picked up automatically.

---

## Task 1 — New file `AppSeedEngine/Core/EngineMainMenu.swift`

Menu construction moves out of `EngineAppDelegate` into this new file.
Create it with exactly this content:

```swift
import AppKit

/// Builds the wrapped app's main menu bar. Construction only — behavior lives
/// on BrowserWindowController (web/window-state actions, reached as nil-target
/// selectors via the responder chain and validated there) and on
/// EngineAppDelegate (app-level customization actions).
enum EngineMainMenu {
    static func make(appName: String) -> NSMenu {
        let mainMenu = NSMenu()
        addSubmenu(appMenu(appName: appName), title: appName, to: mainMenu)
        addSubmenu(fileMenu(), title: "File", to: mainMenu)
        addSubmenu(editMenu(), title: "Edit", to: mainMenu)
        addSubmenu(viewMenu(), title: "View", to: mainMenu)
        addSubmenu(navigationMenu(), title: "Navigation", to: mainMenu)
        let window = windowMenu()
        addSubmenu(window, title: "Window", to: mainMenu)
        NSApp.windowsMenu = window
        return mainMenu
    }

    private static func appMenu(appName: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About \(appName)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close Window",
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(.separator())
        let clearCache = NSMenuItem(title: "Clear Cache",
                                    action: #selector(BrowserWindowController.clearCache(_:)),
                                    keyEquivalent: "e")
        clearCache.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(clearCache)
        menu.addItem(withTitle: "Clear All Website Data…",
                     action: #selector(BrowserWindowController.clearAllWebsiteData(_:)),
                     keyEquivalent: "")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        let copyURL = NSMenuItem(title: "Copy Current URL",
                                 action: #selector(BrowserWindowController.copyCurrentURL(_:)),
                                 keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(copyURL)
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Reload Page",
                     action: #selector(BrowserWindowController.reloadPage(_:)), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Actual Size",
                     action: #selector(BrowserWindowController.zoomActualSize(_:)), keyEquivalent: "0")
        menu.addItem(withTitle: "Zoom In",
                     action: #selector(BrowserWindowController.zoomIn(_:)), keyEquivalent: "+")
        menu.addItem(withTitle: "Zoom Out",
                     action: #selector(BrowserWindowController.zoomOut(_:)), keyEquivalent: "-")
        menu.addItem(.separator())
        let reloadCustomizations = NSMenuItem(
            title: "Reload Customizations",
            action: #selector(EngineAppDelegate.reloadCustomizations(_:)),
            keyEquivalent: "r"
        )
        reloadCustomizations.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(reloadCustomizations)
        menu.addItem(withTitle: "Open Customization Folder…",
                     action: #selector(EngineAppDelegate.openCustomizationFolder(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let fullScreen = NSMenuItem(title: "Enter Full Screen",
                                    action: #selector(NSWindow.toggleFullScreen(_:)),
                                    keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)
        return menu
    }

    private static func navigationMenu() -> NSMenu {
        let menu = NSMenu(title: "Navigation")
        menu.addItem(withTitle: "Back",
                     action: #selector(BrowserWindowController.navigateBack(_:)), keyEquivalent: "[")
        menu.addItem(withTitle: "Forward",
                     action: #selector(BrowserWindowController.navigateForward(_:)), keyEquivalent: "]")
        menu.addItem(.separator())
        let home = NSMenuItem(title: "Go Home",
                              action: #selector(BrowserWindowController.goHome(_:)),
                              keyEquivalent: "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(home)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Float on Top",
                     action: #selector(BrowserWindowController.toggleFloatOnTop(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func addSubmenu(_ submenu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }
}
```

Notes on deliberate choices (leave them as written):
- **Close Window moved to File** (AppKit convention) — remove it from Window.
- **Back/Forward moved from View to the new Navigation menu.**
- `NSMenuItem(withTitle:action:keyEquivalent:)` defaults to the ⌘ modifier;
  masks are set explicitly only where the combo differs.
- Menus keep the default `autoenablesItems = true` so `validateMenuItem`
  (Task 3) controls enabled state.

## Task 2 — Edit `AppSeedEngine/Core/EngineAppDelegate.swift`

1. Replace line 12
   `NSApp.mainMenu = Self.makeMainMenu(appName: config.appName)` with:
   ```swift
   NSApp.mainMenu = EngineMainMenu.make(appName: config.appName)
   ```
2. Delete the entire `// MARK: - Main menu` section: the doc comment,
   `makeMainMenu(appName:)`, and `addSubmenu(_:title:to:)` (lines 59–121 in
   the current file). Keep everything else, including
   `reloadCustomizations(_:)` and `openCustomizationFolder(_:)` — the new
   menu still targets them.

## Task 3 — Edit `AppSeedEngine/Core/BrowserWindowController.swift`

### 3a. Add two UserDefaults keys next to `frameAutosaveKey` (line 8):

```swift
private static let pageZoomKey = "AppSeedEngine.PageZoom"
private static let floatOnTopKey = "AppSeedEngine.FloatOnTop"
```

### 3b. Restore persisted state in `init`, after the existing frame-autosave
block (after line 87 `window.setFrameAutosaveName(...)`):

```swift
// Restore per-app zoom and float-on-top from the last session.
let savedZoom = UserDefaults.standard.double(forKey: Self.pageZoomKey)
if savedZoom >= 0.5 && savedZoom <= 3.0 {
    webView.pageZoom = CGFloat(savedZoom)
}
if UserDefaults.standard.bool(forKey: Self.floatOnTopKey) {
    window.level = .floating
}
```

### 3c. Append the menu actions at the end of the class body (after
`reloadCustomizations()`):

```swift
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
```

### 3d. Add the validation extension at the very end of the file (outside the
class):

```swift
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
```

## Task 4 — Bump `Shared/EngineVersion.swift`

Change `static let current = 3` to `4` and append to the history comment:

```
///   4 — full main menu (File/Navigation/Window completion, page zoom,
///       float-on-top, clear cache / clear website data).
```

(If H2 — `docs/specs/wrapped-app-chrome.md` — ships in the same release, this
single bump covers both; do not bump twice.)

---

## Acceptance criteria

1. `Scripts/build.sh` compiles both targets with no warnings introduced.
2. Generate a test app:
   `build/AppSeed.app/Contents/MacOS/AppSeed --make https://en.wikipedia.org --out /tmp/appseed-test --overwrite`
   and launch it. Verify:
   - Menu bar shows: `<AppName>` / File / Edit / View / Navigation / Window —
     no Help menu.
   - **Navigation**: Back/Forward are grayed out on the start page; after
     clicking a link, Back enables (⌘[ works); Go Home (⇧⌘H) returns to the
     start URL.
   - **View**: ⌘+ / ⌘− / ⌘0 visibly resize and reflow content; quit and
     relaunch → zoom level restored. Reload Customizations ⌥⌘R and Open
     Customization Folder… still work. ⌃⌘F enters full screen.
   - **Edit**: Copy Current URL puts the page URL on the clipboard (⇧⌘C);
     grayed out before any page loads.
   - **File**: Close Window ⌘W closes (and, per existing delegate behavior,
     quits the app). Clear Cache reloads without signing out. Clear All
     Website Data… shows the warning alert; Cancel does nothing; "Clear and
     Sign Out" signs the site out and returns to the start page.
   - **Window**: Float on Top shows a checkmark when active and the window
     stays above other apps; state survives relaunch. Minimize/Zoom/Bring All
     to Front behave normally.
3. Factory: open Settings › My Apps — previously generated apps show as
   needing update (EngineVersion 4 > their stamped version). Run Update All
   on one and confirm its login survives.
4. OAuth regression check: `--make` a site with Google login and sign in —
   flow must complete in-window as before (nothing in this spec touches
   `NavigationCoordinator`).
