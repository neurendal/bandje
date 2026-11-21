import BandjeKit
import Foundation
import PDFKit
import Testing
@testable import Bandje

/// Markers on the Mac (specs/markers.md): in the transcript's `.md`, `.json`, PDF and web page, the
/// window's sentence flags, the recording's serial writes and the shortcut.
final class MarkerTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    private func transcript() -> Transcript {
        func seg(_ who: String, _ start: Double, _ text: String) -> Segment {
            let words = text.split(separator: " ").enumerated().map {
                TimedWord(text: String($0.element), start: start + Double($0.offset) * 0.3, end: start + Double($0.offset) * 0.3 + 0.25)
            }
            return Segment(speaker: who, channel: nil, words: words)
        }
        return Transcript(title: "Overleg", duration: 75, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4",
                          segments: [seg("Spreker 1", 1, "Goedemorgen allemaal."), seg("Spreker 2", 12, "Dank je. Wat kost het?"),
                                     seg("Spreker 1", 70, "Tot dinsdag.")],
                          speakerNames: ["Spreker 1": "Anna"], audioFile: "Overleg.m4a")
    }

    private func marked() -> Transcript {
        var t = transcript()
        TranscriptWriter.apply(Markers(times: [0.3, 13.2, 71], notes: ["13.2": "Prijs?", "71.0": "Actiepunt <Daan>"]), to: &t)
        return t
    }

    @Test func markdownPutsAMarkerLineUnderTheTurnItFallsIn() {
        let md = TranscriptWriter.markdown(marked(), locale: Locale(identifier: "nl_NL"))
        #expect(md.contains("---\n\n**0:01 · Anna**  \nGoedemorgen allemaal.\n\n🚩 0:00\n\n"))
        #expect(md.contains("\n\n🚩 0:13 Prijs?\n\n"))
        #expect(md.contains("**1:10 · Anna**  \nTot dinsdag.\n\n🚩 1:11 Actiepunt <Daan>\n\n"))
        #expect(!TranscriptWriter.markdown(transcript(), locale: Locale(identifier: "nl_NL")).contains("🚩"))
    }

    @Test func plainTextHasTimesSpeakersAndMarkersUnderTheTurn() {
        let text = TranscriptWriter.plainText(marked(), locale: Locale(identifier: "nl_NL"))
        #expect(text.contains("\n\n0:01 · Anna\nGoedemorgen allemaal.\n🚩 0:00\n\n"))
        #expect(text.hasSuffix("1:10 · Anna\nTot dinsdag.\n🚩 1:11 Actiepunt <Daan>\n"))
        #expect(!text.contains("**"))
    }

    @Test func markdownWithoutSpeechStillListsTheMarkers() {
        var t = Transcript(title: "x", duration: 10, mode: "sprekers", vozVersion: "v", whoVersion: nil, segments: [])
        TranscriptWriter.apply(Markers(times: [4]), to: &t)
        #expect(TranscriptWriter.markdown(t, locale: Locale(identifier: "nl_NL")).hasSuffix("\n🚩 0:04\n"))
    }

    @Test func markersAndNotesRoundTripThroughTheJson() throws {
        let url = dir.appendingPathComponent("t.json")
        try Data(TranscriptWriter.json(marked())).write(to: url)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        // `markers` stays the iPhone's list of seconds; the notes are a key of their own.
        #expect(raw["markers"] as? [Double] == [0.3, 13.2, 71])
        #expect(raw["markerNotes"] as? [String: String] == ["13.2": "Prijs?", "71.0": "Actiepunt <Daan>"])
        var back = try TranscriptWriter.read(json: url)
        #expect(TranscriptWriter.markers(of: back) == Markers(times: [0.3, 13.2, 71], notes: ["13.2": "Prijs?", "71.0": "Actiepunt <Daan>"]))
        #expect(TranscriptWriter.markdown(back) == TranscriptWriter.markdown(marked()))
        // All removed: no keys left behind.
        TranscriptWriter.apply(Markers(), to: &back)
        let cleared = try JSONSerialization.jsonObject(with: TranscriptWriter.json(back)) as! [String: Any]
        #expect(cleared["markers"] == nil && cleared["markerNotes"] == nil)
    }

    @Test func exportsTakeTheFolderMarkers() throws {
        let folder = dir.appendingPathComponent("Overleg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = folder.appendingPathComponent("Overleg.json")
        // No `.bandje.json` (a file transcribed elsewhere): the transcript's own markers stay.
        #expect(TranscriptWriter.markers(of: TranscriptWriter.withFolderMarkers(marked(), json: json)).count == 3)
        try RecordingMeta(created: Date(timeIntervalSince1970: 5)).write(to: folder)
        try Markers(times: [20], notes: ["20.0": "Nieuw"]).write(to: folder)
        let t = TranscriptWriter.withFolderMarkers(marked(), json: json)
        #expect(TranscriptWriter.markers(of: t) == Markers(times: [20], notes: ["20.0": "Nieuw"]))
        #expect(RecordingMeta.read(from: folder)?.created == Date(timeIntervalSince1970: 5))
    }

    @Test func webPageAndPdfShowTheMarkers() throws {
        let html = WebExport.page(marked(), summaries: [], audio: nil, logoBase64: nil)
        #expect(html.contains("</p></div>\n<div class=\"marker\"><a class=\"t\" data-t=\"13.2\">🚩 0:13</a> <span>Prijs?</span></div>\n"))
        #expect(html.contains("<span>Actiepunt &lt;Daan&gt;</span>"))
        #expect(html.contains("data-t=\"0.3\">🚩 0:00</a></div>"))
        #expect(!WebExport.page(transcript(), summaries: [], audio: nil, logoBase64: nil).contains("class=\"marker\""))
        let pdf = try #require(PDFDocument(data: WebExport.pdf(marked())))
        let text = pdf.page(at: 0)?.string ?? ""
        #expect(text.contains("0:13 Prijs?"))
        #expect(text.contains("1:11 Actiepunt <Daan>"))
    }

    @Test func theWindowFlagsTheSentenceAMarkerFallsIn() {
        let turns = TranscriptLayout.turns(transcript())
        // Turn 1 (12 s) has two sentences: "Dank je." from 12.0, "Wat kost het?" from 12.6.
        let flags = TranscriptBody.flags(Markers(times: [0.3, 12.3, 13.4, 71]), in: turns)
        #expect(flags[0] == [TurnView.Flag(sentence: 0, time: 0.3)])
        #expect(flags[1] == [TurnView.Flag(sentence: 0, time: 12.3), TurnView.Flag(sentence: 1, time: 13.4)])
        #expect(flags[2] == [TurnView.Flag(sentence: 0, time: 71)])
        #expect(TranscriptBody.flags(Markers(), in: turns).isEmpty)
    }

    @Test func flagsWhileRecordingSurviveFinishingTheRecording() async throws {
        let caf = try OutputLocation.newRecording(title: "Gesprek", date: Date(timeIntervalSince1970: 9), in: dir)
        let folder = caf.deletingLastPathComponent()
        // Quick presses from the shortcut, the menu and the window: one queue, none lost.
        for i in 0..<20 { MarkerFile.changeLater(in: folder, { $0.add(at: Double(i) * 2.5) }, failed: {}) }
        await MarkerFile.drain()
        OutputLocation.finishMeta(folder)
        let meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.recording == nil)
        #expect(meta.markers.count == 20)
        #expect(Markers.read(from: folder).times == (0..<20).map { Double($0) * 2.5 })
        let after = try await MarkerFile.change(in: folder) { $0.setNote("Prijs", at: 5) }
        #expect(after.note(at: 5) == "Prijs" && Markers.read(from: folder) == after)
    }

    @Test func markShortcutDefaultsToControlOptionCommandM() {
        #expect(Shortcut.defaultMark.display == "⌃⌥⌘M")
        #expect(Shortcut.defaultMark.menuKey.0 == "m")
        #expect(Set([Shortcut.defaultRecord.display, Shortcut.defaultDictate.display, Shortcut.defaultMark.display]).count == 3)
    }
}
