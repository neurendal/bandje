// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import ActivityKit
import AVFoundation
import Foundation
import FoundationModels
import SwiftUI
import Voz
import Who

/// DEBUG-only launch arguments for automated tests in the simulator (see OVERNIGHT.md 3).
/// Every mode writes its outcome to Documents/selftest/last.json. Compiled out of Release.
struct SelftestOptions: Equatable, Sendable {
    var fakeMic: String?
    var record: Double?
    var importPath: String?
    var inbox: String?
    var transcribe: String?
    var noSpeakers = false
    var cancelAfter: Double?
    var summarize: String?
    var fmUnavailable = false
    var killAfter: Double?
    var simulateInterruption: Double?
    var demoState: String?
    var reset = false
    var checkModels = false
    var list = false
    var intents: String?
    var rateTest: String?
    var sample: String?
    var speakerNames: [String] = []
    /// `--sample-date 2026-11-05T10:30:00` (local time) for the sample recording.
    var sampleDate: String?
    /// `--english-demo`: the English demo library (as in the Mac app's window).
    var englishDemo = false
    /// `--dutch-demo`: the Dutch list next to the sample "Planning, donderdag" (as in the Mac window).
    var dutchDemo = false
    /// `--canned-summary <file>`: with `--sample`, this text (the body under the template's headings)
    /// is the summary instead of running the model (screenshots where the model isn't available).
    var cannedSummary: String?
    /// `--canned-sample <content.json>` (docs/appstore/content/<lang>.json): with `--sample`, the
    /// sample's transcript, speakers and summary and the list beside it come from this file, in its
    /// language (App Store screenshots in languages without a recorded sample).
    var cannedSample: String?
    /// `--render-art <dir>`: the cassette (with a title sticker and without) and the Band●je wordmark
    /// as large transparent PNGs, for App Store artwork (scripts/dev/make-store-art.py).
    var renderArt: String?
    /// `--search <text>`: the library opens with this search (screenshots).
    var search: String?
    /// `--seek <seconds>` for `--demo-state open-newest`; it then stays paused there.
    var seek: Double?
    /// `--open-sheet speakers|share`: with `--demo-state open-newest`, opens that sheet too.
    var openSheet: String?

    var isEmpty: Bool { self == SelftestOptions() }

    /// Parses `--flag value` pairs; unknown arguments (e.g. Xcode's own) are ignored.
    init(arguments: [String] = []) {
        var i = 0
        func value() -> String? {
            guard i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") else { return nil }
            i += 1
            return arguments[i]
        }
        while i < arguments.count {
            switch arguments[i] {
            case "--fake-mic": fakeMic = value()
            case "--record": record = value().flatMap(Double.init)
            case "--import": importPath = value()
            case "--inbox": inbox = value()
            case "--transcribe": transcribe = value()
            case "--no-speakers": noSpeakers = true
            case "--cancel-after": cancelAfter = value().flatMap(Double.init)
            case "--summarize": summarize = value()
            case "--fm-unavailable": fmUnavailable = true
            case "--kill-after": killAfter = value().flatMap(Double.init)
            case "--simulate-interruption": simulateInterruption = value().flatMap(Double.init)
            case "--demo-state": demoState = value()
            case "--reset": reset = true
            case "--check-models": checkModels = true
            case "--list": list = true
            case "--intents": intents = value() ?? "run"
            case "--rate-test": rateTest = value()
            case "--sample": sample = value()
            case "--sample-date": sampleDate = value()
            case "--english-demo": englishDemo = true
            case "--dutch-demo": dutchDemo = true
            case "--canned-summary": cannedSummary = value()
            case "--canned-sample": cannedSample = value()
            case "--render-art": renderArt = value()
            case "--search": search = value()
            case "--seek": seek = value().flatMap(Double.init)
            case "--open-sheet": openSheet = value()
            case "--speaker-names": speakerNames = (value() ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            default: break
            }
            i += 1
        }
    }
}

enum Selftest {
    static let options = SelftestOptions(arguments: ProcessInfo.processInfo.arguments)

    static var resultURL: URL {
        URL.documentsDirectory.appending(path: "selftest/last.json")
    }

    static func startIfRequested() {
        let options = options
        guard !options.isEmpty else { return }
        if options.reset {
            resetDocuments()
            UserDefaults.standard.removeObject(forKey: "consentShown")  // the one-time notice shows again
        }
        if options.checkModels { write(checkModels()) }
    }

    /// Modes that need the running app (after the library's launch scan and recovery).
    /// `--import` returns the imported recording so the UI opens it, as "Open in" does.
    @MainActor
    static func run(recorder: Recorder, library: Library) async -> Recording? {
        let options = options
        if let dir = options.renderArt {
            renderArt(to: dir)
            return nil
        }
        if let path = options.fakeMic, let seconds = options.record {
            await record(path: path, seconds: seconds, options: options, recorder: recorder, library: library)
        } else if let path = options.importPath {
            return await importFile(path: path, library: library)
        } else if let path = options.inbox {
            await inbox(path: path, library: library)
        } else if let target = options.summarize {
            return await summarize(target, options: options, library: library)
        } else if let target = options.transcribe {
            return await transcribe(target, options: options, library: library)
        } else if let path = options.sample {
            await sample(path, names: options.speakerNames, library: library)
        } else if let target = options.rateTest {
            await rateTest(target, library: library)
        } else if options.list {
            write(["mode": "list", "ok": true, "recordings": library.recordings.map(describe),
                   "syncSetting": UserDefaults.standard.bool(forKey: CloudSync.settingKey),
                   "syncOn": CloudSync.shared.isOn, "iCloudAvailable": CloudSync.shared.isAvailable,
                   "cloud": Storage.cloud?.path ?? NSNull(), "local": Storage.documents.path,
                   "cloudContents": Storage.cloud.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []])
        } else if let mode = options.intents {
            await intents(mode, recorder: recorder, library: library)
        }
        return nil
    }

