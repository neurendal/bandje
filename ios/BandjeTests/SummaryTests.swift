// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import Bandje

/// Summaries: transcript lines, chunking, prompts, echo removal, files and display blocks. One
/// live Foundation Models run when the model is available (it is in the iOS 26.5 simulator on a
/// Mac with Apple Intelligence); the longer runs are in the `--summarize` selftests.
@Suite(.serialized)
struct SummaryTests {
    /// The review prompt: after the 3rd and 10th finished transcription, once per version, never automated.
    @Test func reviewPromptMoments() {
        let d = UserDefaults(suiteName: "bandje-review-\(UUID().uuidString)")!
        for _ in 0..<2 { ReviewPrompt.transcriptionDone(defaults: d) }
        #expect(!ReviewPrompt.shouldAsk(defaults: d, version: "1.0.0", automated: false))
        ReviewPrompt.transcriptionDone(defaults: d)
        #expect(ReviewPrompt.shouldAsk(defaults: d, version: "1.0.0", automated: false))
        #expect(!ReviewPrompt.shouldAsk(defaults: d, version: "1.0.0", automated: true))
        ReviewPrompt.markAsked(defaults: d, version: "1.0.0")
        #expect(!ReviewPrompt.shouldAsk(defaults: d, version: "1.0.0", automated: false))
        for _ in 0..<7 { ReviewPrompt.transcriptionDone(defaults: d) }
        #expect(!ReviewPrompt.shouldAsk(defaults: d, version: "1.0.0", automated: false))  // once per version
        #expect(ReviewPrompt.shouldAsk(defaults: d, version: "1.1.0", automated: false))
        ReviewPrompt.markAsked(defaults: d, version: "1.1.0")
        for _ in 0..<20 { ReviewPrompt.transcriptionDone(defaults: d) }
        #expect(!ReviewPrompt.shouldAsk(defaults: d, version: "1.2.0", automated: false))  // after the 10th: no more
    }

