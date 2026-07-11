import Foundation

/// Registrable-domain handling shared by the factory (bundle-id derivation,
/// app-name suggestion) and the engine (same-site navigation policy).
///
/// The one rule, applied consistently everywhere:
///   1. lowercase the host and strip a leading "www."
///   2. keep the last two DNS labels — or the last three when the final two
///      labels form a known multi-part public suffix (e.g. "co.uk").
///
/// So `linear.app`, `www.linear.app` → `linear.app`, and
/// `app.linear.com` → `linear.com`.
enum DomainUtils {
    /// Common multi-part public suffixes. Not the full Public Suffix List by
    /// design — a dependency-free approximation that covers the frequent cases.
    private static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk",
        "co.jp", "ne.jp", "or.jp", "ac.jp",
        "com.au", "net.au", "org.au", "edu.au",
        "co.nz", "org.nz", "net.nz",
        "co.in", "net.in", "org.in",
        "com.br", "com.mx", "com.ar", "com.co",
        "com.sg", "com.my", "com.hk", "com.tw", "co.kr",
        "com.tr", "co.za", "co.il", "com.cn",
    ]

    static func registrableDomain(of host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }
        let labels = normalized.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return normalized }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let keep = multiPartSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// Deterministic bundle identifier for a wrapped site.
    ///
    /// The same domain must always produce the same identifier: macOS silos
    /// `WKWebsiteDataStore` (~/Library/WebKit/<bundle id>) and Keychain access
    /// by bundle id, so a stable id means regenerating an app for the same
    /// site keeps its login session and local storage. Never derive this from
    /// a UUID.
    static func bundleIdentifier(forHost host: String) -> String {
        let domain = registrableDomain(of: host)
        let slug = domain
            .replacingOccurrences(of: ".", with: "-")
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        return "com.appseed.wrapped.\(slug.lowercased())"
    }

    /// Fallback app-name suggestion when the page `<title>` can't be fetched:
    /// the first label of the registrable domain, capitalized — "Linear" for
    /// `linear.app`.
    static func suggestedAppName(forHost host: String) -> String {
        let domain = registrableDomain(of: host)
        guard let firstLabel = domain.split(separator: ".").first, !firstLabel.isEmpty else {
            return domain
        }
        return firstLabel.prefix(1).uppercased() + firstLabel.dropFirst()
    }
}
