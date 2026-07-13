import AppKit

/// One app AppSeed has created, discovered by scanning install directories —
/// there is no separate database (a deliberate v1 cut); the bundles on disk
/// are the source of truth.
struct WrappedApp {
    let name: String
    let url: String
    let bundleID: String
    let path: URL
    /// Engine version the app was built with (0 for apps predating versioning).
    let engineVersion: Int

    /// True when the app was built with an engine older than this AppSeed's —
    /// the precise "an update is available for this app" signal.
    var needsUpdate: Bool { engineVersion < EngineVersion.current }
}

/// Discovers and removes AppSeed-generated apps. "My Apps" in the menu bar is
/// built from `installed()`; the per-app Remove action calls `remove(_:)`.
enum WrappedAppsRegistry {
    /// Scans the likely install locations for AppSeed clones. Covers the
    /// user's configured install directory plus the two standard Applications
    /// folders, since an app may have been created before the location was
    /// changed (or dragged elsewhere by hand).
    static func installed() -> [WrappedApp] {
        let fileManager = FileManager.default
        var seenPaths = Set<String>()
        var apps: [WrappedApp] = []

        for directory in candidateDirectories() {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for bundleURL in entries where bundleURL.pathExtension == "app" {
                let standardized = bundleURL.standardizedFileURL.path
                guard !seenPaths.contains(standardized) else { continue }
                guard let app = wrappedApp(at: bundleURL) else { continue }
                seenPaths.insert(standardized)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Moves the app and everything it stored to the Trash (reversible — the
    /// "drag to Trash" mental model, but also sweeping the per-bundle-id login
    /// and cache data a normal user could never find by hand). Quits the app
    /// first if it's running.
    static func remove(_ app: WrappedApp) throws {
        terminateIfRunning(bundleID: app.bundleID)

        let fileManager = FileManager.default
        var firstError: Error?
        func trash(_ url: URL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        // The bundle itself first — that's the failure that matters most
        // (e.g. a permission error in /Applications).
        trash(app.path)
        // Then the private data siloed under the deterministic bundle id.
        for location in dataLocations(bundleID: app.bundleID) {
            trash(location)
        }

        if let firstError { throw firstError }
    }

    // MARK: - Discovery internals

    private static func candidateDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories = [
            AppFactory.defaultInstallDirectory,
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
        ]
        // De-duplicate while preserving order (configured dir may equal one of
        // the standard ones).
        var seen = Set<String>()
        directories = directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return directories
    }

    private static func wrappedApp(at bundleURL: URL) -> WrappedApp? {
        guard AppFactory.isAppSeedClone(bundleURL) else { return nil }
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              bundleID.hasPrefix("com.appseed.wrapped.") // exclude stray engine copies
        else { return nil }

        // The wrapped URL and engine version live in the injected config;
        // fall back gracefully (an app predating versioning reports 0).
        var url = ""
        var engineVersion = 0
        let configURL = bundleURL.appendingPathComponent("Contents/Resources/AppConfig.json")
        if let configData = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: configData) {
            url = config.url
            engineVersion = config.engineVersion ?? 0
        }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return WrappedApp(name: name, url: url, bundleID: bundleID, path: bundleURL,
                          engineVersion: engineVersion)
    }

    /// True when at least one installed app is on an older engine — the
    /// condition under which "Update All Apps" is worth surfacing.
    static func updatesAvailable() -> Bool {
        installed().contains { $0.needsUpdate }
    }

    // MARK: - Removal internals

    /// Per-bundle-id data written by a non-sandboxed WKWebView app, plus
    /// AppSeed's own customization folder. All are namespaced by the
    /// deterministic bundle id (`com.appseed.wrapped.*`), so matching on it
    /// can never touch another app's data.
    private static func dataLocations(bundleID: String) -> [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("WebKit/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            library.appendingPathComponent("Cookies/\(bundleID).binarycookies"),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true),
            library.appendingPathComponent("Preferences/\(bundleID).plist"),
            library.appendingPathComponent("Application Support/AppSeed/\(bundleID)", isDirectory: true),
        ]
    }

    private static func terminateIfRunning(bundleID: String) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            running.terminate()
        }
    }
}
