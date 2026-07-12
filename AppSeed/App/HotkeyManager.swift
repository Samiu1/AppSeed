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

    private static let keyCodeDefaultsKey = "hotkeyKeyCode"
    private static let modifiersDefaultsKey = "hotkeyModifiers"

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

    /// ⌥P by default. Recorded via the HUD's shortcut chip; also settable
    /// without a UI:
    ///   defaults write com.appseed.factory hotkeyKeyCode -int <virtual key code>
    ///   defaults write com.appseed.factory hotkeyModifiers -int <carbon modifier mask>
    static func configuredShortcut() -> Shortcut {
        let defaults = UserDefaults.standard
        let keyCode = (defaults.object(forKey: keyCodeDefaultsKey) as? NSNumber)?.uint32Value
            ?? UInt32(kVK_ANSI_P)
        let modifiers = (defaults.object(forKey: modifiersDefaultsKey) as? NSNumber)?.uint32Value
            ?? UInt32(optionKey)
        return Shortcut(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            displayString: describe(keyCode: keyCode, modifiers: modifiers)
        )
    }

    func register(onPress handler: @escaping () -> Void) throws {
        onPress = handler
        try installHandlerIfNeeded()
        try registerConfiguredHotKey()
    }

    /// Live re-bind from the HUD's shortcut recorder: persists the new combo,
    /// drops the old registration, and registers the new one. Throws (and
    /// keeps the previous defaults values would-be stale but harmless) if the
    /// new combo is taken by another app.
    func updateShortcut(keyCode: UInt32, carbonModifiers: UInt32) throws {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersDefaultsKey)
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        try registerConfiguredHotKey()
    }

    // MARK: - Registration internals

    private func installHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
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
        guard status == noErr else {
            throw HotkeyError.handlerInstallFailed(status)
        }
    }

    private func registerConfiguredHotKey() throws {
        let shortcut = Self.configuredShortcut()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4150_5344) /* 'APSD' */, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            throw HotkeyError.registrationFailed(status)
        }
    }

    // MARK: - Modifier / key-name mapping

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    /// True when the mask contains a "real" modifier — recording requires
    /// ⌘/⌥/⌃ so plain typing (or shift-typing) can't become the hotkey.
    static func hasNonShiftModifier(_ carbonModifiers: UInt32) -> Bool {
        carbonModifiers & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
    }

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + (keyNames[keyCode] ?? "key\(keyCode)")
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]
}
