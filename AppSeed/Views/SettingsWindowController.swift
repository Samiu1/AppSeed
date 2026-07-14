import AppKit

/// A top-down (flipped) container so absolute frames can be measured from the
/// top edge — stable regardless of how tall the content area ends up.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A clickable sidebar navigation row: icon + label with a selection pill.
private final class SidebarRow: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(title: String, symbol: String, width: CGFloat, iconTintWhenIdle: NSColor = HUDStyle.secondaryText) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        self.iconTintWhenIdle = iconTintWhenIdle

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.frame = NSRect(x: 12, y: 8, width: 18, height: 18)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 38, y: 8, width: width - 46, height: 18)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        setSelected(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var iconTintWhenIdle: NSColor = HUDStyle.secondaryText

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (selected ? HUDStyle.fieldBackground : .clear).cgColor
        label.textColor = selected ? HUDStyle.text : HUDStyle.secondaryText
        iconView.contentTintColor = selected ? HUDStyle.accent : iconTintWhenIdle
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Which Settings section to show when opening.
enum SettingsTab {
    case general
    case myApps
    case about
}

/// AppSeed's Settings window: a sidebar + content-pane window.
///
///  - General: the global shortcut, start-at-login, and install location.
///  - My Apps: the full list of created apps, with favouriting (favourites are
///    what the menu bar shows), Show in Finder, Remove, and — only when some
///    app is on an older engine — Update All.
///
/// A single shared instance is reused across opens. The title bar is hidden
/// (full-size content) so the sidebar runs edge-to-top with the traffic
/// lights floating over it, matching the dark HUD aesthetic.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    // General controls
    private var startAtLoginCheckbox: NSButton!
    private var shortcutButton: NSButton!
    private var pathLabel: NSTextField!
    private var recordingMonitor: Any?

    // My Apps controls
    private var appsListStack: FlippedView!
    private var appsScrollView: NSScrollView!
    private var updateStatusLabel: NSTextField!
    private var updateButton: NSButton!
    /// Backing array for the current rows; row buttons reference apps by tag.
    private var currentApps: [WrappedApp] = []

    // Layout / navigation
    private var generalView: NSView!
    private var myAppsView: NSView!
    private var aboutView: NSView!
    private var generalRow: SidebarRow!
    private var myAppsRow: SidebarRow!
    private var aboutRow: SidebarRow!

    private let windowSize = NSSize(width: 640, height: 460)
    private let sidebarWidth: CGFloat = 176
    private let contentTopInset: CGFloat = 24

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 640, height: 460)),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AppSeed Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = HUDStyle.surface
        self.init(window: window)
        window.delegate = self
        buildLayout()
    }

    /// Brings the window forward on the requested section, refreshing everything.
    func present(selecting tab: SettingsTab = .general) {
        refreshStartAtLogin()
        refreshShortcut()
        refreshPath()
        rebuildMyApps()
        select(tab)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private var contentSize: NSSize {
        NSSize(width: windowSize.width - sidebarWidth - 1, height: windowSize.height - contentTopInset)
    }

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        // Sidebar (darker), pinned to the full height on the left.
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: windowSize.height))
        sidebar.autoresizingMask = [.height]
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = HUDStyle.sidebarBackground.cgColor
        content.addSubview(sidebar)
        buildSidebar(into: sidebar)

        // Hairline separator between sidebar and content.
        let divider = NSView(frame: NSRect(x: sidebarWidth, y: 0, width: 1, height: windowSize.height))
        divider.autoresizingMask = [.height]
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        content.addSubview(divider)

        // Content container fills the rest; each section view is placed below
        // the (invisible) title-bar strip and toggled by selection.
        let contentContainer = FlippedView(frame: NSRect(
            x: sidebarWidth + 1, y: 0,
            width: windowSize.width - sidebarWidth - 1, height: windowSize.height))
        contentContainer.autoresizingMask = [.width, .height]
        content.addSubview(contentContainer)

        let contentFrame = NSRect(x: 0, y: contentTopInset, width: contentSize.width, height: contentSize.height)
        generalView = buildGeneralTab(size: contentSize)
        generalView.frame = contentFrame
        myAppsView = buildMyAppsTab(size: contentSize)
        myAppsView.frame = contentFrame
        aboutView = buildAboutTab(size: contentSize)
        aboutView.frame = contentFrame
        contentContainer.addSubview(generalView)
        contentContainer.addSubview(myAppsView)
        contentContainer.addSubview(aboutView)

        select(.general)
    }

    private func buildSidebar(into sidebar: FlippedView) {
        let rowWidth = sidebarWidth - 24
        generalRow = SidebarRow(title: "General", symbol: "gearshape.fill", width: rowWidth)
        generalRow.frame.origin = NSPoint(x: 12, y: 52)
        generalRow.onClick = { [weak self] in self?.select(.general) }
        sidebar.addSubview(generalRow)

        myAppsRow = SidebarRow(title: "My Apps", symbol: "square.grid.2x2.fill", width: rowWidth)
        myAppsRow.frame.origin = NSPoint(x: 12, y: 52 + 40)
        myAppsRow.onClick = { [weak self] in self?.select(.myApps) }
        sidebar.addSubview(myAppsRow)

        aboutRow = SidebarRow(title: "About", symbol: "info.circle.fill", width: rowWidth)
        aboutRow.frame.origin = NSPoint(x: 12, y: 52 + 80)
        aboutRow.onClick = { [weak self] in self?.select(.about) }
        sidebar.addSubview(aboutRow)

        // Footer branding (non-interactive): leaf + version, pinned bottom-left.
        let footer = SidebarRow(title: "AppSeed \(Self.appShortVersion)", symbol: "leaf.fill",
                                width: rowWidth, iconTintWhenIdle: HUDStyle.accent)
        footer.frame.origin = NSPoint(x: 12, y: windowSize.height - 46)
        sidebar.addSubview(footer)
    }

    private func select(_ tab: SettingsTab) {
        generalView?.isHidden = tab != .general
        myAppsView?.isHidden = tab != .myApps
        aboutView?.isHidden = tab != .about
        generalRow?.setSelected(tab == .general)
        myAppsRow?.setSelected(tab == .myApps)
        aboutRow?.setSelected(tab == .about)
    }

    private static var appShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - General section

    private func buildGeneralTab(size: NSSize) -> NSView {
        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        root.autoresizingMask = [.width, .height]
        let inset: CGFloat = 20
        let width = size.width - inset * 2

        let generalHeading = Self.heading("General", top: 20, width: width, inset: inset)
        startAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: self,
                                        action: #selector(toggleStartAtLogin))
        startAtLoginCheckbox.attributedTitle = NSAttributedString(
            string: "Start AppSeed at login",
            attributes: [
                .foregroundColor: HUDStyle.text,
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        startAtLoginCheckbox.frame = NSRect(x: inset, y: 46, width: width, height: 20)
        let generalDesc = Self.caption(
            "Runs quietly in the background so your shortcut always works.",
            top: 70, width: width, inset: inset)

        let separator1 = Self.separator(top: 96, width: width, inset: inset)

        let shortcutHeading = Self.heading("Keyboard Shortcut", top: 116, width: width, inset: inset)
        let shortcutDesc = Self.caption("Press this anywhere to open AppSeed.", top: 140, width: width - 120, inset: inset)
        shortcutButton = NSButton(frame: NSRect(x: size.width - inset - 120, y: 132, width: 120, height: 28))
        shortcutButton.bezelStyle = .rounded
        shortcutButton.setButtonType(.momentaryPushIn)
        shortcutButton.target = self
        shortcutButton.action = #selector(beginRecording)

        let separator2 = Self.separator(top: 176, width: width, inset: inset)

        let locationHeading = Self.heading("Install Location", top: 196, width: width, inset: inset)
        let locationDesc = Self.caption("New apps are saved here.", top: 220, width: width, inset: inset)
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pathLabel.textColor = HUDStyle.text
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.frame = NSRect(x: inset, y: 244, width: width - 110, height: 20)

        let changeButton = NSButton(frame: NSRect(x: size.width - inset - 96, y: 240, width: 96, height: 28))
        changeButton.title = "Change…"
        changeButton.bezelStyle = .rounded
        changeButton.target = self
        changeButton.action = #selector(changeInstallLocation)

        let resetButton = NSButton(frame: NSRect(x: inset, y: 276, width: 190, height: 24))
        resetButton.attributedTitle = NSAttributedString(
            string: "Reset to ~/Applications",
            attributes: [
                .foregroundColor: HUDStyle.text,
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        resetButton.bezelStyle = .inline
        resetButton.controlSize = .small
        resetButton.target = self
        resetButton.action = #selector(resetInstallLocation)

        [generalHeading, startAtLoginCheckbox, generalDesc, separator1,
         shortcutHeading, shortcutDesc, shortcutButton, separator2,
         locationHeading, locationDesc, pathLabel, changeButton, resetButton]
            .forEach(root.addSubview)
        return root
    }

    // MARK: - About section

    /// Inline About pane: app icon, name, version/build, description, copyright,
    /// centered in the content area.
    private func buildAboutTab(size: NSSize) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: size.width - 48),
        ])

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),
        ])
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(14, after: iconView)

        let name = NSTextField(labelWithString: "AppSeed")
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = HUDStyle.text
        name.alignment = .center
        stack.addArrangedSubview(name)

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (Build \(build))")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = HUDStyle.secondaryText
        versionLabel.alignment = .center
        stack.addArrangedSubview(versionLabel)
        stack.setCustomSpacing(16, after: versionLabel)

        let desc = NSTextField(wrappingLabelWithString: "Turn any website into a lightweight Mac app.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = HUDStyle.text
        desc.alignment = .center
        desc.isEditable = false
        desc.drawsBackground = false
        desc.isBordered = false
        desc.preferredMaxLayoutWidth = size.width - 96
        stack.addArrangedSubview(desc)
        stack.setCustomSpacing(16, after: desc)

        let copyright = NSTextField(labelWithString: "© 2026 Samiul Islam")
        copyright.font = .systemFont(ofSize: 10)
        copyright.textColor = HUDStyle.secondaryText
        copyright.alignment = .center
        stack.addArrangedSubview(copyright)

        return root
    }

    // MARK: - My Apps tab

    private func buildMyAppsTab(size: NSSize) -> NSView {
        let root = FlippedView(frame: NSRect(origin: .zero, size: size))
        root.autoresizingMask = [.width, .height]
        let inset: CGFloat = 20
        let width = size.width - inset * 2

        let heading = Self.heading("My Apps", top: 20, width: width, inset: inset)
        let caption = Self.caption(
            "Star an app to show it in the menu bar for quick launching.",
            top: 44, width: width, inset: inset)

        let openFolderButton = NSButton(frame: NSRect(x: size.width - inset - 150, y: 14, width: 150, height: 26))
        openFolderButton.title = "Open Apps Folder"
        openFolderButton.bezelStyle = .rounded
        openFolderButton.controlSize = .small
        openFolderButton.target = self
        openFolderButton.action = #selector(openAppsFolder)

        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = .systemFont(ofSize: 12)
        updateStatusLabel.textColor = HUDStyle.secondaryText
        updateStatusLabel.lineBreakMode = .byTruncatingTail
        updateStatusLabel.frame = NSRect(x: inset, y: 72, width: width - 130, height: 18)

        updateButton = NSButton(frame: NSRect(x: size.width - inset - 120, y: 66, width: 120, height: 28))
        updateButton.title = "Update All"
        updateButton.bezelStyle = .rounded
        updateButton.target = self
        updateButton.action = #selector(updateAllApps)

        let separator = Self.separator(top: 104, width: width, inset: inset)

        // Scrollable list fills the remaining height and grows with the window.
        let listTop: CGFloat = 116
        appsScrollView = NSScrollView(frame: NSRect(
            x: inset, y: listTop, width: width, height: size.height - listTop - 16))
        appsScrollView.autoresizingMask = [.width, .height]
        appsScrollView.hasVerticalScroller = true
        appsScrollView.drawsBackground = false
        appsScrollView.borderType = .noBorder

        appsListStack = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        appsListStack.autoresizingMask = [.width]
        appsScrollView.documentView = appsListStack

        [heading, caption, openFolderButton, updateStatusLabel, updateButton, separator, appsScrollView]
            .forEach(root.addSubview)
        return root
    }

    @objc private func openAppsFolder() {
        let directory = AppFactory.defaultInstallDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    /// Rebuilds the app list and the update banner from disk.
    private func rebuildMyApps() {
        guard let appsListStack else { return }
        appsListStack.subviews.forEach { $0.removeFromSuperview() }

        let apps = WrappedAppsRegistry.installed()
        currentApps = apps

        // Update banner state.
        let stale = apps.filter { $0.needsUpdate }.count
        if stale > 0 {
            updateStatusLabel.stringValue = stale == 1
                ? "1 app can be updated to the latest version."
                : "\(stale) apps can be updated to the latest version."
            updateButton.isHidden = false
        } else {
            updateStatusLabel.stringValue = apps.isEmpty
                ? "No apps yet — create one with the shortcut."
                : "All apps are up to date."
            updateButton.isHidden = true
        }

        // Rows.
        let rowHeight: CGFloat = 54
        let width = appsScrollView.contentSize.width
        for (index, app) in apps.enumerated() {
            let row = makeAppRow(app, index: index, width: width, y: CGFloat(index) * rowHeight, height: rowHeight)
            appsListStack.addSubview(row)
        }
        let totalHeight = max(CGFloat(apps.count) * rowHeight, appsScrollView.contentSize.height)
        appsListStack.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
    }

    private func makeAppRow(_ app: WrappedApp, index: Int, width: CGFloat, y: CGFloat, height: CGFloat) -> NSView {
        let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: height))
        row.autoresizingMask = [.width]

        let star = NSButton(frame: NSRect(x: 4, y: 15, width: 24, height: 24))
        star.isBordered = false
        star.bezelStyle = .regularSquare
        star.imagePosition = .imageOnly
        let starred = FavoritesStore.isFavorite(app.bundleID)
        star.image = NSImage(systemSymbolName: starred ? "star.fill" : "star",
                             accessibilityDescription: starred ? "Favourited" : "Not favourited")
        star.contentTintColor = starred ? .systemYellow : HUDStyle.secondaryText
        star.toolTip = starred ? "Shown in the menu bar" : "Show in the menu bar"
        star.target = self
        star.action = #selector(toggleFavorite(_:))
        star.tag = index

        let icon = NSImageView(frame: NSRect(x: 34, y: 11, width: 32, height: 32))
        icon.image = NSWorkspace.shared.icon(forFile: app.path.path)

        let name = NSTextField(labelWithString: app.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = HUDStyle.text
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: 76, y: 9, width: width - 76 - 180, height: 18)

        let subtitle = app.needsUpdate ? "update available" : ""
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = app.needsUpdate ? HUDStyle.errorText : HUDStyle.secondaryText
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: 76, y: 28, width: width - 76 - 180, height: 15)

        let remove = NSButton(frame: NSRect(x: width - 84, y: 14, width: 72, height: 26))
        remove.title = "Remove"
        remove.bezelStyle = .rounded
        remove.controlSize = .small
        remove.font = .systemFont(ofSize: 11)
        remove.target = self
        remove.action = #selector(removeApp(_:))
        remove.tag = index

        let reveal = NSButton(frame: NSRect(x: width - 84 - 34, y: 14, width: 28, height: 26))
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder")
        reveal.bezelStyle = .rounded
        reveal.controlSize = .small
        reveal.toolTip = "Show in Finder"
        reveal.target = self
        reveal.action = #selector(revealApp(_:))
        reveal.tag = index

        [star, icon, name, sub, reveal, remove].forEach(row.addSubview)
        return row
    }

    // MARK: - My Apps actions

    /// Row buttons carry their app's index in `tag`.
    private func app(for sender: NSButton) -> WrappedApp? {
        currentApps.indices.contains(sender.tag) ? currentApps[sender.tag] : nil
    }

    @objc private func toggleFavorite(_ sender: NSButton) {
        guard let app = app(for: sender) else { return }
        FavoritesStore.toggle(app.bundleID)
        rebuildMyApps()
    }

    @objc private func revealApp(_ sender: NSButton) {
        guard let app = app(for: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.path])
    }

    @objc private func removeApp(_ sender: NSButton) {
        guard let app = app(for: sender) else { return }
        let confirm = NSAlert()
        confirm.messageText = "Remove \(app.name)?"
        confirm.informativeText = """
        This moves \(app.name) and its saved logins and data to the Trash. \
        You can restore it from the Trash until it's emptied.
        """
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Move to Trash")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try WrappedAppsRegistry.remove(app)
            FavoritesStore.setFavorite(false, bundleID: app.bundleID) // tidy up
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Couldn't remove \(app.name)"
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: "OK")
            failure.runModal()
        }
        rebuildMyApps()
    }

    @objc private func updateAllApps() {
        let confirm = NSAlert()
        confirm.messageText = "Update apps to the latest version?"
        confirm.informativeText = """
        This rebuilds apps that are on an older version. Any open apps will \
        restart, and your logins are kept.
        """
        confirm.addButton(withTitle: "Update")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        // Refresh the list once the batch finishes so the banner clears.
        UpdateProgressWindowController.shared.run { [weak self] in
            self?.rebuildMyApps()
        }
    }

    // MARK: - Reusable bits (top-anchored, for flipped containers)

    private static func heading(_ text: String, top: CGFloat, width: CGFloat, inset: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = HUDStyle.accent
        label.frame = NSRect(x: inset, y: top, width: width, height: 18)
        return label
    }

    private static func caption(_ text: String, top: CGFloat, width: CGFloat, inset: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = HUDStyle.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: inset, y: top, width: width, height: 15)
        return label
    }

    private static func separator(top: CGFloat, width: CGFloat, inset: CGFloat) -> NSBox {
        let box = NSBox(frame: NSRect(x: inset, y: top, width: width, height: 1))
        box.boxType = .separator
        return box
    }

    // MARK: - Start at login

    private func refreshStartAtLogin() {
        startAtLoginCheckbox?.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func toggleStartAtLogin() {
        let wantEnabled = startAtLoginCheckbox.state == .on
        do {
            try LoginItemManager.setEnabled(wantEnabled)
        } catch {
            refreshStartAtLogin()
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login setting"
            alert.informativeText = LoginItemManager.requiresApproval
                ? "macOS needs your approval first. Open System Settings › General › Login Items and enable AppSeed there."
                : error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Shortcut recording

    private func refreshShortcut() {
        shortcutButton?.title = HotkeyManager.configuredShortcut().displayString
    }

    /// Click → the next key combo pressed becomes the global shortcut. Must
    /// include ⌘/⌥/⌃ so plain typing can't be captured; Esc cancels. The local
    /// monitor is valid because this window is key while recording (the
    /// always-on trigger itself stays Carbon, in HotkeyManager).
    @objc private func beginRecording() {
        guard recordingMonitor == nil else { return }
        shortcutButton.title = "Press keys…"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleRecordingKeyDown(event)
            return nil // consume
        }
    }

    private func handleRecordingKeyDown(_ event: NSEvent) {
        if event.keyCode == UInt16(53) { // esc — cancel
            endRecording()
            return
        }
        let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
        guard HotkeyManager.hasNonShiftModifier(modifiers) else {
            shortcutButton.title = "Add ⌘, ⌥, or ⌃…"
            return
        }
        do {
            try HotkeyManager.shared.updateShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't set that shortcut"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        endRecording()
    }

    private func endRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        refreshShortcut()
    }

    func windowDidResignKey(_ notification: Notification) {
        endRecording() // never leave a dangling key monitor
    }

    func windowWillClose(_ notification: Notification) {
        endRecording()
    }

    // MARK: - Install location

    private func refreshPath() {
        pathLabel?.stringValue = AppFactory.displayPath(for: AppFactory.defaultInstallDirectory)
    }

    @objc private func changeInstallLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose where new apps are saved"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppFactory.defaultInstallDirectory
        if panel.runModal() == .OK, let selected = panel.url {
            AppFactory.defaultInstallDirectory = selected
            refreshPath()
        }
    }

    @objc private func resetInstallLocation() {
        AppFactory.defaultInstallDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        refreshPath()
    }
}
