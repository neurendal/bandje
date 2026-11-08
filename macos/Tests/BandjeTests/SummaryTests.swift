import Foundation
import Testing
@testable import Bandje

/// M8 and M9: everything around the model, without the model.
struct SummaryTests {
    private func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bandje-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func transcript() -> Transcript {
        func seg(_ who: String, _ start: Double, _ text: String) -> Segment {
            let words = text.split(separator: " ").enumerated().map {
                TimedWord(text: String($0.element), start: start + Double($0.offset) * 0.3, end: start + Double($0.offset) * 0.3 + 0.25)
            }
            return Segment(speaker: who, channel: nil, words: words)
        }
        return Transcript(title: "2026-11-05_10-00", duration: 75, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4",
                          segments: [seg("Spreker 1", 1, "Goedemorgen <Anna> & welkom"), seg("Spreker 2", 12, "Dank je"),
                                     seg("Spreker 2", 14, "ik vraag 4000 euro"), seg("Spreker 1", 70, "Tot dinsdag")],
                          speakerNames: ["Spreker 1": "Anna"], audioFile: "gesprek.m4a")
    }

    // MARK: Templates

    @Test func templatesMergeKeepsOrOverwrites() throws {
        let source = temp(), target = temp()
        try Data("1".utf8).write(to: source.appendingPathComponent("A.md"))
        try Data("2".utf8).write(to: source.appendingPathComponent("B.txt"))
        try Data("x".utf8).write(to: source.appendingPathComponent("notes.pdf"))
        try Data("x".utf8).write(to: target.appendingPathComponent("A.md"))
        try Summaries.mergeTemplates(from: source, into: target, overwrite: false)
        #expect(Files.readString(target.appendingPathComponent("A.md")) == "x")
        #expect(Files.readString(target.appendingPathComponent("B.txt")) == "2")
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("notes.pdf").path))
        try Summaries.mergeTemplates(from: source, into: target, overwrite: true)
        #expect(Files.readString(target.appendingPathComponent("A.md")) == "1")
        // A target folder that doesn't exist yet is created.
        let fresh = temp().appendingPathComponent("Templates")
        try Summaries.mergeTemplates(from: source, into: fresh, overwrite: false)
        #expect(Summaries.templates(in: fresh).map(\.name) == ["A", "B"])
    }

    @Test func templatesAreMdAndTxtSortedByNameAndEmptyOnesSkipped() throws {
        let dir = temp()
        try "## A".write(to: dir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "## B".write(to: dir.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "  \n".write(to: dir.appendingPathComponent("leeg.md"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("notitie.rtf"), atomically: true, encoding: .utf8)
        #expect(Summaries.templates(in: dir).map(\.name) == ["A", "b"])
    }

    @Test func examplesOnlyGoIntoANewFolder() throws {
        let dir = temp().appendingPathComponent("Templates")
        let defaults = UserDefaults(suiteName: "seed-\(UUID().uuidString)")!
        Summaries.seedIfMissing(dir, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: dir).map(\.name) == ["Algemene samenvatting", "Klantinterview (productvalidatie)", "Sollicitatiegesprek", "Vergadering"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Vergadering.md"))
        Summaries.seedIfMissing(dir, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: dir).count == 3) // the user's removal stays
        let en = temp().appendingPathComponent("Templates")
        Summaries.seedIfMissing(en, language: "de", defaults: defaults)
        #expect(Summaries.templates(in: en).map(\.name).contains("Besprechung"))  // German examples, as on the iPhone
    }

    /// A later example (Algemene samenvatting, as on the iPhone) goes once into an existing folder:
    /// never over a file of that name, and not again after the user deleted it.
    @Test func laterExampleGoesOnceIntoAnExistingFolder() throws {
        let dir = temp().appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "eigen".write(to: dir.appendingPathComponent("Mijn template.md"), atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: "seed-\(UUID().uuidString)")!
        Summaries.seedIfMissing(dir, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: dir).map(\.name) == ["Algemene samenvatting", "Mijn template"])
        #expect(Summaries.templates(in: dir).first?.text.contains("## Belangrijkste punten") == true)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Algemene samenvatting.md"))
        Summaries.seedIfMissing(dir, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: dir).map(\.name) == ["Mijn template"])
        // An own file of that name is never replaced.
        let other = temp().appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "van mij".write(to: other.appendingPathComponent("Generic summary.md"), atomically: true, encoding: .utf8)
        Summaries.seedIfMissing(other, language: "en", defaults: UserDefaults(suiteName: "seed-\(UUID().uuidString)")!)
        #expect(Summaries.templates(in: other).first?.text == "van mij")
    }

    @Test func interviewExampleAsksForTheDetailsTheSpikeMissed() {
        let t = Summaries.examples(language: "nl").first { $0.name == "Sollicitatiegesprek" }!
        for word in ["Salariswens", "exacte bedragen", "Andere sollicitaties", "opleidingsbudget", "Vervolgafspraken"] {
            #expect(t.text.contains(word))
        }
    }

    // MARK: Text, chunks, prompts

    @Test func linesUseGivenNamesAndTimes() {
        #expect(Summaries.lines(transcript()) == [
            "[00:01] Anna: Goedemorgen <Anna> & welkom", "[00:12] Spreker 2: Dank je ik vraag 4000 euro", "[01:10] Anna: Tot dinsdag",
        ])
    }

    @Test func languageOfDutchAndEnglishText() {
        #expect(Summaries.language(of: "Goedemorgen, fijn dat je er bent. Zullen we beginnen met de planning voor volgende week?") == "nl")
        #expect(Summaries.language(of: "Good morning, thanks for joining. Shall we start with the plan for next week?") == "en")
        #expect(Summaries.languageName("nl") == "Dutch")
    }

    @Test func chunksKeepWholeLinesAndStayUnderTheLimit() {
        let lines = (1...40).map { "[00:\(String(format: "%02d", $0))] Anna: " + String(repeating: "woord ", count: $0) }
        let chunks = Summaries.chunks(lines, limit: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { Summaries.estimatedTokens($0) <= 100 + 2 })
        #expect(chunks.joined(separator: "\n") == lines.joined(separator: "\n"))
        // One line longer than the limit is cut at words, nothing is lost.
        let long = Summaries.chunks(["[00:01] Anna: " + String(repeating: "lang ", count: 200)], limit: 50)
        #expect(long.count > 1 && long.allSatisfy { Summaries.estimatedTokens($0) <= 52 })
        #expect(long.joined(separator: " ").split(separator: " ").count == 202)
        #expect(Summaries.chunks(["kort"], limit: 100) == ["kort"])
    }

    @Test func instructionsHoldRulesLanguageAndTemplate() {
        let t = Summaries.Template(name: "X", text: "## Besluiten\nElk besluit.\n")
        let i = Summaries.instructions(template: t, language: "nl")
        #expect(i.contains("Write in Dutch."))
        #expect(i.contains("Never invent"))
        #expect(i.contains("not discussed"))
        #expect(i.hasSuffix("## Besluiten\nElk besluit."))
        #expect(Summaries.instructions(template: t, language: "nl", fromNotes: true).contains("Use only information from the notes"))
        #expect(Summaries.noteInstructions(template: t, language: "de", part: 2, of: 3).contains("part 2 of 3"))
        #expect(!i.contains("Translate")) // the text follows the conversation, the headings the template
    }

    @Test func templateEchoIsRemoved() {
        let t = Summaries.Template(name: "X", text: "## Kern\nDe uitkomst in twee zinnen.\n\n## Vervolg\nDe volgende afspraak.\n")
        let body = "## Kern\nDe uitkomst in twee zinnen.\n\nAlles is goed.\n\n## Vervolg\n  de volgende afspraak.  \n\nDinsdag."
        #expect(Summaries.removeTemplateEcho(body, template: t) == "## Kern\n\nAlles is goed.\n\n## Vervolg\n\nDinsdag.")
        let job = Summaries.Template(name: "J", text: "## Vragen\nWat de kandidaat zelf vroeg, en het antwoord.\n## Andere\nAndere gesprekken of aanbiedingen van de kandidaat, en hoe ver die zijn.\n## Indruk\nSterke punten en zorgen die naar voren kwamen. Geen eigen oordeel.")
        let echo = "## Vragen\nWat de kandidaat zelf vroeg, en het antwoord:\n* Thuiswerken?\n## Andere\nAndere gesprekken of aanbiedingen van de kandidaat: Bol in Utrecht.\n## Indruk\nSterke punten en zorgen die naar voren kwamen:\n* Enthousiast\nSalaris: 6000 euro"
        #expect(Summaries.removeTemplateEcho(echo, template: job)
                == "## Vragen\n* Thuiswerken?\n## Andere\nBol in Utrecht.\n## Indruk\n* Enthousiast\nSalaris: 6000 euro")
    }

    // MARK: Output

    @Test func outputFileAndDocument() {
        let json = URL(fileURLWithPath: "/x/2026-11-05_10-00/2026-11-05_10-00.json")
        #expect(Summaries.outputURL(json: json, template: "Klant/interview").lastPathComponent
                == "2026-11-05_10-00 \(Summaries.fileWord) Klant-interview.md")
        let doc = Summaries.document(transcript(), template: "Vergadering", body: "## Kern\nAlles goed.\n",
                                     date: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "nl"))
        #expect(doc.hasPrefix("# Samenvatting "))
        #expect(doc.contains("Template Vergadering"))
        #expect(doc.contains("Apple Intelligence"))
        #expect(Summaries.body(ofDocument: doc) == "## Kern\nAlles goed.")
    }


    @Test func importedAudioIsCopiedIntoItsOwnFolder() throws {
        let dir = temp(), elsewhere = temp()
        let memo = elsewhere.appendingPathComponent("Memo 12.m4a")
        try Data([1, 2, 3]).write(to: memo)
        let (folder, audio) = OutputLocation.importFolder(for: memo, in: dir)
        #expect(folder == dir.appendingPathComponent("Memo 12", isDirectory: true))
        #expect(audio == folder.appendingPathComponent("Memo 12.m4a"))
        #expect(try Data(contentsOf: audio) == Data([1, 2, 3]))
        #expect(FileManager.default.fileExists(atPath: memo.path)) // the original stays
        // Importing again never touches the first import: a new folder. A file already in its own
        // folder is used as is (transcribing it again).
        let again = OutputLocation.importFolder(for: memo, in: dir)
        #expect(again.folder.lastPathComponent == "Memo 12 2" && again.audio.lastPathComponent == "Memo 12 2.m4a")
        #expect(try Data(contentsOf: audio) == Data([1, 2, 3]))
        #expect(OutputLocation.importFolder(for: audio, in: dir).audio == audio)
    }

    /// Security audit: an import must never replace a recording or land in Bandje's own folders.
    @Test func importNeverReplacesARecordingOrUsesBandjeFolders() throws {
        let dir = temp(), elsewhere = temp()
        let rec = dir.appendingPathComponent("2026-11-05_17-04")
        try FileManager.default.createDirectory(at: rec, withIntermediateDirectories: true)
        let original = rec.appendingPathComponent("2026-11-05_17-04.m4a")
        try Data([9]).write(to: original)
        let sameName = elsewhere.appendingPathComponent("2026-11-05_17-04.m4a")
        try Data([1]).write(to: sameName)
        let imported = OutputLocation.importFolder(for: sameName, in: dir)
        #expect(imported.folder.lastPathComponent == "2026-11-05_17-04 2")
        #expect(try Data(contentsOf: original) == Data([9]))
        for name in ["Templates.m4a", "selftest.wav", ".models.mp3", "...m4a"] {
            let f = elsewhere.appendingPathComponent(name)
            try Data([2]).write(to: f)
            let folder = OutputLocation.importFolder(for: f, in: dir).folder.lastPathComponent
            #expect(!["Templates", "selftest", ".models"].contains(folder) && !folder.hasPrefix("."), "\(name) -> \(folder)")
        }
    }

    // MARK: Share as web page

    @Test func webExportIsSelfContainedAndBranded() {
        var t = transcript()
        t.title = "Opname 6 nov 14.32"
        t.segments[0].words = [TimedWord(text: "<script>alert(1)</script> & \"x\"", start: 1, end: 2)]
        let html = WebExport.page(t, summaries: [.init(name: "Vergadering", markdown: "## Kern\n- punt [00:12]")],
                                  audio: (base64: "AAAA", type: "audio/mp4"), logoBase64: "BBBB")
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;"))
        #expect(!html.contains("<script>alert"))
        #expect(html.components(separatedBy: "\"https://band.je\"").count == 2)          // the link, exactly once
        #expect(html.range(of: #"https?://(?!band\.je")"#, options: .regularExpression) == nil)  // no other URL
        #expect(html.contains("src=\"data:audio/mp4;base64,AAAA\""))
        #expect(html.contains("src=\"data:image/png;base64,BBBB\""))
        #expect(!html.contains("bandje://") && !html.contains("file://"))
        #expect(html.range(of: #"<(script|link|img|audio)[^>]+(src|href)="(?!data:)"#, options: .regularExpression) == nil)
        #expect(html.contains("<title>Opname 6 nov 14.32 · Band·je</title>"))
        #expect(html.contains("Band·je neemt je gesprekken op en zet ze om in tekst."))
        #expect(html.contains("geen tokens") && !html.contains("geen cloud"))
        #expect(html.contains("<link rel=\"icon\" type=\"image/png\" href=\"data:image/png;base64,BBBB\">"))
        #expect(html.contains("<link rel=\"apple-touch-icon\" href=\"data:image/png;base64,BBBB\">"))
        // One centred column: title, facts, player and tabs share one container.
        #expect(html.contains("<header>\n<div class=\"wrap\">"))
    }

    @Test func webExportHasTabsTurnsTimesAndEscapes() {
        let html = WebExport.page(transcript(), summaries: [.init(name: "B", markdown: "x"), .init(name: "A & co", markdown: "y")],
                                  audio: nil, logoBase64: nil, select: "A & co")
        // Several summaries: "Samenvatting · <template>"; one: just "Samenvatting" (as on the iPhone).
        #expect(html.contains(">Samenvatting · B</button>"))
        #expect(html.contains("aria-selected=\"true\">Samenvatting · A &amp; co</button>"))
        let one = WebExport.page(transcript(), summaries: [.init(name: "Vergadering", markdown: "x")], audio: nil, logoBase64: nil)
        #expect(one.contains(">Samenvatting</button>") && !one.contains(">Vergadering</button>"))
        #expect(WebExport.tabTitle("Vergadering", count: 1) == "Samenvatting")
        #expect(html.contains("<div role=\"tabpanel\" id=\"s0\" hidden>"))
        #expect(html.contains("Goedemorgen &lt;Anna&gt; &amp; welkom"))
        #expect(html.contains("data-start=\"1.0\""))
        #expect(html.contains("<a class=\"t\" data-t=\"70.0\">1:10</a>"))
        #expect(html.contains("<span class=\"who\">Anna</span>"))
        #expect(!html.contains("<audio"))
    }

    @Test func markdownToHtml() {
        let h = WebExport.markdown("## Besluiten\n- **Anna** doet het [03:12]\n- om 10:30 uur\n\n1. een\n2. twee\n\nTekst *schuin* & `code`")
        #expect(h.contains("<h3>Besluiten</h3>"))
        #expect(h.contains("<li><strong>Anna</strong> doet het <a class=\"t\" data-t=\"192\">03:12</a></li>"))
        #expect(h.contains("<li>om 10:30 uur</li>")) // a clock time stays text
        #expect(h.contains("<ol>\n<li>een</li>\n<li>twee</li>\n</ol>"))
        #expect(h.contains("<p>Tekst <em>schuin</em> &amp; <code>code</code></p>"))
        #expect(WebExport.seconds("1:02:03") == 3723)
        #expect(WebExport.seconds("12:75") == nil)
    }

    @Test func noPageNextToTheRecordingAnyMore() throws {
        let dir = temp()
        let md = try TranscriptWriter.write(transcript(), for: dir.appendingPathComponent("rec.m4a"))
        #expect(FileManager.default.fileExists(atPath: md.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("rec.html").path))
    }

    @Test func summariesNextToTheTranscriptAreFound() throws {
        let dir = temp()
        let json = dir.appendingPathComponent("rec.json")
        let doc = Summaries.document(transcript(), template: "Vergadering", body: "## Kern\nok")
        try doc.write(to: dir.appendingPathComponent("rec samenvatting Vergadering.md"), atomically: true, encoding: .utf8)
        try doc.write(to: dir.appendingPathComponent("rec summary Job interview.md"), atomically: true, encoding: .utf8)
        try "transcript".write(to: dir.appendingPathComponent("rec.md"), atomically: true, encoding: .utf8)
        try "other".write(to: dir.appendingPathComponent("record2 samenvatting X.md"), atomically: true, encoding: .utf8)
        let found = WebExport.summaries(for: json)
        #expect(found.map(\.name) == ["Job interview", "Vergadering"])
        #expect(found[1].markdown == "## Kern\nok")
    }
}

