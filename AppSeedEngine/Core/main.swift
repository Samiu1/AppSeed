import AppKit

// AppSeedEngine — the blueprint runtime cloned by the AppSeed factory.
// Reads AppConfig.json from its own Resources and renders the configured
// site in a native, title-barless WKWebView window.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = EngineAppDelegate()
app.delegate = delegate
app.run()
