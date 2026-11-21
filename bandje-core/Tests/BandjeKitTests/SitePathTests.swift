// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import BandjeKit

@Suite("SitePath: band.je pages in the app's language")
struct SitePathTests {
    @Test("App localizations map to the site's ten languages; unknown is English")
    func languages() {
        #expect(SitePath.language(for: "nl") == "nl")
        #expect(SitePath.language(for: "pt-BR") == "pt")
        #expect(SitePath.language(for: "en-GB") == "en")
        #expect(SitePath.language(for: "uk_UA") == "uk")
        #expect(SitePath.language(for: "DE") == "de")
        #expect(SitePath.language(for: "ja") == "en")
        #expect(SitePath.language(for: "") == "en")
        #expect(SitePath.language(for: nil) == "en")
        for code in SitePath.languages { #expect(SitePath.language(for: code) == code) }
    }

    @Test("English at the root, the others under /<code>/, the fragment kept")
    func paths() {
        #expect(SitePath.path("/", localization: "en") == "/")
        #expect(SitePath.path("/", localization: "nl") == "/nl/")
        #expect(SitePath.path("/support/", localization: "en") == "/support/")
        #expect(SitePath.path("/support/", localization: "ru") == "/ru/support/")
        #expect(SitePath.path("/support/", fragment: "phone-calls", localization: "en") == "/support/#phone-calls")
        #expect(SitePath.path("/support/", fragment: "phone-calls", localization: "pt-BR") == "/pt/support/#phone-calls")
        #expect(SitePath.path("privacy/", localization: "fr") == "/fr/privacy/")
        #expect(SitePath.path("/privacy/", localization: "zh-Hans") == "/privacy/")
    }
}
