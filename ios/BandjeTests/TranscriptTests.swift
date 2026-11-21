// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import Foundation
import Testing
@testable import Bandje

/// Transcript model, layout, chunking and the reader. The live Voz/Who runs are in the
/// `--transcribe` selftests (scripts/dev/score.py) and one short run here.
@Suite(.serialized)
struct TranscriptTests {
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/fixtures")

    private func w(_ text: String, _ start: Double, _ end: Double? = nil) -> TimedWord {
        TimedWord(text: text, start: start, end: end ?? start + 0.3)
    }

    @Test func segmentsSplitOnPause() {
        let words = [w("Hallo", 0), w("daar.", 0.4), w("Nieuw", 2.0)]
        let segs = TranscriptWriter.segments(words, speaker: "")
        #expect(segs.count == 2)
        #expect(segs[0].text == "Hallo daar.")
        #expect(segs[1].start == 2.0)
    }

    @Test func speakersByOverlapAndNearestTurn() {
        let turns = [TranscriptWriter.SpeakerTurn(start: 0, end: 2, speaker: 0),
                     TranscriptWriter.SpeakerTurn(start: 2.2, end: 4, speaker: 1)]
        let words = [w("a", 0.1), w("b", 1.0), w("c", 2.5), w("d", 5.0)]
        #expect(TranscriptWriter.assignSpeakers(words, turns: turns) == [0, 0, 1, 1])
        let segs = TranscriptWriter.speakerSegments(words, turns: turns)
        #expect(segs.map(\.speakerNumber) == [0, 1, 1])
        #expect(TranscriptWriter.assignSpeakers(words, turns: []) == [nil, nil, nil, nil])
    }

    private func sample() -> Transcript {
        let turns = [TranscriptWriter.SpeakerTurn(start: 0, end: 3, speaker: 0),
                     TranscriptWriter.SpeakerTurn(start: 3, end: 6, speaker: 1)]
        let words = [w("Goedemiddag,", 0), w("met", 0.4), w("Jan.", 0.8), w("Hallo", 3.2), w("Jan.", 3.6)]
        return Transcript(title: "Interview Anna", duration: 6, mode: TranscriptWriter.modeSpeakers, vozVersion: "v",
                          whoVersion: "w", segments: TranscriptWriter.speakerSegments(words, turns: turns),
                          audioFile: "Interview Anna.m4a", markers: [1.5, 4])
    }

    @Test func jsonRoundTripKeepsEverything() throws {
        var t = sample()
        t.speakerNames = [TranscriptWriter.speakerLabel(0): "Jan"]
        t.recorded = Date(timeIntervalSince1970: 1_793_900_000)
        t.location = RecordedLocation(latitude: 52.37, longitude: 4.89, accuracy: 10)
        let url = FileManager.default.temporaryDirectory.appending(path: "t-\(UUID().uuidString).json")
        try TranscriptWriter.write(t, json: url)
        let back = try TranscriptWriter.read(json: url)
        #expect(back == t)
        let md = try String(contentsOf: url.deletingPathExtension().appendingPathExtension("md"), encoding: .utf8)
        #expect(md.hasPrefix("# Interview Anna"))
        #expect(md.contains("**0:00 · Jan**  \nGoedemiddag, met Jan."))
        #expect(md.contains("**0:03 · \(TranscriptWriter.speakerLabel(1))**"))
        #expect(md.contains("📼 ") && md.contains("📍 52.3700, 4.8900") && md.contains("band.je"))
        #expect(TranscriptWriter.searchText(json: url)?.search.contains("Goedemiddag") == true)
        #expect(TranscriptWriter.searchText(json: url)?.preview.isEmpty == false)
        let text = TranscriptWriter.plainText(t)
        #expect(text.hasPrefix("Interview Anna\n📼 "))
        // The marker at 1.5 s falls in Jan's turn: its line comes right after the text, as in the
        // transcript screen (specs/markers.md 6).
        #expect(text.contains("\n\n0:00 · Jan\nGoedemiddag, met Jan.\n🚩 0:01\n\n"))
    }

