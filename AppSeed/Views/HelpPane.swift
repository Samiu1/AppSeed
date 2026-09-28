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
        ⇧⌘H — go to the home page     ⌘0 / ⌘+ / ⌘− — zoom
        ⌥⌘R — reload customizations   ⌥⌘E — clear the cache
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
