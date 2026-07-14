# Spec H3 — Help Tab in Settings (Factory Help Modernization)

**Status:** ready to implement
**Targets:** `AppSeed` (factory) only — **no EngineVersion bump**.
**Depends on:** nothing (independent of H1/H2). One content note: the
"Keyboard shortcuts" section below lists wrapped-app shortcuts added by H1
(`docs/specs/menu-system.md`). If H3 ships *before* H1, omit the rows marked
`(H1)` and add them when H1 lands.

## Context

The factory's Help window is a programmatically built `NSTextView` wall of
hardcoded text (`AppSeed/App/StatusItemController.swift:151-229`). It
duplicates window chrome and reads like utility text. Meanwhile Settings
(`AppSeed/Views/SettingsWindowController.swift`) already has a polished
sidebar + content-pane layout (General / My Apps / About) in the dark HUD
style — About already moved from a separate window into a Settings tab.

**Decision:** fold Help into Settings as a fourth sidebar tab. The standalone
help window is deleted.

### Constraints

- Reuse the visual language of the existing Settings tabs: `HUDStyle` colors,
  13pt semibold accent headings, 11pt secondary captions, `NSBox` separators.
  The reference builders are `SettingsWindowController.heading/caption/separator`
  (lines 570–591) — they are `private`, so `HelpPane` defines its own local
  copies rather than changing their visibility.
- `FlippedView` in `SettingsWindowController.swift` is also `private` —
  `HelpPane` declares its own private equivalent.
- `SettingsWindowController.swift` is already ~695 lines; all Help content
  goes in the **new file**, and the controller grows by only ~15 lines.
- Do not modify `Scripts/build.sh` — it globs `AppSeed/Views/*.swift`.

---

## Task 1 — New file `AppSeed/Views/HelpPane.swift`

```swift
import AppKit

/// The Help tab for the Settings window. Pure construction — call `build`
/// with the current global shortcut string; rebuild to refresh it.
enum HelpPane {
    /// Top-down container so section frames measure from the top edge.
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    static func build(size: NSSize, shortcut: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let inset: CGFloat = 20
        let width = size.width - inset * 2
        let doc = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: size.width, height: 0))
        var y: CGFloat = 8

        addHeading("Create an app from any website", to: doc, y: &y, inset: inset, width: width)
        addBody("""
        1. Press \(shortcut) anywhere (or click the leaf icon and choose New App).
        2. Type or paste a website address — if a link is on your clipboard, it's filled in for you.
        3. Press Return. The website becomes a real Mac app in your Applications folder and opens right away.
        """, to: doc, y: &y, inset: inset, width: width)
        addSeparator(to: doc, y: &y, inset: inset, width: width)

        addHeading("Keyboard shortcuts", to: doc, y: &y, inset: inset, width: width)
        addBody("""
        \(shortcut) — open AppSeed from anywhere (change it in Settings › General).

        Inside any created app:
        ⌘R — reload the page          ⌘[ / ⌘] — back / forward
        ⇧⌘H — go to the home page     ⌘0 / ⌘+ / ⌘− — zoom (H1)
        ⌥⌘R — reload customizations   ⌥⌘E — clear the cache (H1)
        """, to: doc, y: &y, inset: inset, width: width)
        addSeparator(to: doc, y: &y, inset: inset, width: width)

        addHeading("Customize a created app (optional)", to: doc, y: &y, inset: inset, width: width)
        addBody("""
        Inside any created app, choose View ▸ Open Customization Folder…. Drop styles into custom.css or scripts into inject.js, then choose View ▸ Reload Customizations to apply. Your changes survive re-creating the app.
        """, to: doc, y: &y, inset: inset, width: width)
        addCodeBlock("""
        ~/Library/Application Support/AppSeed/
        └── com.appseed.wrapped.<site>/
            ├── custom.css    ← styles added to every page
            └── inject.js     ← script run on every page
        """, to: doc, y: &y, inset: inset, width: width)
        addSeparator(to: doc, y: &y, inset: inset, width: width)

        addHeading("Your logins are safe", to: doc, y: &y, inset: inset, width: width)
        addBody("""
        Each created app keeps its own private cookies and sign-ins, separate from Safari and from other created apps. Re-creating an app for the same website keeps you signed in.
        """, to: doc, y: &y, inset: inset, width: width)
        addSeparator(to: doc, y: &y, inset: inset, width: width)

        addHeading("Install & remove", to: doc, y: &y, inset: inset, width: width)
        addBody("""
        Apps go to your personal Applications folder by default — click the folder line at the bottom of the input card to choose somewhere else.

        To remove an app, open Settings › My Apps and choose Remove — this moves the app and its saved logins to the Trash. (You can also drag it from the Applications folder to the Trash, like any Mac app.)
        """, to: doc, y: &y, inset: inset, width: width)

        doc.frame.size.height = y + 24
        scroll.documentView = doc
        return scroll
    }

    // MARK: - Layout helpers (styles mirror SettingsWindowController's
    // private heading/caption/separator builders — kept local because those
    // are private to the controller)

    private static func addHeading(_ text: String, to parent: NSView, y: inout CGFloat,
                                   inset: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = HUDStyle.accent
        label.frame = NSRect(x: inset, y: y, width: width, height: 18)
        parent.addSubview(label)
        y += 26
    }

    private static func addBody(_ text: String, to parent: NSView, y: inout CGFloat,
                                inset: CGFloat, width: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = HUDStyle.text
        label.isEditable = false
        label.preferredMaxLayoutWidth = width
        let height = label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: inset, y: y, width: width, height: height)
        parent.addSubview(label)
        y += height + 14
    }

    private static func addCodeBlock(_ text: String, to parent: NSView, y: inout CGFloat,
                                     inset: CGFloat, width: CGFloat) {
        let padding: CGFloat = 12
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = HUDStyle.text
        label.isEditable = false
        label.preferredMaxLayoutWidth = width - padding * 2
        let textHeight = label.sizeThatFits(
            NSSize(width: width - padding * 2, height: .greatestFiniteMagnitude)).height

        let box = NSView(frame: NSRect(x: inset, y: y, width: width, height: textHeight + padding * 2))
        box.wantsLayer = true
        box.layer?.backgroundColor = HUDStyle.fieldBackground.cgColor
        box.layer?.cornerRadius = 8
        box.layer?.cornerCurve = .continuous
        label.frame = NSRect(x: padding, y: padding, width: width - padding * 2, height: textHeight)
        box.addSubview(label)
        parent.addSubview(box)
        y += box.frame.height + 14
    }

    private static func addSeparator(to parent: NSView, y: inout CGFloat,
                                     inset: CGFloat, width: CGFloat) {
        let box = NSBox(frame: NSRect(x: inset, y: y + 4, width: width, height: 1))
        box.boxType = .separator
        parent.addSubview(box)
        y += 24
    }
}
```