/// With several summaries the newest comes first (as on the iPhone), not the first by name:
/// a new summary with another template is the one you see.
@Test func summariesNewestFirst() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let json = dir.appendingPathComponent("Opname.json")
    try Data("{}".utf8).write(to: json)
    let a = dir.appendingPathComponent("Opname samenvatting Actiepunten.md")
    let z = dir.appendingPathComponent("Opname samenvatting Zakelijk.md")
    try Data("# s\n\n---\n\naaa".utf8).write(to: a)
    try Data("# s\n\n---\n\nzzz".utf8).write(to: z)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: a.path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: z.path)
    #expect(WebExport.summaries(for: json).map(\.name) == ["Zakelijk", "Actiepunten"])
}

/// The share sheet's text (Mail's body; the subject is the title): what it is, the recording and
/// its date, and the note "Opgenomen met Band·je" with Band·je linked to band.je.
@Test func shareTextNamesTheRecordingAndBandje() {
    var c = Calendar(identifier: .gregorian); c.timeZone = .current
    let date = c.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10, minute: 30))!
    for kind in [ShareText.Kind.audio, .transcript, .webPage] {
        let body = ShareText.body(kind, title: "Planning, donderdag", date: date, locale: Locale(identifier: "nl_NL"))
        #expect(body.string.contains("Planning, donderdag"))
        #expect(body.string.contains("2026"))
        #expect(!body.string.contains("http"))
        let name = (body.string as NSString).range(of: "Band·je")
        #expect(name.location != NSNotFound)
        #expect((body.attribute(.link, at: name.location, effectiveRange: nil) as? URL)?.host == "band.je")
    }
    #expect(ShareText.body(.audio, title: "x", date: date) != ShareText.body(.webPage, title: "x", date: date))
}

