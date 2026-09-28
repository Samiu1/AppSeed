# Spec H2 — Wrapped-App Chrome (Floating Toolbar, Progress Bar, Drag Hint)

**Status:** ready to implement
**Targets:** `AppSeedEngine` + `Shared/EngineVersion.swift`
**Depends on:** H1 (`docs/specs/menu-system.md`) — the toolbar buttons reuse
the `navigateBack(_:)` / `navigateForward(_:)` / `reloadPage(_:)` actions H1
adds to `BrowserWindowController`. Implement H1 first.

## Context

This implements the three items of ROADMAP section E. Generated apps are
edge-to-edge WKWebViews with hidden title bars — no back/forward/reload
affordance except ⌘[/⌘], no loading feedback, and no hint that the top strip
is draggable. Users feel "trapped."

### Constraints (do NOT violate)

- **Keep the window NOT `.fullSizeContentView`.** The comment at
  `BrowserWindowController.swift:20-25` explains why: full-size content makes
  the web view swallow drag events in the title strip and overlaps the
  traffic lights. All overlays in this spec live in the *content* area, below
  the strip.
- **No `HUDStyle` in the engine target.** `HUDStyle` lives in
  `AppSeed/Views/HUDPanel.swift`, which is compiled only into the factory.
  Engine UI uses system colors (`NSColor.controlAccentColor`,
  `NSVisualEffectView`).
- Do not touch `NavigationCoordinator.swift`.
- Do not modify `Scripts/build.sh` — new files in `AppSeedEngine/Core/` are
  picked up by its glob automatically.
- Do not reach into private view hierarchies (`NSThemeFrame`,
  `standardWindowButton(...).superview`) — Task 4 uses only the public
  titlebar-accessory API.

---

## Task 1 — Container view (prerequisite for Tasks 2–3)

Today `BrowserWindowController.init` sets `window.contentView = webView`
directly (line 58). Overlays need a container.

In `AppSeedEngine/Core/BrowserWindowController.swift`:

1. Add stored properties (near `webView`, line 10):
   ```swift
   private let containerView: EngineContentView
   private let progressBar = ProgressBarView()
   private let toolbar = FloatingToolbar()
   private var loadingObservation: NSKeyValueObservation?
   private var progressObservation: NSKeyValueObservation?
   private var toolbarHideTimer: Timer?
   ```
   (`EngineContentView` and `FloatingToolbar` are created in Task 3,
   `ProgressBarView` in Task 2 — create those files first if the compiler
   complains about order; swiftc compiles them together, so order doesn't
   actually matter.)

2. Replace line 58 `window.contentView = webView` with:
   ```swift
   let containerView = EngineContentView(frame: contentRect)
   containerView.autoresizesSubviews = true
   webView.frame = containerView.bounds   // autoresizingMask [.width,.height] already set
   containerView.addSubview(webView)
   self.containerView = containerView
   window.contentView = containerView
   ```
   Everything else in `init` (tint KVO, frame autosave, NavigationCoordinator
   attach) stays exactly as is.

3. Add cleanup:
   ```swift
   deinit {
       toolbarHideTimer?.invalidate()
   }
   ```

## Task 2 — New file `AppSeedEngine/Core/ProgressBarView.swift`

A Safari-style 2pt loading bar pinned to the top of the content area
(directly under the transparent title strip).

```swift
import AppKit

/// A thin Safari-style loading bar: fills left-to-right with the accent
/// color while a page loads, then completes and fades out.
final class ProgressBarView: NSView {
    static let barHeight: CGFloat = 2

    private let fill = NSView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    /// value in 0...1 — sets the filled width, animated.
    func setProgress(_ value: Double) {
        let clamped = max(0, min(1, value))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            fill.animator().frame = NSRect(
                x: 0, y: 0,
                width: bounds.width * CGFloat(clamped),
                height: bounds.height
            )
        }
    }

    /// Show immediately with a sliver of progress so slow pages give
    /// instant feedback.
    func beginLoading() {
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * 0.05, height: bounds.height)
        alphaValue = 1
    }

    /// Run to full, pause briefly, then fade away.
    func finishLoading() {
        setProgress(1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.animator().alphaValue = 0
            }
        }
    }
}
```

Wire-up in `BrowserWindowController.init`, right after
`containerView.addSubview(webView)`:

```swift
progressBar.frame = NSRect(
    x: 0, y: containerView.bounds.height - ProgressBarView.barHeight,
    width: containerView.bounds.width, height: ProgressBarView.barHeight
)
progressBar.autoresizingMask = [.width, .minYMargin]  // stays pinned to the top edge
containerView.addSubview(progressBar)
```

And after `super.init(window: window)` (same pattern as the existing
`pageColorObservation` at line 78):

```swift
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
```

## Task 3 — New file `AppSeedEngine/Core/FloatingToolbar.swift`

Two classes in one file: the tracking content view and the toolbar itself.

