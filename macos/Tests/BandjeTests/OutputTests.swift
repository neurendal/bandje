import AudioToolbox
import Foundation
import Testing
@testable import Bandje

/// Each test gets a fresh temporary directory (Swift Testing creates one instance per test).
final class OutputTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    @Test func iPhoneJsonRoundTripKeepsUnknownKeys() throws {
        // As the iPhone writes it: no channel, markers/recorded/location, a key nobody knows yet.
        let raw: [String: Any] = ["title": "Opname 6 nov 14.32", "duration": 12.0, "mode": "sprekers",
            "models": ["voz": "v0.5.0", "who": "v0.3.4", "sdk": "desert-ant-core 4.2.3"],
            "segments": [["speaker": "Spreker 1", "start": 0.5, "end": 1.0, "text": "hoi", "channel": NSNull(),
                          "speakerNumber": 1, "words": [["text": "hoi", "start": 0.5, "end": 1.0]]]],
            "speakerNames": [:] as [String: String], "audio": "Opname 6 nov 14.32.m4a",
            "markers": [3.5], "recorded": "2026-11-06T13:32:00Z",
            "location": ["latitude": 52.1, "longitude": 5.1, "accuracy": 20.0], "future": ["x": 1]]
        let url = dir.appendingPathComponent("t.json")
        try JSONSerialization.data(withJSONObject: raw).write(to: url)
        var t = try TranscriptWriter.read(json: url)
        #expect(t.recorded == ISO8601DateFormatter().date(from: "2026-11-06T13:32:00Z"))
        t.speakerNames["Spreker 1"] = "Anna"
        let out = try JSONSerialization.jsonObject(with: TranscriptWriter.json(t)) as! [String: Any]
        #expect(out["markers"] as? [Double] == [3.5])
        #expect((out["location"] as? [String: Double])?["latitude"] == 52.1)
        #expect((out["future"] as? [String: Int])?["x"] == 1)
        #expect(out["recorded"] as? String == "2026-11-06T13:32:00Z")
        #expect((out["speakerNames"] as? [String: String])?["Spreker 1"] == "Anna")
    }

    @Test func iPhoneModelsAreKeptWhenTheMacRewrites() throws {
        let raw: [String: Any] = ["title": "x", "duration": 1.0, "mode": "sprekers",
            "models": ["voz": "v0.6.0", "who": "v0.4.0", "sdk": "desert-ant-core 4.3.0", "device": "iPhone"],
            "segments": [] as [Any]]
        let url = dir.appendingPathComponent("m.json")
        try JSONSerialization.data(withJSONObject: raw).write(to: url)
        var t = try TranscriptWriter.read(json: url)
        t.speakerNames["Spreker 1"] = "Anna"
        let models = (try JSONSerialization.jsonObject(with: TranscriptWriter.json(t)) as! [String: Any])["models"] as! [String: Any]
        #expect(models["sdk"] as? String == "desert-ant-core 4.3.0")
        #expect(models["device"] as? String == "iPhone")
        #expect(models["voz"] as? String == "v0.6.0")
    }

    @Test func legacyRecordingKeepsItsDateAndModeAfterARename() throws {
        let folder = dir.appendingPathComponent("2026-11-05_14-30")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("2026-11-05_14-30.json"))
        let renamed = try Library.renameFolder(folder, to: "Overleg")
        #expect(RecordingMeta.read(from: renamed)?.created == date(2026, 11, 5, 14, 30))
        #expect(OutputLocation.recordingDate(renamed.appendingPathComponent("Overleg.json")) == date(2026, 11, 5, 14, 30))
    }

    @Test func summariesHaveNoLogoAnyMore() {
        let t = Transcript(title: "Opname 6 nov 14.32", duration: 1, mode: "sprekers", vozVersion: "v", whoVersion: nil, segments: [])
        let doc = Summaries.document(t, template: "Vergadering", body: "## Kern\nok")
        #expect(!doc.contains("![Band"))
        #expect(doc.hasPrefix("# "))
    }

    @Test func recordingMetaWithOnlyADateIsRead() throws {
        let folder = dir.appendingPathComponent("Oud")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{ "created" : "2026-11-05T09:30:00Z" }"#.utf8).write(to: folder.appendingPathComponent(".bandje.json"))
        #expect(RecordingMeta.read(from: folder)?.created == ISO8601DateFormatter().date(from: "2026-11-05T09:30:00Z"))
        #expect(RecordingMeta.read(from: folder)?.markers == [])
    }

    @Test func recordingMetaMatchesTheIPhone() throws {
        let folder = dir.appendingPathComponent("Opname 6 nov 14.32")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().date(from: "2026-11-06T13:32:00Z")!
        try RecordingMeta(created: date, recording: true).write(to: folder)
        let text = try String(contentsOf: folder.appendingPathComponent(".bandje.json"), encoding: .utf8)
        #expect(text.contains("\"created\" : \"2026-11-06T13:32:00Z\""))
        #expect(RecordingMeta.read(from: folder) == RecordingMeta(created: date, recording: true))
    }

    /// The iPhone's cassette colour (and any key the Mac doesn't know yet) survive a Mac rewrite;
    /// a key the Mac clears (the recording flag) is really gone.
    @Test func recordingMetaKeepsColourAndUnknownKeys() throws {
        let folder = dir.appendingPathComponent("Opname 7 nov 9.00")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"created":"2026-11-07T08:00:00Z","color":"green","recording":true,"future":{"a":1}}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent(".bandje.json"))
        var meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.color == "green")
        meta.recording = nil
        try meta.write(to: folder)
        let o = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".bandje.json"))) as? [String: Any])
        #expect(o["color"] as? String == "green")
        #expect((o["future"] as? [String: Any])?["a"] as? Int == 1)
        #expect(o["recording"] == nil)
        meta.color = nil  // back to the default: written as no key
        try meta.write(to: folder)
        let o2 = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".bandje.json"))) as? [String: Any])
        #expect(o2["color"] == nil)
        #expect(o2["future"] != nil)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (y, mo, d, h, mi)
        return Calendar.current.date(from: c)!
    }

    @Test func newRecordingsUseTheIPhoneNames() throws {
        let date = ISO8601DateFormatter().date(from: "2026-11-06T13:32:00Z")!  // 14:32 in Amsterdam
        let ams = TimeZone(identifier: "Europe/Amsterdam")!
        #expect(OutputLocation.defaultTitle(for: date, locale: Locale(identifier: "nl_NL"), timeZone: ams) == "Opname 6 nov 14.32")
        #expect(OutputLocation.defaultTitle(for: date, locale: Locale(identifier: "en_US"), timeZone: ams).hasSuffix(" Nov 6 14.32"))
        // The app's language with the Mac's region, as the iPhone (Locale.current): English in the
        // Netherlands is "6 Nov", the same name on both.
        let enNL = TranscriptWriter.titleLocale(language: "en", region: "NL")
        #expect(OutputLocation.defaultTitle(for: date, locale: enNL, timeZone: ams).hasSuffix(" 6 Nov 14.32"))
        #expect(TranscriptWriter.titleLocale(language: "nl", region: nil).identifier == "nl")
        let caf = try OutputLocation.newRecording(title: "Opname 6 nov 14.32", date: date, in: dir)
        #expect(caf.lastPathComponent == "Opname 6 nov 14.32.caf")
        #expect(caf.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(RecordingMeta.read(from: caf.deletingLastPathComponent())?.recording == true)
        let second = try OutputLocation.newRecording(title: "Opname 6 nov 14.32", date: date, in: dir)
        #expect(second.deletingLastPathComponent().lastPathComponent == "Opname 6 nov 14.32 2")
        #expect(OutputLocation.uniqueName("Templates", in: dir) != "Templates")  // reserved, any case
        #expect(OutputLocation.uniqueName("templates", in: dir) != "templates")
        #expect(OutputLocation.safeName("a/b: c") == "a-b. c")
        OutputLocation.finishMeta(caf.deletingLastPathComponent())
        #expect(RecordingMeta.read(from: caf.deletingLastPathComponent())?.recording == nil)
    }

    @Test func transcriptTakesDateMarkersAndLocationFromMeta() {
        var t = Transcript(title: "x", duration: 1, mode: "sprekers", vozVersion: "v", whoVersion: nil, segments: [])
        let meta = RecordingMeta(created: Date(timeIntervalSince1970: 5), markers: [2.5],
                                 location: RecordedLocation(latitude: 52, longitude: 5, accuracy: 9))
        TranscriptWriter.apply(meta, to: &t)
        #expect(t.recorded == Date(timeIntervalSince1970: 5))
        #expect(t.extra["markers"] as? [Double] == [2.5])
        #expect((t.extra["location"] as? [String: Double])?["accuracy"] == 9)
        var plain = t
        TranscriptWriter.apply(RecordingMeta(created: Date(timeIntervalSince1970: 7)), to: &plain)
        #expect(plain.recorded == Date(timeIntervalSince1970: 7))
    }

    @Test func coordinatedWriteReadCopyMove() throws {
        let sub = dir.appendingPathComponent("x"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let y = sub.appendingPathComponent("y.txt")
        try Files.write(Data("a".utf8), to: y)
        #expect(try Files.read(y) == Data("a".utf8))
        #expect(Files.readString(y) == "a")
        let z = dir.appendingPathComponent("z.txt"), w = dir.appendingPathComponent("w.txt")
        try Files.copy(y, to: z)
        try Files.move(z, to: w)
        #expect(FileManager.default.fileExists(atPath: y.path) && !FileManager.default.fileExists(atPath: z.path))
        #expect(Files.readString(w) == "a")
        #expect(Files.readString(dir.appendingPathComponent("missing.txt")) == nil)
    }

    @Test func publishAvoidsNameClash() throws {
        let target = dir.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Opname 6 nov 14.32"), withIntermediateDirectories: true)
        #expect(ICloudSync.publishName(for: "Opname 6 nov 14.32", in: target) == "Opname 6 nov 14.32 2")
        #expect(ICloudSync.publishName(for: "Memo", in: target) == "Memo")
    }

    @Test func stagingPlanMovesOnlyFinishedRecordings() throws {
        let staging = dir.appendingPathComponent("staging")
        let fm = FileManager.default
        func folder(_ name: String, files: [String], recording: Bool?) throws -> URL {
            let f = staging.appendingPathComponent(name)
            try fm.createDirectory(at: f, withIntermediateDirectories: true)
            for file in files { fm.createFile(atPath: f.appendingPathComponent(file).path, contents: Data()) }
            try RecordingMeta(created: Date(), recording: recording).write(to: f)
            return f
        }
        let done = try folder("A", files: ["A.m4a"], recording: nil)
        _ = try folder("B", files: ["B.caf"], recording: nil)          // not converted yet
        _ = try folder("C", files: ["C.m4a"], recording: true)         // still recording
        #expect(ICloudSync.flushStagingPlan(staging: staging).map(\.lastPathComponent) == [done.lastPathComponent])
    }

    @Test func syncToggleRefusedWhileBusy() {
        #expect(ICloudSync.canToggle(recording: false, transcribing: false, summarizing: false))
        // Also not while a stopped recording is still being converted and moved.
        #expect(!ICloudSync.canToggle(recording: false, transcribing: false, summarizing: false, finishing: true))
        #expect(!ICloudSync.canToggle(recording: true, transcribing: false, summarizing: false))
        #expect(!ICloudSync.canToggle(recording: false, transcribing: true, summarizing: false))
        #expect(!ICloudSync.canToggle(recording: false, transcribing: false, summarizing: true))
    }

    @Test func ensureDownloadedLocalFileIsImmediate() async throws {
        let f = dir.appendingPathComponent("a.m4a")
        try Data([1]).write(to: f)
        let start = Date()
        try await ICloudSync.ensureDownloaded(f)
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    @Test func recordingFoldersSkipReservedAndHidden() throws {
        for name in ["Opname 6 nov 14.32", "Templates", "selftest", ".bandje", "Memo"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("loose.m4a").path, contents: Data())
        #expect(OutputLocation.recordingFolders(in: dir).map(\.lastPathComponent) == ["Memo", "Opname 6 nov 14.32"])
    }

    @Test func legacyRecordingDateAndOwnership() throws {
        let folder = dir.appendingPathComponent("2026-11-05_14-30")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = folder.appendingPathComponent("2026-11-05_14-30.json")
        try Data("{}".utf8).write(to: json)
        #expect(OutputLocation.recordingDate(json) == date(2026, 11, 5, 14, 30))
        #expect(OutputLocation.isOwnRecording(folder.appendingPathComponent("2026-11-05_14-30.m4a")))
        let phone = dir.appendingPathComponent("Opname 6 nov 14.32")
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try RecordingMeta(created: Date(timeIntervalSince1970: 1_000)).write(to: phone)
        #expect(OutputLocation.recordingDate(phone.appendingPathComponent("Opname 6 nov 14.32.json")) == Date(timeIntervalSince1970: 1_000))
        #expect(!OutputLocation.isOwnRecording(phone.appendingPathComponent("Opname 6 nov 14.32.m4a")))  // no stereo file: iPhone
    }

    @Test func elapsedString() {
        #expect(OutputLocation.elapsedString(0) == "00:00")
        #expect(OutputLocation.elapsedString(65.9) == "01:05")
        #expect(OutputLocation.elapsedString(3599) == "59:59")
        #expect(OutputLocation.elapsedString(3600) == "1:00:00")
        #expect(OutputLocation.elapsedString(36_061) == "10:01:01")
    }

    @Test func outputDirResolvesTilde() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(OutputLocation.resolve("~/Music/Gesprekken", home: home).path == "/Users/test/Music/Gesprekken")
        #expect(OutputLocation.resolve("~", home: home).path == "/Users/test")
        #expect(OutputLocation.resolve("/Users/x/Music/B", home: home).path == "/Users/x/Music/B")
    }

    @Test func convertToM4AWritesStereoAACAndRemovesCaf() throws {
        let caf = dir.appendingPathComponent("2026-11-04_14-30.caf")
        let frames = 48_000 * 2
        var format = FileWriter.floatFormat(rate: 48_000, channels: 2)
        var ref: ExtAudioFileRef?
        #expect(ExtAudioFileCreateWithURL(caf as CFURL, kAudioFileCAFType, &format, nil,
                                          AudioFileFlags.eraseFile.rawValue, &ref) == noErr)
        var samples = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames { samples[2 * i] = 0.3 * sin(Float(i) * 0.05) } // left only
        samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            #expect(ExtAudioFileWrite(ref!, UInt32(frames), &list) == noErr)
        }
        ExtAudioFileDispose(ref!)

        let m4a = try AudioExport.convertToM4A(caf)
        #expect(m4a.lastPathComponent == "2026-11-04_14-30.m4a")
        #expect(!FileManager.default.fileExists(atPath: caf.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.contains("converting") } == nil)

        var inRef: ExtAudioFileRef?
        #expect(ExtAudioFileOpenURL(m4a as CFURL, &inRef) == noErr)
        defer { ExtAudioFileDispose(inRef!) }
        var fileFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(inRef!, kExtAudioFileProperty_FileDataFormat, &size, &fileFormat)
        #expect(fileFormat.mFormatID == kAudioFormatMPEG4AAC)
        #expect(fileFormat.mChannelsPerFrame == 2)
        #expect(fileFormat.mSampleRate == 48_000)
        var length: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(inRef!, kExtAudioFileProperty_FileLengthFrames, &size, &length)
        #expect(abs(Double(length) - Double(frames)) <= 2_048)
    }

    @Test func unfinishedRecordingsAreLeftoverCafsOnly() {
        for name in ["2026-11-04_14-30.caf", "2026-11-04_09-00.caf", "2026-11-04_10-00.m4a",
                     "2026-11-04_11-00.converting.m4a", "notes.txt"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        // A recording folder (since M7) counts too.
        let folder = dir.appendingPathComponent("2026-11-05_08-00")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("2026-11-05_08-00.caf").path, contents: Data())
        #expect(OutputLocation.unfinishedRecordings(in: dir).map(\.lastPathComponent)
                == ["2026-11-04_09-00.caf", "2026-11-04_14-30.caf", "2026-11-05_08-00.caf"])
        #expect(OutputLocation.unfinishedRecordings(in: dir.appendingPathComponent("missing")) == [])
    }

    /// Kies opname: by recording date, not folder name: own recordings by the date in
    /// their file name (also in a renamed folder), imports by their audio; only transcripts (`.json`
    /// with an `.md`), at most `limit`.
    @Test func recentTranscriptsByRecordingDate() throws {
        let fm = FileManager.default
        func make(_ path: String, created: Date? = nil) throws {
            let url = dir.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("{}".utf8))
            if let created { try fm.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
        }
        func transcript(_ path: String) throws {
            try make(path + ".json")
            try make(path + ".md")
        }
        try transcript("Zeta/2026-11-03_09-00")              // renamed folder, recorded 3 Nov
        try transcript("2026-11-05_16-02/2026-11-05_16-02")   // recorded 5 Nov
        try transcript("Aap/Memo")                            // imported memo recorded 4 Nov
        try make("Aap/Memo.m4a", created: date(2026, 11, 4, 12, 0))
        try transcript("2026-10-01_08-00")                    // older recording directly in the folder
        try make("selftest/last.json")                        // no transcript
        try transcript("selftest/2026-11-06_10-00")           // selftest output, not a recording
        try make("2026-11-05_16-02/2026-11-05_16-02 samenvatting Vergadering.md")
        #expect(OutputLocation.recentTranscripts(in: dir, limit: 10).map(\.lastPathComponent)
                == ["2026-11-05_16-02.json", "Memo.json", "2026-11-03_09-00.json", "2026-10-01_08-00.json"])
        #expect(OutputLocation.recentTranscripts(in: dir, limit: 2).count == 2)
        #expect(OutputLocation.recentTranscripts(in: dir.appendingPathComponent("missing"), limit: 8) == [])
    }

    /// Menu bar clock: red while recording, orange while dictating, blinking in the
    /// dictation's last 30 seconds; nothing when idle.
    @MainActor @Test func menuBarClock() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(BandjeApp.clock(recording: nil, dictating: nil, now: start) == nil)
        let rec = BandjeApp.clock(recording: start, dictating: nil, now: start.addingTimeInterval(754))
        #expect(rec?.0 == "12:34" && rec?.1 == .systemRed)
        #expect(BandjeApp.clock(recording: start, dictating: nil, now: start.addingTimeInterval(3723))?.0 == "1:02:03")
        let dict = BandjeApp.clock(recording: start, dictating: start.addingTimeInterval(100), now: start.addingTimeInterval(112))
        #expect(dict?.0 == "00:12" && dict?.1 == .systemOrange)
        let late = start.addingTimeInterval(100)
        let colors = [0.0, 0.5].map { BandjeApp.clock(recording: nil, dictating: late, now: late.addingTimeInterval(280 + $0))?.1 }
        #expect(colors.contains(.clear) && colors.contains(.systemOrange))
        let early = [0.0, 0.5].map { BandjeApp.clock(recording: nil, dictating: late, now: late.addingTimeInterval(200 + $0))?.1 }
        #expect(early == [.systemOrange, .systemOrange])
    }

    @MainActor @Test func dictationEndsWithASpace() {
        #expect(BandjeApp.withTrailingSpace("Klopt dit.") == "Klopt dit. ")
        #expect(BandjeApp.withTrailingSpace("al een spatie ") == "al een spatie ")
        #expect(BandjeApp.withTrailingSpace("regel\n") == "regel\n")
        #expect(BandjeApp.withTrailingSpace("") == "")
    }

    @Test func syncedFolders() {
        let home = OutputLocation.realHome
        #expect(OutputLocation.isSynced(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Bandje")))
        #expect(OutputLocation.isSynced(home.appendingPathComponent("Library/CloudStorage/Dropbox/Bandje")))
        #expect(!OutputLocation.isSynced(home.appendingPathComponent("Music/Bandje")))
        #expect(!OutputLocation.isSynced(dir))
    }

    @Test func languageNamesAreInTheLanguageItself() {
        #expect(AppLanguage.codes.count == 10)
        #expect(AppLanguage.name("nl") == "Nederlands")
        #expect(AppLanguage.name("de") == "Deutsch")
        #expect(AppLanguage.name("uk") == "Українська")
    }

    @Test func freeBytesIsKnownForTempDir() {
        #expect((OutputLocation.freeBytes(at: dir) ?? 0) > 0)
        // A recording's own folder does not exist yet when the recording starts.
        let notYet = dir.appendingPathComponent("2026-11-06_08-17_2", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: notYet.path))
        #expect((OutputLocation.freeBytes(at: notYet) ?? 0) > 0)
    }

    /// After a microphone switch the capture may run at another rate; the file stays 48 kHz
    /// and its length keeps matching the duration of both parts.
    @Test func writerSwitchesInputRate() throws {
        let caf = dir.appendingPathComponent("rate.caf")
        let ring = RingBuffer(capacity: 48_000 * 2 * 4)
        let writer = try FileWriter(url: caf, channels: 2, inputSampleRate: 48_000, ring: ring)
        writer.start()
        func feed(frames: Int) {
            var block = [Float](repeating: 0.1, count: 1_000 * 2)
            var left = frames
            while left > 0 {
                let n = min(left, 1_000)
                while !block.withUnsafeMutableBufferPointer({ ring.write($0.baseAddress!, count: n * 2) }) {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                left -= n
            }
        }
        feed(frames: 48_000)      // 1 s at 48 kHz (built-in mic)
        writer.setInputSampleRate(24_000)
        feed(frames: 24_000)      // 1 s at 24 kHz (AirPods)
        writer.setInputSampleRate(16_000)
        feed(frames: 16_000)      // 1 s at 16 kHz
        writer.setInputSampleRate(48_000)
        feed(frames: 48_000)      // 1 s at 48 kHz again
        writer.finish()
        #expect(writer.writeError == noErr)

        var ref: ExtAudioFileRef?
        #expect(ExtAudioFileOpenURL(caf as CFURL, &ref) == noErr)
        defer { ExtAudioFileDispose(ref!) }
        var length: Int64 = 0
        var size = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(ref!, kExtAudioFileProperty_FileLengthFrames, &size, &length)
        #expect(abs(Double(length) - 192_000) <= 1_000)
        #expect(abs(Double(writer.framesWritten) - Double(length)) <= 1)
    }

    /// Starting at a non-48 kHz rate (recording started with AirPods as microphone).
    @Test func writerConvertsFromStartRate() throws {
        let caf = dir.appendingPathComponent("start16k.caf")
        let ring = RingBuffer(capacity: 16_000 * 2 * 2)
        let writer = try FileWriter(url: caf, channels: 2, inputSampleRate: 16_000, ring: ring)
        var block = [Float](repeating: 0.25, count: 16_000 * 2)
        #expect(block.withUnsafeMutableBufferPointer { ring.write($0.baseAddress!, count: $0.count) })
        writer.start()
        writer.finish()
        #expect(writer.writeError == noErr)
        #expect(abs(Double(writer.framesWritten) - 48_000) <= 500)
    }

    @Test func convertFailureKeepsCaf() {
        let caf = dir.appendingPathComponent("broken.caf")
        FileManager.default.createFile(atPath: caf.path, contents: Data("not audio".utf8))
        #expect(throws: (any Error).self) { try AudioExport.convertToM4A(caf) }
        #expect(FileManager.default.fileExists(atPath: caf.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("broken.m4a").path))
    }
}
