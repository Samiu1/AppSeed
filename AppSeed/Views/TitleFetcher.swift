import Foundation

/// Fetches the target page's <title> for the HUD's App Name auto-suggestion.
/// Best-effort with a short timeout — the fallback (registrable domain) is
/// filled in immediately by the HUD, so a slow site never blocks the user.
enum TitleFetcher {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        return URLSession(configuration: configuration)
    }()

    static func fetchTitle(from url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }

        // Generous cap: heavy SPAs inline hundreds of KB before <title>.
        let html = String(decoding: data.prefix(4 * 1024 * 1024), as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]+)", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let titleRange = Range(match.range(at: 1), in: html)
        else { return nil }

        let title = decodeEntities(String(html[titleRange]))
        return cleanTitle(title)
    }

    /// "Linear – Plan and build products" → "Linear": keep the part before
    /// the first marketing separator, capped to a sane app-name length.
    private static func cleanTitle(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" | ", " – ", " — ", " · ", " :: ", " - "] {
            if let range = title.range(of: separator) {
                title = String(title[..<range.lowerBound])
            }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 40 {
            title = String(title.prefix(40)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : title
    }

    private static func decodeEntities(_ text: String) -> String {
        var decoded = text
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, character) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: character)
        }
        return decoded
    }
}
