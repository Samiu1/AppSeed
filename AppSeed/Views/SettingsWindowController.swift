import AppKit

/// AppSeed's Settings window: the home for configuration that doesn't belong
/// on the disposable HUD — the global shortcut and the install location.
///
/// Unlike the HUD (a two-second input card), this is a normal titled window
/// that follows the system light/dark appearance. A single shared instance is
/// reused across opens.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var startAtLoginCheckbox: NSButton!
    private var shortcutButton: NSButton!
    private var pathLabel: NSTextField!
    private var recordingMonitor: Any?

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppSeed Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildContent()
    }

    /// Brings the window forward, refreshing all controls to current values.
    func present() {
        refreshStartAtLogin()
        refreshShortcut()
        refreshPath()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let inset: CGFloat = 24
        let width = content.bounds.width - inset * 2

        // Section: General (Start at login)
        let generalHeading = Self.heading("General", y: 288, width: width, inset: inset)
        startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start AppSeed at login", target: self,
                                        action: #selector(toggleStartAtLogin))
        startAtLoginCheckbox.font = .systemFont(ofSize: 13)
        startAtLoginCheckbox.frame = NSRect(x: inset, y: 262, width: width, height: 20)
        let generalDesc = Self.caption(
            "Runs quietly in the background so your shortcut always works.",
            y: 244, width: width, inset: inset)

        let separator1 = NSBox(frame: NSRect(x: inset, y: 224, width: width, height: 1))
        separator1.boxType = .separator

        // Section: Keyboard Shortcut
        let shortcutHeading = Self.heading("Keyboard Shortcut", y: 194, width: width, inset: inset)
        let shortcutDesc = Self.caption(
            "Press this anywhere to open AppSeed.", y: 174, width: width - 120, inset: inset)
        shortcutButton = NSButton(frame: NSRect(x: content.bounds.width - inset - 108, y: 172, width: 108, height: 28))
        shortcutButton.bezelStyle = .rounded
        shortcutButton.setButtonType(.momentaryPushIn)
        shortcutButton.target = self
        shortcutButton.action = #selector(beginRecording)

        let separator2 = NSBox(frame: NSRect(x: inset, y: 144, width: width, height: 1))
        separator2.boxType = .separator

        // Section: Install Location
        let locationHeading = Self.heading("Install Location", y: 114, width: width, inset: inset)
        let locationDesc = Self.caption(
            "New apps are saved here.", y: 94, width: width, inset: inset)
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pathLabel.textColor = .labelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.frame = NSRect(x: inset, y: 64, width: width - 110, height: 20)

        let changeButton = NSButton(frame: NSRect(x: content.bounds.width - inset - 96, y: 60, width: 96, height: 28))
        changeButton.title = "Change…"
        changeButton.bezelStyle = .rounded
        changeButton.target = self
        changeButton.action = #selector(changeInstallLocation)

        let resetButton = NSButton(frame: NSRect(x: inset, y: 22, width: 180, height: 24))
        resetButton.title = "Reset to ~/Applications"
        resetButton.bezelStyle = .inline
        resetButton.controlSize = .small
        resetButton.target = self
        resetButton.action = #selector(resetInstallLocation)

        [generalHeading, startAtLoginCheckbox, generalDesc, separator1,
         shortcutHeading, shortcutDesc, shortcutButton, separator2,
         locationHeading, locationDesc, pathLabel, changeButton, resetButton]
            .forEach(content.addSubview)

        refreshStartAtLogin()
        refreshShortcut()
        refreshPath()
    }

    private static func heading(_ text: String, y: CGFloat, width: CGFloat, inset: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.frame = NSRect(x: inset, y: y, width: width, height: 18)
        return label
    }

    private static func caption(_ text: String, y: CGFloat, width: CGFloat, inset: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: inset, y: y, width: width, height: 15)
        return label
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
            // Revert the checkbox to the true system state and explain.
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