Note: the code block's `label` sits inside a **non-flipped** `NSView` (`box`),
so `y: padding` is measured from the bottom — for a symmetric padding box the
value is the same either way; leave as written. Replace the `(H1)` markers in
the shortcuts section with nothing once H1 has shipped (or omit those rows if
H1 hasn't).

## Task 2 — Edit `AppSeed/Views/SettingsWindowController.swift`

Five small changes:

1. **Enum** (line 56): add `case help` to `SettingsTab`:
   ```swift
   enum SettingsTab {
       case general
       case myApps
       case about
       case help
   }
   ```

2. **Properties** (with the other layout/navigation properties, lines 90–95):
   ```swift
   private var helpView: NSView!
   private var helpRow: SidebarRow!
   ```

3. **`buildSidebar(into:)`** (line 178): after the `aboutRow` block, add:
   ```swift
   helpRow = SidebarRow(title: "Help", symbol: "questionmark.circle.fill", width: rowWidth)
   helpRow.frame.origin = NSPoint(x: 12, y: 52 + 120)
   helpRow.onClick = { [weak self] in self?.select(.help) }
   sidebar.addSubview(helpRow)
   ```

4. **`buildLayout()`** (line 138): after the `aboutView` block
   (`contentContainer.addSubview(aboutView)`), add:
   ```swift
   helpView = HelpPane.build(size: contentSize,
                             shortcut: HotkeyManager.configuredShortcut().displayString)
   helpView.frame = contentFrame
   contentContainer.addSubview(helpView)
   ```
   And add a rebuild helper (used so the shortcut text stays current after
   the user re-records it):
   ```swift
   /// The Help copy interpolates the current global shortcut — rebuild the
   /// pane on every present so a re-recorded shortcut shows correctly.
   private func rebuildHelp() {
       guard let container = helpView?.superview else { return }
       let frame = helpView.frame
       helpView.removeFromSuperview()
       helpView = HelpPane.build(size: contentSize,
                                 shortcut: HotkeyManager.configuredShortcut().displayString)
       helpView.frame = frame
       container.addSubview(helpView)
   }
   ```

5. **`select(_:)`** (line 212) — add the two Help lines:
   ```swift
   helpView?.isHidden = tab != .help
   helpRow?.setSelected(tab == .help)
   ```
   **`present(selecting:)`** (line 120) — add `rebuildHelp()` alongside the
   other refresh calls, BEFORE `select(tab)`:
   ```swift
   func present(selecting tab: SettingsTab = .general) {
       refreshStartAtLogin()
       refreshShortcut()
       refreshPath()
       rebuildMyApps()
       rebuildHelp()
       select(tab)
       ...
   ```

## Task 3 — Edit `AppSeed/App/StatusItemController.swift`

Delete the old help window entirely:

1. Delete the `private var helpWindow: NSWindow?` property (line 10).
2. Replace the whole `showHelp()` body (lines 136–147) with:
   ```swift
   @objc private func showHelp() {
       SettingsWindowController.shared.present(selecting: .help)
   }
   ```
3. Delete the `// MARK: - Help window` section: `makeHelpWindow()` and
   `helpText()` (lines 149–229). The file ends after `showHelp()`.
4. The menu item itself (line 58, "Help") is unchanged — it still calls
   `showHelp`.

---

## Acceptance criteria

1. `Scripts/build.sh` compiles; `swiftc` reports no unused-symbol warnings
   from the deletion.
2. Menu bar leaf › **Help** opens the Settings window on a **Help** tab whose
   sidebar row (question-mark icon) is selected and styled identically to
   General / My Apps / About.
3. The Help pane scrolls; headings are clay-accent semibold; the directory
   tree renders in a rounded monospaced block; all five sections present:
   Create an app / Keyboard shortcuts / Customize / Logins are safe /
   Install & remove.
4. Change the global shortcut in Settings › General, close Settings, reopen
   via Help — the new shortcut string appears in both the "Create an app"
   step 1 and the shortcuts list.
5. `grep -rn "helpWindow\|makeHelpWindow\|helpText" AppSeed/` returns no
   matches (no orphaned code).
6. Settings still opens correctly on every other tab (`present(selecting:)`
   from the Settings… menu item and from `showHelp`).
