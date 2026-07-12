import Foundation
import WebKit

/// Per-app runtime injection: `inject.js` and `custom.css` applied to every
/// page via WKUserContentController.
///
/// The editable copies live OUTSIDE the app bundle, in
/// `~/Library/Application Support/AppSeed/<bundle id>/` — editing files inside
/// a signed bundle would invalidate its signature, and regeneration would
/// wipe them. Because the factory derives the bundle id deterministically
/// from the site's domain, the customization folder survives regenerating
/// the app. Bundle Resources are still honored as a fallback so a bundle can
/// ship pre-baked injections.
///
/// The engine creates the folder with commented template files on first
/// launch; View ▸ Open Customization Folder reveals it, and View ▸ Reload
/// Customizations (⌥⌘R) re-reads the files without relaunching.
enum ResourceInjector {
    static var customizationDirectory: URL {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("AppSeed", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "unknown-app", isDirectory: true)
    }

    static func ensureCustomizationTemplates() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: customizationDirectory, withIntermediateDirectories: true)
        writeTemplateIfMissing("inject.js", contents: Self.javascriptTemplate)
        writeTemplateIfMissing("custom.css", contents: Self.stylesheetTemplate)
    }

    static func installUserScripts(into controller: WKUserContentController) {
        if let script = loadCustomization("inject.js") ?? loadBundleResource(named: "inject", extension: "js") {
            controller.addUserScript(WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }
        if let css = loadCustomization("custom.css") ?? loadBundleResource(named: "custom", extension: "css") {
            controller.addUserScript(WKUserScript(
                source: styleInjectionScript(for: css),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }
    }

    // MARK: - Loading

    private static func loadCustomization(_ filename: String) -> String? {
        nonEmptyContents(of: customizationDirectory.appendingPathComponent(filename))
    }

    private static func loadBundleResource(named name: String, extension ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return nonEmptyContents(of: url)
    }

    private static func nonEmptyContents(of url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return contents
    }

    private static func writeTemplateIfMissing(_ filename: String, contents: String) {
        let destination = customizationDirectory.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? contents.write(to: destination, atomically: true, encoding: .utf8)
    }

    // MARK: - Templates

    private static let javascriptTemplate = """
    // inject.js — JavaScript run on every page of this app (at document end).
    // Edit, then choose View ▸ Reload Customizations (⌥⌘R) in the app to apply.
    //
    // Example — remove promo banners:
    //   document.querySelectorAll('.promo-banner').forEach(el => el.remove());

    """

    private static let stylesheetTemplate = """
    /* custom.css — stylesheet appended to every page of this app.
       Edit, then choose View ▸ Reload Customizations (⌥⌘R) in the app to apply.

       Example — hide the site header:
       header { display: none !important; }
    */

    """

    /// Percent-encoding round-trip keeps arbitrary CSS safe to embed in a JS
    /// string literal without escaping edge cases.
    private static func styleInjectionScript(for css: String) -> String {
        let encoded = css.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return """
        (function () {
            var style = document.createElement('style');
            style.textContent = decodeURIComponent('\(encoded)');
            document.documentElement.appendChild(style);
        })();
        """
    }
}
