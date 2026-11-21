// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import Bandje

/// The band.je links in Settings open the page in the app's language (English at the root).
struct SiteLinkTests {
    @Test func linksFollowTheAppLanguage() {
        #expect(AboutView.site("/", localization: "en").absoluteString == "https://band.je/")
        #expect(AboutView.site("/", localization: "nl").absoluteString == "https://band.je/nl/")
        #expect(AboutView.site("/support/", localization: "de").absoluteString == "https://band.je/de/support/")
        #expect(AboutView.site("/support/", fragment: "phone-calls", localization: "en").absoluteString == "https://band.je/support/#phone-calls")
        #expect(AboutView.site("/support/", fragment: "phone-calls", localization: "uk").absoluteString == "https://band.je/uk/support/#phone-calls")
        #expect(AboutView.site("/privacy/", localization: "pt-BR").absoluteString == "https://band.je/pt/privacy/")
        #expect(AboutView.site("/privacy/", localization: "ja").absoluteString == "https://band.je/privacy/")
    }

    /// Every language the app ships in has its own pages on band.je.
    @Test func everyAppLanguageIsASiteLanguage() {
        let shipped = Bundle.main.localizations.filter { $0 != "Base" }
        #expect(!shipped.isEmpty)
        for language in shipped {
            #expect(AboutView.site("/", localization: language).absoluteString != "https://band.je/" || language.hasPrefix("en"), "\(language)")
        }
    }
}
