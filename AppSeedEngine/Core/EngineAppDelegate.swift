import AppKit

final class EngineAppDelegate: NSObject, NSApplicationDelegate {
    private var browserWindowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let config = try AppConfig.loadFromMainBundle()
            // Creates ~/Library/Application Support/AppSeed/<bundle id>/ with
            // commented inject.js / custom.css templates on first launch.
            ResourceInjector.ensureCustomizationTemplates()
            NSApp.mainMenu = EngineMainMenu.make(appName: config.appName)
            let controller = BrowserWindowController(config: config)
            browserWindowController = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.loadStartPage()
        } catch {
            presentFatalError(error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            browserWindowController?.showWindow(nil)
        }
        return true
    }

    // MARK: - Customization actions (reached via the responder chain)

    @objc func reloadCustomizations(_ sender: Any?) {
        browserWindowController?.reloadCustomizations()
    }

    @objc func openCustomizationFolder(_ sender: Any?) {
        ResourceInjector.ensureCustomizationTemplates()
        NSWorkspace.shared.open(ResourceInjector.customizationDirectory)
    }

    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "This app can't start"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
