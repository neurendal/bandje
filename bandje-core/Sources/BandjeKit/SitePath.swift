// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Paths of band.je pages in the app's language (owner, 2026-11-12): English is at the root
/// (`/support/`), the other nine languages under `/<code>/` (`/nl/support/`). Only the path: each
/// app puts its own `https://band.je` in front (BandjeKit holds no URLs), and the link opens the
/// browser.
public enum SitePath {
    /// The site's languages; English has no prefix.
    public static let languages = ["en", "nl", "de", "fr", "es", "it", "pt", "pl", "ru", "uk"]

    /// The site language for an app localization: "pt-BR" → "pt", "nl" → "nl"; unknown or nil →
    /// "en".
    public static func language(for localization: String?) -> String {
        guard let localization else { return "en" }
        let code = localization.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return languages.contains(code) ? code : "en"
    }

    /// `page` ("/" for the home page, "/support/") with the language prefix, plus `#fragment`.
    /// `localization` defaults to the language the app runs in.
    public static func path(_ page: String, fragment: String? = nil,
                            localization: String? = Bundle.main.preferredLocalizations.first) -> String {
        let language = language(for: localization)
        let page = page.hasPrefix("/") ? page : "/" + page
        let prefixed = language == "en" ? page : "/" + language + page
        guard let fragment, !fragment.isEmpty else { return prefixed }
        return prefixed + "#" + fragment
    }
}
