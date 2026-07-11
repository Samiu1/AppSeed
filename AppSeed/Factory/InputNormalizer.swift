import Foundation

enum NormalizationError: LocalizedError {
    case emptyURL
    case invalidURL(String)
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Enter a web address."
        case .invalidURL(let raw):
            return "\"\(raw)\" doesn't look like a web address."
        case .emptyName:
            return "Enter an app name."
        }
    }
}

/// Step 0 of the factory pipeline: validate and normalize the two user inputs
/// before any file is touched.
enum InputNormalizer {
    /// Defaults the scheme to https:// when absent and rejects anything that
    /// isn't a resolvable-looking web URL.
    static func normalizeURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NormalizationError.emptyURL }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw NormalizationError.invalidURL(trimmed)
        }

        var candidate = trimmed
        let lowered = candidate.lowercased()
        if !lowered.hasPrefix("http://") && !lowered.hasPrefix("https://") {
            guard !lowered.contains("://") else { throw NormalizationError.invalidURL(trimmed) }
            candidate = "https://" + candidate
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host == "localhost" || host.contains("."),
              let url = components.url
        else {
            throw NormalizationError.invalidURL(trimmed)
        }
        return url
    }

    /// Sanitizes an app name into a legal macOS filename: strips control
    /// characters and leading dots, replaces path-hostile characters, trims
    /// whitespace, and rejects empty results.
    static func sanitizeAppName(_ raw: String) throws -> String {
        var name = String(raw.map { "/:".contains($0) ? "-" : $0 })
        name = String(String.UnicodeScalarView(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.count > 80 {
            name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { throw NormalizationError.emptyName }
        return name
    }

    /// Loose check used for clipboard pre-fill only — never throws, never
    /// blocks submission.
    static func looksLikeURL(_ raw: String) -> Bool {
        guard raw.count < 2048 else { return false }
        return (try? normalizeURL(raw)) != nil
    }
}