/// The App Store review request: from the third transcript, not in the first week, once per version,
/// never while Band·je is busy (recording, dictating, transcribing).
@Test func reviewRequestOnlyAtAGoodMoment() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let week = now.addingTimeInterval(-8 * 86_400)
    #expect(ReviewPrompt.shouldAsk(transcripts: 3, firstLaunch: week, now: now, askedVersion: nil, version: "1.0.0", busy: false))
    #expect(!ReviewPrompt.shouldAsk(transcripts: 2, firstLaunch: week, now: now, askedVersion: nil, version: "1.0.0", busy: false))
    #expect(!ReviewPrompt.shouldAsk(transcripts: 5, firstLaunch: now.addingTimeInterval(-86_400), now: now, askedVersion: nil, version: "1.0.0", busy: false))
    #expect(!ReviewPrompt.shouldAsk(transcripts: 5, firstLaunch: week, now: now, askedVersion: "1.0.0", version: "1.0.0", busy: false))
    #expect(ReviewPrompt.shouldAsk(transcripts: 5, firstLaunch: week, now: now, askedVersion: "1.0.0", version: "1.0.1", busy: false))
    #expect(!ReviewPrompt.shouldAsk(transcripts: 5, firstLaunch: week, now: now, askedVersion: nil, version: "1.0.0", busy: true))
    #expect(!ReviewPrompt.shouldAsk(transcripts: 5, firstLaunch: nil, now: now, askedVersion: nil, version: "1.0.0", busy: false))
}

