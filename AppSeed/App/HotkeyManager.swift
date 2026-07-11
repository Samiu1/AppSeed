import AppKit
import Carbon

/// System-wide hotkey via Carbon's RegisterEventHotKey +
/// InstallEventHandler on the application event target.
///
/// This is the correct native mechanism for an LSUIElement background agent:
/// the shortcut must fire while AppSeed is NOT the focused app. SwiftUI's
/// .keyboardShortcut and NSEvent *local* monitors only fire when the app is
/// focused and would break the trigger entirely. Carbon is deprecated but
/// remains the supported native path — do not "modernize" this away, and do
/// not replace it with a third-party wrapper like MASShortcut.
final class HotkeyManager {
    static let shared = HotkeyManager()

    struct Shortcut {
        var keyCode: UInt32
        var carbonModifiers: UInt32
        var displayString: String
    }

    enum HotkeyError: LocalizedError {
        case handlerInstallFailed(OSStatus)
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .handlerInstallFailed(let status):
                return "Installing the keyboard event handler failed (OSStatus \(status))."
            case .registrationFailed(let status):
                return "Registering the shortcut failed (OSStatus \(status)). Another app may already own it."
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?

    private init() {}

    /// ⌥P by default. Customizable without a UI via:
    ///   defaults write com.appseed.factory hotkeyKeyCode -int <virtual key code>
    ///   defaults write com.appseed.factory hotkeyModifiers -int <carbon modifier mask>
    /// (e.g. optionKey = 2048, cmdKey = 256, controlKey = 4096, shiftKey = 512)
    static func configuredShortcut() -> Shortcut {
        let defaults = UserDefaults.standard
        let keyCode = (defaults.object(forKey: "hotkeyKeyCode") as? NSNumber)?.uint32Value
            ?? UInt32(kVK_ANSI_P)
        let modifiers = (defaults.object(forKey: "hotkeyModifiers") as? NSNumber)?.uint32Value
            ?? UInt32(optionKey)
        return Shortcut(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            displayString: describe(keyCode: keyCode, modifiers: modifiers)
        )
    }

    func register(onPress handler: @escaping () -> Void) throws {
        onPress = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPress?() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            throw HotkeyError.handlerInstallFailed(installStatus)
        }

        let shortcut = Self.configuredShortcut()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4150_5344) /* 'APSD' */, id: 1)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            throw HotkeyError.registrationFailed(registerStatus)
        }
    }

    private static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        let keyNames: [UInt32: String] = [
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
        ]
        return parts + (keyNames[keyCode] ?? "key \(keyCode)")
    }
}
