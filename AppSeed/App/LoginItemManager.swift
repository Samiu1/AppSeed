import Foundation
import ServiceManagement

/// Start-at-login control via the modern `SMAppService` API (macOS 13+).
///
/// For a background agent, `SMAppService.mainApp` registers the app itself as
/// a login item — no separate helper bundle or privileged daemon. macOS shows
/// the resulting item under System Settings › General › Login Items, where the
/// user can also toggle it; `isEnabled` reflects that live state.
enum LoginItemManager {
    /// Whether AppSeed is currently set to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters AppSeed as a login item. Throws so the caller
    /// can surface the failure — e.g. when the user has the item disabled at
    /// the system level (`.requiresApproval`) and macOS blocks the change.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// True when macOS is holding the login item in a "needs user approval"
    /// state — the caller should point the user at System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
