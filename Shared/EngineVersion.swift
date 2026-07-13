import Foundation

/// Version of the AppSeedEngine embedded in this build of the factory.
///
/// Stamped into every generated app's `AppConfig.json` at creation time so
/// AppSeed can tell which apps were built with an older engine and offer to
/// update only those — the accurate signal for "Update All Apps" (an app is
/// stale when its stamped version is below `current`, regardless of whether a
/// newer *AppSeed* exists).
///
/// BUMP THIS whenever the engine's behavior changes (navigation, runtime,
/// window handling, etc.) so existing apps are correctly flagged as stale.
///
/// History:
///   1 — initial engine.
///   2 — window drag/traffic-light fix; OAuth kept in-WebView (dropped the
///       ASWebAuthenticationSession hand-off).
///   3 — web Notification API bridged to native UNUserNotificationCenter.
enum EngineVersion {
    static let current = 3
}
