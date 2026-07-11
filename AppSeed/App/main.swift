import AppKit

// AppSeed — the factory. A background (LSUIElement) agent with no Dock icon:
// summoned via the global hotkey (⌥P by default), it shows a floating HUD
// that turns a URL into a standalone native .app in under a second.

// Hidden CLI mode (`AppSeed --make <url> ...`) for scripting and end-to-end
// testing without the HUD. Exits the process when it handles the invocation.
HeadlessFactoryCLI.runIfRequested()

let app = NSApplication.shared
// LSUIElement=YES in Info.plist is the authoritative no-Dock-icon setting
// (set at build time — hiding at runtime would flash an icon on launch).
// The explicit policy here only covers running the bare binary in development.
app.setActivationPolicy(.accessory)

let delegate = FactoryAppDelegate()
app.delegate = delegate
app.run()
