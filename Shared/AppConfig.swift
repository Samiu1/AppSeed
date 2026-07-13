import Foundation

/// Configuration injected into every generated app bundle at
/// `Contents/Resources/AppConfig.json`.
///
/// Written by the AppSeed factory at creation time, read once at launch by the
/// AppSeedEngine runtime. Generated apps are static after creation — there is
/// deliberately no live "update config of a running app" channel (v1 cut).
struct AppConfig: Codable {
    struct WindowState: Codable {
        var width: Double
        var height: Double
    }

    var appName: String
    var url: String
    var bundleIdentifier: String
    var window: WindowState
    /// Engine version that built this app. Optional for backward compatibility
    /// with apps generated before versioning existed (treated as version 0,
    /// i.e. stale). The engine runtime ignores it; only the factory reads it.
    var engineVersion: Int?

    static let resourceName = "AppConfig"

    static func loadFromMainBundle() throws -> AppConfig {
        guard let fileURL = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            throw AppConfigError.missingFromBundle
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}

enum AppConfigError: LocalizedError {
    case missingFromBundle

    var errorDescription: String? {
        switch self {
        case .missingFromBundle:
            return "AppConfig.json is missing from the app bundle's Resources folder. This bundle was not generated correctly."
        }
    }
}
