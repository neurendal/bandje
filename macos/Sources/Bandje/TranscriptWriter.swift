import BandjeKit
import Foundation

/// A recognised word with its time in seconds from the start of the recording.
struct TimedWord: Codable, Equatable {
    var text: String
    var start: Double
    var end: Double
}

/// Consecutive words of one speaker.
struct Segment: Equatable {
    var speaker: String
    /// 0 = left (microphone), 1 = right (system audio), nil for a mono file.
    var channel: Int?
    var words: [TimedWord]
    /// Who's speaker number (0-based) in modes B and C, nil otherwise.
    var speakerNumber: Int? = nil
    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.map(\.end).max() ?? start }
    var text: String { words.map(\.text).joined(separator: " ") }
}

/// Everything that goes into `<name>.md` and `<name>.json`.
struct Transcript {
    var title: String
    var duration: Double
    var mode: String
    var vozVersion: String
    var whoVersion: String?
    var segments: [Segment]
    var crosstalkRemoved: Int = 0
    /// Names the user gave in "Sprekers benoemen…", keyed by the original label ("Spreker 1", "Ik").
    var speakerNames: [String: String] = [:]
    /// File name of the audio (same folder as the transcript for own recordings), for playback.
    var audioFile: String? = nil
    /// When the recording was made (json `recorded`, ISO 8601); the iPhone writes it, so does the Mac.
    var recorded: Date? = nil
    /// Every other top-level json key (the iPhone's `markers`, `location`, keys of later versions):
    /// kept as read and written back unchanged.
    var extra: [String: Any] = [:]
    /// The `models` object as read (an iPhone transcript has its own `sdk` and maybe more keys):
    /// kept, with only `voz` and `who` taken from this transcript.
    var models: [String: Any] = [:]

    func name(of label: String) -> String {
        let name = speakerNames[label]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? label : name
    }

    /// Speakers without a name yet (the menu's "Benoem sprekers… (1 zonder naam)").
    var unnamedSpeakers: Int {
        speakerLabels.filter { !$0.isEmpty && (speakerNames[$0]?.isEmpty ?? true) }.count
    }

    /// Original labels in order of first appearance.
    var speakerLabels: [String] {
        var seen: [String] = []
        for seg in segments where !seen.contains(seg.speaker) { seen.append(seg.speaker) }
        return seen
    }
}

enum TranscriptWriter {
    static var me: String { tr("transcript.me", "Ik") }
    static var otherSide: String { tr("transcript.otherSide", "Andere kant") }
    /// A pause longer than this starts a new segment.
    static let pause = 0.8

    // MARK: Segments

    /// Groups words into segments, splitting at a pause longer than `pause`.
    static func segments(_ words: [TimedWord], speaker: String, channel: Int?, pause: Double = pause) -> [Segment] {
        var out: [Segment] = []
        for word in words {
            if var last = out.last, word.start - last.end <= pause {
                last.words.append(word)
                out[out.count - 1] = last
            } else {
                out.append(Segment(speaker: speaker, channel: channel, words: [word]))
            }
        }
        return out
    }

    /// Both channels, sorted by start time (left first on a tie).
    static func merge(_ a: [Segment], _ b: [Segment]) -> [Segment] {
        (a + b).enumerated().sorted { x, y in
            x.element.start != y.element.start ? x.element.start < y.element.start : x.offset < y.offset
        }.map(\.element)
    }