/// Samenvatten › Nieuw template: a usable template that never replaces an existing one.
@Test func newTemplateGetsAFreeName() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let first = try Summaries.newTemplate(in: dir, language: "nl")
    let second = try Summaries.newTemplate(in: dir, language: "nl")
    let english = try Summaries.newTemplate(in: dir, language: "de")
    #expect(first.lastPathComponent == "Nieuw template.md")
    #expect(second.lastPathComponent == "Nieuw template 2.md")
    #expect(english.lastPathComponent == "New template.md")
    #expect(Summaries.templates(in: dir).map(\.name) == ["New template", "Nieuw template", "Nieuw template 2"])
    #expect(Summaries.templates(in: dir)[1].text.hasPrefix("## Kern"))
}

/// The library shows nothing (and says it is loading) until the recordings folder is known.
@MainActor @Test func libraryWaitsForTheFolder() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let library = Library(root: { dir })
    var known = false
    library.isRootKnown = { known }
    await library.refresh()
    #expect(!library.hasLoaded)
    known = true
    await library.refresh()
    #expect(library.hasLoaded && library.recordings.isEmpty)
}

/// The examples and the summary file word come from the iPhone's data (SummaryTemplates.swift):
/// four per language, the generic one last; a language without data gets English.
@Test func examplesInEveryLanguageAsOnTheIPhone() {
    for lang in ["de", "en", "es", "fr", "it", "nl", "pl", "pt", "ru", "uk"] {
        let examples = Summaries.examples(language: lang)
        #expect(examples.count == 4, "\(lang)")
        #expect(examples.allSatisfy { $0.text.hasPrefix("## ") }, "\(lang)")
        #expect(Summaries.laterExamples.contains(examples[3].name), "\(lang)")
        #expect(!Summaries.fileWord(language: lang).isEmpty)
    }
    #expect(Summaries.examples(language: "nl").map(\.name) == ["Vergadering", "Sollicitatiegesprek", "Klantinterview (productvalidatie)", "Algemene samenvatting"])
    #expect(Summaries.examples(language: "ja") == Summaries.examples(language: "en"))
    #expect(Summaries.fileWord(language: "nl") == "samenvatting")
    #expect(Summaries.fileWord(language: "de") == "Zusammenfassung")
    #expect(Summaries.fileWord(language: "ja") == "summary")
    #expect(Summaries.laterExamples.count == 10)
}