    /// Markers and notes: kept in the .json, a line under their turn in the .md and the text.
    @Test func markersAndNotesInTheExports() throws {
        var t = sample()
        var m = t.markerSet
        m.setNote("Actiepunt Jan", at: 4)
        t.markerSet = m
        let url = FileManager.default.temporaryDirectory.appending(path: "t-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try TranscriptWriter.write(t, json: url)
        let back = try TranscriptWriter.read(json: url)
        #expect(back.markers == [1.5, 4])
        #expect(back.markerNotes == ["4.0": "Actiepunt Jan"])
        let md = TranscriptWriter.markdown(t)
        #expect(md.contains("Goedemiddag, met Jan.\n\n🚩 0:01\n\n**0:03 · \(TranscriptWriter.speakerLabel(1))**"))
        #expect(md.hasSuffix("\n\n🚩 0:04 Actiepunt Jan\n\n"))
        // An older transcript without notes reads as before.
        let old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var stripped = old
        stripped["markerNotes"] = nil
        try JSONSerialization.data(withJSONObject: stripped).write(to: url)
        #expect(try TranscriptWriter.read(json: url).markerNotes.isEmpty)
    }

    /// In the transcript screen: a flag before the sentence a marker falls in.
    @Test func markersPlacedAtSentences() {
        let t = sample()
        let turns = TranscriptLayout.turns(t)
        let places = TranscriptBody.markerPlaces(t.markerSet, in: turns)
        #expect(places.values.flatMap(\.all).sorted() == [1.5, 4])
        #expect(places[turns[0].id]?.all == [1.5])
        #expect(places[turns[1].id]?.sentences[0] == [4])
    }

    @Test func renamingOneSpeakerRenamesAllTheirTurns() {
        var t = sample()
        t.segments += TranscriptWriter.speakerSegments([w("Weer", 10)], turns: [.init(start: 9, end: 11, speaker: 0)])
        t.speakerNames = [TranscriptWriter.speakerLabel(0): "Anna"]
        let md = TranscriptWriter.markdown(t)
        #expect(md.components(separatedBy: " · Anna**").count == 3)
        #expect(t.speakerLabels.count == 2)
    }

    @Test func noSpeakersHasNoLabels() {
        let t = Transcript(title: "x", duration: 2, mode: TranscriptWriter.modeNoSpeakers, vozVersion: "v", whoVersion: nil,
                           segments: TranscriptWriter.segments([w("Hallo.", 0)], speaker: ""))
        #expect(t.speakerLabels.isEmpty)
        #expect(TranscriptWriter.markdown(t).contains("**0:00**  \nHallo.\n"))
        #expect(TranscriptLayout.turns(t).first?.speaker == "")
    }

    @Test func sentencesAndActiveSentence() {
        let turns = TranscriptLayout.turns(sample())
        #expect(turns.count == 2)
        #expect(turns[0].sentences.map(\.text) == ["Goedemiddag, met Jan."])
        let words = [w("Een", 0), w("twee.", 0.4), w("Drie", 0.8), w("vier", 1.2), w("vijf", 3.0)]
        let t = Transcript(title: "", duration: 4, mode: "", vozVersion: "", whoVersion: nil,
                           segments: TranscriptWriter.segments(words, speaker: "S", pause: 5))
        let layout = TranscriptLayout.turns(t)
        #expect(layout[0].sentences.map(\.text) == ["Een twee.", "Drie vier", "vijf"])
        #expect(TranscriptLayout.active(at: 0.9, in: layout)! == (0, 1))
        #expect(TranscriptLayout.active(at: 3.1, in: layout)! == (0, 2))
        #expect(TranscriptLayout.active(at: -1, in: layout) == nil)
    }

    @Test func longTurnsBecomeParagraphs() {
        // 150 s of one speaker, a sentence every 5 s: paragraphs of about 60 s.
        let words = (0..<30).map { w("zin\($0).", Double($0) * 5) }
        let t = Transcript(title: "", duration: 150, mode: "", vozVersion: "", whoVersion: nil,
                           segments: TranscriptWriter.segments(words, speaker: "S", pause: 10))
        let layout = TranscriptLayout.turns(t)
        #expect(layout.count == 3)
        #expect(layout.map(\.continued) == [false, true, true])
        #expect(layout.map(\.id) == [0, 1, 2])
        #expect(layout.flatMap(\.sentences).count == 30)
    }

    @Test func searchMatches() {
        let layout = TranscriptLayout.turns(sample())
        #expect(TranscriptBody.matches(in: layout, query: "jan").count == 2)
        #expect(TranscriptBody.matches(in: layout, query: " ").isEmpty)
    }

    @Test func cutPointIsInTheQuietPart() {
        var samples = [Float](repeating: 0.5, count: 16_000 * 10)
        for i in 150_000..<151_600 { samples[i] = 0 } // 100 ms of silence at 9.4 s
        let cut = Chunking.cutPoint(samples, target: 160_000, search: 48_000, window: 1_600)
        #expect(cut >= 150_000 && cut <= 151_600)
        #expect(Chunking.cutPoint([0.1, 0.2], target: 10, search: 5, window: 4) == 2)
        #expect(Chunking.isSilent([Float](repeating: 0.00005, count: 100)))
        #expect(!Chunking.isSilent([0, 0.2]))
    }

    @Test func readerReadsInPiecesAtSixteenKilohertz() throws {
        let url = Self.fixtures.appending(path: "nl_dialogue.wav")
        try #require(FileManager.default.fileExists(atPath: url.path), "run make fixtures")
        let reader = try MonoReader(url: url, rate: 16_000)
        var total = 0
        while true {
            let piece = try reader.read(100_000)
            if piece.isEmpty { break }
            #expect(piece.count <= 100_000)
            total += piece.count
        }
        #expect(abs(total - reader.expectedFrames) < 2_000)
        #expect(abs(Double(total) / 16_000 - reader.duration) < 0.1)
        let all = try MonoReader(url: url, rate: 16_000).readAll()
        #expect(all.count == total)
    }

    @Test func unreadableAudioGivesAClearError() throws {
        let url = Self.fixtures.appending(path: "corrupt.m4a")
        try #require(FileManager.default.fileExists(atPath: url.path), "run make fixtures")
        #expect(throws: TranscriptionError.self) { try MonoReader(url: url, rate: 16_000) }
    }

    @Test func modelsInTheBundleAreComplete() {
        #expect(Transcriber.vozPresent())
        #expect(Transcriber.whoPresent())
    }

    /// One real Voz run (no speakers) on a short fixture, and a cancelled one.
    @Test func transcribesAndCancels() async throws {
        let url = Self.fixtures.appending(path: "nl_xander_1.wav")
        try #require(FileManager.default.fileExists(atPath: url.path), "run make fixtures")
        let t = try await Transcriber.shared.transcribe(url, title: "x", speakers: false, markers: [2]) { _ in }
        let text = t.segments.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("afspraak"))
        #expect(text.contains("woensdagochtend"))
        #expect(t.markers == [2])
        #expect(t.whoVersion == nil)

        let task = Task { try await Transcriber.shared.transcribe(url, title: "x", speakers: false, markers: []) { _ in } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: The shared document (specs/share.md)

    @Test func sharedDocumentPutsSummariesBeforeTheTurns() throws {
        let t = sample()
        let dir = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)/Interview Anna", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try Data("transcript".utf8).write(to: dir.appending(path: "Interview Anna.md"))  // not a summary
        let older = dir.appending(path: "Interview Anna samenvatting Vergadering.md")
        try Data(Summaries.document(title: "Interview Anna", template: "Vergadering", body: "## Kern\nDe afspraak is **verzet**.",
                                    locale: Locale(identifier: "nl_NL")).utf8).write(to: older)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: older.path)
        let newer = dir.appending(path: "Interview Anna samenvatting Actiepunten.md")
        try Data(Summaries.document(title: "Interview Anna", template: "Actiepunten", body: "- Jan belt terug",
                                    locale: Locale(identifier: "nl_NL")).utf8).write(to: newer)

        // Newest first, as the app shows them; the newest is the one the summary tab shows.
        let parts = Summaries.parts(in: dir)
        #expect(parts.map(\.file.lastPathComponent) == [newer.lastPathComponent, older.lastPathComponent])
        #expect(Summaries.files(in: dir).first == Summaries.file(in: dir))
        // "Summary · <template>"; the body without the file's heading and metadata line.
        #expect(parts[0].heading.hasSuffix(" · Actiepunten") && parts[1].heading.hasSuffix(" · Vergadering"))
        #expect(parts[0].body == "- Jan belt terug")
        #expect(parts[1].body == "## Kern\nDe afspraak is **verzet**.")
        #expect(Summaries.part(older, markdown: "Alleen tekst", in: dir).body == "Alleen tekst")

        let text = TranscriptWriter.plainText(t, summaries: parts)
        #expect(text.hasPrefix("Interview Anna\n"))
        let first = try #require(text.range(of: parts[0].heading)), second = try #require(text.range(of: "De afspraak"))
        let turn = try #require(text.range(of: "Goedemiddag, met"))
        #expect(first.lowerBound < second.lowerBound && second.lowerBound < turn.lowerBound)
        #expect(!text.contains("Apple Intelligence") && !text.contains("---"))
        // Plain text: no Markdown marks, bullets as "•", a "Transcript" heading before the turns.
        #expect(text.contains("• Jan belt terug") && text.contains("Kern\nDe afspraak is verzet.") && !text.contains("**"))
        #expect(text.contains("\n\n\(String(localized: "Transcript"))\n\n0:00 · "))
        // Only the summaries: the title block stays, no turns.
        let onlySummary = TranscriptWriter.plainText(t, summaries: [parts[1]], turns: false)
        #expect(onlySummary.contains("De afspraak") && !onlySummary.contains("Jan belt") && !onlySummary.contains("Goedemiddag"))
        #expect(onlySummary.hasPrefix("Interview Anna\n") && !onlySummary.contains("\n\(String(localized: "Transcript"))\n"))

        let md = TranscriptWriter.markdown(t, summaries: parts)
        #expect(md.hasPrefix("# Interview Anna\n"))
        #expect(md.contains("## \(parts[0].heading)\n\n- Jan belt terug\n\n---\n\n## \(parts[1].heading)\n\n### Kern"))
        let mdTurn = try #require(md.range(of: "**0:00")), mdSummary = try #require(md.range(of: "### Kern"))
        #expect(mdSummary.lowerBound < mdTurn.lowerBound)
        #expect(md.contains("## \(String(localized: "Transcript"))\n\n**0:00"))
        #expect(!md.contains("_Template"))
        let mdOnly = TranscriptWriter.markdown(t, summaries: [parts[0]], turns: false)
        #expect(!mdOnly.contains("**0:00") && mdOnly.hasSuffix("- Jan belt terug\n"))

        // No summary: exactly the transcript as before.
        #expect(TranscriptWriter.plainText(t, summaries: []) == TranscriptWriter.plainText(t))
        #expect(TranscriptWriter.markdown(t, summaries: []) == TranscriptWriter.markdown(t))
        #expect(Summaries.parts(in: dir.appending(path: "nothing")).isEmpty)

        // The PDF is made with and without the turns.
        #expect(SharedPDF.pdf(t, summaries: parts).count > 1000)
        #expect(SharedPDF.pdf(t, summaries: parts, turns: false).count > 1000)
    }

    @Test func copyThisTurn() {
        var t = sample()
        t.speakerNames = [TranscriptWriter.speakerLabel(0): "Jan"]
        let turns = TranscriptLayout.turns(t)
        #expect(TranscriptBody.copyText(turns[0], in: t) == "0:00 · Jan\nGoedemiddag, met Jan.")
        #expect(Summaries.plainText(.paragraph("De afspraak is **verzet**.")) == "De afspraak is verzet.")
        #expect(Summaries.plainText(.bullet("*Jan* belt")) == "Jan belt")
    }
}
