import AppKit

/// Result of regenerating one wrapped app.
struct AppUpdateOutcome {
    let name: String
    let succeeded: Bool
    let detail: String? // failure reason when !succeeded
}

/// "Update All Apps": regenerates every AppSeed-created app in place with the
/// factory's current embedded engine.
///
/// This is the Layer-2 update path (see ROADMAP.md): shipping a new AppSeed
/// updates the *factory*, but the apps a user already made stay frozen on the
/// engine that built them until they're regenerated. Because bundle ids are
/// deterministic per domain, each rebuilt app keeps its `WKWebsiteDataStore`,
/// so logins survive the update.
enum AppUpdater {
    typealias ProgressHandler = (_ completed: Int, _ total: Int, _ currentName: String) -> Void

    /// Regenerates each installed wrapped app sequentially, reporting progress
    /// on the main actor. Never throws — per-app failures are captured in the
    /// returned outcomes so one bad app can't abort the batch.
    static func updateAll(progress: @escaping ProgressHandler) async -> [AppUpdateOutcome] {
        let apps = WrappedAppsRegistry.installed()
        var outcomes: [AppUpdateOutcome] = []
        for (index, app) in apps.enumerated() {
            await MainActor.run { progress(index, apps.count, app.name) }
            outcomes.append(await update(app))
        }
        await MainActor.run { progress(apps.count, apps.count, "") }
        return outcomes
    }

    private static func update(_ app: WrappedApp) async -> AppUpdateOutcome {
        guard let url = URL(string: app.url), url.scheme != nil else {
            return AppUpdateOutcome(name: app.name, succeeded: false,
                                    detail: "This app has no saved web address.")
        }

        // Quit any running instance so its bundle isn't replaced while live.
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }

        // Preserve the exact on-disk filename and folder so the rebuilt bundle
        // overwrites this one (rather than landing at a name derived from the
        // display name, which can differ).
        let filename = app.path.deletingPathExtension().lastPathComponent
        let request = FactoryRequest(
            url: url,
            appName: filename,
            destinationDirectory: app.path.deletingLastPathComponent()
        )
        // These are our own clones, so overwrite-in-place is the safe resolution.
        let factory = AppFactory(progress: { _ in }, resolveCollision: { _ in .overwrite })
        do {
            _ = try await factory.build(request)
            return AppUpdateOutcome(name: app.name, succeeded: true, detail: nil)
        } catch {
            return AppUpdateOutcome(name: app.name, succeeded: false, detail: error.localizedDescription)
        }
    }
}
