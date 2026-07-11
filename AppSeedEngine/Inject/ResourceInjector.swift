import Foundation
import WebKit

/// Optional per-app runtime injection. If the generated bundle's Resources
/// contain `inject.js` and/or `custom.css`, they are applied to every page
/// via WKUserContentController — the supported way to tailor wrapped sites
/// (hide chrome, tweak layout) without touching the engine.
enum ResourceInjector {
    static func installUserScripts(into controller: WKUserContentController) {
        if let script = loadResource(named: "inject", extension: "js") {
            controller.addUserScript(WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }
        if let css = loadResource(named: "custom", extension: "css") {
            controller.addUserScript(WKUserScript(
                source: styleInjectionScript(for: css),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }
    }

    private static func loadResource(named name: String, extension ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.isEmpty
        else { return nil }
        return contents
    }

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
