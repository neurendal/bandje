// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Bandje

/// "Share as web page" (ported from the Mac app's tests in SummaryTests and LibraryTests).
@Suite(.serialized)
struct WebExportTests {
    private func transcript() -> Transcript {
        let a = Segment(speaker: "Anna", words: [TimedWord(text: "Goedemorgen <Anna> & welkom", start: 1, end: 3)], speakerNumber: 0)
        let b = Segment(speaker: "Joris", words: [TimedWord(text: "Dag allemaal.", start: 70, end: 72)], speakerNumber: 1)
        return Transcript(title: "Overleg", duration: 80, mode: TranscriptWriter.modeSpeakers, vozVersion: "v",
                          whoVersion: "w", segments: [a, b])
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func pageIsSelfContainedAndBranded() {
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
        #expect(html.contains("<noscript>") && !html.contains("no cloud") && !html.contains("geen cloud"))
        #expect(html.contains("<link rel=\"icon\" type=\"image/png\" href=\"data:image/png;base64,BBBB\">"))
        #expect(html.contains("<link rel=\"apple-touch-icon\" href=\"data:image/png;base64,BBBB\">"))
        #expect(html.components(separatedBy: "<div class=\"wrap\">").count == 3)  // header and footer
    }

    @Test func pageForALook() async throws {
        // build/web-page.html with a real logo, for a look in a browser (the test host can write build/).
        let logo = await WebExport.logoPNG()?.base64EncodedString()
        let html = WebExport.page(transcript(), summaries: [.init(name: "Samenvatting", markdown: "## Kern\nHet overleg [00:01].")],
                                  audio: nil, logoBase64: logo)
        let out = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "build/web-page.html")
        try Data(html.utf8).write(to: out)
        #expect(logo != nil)
    }

    @Test func pageHasTabsTurnsTimesAndEscapes() {
        let html = WebExport.page(transcript(), summaries: [.init(name: "B", markdown: "x"), .init(name: "A & co", markdown: "y")],
                                  audio: nil, logoBase64: nil, select: "A & co")
        #expect(html.contains(">B</button>"))
        #expect(html.contains("aria-selected=\"true\">A &amp; co</button>"))
        #expect(html.contains("<div role=\"tabpanel\" id=\"s0\" hidden>"))
        #expect(html.contains("Goedemorgen &lt;Anna&gt; &amp; welkom"))
        #expect(html.contains("data-start=\"1.0\""))
        #expect(html.contains("<a class=\"t\" data-t=\"70.0\">1:10</a>"))
        #expect(html.contains("<span class=\"who\">Anna</span>"))
        #expect(!html.contains("<audio"))
    }

    /// The PDF share: a real PDF with the title and the text, longer transcripts over several pages.
    @Test func transcriptPDF() throws {
        let pdf = SharedPDF.pdf(transcript())
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let short = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        #expect(short.numberOfPages == 1)
        var long = transcript()
        long.segments = (0..<400).map { i in
            Segment(speaker: i % 2 == 0 ? "Anna" : "Joris",
                    words: [TimedWord(text: "Een zin die een paar keer terugkomt in dit lange gesprek.", start: Double(i), end: Double(i) + 0.5)],
                    speakerNumber: i % 2)
        }
        let doc = try #require(CGPDFDocument(CGDataProvider(data: SharedPDF.pdf(long) as CFData)!))
        #expect(doc.numberOfPages > 3)
    }

    /// The list shows a length that can't be read as a time of day ("14:01 · 20 min").
    @Test func spokenDurations() {
        #expect(spokenDuration(48).contains("48"))
        #expect(spokenDuration(20 * 60 + 40).contains("21") && !spokenDuration(20 * 60 + 40).contains(":"))
        #expect(!spokenDuration(3725).contains(":"))
    }

    @Test func markdownToHtml() {
        let h = WebExport.markdown("## Besluiten\n- **Anna** doet het [03:12]\n- om 10:30 uur\n\n1. een\n2. twee\n\nTekst *schuin* & `code`")
        #expect(h.contains("<h3>Besluiten</h3>"))
        #expect(h.contains("<li><strong>Anna</strong> doet het <a class=\"t\" data-t=\"192\">03:12</a></li>"))
        #expect(h.contains("<li>om 10:30 uur</li>"))  // a clock time stays text
        #expect(h.contains("<ol>\n<li>een</li>\n<li>twee</li>\n</ol>"))
        #expect(h.contains("<p>Tekst <em>schuin</em> &amp; <code>code</code></p>"))
        #expect(WebExport.seconds("1:02:03") == 3723)
        #expect(WebExport.seconds("12:75") == nil)
    }

    @Test func summariesOfBothAppsAreFound() throws {
        let dir = try tempDir().appending(path: "rec")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let doc = Summaries.document(title: "rec", template: "Vergadering", body: "## Kern\nok")
        try doc.write(to: dir.appending(path: "rec samenvatting.md"), atomically: true, encoding: .utf8)          // iPhone
        try doc.write(to: dir.appending(path: "rec summary Job interview.md"), atomically: true, encoding: .utf8) // Mac
        try "transcript".write(to: dir.appending(path: "rec.md"), atomically: true, encoding: .utf8)
        let found = WebExport.summaries(in: dir)
        #expect(found.count == 2 && found.contains { $0.name == "Job interview" })
        #expect(found.allSatisfy { $0.markdown == "## Kern\nok" })
    }

    @Test func compactAudioIsMonoSpeechQuality() async throws {
        let dir = try tempDir()
        let url = dir.appending(path: "stereo.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960_000)!
            buffer.frameLength = 960_000
            for c in 0..<2 { for i in 0..<960_000 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * 0.05)) * 0.3 } }
            try file.write(from: buffer)
        }
        let data = try await WebExport.compactAudio(url)
        let out = dir.appending(path: "compact.m4a")
        try data.write(to: out)
        let compact = try AVAudioFile(forReading: out)
        #expect(compact.fileFormat.channelCount == 1 && compact.fileFormat.sampleRate == 22_050)
        #expect(abs(Double(compact.length) / 22_050 - 20) < 0.2)  // the whole 20 s
        #expect(data.count < 110_000)                              // ~32 kbit/s: 80 kB + header
    }
}