    /// Templates as files, as on the Mac: examples once, own files win, names from file names,
    /// one summary file per template and the newest one shown.
    @Test func templatesAndSummaryFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "bandje-templates-\(UUID().uuidString)")
        let folder = root.appending(path: "Templates")
        #expect(Summaries.templates(in: folder, language: "nl").map(\.name) == ["Vergadering", "Sollicitatiegesprek", "Klantinterview (productvalidatie)", "Algemene samenvatting"])
        Summaries.seedIfMissing(folder, language: "nl")
        #expect(Summaries.templates(in: folder, language: "nl").count == 4)
        Summaries.deleteTemplate("Sollicitatiegesprek", in: folder)
        Summaries.deleteTemplate("Algemene samenvatting", in: folder)
        Summaries.seedIfMissing(folder, language: "nl")  // an existing folder stays as it is
        #expect(Summaries.templates(in: folder, language: "nl").count == 2)
        // A later example arrives once in an existing folder, and not again after deleting it.
        let defaults = UserDefaults(suiteName: "bandje-test-\(UUID().uuidString)")!
        Summaries.addLaterExamples(in: folder, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: folder, language: "nl").map(\.name).contains("Algemene samenvatting"))
        Summaries.deleteTemplate("Algemene samenvatting", in: folder)
        Summaries.addLaterExamples(in: folder, language: "nl", defaults: defaults)
        #expect(Summaries.templates(in: folder, language: "nl").count == 2)
        try Summaries.saveTemplate(.init(name: "Eigen: kort", text: "## Kort\nEén zin."), in: folder)
        #expect(Summaries.templates(in: folder, language: "nl").map(\.name).contains("Eigen- kort"))
        Summaries.restoreExamples(in: folder, language: "nl")
        #expect(Summaries.templates(in: folder, language: "nl").count == 5)

        let recording = root.appending(path: "Overleg")
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        let a = Summaries.outputURL(in: recording, template: "Vergadering", language: "nl")
        #expect(a.lastPathComponent == "Overleg samenvatting Vergadering.md")
        try Data("a".utf8).write(to: a)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: a.path)
        let b = Summaries.outputURL(in: recording, template: "Sollicitatiegesprek", language: "nl")
        try Data("b".utf8).write(to: b)
        #expect(Summaries.file(in: recording)?.lastPathComponent == b.lastPathComponent)
        #expect(Summaries.templateName(of: b, in: recording) == "Sollicitatiegesprek")
        #expect(Summaries.templateName(of: Summaries.outputURL(in: recording, language: "nl"), in: recording) == nil)
    }

    private func w(_ text: String, _ start: Double) -> TimedWord { TimedWord(text: text, start: start, end: start + 0.3) }

    private func sample(duration: Double = 6) -> Transcript {
        let turns = [TranscriptWriter.SpeakerTurn(start: 0, end: 3, speaker: 0),
                     TranscriptWriter.SpeakerTurn(start: 3, end: 6, speaker: 1)]
        let words = [w("Goedemiddag,", 0), w("met", 0.4), w("Jan.", 0.8), w("Hallo", 3.2), w("Jan.", 3.6)]
        var t = Transcript(title: "Interview Anna", duration: duration, mode: TranscriptWriter.modeSpeakers, vozVersion: "v",
                           whoVersion: "w", segments: TranscriptWriter.speakerSegments(words, turns: turns))
        t.speakerNames = [TranscriptWriter.speakerLabel(0): "Jan"]
        return t
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func linesUseNamesAndTimes() {
        let lines = Summaries.lines(sample())
        #expect(lines == ["[00:00] Jan: Goedemiddag, met Jan.", "[00:03] \(TranscriptWriter.speakerLabel(1)): Hallo Jan."])
        #expect(Summaries.lines(sample(duration: 4000)).first?.hasPrefix("[0:00:00] Jan:") == true)
        var bare = sample()
        bare.segments = TranscriptWriter.segments(bare.segments.flatMap(\.words), speaker: "")
        #expect(Summaries.lines(bare) == ["[00:00] Goedemiddag, met Jan. Hallo Jan."])
    }

    @Test func chunksKeepWholeLinesUnderTheLimit() {
        let lines = (1...40).map { "[00:\(String(format: "%02d", $0))] Spreker \($0 % 2 + 1): " + String(repeating: "woord ", count: 20) }
        let chunks = Summaries.chunks(lines, limit: 200)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.split(separator: "\n").reduce(0) { $0 + Summaries.estimatedTokens(String($1)) + 1 } <= 200)
        }
        #expect(chunks.joined(separator: "\n") == lines.joined(separator: "\n"))
        #expect(Summaries.chunks([], limit: 100).isEmpty)
        #expect(Summaries.chunks(["kort"], limit: 100) == ["kort"])
    }

    @Test func overlongLineIsCutAtWords() {
        let line = (1...300).map { "w\($0)" }.joined(separator: " ")
        let chunks = Summaries.chunks([line], limit: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { Summaries.estimatedTokens($0) <= 100 })
        #expect(chunks.joined(separator: " ") == line)
    }

    @Test func templateFollowsAppLanguage() {
        let nl = Summaries.template(language: "nl")
        #expect(nl.name == "Vergadering")
        #expect(nl.text.contains("## Actiepunten"))
        let en = Summaries.template(language: "en")
        #expect(en.name == "Meeting")
        #expect(en.text.contains("## Action items"))
        #expect(Summaries.fileWord(language: "nl") == "samenvatting")
        #expect(Summaries.fileWord(language: "en") == "summary")
    }

    @Test func instructionsCarryLanguageRulesAndTemplate() {
        let template = Summaries.template(language: "nl")
        let text = Summaries.instructions(template: template, language: "nl")
        #expect(text.contains("Write in Dutch."))
        #expect(text.contains("Use only information from the transcript."))
        #expect(text.contains("Never invent names, numbers, amounts, dates or facts."))
        #expect(text.hasSuffix(template.text.trimmingCharacters(in: .whitespacesAndNewlines)))
        let fromNotes = Summaries.instructions(template: template, language: "en", fromNotes: true)
        #expect(fromNotes.contains("Write in English."))
        #expect(fromNotes.contains("information from the notes"))
        let notes = Summaries.noteInstructions(template: template, language: "nl", part: 2, of: 3)
        #expect(notes.contains("part 2 of 3"))
        #expect(notes.contains("short bullets in Dutch"))
        #expect(notes.contains("## Besluiten"))
    }

    @Test func languageOfTheConversation() {
        #expect(Summaries.language(of: "Goedemiddag, we gaan de begroting voor het nieuwe jaar doornemen en de afspraak verzetten.") == "nl")
        #expect(Summaries.language(of: "Good afternoon, let's go through the budget for next year and move the meeting.") == "en")
        #expect(Summaries.languageName("nl") == "Dutch")
    }

    @Test func templateEchoIsRemoved() {
        let template = Summaries.template(language: "nl")
        let answer = """
        ## Kern
        De belangrijkste uitkomst van het gesprek in twee of drie zinnen.
        De afspraak is verzet.


        ## Besluiten
        Elk besluit als opsommingsteken: woensdag om 10 uur.
        """
        let cleaned = Summaries.removeTemplateEcho(answer, template: template)
        #expect(cleaned == "## Kern\nDe afspraak is verzet.\n\n## Besluiten\nwoensdag om 10 uur.")
    }

    @Test func repeatedTemplateIsCutAndNotesLoseHeadings() {
        let looped = "## Kern\nA\n\n## Besluiten\n* B\n\n## Kern\nA again\n\n## Besluiten\n* B again"
        #expect(Summaries.firstPass(looped) == "## Kern\nA\n\n## Besluiten\n* B")
        #expect(Summaries.firstPass("## Kern\nA\n## Besluiten\nB") == "## Kern\nA\n## Besluiten\nB")
        #expect(Summaries.cleanNotes("## Kern\n- [00:12] Jan verzet de afspraak\n\n### Besluiten\n  - [01:00] Begroting  ")
                == ["- [00:12] Jan verzet de afspraak", "- [01:00] Begroting"])
    }

    @Test func documentRoundTripAndBlocks() {
        let body = "## Kern\nDe afspraak is **verzet**.\n\n## Besluiten\n*   Woensdag 10 uur\n- Begroting\n• Agenda"
        let doc = Summaries.document(title: "Interview Anna", template: "Vergadering", body: body,
                                     date: Date(timeIntervalSince1970: 1_800_000_000), locale: Locale(identifier: "nl_NL"))
        #expect(doc.hasPrefix("# "))
        #expect(doc.contains("Interview Anna"))
        #expect(doc.contains("Vergadering"))
        #expect(Summaries.body(ofDocument: doc) == body)
        #expect(Summaries.blocks(Summaries.body(ofDocument: doc)) == [
            .heading("Kern"), .paragraph("De afspraak is **verzet**."), .heading("Besluiten"),
            .bullet("Woensdag 10 uur"), .bullet("Begroting"), .bullet("Agenda"),
        ])
        #expect(Summaries.body(ofDocument: "Alleen tekst") == "Alleen tekst")
    }

    @Test func summaryFileIsFoundAndMovesWithRename() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Talk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("t".utf8).write(to: folder.appending(path: "Talk.md"))
        #expect(Summaries.file(in: folder) == nil)  // the transcript's .md is not a summary
        // A Mac summary carries the template name.
        try Data("m".utf8).write(to: folder.appending(path: "Talk samenvatting Vergadering.md"))
        #expect(Summaries.file(in: folder)?.lastPathComponent == "Talk samenvatting Vergadering.md")
        // Ours wins over others.
        let ours = Summaries.outputURL(in: folder, language: "en")
        #expect(ours.lastPathComponent == "Talk summary.md")
        try Data("s".utf8).write(to: ours)
        #expect(Summaries.file(in: folder)?.lastPathComponent.hasPrefix("Talk s") == true)
        #expect(Summaries.file(in: folder)?.lastPathComponent != "Talk samenvatting Vergadering.md")

        let renamed = try Storage.rename(folder, to: "Overleg")
        #expect(FileManager.default.fileExists(atPath: renamed.appending(path: "Overleg summary.md").path))
        #expect(Summaries.file(in: renamed) != nil)
    }

    @Test(.enabled(if: OnDeviceSummarizer.isAvailable, "Foundation Models not available here"))
    func liveSummaryHasTheTemplateHeadings() async throws {
        let words = "Goedemiddag Ellen. We verzetten de afspraak van dinsdag naar woensdagochtend om tien uur. Jan maakt vrijdag de begroting af."
            .split(separator: " ").enumerated().map { w(String($1), Double($0) * 0.4) }
        let t = Transcript(title: "Overleg", duration: 20, mode: TranscriptWriter.modeNoSpeakers, vozVersion: "v",
                           whoVersion: nil, segments: TranscriptWriter.segments(words, speaker: ""))
        let template = Summaries.template(language: "nl")
        let body = try await OnDeviceSummarizer.summarize(t, template: template) { _ in }
        let headings = Summaries.blocks(body).compactMap { block -> String? in
            if case .heading(let h) = block { h } else { nil }
        }
        #expect(headings == ["Kern", "Besluiten", "Actiepunten", "Open vragen", "Vervolg"])
    }
}
