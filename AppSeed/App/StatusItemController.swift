import AppKit

/// Menu bar presence for AppSeed. A deliberate amendment to the original
/// "exists only when invoked" model: non-technical users need a visible,
/// clickable home for the app — the status item is the discoverable path to
/// everything the hotkey does, plus Help and About.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let hud: HUDController
    private var helpWindow: NSWindow?
    private let shortcutHintItem = NSMenuItem()

    init(hud: HUDController) {
        self.hud = hud
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.toolTip = "AppSeed — turn any website into a Mac app"
        }
        statusItem.menu = buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let newApp = NSMenuItem(title: "New App…", action: #selector(showHUD), keyEquivalent: "")
        newApp.target = self
        menu.addItem(newApp)

        shortcutHintItem.isEnabled = false
        menu.addItem(shortcutHintItem)

        menu.addItem(.separator())

        let openFolder = NSMenuItem(title: "Open Apps Folder", action: #selector(openInstallFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let help = NSMenuItem(title: "AppSeed Help", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        let about = NSMenuItem(title: "About AppSeed", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit AppSeed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    /// The AppSeed leaf, rendered from Resources/MenuBarLeaf.png (built from
    /// leaf.svg). Sized to the standard 18pt menu bar height and marked as a
    /// template so macOS tints it for light/dark menu bars. Falls back to the
    /// system leaf symbol if the asset is somehow missing.
    private static func menuBarIcon() -> NSImage {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "MenuBarLeaf", withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "AppSeed")
                ?? NSImage()
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh on every open — the user can re-record the shortcut at any time.
        shortcutHintItem.title = "Shortcut: \(HotkeyManager.configuredShortcut().displayString)"
    }

    // MARK: - Actions

    @objc private func showHUD() {
        hud.show()
    }

    @objc private func openInstallFolder() {
        let directory = AppFactory.defaultInstallDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Turn any website into a lightweight Mac app.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }

    @objc private func showHelp() {
        if let helpWindow {
            NSApp.activate(ignoringOtherApps: true)
            helpWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = Self.makeHelpWindow()
        helpWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Help window

    private static func makeHelpWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppSeed Help"
        window.isReleasedWhenClosed = false

        let scrollView = NSScrollView(frame: window.contentLayoutRect)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(helpText())
        scrollView.documentView = textView
        window.contentView = scrollView
        return window
    }

    private static func helpText() -> NSAttributedString {
        let shortcut = HotkeyManager.configuredShortcut().displayString
        let text = NSMutableAttributedString()

        func heading(_ string: String) {
            text.append(NSAttributedString(string: string + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        func body(_ string: String) {
            text.append(NSAttributedString(string: string + "\n\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }

        heading("Create an app from any website")
        body("""
        1. Press \(shortcut) anywhere (or click the leaf icon and choose New App…).
        2. Type or paste a website address — if a link is on your clipboard, it's filled in for you.
        3. Press Return. The website becomes a real Mac app in your Applications folder and opens right away.
        """)

        heading("Your logins are safe")
        body("""
        Each created app keeps its own private cookies and sign-ins, separate from Safari and from other created apps. Re-creating an app for the same website keeps you signed in.
        """)

        heading("Change the keyboard shortcut")
        body("""
        Open the input card, click the shortcut badge in its top-right corner, then press the new key combination (it must include ⌘, ⌥, or ⌃).
        """)

        heading("Customize a created app (optional)")
        body("""
        Inside any created app, choose View ▸ Open Customization Folder…. Drop styles into custom.css or scripts into inject.js, then choose View ▸ Reload Customizations to apply. Your changes survive re-creating the app.
        """)

        heading("Where apps are installed")
        body("""
        Apps go to your personal Applications folder by default. Click the folder line at the bottom of the input card to choose somewhere else.
        """)

        heading("Removing an app")
        body("""
        Drag it from the Applications folder to the Trash, like any Mac app.
        """)

        return text
    }
}
