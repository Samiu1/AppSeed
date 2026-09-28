import AppKit

/// Menu bar presence for AppSeed. A deliberate amendment to the original
/// "exists only when invoked" model: non-technical users need a visible,
/// clickable home for the app — the status item is the discoverable path to
/// everything the hotkey does, plus Help and About.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let hud: HUDController
    private let menu = NSMenu()

    init(hud: HUDController) {
        self.hud = hud
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.toolTip = "AppSeed — turn any website into a Mac app"
        }
        menu.autoenablesItems = false
        menu.delegate = self
        populateMenu() // initial fill; rebuilt on every open by menuWillOpen
        statusItem.menu = menu
    }

    // MARK: - Menu

    /// Rebuilt on every open so the shortcut hint and the "My Apps" list stay
    /// current (apps are created/removed while AppSeed runs).
    private func populateMenu() {
        menu.removeAllItems()

        // Show the global shortcut right-aligned, like the other rows. It's
        // display-only here — the always-on trigger is the Carbon hotkey.
        let shortcut = HotkeyManager.menuKeyEquivalent()
        let newApp = NSMenuItem(title: "New App", action: #selector(showHUD), keyEquivalent: shortcut.key)
        newApp.keyEquivalentModifierMask = shortcut.modifiers
        newApp.target = self
        menu.addItem(newApp)

        menu.addItem(.separator())

        // Only surface the favourites section when there are favourites — an
        // empty "My Apps" header just adds noise. Full management is in
        // Settings › My Apps regardless.
        let favorites = WrappedAppsRegistry.installed().filter { FavoritesStore.isFavorite($0.bundleID) }
        if !favorites.isEmpty {
            addFavoritesSection(favorites)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let help = NSMenuItem(title: "Help", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// "My Apps" header + one launch item per favourited app. Only called when
    /// there is at least one favourite (the menu stays clean otherwise).
    private func addFavoritesSection(_ favorites: [WrappedApp]) {
        let header = NSMenuItem(title: "My Apps", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for app in favorites {
            let item = NSMenuItem(title: app.name, action: #selector(openWrappedApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app
            item.image = Self.appIcon(for: app.path)
            menu.addItem(item)
        }
        // Full app management (favouriting, remove, updates) lives in
        // Settings › My Apps — reachable via the Settings… item below.
    }

    /// A wrapped app's own icon, sized for a menu row.
    private static func appIcon(for path: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
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
        // Rebuild so the shortcut hint and the "My Apps" list reflect the
        // current state (apps created/removed, shortcut re-recorded).
        populateMenu()
    }

    // MARK: - Actions

    @objc private func showHUD() {
        hud.show()
    }

    // MARK: - My Apps actions

    /// Launch a favourited app straight from the menu.
    @objc private func openWrappedApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? WrappedApp else { return }
        NSWorkspace.shared.openApplication(at: app.path, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.present(selecting: .general)
    }

    @objc private func showHelp() {
        SettingsWindowController.shared.present(selecting: .help)
    }
}
