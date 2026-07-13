import Foundation

/// Which apps the user has favourited — favourites are the only apps shown in
/// the menu bar (the full list lives in Settings › My Apps).
///
/// Keyed by bundle id (the app's stable identity), persisted in UserDefaults
/// alongside the rest of AppSeed's settings, so favourites survive app updates.
enum FavoritesStore {
    private static let key = "favoriteBundleIDs"

    static func favorites() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func isFavorite(_ bundleID: String) -> Bool {
        favorites().contains(bundleID)
    }

    static func setFavorite(_ isFavorite: Bool, bundleID: String) {
        var current = favorites()
        if isFavorite {
            current.insert(bundleID)
        } else {
            current.remove(bundleID)
        }
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func toggle(_ bundleID: String) {
        setFavorite(!isFavorite(bundleID), bundleID: bundleID)
    }
}
