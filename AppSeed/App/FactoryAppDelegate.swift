import AppKit

final class FactoryAppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUDController()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityAdvisor.runFirstLaunchCheck()

        // Menu bar home: visible whenever AppSeed runs, since the app has no
        // Dock icon (LSUIElement) and would otherwise be invisible.
        statusItemController = StatusItemController(hud: hud)

        do {
            try HotkeyManager.shared.register { [weak self] in
                self?.hud.toggle()
            }
        } catch {
            // The hotkey must fail visibly, never silently.
            presentHotkeyFailure(error)
        }

        // AppSeed has no Dock icon or menu bar item; opening it from Finder is
        // itself an invocation, so show the HUD immediately.
        hud.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hud.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func presentHotkeyFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Global shortcut unavailable"
        alert.informativeText = """
        AppSeed could not register its global shortcut (\(HotkeyManager.configuredShortcut().displayString)).

        \(error.localizedDescription)

        You can still open AppSeed by double-clicking it in Finder.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