    /// Joins consecutive segments of the same speaker with nobody in between.
    static func joinConsecutive(_ segments: [Segment]) -> [Segment] {
        var out: [Segment] = []
        for seg in segments {
            if var last = out.last, last.speaker == seg.speaker {
                last.words += seg.words
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    // MARK: Speakers (Who, modes B and C)

    /// One Who turn. A copy of the SDK's `Turn`, so this file stays free of the SDK and testable.
    struct SpeakerTurn: Equatable {
        var start: Double
        var end: Double
        var speaker: Int
    }

    /// Human-readable transcription mode for the `.md`; the `.json` keeps the stable Dutch value.
    static func modeLabel(_ mode: String) -> String {
        switch mode {
        case "kanaalscheiding": tr("mode.channels", "kanaalscheiding")
        case "kanaalscheiding + sprekers": tr("mode.channelsSpeakers", "kanaalscheiding + sprekers")
        case "sprekers": tr("mode.speakers", "sprekers")
        default: mode
        }
    }

    static func speakerLabel(_ n: Int) -> String { tr("transcript.speaker", "Spreker %@", "\(n + 1)") }

    /// The Who speaker for each word: the one whose turns overlap the word most. A word that
    /// overlaps no turn (Who's turns and Voz's word times do not line up exactly) gets the
    /// speaker of the nearest turn; nil only when there are no turns at all.
    static func assignSpeakers(_ words: [TimedWord], turns: [SpeakerTurn]) -> [Int?] {
        words.map { word in
            let end = word.start + max(word.end - word.start, 0.08)
            var overlap: [Int: Double] = [:]
            for t in turns {
                let o = min(end, t.end) - max(word.start, t.start)
                if o > 0 { overlap[t.speaker, default: 0] += o }
            }
            // Highest overlap; on a tie the lower speaker number, so the result is deterministic.
            if let best = overlap.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
                return best.key
            }
            let nearest = turns.min { a, b in
                let da = max(a.start - end, word.start - a.end), db = max(b.start - end, word.start - b.end)
                return da != db ? da < db : a.speaker < b.speaker
            }
            return nearest?.speaker
        }
    }

    /// Segments labelled `Spreker n`: a new segment at a change of speaker or a pause longer than `pause`.
    static func speakerSegments(_ words: [TimedWord], turns: [SpeakerTurn], channel: Int?, pause: Double = pause) -> [Segment] {
        var out: [Segment] = []
        for (word, who) in zip(words, assignSpeakers(words, turns: turns)) {
            let n = who ?? 0
            if var last = out.last, last.speakerNumber == n, word.start - last.end <= pause {
                last.words.append(word)
                out[out.count - 1] = last
            } else {
                out.append(Segment(speaker: speakerLabel(n), channel: channel, words: [word], speakerNumber: n))
            }
        }
        return out
    }

    /// Left-channel segments split by Who that, after the crosstalk filter, hold one speaker only:
    /// back to plain `label` segments. Several speakers, or none split: unchanged.
    static func unsplitIfOneSpeaker(_ segments: [Segment], label: String) -> [Segment] {
        guard Set(segments.compactMap(\.speakerNumber)).count == 1 else { return segments }
        let words = segments.flatMap(\.words).sorted { $0.start < $1.start }
        return Self.segments(words, speaker: label, channel: segments.first?.channel)
    }

    /// Speaker numbers (and their `Spreker n` labels) shifted by `offset`; plain segments unchanged.
    static func renumber(_ segments: [Segment], offset: Int) -> [Segment] {
        segments.map { seg in
            guard let n = seg.speakerNumber else { return seg }
            return Segment(speaker: speakerLabel(n + offset), channel: seg.channel, words: seg.words, speakerNumber: n + offset)
        }
    }

    // MARK: Crosstalk

    struct CrosstalkSettings {
        /// Share of the left segment's duration that must overlap right-channel segments.
        var overlap: Double
        /// How much quieter (dB) the left channel must be than the right in that span.
        var db: Double

        /// From `defaults write com.neurendal.bandje crosstalkOverlap 0.6` / `crosstalkDb 6`.
        static var current: CrosstalkSettings {
            let d = UserDefaults.standard
            return CrosstalkSettings(overlap: d.object(forKey: "crosstalkOverlap") == nil ? 0.6 : d.double(forKey: "crosstalkOverlap"),
                                     db: d.object(forKey: "crosstalkDb") == nil ? 6 : d.double(forKey: "crosstalkDb"))
        }
    }

    /// Drops left (microphone) speech that is the other side leaking in through the speakers:
    /// mostly overlapping in time with right-channel speech, and clearly quieter on the left.
    ///
    /// Judged per word, not per pause-separated segment: the leak often follows the user's own
    /// sentence within 0.8 s, so one segment can hold both, and a segment-level test then keeps
    /// the leak (measured in the M5 selftest). The kept words are regrouped into segments.
    /// Returns the kept segments and how many leaked runs of words were removed.
    static func filterCrosstalk(left: [Segment], right: [Segment], leftSamples: [Float], rightSamples: [Float],
                                sampleRate: Double, settings: CrosstalkSettings) -> (kept: [Segment], removed: Int) {
        // Kept words with the segment they came from, so split speakers keep their labels.
        var keptWords: [(word: TimedWord, from: Segment)] = []
        var removedRuns = 0
        var inRun = false
        for (word, from) in left.flatMap({ seg in seg.words.map { ($0, seg) } }) {
            let end = word.start + max(word.end - word.start, 0.08) // a word can be a single 80 ms frame
            var overlapped = 0.0
            for r in right {
                overlapped += max(0, min(end, r.end) - max(word.start, r.start))
            }
            let share = overlapped / (end - word.start)
            let l = levelDb(leftSamples, from: word.start, to: end, rate: sampleRate)
            let r = levelDb(rightSamples, from: word.start, to: end, rate: sampleRate)
            if share >= settings.overlap, l <= r - settings.db {
                if !inRun { removedRuns += 1 }
                inRun = true
            } else {
                keptWords.append((word, from))
                inRun = false
            }
        }
        var kept: [Segment] = []
        for (word, from) in keptWords {
            if var last = kept.last, last.speaker == from.speaker, word.start - last.end <= pause {
                last.words.append(word)
                kept[kept.count - 1] = last
            } else {
                kept.append(Segment(speaker: from.speaker, channel: from.channel, words: [word], speakerNumber: from.speakerNumber))
            }
        }
        return (kept, removedRuns)
    }

    /// RMS in dBFS of `samples` between two times (-200 for silence or an empty span).
    static func levelDb(_ samples: [Float], from: Double, to: Double, rate: Double) -> Double {
        let a = max(0, min(samples.count, Int(from * rate)))
        let b = max(a, min(samples.count, Int(to * rate)))
        guard b > a else { return -200 }
        var sum = 0.0
        for i in a..<b { sum += Double(samples[i]) * Double(samples[i]) }
        let rms = (sum / Double(b - a)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -200
    }

    // MARK: Output

    /// `2026-11-04_14-30` (optionally `_2`) becomes `2026-11-04 14:30`; anything else stays as is.
    static func title(forBaseName name: String) -> String {
        guard isRecordingName(name) else { return name }
        let parts = name.split(separator: "_")
        return "\(parts[0]) \(parts[1].replacingOccurrences(of: "-", with: ":"))"
    }

    /// Whether a base name is one of Bandje's own (old) recording names: a real date and time
    /// `yyyy-MM-dd_HH-mm`, optionally followed by `_2`, `_3`….
    static func isRecordingName(_ name: String) -> Bool {
        let parts = name.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts[0].count == 10, parts[1].count == 5 else { return false }
        if parts.count == 3 {
            guard parts[2].allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(parts[2]), n >= 2 else { return false }
        }
        return recordingNameFormat.date(from: "\(parts[0])_\(parts[1])") != nil
    }

    private static let recordingNameFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")  // every time exists (no daylight saving gap)
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        f.isLenient = false
        return f
    }()

    /// The app's language with this Mac's region, for the names of new recordings: the iPhone uses
    /// `Locale.current`, so English in the Netherlands is "Recording 6 Nov 14.32" on both.
    static func titleLocale(language: String = Bundle.main.preferredLocalizations.first ?? "nl",
                            region: String? = Locale.current.region?.identifier) -> Locale {
        Locale(identifier: region.map { "\(language)_\($0)" } ?? language)
    }

    /// Language of the app's texts, so the date matches the rest of the transcript.
    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "nl")
    }

