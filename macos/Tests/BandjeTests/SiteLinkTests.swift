import Foundation
import Testing
@testable import Bandje

/// The band.je link in About opens the site in the app's language (English at the root).
struct SiteLinkTests {
    @Test func linkFollowsTheAppLanguage() {
        #expect(AboutView.site("/", localization: "en").absoluteString == "https://band.je/")
        #expect(AboutView.site("/", localization: "nl").absoluteString == "https://band.je/nl/")
        #expect(AboutView.site("/", localization: "pt-BR").absoluteString == "https://band.je/pt/")
        #expect(AboutView.site("/support/", localization: "ru").absoluteString == "https://band.je/ru/support/")
        #expect(AboutView.site("/", localization: "ja").absoluteString == "https://band.je/")
        #expect(AboutView.site("/", localization: nil).absoluteString == "https://band.je/")
    }
}
