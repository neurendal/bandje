import Foundation
import Testing
@testable import Bandje

struct TranscriptTests {
    private func w(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

    @Test func segmentsSplitOnPauseLongerThanPointEight() {
        let words = [w("a", 0, 0.3), w("b", 0.5, 0.9), w("c", 1.7, 2.0), w("d", 2.9, 3.1)]
        let segs = TranscriptWriter.segments(words, speaker: "Ik", channel: 0)
        // 0.9 -> 1.7 is exactly 0.8 (same segment), 2.0 -> 2.9 is 0.9 (new segment).
        #expect(segs.map(\.text) == ["a b c", "d"])
        #expect(segs[0].start == 0)
        #expect(segs[0].end == 2.0)
    }

    @Test func mergeOrdersOverlappingAndConsecutiveSegmentsWithLabels() {
        let left = TranscriptWriter.segments([w("hoi", 0.0, 0.4), w("hoe", 0.5, 0.8), w("gaat", 5.0, 5.3), w("het", 5.4, 5.6)],
                                             speaker: TranscriptWriter.me, channel: 0)
        let right = TranscriptWriter.segments([w("hallo", 1.0, 1.5), w("goed", 5.2, 5.5), w("hoor", 9.0, 9.3)],
                                              speaker: TranscriptWriter.otherSide, channel: 1)
        let merged = TranscriptWriter.merge(left, right)
        #expect(merged.map(\.speaker) == ["Ik", "Andere kant", "Ik", "Andere kant", "Andere kant"])
        #expect(merged.map(\.text) == ["hoi hoe", "hallo", "gaat het", "goed", "hoor"])
        #expect(merged.map(\.channel) == [0, 1, 0, 1, 1])
        // Consecutive segments of the same speaker are joined for the .md.
        let joined = TranscriptWriter.joinConsecutive(merged)
        #expect(joined.map(\.speaker) == ["Ik", "Andere kant", "Ik", "Andere kant"])
        #expect(joined.last?.text == "goed hoor")
    }

    @Test func mergeTieKeepsLeftFirst() {
        let left = [Segment(speaker: "Ik", channel: 0, words: [w("ja", 2, 2.2)])]
        let right = [Segment(speaker: "Andere kant", channel: 1, words: [w("nee", 2, 2.3)])]
        #expect(TranscriptWriter.merge(left, right).map(\.speaker) == ["Ik", "Andere kant"])
    }

    /// Synthetic stereo at 16 kHz: right speaks 1-3 s; left has a -20 dB copy of it (crosstalk)
    /// plus the user's own speech at 5-6 s, loud, while right also talks quietly over it.
    @Test func crosstalkFilterDropsQuietLeftCopyAndKeepsOwnSpeech() {
        let rate = 16_000.0
        let n = Int(8 * rate)
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        for i in Int(1 * rate)..<Int(3 * rate) {
            let s = Float(0.5 * sin(Double(i) * 0.07))
            right[i] = s
            left[i] = s * 0.1 // -20 dB
        }
        for i in Int(0.4 * rate)..<Int(0.9 * rate) { // my own "oké" just before the other side starts
            left[i] = Float(0.5 * sin(Double(i) * 0.05))
        }
        for i in Int(5 * rate)..<Int(6 * rate) {
            left[i] = Float(0.5 * sin(Double(i) * 0.05))
            right[i] = Float(0.2 * sin(Double(i) * 0.09)) // other side talks over the user
        }
        let rightSegs = [Segment(speaker: "Andere kant", channel: 1, words: [w("hallo", 1.0, 1.6), w("daar", 1.7, 3.0)]),
                         Segment(speaker: "Andere kant", channel: 1, words: [w("ja", 5.0, 6.0)])]
        // Own word and the leak within 0.8 s: one segment, of which only the leak must go.
        let leftSegs = [Segment(speaker: "Ik", channel: 0, words: [w("oké", 0.4, 0.9), w("hallo", 1.05, 1.6), w("daar", 1.7, 2.9)]),
                        Segment(speaker: "Ik", channel: 0, words: [w("prima", 5.0, 6.0)])]
        let settings = TranscriptWriter.CrosstalkSettings(overlap: 0.6, db: 6)
        let out = TranscriptWriter.filterCrosstalk(left: leftSegs, right: rightSegs, leftSamples: left, rightSamples: right,
                                                   sampleRate: rate, settings: settings)
        #expect(out.removed == 1)
        #expect(out.kept.map(\.text) == ["oké", "prima"])
        #expect(out.kept.allSatisfy { $0.speaker == "Ik" && $0.channel == 0 })

        // Without overlap in time nothing is removed, however quiet the left channel is.
        let lonely = [Segment(speaker: "Ik", channel: 0, words: [w("hm", 7.0, 7.5)])]
        #expect(TranscriptWriter.filterCrosstalk(left: lonely, right: rightSegs, leftSamples: left, rightSamples: right,
                                                 sampleRate: rate, settings: settings).removed == 0)
        // A stricter dB threshold (copy only 20 dB down, threshold 30) keeps the copy.
        let strict = TranscriptWriter.CrosstalkSettings(overlap: 0.6, db: 30)
        #expect(TranscriptWriter.filterCrosstalk(left: leftSegs, right: rightSegs, leftSamples: left, rightSamples: right,
                                                 sampleRate: rate, settings: strict).removed == 0)
    }

    @Test func speakersOnTheMicrophone() {
        // Two people at one Mac: the crosstalk filter keeps each word's speaker.
        let sp = { (n: Int, words: [TimedWord]) in
            Segment(speaker: TranscriptWriter.speakerLabel(n), channel: 0, words: words, speakerNumber: n)
        }
        let room = [sp(0, [w("goedemorgen", 0.2, 0.9)]), sp(1, [w("hoi", 1.0, 1.3), w("allemaal", 1.4, 1.9)]), sp(0, [w("zullen", 3.0, 3.4)])]
        let silence = [Float](repeating: 0, count: 16_000 * 4)
        let kept = TranscriptWriter.filterCrosstalk(left: room, right: [], leftSamples: silence, rightSamples: silence,
                                                    sampleRate: 16_000, settings: .init(overlap: 0.6, db: 6))
        #expect(kept.kept == room)
        // Still two speakers: unchanged. One speaker left (the other was a leak the filter removed): "Ik" again,
        // split at pauses like a plain left channel.
        #expect(TranscriptWriter.unsplitIfOneSpeaker(room, label: "Ik") == room)
        let one = [sp(0, [w("goedemorgen", 0.2, 0.9)]), sp(0, [w("zullen", 3.0, 3.4), w("we", 3.5, 3.7)])]
        let ik = TranscriptWriter.unsplitIfOneSpeaker(one, label: "Ik")
        #expect(ik.map(\.speaker) == ["Ik", "Ik"] && ik.map(\.text) == ["goedemorgen", "zullen we"])
        #expect(ik.allSatisfy { $0.speakerNumber == nil && $0.channel == 0 })
        let plain = TranscriptWriter.segments([w("a", 0, 0.3)], speaker: "Ik", channel: 0)
        #expect(TranscriptWriter.unsplitIfOneSpeaker(plain, label: "Ik") == plain)
        // Speakers on both channels: the right side counts on after the left, so names don't collide.
        let right = TranscriptWriter.speakerSegments([w("x", 5, 5.3), w("y", 7, 7.3)], turns: [turn(4, 6, 0), turn(6.5, 8, 1)], channel: 1)
        let shifted = TranscriptWriter.renumber(right, offset: 2)
        #expect(shifted.map(\.speakerNumber) == [2, 3] && shifted.map(\.speaker) == ["Spreker 3", "Spreker 4"])
        #expect(TranscriptWriter.renumber(plain, offset: 2) == plain)
    }

    private func turn(_ s: Double, _ e: Double, _ who: Int) -> TranscriptWriter.SpeakerTurn {
        TranscriptWriter.SpeakerTurn(start: s, end: e, speaker: who)
    }

    @Test func wordsGoToTheTurnWithMostOverlap() {
        let turns = [turn(0, 2.0, 0), turn(1.8, 4.0, 1), turn(6.0, 7.0, 0)]
        let words = [
            w("a", 0.2, 0.5),   // only speaker 0
            w("b", 1.7, 2.3),   // 0: 0.3 s, 1: 0.5 s -> 1
            w("c", 1.85, 2.0),  // both 0.15 s -> tie, lower number
            w("d", 4.5, 4.8),   // no overlap; nearest is speaker 1 (0.5 s) vs 0 (1.2 s)
            w("e", 5.7, 5.9),   // no overlap; nearest is speaker 0 (0.1 s)
            w("f", 6.5, 6.5),   // zero length: counted as 80 ms
        ]
        #expect(TranscriptWriter.assignSpeakers(words, turns: turns) == [0, 1, 0, 1, 0, 0])
        #expect(TranscriptWriter.assignSpeakers(words, turns: []) == [nil, nil, nil, nil, nil, nil])
    }

    @Test func speakerSegmentsSplitOnSpeakerChangeAndPause() {
        let turns = [turn(0, 3, 0), turn(3, 6, 1), turn(6, 12, 0)]
        let words = [w("hoi", 0.1, 0.5), w("daar", 0.6, 1.0), w("ja", 3.2, 3.5), w("hallo", 3.6, 4.0),
                     w("nou", 6.1, 6.4), w("goed", 9.0, 9.3)]
        let segs = TranscriptWriter.speakerSegments(words, turns: turns, channel: 1)
        #expect(segs.map(\.text) == ["hoi daar", "ja hallo", "nou", "goed"])
        #expect(segs.map(\.speaker) == ["Spreker 1", "Spreker 2", "Spreker 1", "Spreker 1"])
        #expect(segs.map(\.speakerNumber) == [0, 1, 0, 0])
        #expect(segs.allSatisfy { $0.channel == 1 })
        // Without any turns everything is one speaker.
        #expect(Set(TranscriptWriter.speakerSegments(words, turns: [], channel: nil).map(\.speaker)) == ["Spreker 1"])
        // Mode B: merged with the left channel by start time, labels Ik / Spreker n.
        let left = TranscriptWriter.segments([w("oké", 2.0, 2.4)], speaker: TranscriptWriter.me, channel: 0)
        #expect(TranscriptWriter.merge(left, segs).map(\.speaker) == ["Spreker 1", "Ik", "Spreker 2", "Spreker 1", "Spreker 1"])
        #expect(TranscriptWriter.joinConsecutive(TranscriptWriter.merge(left, segs)).map(\.speaker)
                == ["Spreker 1", "Ik", "Spreker 2", "Spreker 1"])
    }

    @Test func recordingNamesAndDownmix() {
        #expect(TranscriptWriter.isRecordingName("2026-11-04_14-30"))
        #expect(TranscriptWriter.isRecordingName("2026-11-04_14-30_2"))
        #expect(!TranscriptWriter.isRecordingName("Nieuwe opname 3"))
        #expect(!TranscriptWriter.isRecordingName("memo_2026"))
        #expect(Transcriber.downmix([[1, 0.5, 0], [0, 0.5, 1]]) == [0.5, 0.5, 0.5])
        #expect(Transcriber.downmix([[0.25, 0.5]]) == [0.25, 0.5])
    }

    @Test func jsonRoundTrip() throws {
        let segs = TranscriptWriter.speakerSegments([w("a", 0, 0.3), w("b", 2, 2.3)], turns: [turn(0, 1, 0), turn(1.5, 3, 1)], channel: nil)
        var t = Transcript(title: "Memo", duration: 3, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4", segments: segs)
        t.speakerNames = ["Spreker 2": "Jan"]
        t.audioFile = "Memo.m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bandje-roundtrip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try TranscriptWriter.json(t).write(to: url)
        let back = try TranscriptWriter.read(json: url)
        #expect(back.segments == t.segments)
        #expect(back.speakerNames == ["Spreker 2": "Jan"])
        #expect(back.audioFile == "Memo.m4a")
        #expect(back.speakerLabels == ["Spreker 1", "Spreker 2"])
        #expect(TranscriptWriter.markdown(back) == TranscriptWriter.markdown(t))
    }

    @Test func jsonHasSpeakerNumbers() throws {
        let segs = TranscriptWriter.speakerSegments([w("a", 0, 0.3), w("b", 2, 2.3)], turns: [turn(0, 1, 0), turn(1.5, 3, 1)], channel: nil)
        let t = Transcript(title: "Memo", duration: 3, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4", segments: segs)
        let json = try #require(try JSONSerialization.jsonObject(with: TranscriptWriter.json(t)) as? [String: Any])
        let s = try #require(json["segments"] as? [[String: Any]])
        #expect(s.compactMap { $0["speakerNumber"] as? Int } == [1, 2])
        #expect(s.allSatisfy { $0["channel"] is NSNull })
        // The model versions live in the json (the Markdown has the iPhone's header without them).
        #expect((json["models"] as? [String: Any])?["who"] as? String == "v0.3.4")
    }

    @Test func markdownLikeTheIPhone() {
        var t = Transcript(title: "Opname 6 nov 14.32", duration: 75, mode: "sprekers", vozVersion: "v0.5.0", whoVersion: "v0.3.4",
                           segments: TranscriptWriter.speakerSegments([w("hoi", 1, 1.3), w("dag", 62, 62.4)],
                                                                      turns: [turn(0, 30, 0), turn(60, 70, 1)], channel: nil))
        t.recorded = ISO8601DateFormatter().date(from: "2026-11-06T13:32:00Z")
        t.extra["location"] = ["latitude": 52.09071, "longitude": 5.12142, "accuracy": 10.0]
        t.speakerNames["Spreker 2"] = "Anna"
        let md = TranscriptWriter.markdown(t, locale: Locale(identifier: "nl_NL"))
        let lines = md.components(separatedBy: "\n")
        #expect(lines[0] == "# Opname 6 nov 14.32")
        #expect(lines[2].hasPrefix("📼 ") && lines[2].contains(" · 1:15 · ") && lines[2].hasSuffix("Spreker 1, Anna  "))
        #expect(lines[3] == "📍 52.0907, 5.1214  ")
        #expect(lines[4] == "Opgenomen met Band·je · band.je")
        #expect(md.contains("\n---\n\n**0:01 · Spreker 1**  \nhoi\n\n**1:02 · Anna**  \ndag\n"))
        #expect(!md.contains("Voz") && !md.contains("![Bandje]"))
    }

    @Test func markdownFormat() throws {
        let segs = TranscriptWriter.merge(
            TranscriptWriter.segments([w("Hoi,", 3.2, 3.5), w("goedemiddag.", 3.6, 4.2)], speaker: "Ik", channel: 0),
            TranscriptWriter.segments([w("Ja", 6.1, 6.3), w("hallo.", 6.4, 6.8)], speaker: "Andere kant", channel: 1))
        let t = Transcript(title: TranscriptWriter.title(forBaseName: "2026-11-04_14-30"), duration: 1935, mode: "kanaalscheiding",
                           vozVersion: "v0.5.0", whoVersion: nil, segments: segs)
        // An old Mac title (date and time) still gets the readable heading.
        let md = TranscriptWriter.markdown(t, locale: Locale(identifier: "nl_NL"))
        #expect(md.hasPrefix("# Opname woensdag 4 november 2026 om 14:30\n"))
        #expect(md.contains("**0:03 · Ik**  \nHoi, goedemiddag.\n\n**0:06 · Andere kant**  \nJa hallo.\n"))
        var named = t
        named.speakerNames = ["Andere kant": "Jan", "Ik": " "]
        #expect(TranscriptWriter.markdown(named, locale: Locale(identifier: "nl_NL")).contains("**0:06 · Jan**  \nJa hallo."))
        #expect(TranscriptWriter.title(forBaseName: "2026-11-04_14-30_2") == "2026-11-04 14:30")
        #expect(TranscriptWriter.title(forBaseName: "Memo 12") == "Memo 12")
        #expect(TranscriptWriter.timestamp(3725.9) == "01:02:05")
        let json = try #require(try JSONSerialization.jsonObject(with: TranscriptWriter.json(t)) as? [String: Any])
        let channels = (json["segments"] as? [[String: Any]])?.compactMap { $0["channel"] as? String }
        #expect(channels == ["L", "R"])
    }

    @Test func layoutCutsTurnsIntoSentencesAndFindsTheActiveOne() {
        let segs = TranscriptWriter.merge(
            TranscriptWriter.segments([w("Hoi.", 0, 0.4), w("Hoe", 0.5, 0.7), w("gaat", 0.8, 1.0), w("het?", 1.1, 1.4)], speaker: "Ik", channel: 0),
            TranscriptWriter.segments([w("Goed", 3, 3.3), w("dank", 3.4, 3.6), w("je", 5, 5.2)], speaker: "Andere kant", channel: 1))
        let t = Transcript(title: "x", duration: 6, mode: "kanaalscheiding", vozVersion: "v", whoVersion: nil, segments: segs)
        let turns = TranscriptLayout.turns(t)
        #expect(turns.map(\.speaker) == ["Ik", "Andere kant"])
        #expect(turns[0].sentences.map(\.text) == ["Hoi.", "Hoe gaat het?"])
        #expect(turns[1].sentences.map(\.text) == ["Goed dank", "je"])   // a pause longer than 0.8 s ends a sentence
        #expect(TranscriptLayout.active(at: 0.6, in: turns)! == (0, 1))
        #expect(TranscriptLayout.active(at: 5.1, in: turns)! == (1, 1))
        #expect(TranscriptLayout.active(at: -1, in: turns) == nil)
    }

    @Test func summaryBlocksFromMarkdown() {
        #expect(SummaryBlock.parse("## Besluiten\n- Eén\n\nTekst") == [.heading("Besluiten"), .bullet("Eén"), .paragraph("Tekst")])
    }
}

/// With Sprekers herkennen off a transcript has no speaker labels: the Markdown shows only the time.
@Test func markdownWithoutSpeakers() {
    let t = Transcript(title: "Memo", duration: 3, mode: "tekst", vozVersion: "v", whoVersion: nil,
                       segments: TranscriptWriter.segments([TimedWord(text: "Hallo daar", start: 1, end: 2)], speaker: "", channel: nil))
    let md = TranscriptWriter.markdown(t, locale: Locale(identifier: "nl_NL"))
    #expect(md.contains("**0:01**"))
    #expect(!md.contains(" · **"))
}

/// The menu's "Benoem sprekers… (1 zonder naam)": only the speakers that have no name yet.
@Test func unnamedSpeakersCount() {
    func seg(_ who: String) -> Segment { Segment(speaker: who, channel: nil, words: [TimedWord(text: "x", start: 0, end: 1)]) }
    var t = Transcript(title: "x", duration: 1, mode: "sprekers", vozVersion: "v", whoVersion: nil,
                       segments: [seg("Spreker 1"), seg("Spreker 2"), seg("Spreker 1")])
    #expect(t.unnamedSpeakers == 2)
    t.speakerNames = ["Spreker 1": "Anna"]
    #expect(t.unnamedSpeakers == 1)
    t.speakerNames["Spreker 2"] = "Ben"
    #expect(t.unnamedSpeakers == 0)
}

/// The menu's current recording, without saying "Opname" twice: a default name becomes its date,
/// an own name stays; "Laatste opname" for the newest.
@Test func menuHeaderOfTheCurrentRecording() {
    var c = Calendar(identifier: .gregorian); c.timeZone = .current
    let date = c.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 21, minute: 35))!
    let nl = Locale(identifier: "nl_NL")
    let auto = OutputLocation.defaultTitle(for: date, locale: nl)
    let latest = BandjeApp.menuHeader(title: auto, date: date, latest: true, locale: nl)
    #expect(latest.contains("6 nov"))
    #expect(latest.contains("21:35"))
    #expect(!latest.contains(auto))
    #expect(BandjeApp.menuHeader(title: auto + " 2", date: date, latest: false, locale: nl).contains("21:35"))
    #expect(BandjeApp.menuHeader(title: "Planning, donderdag", date: date, latest: false, locale: nl).hasSuffix("Planning, donderdag"))
    #expect(BandjeApp.menuHeader(title: "Planning", date: date, latest: true, locale: nl) != BandjeApp.menuHeader(title: "Planning", date: date, latest: false, locale: nl))
}