    /// `2026-11-04 14:30` becomes "woensdag 4 november 2026 om 14:30" (in `locale`); other titles stay.
    static func displayTitle(_ title: String, locale: Locale) -> String {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = parse.date(from: title) else { return title }
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyyHHmm")
        return f.string(from: date)
    }

    /// `mm:ss`, or `h:mm:ss` from one hour on (the whole transcript uses one form).
    static func clock(_ t: Double, long: Bool) -> String {
        let s = max(0, Int(t))
        return long ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                    : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// `m:ss`, or `h:mm:ss` from an hour on: the times in the Markdown (as on the iPhone).
    static func shortClock(_ t: Double) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The header lines, as the iPhone writes them: when, how long, language and speakers; where;
    /// made with Bandje.
    static func headerLines(_ t: Transcript, locale: Locale) -> [String] {
        var facts: [String] = []
        if let recorded = t.recorded {
            facts.append(recorded.formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
                .hour().minute().locale(locale)))
        }
        facts.append(shortClock(t.duration))
        let text = t.segments.map(\.text).joined(separator: " ")
        // A few words are too little to tell the language reliably.
        if text.split(separator: " ").count >= 12, let code = Summaries.language(of: text),
           let name = locale.localizedString(forLanguageCode: code) {
            facts.append(name.capitalized(with: locale))
        }
        let names = t.speakerLabels.map { t.name(of: $0) }
        if !names.isEmpty { facts.append(names.joined(separator: ", ")) }
        var lines = ["📼 " + facts.joined(separator: " · ")]
        if let l = t.extra["location"] as? [String: Any], let lat = l["latitude"] as? Double, let lon = l["longitude"] as? Double {
            lines.append("📍 " + String(format: "%.4f, %.4f", lat, lon))
        }
        lines.append(tr("transcript.madeWith", "Opgenomen met Band·je · band.je"))
        return lines
    }

