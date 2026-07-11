import Foundation

enum IconError: LocalizedError {
    case noIconFound

    var errorDescription: String? {
        switch self {
        case .noIconFound:
            return "No usable site icon was found."
        }
    }
}

/// Builds `AppIcon.icns` for a generated app from the wrapped site's own icon.
///
/// Deliberately does NOT use Cocoa image APIs to author the .icns — native
/// multi-resolution .icns generation is unreliable and tends to produce
/// corrupted icons. Instead it drives macOS's own `sips` and `iconutil`
/// command-line tools via Process, exactly as the spec requires.
enum IconBuilder {
    private static let sipsPath = "/usr/bin/sips"
    private static let iconutilPath = "/usr/bin/iconutil"

    /// iconutil silently fails or emits a corrupt .icns when the PNGs inside
    /// the .iconset are not named to Apple's exact convention — these names
    /// must not change.
    private static let iconSizes: [Int] = [16, 32, 128, 256, 512]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    /// Fetches the site's best icon and swaps it into the staged bundle.
    /// Throws when no usable icon exists — callers treat that as non-fatal
    /// and keep the engine's default icon.
    static func installIcon(for siteURL: URL, into stagedBundle: URL) async throws {
        let imageData = try await fetchBestIconData(for: siteURL)
        let icnsURL = try makeICNS(from: imageData)
        defer { try? FileManager.default.removeItem(at: icnsURL.deletingLastPathComponent()) }

        let destination = stagedBundle
            .appendingPathComponent("Contents/Resources/AppIcon.icns")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: icnsURL, to: destination)
    }

    // MARK: - Icon discovery

    private static func fetchBestIconData(for siteURL: URL) async throws -> Data {
        var candidates: [URL] = []
        if var rootComponents = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) {
            rootComponents.path = ""
            rootComponents.query = nil
            rootComponents.fragment = nil
            if let root = rootComponents.url {
                candidates.append(root.appendingPathComponent("apple-touch-icon.png"))
                candidates.append(root.appendingPathComponent("apple-touch-icon-precomposed.png"))
            }
        }
        candidates.append(contentsOf: await iconLinks(from: siteURL))

        for candidate in candidates {
            if let data = try? await download(candidate), isLikelyImage(data) {
                return data
            }
        }
        throw IconError.noIconFound
    }

    /// Scrapes <link rel="...icon..."> hrefs from the page head, preferring
    /// apple-touch icons, then PNGs.
    private static func iconLinks(from siteURL: URL) async -> [URL] {
        guard let html = try? await downloadText(siteURL) else { return [] }
        let pattern = #"<link\b[^>]*rel=["']?[^"'>]*icon[^"'>]*["']?[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var hrefs: [String] = []
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            if let href = attributeValue("href", in: tag) {
                hrefs.append(href)
            }
        }
        let ranked = hrefs.sorted { score($0) > score($1) }
        return ranked.prefix(5).compactMap { URL(string: $0, relativeTo: siteURL)?.absoluteURL }
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
              let valueRange = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[valueRange])
    }

    private static func score(_ href: String) -> Int {
        let lowered = href.lowercased()
        if lowered.contains("apple-touch") { return 3 }
        if lowered.hasSuffix(".png") || lowered.contains(".png?") { return 2 }
        if lowered.hasSuffix(".ico") { return 1 }
        return 0
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 100 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func downloadText(_ url: URL) async throws -> String {
        let data = try await download(url)
        // Generous cap: sites like linear.app inline >800KB of assets before
        // the <link rel="icon"> tags appear in the document head.
        let capped = data.prefix(4 * 1024 * 1024)
        return String(data: capped, encoding: .utf8)
            ?? String(decoding: capped, as: UTF8.self)
    }

    private static func isLikelyImage(_ data: Data) -> Bool {
        let magic = [UInt8](data.prefix(4))
        guard magic.count == 4 else { return false }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let jpeg: [UInt8] = [0xFF, 0xD8]
        let ico: [UInt8] = [0x00, 0x00, 0x01, 0x00]
        let gif: [UInt8] = [0x47, 0x49, 0x46]
        return magic == png
            || Array(magic.prefix(2)) == jpeg
            || magic == ico
            || Array(magic.prefix(3)) == gif
    }

    // MARK: - .icns assembly (sips + iconutil)

    private static func makeICNS(from imageData: Data) throws -> URL {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("appseed-icon-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let sourceURL = workDirectory.appendingPathComponent("source.img")
        try imageData.write(to: sourceURL)

        // Normalize whatever we downloaded (PNG/JPEG/ICO/GIF) to PNG first.
        // If sips can't read the format, the whole step fails and the caller
        // keeps the default icon.
        let basePNG = workDirectory.appendingPathComponent("base.png")
        try ProcessRunner.run(sipsPath, ["-s", "format", "png", sourceURL.path, "--out", basePNG.path])

        let iconset = workDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

        for size in iconSizes {
            let onePoint = iconset.appendingPathComponent("icon_\(size)x\(size).png")
            try ProcessRunner.run(sipsPath, ["-z", "\(size)", "\(size)", basePNG.path, "--out", onePoint.path])

            let doubled = size * 2
            let twoPoint = iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png")
            try ProcessRunner.run(sipsPath, ["-z", "\(doubled)", "\(doubled)", basePNG.path, "--out", twoPoint.path])
        }

        let icnsURL = workDirectory.appendingPathComponent("AppIcon.icns")
        try ProcessRunner.run(iconutilPath, ["-c", "icns", iconset.path, "-o", icnsURL.path])
        return icnsURL
    }
}
