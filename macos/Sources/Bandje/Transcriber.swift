import AVFoundation
import Foundation
import Voz
import Who

struct TranscriberError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs Voz on a recording. Models are loaded only from the local model folder
/// (`Voz(modelDirectory:)` has no download path); the app never fetches anything.
actor Transcriber {
    static let shared = Transcriber()

    enum Status: Sendable {
        /// A model is being loaded; `firstTime` when it was never loaded on this Mac before
        /// (Core ML then specializes it for the chip, which takes the longest).
        /// `expected`: about how many seconds the load takes (for an estimated %; the SDK has no
        /// progress for loading).
        case loading(firstTime: Bool, expected: Double)
        case transcribing(Double)
    }

    /// An estimated % for a load that reports no progress: elapsed against expected, at most 95
    /// until the load is really done.
    nonisolated static func loadPercent(elapsed: Double, expected: Double) -> Int {
        guard expected > 0 else { return 95 }
        return min(95, max(0, Int((elapsed / expected * 100).rounded())))
    }

    /// How long the last Voz load took on this Mac; 20 s the first time (Core ML specializes the
    /// model for the chip then), else 4 s until measured.
    private static func expectedVozLoad(firstTime: Bool) -> Double {
        let last = UserDefaults.standard.double(forKey: "vozLoadSeconds")
        return firstTime ? 20 : (last > 0 ? last : 4)
    }

    static var missingModels: String { tr("models.missing", "De spraakmodellen ontbreken. Draai eerst scripts/fetch-models.sh; die zet ze in ~/Music/Bandje/.models.") }

    /// The models that ship inside the app (`Contents/Resources/Models`, the App Store build), else
    /// `~/Music/Bandje/.models` (filled by scripts/fetch-models.sh, for your own builds).
    /// Independent of `outputDir`. Bandje never downloads models.
    nonisolated(unsafe) static var modelsDirectory: URL = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("voz/meta.json").path) {
            return bundled
        }
        return OutputLocation.defaultDirectory.appendingPathComponent(".models", isDirectory: true)
    }()
    static var vozDirectory: URL { modelsDirectory.appendingPathComponent("voz", isDirectory: true) }
    static let vozFiles = ["encoder.mlmodelc", "mel.mlmodelc", "decoder.mlmodelc", "meta.json", "vocab.json", "embedding.f16"]

    static var vozVersion: String { VozModel.revision }
    static var sdkVersion: String { VozModel.sdkVersion }

    private var voz: Voz?
    /// Seconds the last model load took (0 when it was already loaded). For the selftest.
    private(set) var lastLoadSeconds: Double = 0

    static func modelsPresent() -> Bool {
        vozFiles.allSatisfy { FileManager.default.fileExists(atPath: vozDirectory.appendingPathComponent($0).path) }
    }

    private func loadVoz(status: @Sendable (Status) -> Void) throws -> Voz {
        if let voz { lastLoadSeconds = 0; return voz }
        guard Self.modelsPresent() else { throw TranscriberError(message: Self.missingModels) }
        let firstTime = !UserDefaults.standard.bool(forKey: "vozLoadedOnce")
        status(.loading(firstTime: firstTime, expected: Self.expectedVozLoad(firstTime: firstTime)))
        let t0 = Date()
        do {
            let loaded = try Voz(modelDirectory: Self.vozDirectory)
            lastLoadSeconds = Date().timeIntervalSince(t0)
            UserDefaults.standard.set(true, forKey: "vozLoadedOnce")
            UserDefaults.standard.set(lastLoadSeconds, forKey: "vozLoadSeconds")
            voz = loaded
            return loaded
        } catch {
            throw TranscriberError(message: tr("models.loadFailed", "Het spraakmodel kon niet geladen worden (%@). Draai scripts/fetch-models.sh opnieuw.", "\(error)"))
        }
    }

    /// Loads Voz ahead of use (shortly after launch, and when dictation starts), so dictation and
    /// transcription start without waiting. Costs about 30-60 MB: Core ML maps the weights from disk.
    func preload() {
        _ = try? loadVoz { _ in }
    }

    /// Dictation: Voz only, nothing on disk. `samples` are mono at `rate`.
    func dictate(_ samples: [Float], rate: Double) async throws -> String {
        let voz = try loadVoz { _ in }
        let audio = DictationCapture.resample(samples, from: rate, to: voz.sampleRate)
        guard !DictationCapture.isSilent(audio) else { return "" }
        return try await voz.transcribe(samples: audio).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transcribes `audio` and writes `<name>.md` and `<name>.json` into `directory` (default: next
    /// to `audio`); returns the `.md` URL.
    /// - A stereo file that is one of our own recordings (`ownRecording`): mode A, left = me,
    ///   right = the other side, plus mode B (5.2) when Who hears more than one speaker on the right.
    /// - Anything else (a voice memo, any mono or foreign file): mode C (5.3), downmix to mono, Who + Voz.
    func transcribe(_ audio: URL, in directory: URL? = nil, ownRecording: Bool = true,
                    status: @escaping @Sendable (Status) -> Void) async throws -> (url: URL, transcript: Transcript) {
        let voz = try loadVoz(status: status)
        status(.transcribing(0))
        let (channels, duration) = try Self.readChannels(audio, rate: voz.sampleRate)
        let transcript: Transcript
        if channels.count == 2, ownRecording {
            transcript = try await channelSeparation(voz, channels, status: status)
        } else if Self.detectSpeakers {
            transcript = try await monoWithSpeakers(voz, Self.downmix(channels), status: status)
        } else {
            // Speakers off: the words only, one block without a speaker label.
            let words = try await Self.words(voz, Self.downmix(channels)) { p in status(.transcribing(p)) }
            transcript = Transcript(title: "", duration: 0, mode: "tekst", vozVersion: Self.vozVersion, whoVersion: nil,
                                    segments: TranscriptWriter.segments(words, speaker: "", channel: nil))
        }
        var t = transcript
        t.title = TranscriptWriter.title(forBaseName: audio.deletingPathExtension().lastPathComponent)
        t.audioFile = audio.lastPathComponent
        t.duration = duration
        if let meta = RecordingMeta.read(from: audio.deletingLastPathComponent()) { TranscriptWriter.apply(meta, to: &t) }
        let md = try TranscriptWriter.write(t, for: audio, in: directory)
        status(.transcribing(1))
        return (md, t)
    }

    /// Modes A and B. Who runs on both channels if its model is there; without it this is plain mode A.
    /// Left: several people around one Mac (a meeting at a table) become `Spreker n` instead of "Ik".
    /// Right: several people at the other side of a call. A channel with one voice keeps its plain label.
    private func channelSeparation(_ voz: Voz, _ channels: [[Float]], status: @escaping @Sendable (Status) -> Void) async throws -> Transcript {
        var words: [[TimedWord]] = []
        for i in 0..<2 {
            words.append(try await Self.words(voz, channels[i]) { p in status(.transcribing((Double(i) + p) / 2)) })
        }
        var left = TranscriptWriter.segments(words[0], speaker: TranscriptWriter.me, channel: 0)
        var right = TranscriptWriter.segments(words[1], speaker: TranscriptWriter.otherSide, channel: 1)
        var whoVersion: String?
        // Who on one channel: its segments by speaker, but only when at least two speakers actually
        // get words (Who can give a short stretch of one voice a number of its own, which would turn
        // a normal call into "Spreker 1" only), and the number of speakers Who kept.
        func split(_ i: Int) async throws -> (segments: [Segment]?, count: Int, raw: String) {
            guard !words[i].isEmpty, Self.detectSpeakers, Self.whoPresent() else { return (nil, 0, "") }
            let turns = try await diarize(channels[i], rate: voz.sampleRate, status: status)
            whoVersion = Self.whoVersion
            let bySpeaker = TranscriptWriter.speakerSegments(words[i], turns: turns, channel: i)
            let several = Set(bySpeaker.compactMap(\.speakerNumber)).count > 1
            return (several ? bySpeaker : nil, Set(turns.map(\.speaker)).count, lastRawWho)
        }
        let l = try await split(0), r = try await split(1)
        if let segments = l.segments { left = segments }
        if let segments = r.segments { right = segments }
        lastRawWho = [l.raw.isEmpty ? nil : "L: " + l.raw, r.raw.isEmpty ? nil : "R: " + r.raw]
            .compactMap { $0 }.joined(separator: "; ")
        let filtered = TranscriptWriter.filterCrosstalk(left: left, right: right,
                                                        leftSamples: channels[0], rightSamples: channels[1],
                                                        sampleRate: voz.sampleRate, settings: .current)
        // Without headphones the other side leaks into the microphone and Who may call that leak a
        // second voice. Once the crosstalk filter removed the leak, one voice left is "Ik" again.
        let kept = TranscriptWriter.unsplitIfOneSpeaker(filtered.kept, label: TranscriptWriter.me)
        let leftSplit = kept.contains { $0.speakerNumber != nil }
        let rightSplit = right.contains { $0.speakerNumber != nil }
        // Speaker numbers must not collide between the channels: the right side counts on after the left.
        if leftSplit, rightSplit {
            right = TranscriptWriter.renumber(right, offset: (kept.compactMap(\.speakerNumber).max() ?? -1) + 1)
        }
        lastSpeakerCount = (leftSplit ? l.count : 0) + r.count
        let anySplit = leftSplit || rightSplit
        return Transcript(title: "", duration: 0, mode: anySplit ? "kanaalscheiding + sprekers" : "kanaalscheiding",
                          vozVersion: Self.vozVersion, whoVersion: whoVersion,
                          segments: TranscriptWriter.merge(kept, right), crosstalkRemoved: filtered.removed)
    }

    /// Mode C: who spoke when from Who, the words from Voz, each word to the turn it overlaps most.
    private func monoWithSpeakers(_ voz: Voz, _ samples: [Float], status: @escaping @Sendable (Status) -> Void) async throws -> Transcript {
        guard Self.whoPresent() else { throw TranscriberError(message: Self.missingWho) }
        let words = try await Self.words(voz, samples) { p in status(.transcribing(p * 0.95)) }
        var turns: [TranscriptWriter.SpeakerTurn] = []
        if !words.isEmpty {
            turns = try await diarize(samples, rate: voz.sampleRate, status: status)
        }
        lastSpeakerCount = Set(turns.map(\.speaker)).count
        return Transcript(title: "", duration: 0, mode: "sprekers", vozVersion: Self.vozVersion, whoVersion: Self.whoVersion,
                          segments: TranscriptWriter.speakerSegments(words, turns: turns, channel: nil))
    }

    // MARK: Who

    static var missingWho: String { tr("models.missingWho", "Het sprekermodel (Who) ontbreekt. Draai eerst scripts/fetch-models.sh; die zet het in ~/Music/Bandje/.models.") }
    static var whoDirectory: URL { modelsDirectory.appendingPathComponent("who", isDirectory: true) }
    static var whoVersion: String { WhoModel.revision }
    /// Speakers below this share of the recording (a laugh, a jingle) are dropped.
    static let minimumSpeakerShare = 0.05

    private var who: Who?
    private var whoLoaded = false
    /// Speakers Who kept in the last transcription. For the selftest.
    private(set) var lastSpeakerCount = 0
    /// Who's result before the minimum-share filter, for the selftest.
    private(set) var lastRawWho = ""

    /// Checked before every Who use: `Who(directory:)` downloads into the folder when the model is
    /// not there, so it must only ever be built for a folder that already holds it.
    /// Instellingen › Transcriptie › Sprekers herkennen (on by default, the iPhone's key): off,
    /// own recordings keep Ik / the other side, other files get the text without speakers.
    static var detectSpeakers: Bool {
        get { UserDefaults.standard.object(forKey: "detectSpeakers") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "detectSpeakers") }
    }

    static func whoPresent() -> Bool {
        Who.isDownloaded(directory: whoDirectory.path)
    }

    private func diarize(_ samples: [Float], rate: Double, status: @Sendable (Status) -> Void) async throws -> [TranscriptWriter.SpeakerTurn] {
        guard Self.whoPresent() else { throw TranscriberError(message: Self.missingWho) }
        let who = self.who ?? Who(directory: Self.whoDirectory.path)
        self.who = who
        if !whoLoaded {
            let firstTime = !UserDefaults.standard.bool(forKey: "whoLoadedOnce")
            status(.loading(firstTime: firstTime, expected: firstTime ? 15 : 5))
        }
        let result: Diarization
        do {
            let raw = try await who.diarize(samples: samples, sampleRate: rate)
            lastRawWho = "\(raw.speakerCount) speakers, \(raw.turns.count) turns, \(String(format: "%.1f", raw.duration)) s"
            result = raw.keepingSpeakers(minimumShare: Self.minimumSpeakerShare)
        } catch {
            throw TranscriberError(message: tr("error.who", "Sprekerherkenning (Who) mislukt (%@). Draai scripts/fetch-models.sh opnieuw als het model beschadigd is.", "\(error)"))
        }
        whoLoaded = true
        UserDefaults.standard.set(true, forKey: "whoLoadedOnce")
        return result.turns.map { TranscriptWriter.SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
    }

    /// Average of all channels.
    static func downmix(_ channels: [[Float]]) -> [Float] {
        guard channels.count > 1 else { return channels.first ?? [] }
        let n = channels.map(\.count).min() ?? 0
        let scale = 1 / Float(channels.count)
        return (0..<n).map { i in channels.reduce(0) { $0 + $1[i] } * scale }
    }

    /// Words of one channel. A channel that is (nearly) digital silence is skipped: nothing to hear,
    /// and an empty channel is the normal case for a mic-less recording.
    private static func words(_ voz: Voz, _ samples: [Float], progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        guard (samples.lazy.map { abs($0) }.max() ?? 0) > 1e-4 else { progress(1); return [] }
        let result = try await voz.transcribe(samples: samples) { progress($0.fractionCompleted) }
        return result.words.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
    }

    /// Reads an audio file into one float array per channel at `rate`.
    static func readChannels(_ url: URL, rate: Double) throws -> (channels: [[Float]], duration: Double) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TranscriberError(message: tr("audio.unreadable", "Kan %@ niet lezen als audio.", url.lastPathComponent))
        }
        let inFormat = file.processingFormat
        let count = Int(inFormat.channelCount)
        guard count > 0, file.length > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                            channels: inFormat.channelCount, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 32768),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(32768 * rate / inFormat.sampleRate) + 4096)
        else { throw TranscriberError(message: tr("audio.empty", "%@ bevat geen bruikbare audio.", url.lastPathComponent)) }

        let expected = Int(Double(file.length) * rate / inFormat.sampleRate) + 4096
        var channels = (0..<count).map { _ -> [Float] in var a = [Float](); a.reserveCapacity(expected); return a }
        var finished = false
        while true {
            var readError: Error?
            let status = converter.convert(to: outBuf, error: nil) { _, inputStatus in
                // Reading at the end throws instead of returning 0 frames, so stop on the position.
                let remaining = file.length - file.framePosition
                if finished || remaining <= 0 { finished = true; inputStatus.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: inBuf, frameCount: AVAudioFrameCount(min(Int64(inBuf.frameCapacity), remaining)))
                } catch {
                    readError = error
                }
                if inBuf.frameLength == 0 || readError != nil {
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuf
            }
            if let readError { throw TranscriberError(message: tr("audio.readFailed", "Lezen van %1$@ mislukt: %2$@", url.lastPathComponent, readError.localizedDescription)) }
            if status == .error { throw TranscriberError(message: tr("audio.resampleFailed", "Omzetten van %@ naar 16 kHz mislukt.", url.lastPathComponent)) }
            if let data = outBuf.floatChannelData, outBuf.frameLength > 0 {
                for c in 0..<count {
                    channels[c].append(contentsOf: UnsafeBufferPointer(start: data[c], count: Int(outBuf.frameLength)))
                }
            }
            if status == .endOfStream { break }
        }
        return (channels, Double(file.length) / inFormat.sampleRate)
    }
}