    /// The iPhone's layout: title, the header lines, a rule, then per turn "**0:01 · Spreker 1**"
    /// with the text on the next line (a Markdown hard break: two spaces before the newline).
    /// An old Mac title (`2026-11-04 14:30`) becomes "Opname woensdag 4 november 2026 om 14:30".
    static func markdown(_ t: Transcript, locale: Locale = appLocale) -> String {
        markdownHead(t, locale: locale) + markdownTurns(t, locale: locale)
    }

    /// The title block of `markdown`: the heading, the header lines and the rule.
    static func markdownHead(_ t: Transcript, locale: Locale = appLocale) -> String {
        "# \(heading(t, locale: locale))\n\n" + headerLines(t, locale: locale).joined(separator: "  \n") + "\n\n---\n\n"
    }

    /// The title of the transcript's documents: an old Mac title becomes "Opname <date>".
    static func heading(_ t: Transcript, locale: Locale = appLocale) -> String {
        let display = displayTitle(t.title, locale: locale)
        return display == t.title ? t.title : tr("transcript.title", "Opname %@", display)
    }

    /// The turns of `markdown`, after its title block.
    static func markdownTurns(_ t: Transcript, locale: Locale = appLocale) -> String {
        var out = ""
        let joined = joinConsecutive(t.segments)
        let marks = markers(of: t)
        let placed = marks.placed(in: joined.map(\.start))
        if joined.isEmpty {
            out += "_" + tr("transcript.noSpeech", "Geen spraak herkend.") + "_\n"
            // No turns to put them under: the markers after the line.
            for time in marks.times { out += "\n" + marks.line(at: time, clock: shortClock) + "\n" }
        }
        for (i, seg) in joined.enumerated() {
            // Without speakers (Sprekers herkennen off): only the time.
            let label = seg.speaker.isEmpty ? shortClock(seg.start) : "\(shortClock(seg.start)) · \(t.name(of: seg.speaker))"
            out += "**\(label)**  \n\(seg.text)\n\n"
            // A marker: "🚩 12:34 note" as its own paragraph under the turn it falls in, as in the app.
            for time in placed[i] ?? [] { out += marks.line(at: time, clock: shortClock) + "\n\n" }
        }
        return out
    }