    /// `--sample <path> [--speaker-names "Anna,Ben,Chris"]` (after `--reset`): the website's sample
    /// recording as the newest in a demo library: imported, transcribed with speakers, the speakers
    /// named in order of appearance, summarised. The screenshots are then taken with
    /// `--demo-state open-newest` / `library` without `--reset`.
    @MainActor
    static func sample(_ path: String, names: [String], library: Library) async {
        let options = options
        var result: [String: Any] = ["mode": "sample", "path": path]
        defer { write(result) }
        do {
            let english = options.englishDemo, dutch = options.dutchDemo
            let today = Self.parseSampleDate(options.sampleDate).map { $0.addingTimeInterval(86_400) }
            let canned = try options.cannedSample.map { try CannedSample(file: containerPath($0)) }
            let list = canned?.list
            try await Task.detached { try makeDemoLibrary(english: english, dutch: dutch, today: today, list: list) }.value
            await library.refresh()
            guard var recording = await library.importFiles([containerPath(path)]).first else {
                result["error"] = "import failed: \(library.importErrors)"
                return
            }
            // Its date: given (to match the Mac window), else now (on top of the list).
            let date = parseSampleDate(options.sampleDate) ?? .now
            var meta = RecordingMeta.read(from: recording.folder) ?? RecordingMeta(created: date)
            meta.created = date
            try meta.write(to: recording.folder)
            await library.refresh()
            recording = library.recordings.first { $0.folder == recording.folder } ?? recording
            if let canned {
                let folder = recording.folder, duration = recording.duration
                try await Task.detached {
                    try writeDemoTranscript(in: folder, duration: duration, summary: false,
                                            lines: canned.lines, names: canned.speakers)
                }.value
                let template = Summaries.template()
                let md = Summaries.document(title: recording.title, template: template.name, body: canned.summary,
                                            date: date.addingTimeInterval(600))
                try md.write(to: Summaries.outputURL(in: recording.folder, template: template.name), atomically: true, encoding: .utf8)
                await library.refresh()
                result["title"] = recording.title
                result["ok"] = true
                return
            }
            Transcriptions.shared.start(recording, speakers: true)
            await Transcriptions.shared.wait(recording.folder)
            await library.refresh()
            recording = library.recordings.first { $0.folder == recording.folder } ?? recording
            guard let json = recording.transcript else {
                result["error"] = "no transcript: \(Transcriptions.shared.errors[recording.folder.standardizedFileURL] ?? "?")"
                return
            }
            var t = try TranscriptWriter.read(json: json)
            for (label, name) in zip(t.speakerLabels, names) { t.speakerNames[label] = name }
            try TranscriptWriter.write(t, json: json)
            result["speakers"] = t.speakerLabels.map { t.name(of: $0) }
            if let canned = options.cannedSummary {
                let body = try String(contentsOf: containerPath(canned), encoding: .utf8)
                let template = Summaries.template()
                let md = Summaries.document(title: recording.title, template: template.name, body: body,
                                            date: recording.date.addingTimeInterval(600))
                try md.write(to: Summaries.outputURL(in: recording.folder, template: template.name), atomically: true, encoding: .utf8)
            } else if OnDeviceSummarizer.isAvailable {
                SummaryJobs.shared.start(recording)
                await SummaryJobs.shared.wait(recording.folder)
            }
            await library.refresh()
            result["summary"] = library.recordings.first { $0.folder == recording.folder }?.summary?.lastPathComponent as Any
            result["title"] = recording.title
            result["ok"] = true
        } catch {
            result["ok"] = false
            result["error"] = error.localizedDescription
        }
    }

    /// `--rate-test <title or path>`: plays 3 s at 1× and 3 s at 2× (silently) and reports how far
    /// the position moved each time.
    @MainActor
    static func rateTest(_ target: String, library: Library) async {
        var result: [String: Any] = ["mode": "rate-test", "target": target]
        let recording = target.hasPrefix("/") || target.hasPrefix("~/")
            ? await library.importFiles([containerPath(target)]).first
            : library.recordings.first { $0.title == target }
        guard let recording else {
            result["ok"] = false
            write(result)
            return
        }
        let player = Player.shared
        player.volume = 0
        for rate: Float in [1, 2] {
            player.unload()
            player.load(recording)
            player.setRate(rate)
            player.play()
            try? await Task.sleep(for: .seconds(3))
            player.pause()
            result["moved@\(rate)"] = player.currentTime
            result["playing@\(rate)"] = player.isPlaying
            result["error@\(rate)"] = player.errorMessage as Any
        }
        player.setRate(1)
        player.unload()
        let one = result["moved@1.0"] as? Double ?? 0, two = result["moved@2.0"] as? Double ?? 0
        result["ok"] = two > one * 1.6
        write(result)
    }

