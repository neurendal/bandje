import BandjeKit
import Foundation
import PDFKit
import Testing
@testable import Bandje

/// Share › PDF, Text, Markdown and Print (specs/share.md): one document, the chosen summaries
/// first, then the transcript.
struct ShareTests {
    private let nl = Locale(identifier: "nl_NL")

    private func transcript() -> Transcript {
        func seg(_ who: String, _ start: Double, _ text: String) -> Segment {
            let words = text.split(separator: " ").enumerated().map {
                TimedWord(text: String($0.element), start: start + Double($0.offset) * 0.3, end: start + Double($0.offset) * 0.3 + 0.25)
            }
            return Segment(speaker: who, channel: nil, words: words)
        }
        var t = Transcript(title: "Overleg", duration: 75, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4",
                           segments: [seg("Spreker 1", 1, "Goedemorgen allemaal."), seg("Spreker 2", 12, "Dank je. Wat kost het?")],
                           speakerNames: ["Spreker 1": "Anna"], audioFile: "Overleg.m4a")
        TranscriptWriter.apply(Markers(times: [13], notes: [:]), to: &t)
        return t
    }

    private let summaries = [
        WebExport.Summary(name: "Zakelijk", markdown: "## Besluiten\n\n- **Prijs** volgt\n- Dinsdag weer"),
        WebExport.Summary(name: "Actiepunten", markdown: "Anna belt de klant."),
    ]

    private func index(_ needle: String, in s: String) -> String.Index? { s.range(of: needle)?.lowerBound }

    @Test func withoutSummariesTheDocumentIsTheTranscript() {
        let doc = ShareDocument(transcript: transcript())
        #expect(doc.markdown(locale: nl) == TranscriptWriter.markdown(transcript(), locale: nl))
        #expect(doc.plainText(locale: nl) == TranscriptWriter.plainText(transcript(), locale: nl))
        #expect(doc.kind == .transcript)
        #expect(!doc.markdown(locale: nl).contains("## Transcript"))
    }

    @Test func markdownHasTitleThenSummariesInOrderThenTranscript() throws {
        let md = ShareDocument(transcript: transcript(), summaries: summaries).markdown(locale: nl)
        let title = try #require(index("# Overleg", in: md))
        let first = try #require(index("## Samenvatting · Zakelijk", in: md))
        let second = try #require(index("## Samenvatting · Actiepunten", in: md))
        let turns = try #require(index("## Transcript", in: md))
        let turn = try #require(index("**0:01 · Anna**", in: md))
        #expect(title < first && first < second && second < turns && turns < turn)
        // The summary's own heading one level down; its text as written; the marker under its turn.
        #expect(md.contains("### Besluiten"))
        #expect(md.contains("- **Prijs** volgt"))
        #expect(md.contains("🚩 0:13"))
        // Only the body: never the summary file's title or metadata line.
        #expect(!md.contains("Apple Intelligence"))
    }

    @Test func plainTextHasNoMarkdown() throws {
        let text = ShareDocument(transcript: transcript(), summaries: summaries).plainText(locale: nl)
        let first = try #require(index("Samenvatting · Zakelijk", in: text))
        let second = try #require(index("Samenvatting · Actiepunten", in: text))
        let turns = try #require(index("\nTranscript\n", in: text))
        let turn = try #require(index("0:01 · Anna\nGoedemorgen allemaal.", in: text))
        #expect(text.hasPrefix("Overleg\n"))
        #expect(first < second && second < turns && turns < turn)
        #expect(text.contains("Besluiten\n"))
        #expect(text.contains("• Prijs volgt"))
        #expect(!text.contains("**") && !text.contains("#"))
    }

    @Test func partsCanBeLeftOut() {
        let onlySummary = ShareDocument(transcript: transcript(), summaries: [summaries[1]], includesTranscript: false)
        for s in [onlySummary.markdown(locale: nl), onlySummary.plainText(locale: nl)] {
            #expect(s.contains("Overleg"))  // the title block stays at the top
            #expect(s.contains("Samenvatting · Actiepunten"))
            #expect(!s.contains("Zakelijk"))
            #expect(!s.contains("Goedemorgen"))
            #expect(!s.contains("Transcript"))
        }
        #expect(onlySummary.kind == .summary)
        let both = ShareDocument(transcript: transcript(), summaries: [summaries[0]])
        #expect(both.kind == .summaryAndTranscript)
        #expect(!both.markdown(locale: nl).contains("Actiepunten"))
    }

    @Test func pdfHasTheSameParts() throws {
        let pdf = try #require(PDFDocument(data: ShareDocument(transcript: transcript(), summaries: summaries).pdf(locale: nl)))
        let text = try #require(pdf.string)
        let first = try #require(index("Samenvatting · Zakelijk", in: text))
        let second = try #require(index("Samenvatting · Actiepunten", in: text))
        let turn = try #require(index("Goedemorgen", in: text))
        #expect(first < second && second < turn)
        #expect(text.contains("Prijs volgt") && !text.contains("**"))
        let noTurns = try #require(PDFDocument(data: ShareDocument(transcript: transcript(), summaries: summaries, includesTranscript: false).pdf(locale: nl)))
        #expect(!(noTurns.string ?? "").contains("Goedemorgen"))
        #expect((noTurns.string ?? "").contains("Anna belt de klant."))
    }

    @Test func copyThisTurnIsTimeSpeakerAndText() {
        let t = transcript()
        let turns = TranscriptLayout.turns(t)
        #expect(TranscriptBody.copyText(of: turns[0], in: t) == "0:01 · Anna\nGoedemorgen allemaal.")
        #expect(TranscriptBody.copyText(of: turns[1], in: t) == "0:12 · Spreker 2\nDank je. Wat kost het?")
    }
}
