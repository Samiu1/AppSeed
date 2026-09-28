import AppKit

/// Builds the wrapped app's main menu bar. Construction only — behavior lives
/// on BrowserWindowController (web/window-state actions, reached as nil-target
/// selectors via the responder chain and validated there) and on
/// EngineAppDelegate (app-level customization actions).
enum EngineMainMenu {
    static func make(appName: String) -> NSMenu {
        let mainMenu = NSMenu()
        addSubmenu(appMenu(appName: appName), title: appName, to: mainMenu)
        addSubmenu(fileMenu(), title: "File", to: mainMenu)
        addSubmenu(editMenu(), title: "Edit", to: mainMenu)
        addSubmenu(viewMenu(), title: "View", to: mainMenu)
        addSubmenu(navigationMenu(), title: "Navigation", to: mainMenu)
        let window = windowMenu()
        addSubmenu(window, title: "Window", to: mainMenu)
        NSApp.windowsMenu = window
        return mainMenu
    }

    private static func appMenu(appName: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About \(appName)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close Window",
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(.separator())
        let clearCache = NSMenuItem(title: "Clear Cache",
                                    action: #selector(BrowserWindowController.clearCache(_:)),
                                    keyEquivalent: "e")
        clearCache.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(clearCache)
        menu.addItem(withTitle: "Clear All Website Data…",
                     action: #selector(BrowserWindowController.clearAllWebsiteData(_:)),
                     keyEquivalent: "")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        let copyURL = NSMenuItem(title: "Copy Current URL",
                                 action: #selector(BrowserWindowController.copyCurrentURL(_:)),
                                 keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(copyURL)
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Reload Page",
                     action: #selector(BrowserWindowController.reloadPage(_:)), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Actual Size",
                     action: #selector(BrowserWindowController.zoomActualSize(_:)), keyEquivalent: "0")
        menu.addItem(withTitle: "Zoom In",
                     action: #selector(BrowserWindowController.zoomIn(_:)), keyEquivalent: "+")
        menu.addItem(withTitle: "Zoom Out",
                     action: #selector(BrowserWindowController.zoomOut(_:)), keyEquivalent: "-")
        menu.addItem(.separator())
        let reloadCustomizations = NSMenuItem(
            title: "Reload Customizations",
            action: #selector(EngineAppDelegate.reloadCustomizations(_:)),
            keyEquivalent: "r"
        )
        reloadCustomizations.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(reloadCustomizations)
        menu.addItem(withTitle: "Open Customization Folder…",
                     action: #selector(EngineAppDelegate.openCustomizationFolder(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let fullScreen = NSMenuItem(title: "Enter Full Screen",
                                    action: #selector(NSWindow.toggleFullScreen(_:)),
                                    keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)
        return menu
    }

    private static func navigationMenu() -> NSMenu {
        let menu = NSMenu(title: "Navigation")
        menu.addItem(withTitle: "Back",
                     action: #selector(BrowserWindowController.navigateBack(_:)), keyEquivalent: "[")
        menu.addItem(withTitle: "Forward",
                     action: #selector(BrowserWindowController.navigateForward(_:)), keyEquivalent: "]")
        menu.addItem(.separator())
        let home = NSMenuItem(title: "Go Home",
                              action: #selector(BrowserWindowController.goHome(_:)),
                              keyEquivalent: "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(home)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Float on Top",
                     action: #selector(BrowserWindowController.toggleFloatOnTop(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func addSubmenu(_ submenu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }
}