    /// `--fake-mic <file> --intents [run|hold]`: performs the App Intents as Siri, Shortcuts, the
    /// Action button, the Control and the Live Activity buttons do, and checks the recorder, the
    /// Live Activity (as ActivityKit reports it) and the Control state after each step. `hold`
    /// starts a recording through the intent and leaves it running (Dynamic Island screenshots).
    @MainActor
    static func intents(_ mode: String, recorder: Recorder, library: Library) async {
        var result: [String: Any] = ["mode": "intents", "variant": mode,
                                     "activitiesEnabled": ActivityAuthorizationInfo().areActivitiesEnabled]
        var steps: [[String: Any]] = []
        var ok = true
        func snapshot(_ name: String, expectActive: Bool, expectPaused: Bool = false) async {
            try? await Task.sleep(for: .milliseconds(800))
            let activities = LiveRecording.currentActivities().filter { ($0["state"] as? String) == "active" }
            let pass = recorder.isActive == expectActive && (recorder.state == .paused) == expectPaused
                && RecordingControl.isRecording == expectActive
                && activities.count == (expectActive ? 1 : 0)
                && (!expectActive || (activities.first?["isPaused"] as? Bool) == expectPaused)
            ok = ok && pass
            steps.append(["step": name, "pass": pass, "recorder": "\(recorder.state)", "elapsed": recorder.elapsed,
                          "control": RecordingControl.isRecording, "activities": activities])
        }
        let consent = RecordingCommands.consentShown
        do {
            // Before the one-time notice an intent may not start a recording.
            RecordingCommands.consentShown = false
            do {
                _ = try await StartRecordingIntent().perform()
                steps.append(["step": "start-without-consent", "pass": false])
                ok = false
            } catch {
                steps.append(["step": "start-without-consent", "pass": !recorder.isActive, "error": error.localizedDescription])
                ok = ok && !recorder.isActive
            }
            RecordingCommands.consentShown = true

            _ = try await StartRecordingIntent().perform()
            await snapshot("start", expectActive: true)
            if mode == "hold" {
                result["ok"] = ok
                result["steps"] = steps
                write(result)
                return
            }
            try? await Task.sleep(for: .seconds(2))
            _ = try await PauseRecordingIntent().perform()
            await snapshot("pause", expectActive: true, expectPaused: true)
            _ = try await PauseRecordingIntent().perform()
            await snapshot("resume", expectActive: true)
            let first = recorder.folder
            let off = RecordingToggleIntent()
            off.value = false
            _ = try await off.perform()
            await snapshot("control-off", expectActive: false)

            let on = RecordingToggleIntent()
            on.value = true
            _ = try await on.perform()
            await snapshot("control-on", expectActive: true)
            try? await Task.sleep(for: .seconds(1))
            let second = recorder.folder
            _ = try await StopRecordingIntent().perform()
            await snapshot("stop", expectActive: false)

            await library.refresh()
            let saved = library.recordings.filter { $0.folder == first || $0.folder == second }
            result["saved"] = saved.map(describe)
            let savedOK = saved.count == 2 && saved.allSatisfy { $0.duration > 0.5 }
            ok = ok && savedOK
        } catch {
            ok = false
            result["error"] = error.localizedDescription
        }
        RecordingCommands.consentShown = consent
        result["liveEvents"] = LiveRecording.shared.events
        result["steps"] = steps
        result["ok"] = ok
        write(result)
    }

    /// `--import <path>`: the same path as "Open in" (`Library.openDocument`).
    @MainActor
    static func importFile(path: String, library: Library) async -> Recording? {
        var result: [String: Any] = ["mode": "import", "source": path]
        library.importErrors = []
        let recording = await library.openDocument(URL(filePath: path))
        if let recording {
            result.merge(describe(recording)) { _, new in new }
            result["files"] = (try? FileManager.default.contentsOfDirectory(atPath: recording.folder.path).sorted()) ?? []
            result["date"] = ISO8601DateFormatter().string(from: recording.date)
            result["sourceStillThere"] = FileManager.default.fileExists(atPath: path)
        }
        result["errors"] = library.importErrors
        result["ok"] = recording != nil
        result["libraryCount"] = library.recordings.count
        write(result)
        return recording
    }

