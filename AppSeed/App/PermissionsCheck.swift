import AppKit
import ApplicationServices

/// First-launch permission surface, per the Phase 0 decisions.
///
/// Note for maintainers: Carbon's RegisterEventHotKey does not itself require
/// Accessibility access on current macOS — but the product spec requires
/// surfacing the permission state in plain language on first launch so a
/// denied shortcut can never fail silently. Registration failures are also
/// reported visibly by FactoryAppDelegate, independent of this check.
enum AccessibilityAdvisor {
    private static let firstLaunchKey = "didRunAccessibilityCheck"
    private static let settingsDeepLink =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static func runFirstLaunchCheck() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstLaunchKey) else { return }
        defaults.set(true, forKey: firstLaunchKey)

        guard !AXIsProcessTrusted() else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AppSeed needs Accessibility access to listen for your shortcut"
        alert.informativeText = """
        AppSeed runs invisibly in the background and appears when you press \
        \(HotkeyManager.configuredShortcut().displayString). Granting Accessibility access in \
        System Settings › Privacy & Security › Accessibility makes sure the shortcut always works.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: settingsDeepLink) {
            NSWorkspace.shared.open(url)
        }
    }
}
