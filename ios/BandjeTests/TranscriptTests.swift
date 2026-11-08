// SPDX-License-Identifier: GPL-3.0-only
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
        #expect(text.contains("\n\n0:00 · Jan\nGoedemiddag, met Jan."))
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
}