    /// The transcript as plain text for the clipboard, as the iPhone's: the title and header lines,
    /// then per turn "0:01 · Spreker 1" with the text on the next line and its markers under it.
    static func plainText(_ t: Transcript, locale: Locale = appLocale) -> String {
        ([plainTextHead(t, locale: locale)] + plainTextTurns(t, locale: locale)).joined(separator: "\n\n") + "\n"
    }

    /// The title block of `plainText`: the title and the header lines.
    static func plainTextHead(_ t: Transcript, locale: Locale = appLocale) -> String {
        heading(t, locale: locale) + "\n" + headerLines(t, locale: locale).joined(separator: "\n")
    }

    /// The turns of `plainText`, one paragraph each (an empty line between them).
    static func plainTextTurns(_ t: Transcript, locale: Locale = appLocale) -> [String] {
        let joined = joinConsecutive(t.segments)
        let marks = markers(of: t)
        let placed = marks.placed(in: joined.map(\.start))
        var parts: [String] = []
        if joined.isEmpty {
            parts.append(tr("transcript.noSpeech", "Geen spraak herkend.")
                         + marks.times.map { "\n" + marks.line(at: $0, clock: shortClock) }.joined())
        }
        for (i, seg) in joined.enumerated() {
            let time = shortClock(seg.start)
            parts.append((seg.speaker.isEmpty ? time : "\(time) · \(t.name(of: seg.speaker))") + "\n" + seg.text
                         + (placed[i] ?? []).map { "\n" + marks.line(at: $0, clock: shortClock) }.joined())
        }
        return parts
    }

    // MARK: Markers (specs/markers.md)