    /// `--inbox <path>`: copies the file into the real App Group inbox (as the share extension
    /// does), then picks the inbox up as on `.active`.
    @MainActor
    static func inbox(path: String, library: Library) async {
        var result: [String: Any] = ["mode": "inbox", "source": path]
        do {
            guard let inbox = Importer.inbox else { throw RecorderError(message: "no App Group container") }
            result["inbox"] = inbox.path
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let target = inbox.appending(path: URL(filePath: path).lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: URL(filePath: path), to: target)
            library.importErrors = []
            let before = Set(library.recordings.map(\.folder))
            await library.pickUpInbox()
            let added = library.recordings.filter { !before.contains($0.folder) }
            let left = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path).filter { !$0.hasPrefix(".") }) ?? []
            result["imported"] = added.map(describe)
            result["inboxLeft"] = left
            result["errors"] = library.importErrors
            result["ok"] = !added.isEmpty && left.isEmpty
        } catch {
            result["ok"] = false
            result["error"] = error.localizedDescription
        }
        write(result)
    }

    /// `--fake-mic <file>` without `--record`: the record button uses the file instead of the
    /// microphone (UI tests). Nil otherwise: the real microphone.
    static func uiFakeMic() -> (any CaptureSource)? {
        guard let path = options.fakeMic, options.record == nil else { return nil }
        return try? FakeMicSource(url: URL(filePath: path))
    }

    /// `--fake-mic <file> --record <s>`: records from the file (ends at its end or after `s`),
    /// sets a marker at 10 s; with `--simulate-interruption <s>` an interruption of 2 s, with
    /// `--kill-after <s>` a hard kill (SIGKILL) during the recording.
    @MainActor
    static func record(path: String, seconds: Double, options: SelftestOptions, recorder: Recorder, library: Library) async {
        var result: [String: Any] = ["mode": "record", "source": path]
        do {
            try await recorder.start(source: FakeMicSource(url: URL(filePath: path)))
            guard let folder = recorder.folder else { throw RecorderError(message: "no folder") }
            result["folder"] = folder.lastPathComponent
            if let kill = options.killAfter {
                Task.detached {
                    try? await Task.sleep(for: .seconds(kill))
                    Darwin.kill(getpid(), SIGKILL)
                }
            }
            if let at = options.simulateInterruption {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(at))
                    postInterruption(.began, options: [])
                    try? await Task.sleep(for: .seconds(2))
                    postInterruption(.ended, options: .shouldResume)
                }
            }
            let start = Date()
            var marked = false
            while recorder.isActive, Date().timeIntervalSince(start) < seconds {
                try? await Task.sleep(for: .milliseconds(100))
                if !marked, recorder.elapsed >= 10 {
                    recorder.addMarker()
                    marked = true
                }
            }
            result["wallSeconds"] = Date().timeIntervalSince(start)
            await recorder.stop()
            while recorder.state != .idle { try? await Task.sleep(for: .milliseconds(100)) }
            await library.refresh()
            let audio = folder.appending(path: "\(folder.lastPathComponent).m4a")
            let exists = FileManager.default.fileExists(atPath: audio.path)
            let cafLeft = FileManager.default.fileExists(atPath: folder.appending(path: "\(folder.lastPathComponent).caf").path)
            let meta = RecordingMeta.read(from: folder)
            result["audio"] = audio.path
            result["duration"] = Storage.duration(of: audio)
            result["markers"] = meta?.markers ?? []
            result["metaRecordingFlag"] = meta?.recording as Any
            result["cafLeft"] = cafLeft
            result["events"] = recorder.events
            result["error"] = recorder.errorMessage as Any
            result["inLibrary"] = library.recordings.contains { $0.folder.standardizedFileURL == folder.standardizedFileURL }
            result["ok"] = exists && !cafLeft && recorder.errorMessage == nil
        } catch {
            result["ok"] = false
            result["error"] = error.localizedDescription
        }
        write(result)
    }

    /// An absolute path, or `~/…` inside the app's container (on a device the container path is
    /// not known up front; `devicectl device copy to` puts fixtures in `tmp/`).
    static func containerPath(_ target: String) -> URL {
        target.hasPrefix("~/") ? URL(filePath: NSHomeDirectory()).appending(path: String(target.dropFirst(2)))
                               : URL(filePath: target)
    }

    /// `--transcribe <title or path>`: a path is imported first (copy), a title is looked up.
    /// Measures wall time and peak memory (phys_footprint, sampled every 0.1 s). With
    /// `--cancel-after <s>` the job is cancelled and nothing may be left behind; `--no-speakers`
    /// skips Who. Returns the recording so the UI shows it.
    @MainActor
    static func transcribe(_ target: String, options: SelftestOptions, library: Library) async -> Recording? {
        var result: [String: Any] = ["mode": "transcribe", "target": target, "speakers": !options.noSpeakers]
        let recording: Recording?
        if target.hasPrefix("/") || target.hasPrefix("~/") {
            recording = await library.importFiles([containerPath(target)]).first
        } else {
            recording = library.recordings.first { $0.title == target }
        }
        guard let recording else {
            result["ok"] = false
            result["error"] = "recording not found: \(target) \(library.importErrors)"
            write(result)
            return nil
        }
        result["title"] = recording.title
        result["audioDuration"] = recording.duration
        let baseline = footprintMB()
        let sampler = MemorySampler()
        let sampling = Task.detached { await sampler.run() }
        let start = Date()
        let jobs = Transcriptions.shared
        jobs.start(recording, speakers: !options.noSpeakers)
        if let after = options.cancelAfter {
            try? await Task.sleep(for: .seconds(after))
            result["phaseAtCancel"] = "\(jobs.phase(of: recording.folder).map { String(describing: $0) } ?? "none")"
            jobs.cancel(recording.folder)
        }
        await jobs.wait(recording.folder)
        let seconds = Date().timeIntervalSince(start)
        sampling.cancel()
        await library.refresh()
        result["seconds"] = seconds
        result["baselineMB"] = baseline
        result["peakMB"] = await sampler.peak
        result["realtimeFactor"] = recording.duration / max(seconds, 0.001)
        result["bgSubmitError"] = jobs.lastSubmitError as Any
        result["bgTaskStarted"] = jobs.lastBackgroundTaskStarted
        result["error"] = jobs.errors[recording.folder.standardizedFileURL] as Any
        result["files"] = ((try? FileManager.default.contentsOfDirectory(atPath: recording.folder.path)) ?? []).sorted()
        result["whoRaw"] = await Transcriber.shared.lastRawWho
        result["timings"] = await Transcriber.shared.lastTimings
        result["license"] = licenseStatus()
        let json = Storage.transcriptFile(in: recording.folder)
        result["json"] = json?.path as Any
        if let json, let transcript = try? TranscriptWriter.read(json: json) {
            let words = transcript.segments.flatMap { seg in
                seg.words.map { ["text": $0.text, "start": $0.start, "end": $0.end, "speaker": seg.speakerNumber.map { $0 as Any } ?? NSNull()] as [String: Any] }
            }
            result["words"] = words
            result["text"] = transcript.segments.map(\.text).joined(separator: " ")
            result["speakerCount"] = transcript.speakerLabels.count
            result["segments"] = transcript.segments.count
        }
        if options.cancelAfter != nil {
            result["ok"] = json == nil && jobs.errors[recording.folder.standardizedFileURL] == nil
        } else {
            result["ok"] = json != nil
        }
        write(result)
        return library.recordings.first { $0.folder == recording.folder }
    }

    /// `--summarize <title or path>`: a path is imported and transcribed first (`--no-speakers`
    /// applies), a title must already have a transcript. Reports Foundation Models availability,
    /// context size, the detected language, wall time, peak memory and the summary's headings.
    @MainActor
    static func summarize(_ target: String, options: SelftestOptions, library: Library) async -> Recording? {
        var result: [String: Any] = ["mode": "summarize", "target": target,
                                     "availability": OnDeviceSummarizer.availabilityDescription,
                                     "isAvailable": OnDeviceSummarizer.isAvailable]
        var recording: Recording?
        if target.hasPrefix("/") || target.hasPrefix("~/") {
            recording = await library.importFiles([containerPath(target)]).first
            if let r = recording {
                Transcriptions.shared.start(r, speakers: !options.noSpeakers)
                await Transcriptions.shared.wait(r.folder)
                await library.refresh()
                recording = library.recordings.first { $0.folder == r.folder }
            }
        } else {
            recording = library.recordings.first { $0.title == target }
        }
        guard let recording, let json = recording.transcript else {
            result["ok"] = false
            result["error"] = "no transcribed recording: \(target) \(library.importErrors)"
            write(result)
            return recording
        }
        result["title"] = recording.title
        guard OnDeviceSummarizer.isAvailable else {
            result["ok"] = false
            result["error"] = "Foundation Models not available"
            write(result)
            return recording
        }
        let context = SystemLanguageModel.default.contextSize
        result["contextSize"] = context
        if let transcript = try? TranscriptWriter.read(json: json) {
            let lines = Summaries.lines(transcript)
            let language = Summaries.language(of: lines.joined(separator: "\n")) ?? "?"
            result["language"] = language
            result["languageSupported"] = OnDeviceSummarizer.supports(language: language)
            result["chunks"] = Summaries.chunks(lines, limit: max(800, context - 1600)).count
        }
        let sampler = MemorySampler()
        let sampling = Task.detached { await sampler.run() }
        let start = Date()
        let jobs = SummaryJobs.shared
        jobs.start(recording)
        if let after = options.cancelAfter {
            try? await Task.sleep(for: .seconds(after))
            jobs.cancel(recording.folder)
        }
        await jobs.wait(recording.folder)
        sampling.cancel()
        await library.refresh()
        result["seconds"] = Date().timeIntervalSince(start)
        result["peakMB"] = await sampler.peak
        result["error"] = jobs.errors[recording.folder.standardizedFileURL] as Any
        result["files"] = ((try? FileManager.default.contentsOfDirectory(atPath: recording.folder.path)) ?? []).sorted()
        let file = Summaries.file(in: recording.folder)
        result["summaryFile"] = file?.lastPathComponent as Any
        if let file, let md = try? String(contentsOf: file, encoding: .utf8) {
            result["summary"] = md
            result["headings"] = Summaries.blocks(Summaries.body(ofDocument: md)).compactMap { block -> String? in
                if case .heading(let h) = block { h } else { nil }
            }
        }
        result["ok"] = options.cancelAfter != nil ? file == nil : file != nil
        write(result)
        return library.recordings.first { $0.folder == recording.folder }
    }

    /// What the SDK stored after its license check (read-only; the token itself is not logged).
    static func licenseStatus() -> [String: Any] {
        var out: [String: Any] = [:]
        let id = Bundle.main.bundleIdentifier ?? ""
        for model in ["voz", "who"] {
            let raw = UserDefaults.standard.object(forKey: "ai.desertant.license.\(id).\(model)")
            let data = (raw as? String).map { Data($0.utf8) } ?? raw as? Data
            if let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                out[model] = ["activated": o["activated"] ?? false, "period": o["period"] ?? NSNull(),
                              "hasToken": o["token"] != nil, "lastFailedGrantAt": o["lastFailedGrantAt"] ?? NSNull()]
            } else {
                out[model] = raw == nil ? "none" : "unreadable"
            }
        }
        return out
    }

    /// Resident memory as Xcode's gauge shows it (phys_footprint), in MB.
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    actor MemorySampler {
        private(set) var peak = 0.0
        func run() async {
            while !Task.isCancelled {
                peak = max(peak, Selftest.footprintMB())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: Demo states (screenshots)

    enum DemoRoute { case open(Recording), record, about, onboarding }

    /// `--demo-state <name>`: puts the UI in a fixed state with sample data (after `--reset`).
    /// `idle`: detail of a 12:30 recording, stopped at 0. `playing-10` / `playing-90`: the same,
    /// playing from 10 % / 90 %. `recording`: the record screen, recording from a generated
    /// speech-like signal. `speakers` / `share`: the transcript with the speaker-naming sheet or the
    /// web page's share sheet open. Anything else: the library as is.
    @MainActor
    static func demo(_ name: String, recorder: Recorder, library: Library) async -> DemoRoute? {
        var result: [String: Any] = ["mode": "demo-state", "state": name]
        defer { write(result) }
        do {
            switch name {
            case "idle", "detail", "playing-10", "playing-90":
                let folder = try await Task.detached {
                    try makeDemoRecording(title: "Interview Anna", seconds: 750, markers: [95, 312, 540])
                }.value
                await library.refresh()
                guard let recording = library.recordings.first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else {
                    throw RecorderError(message: "demo recording not in library")
                }
                let player = Player.shared
                player.load(recording)
                if name.hasPrefix("playing-"), let percent = Double(name.dropFirst("playing-".count)) {
                    player.seek(to: player.duration * percent / 100)
                    player.play()
                }
                result["ok"] = true
                return .open(recording)
            case "transcript", "summary", "transcribing", "error", "speakers", "share":
                let folder = try await Task.detached {
                    try makeDemoRecording(title: "Weekoverleg team", seconds: 750, markers: [])
                }.value
                if name != "transcribing", name != "error" {
                    try await Task.detached { try writeDemoTranscript(in: folder, duration: 750, summary: name == "summary") }.value
                }
                await library.refresh()
                guard let recording = library.recordings.first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else {
                    throw RecorderError(message: "demo recording not in library")
                }
                switch name {
                case "transcribing": Transcriptions.shared.demoPhase(folder, .transcribing(0.42))
                case "error": Transcriptions.shared.errors[folder.standardizedFileURL] = Transcriber.missingModels
                default: break
                }
                let player = Player.shared
                player.load(recording)
                if name == "transcript" {
                    player.seek(to: 21)
                    player.play()
                }
                result["ok"] = true
                return .open(recording)
            case "library", "import-error":
                try await Task.detached { try makeDemoLibrary() }.value
                await library.refresh()
                if let lecture = library.recordings.first(where: { $0.title == "College statistiek" }) {
                    Transcriptions.shared.demoPhase(lecture.folder, .transcribing(0.42))
                }
                if name == "import-error" {
                    library.importErrors = [String(localized: "“\("Notitie 12.amr")” is not an audio or video file Bandje can open.")]
                }
                result["ok"] = true
                return nil
            case "recording":
                let source = FileManager.default.temporaryDirectory.appending(path: "demo-mic.caf")
                try await Task.detached { try writeSpeechLike(to: source, seconds: 600) }.value
                try await recorder.start(source: FakeMicSource(url: source))
                result["ok"] = true
                return .record
            case "about":
                result["ok"] = true
                return .about
            case "onboarding":
                result["ok"] = true
                return .onboarding
            case "open-newest":
                // The newest recording (the sample), playing from 40 s, without resetting anything.
                // The sample: the newest with a summary (the English library has a newer call without one).
                guard let recording = library.recordings.first(where: { $0.summary != nil && $0.transcript != nil })
                        ?? library.recordings.first else { throw RecorderError(message: "empty library") }
                Player.shared.load(recording)
                if let seek = options.seek {
                    // Paused there: the transcript opens at that sentence, highlighted.
                    Player.shared.seek(to: seek)
                } else {
                    Player.shared.seek(to: min(40, Player.shared.duration / 3))
                    Player.shared.play()
                }
                result["ok"] = true
                return .open(recording)
            default:
                result["ok"] = true
                return nil
            }
        } catch {
            result["ok"] = false
            result["error"] = error.localizedDescription
            return nil
        }
    }

    /// A finished recording in Documents with a quiet, speech-like signal.
    nonisolated static func makeDemoRecording(title: String, seconds: Double, markers: [Double]) throws -> URL {
        let caf = try Storage.newRecording(title: title, date: Date().addingTimeInterval(-3600))
        try writeSpeechLike(to: caf, seconds: seconds)
        _ = try AudioExport.convertToM4A(caf)
        let folder = caf.deletingLastPathComponent()
        var meta = RecordingMeta.read(from: folder) ?? RecordingMeta(created: Date())
        meta.recording = nil
        meta.markers = markers
        try meta.write(to: folder)
        return folder
    }

    /// A 220 Hz tone with a syllable-like envelope (so the level moves), written as CAF. Ten
    /// seconds are computed once and repeated (a long demo would take too long in Debug).
    nonisolated static func writeSpeechLike(to url: URL, seconds: Double) throws {
        let writer = try CAFWriter(url: url)
        let rate = CAFWriter.sampleRate
        let block = speechLike(seconds: 10, rate: rate)
        var left = Int(seconds * rate)
        while left > 0 {
            let n = min(left, block.count)
            writer.append(n == block.count ? block : Array(block[..<n]), rate: rate)
            left -= n
        }
        writer.finish()
    }

    nonisolated static func speechLike(seconds: Double, rate: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { i -> Float in
            let t = Double(i) / rate
            let envelope = max(0, sin(2 * .pi * 3.1 * t)) * (0.5 + 0.5 * sin(2 * .pi * 0.4 * t))
            return Float(0.25 * envelope * sin(2 * .pi * 220 * t))
        }
    }

    /// Six recordings of different length, age and transcript state (screenshots of the library).
    /// `--render-art`: writes cassette.png, cassette-blank.png and wordmark.png into `dir`.
    @MainActor static func renderArt(to dir: String) {
        let folder = containerPath(dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func save(_ view: some View, _ name: String, scale: CGFloat) {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
            renderer.scale = scale
            renderer.isOpaque = false
            if let data = renderer.uiImage?.pngData() { try? data.write(to: folder.appending(path: name)) }
        }
        save(CassetteView(state: CassetteState(duration: 0, title: "Band·je")).frame(width: 1000), "cassette.png", scale: 3)
        save(CassetteView(state: CassetteState()).frame(width: 1000), "cassette-blank.png", scale: 3)
        save(BrandMark(size: 200).foregroundStyle(.white).padding(10), "wordmark.png", scale: 3)
        write(["mode": "render-art", "ok": true])
    }

    /// docs/appstore/content/<lang>.json, the parts the screenshots use.
    struct CannedSample: Sendable {
        struct Item: Sendable { let title: String; let speakers: [String]; let lines: [(Int, String)] }
        let speakers: [String]
        let lines: [(Int, String)]
        let summary: String
        let list: [Item]

        init(file: URL) throws {
            let o = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
            let sample = o["sample"] as? [String: Any] ?? [:]
            speakers = sample["speakers"] as? [String] ?? []
            lines = (sample["lines"] as? [[Any]] ?? []).map { ($0[0] as? Int ?? 0, $0[1] as? String ?? "") }
            summary = sample["summary"] as? String ?? ""
            list = (o["list"] as? [[String: Any]] ?? []).map { item in
                let speakers = item["speakers"] as? [String] ?? []
                let lines = (item["lines"] as? [String] ?? []).enumerated().map { ($0.offset % 2, $0.element) }
                return Item(title: item["title"] as? String ?? "", speakers: speakers, lines: lines)
            }
        }
    }

    /// `--sample-date 2026-11-05T10:30:00` (local time).
    nonisolated static func parseSampleDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    /// `today`: the day the sample lists are laid out from (the day after the sample, as in the Mac
    /// window), so they don't shift with the clock (a run past midnight put a call at 23:59).
    nonisolated static func makeDemoLibrary(english: Bool = false, dutch: Bool = false, today: Date? = nil,
                                            list: [CannedSample.Item]? = nil) throws {
        let now = Date()
        let day = 86_400.0
        let start = Calendar.current.startOfDay(for: today ?? now)
        func ago(_ days: Double, _ hour: Double) -> Double { now.timeIntervalSince(start.addingTimeInterval(-days * day + hour * 3600)) }
        let sampleList = english || dutch || list != nil
        // A canned list takes the English list's places: today 9:00, two and four days back.
        let places: [(Double, Double, Double)] = [(1240, 0, 9), (1830, 2, 14.25), (915, 4, 9.5)]
        let items: [(String, Double, Double, Bool, Bool)] = list.map { list in
            zip(list, places).map { item, place in (item.title, place.0, ago(place.1, place.2), true, false) }
        } ?? (dutch
            // The Mac window's Dutch list: the sample "Planning, donderdag" is added yesterday.
            ? [("Gesprek met Jan", 18, ago(0, 9.67), true, false),
               ("Sollicitatie Sanne", 127, ago(2, 14.25), true, false),
               ("Weekoverleg", 54, ago(4, 10), true, false)]
            : english
            // The Mac window's list (band.je): the sample "Planning, Thursday" is added yesterday.
            ? [("Call with Sarah", 1240, ago(0, 9), true, false),
               ("Interview, Sanne", 1830, ago(2, 14.25), true, false),
               ("Weekly standup", 915, ago(4, 9.5), true, false)]
            : [  // title, seconds, age, transcript, summary
            ("Weekoverleg team", 2832, 2 * 3600, true, true),
            ("College statistiek", 3730, 5 * 3600, false, false),
            ("Interview Anna", 750, day + 4000, true, false),
            ("Spraakbericht Joris", 48, 2 * day, false, false),
            ("Belopname huisarts", 365, 5 * day, true, false),
            (Storage.defaultTitle(for: now.addingTimeInterval(-9 * day)), 201, 9 * day, false, false),
        ])
        let cannedLines = Dictionary(uniqueKeysWithValues: (list ?? []).map { ($0.title, $0.lines) })
        let cannedNames = Dictionary(uniqueKeysWithValues: (list ?? []).map { ($0.title, $0.speakers) })
        let rate = 8_000.0
        let block = speechLike(seconds: 10, rate: rate)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        for (title, seconds, age, transcript, summary) in items {
            let caf = try Storage.newRecording(title: title, date: now.addingTimeInterval(-age))
            let folder = caf.deletingLastPathComponent()
            let wav = folder.appending(path: "\(folder.lastPathComponent).wav")
            let file = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                                                   AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                                                   AVLinearPCMIsFloatKey: false])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(block.count))!
            var left = Int(seconds * rate)
            while left > 0 {
                let n = min(left, block.count)
                block.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: n) }
                buffer.frameLength = AVAudioFrameCount(n)
                try file.write(from: buffer)
                left -= n
            }
            var meta = RecordingMeta.read(from: folder) ?? RecordingMeta(created: now.addingTimeInterval(-age))
            meta.recording = nil
            try meta.write(to: folder)
            if transcript {
                try writeDemoTranscript(in: folder, duration: seconds, summary: summary,
                                        lines: sampleList ? cannedLines[title] ?? sampleLines[title] : nil,
                                        names: sampleList ? cannedNames[title] ?? sampleNames[title] ?? [] : ["Anna", "Joris"])
            }
        }
    }

    /// A Dutch two-speaker conversation (named "Anna" and "Joris") as the transcript of `folder`,
    /// optionally with a summary.
    /// English demo transcripts (the list in the Mac window on band.je).
    nonisolated static let sampleLines: [String: [(Int, String)]] = [
        "Gesprek met Jan": [(0, "Goedemiddag, met Jan. Ik bel even over de afspraak van volgende week dinsdag."),
                            (1, "Hoi Jan. Dinsdag om tien uur staat nog, toch?")],
        "Sollicitatie Sanne": [(0, "Goedemiddag Sanne, fijn dat je er bent. Zullen we beginnen met hoe je bij design terechtkwam?"),
                               (1, "Graag. Het begon met posters voor mijn schoolband, geloof het of niet.")],
        "Weekoverleg": [(0, "Goedemorgen allemaal. Korte ronde: wat is af, en wat komt er?"),
                        (1, "De twee crashmeldingen zijn opgelost, ik zit nu op de welkomstschermen.")],
        "Call with Sarah": [(0, "Hi Sarah, thanks for calling back. Do you have a minute about the contract?"),
                            (1, "Sure. I read it last night, and there are two things I'd like to change.")],
        "Interview, Sanne": [(0, "Thanks for making time, Sanne. Shall we start with how you got into design?"),
                             (1, "Of course. It started with posters for my school band, believe it or not.")],
        "Weekly standup": [(0, "Morning everyone. Quick round: what did you finish, what's next?"),
                           (1, "I closed the two crash reports and I'm on the onboarding screens now.")],
    ]
    nonisolated static let sampleNames: [String: [String]] = [
        "Gesprek met Jan": ["Jan", "Ben"], "Sollicitatie Sanne": ["Chris", "Sanne"], "Weekoverleg": ["Anna", "Ben"],
        "Call with Sarah": ["Ben", "Sarah"], "Interview, Sanne": ["Chris", "Sanne"], "Weekly standup": ["Anna", "Ben"],
    ]

    nonisolated static func writeDemoTranscript(in folder: URL, duration: Double, summary: Bool,
                                                lines given: [(Int, String)]? = nil, names: [String] = ["Anna", "Joris"]) throws {
        let lines: [(Int, String)] = given ?? [
            (0, "Goedemorgen allemaal. Zullen we beginnen met de planning voor de lancering?"),
            (1, "Ja, goed idee. De app is bijna klaar, we testen deze week nog op een paar toestellen."),
            (0, "Mooi. Wat is er nog nodig voordat we hem kunnen insturen?"),
            (1, "Vooral de schermafbeeldingen en de teksten voor de App Store. Die maak ik vrijdag af."),
            (0, "Dan zet ik de privacyverklaring op de website. Kun jij de vertaling naar het Engels nakijken?"),
            (1, "Doe ik. Zullen we volgende week dinsdag om tien uur kijken waar we staan?"),
            (0, "Prima, ik stuur een uitnodiging. Verder nog iets?"),
            (1, "Alleen dat de transcriptie op oudere iPhones wat langzamer is. Dat wil ik nog meten."),
            (0, "Goed punt. Neem een opname van een uur, dan weten we het zeker."),
        ]
        var segments: [Segment] = []
        var t = 1.2
        for (speaker, text) in lines {
            var words: [TimedWord] = []
            for word in text.split(separator: " ") {
                let length = 0.12 + 0.045 * Double(word.count)
                words.append(TimedWord(text: String(word), start: t, end: t + length))
                t += length + 0.08
            }
            segments.append(Segment(speaker: TranscriptWriter.speakerLabel(speaker), words: words, speakerNumber: speaker))
            t += 1.1
        }
        let name = folder.lastPathComponent
        let transcript = Transcript(title: name, duration: duration, mode: TranscriptWriter.modeSpeakers,
                                    vozVersion: Transcriber.vozVersion, whoVersion: Transcriber.whoVersion,
                                    segments: segments,
                                    speakerNames: Dictionary(uniqueKeysWithValues: names.enumerated().map { (TranscriptWriter.speakerLabel($0.offset), $0.element) }),
                                    audioFile: Storage.audioFile(in: folder)?.lastPathComponent)
        try TranscriptWriter.write(transcript, json: folder.appending(path: "\(name).json"))
        guard summary else { return }
        let body = """
        ## Kern
        De app is bijna klaar voor de lancering. Deze week volgen nog tests op een paar toestellen; daarna gaan de App Store-materialen en de privacyverklaring de deur uit.

        ## Besluiten
        - De lancering gaat door zoals gepland.
        - Joris meet de transcriptiesnelheid op oudere iPhones met een opname van een uur.

        ## Actiepunten
        - Joris: schermafbeeldingen en App Store-teksten, vrijdag.
        - Anna: privacyverklaring op de website.
        - Joris: Engelse vertaling nakijken.

        ## Open vragen
        - Hoe snel is de transcriptie op oudere iPhones?

        ## Vervolg
        Dinsdag om tien uur, Anna stuurt de uitnodiging.
        """
        let md = Summaries.document(title: name, template: Summaries.template().name, body: body)
        try md.write(to: Summaries.outputURL(in: folder), atomically: true, encoding: .utf8)
    }

    static func postInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended { info[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    static func describe(_ recording: Recording) -> [String: Any] {
        var playable = false
        if let audio = recording.audio, let player = try? AVAudioPlayer(contentsOf: audio) {
            playable = player.prepareToPlay() && player.duration > 0
        }
        return ["title": recording.title, "duration": recording.duration, "markers": recording.markers,
                "audio": recording.audio?.lastPathComponent ?? "", "playable": playable,
                "inCloud": recording.folder.path.contains("Mobile Documents")]
    }

    /// Empties Documents (test isolation), keeping nothing.
    static func resetDocuments() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: URL.documentsDirectory, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? fm.removeItem(at: item) }
    }

    /// Model folders in the bundle: present, and complete according to the SDK's own check.
    static func checkModels() -> [String: Any] {
        let models = Bundle.main.bundleURL.appending(path: "Models")
        let voz = models.appending(path: "voz")
        let who = models.appending(path: "who")
        let vozOK = Voz.isDownloaded(directory: voz.path)
        let whoOK = Who.isDownloaded(directory: who.path)
        return ["mode": "check-models", "ok": vozOK && whoOK, "voz": vozOK, "who": whoOK]
    }

    static func write(_ result: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: resultURL, options: .atomic)
        } catch {
            print("selftest: could not write result: \(error)")
        }
    }
}
#endif
