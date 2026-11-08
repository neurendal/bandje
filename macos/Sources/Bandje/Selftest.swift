#if DEBUG
import AppKit
import Carbon.HIToolbox
import CoreAudio
import Foundation
import FoundationModels

/// DEBUG-only command line test modes. Results go to ~/Music/Bandje/selftest/last.json,
/// because `open` does not forward stdout.
@MainActor
enum Selftest {
    static var directory: URL { OutputLocation.defaultDirectory.appendingPathComponent("selftest", isDirectory: true) }

    /// Returns true when a selftest mode was started (the app then skips its normal UI).
    static func runIfRequested() -> Bool {
        if CommandLine.arguments.contains("--selftest-recover") {
            recover()
            return true
        }
        if let dir = value("--selftest-model-dir") {
            Transcriber.modelsDirectory = URL(fileURLWithPath: dir, isDirectory: true)
        }
        if let file = value("--selftest-transcribe") {
            Task { await transcribe(URL(fileURLWithPath: file)) }
            return true
        }
        // `--selftest-snapshot naming <json>` / `--selftest-snapshot shortcuts`: open the window,
        // write a PNG of it to the selftest folder, quit. For checking the layout without a screen recording.
        if let which = value("--selftest-snapshot") {
            // `--appearance light|dark`: render in that appearance, whatever macOS uses.
            if let look = value("--appearance") {
                NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
            }
            switch which {
            case "about":
                AboutWindow.show()
            case "menu":
                // The status menu as text (indent = submenu or status line), for checking the order.
                let delegate = NSApp.delegate as? BandjeApp
                delegate?.setUpForSnapshot()
                write(["mode": "selftest-snapshot", "menu": delegate?.menuOutline() ?? [], "errors": [String]()], to: "last.json")
                NSApp.terminate(nil)
                return true
            case "menu-open":
                // The status menu open, as clicked (website screenshots): `--library <folder>` its
                // recordings, `--mic`/`--output` the device names shown. last.json gets the pid with
                // "open": false at once and "open": true once the menu is up; a script captures the
                // windows meanwhile (screencapture -l). The menu closes and the app quits after 6 s.
                if let library = value("--library") { OutputLocation.snapshotDirectory = URL(fileURLWithPath: library, isDirectory: true) }
                BandjeApp.snapshotDevices = (value("--mic") ?? "Microphone", value("--output") ?? "Speakers")
                let delegate = NSApp.delegate as? BandjeApp
                delegate?.setUpForSnapshot()
                if let json = value("--select") { delegate?.selectForSnapshot(URL(fileURLWithPath: json)) }
                try? delegate?.statusIconForSnapshot()?.write(to: directory.appendingPathComponent("snapshot-status.png"))
                write(["mode": "selftest-snapshot", "pid": Int(getpid()), "open": false, "errors": [String]()], to: "last.json")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    // Timers in the common modes: they fire while the menu tracks.
                    RunLoop.main.add(Timer(timeInterval: 1.5, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            // The menu's own window drawn into a bitmap (no screen capture).
                            var errors: [String] = []
                            if let view = NSApp.windows.first(where: { "\(type(of: $0))".contains("Menu") && $0.isVisible })?.contentView?.superview,
                               let png = menuPNG(view, dark: value("--appearance") == "dark") {
                                try? png.write(to: directory.appendingPathComponent("snapshot-menu.png"))
                            } else {
                                errors.append("no menu window")
                            }
                            write(["mode": "selftest-snapshot", "pid": Int(getpid()), "open": true, "errors": errors], to: "last.json")
                        }
                    }, forMode: .common)
                    RunLoop.main.add(Timer(timeInterval: 6, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            delegate?.closeMenuForSnapshot()
                            DispatchQueue.main.async { NSApp.terminate(nil) }
                        }
                    }, forMode: .common)
                    delegate?.openMenuForSnapshot()
                }
                return true
            case "window", "naming", "rename", "welcome", "recorder":
                // `--select <json>`: that recording; `--library <folder>`: the folder the library shows
                // (default the selftest folder); `--window-size 1280x800`; `--seek <s>`: the player at
                // that position, so its sentence lights up (website screenshots).
                let library = value("--library").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? directory
                Library.shared.root = { library }
                Library.shared.isRootKnown = { true }
                Task {
                    await Library.shared.refresh()
                    // The library's own URL for `--select` (an argument can arrive in another Unicode
                    // normalization than the file system's: "Сарой", "Sarą" were not found).
                    func same(_ a: String, _ b: String) -> Bool {
                        a.precomposedStringWithCanonicalMapping == b.precomposedStringWithCanonicalMapping
                    }
                    let pick = value("--select").map { arg in
                        Library.shared.recordings.compactMap(\.transcript).first { same($0.path, URL(fileURLWithPath: arg).standardizedFileURL.path) }
                            ?? URL(fileURLWithPath: arg)
                    } ?? Library.shared.recordings.first { $0.transcript != nil }?.transcript
                    Activity.shared.showsWelcome = which == "welcome"
                    if which == "recorder" {
                        // The record screen as during a recording (nothing is recorded): 1:23 in, a steady level.
                        // `--recorded-at <ISO 8601>`: the moment in the default name (App Store screenshots).
                        let started = value("--recorded-at").flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                        Activity.shared.recordingTitle = value("--title") ?? OutputLocation.defaultTitle(for: started)
                        Activity.shared.recordingStarted = Date().addingTimeInterval(-83)
                        Activity.shared.level = { 0.5 }
                        Activity.shared.isRecording = true
                    }
                    MainWindow.show(select: pick, nameSpeakers: which == "naming", tab: value("--tab"))
                    if let size = value("--window-size")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                        MainWindow.nsWindow?.setContentSize(NSSize(width: size[0], height: size[1]))
                        MainWindow.nsWindow?.center()
                    }
                    if let seek = value("--seek").flatMap(Double.init),
                       let audio = Library.shared.recordings.first(where: { $0.transcript == pick })?.audio {
                        try? await AudioPlayer.shared.load(audio)
                        AudioPlayer.shared.seek(seek)
                    }
                    // Active, so the sidebar isn't drawn dimmed.
                    NSApp.activate(ignoringOtherApps: true)
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                    MainWindow.nsWindow?.orderFrontRegardless()
                    MainWindow.nsWindow?.makeKeyAndOrderFront(nil)
                    // The Name and Colour sheet, as from the menu.
                    if which == "rename" {
                        // After the recording view is on screen.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotificationCenter.default.post(name: .bandjeRename, object: nil) }
                    }
                    // A timer in the common modes: it also fires while a sheet (Name Speakers) is up.
                    RunLoop.main.add(Timer(timeInterval: 3, repeats: false) { _ in
                        MainActor.assumeIsolated { snapshot(which) }
                    }, forMode: .common)
                }
                return true
            default:
                // `--tab 0…5`: which settings tab.
                SettingsWindow.show(apply: { _, _ in nil }, chooseFolder: { _ in false }, restart: {},
                                    tab: value("--tab").flatMap(Int.init))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { snapshot(which) }
            return true
        }
        if CommandLine.arguments.contains("--selftest-set-input") {
            setInput()
            return true
        }
        // `--selftest-help [anchor]`: open Bandje Help as the menu does (on `anchor`, like
        // Hoe maak ik een template?); check that Help Viewer or Tips runs.
        // `--selftest-capture <n>`: start and stop the dictation microphone n times, 1.5 s each with
        // 0.3 s between, like quick dictations; reports how much audio each one got.
        if let n = value("--selftest-capture").flatMap(Int.init) {
            Task { @MainActor in
                var runs: [[String: Any]] = []
                for _ in 0..<n {
                    let capture = DictationCapture()
                    var problem = ""
                    do { try await capture.start() } catch { problem = "\(error)" }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let (samples, rate) = capture.stop()
                    let seconds = rate > 0 ? Double(samples.count) / rate : 0
                    runs.append(["seconds": (seconds * 100).rounded() / 100, "restarts": capture.restarts, "error": problem])
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                write(["mode": "selftest-capture", "runs": runs, "errors": [String]()], to: "last.json")
                NSApp.terminate(nil)
            }
            return true
        }
        if CommandLine.arguments.contains("--selftest-help") {
            NSHelpManager.shared.registerBooks(in: .main)
            if let anchor = value("--selftest-help"), !anchor.hasPrefix("-") {
                BandjeApp.openHelp(anchor: anchor)
            } else {
                NSApp.showHelp(nil)
            }
            // Help Viewer shows the book, or Tips on macOS 26; it can take a while to launch.
            Task { @MainActor in
                var viewer = false
                for _ in 0..<30 where !viewer {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    viewer = NSWorkspace.shared.runningApplications.contains {
                        ["com.apple.helpviewer", "com.apple.tips"].contains($0.bundleIdentifier ?? "")
                    }
                }
                write(["mode": "selftest-help", "helpViewer": viewer,
                       "book": Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String ?? "",
                       "errors": [String]()], to: "last.json")
                NSApp.terminate(nil)
            }
            return true
        }
        if let file = value("--selftest-summarize") {
            Task { await summarize(json: URL(fileURLWithPath: file)) }
            return true
        }
        // `--selftest-export <json> [--compact]`: the shared web page for that transcript, path in last.json.
        if let json = value("--selftest-export") {
            Task {
                do {
                    let page = try await WebExport.export(json: URL(fileURLWithPath: json), compact: CommandLine.arguments.contains("--compact"))
                    write(["mode": "selftest-export", "html": page.path, "errors": [String]()], to: "last.json")
                } catch {
                    write(["mode": "selftest-export", "errors": ["\(error)"]], to: "last.json")
                }
                NSApp.terminate(nil)
            }
            return true
        }
        if let file = value("--selftest-dictate") {
            Task { await dictate(URL(fileURLWithPath: file)) }
            return true
        }
        if let seconds = value("--selftest-record").flatMap(Double.init) {
            Task { await record(seconds: seconds, fakeMic: value("--selftest-fake-mic").map { URL(fileURLWithPath: $0) }) }
            return true
        }
        return false
    }

    /// The argument after `flag`, if present.
    static func value(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--selftest-recover`: the crash-recovery path of the app (`unfinishedRecordings` +
    /// `convertToM4A`) on the selftest folder.
    static func recover() {
        var converted: [[String: Any]] = []
        var errors: [String] = []
        for caf in OutputLocation.unfinishedRecordings(in: directory) {
            do {
                let m4a = try AudioExport.convertToM4A(caf)
                converted.append(["caf": caf.path, "m4a": m4a.path, "cafRemoved": !FileManager.default.fileExists(atPath: caf.path)])
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        write(["mode": "selftest-recover", "converted": converted, "errors": errors], to: "last.json")
        NSApp.terminate(nil)
    }

    /// `--selftest-set-input`: switch the macOS default input to another device and back.
    static func setInput() {
        var result: [String: Any] = ["mode": "selftest-set-input", "lidClosed": Recorder.lidClosed()]
        let before = Recorder.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        result["before"] = Recorder.deviceName(before) ?? "?"
        result["beforeBuiltIn"] = Recorder.isBuiltIn(before)
        result["suggested"] = Recorder.suggestedMicrophone(excluding: before)?.name ?? NSNull()
        if let other = Recorder.inputDevices().first(where: { $0.id != before }) {
            result["setStatus"] = Int(Recorder.setDefaultInput(other.id))
            result["after"] = Recorder.deviceName(Recorder.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)) ?? "?"
            result["target"] = other.name
            result["restoreStatus"] = Int(Recorder.setDefaultInput(before))
            result["restored"] = Recorder.defaultDevice(kAudioHardwarePropertyDefaultInputDevice) == before
        }
        // Menu Geluidsuitvoer: the same for the output.
        let out = Recorder.outputDevice()
        result["outputBefore"] = Recorder.deviceName(out) ?? "?"
        result["outputDevices"] = Recorder.outputDevices().map(\.name)
        if let other = Recorder.outputDevices().first(where: { $0.id != out }) {
            result["outputSetStatus"] = Int(Recorder.setDefaultOutput(other.id))
            result["outputAfter"] = Recorder.deviceName(Recorder.outputDevice()) ?? "?"
            result["outputTarget"] = other.name
            result["outputRestoreStatus"] = Int(Recorder.setDefaultOutput(out))
            result["outputRestored"] = Recorder.outputDevice() == out
        }
        write(result, to: "last.json")
        NSApp.terminate(nil)
    }

    static func snapshot(_ name: String) {
        // The Name Speakers sheet on its own; the Bandje window when it is open; else the visible window.
        let sheet = ["naming", "rename"].contains(name) ? NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) : nil
        guard let window = sheet ?? MainWindow.nsWindow.flatMap({ $0.isVisible ? $0 : nil })
                ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frameView = window.contentView?.superview,
              var rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            write(["mode": "selftest-snapshot", "errors": ["no window"]], to: "last.json")
            NSApp.terminate(nil)
            return
        }
        // `--scale 2`: Retina pixels also on a non-Retina display (website screenshots).
        if let scale = value("--scale").flatMap(Double.init), scale > 0,
           let hi = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frameView.bounds.width * scale),
                                     pixelsHigh: Int(frameView.bounds.height * scale), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            hi.size = frameView.bounds.size
            rep = hi
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let url = directory.appendingPathComponent("snapshot-\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        write(["mode": "selftest-snapshot", "file": url.path, "errors": [String]()], to: "last.json")
        // An open sheet (Name Speakers, Name and Colour) blocks quitting: close it first, unsaved.
        for w in NSApp.windows { if let s = w.attachedSheet { w.endSheet(s) } }
        NSApp.terminate(nil)
    }

    /// `--selftest-summarize <json>` (M8): the example templates (fresh, in `--templates <dir>`, language
    /// `--template-language`, default nl), or only `--template <name>`, on a transcript; writes the
    /// summaries and the player next to it, like the menu does.
    static func summarize(json: URL) async {
        var result: [String: Any] = ["mode": "selftest-summarize", "available": BandjeApp.summariesAvailable]
        var errors: [String] = []
        var runs: [[String: Any]] = []
        if #available(macOS 26.0, *), OnDeviceSummarizer.isAvailable {
            let dir = URL(fileURLWithPath: value("--templates") ?? directory.appendingPathComponent("templates").path, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            Summaries.seedIfMissing(dir, language: value("--template-language") ?? "nl")
            let only = value("--template")
            do {
                let t = try TranscriptWriter.read(json: json)
                result["language"] = Summaries.language(of: Summaries.lines(t).joined(separator: "\n")) ?? NSNull()
                result["estimatedTokens"] = Summaries.estimatedTokens(Summaries.lines(t).joined(separator: "\n"))
                result["contextSize"] = SystemLanguageModel.default.contextSize
                for template in Summaries.templates(in: dir) where only == nil || only == template.name {
                    let t0 = Date()
                    var run: [String: Any] = ["template": template.name]
                    do {
                        let body = try await OnDeviceSummarizer.summarize(t, template: template) { _ in }
                        run["seconds"] = Date().timeIntervalSince(t0)
                        run["text"] = body
                        let out = Summaries.outputURL(json: json, template: template.name)
                        try Data(Summaries.document(t, template: template.name, body: body).utf8).write(to: out, options: .atomic)
                        run["file"] = out.path
                        run["headings"] = template.text.split(separator: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
                    } catch {
                        run["error"] = error.localizedDescription
                        errors.append("\(template.name): \(error.localizedDescription)")
                    }
                    runs.append(run)
                }
                result["html"] = try await WebExport.export(json: json, compact: false).path
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        result["runs"] = runs
        result["errors"] = errors
        write(result, to: "last.json")
        NSApp.terminate(nil)
    }

    /// `--selftest-dictate <file>`: the dictation path on a fixture: mono at 48 kHz as the
    /// microphone would deliver it, then resample + Voz. Also checks that the dictation hotkeys
    /// (⌃⌥⌘D, and Return/Enter/Esc without modifiers) can be registered.
    static func dictate(_ audio: URL) async {
        var result: [String: Any] = ["mode": "selftest-dictate", "input": audio.path]
        var errors: [String] = []
        result["hotkeys"] = [
            "dictate": Int(Hotkey.register(.dictate, key: kVK_ANSI_D, modifiers: Hotkey.controlOptionCommand, pressed: {})),
            "return": Int(Hotkey.register(.dictateReturn, key: kVK_Return, pressed: {})),
            "enter": Int(Hotkey.register(.dictateEnter, key: kVK_ANSI_KeypadEnter, pressed: {})),
            "escape": Int(Hotkey.register(.dictateEscape, key: kVK_Escape, pressed: {})),
        ]
        for id in [Hotkey.ID.dictate, .dictateReturn, .dictateEnter, .dictateEscape] { Hotkey.unregister(id) }
        do {
            let rate = 48_000.0
            let samples = Transcriber.downmix(try Transcriber.readChannels(audio, rate: rate).channels)
            let t0 = Date()
            result["text"] = try await Transcriber.shared.dictate(samples, rate: rate)
            result["seconds"] = Date().timeIntervalSince(t0)
            result["loadSeconds"] = await Transcriber.shared.lastLoadSeconds
            let t1 = Date()
            _ = try await Transcriber.shared.dictate(samples, rate: rate)
            result["secondsWarm"] = Date().timeIntervalSince(t1)
        } catch {
            errors.append(error.localizedDescription)
        }
        result["errors"] = errors
        write(result, to: "last.json")
        NSApp.terminate(nil)
    }

    /// `--selftest-transcribe <file>`: the app's transcription pipeline on one file (writes `.md`/`.json`
    /// next to it). With `--selftest-model-dir <dir>` the models are looked up elsewhere (missing-model test).
    static func transcribe(_ audio: URL) async {
        var result: [String: Any] = ["mode": "selftest-transcribe", "input": audio.path, "pid": Int(getpid()),
                                     "modelsDirectory": Transcriber.modelsDirectory.path,
                                     "sandboxed": ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil]
        var errors: [String] = []
        let statusLog = StatusLog()
        write(["state": "transcribing", "pid": Int(getpid())], to: "state.json")
        // `--selftest-crosstalk-db <dB>`: the `crosstalkDb` default for this run only (1000 = filter off).
        // Without the flag the built-in defaults apply. Cleared again before terminate (which exits the
        // process, so a `defer` would not run).
        if let db = value("--selftest-crosstalk-db").flatMap(Double.init) {
            UserDefaults.standard.set(db, forKey: "crosstalkDb")
        } else {
            UserDefaults.standard.removeObject(forKey: "crosstalkDb")
        }
        result["crosstalkSettings"] = ["overlap": TranscriptWriter.CrosstalkSettings.current.overlap,
                                       "db": TranscriptWriter.CrosstalkSettings.current.db]
        // Fixtures are treated as own recordings (mode A/B); `--selftest-as-import`: as
        // `Transcribeer bestand…` decides (mode A/B only for the old Mac names).
        let ownRecording = !CommandLine.arguments.contains("--selftest-as-import")
            || TranscriptWriter.isRecordingName(audio.deletingPathExtension().lastPathComponent)
        result["ownRecording"] = ownRecording
        let t0 = Date()
        do {
            let (md, transcript) = try await Transcriber.shared.transcribe(audio, ownRecording: ownRecording) { statusLog.add($0) }
            result.merge(describe(md, transcript)) { $1 }
            result["speakerCount"] = await Transcriber.shared.lastSpeakerCount
            result["whoRaw"] = await Transcriber.shared.lastRawWho
        } catch {
            errors.append(error.localizedDescription)
        }
        result["seconds"] = Date().timeIntervalSince(t0)
        result["loadSeconds"] = await Transcriber.shared.lastLoadSeconds
        result["statusUpdates"] = statusLog.summary
        result["errors"] = errors
        UserDefaults.standard.removeObject(forKey: "crosstalkDb")
        UserDefaults.standard.synchronize()
        write(["state": "done"], to: "state.json")
        write(result, to: "last.json")
        NSApp.terminate(nil)
    }

    nonisolated static func describe(_ md: URL, _ t: Transcript) -> [String: Any] {
        ["md": md.path, "json": md.deletingPathExtension().appendingPathExtension("json").path,
         "transcriptMode": t.mode, "whoVersion": t.whoVersion ?? NSNull(), "crosstalkRemoved": t.crosstalkRemoved, "duration": t.duration,
         "segments": t.segments.map { seg in
             ["speaker": seg.speaker, "start": seg.start, "end": seg.end, "text": seg.text,
              "words": seg.words.map { ["text": $0.text, "start": $0.start, "end": $0.end] }] as [String: Any]
         }]
    }

    /// Collects the status callbacks (from any thread): whether "loading" was shown and the progress values.
    final class StatusLog: @unchecked Sendable {
        private let lock = NSLock()
        private var loading = false
        private var fractions: [Double] = []
        func add(_ s: Transcriber.Status) {
            lock.withLock {
                switch s {
                case .loading: loading = true
                case .transcribing(let f): fractions.append(f)
                }
            }
        }
        var summary: [String: Any] {
            lock.withLock { ["loading": loading, "count": fractions.count, "first": fractions.first ?? -1, "last": fractions.last ?? -1,
                             "monotonic": zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }] }
        }
    }

    /// `--selftest-rebuild 4:nomic,8:mic`: capture rebuilds at these seconds after the first
    /// sample (`nomic` = as if no input device is left, output device as clock).
    static func rebuildPlan() -> [(at: Double, noMic: Bool)] {
        (value("--selftest-rebuild") ?? "").split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":")
            guard let at = parts.first.flatMap({ Double($0) }) else { return nil }
            return (at, parts.count > 1 && parts[1] == "nomic")
        }
    }

    static func record(seconds: Double, fakeMic: URL?) async {
        var result: [String: Any] = ["mode": "selftest-record", "requestedSeconds": seconds]
        var errors: [String] = []
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url: URL
        do {
            url = try OutputLocation.newRecording(title: OutputLocation.defaultTitle(for: Date()), date: Date(), in: directory)
        } catch {
            write(["mode": "selftest-record", "errors": ["\(error)"]], to: "last.json")
            NSApp.terminate(nil)
            return
        }
        result["path"] = url.path
        result["sandboxed"] = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        result["pid"] = Int(getpid())
        result["fakeMic"] = fakeMic?.path ?? NSNull()
        // M3: resolved output directory (honours `defaults ... outputDir`) and the global hotkey.
        // `--selftest-output-dir <path>` sets the default from inside the app (= the sandbox
        // container's preferences domain) for this run only.
        let args = CommandLine.arguments
        let override = args.firstIndex(of: "--selftest-output-dir").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if let override { UserDefaults.standard.set(override, forKey: "outputDir") }
        let outDir = OutputLocation.directory
        if override != nil { UserDefaults.standard.removeObject(forKey: "outputDir") }
        result["outputDir"] = outDir.path
        result["outputDirWritable"] = (try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil
        result["hotkeyStatus"] = Int(Hotkey.register(.record, key: kVK_ANSI_R, modifiers: Hotkey.controlOptionCommand, pressed: {}))

        // M4: simulated low disk space (start refused, or recording stopped).
        if let mb = value("--selftest-min-free-start-mb").flatMap(Int64.init) { Recorder.minFreeBytesToStart = mb * 1_000_000 }
        if let mb = value("--selftest-min-free-mb").flatMap(Int64.init) { Recorder.minFreeBytesWhileRecording = mb * 1_000_000 }
        let killAfter = value("--selftest-kill-after").flatMap(Double.init)
        var rebuilds = rebuildPlan()
        // M6 "start recording while a transcription runs": `--selftest-transcribe-during <file>`
        // transcribes that file 1 s into the recording, the way the app does (detached, .utility).
        var pendingTranscription = value("--selftest-transcribe-during").map { URL(fileURLWithPath: $0) }
        var transcription: Task<[String: Any], Never>?

        let recorder = Recorder(url: url)
        recorder.fakeMicURL = fakeMic
        do {
            let requested = Date()
            guard await Permissions.microphoneAllowed() else { throw RecorderError(message: Permissions.microphoneDenied) }
            try recorder.start()
            // Wait until audio actually flows; the file starts at the first sample.
            let deadline = Date().addingTimeInterval(10)
            while recorder.stats.firstSampleDate == nil, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let started = recorder.stats.firstSampleDate ?? requested
            result["startedAt"] = started.timeIntervalSince1970
            result["startDelay"] = started.timeIntervalSince(requested)
            write(["state": "recording", "startedAt": started.timeIntervalSince1970, "path": url.path, "pid": Int(getpid())],
                  to: "state.json")
            result["sleepAssertionStatus"] = Int(recorder.sleepAssertionStatus)
            // Same checks as the app's 1 s timer, plus the scripted rebuilds and kill.
            let end = started.addingTimeInterval(seconds)
            var nextHealthCheck = Date()
            while Date() < end {
                let t = Date().timeIntervalSince(started)
                if let killAfter, t >= killAfter {
                    kill(getpid(), SIGKILL)
                }
                if let file = pendingTranscription, t >= 1 {
                    pendingTranscription = nil
                    let startedAt = Date()
                    transcription = Task.detached(priority: .utility) {
                        var out: [String: Any] = ["startedAt": startedAt.timeIntervalSince1970]
                        do {
                            let (md, transcript) = try await Transcriber.shared.transcribe(file) { _ in }
                            out.merge(describe(md, transcript)) { $1 }
                        } catch {
                            out["error"] = error.localizedDescription
                        }
                        out["finishedAt"] = Date().timeIntervalSince1970
                        return out
                    }
                }
                if let next = rebuilds.first, t >= next.at {
                    rebuilds.removeFirst()
                    try recorder.rebuild(forceNoMic: next.noMic)
                }
                if Date() >= nextHealthCheck {
                    nextHealthCheck = Date().addingTimeInterval(1)
                    if let problem = recorder.healthProblem() {
                        result["stoppedBecause"] = problem
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            recorder.stop()
            result["stoppedAt"] = Date().timeIntervalSince1970
        } catch {
            errors.append(error.localizedDescription)
            recorder.stop()
        }
        result["sampleRate"] = recorder.sampleRate
        result["callbacks"] = recorder.stats.callbacks.load(ordering: .relaxed)
        result["allCallbacks"] = recorder.stats.allCallbacks.load(ordering: .relaxed)
        result["emptyCallbacks"] = recorder.stats.emptyCallbacks.load(ordering: .relaxed)
        result["bufferLayout"] = recorder.bufferLayout
        result["peak"] = Double(recorder.stats.peak)
        result["micPeak"] = Double(recorder.stats.micPeak)
        result["micName"] = recorder.micName
        result["framesWritten"] = recorder.framesWritten
        result["droppedSamples"] = recorder.droppedSamples
        result["rebuilds"] = recorder.rebuildLog
        result["gapFrames"] = recorder.stats.gapFrames.load(ordering: .relaxed)
        if let transcription { result["transcription"] = await transcription.value }
        if recorder.stats.callbacks.load(ordering: .relaxed) == 0, errors.isEmpty { errors.append("no IO callbacks") }
        if errors.isEmpty {
            result["cafPath"] = url.path
            let t0 = Date()
            do {
                let m4a = try AudioExport.convertToM4A(url)
                OutputLocation.finishMeta(url.deletingLastPathComponent())
                result["path"] = m4a.path
                result["convertSeconds"] = Date().timeIntervalSince(t0)
                result["cafRemoved"] = !FileManager.default.fileExists(atPath: url.path)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        result["errors"] = errors
        write(["state": "done"], to: "state.json")
        write(result, to: "last.json")
        NSApp.terminate(nil)
    }

    static func write(_ object: [String: Any], to name: String) {
        var object = object
        object["date"] = ISO8601DateFormatter().string(from: Date())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("Bandje selftest: could not write \(name): \(error)")
        }
    }
}
#endif

#if DEBUG
/// The open status menu at 2x on a rounded panel in the menu colour (its own glass is drawn by
/// the window server, not by the view).
@MainActor
private func menuPNG(_ view: NSView, dark: Bool) -> Data? {
    let size = view.bounds.size
    func bitmap() -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }
    guard let content = bitmap(), let rep = bitmap() else { return nil }
    content.size = size
    // Only the items: the glass behind them (NSGlassView) is drawn by the window server and comes
    // out blank; the panel below stands in for it.
    let items = view.subviews.first { $0.subviews.contains { $0 is NSScrollView } } ?? view
    // No item highlighted where the mouse pointer happens to be.
    func rows(_ v: NSView) -> [NSTableRowView] { (v as? NSTableRowView).map { [$0] } ?? v.subviews.flatMap(rows) }
    rows(items).forEach { $0.isSelected = false; $0.displayIfNeeded() }
    items.cacheDisplay(in: items.bounds, to: content)
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let panel = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
    (dark ? NSColor(white: 0.16, alpha: 0.96) : NSColor(white: 0.97, alpha: 0.96)).setFill()
    panel.fill()
    (dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.12)).setStroke()
    panel.lineWidth = 1
    panel.stroke()
    panel.addClip()
    content.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: false, hints: nil)  // draw(in:) alone copies, wiping the panel
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}
#endif
