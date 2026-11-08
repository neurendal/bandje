// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BackgroundTasks
import Foundation
import Observation
import Voz
import Who

struct TranscriptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Transcript (ported from the Mac app's TranscriptWriter; mono only, no crosstalk)

/// A recognised word with its time in seconds from the start of the recording.
struct TimedWord: Codable, Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// Consecutive words of one speaker. `speaker` is empty when speakers were not recognised.
struct Segment: Equatable, Sendable {
    var speaker: String
    var words: [TimedWord]
    /// Who's speaker number (0-based), nil without speakers.
    var speakerNumber: Int? = nil
    var start: Double { words.first?.start ?? 0 }
    var end: Double { words.map(\.end).max() ?? start }
    var text: String { words.map(\.text).joined(separator: " ") }
}

/// Everything in `<name>.json` (same keys as the Mac app, plus `markers`).
struct Transcript: Equatable, Sendable {
    var title: String
    var duration: Double
    /// "sprekers" (Who + Voz, as the Mac's mode C) or "zonder sprekers" (Voz only). Stable Dutch value.
    var mode: String
    var vozVersion: String
    var whoVersion: String?
    var segments: [Segment]
    /// Names the user gave, keyed by the original label ("Spreker 1").
    var speakerNames: [String: String] = [:]
    var audioFile: String? = nil
    var markers: [Double] = []
    /// When the recording was made, and where (if "Store GPS location" was on).
    var recorded: Date? = nil
    var location: RecordedLocation? = nil

    func name(of label: String) -> String {
        let name = speakerNames[label]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? label : name
    }

    /// Original labels in order of first appearance (empty labels left out).
    var speakerLabels: [String] {
        var seen: [String] = []
        for seg in segments where !seg.speaker.isEmpty && !seen.contains(seg.speaker) { seen.append(seg.speaker) }
        return seen
    }
}

enum TranscriptWriter {
    /// A pause longer than this starts a new segment.
    static let pause = 0.8
    static let modeSpeakers = "sprekers"
    static let modeNoSpeakers = "zonder sprekers"

    static func speakerLabel(_ n: Int) -> String { String(localized: "Speaker \(n + 1)") }

    /// Groups words into segments, splitting at a pause longer than `pause`.
    static func segments(_ words: [TimedWord], speaker: String, pause: Double = pause) -> [Segment] {
        var out: [Segment] = []
        for word in words {
            if var last = out.last, word.start - last.end <= pause {
                last.words.append(word)
                out[out.count - 1] = last
            } else {
                out.append(Segment(speaker: speaker, words: [word]))
            }
        }
        return out
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

    /// One Who turn (a copy of the SDK's `Turn`, so this stays testable without the SDK).
    struct SpeakerTurn: Equatable, Sendable {
        var start: Double
        var end: Double
        var speaker: Int
    }

    /// The speaker for each word: the one whose turns overlap it most; else the nearest turn;
    /// nil only without turns. (Mac `assignSpeakers`.)
    static func assignSpeakers(_ words: [TimedWord], turns: [SpeakerTurn]) -> [Int?] {
        words.map { word in
            let end = word.start + max(word.end - word.start, 0.08)
            var overlap: [Int: Double] = [:]
            for t in turns {
                let o = min(end, t.end) - max(word.start, t.start)
                if o > 0 { overlap[t.speaker, default: 0] += o }
            }
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

    /// Segments labelled "Speaker n": new segment at a change of speaker or a pause.
    static func speakerSegments(_ words: [TimedWord], turns: [SpeakerTurn], pause: Double = pause) -> [Segment] {
        var out: [Segment] = []
        for (word, who) in zip(words, assignSpeakers(words, turns: turns)) {
            let n = who ?? 0
            if var last = out.last, last.speakerNumber == n, word.start - last.end <= pause {
                last.words.append(word)
                out[out.count - 1] = last
            } else {
                out.append(Segment(speaker: speakerLabel(n), words: [word], speakerNumber: n))
            }
        }
        return out
    }

    /// `mm:ss`, or `h:mm:ss` when the recording is an hour or longer.
    static func clock(_ t: Double, long: Bool) -> String {
        let s = max(0, Int(t))
        return long ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                    : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// `m:ss`, or `h:mm:ss` from an hour on: the times in the Markdown and text exports.
    static func shortClock(_ t: Double) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The header lines of the exports: when, how long, language and speakers; where; made with Bandje.
    static func headerLines(_ t: Transcript) -> [String] {
        var facts: [String] = []
        if let recorded = t.recorded {
            facts.append(recorded.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
        }
        facts.append(shortClock(t.duration))
        let text = t.segments.map(\.text).joined(separator: " ")
        // A few words are too little to tell the language reliably.
        if text.split(separator: " ").count >= 12, let code = Summaries.language(of: text), let name = Locale.current.localizedString(forLanguageCode: code) {
            facts.append(name.capitalized(with: .current))
        }
        let names = t.speakerLabels.map { t.name(of: $0) }
        if !names.isEmpty { facts.append(names.joined(separator: ", ")) }
        var lines = ["📼 " + facts.joined(separator: " · ")]
        if let l = t.location { lines.append("📍 " + String(format: "%.4f, %.4f", l.latitude, l.longitude)) }
        lines.append(String(localized: "Recorded with Bandje · band.je"))
        return lines
    }

    static func elapsed(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds.rounded())).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// Title, the header lines, a rule, then per turn "**0:01 · Speaker 1**" with the text on the
    /// next line (a Markdown hard break: two spaces before the newline).
    static func markdown(_ t: Transcript) -> String {
        var out = "# \(t.title)\n\n" + headerLines(t).joined(separator: "  \n") + "\n\n---\n\n"
        let joined = joinConsecutive(t.segments)
        if joined.isEmpty { out += "_" + String(localized: "No speech recognised.") + "_\n" }
        for seg in joined {
            let time = shortClock(seg.start)
            let head = seg.speaker.isEmpty ? time : "\(time) · \(t.name(of: seg.speaker))"
            out += "**\(head)**  \n\(seg.text)\n\n"
        }
        return out
    }

    /// Plain text for sharing: the title and header lines, then "0:01 · Speaker 1" and the text per turn.
    static func plainText(_ t: Transcript) -> String {
        let turns = joinConsecutive(t.segments).map { seg in
            let time = shortClock(seg.start)
            return (seg.speaker.isEmpty ? time : "\(time) · \(t.name(of: seg.speaker))") + "\n" + seg.text
        }
        return ([t.title + "\n" + headerLines(t).joined(separator: "\n")] + turns).joined(separator: "\n\n") + "\n"
    }

    static func json(_ t: Transcript) throws -> Data {
        let segments: [[String: Any]] = t.segments.map { seg in
            [
                "speaker": seg.speaker, "start": seg.start, "end": seg.end, "text": seg.text,
                "words": seg.words.map { ["text": $0.text, "start": $0.start, "end": $0.end] },
                "channel": NSNull(),
                "speakerNumber": seg.speakerNumber.map { $0 + 1 as Any } ?? NSNull(),
            ]
        }
        let object: [String: Any] = [
            "title": t.title, "duration": t.duration, "mode": t.mode,
            "models": ["voz": t.vozVersion, "who": t.whoVersion.map { $0 as Any } ?? NSNull(),
                       "sdk": "desert-ant-core \(Transcriber.sdkVersion)"] as [String: Any],
            "crosstalkRemoved": 0,
            "segments": segments,
            "speakerNames": t.speakerNames,
            "audio": t.audioFile.map { $0 as Any } ?? NSNull(),
            "markers": t.markers,
            "recorded": t.recorded.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
            "location": t.location.map { ["latitude": $0.latitude, "longitude": $0.longitude, "accuracy": $0.accuracy] as Any } ?? NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func read(json url: URL) throws -> Transcript {
        let data = try Data(contentsOf: url)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSegments = o["segments"] as? [[String: Any]] else {
            throw TranscriptionError(message: String(localized: "“\(url.lastPathComponent)” is not a Bandje transcript."))
        }
        let segments = rawSegments.map { s -> Segment in
            let words = (s["words"] as? [[String: Any]] ?? []).map {
                TimedWord(text: $0["text"] as? String ?? "", start: $0["start"] as? Double ?? 0, end: $0["end"] as? Double ?? 0)
            }
            return Segment(speaker: s["speaker"] as? String ?? "", words: words,
                           speakerNumber: (s["speakerNumber"] as? Int).map { $0 - 1 })
        }
        let models = o["models"] as? [String: Any] ?? [:]
        return Transcript(title: o["title"] as? String ?? "", duration: o["duration"] as? Double ?? 0,
                          mode: o["mode"] as? String ?? "", vozVersion: models["voz"] as? String ?? "",
                          whoVersion: models["who"] as? String, segments: segments,
                          speakerNames: o["speakerNames"] as? [String: String] ?? [:],
                          audioFile: o["audio"] as? String, markers: o["markers"] as? [Double] ?? [],
                          recorded: (o["recorded"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                          location: (o["location"] as? [String: Double]).flatMap { l in
                              guard let lat = l["latitude"], let lon = l["longitude"] else { return nil }
                              return RecordedLocation(latitude: lat, longitude: lon, accuracy: l["accuracy"] ?? 0)
                          })
    }

    /// Writes `<base>.json` and `<base>.md` (both atomically; json last, it is the source).
    static func write(_ t: Transcript, json url: URL) throws {
        let md = url.deletingPathExtension().appendingPathExtension("md")
        try Storage.coordinated(writing: md, options: .forReplacing) { try Data(markdown(t).utf8).write(to: $0, options: .atomic) }
        try Storage.coordinated(writing: url, options: .forReplacing) { try json(t).write(to: $0, options: .atomic) }
    }

    /// Text for library search: all words plus speaker names.
    /// The text to search (speaker names and all words) and the transcript's first words for the list.
    static func searchText(json url: URL) -> (search: String, preview: String)? {
        guard let t = try? read(json: url) else { return nil }
        let words = t.segments.map(\.text)
        return ((t.speakerNames.values + words).joined(separator: " "),
                String(words.joined(separator: " ").prefix(160)))
    }
}

// MARK: - Display: turns and sentences (tap to seek, follow playback)

struct TranscriptSentence: Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

struct TranscriptTurn: Identifiable, Equatable, Sendable {
    var id: Int
    /// Original label ("" without speakers).
    var speaker: String
    var start: Double
    var sentences: [TranscriptSentence]
    /// A later paragraph of the same speaker's turn (no name shown).
    var continued = false
}

enum TranscriptLayout {
    /// A paragraph ends at the first sentence end after this many seconds (long monologues,
    /// transcripts without speakers).
    static let paragraphSeconds = 60.0

    /// Turns (consecutive segments of one speaker) cut into sentences (after `.`, `?`, `!`, `…`,
    /// or at a pause longer than `TranscriptWriter.pause`), and into paragraphs of about
    /// `paragraphSeconds`.
    static func turns(_ t: Transcript) -> [TranscriptTurn] {
        var out: [TranscriptTurn] = []
        for turn in sentenceTurns(t) {
            var paragraph: [TranscriptSentence] = []
            for sentence in turn.sentences {
                paragraph.append(sentence)
                if sentence.end - paragraph[0].start >= paragraphSeconds {
                    out.append(TranscriptTurn(id: out.count, speaker: turn.speaker, start: paragraph[0].start,
                                              sentences: paragraph, continued: paragraph[0].start > turn.start))
                    paragraph = []
                }
            }
            if !paragraph.isEmpty {
                out.append(TranscriptTurn(id: out.count, speaker: turn.speaker, start: paragraph[0].start,
                                          sentences: paragraph, continued: paragraph[0].start > turn.start))
            }
        }
        return out
    }

    private static func sentenceTurns(_ t: Transcript) -> [TranscriptTurn] {
        TranscriptWriter.joinConsecutive(t.segments).enumerated().map { index, seg in
            var sentences: [TranscriptSentence] = []
            var current: [TimedWord] = []
            func flush() {
                guard let first = current.first else { return }
                sentences.append(TranscriptSentence(start: first.start, end: current.map(\.end).max() ?? first.end,
                                                    text: current.map(\.text).joined(separator: " ")))
                current = []
            }
            for (i, word) in seg.words.enumerated() {
                current.append(word)
                let next = i + 1 < seg.words.count ? seg.words[i + 1] : nil
                let ends = word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!") || word.text.hasSuffix("…")
                if ends || next.map({ $0.start - word.end > TranscriptWriter.pause }) == true { flush() }
            }
            flush()
            return TranscriptTurn(id: index, speaker: seg.speaker, start: seg.start, sentences: sentences)
        }
    }

    /// The sentence playing at `time`: the last one that started at or before it (turn, sentence).
    static func active(at time: Double, in turns: [TranscriptTurn]) -> (turn: Int, sentence: Int)? {
        var found: (Int, Int)?
        for turn in turns {
            guard turn.start <= time + 0.05 else { break }
            for (i, s) in turn.sentences.enumerated() where s.start <= time + 0.05 { found = (turn.id, i) }
        }
        return found
    }
}

// MARK: - Reading audio in pieces

/// Reads an audio file as mono Float32 at `rate`, a piece at a time, so a 2-hour recording is
/// never in memory at once (the Mac's `readChannels` reads it whole).
final class MonoReader {
    let rate: Double
    /// Length of the file in seconds.
    let duration: Double
    /// Expected number of output frames (for progress).
    let expectedFrames: Int
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let inBuf: AVAudioPCMBuffer
    private let outBuf: AVAudioPCMBuffer
    private var pending: [Float] = []
    private var finished = false
    private var inputDone = false

    init(url: URL, rate: Double) throws {
        let unreadable = TranscriptionError(message: String(localized: "Bandje can't read the audio of this recording."))
        guard let file = try? AVAudioFile(forReading: url) else { throw unreadable }
        let inFormat = file.processingFormat
        guard file.length > 0, inFormat.sampleRate > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 32768),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(32768 * rate / inFormat.sampleRate) + 4096)
        else { throw unreadable }
        converter.downmix = true
        self.file = file
        self.converter = converter
        self.inBuf = inBuf
        self.outBuf = outBuf
        self.rate = rate
        duration = Double(file.length) / inFormat.sampleRate
        expectedFrames = Int(Double(file.length) * rate / inFormat.sampleRate)
    }

    /// Up to `count` samples; fewer only at the end, empty when the file is done.
    func read(_ count: Int) throws -> [Float] {
        while pending.count < count, !finished {
            var readError: Error?
            let status = converter.convert(to: outBuf, error: nil) { [self] _, inputStatus in
                // Reading at the end throws instead of returning 0 frames: stop on the position.
                let remaining = file.length - file.framePosition
                if inputDone || remaining <= 0 { inputDone = true; inputStatus.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: inBuf, frameCount: AVAudioFrameCount(min(Int64(inBuf.frameCapacity), remaining)))
                } catch {
                    readError = error
                }
                if inBuf.frameLength == 0 || readError != nil {
                    inputDone = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuf
            }
            if readError != nil || status == .error {
                throw TranscriptionError(message: String(localized: "Bandje can't read the audio of this recording."))
            }
            if let data = outBuf.floatChannelData, outBuf.frameLength > 0 {
                pending.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(outBuf.frameLength)))
            }
            if status == .endOfStream { finished = true }
        }
        let n = min(count, pending.count)
        let out = Array(pending[..<n])
        pending.removeFirst(n)
        return out
    }

    /// The whole (rest of the) file, for Who.
    func readAll() throws -> [Float] {
        var all: [Float] = []
        all.reserveCapacity(expectedFrames + 4096)
        while true {
            let piece = try read(Int(rate) * 60)
            if piece.isEmpty { break }
            all.append(contentsOf: piece)
        }
        return all
    }
}

enum Chunking {
    /// Where to cut `samples` near `target`: the middle of the quietest `window` (by energy) in
    /// the `search` samples before `target`, so no word is split between two Voz calls.
    static func cutPoint(_ samples: [Float], target: Int, search: Int, window: Int) -> Int {
        let end = min(target, samples.count)
        let start = max(0, end - search)
        guard end - start > window else { return end }
        var best = end, bestEnergy = Float.infinity
        var i = start
        while i + window <= end {
            var e: Float = 0
            for j in i..<(i + window) { e += samples[j] * samples[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }

    static func isSilent(_ samples: [Float]) -> Bool {
        (samples.lazy.map { abs($0) }.max() ?? 0) <= 1e-4
    }
}

// MARK: - Transcriber (Voz + Who from the app bundle)

/// Runs Voz (and Who) on a recording. Models only from `Bandje.app/Models`, checked complete
/// first; Bandje never downloads anything.
actor Transcriber {
    static let shared = Transcriber()

    enum Phase: Sendable, Equatable {
        case waiting
        /// `firstTime`: the models have not run since this install, so iOS compiles them for the
        /// Neural Engine first (measured on an iPhone 16 Pro: about 10 s for Voz, 50 s for Who).
        case loading(firstTime: Bool)
        case transcribing(Double)
        /// `progress`: estimated from the recording's length (Who reports none).
        case speakers(firstTime: Bool, progress: Double)
    }

    /// Who's run time, measured on an iPhone 16 Pro (10 min of audio: 15 s, 68 s the first time
    /// after an install or update). With the phone locked it can take several times longer.
    static func estimatedWhoSeconds(duration: TimeInterval, firstTime: Bool) -> Double {
        max(2, 0.03 * duration) + (firstTime ? 55 : 0)
    }

    /// Progress during Who from the time spent so far: linear up to the estimate (95 %), then
    /// creeping towards 99 % so it never stands still and never claims to be done.
    static func whoFraction(elapsed: Double, estimate: Double) -> Double {
        guard estimate > 0, elapsed > 0 else { return 0 }
        if elapsed <= estimate { return 0.95 * elapsed / estimate }
        return 0.95 + 0.04 * (1 - exp(-(elapsed - estimate) / estimate))
    }

    /// Whether `model` ("voz", "who") has run since this install. Core ML's compiled cache is
    /// tied to the app's location, which changes with every install and update.
    static func isPrepared(_ model: String) -> Bool {
        UserDefaults.standard.string(forKey: "prepared.\(model)") == Bundle.main.bundleURL.path
    }

    static func markPrepared(_ model: String) {
        UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: "prepared.\(model)")
    }

    /// Voz runs on pieces of about this length, with a cancel check in between.
    static let chunkSeconds = 300.0
    /// Share of the progress bar for Voz when Who runs after it (on an iPhone 16 Pro Voz takes
    /// about half as long as Who: 7 s and 15 s for 10 minutes).
    static let vozShare = 0.35
    static let minimumSpeakerShare = 0.05

    static var modelsDirectory: URL { Bundle.main.bundleURL.appending(path: "Models", directoryHint: .isDirectory) }
    static var vozDirectory: URL { modelsDirectory.appending(path: "voz", directoryHint: .isDirectory) }
    static var whoDirectory: URL { modelsDirectory.appending(path: "who", directoryHint: .isDirectory) }
    static let vozFiles = ["encoder.mlmodelc", "mel.mlmodelc", "decoder.mlmodelc", "meta.json", "vocab.json", "embedding.f16"]
    static var vozVersion: String { VozModel.revision }
    static var whoVersion: String { WhoModel.revision }
    static var sdkVersion: String { VozModel.sdkVersion }

    static var missingModels: String {
        String(localized: "The speech models in Bandje are incomplete. Reinstall Bandje from the App Store.")
    }

    static func vozPresent() -> Bool {
        vozFiles.allSatisfy { FileManager.default.fileExists(atPath: vozDirectory.appending(path: $0).path) }
    }

    /// Checked before every Who use: `Who(directory:)` downloads into a folder that lacks the model.
    static func whoPresent() -> Bool { Who.isDownloaded(directory: whoDirectory.path) }

    private var voz: Voz?
    private var who: Who?
    /// For the selftest: the raw Who result.
    private(set) var lastRawWho = ""
    /// For the selftest: seconds per step of the last run (loadVoz, voz, readAll, who).
    private(set) var lastTimings: [String: Double] = [:]

    private func loadVoz() throws -> Voz {
        if let voz { return voz }
        guard Self.vozPresent() else { throw TranscriptionError(message: Self.missingModels) }
        do {
            let loaded = try Voz(modelDirectory: Self.vozDirectory)
            voz = loaded
            return loaded
        } catch {
            throw TranscriptionError(message: String(localized: "The speech model could not be loaded (\(String(describing: error)))."))
        }
    }

    /// Transcribes `audio` into a transcript (not written). Cancellation is checked between
    /// pieces and before and after Who; a cancelled run throws `CancellationError`.
    func transcribe(_ audio: URL, title: String, speakers: Bool, markers: [Double],
                    progress: @escaping @Sendable (Phase) -> Void) async throws -> Transcript {
        if speakers, !Self.whoPresent() { throw TranscriptionError(message: Self.missingModels) }
        progress(.loading(firstTime: !Self.isPrepared("voz")))
        let clock = ContinuousClock()
        var mark = clock.now
        func lap(_ step: String) {
            let now = clock.now
            lastTimings[step] = (now - mark) / .seconds(1)
            mark = now
        }
        lastTimings = [:]
        let voz = try loadVoz()
        Self.markPrepared("voz")
        lap("loadVoz")
        try Task.checkCancellation()
        let rate = voz.sampleRate
        let share = speakers ? Self.vozShare : 1.0
        progress(.transcribing(0))

        // Voz, piece by piece.
        let reader = try MonoReader(url: audio, rate: rate)
        let total = Double(max(reader.expectedFrames, 1))
        let chunk = Int(Self.chunkSeconds * rate)
        let search = Int(3 * rate), window = Int(0.1 * rate)
        var words: [TimedWord] = []
        var buffer: [Float] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let more = try reader.read(chunk + search - buffer.count)
            buffer += more
            if buffer.isEmpty { break }
            let atEnd = more.isEmpty || buffer.count < chunk
            let cut = atEnd ? buffer.count : Chunking.cutPoint(buffer, target: chunk, search: search, window: window)
            let piece = Array(buffer[..<cut])
            buffer.removeFirst(cut)
            let start = Double(offset) / rate
            let done = Double(offset)
            if !Chunking.isSilent(piece) {
                let result = try await voz.transcribe(samples: piece) { p in
                    progress(.transcribing(share * min(1, (done + p.fractionCompleted * Double(piece.count)) / total)))
                }
                words += result.words.map { TimedWord(text: $0.text, start: $0.start + start, end: $0.end + start) }
            }
            offset += cut
            progress(.transcribing(share * min(1, Double(offset) / total)))
            if atEnd && buffer.isEmpty { break }
        }
        try Task.checkCancellation()
        lap("voz")

        var transcript = Transcript(title: title, duration: reader.duration,
                                    mode: speakers ? TranscriptWriter.modeSpeakers : TranscriptWriter.modeNoSpeakers,
                                    vozVersion: Self.vozVersion, whoVersion: speakers ? Self.whoVersion : nil,
                                    segments: [], audioFile: audio.lastPathComponent, markers: markers)
        if speakers, !words.isEmpty {
            let firstTime = !Self.isPrepared("who")
            progress(.speakers(firstTime: firstTime, progress: share))
            // Who needs the whole signal; the Voz pieces are gone by now.
            let samples = try MonoReader(url: audio, rate: rate).readAll()
            lap("readAll")
            // Who reports no progress: move the bar on an estimate, every second, so the screen
            // and iOS's background-task progress both keep moving.
            let estimate = Self.estimatedWhoSeconds(duration: reader.duration, firstTime: firstTime)
            let ticker = Task.detached {
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    let elapsed = (ContinuousClock.now - start) / .seconds(1)
                    progress(.speakers(firstTime: firstTime, progress: share + (1 - share) * Self.whoFraction(elapsed: elapsed, estimate: estimate)))
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer { ticker.cancel() }
            let turns = try await diarize(samples, rate: rate)
            Self.markPrepared("who")
            lap("who")
            try Task.checkCancellation()
            transcript.segments = TranscriptWriter.speakerSegments(words, turns: turns)
        } else {
            transcript.segments = TranscriptWriter.segments(words, speaker: "")
        }
        progress(.transcribing(1))
        return transcript
    }

    /// After an install or update iOS compiles the models for the Neural Engine on first use
    /// (about a minute, ~1.9 GB at its peak on an iPhone 16 Pro). Doing that once in the
    /// background makes the first transcription start right away. Skipped when already done.
    func prepareModels() async {
        if !Self.isPrepared("voz"), (try? loadVoz()) != nil { Self.markPrepared("voz") }
        guard !Self.isPrepared("who"), Self.whoPresent(), let rate = voz?.sampleRate else { return }
        // Three seconds of faint noise: enough to load every graph; the result does not matter.
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<Int(3 * rate)).map { _ in Float.random(in: -0.001...0.001, using: &generator) }
        _ = try? await diarize(noise, rate: rate)
        Self.markPrepared("who")
    }

    private func diarize(_ samples: [Float], rate: Double) async throws -> [TranscriptWriter.SpeakerTurn] {
        guard Self.whoPresent() else { throw TranscriptionError(message: Self.missingModels) }
        let who = self.who ?? Who(directory: Self.whoDirectory.path)
        self.who = who
        do {
            let raw = try await who.diarize(samples: samples, sampleRate: rate)
            lastRawWho = "\(raw.speakerCount) speakers, \(raw.turns.count) turns"
            return raw.keepingSpeakers(minimumShare: Self.minimumSpeakerShare).turns
                .map { TranscriptWriter.SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
        } catch {
            throw TranscriptionError(message: String(localized: "Speaker recognition failed (\(String(describing: error)))."))
        }
    }
}

// MARK: - Jobs (one at a time, progress per recording, BGContinuedProcessingTask)

@MainActor @Observable
final class Transcriptions {
    static let shared = Transcriptions()
    nonisolated static let taskPrefix = "com.neurendal.bandje.transcribe"

    /// Running or queued jobs by recording folder.
    private(set) var phases: [URL: Transcriber.Phase] = [:]
    /// The last failure per folder (shown in the detail screen until the next attempt).
    var errors: [URL: String] = [:]
    /// Outcome of the last background-task submission (selftest).
    private(set) var lastSubmitError: String?
    private(set) var lastBackgroundTaskStarted = false

    private var tasks: [URL: Task<Void, Never>] = [:]
    private var last: Task<Void, Never>?
    private var bgIdentifiers: [String: URL] = [:]
    private var bgTasks: [URL: BGContinuedProcessingTask] = [:]
    /// Jobs iOS stopped in the background (not cancelled by the user).
    private var expired: Set<URL> = []

    func phase(of folder: URL) -> Transcriber.Phase? { phases[folder.standardizedFileURL] }
    func isRunning(_ folder: URL) -> Bool { phase(of: folder) != nil }

    /// Fraction 0…1 for display (0 while waiting or loading).
    static func fraction(_ phase: Transcriber.Phase) -> Double {
        switch phase {
        case .waiting, .loading: 0
        case .transcribing(let p): p
        case .speakers(_, let p): p
        }
    }

    /// Registers the launch handler for one submitted identifier (`<prefix>.<uuid>`; the plist
    /// permits the wildcard). Continued-processing handlers may be registered after launch, one
    /// per identifier; each identifier is registered once.
    nonisolated static func register(_ identifier: String) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            // The handler runs on the main queue (`using: .main`); the task is only used there.
            nonisolated(unsafe) let task = task
            MainActor.assumeIsolated {
                guard let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Transcriptions.shared.attach(continued)
            }
        }
    }

    /// Starts (or queues) a transcription of `recording`.
    func start(_ recording: Recording, speakers: Bool) {
        let folder = recording.folder.standardizedFileURL
        guard tasks[folder] == nil, let audio = recording.audio else { return }
        errors[folder] = nil
        phases[folder] = .waiting
        let previous = last
        let title = recording.title
        let markers = recording.markers
        let recorded = recording.date
        let task = Task { [weak self] in
            await previous?.value
            await self?.run(folder: folder, audio: audio, title: title, speakers: speakers, markers: markers, recorded: recorded)
        }
        tasks[folder] = task
        last = task
        submitBackgroundTask(for: folder, title: title)
    }

    func cancel(_ folder: URL) {
        tasks[folder.standardizedFileURL]?.cancel()
    }

    #if DEBUG
    /// Screenshots: shows a job in progress without running one.
    func demoPhase(_ folder: URL, _ phase: Transcriber.Phase) { phases[folder.standardizedFileURL] = phase }
    #endif

    /// Waits until the job for `folder` is done (selftests).
    func wait(_ folder: URL) async {
        await tasks[folder.standardizedFileURL]?.value
    }

    /// "Transcribe automatically after recording/import" (About screen, default off).
    func startIfAutomatic(_ recordings: [Recording]) {
        guard UserDefaults.standard.bool(forKey: "autoTranscribe") else { return }
        let speakers = UserDefaults.standard.object(forKey: "detectSpeakers") as? Bool ?? true
        for recording in recordings where recording.transcript == nil { start(recording, speakers: speakers) }
    }

    private func run(folder: URL, audio: URL, title: String, speakers: Bool, markers: [Double], recorded: Date) async {
        var success = false
        defer {
            phases[folder] = nil
            tasks[folder] = nil
            expired.remove(folder)
            finishBackgroundTask(for: folder, success: success)
        }
        guard !Task.isCancelled else { return }
        do {
            var transcript = try await Transcriber.shared.transcribe(audio, title: title, speakers: speakers, markers: markers) { phase in
                Task { @MainActor in Transcriptions.shared.update(folder, phase) }
            }
            try Task.checkCancellation()
            transcript.recorded = recorded
            // Read now: the location may have arrived after the recording stopped.
            transcript.location = RecordingMeta.read(from: folder)?.location
            let json = folder.appending(path: "\(folder.lastPathComponent).json")
            try await Task.detached { try TranscriptWriter.write(transcript, json: json) }.value
            success = true
            ReviewPrompt.transcriptionDone()
        } catch is CancellationError {
            // Nothing was written: the files are only written at the very end.
            if expired.remove(folder) != nil {
                errors[folder] = String(localized: "iOS stopped the transcription in the background. Keep Bandje open and try again.")
            }
        } catch {
            errors[folder] = error.localizedDescription
        }
        await Library.shared.refresh(except: Recorder.shared.folder)
    }

    private func update(_ folder: URL, _ phase: Transcriber.Phase) {
        guard phases[folder] != nil, tasks[folder]?.isCancelled != true else { return }
        phases[folder] = phase
        if let task = bgTasks[folder] {
            task.progress.completedUnitCount = Int64(Self.fraction(phase) * 100)
        }
    }

    // MARK: Background continuation

    private func submitBackgroundTask(for folder: URL, title: String) {
        let identifier = "\(Self.taskPrefix).\(UUID().uuidString)"
        // Submitting without a registered handler raises an Objective-C exception.
        guard Self.register(identifier) else {
            lastSubmitError = "registration failed"
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: String(localized: "Transcribing"), subtitle: title)
        request.strategy = .fail
        bgIdentifiers[identifier] = folder
        do {
            try BGTaskScheduler.shared.submit(request)
            lastSubmitError = nil
        } catch {
            // Simulator, or the system said no: the job still runs while Bandje is open.
            bgIdentifiers[identifier] = nil
            lastSubmitError = String(describing: error)
        }
    }

    fileprivate func attach(_ task: BGContinuedProcessingTask) {
        lastBackgroundTaskStarted = true
        guard let folder = bgIdentifiers.removeValue(forKey: task.identifier), tasks[folder] != nil else {
            task.setTaskCompleted(success: true)
            return
        }
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = Int64(Self.fraction(phases[folder] ?? .waiting) * 100)
        task.expirationHandler = {
            Task { @MainActor in
                Transcriptions.shared.expired.insert(folder)
                Transcriptions.shared.cancel(folder)
            }
        }
        bgTasks[folder] = task
    }

    private func finishBackgroundTask(for folder: URL, success: Bool) {
        bgIdentifiers = bgIdentifiers.filter { $0.value != folder }
        guard let task = bgTasks.removeValue(forKey: folder) else { return }
        task.progress.completedUnitCount = 100
        task.setTaskCompleted(success: success)
    }
}