```swift
import AppKit

/// The window's content view: hosts the web view plus overlay chrome, and
/// reports mouse movement so the floating toolbar can appear/auto-hide.
final class EngineContentView: NSView {
    var onMouseMoved: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
        super.mouseMoved(with: event)
    }
}

/// A small floating back / forward / reload pill. The buttons are nil-target:
/// their actions resolve through the responder chain to the same
/// BrowserWindowController methods the menu items use (single code path).
final class FloatingToolbar: NSVisualEffectView {
    static let size = NSSize(width: 124, height: 36)

    let backButton: NSButton
    let forwardButton: NSButton
    private(set) var isHovered = false

    init() {
        backButton = Self.makeButton(symbol: "chevron.left", label: "Back",
                                     action: #selector(BrowserWindowController.navigateBack(_:)))
        forwardButton = Self.makeButton(symbol: "chevron.right", label: "Forward",
                                        action: #selector(BrowserWindowController.navigateForward(_:)))
        let reloadButton = Self.makeButton(symbol: "arrow.clockwise", label: "Reload",
                                           action: #selector(BrowserWindowController.reloadPage(_:)))
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        alphaValue = 0

        let buttons = [backButton, forwardButton, reloadButton]
        let buttonWidth = Self.size.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * buttonWidth, y: 0,
                                  width: buttonWidth, height: Self.size.height)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    private static func makeButton(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.toolTip = label
        return button
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}
```

Wire-up in `BrowserWindowController.init`, after the progress-bar wiring
(toolbar must be added LAST so it sits above the web view):

```swift
toolbar.frame.origin = NSPoint(
    x: (containerView.bounds.width - FloatingToolbar.size.width) / 2,
    y: 16
)
toolbar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]  // bottom-center on resize
containerView.addSubview(toolbar)
```

After `super.init(window: window)`:

```swift
containerView.onMouseMoved = { [weak self] in self?.showToolbar() }
```

Autohide helpers — add as private methods on `BrowserWindowController`:

```swift
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
```

## Task 4 — Drag-zone hint (lowest priority — cuttable)

If this task fights back, ship Tasks 1–3 without it and leave the ROADMAP
E item unchecked. The title strip is the real (transparent) titlebar, so the
hint must live in the titlebar via the **public accessory API only**.

In `BrowserWindowController.init`, after `super.init(window: window)`:

```swift
let accessory = NSTitlebarAccessoryViewController()
accessory.layoutAttribute = .right
accessory.view = DragHintView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
window.addTitlebarAccessoryViewController(accessory)
```

New class (append to `FloatingToolbar.swift`):

```swift
/// A faint grabber glyph at the right edge of the (invisible) title strip.
/// Brightens and shows an open-hand cursor on hover, hinting that the strip
/// drags the window.
final class DragHintView: NSView {
    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glyph.image = NSImage(systemSymbolName: "circle.grid.3x3.fill",
                              accessibilityDescription: "Drag to move window")
        glyph.contentTintColor = .tertiaryLabelColor
        glyph.alphaValue = 0.25
        glyph.frame = bounds.insetBy(dx: 7, dy: 7)
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseEntered(with event: NSEvent) { glyph.animator().alphaValue = 0.6 }
    override func mouseExited(with event: NSEvent) { glyph.animator().alphaValue = 0.25 }
}
```

A full-width hover gradient across the strip was considered and **cut**: it
requires private titlebar view hierarchies, which break across macOS
releases.

## Task 5 — EngineVersion

If H1 already bumped `Shared/EngineVersion.swift` to 4 and both ship in the
same release, extend the `4 —` history line with
"; floating toolbar, loading bar, drag hint". If H2 ships separately later,
bump to 5 with its own history line.

---

## Acceptance criteria

1. `Scripts/build.sh` compiles both targets.
2. Generate + launch a test app
   (`--make https://en.wikipedia.org --out /tmp/appseed-test --overwrite`):
   - **Window drag still works** by grabbing the top strip; traffic lights
     unobstructed; page-color tinting of the strip still tracks the site
     (light and dark pages).
   - **Progress bar**: on load, a thin accent-colored bar animates across the
     top of the content area and fades out at completion. Navigate to a heavy
     page to see intermediate progress.
   - **Toolbar**: appears bottom-center on mouse move; fades out ~2s after
     the pointer stops; stays visible while hovered; back/forward buttons
     gray out in sync with the Navigation menu items; all three buttons work.
   - **Drag hint** (if Task 4 shipped): faint grabber at the strip's right
     edge, brightens on hover, open-hand cursor.
   - **Resize** the window: progress bar stays full-width at top, toolbar
     stays bottom-center.
3. OAuth regression: `--make` a Google-login site and sign in — popups still
   work (the container restructure sits next to, but must not affect,
   `NavigationCoordinator`).
4. Quit and relaunch: no crash from KVO/Timer teardown (toolbar timer is
   invalidated in `deinit`).