    /// The markers kept in the transcript: `markers` (times, as the iPhone writes them) and
    /// `markerNotes` (by `Markers.key`).
    static func markers(of t: Transcript) -> Markers {
        let times = (t.extra["markers"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        return Markers(times: times, notes: t.extra["markerNotes"] as? [String: String] ?? [:])
    }

    /// Puts `markers` into the transcript (a copy: the folder's `.bandje.json` and `.markers.json`
    /// stay the source); no markers or notes, no key.
    static func apply(_ markers: Markers, to t: inout Transcript) {
        t.extra["markers"] = markers.isEmpty ? nil : markers.times
        t.extra["markerNotes"] = markers.notes.isEmpty ? nil : markers.notes
    }

    /// The transcript at `json` with the markers its folder has now (for exports: always current,
    /// also when another device changed them since the transcript was written). A folder without
    /// `.bandje.json` (a file transcribed elsewhere) has no markers of its own: the transcript's stay.
    static func withFolderMarkers(_ t: Transcript, json: URL) -> Transcript {
        let folder = json.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(Markers.metaFileName).path) else { return t }
        var out = t
        apply(Markers.read(from: folder), to: &out)
        return out
    }

    static func json(_ t: Transcript) throws -> Data {
        let segments: [[String: Any]] = t.segments.map { seg in
            var s: [String: Any] = [
                "speaker": seg.speaker, "start": seg.start, "end": seg.end, "text": seg.text,
                "words": seg.words.map { ["text": $0.text, "start": $0.start, "end": $0.end] },
            ]
            s["channel"] = seg.channel.map { $0 == 0 ? "L" : "R" } ?? NSNull()
            s["speakerNumber"] = seg.speakerNumber.map { $0 + 1 as Any } ?? NSNull()
            return s
        }
        var object = t.extra
        object.merge([
            "title": t.title, "duration": t.duration, "mode": t.mode,
            "models": t.models.merging(["voz": t.vozVersion, "who": t.whoVersion.map { $0 as Any } ?? NSNull()]) { _, own in own }
                .merging(["sdk": "desert-ant-core \(Transcriber.sdkVersion)"]) { kept, _ in kept },
            "crosstalkRemoved": t.crosstalkRemoved,
            "segments": segments,
            "speakerNames": t.speakerNames,
            "audio": t.audioFile.map { $0 as Any } ?? NSNull(),
            "recorded": t.recorded.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
        ]) { _, known in known }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// The recording's date, and the iPhone's markers and location, from its `.bandje.json`, as the
    /// iPhone puts them in its transcripts.
    static func apply(_ meta: RecordingMeta, to t: inout Transcript) {
        t.recorded = meta.created
        if !meta.markers.isEmpty { t.extra["markers"] = meta.markers }
        if let l = meta.location {
            t.extra["location"] = ["latitude": l.latitude, "longitude": l.longitude, "accuracy": l.accuracy]
        }
    }

    /// The keys `read` models; everything else goes into `Transcript.extra`.
    private static let knownKeys: Set<String> = ["title", "duration", "mode", "models", "crosstalkRemoved",
                                                 "segments", "speakerNames", "audio", "recorded"]

    /// Reads a `.json` written by `json(_:)` back (for "Sprekers benoemen…").
    static func read(json url: URL) throws -> Transcript {
        let data = try Files.read(url)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSegments = o["segments"] as? [[String: Any]] else {
            throw TranscriberError(message: tr("transcript.unreadable", "%@ is geen transcript van Band·je.", url.lastPathComponent))
        }
        let segments = rawSegments.map { s -> Segment in
            let words = (s["words"] as? [[String: Any]] ?? []).map {
                TimedWord(text: $0["text"] as? String ?? "", start: $0["start"] as? Double ?? 0, end: $0["end"] as? Double ?? 0)
            }
            let channel = (s["channel"] as? String).map { $0 == "L" ? 0 : 1 }
            let number = (s["speakerNumber"] as? Int).map { $0 - 1 }
            return Segment(speaker: s["speaker"] as? String ?? "?", channel: channel, words: words, speakerNumber: number)
        }
        let models = o["models"] as? [String: Any] ?? [:]
        return Transcript(title: o["title"] as? String ?? "", duration: o["duration"] as? Double ?? 0,
                          mode: o["mode"] as? String ?? "", vozVersion: models["voz"] as? String ?? "",
                          whoVersion: models["who"] as? String, segments: segments,
                          crosstalkRemoved: o["crosstalkRemoved"] as? Int ?? 0,
                          speakerNames: o["speakerNames"] as? [String: String] ?? [:],
                          audioFile: o["audio"] as? String,
                          recorded: (o["recorded"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                          extra: o.filter { !knownKeys.contains($0.key) },
                          models: models)
    }

    /// Rewrites `<base>.md` and `<base>.json` next to an existing `.json` (after naming speakers).
    static func rewrite(_ t: Transcript, json url: URL) throws {
        let base = url.deletingPathExtension()
        try Files.write(Data(markdown(t).utf8), to: base.appendingPathExtension("md"))
        try Files.write(json(t), to: url)
    }

    /// Writes `<base>.md` and `<base>.json` (base = the audio file's name) into `directory`,
    /// by default next to `audio`; returns the `.md` URL.
    @discardableResult
    static func write(_ t: Transcript, for audio: URL, in directory: URL? = nil) throws -> URL {
        let name = audio.deletingPathExtension().lastPathComponent
        let base = (directory ?? audio.deletingLastPathComponent()).appendingPathComponent(name)
        let md = base.appendingPathExtension("md")
        try Files.write(Data(markdown(t).utf8), to: md)
        try Files.write(json(t), to: base.appendingPathExtension("json"))
        return md
    }
}
