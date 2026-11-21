import AppKit
import AVFoundation
import BandjeKit
import Foundation
import PDFKit
import Testing
@testable import Bandje

/// The Mac window's library (ported from the iPhone's LibraryTests).
final class LibraryTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    private func recording(_ title: String, date: Date, transcript: String? = nil) throws -> URL {
        let folder = dir.appendingPathComponent(title)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingMeta(created: date).write(to: folder)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(title).m4a").path, contents: Data([0]))
        if let transcript {
            var t = Transcript(title: title, duration: 61, mode: "sprekers", vozVersion: "v", whoVersion: nil,
                               segments: TranscriptWriter.segments([TimedWord(text: transcript, start: 0, end: 1)], speaker: "Ik", channel: nil))
            t.audioFile = "\(title).m4a"
            try TranscriptWriter.write(t, for: folder.appendingPathComponent("\(title).m4a"))
            try Data("# s\n\n---\n\nsamenvatting".utf8).write(to: folder.appendingPathComponent("\(title) samenvatting Vergadering.md"))
        }
        return folder
    }

    @Test func scanFindsRecordingsNewestFirstWithTranscriptAndLength() throws {
        _ = try recording("Oud", date: Date(timeIntervalSince1970: 1_000))
        _ = try recording("Nieuw", date: Date(timeIntervalSince1970: 2_000), transcript: "hallo daar")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Templates"), withIntermediateDirectories: true)
        let found = Library.scan(dir)
        #expect(found.map(\.title) == ["Nieuw", "Oud"])
        #expect(found[0].transcript?.lastPathComponent == "Nieuw.json")
        #expect(found[0].duration == 61)          // from the transcript, without opening the audio
        #expect(found[1].transcript == nil)
    }

    /// The cassette colour comes from `.bandje.json` (shared with the iPhone): unknown or absent = red;
    /// choosing a colour writes it, red removes the key, and the date stays.
    @Test func cassetteColourIsReadAndWritten() async throws {
        let folder = try recording("Kleur", date: Date(timeIntervalSince1970: 3_000))
        #expect(TapeColor("purple") == .purple)
        #expect(TapeColor("magenta") == .red)
        #expect(TapeColor(nil) == .red)
        #expect(Library.scan(dir).first?.color == .red)
        try Library.setColor(.green, in: folder)
        #expect(RecordingMeta.read(from: folder)?.color == "green")
        #expect(RecordingMeta.read(from: folder)?.created == Date(timeIntervalSince1970: 3_000))
        #expect(Library.scan(dir).first?.color == .green)
        try Library.setColor(.red, in: folder)
        #expect(RecordingMeta.read(from: folder)?.color == nil)
    }

    /// The flags set while recording on the iPhone show on the Mac's position bar.
    @Test func markersComeFromTheMeta() throws {
        let folder = try recording("Vlag", date: Date(timeIntervalSince1970: 4_000))
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.markers = [12.5, 40]
        try meta.write(to: folder)
        #expect(Library.scan(dir).first?.markers == [12.5, 40])
    }

    /// The same speeds as on the iPhone (specs/player.md 5.3).
    @Test func playbackSpeeds() {
        #expect(PlayerModel.rates == [0.5, 0.75, 1, 1.25, 1.5, 2])
        #expect(PlayerModel.skipInterval == 15)
    }

    /// specs/player.md 3.3: positions are kept under `created` plus the length, so a rename (here,
    /// in Finder or on the iPhone) keeps them.
    @Test func playerIDSurvivesRename() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000.4)
        let folder = try recording("Overleg", date: created, transcript: "hallo")
        let before = try #require(Library.scan(dir).first?.playable)
        #expect(before.id == RecordingID(created: created, duration: 61))
        #expect(before.title == "Overleg")
        #expect(before.url.lastPathComponent == "Overleg.m4a")
        _ = try Library.renameFolder(folder, to: "Gesprek met Jan")
        let after = try #require(Library.scan(dir).first?.playable)
        #expect(after.id == before.id)
        #expect(after.title == "Gesprek met Jan")
        #expect(after.url.lastPathComponent == "Gesprek met Jan.m4a")
    }

    /// A transcript without its audio has nothing to play.
    @Test func noAudioNothingToPlay() {
        let r = Recording(folder: dir.appendingPathComponent("x"), audio: nil, date: Date(), duration: 10)
        #expect(r.playable == nil)
    }

    /// Space plays and pauses, ⌘← and ⌘→ skip (specs/player.md 5.1); other combinations pass through.
    @Test func playerKeys() {
        #expect(PlayerKey(keyCode: 49, modifiers: []) == .playPause)
        #expect(PlayerKey(keyCode: 123, modifiers: [.command, .numericPad, .function]) == .back)
        #expect(PlayerKey(keyCode: 124, modifiers: [.command, .numericPad, .function]) == .forward)
        #expect(PlayerKey(keyCode: 49, modifiers: .command) == nil)
        #expect(PlayerKey(keyCode: 123, modifiers: [.numericPad, .function]) == nil)
        #expect(PlayerKey(keyCode: 124, modifiers: [.command, .shift]) == nil)
    }

    @Test func daysGroupTodayYesterdayAndDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!
        func r(_ d: Int, _ h: Int) -> Recording {
            Recording(folder: dir.appendingPathComponent("\(d)-\(h)"), audio: nil,
                      date: cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))!, duration: 0)
        }
        let days = Library.days([r(6, 14), r(6, 9), r(5, 20), r(1, 10)], now: now, calendar: cal)
        #expect(days.map(\.recordings.count) == [2, 1, 1])
        #expect(days[0].title == Library.dayTitle(now, now: now, calendar: cal))
        #expect(days[0].title != days[1].title && days[1].title != days[2].title)
    }

    @Test func searchMatchesTitleAndTranscriptWords() async throws {
        _ = try recording("Overleg Jan", date: Date(timeIntervalSince1970: 1_000), transcript: "budget voor volgend jaar")
        _ = try recording("Memo", date: Date(timeIntervalSince1970: 2_000))
        let library = await Library(root: { self.dir })
        await library.refresh()
        #expect(await library.search("jan").map(\.title) == ["Overleg Jan"])
        #expect(await library.search("BUDGET").map(\.title) == ["Overleg Jan"])
        #expect(await library.search("").count == 2)
        #expect(await library.preview(for: library.recordings.first { $0.title == "Overleg Jan" }!) == "budget voor volgend jaar")
    }

    @Test func compactAudioIsMonoSpeechQuality() async throws {
        let url = dir.appendingPathComponent("stereo.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960_000)!
            buffer.frameLength = 960_000
            // A call: me (left) silent here, the other side (right) talking. Both must be in the mono mix.
            for i in 0..<960_000 { buffer.floatChannelData![0][i] = 0; buffer.floatChannelData![1][i] = Float(sin(Double(i) * 0.05)) * 0.3 }
            try file.write(from: buffer)
        }
        let data = try await WebExport.compactAudio(url)
        let out = dir.appendingPathComponent("compact.m4a")
        try data.write(to: out)
        let compact = try AVAudioFile(forReading: out)
        #expect(compact.fileFormat.channelCount == 1 && compact.fileFormat.sampleRate == 22_050)
        #expect(abs(Double(compact.length) / 22_050 - 20) < 0.2)                 // the whole 20 s
        #expect(data.count < 110_000)                                            // ~32 kbit/s: 80 kB + header
        let pcm = AVAudioPCMBuffer(pcmFormat: compact.processingFormat, frameCapacity: AVAudioFrameCount(compact.length))!
        try compact.read(into: pcm)
        let samples = UnsafeBufferPointer(start: pcm.floatChannelData![0], count: Int(pcm.frameLength))
        let rms = (samples.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, samples.count))).squareRoot()
        #expect(rms > 0.05)                                                     // the other side is there
    }

    @Test func watcherDoesNotHoldAFilePerRecording() async throws {
        for i in 0..<300 {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Opname \(i)"), withIntermediateDirectories: true)
        }
        func openFiles() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0 }
        let before = openFiles()
        let watcher = await LibraryWatcher()
        await watcher.start(root: dir)
        let during = openFiles()
        await watcher.stop()
        #expect(during - before < 10, "\(during - before) files open for 300 recordings")
    }

    @MainActor @Test func watcherReportsANewRecording() async throws {
        let watcher = LibraryWatcher()
        watcher.start(root: dir)
        defer { watcher.stop() }
        var seen = false
        let token = NotificationCenter.default.addObserver(forName: .bandjeLibraryChanged, object: nil, queue: .main) { _ in seen = true }
        defer { NotificationCenter.default.removeObserver(token) }
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Opname nieuw"), withIntermediateDirectories: true)
        for _ in 0..<40 where !seen { try await Task.sleep(for: .milliseconds(100)) }
        #expect(seen)
    }

    @Test func publishUnderANewNameRenamesTheFilesToo() throws {
        let staging = dir.appendingPathComponent("staging"), cloud = dir.appendingPathComponent("cloud")
        let folder = try recording("Opname 6 nov 14.32", date: Date(), transcript: "hoi")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: staging.appendingPathComponent(folder.lastPathComponent))
        try FileManager.default.createDirectory(at: cloud.appendingPathComponent("Opname 6 nov 14.32"), withIntermediateDirectories: true)
        let ready = try ICloudSync.preparePublish(staging.appendingPathComponent("Opname 6 nov 14.32"), into: cloud)
        #expect(ready.lastPathComponent == "Opname 6 nov 14.32 2")
        let files = try FileManager.default.contentsOfDirectory(atPath: ready.path).filter { !$0.hasSuffix(".html") }.sorted()
        #expect(files.contains("Opname 6 nov 14.32 2.json") && files.contains("Opname 6 nov 14.32 2.m4a"))
        #expect(try TranscriptWriter.read(json: ready.appendingPathComponent("Opname 6 nov 14.32 2.json")).audioFile == "Opname 6 nov 14.32 2.m4a")
    }

    @Test func moveLocalIntoATakenNameRenamesTheFilesToo() throws {
        let staging = dir.appendingPathComponent("staging"), local = dir.appendingPathComponent("local")
        let folder = try recording("Opname 6 nov 14.32", date: Date(), transcript: "hoi")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(folder.lastPathComponent)
        try FileManager.default.moveItem(at: folder, to: staged)
        try FileManager.default.createDirectory(at: local.appendingPathComponent("Opname 6 nov 14.32"), withIntermediateDirectories: true)
        let moved = try ICloudSync.moveLocal(staged, into: local)
        #expect(moved.lastPathComponent == "Opname 6 nov 14.32 2")
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: moved.path)
        #expect(files.contains("Opname 6 nov 14.32 2.m4a") && files.contains("Opname 6 nov 14.32 2.json"))
        #expect(!files.contains { $0.hasPrefix("Opname 6 nov 14.32.") })
        #expect(try TranscriptWriter.read(json: moved.appendingPathComponent("Opname 6 nov 14.32 2.json")).audioFile == "Opname 6 nov 14.32 2.m4a")
    }

    @Test func copyIntoATakenNameRenamesTheFilesToo() async throws {
        let target = dir.appendingPathComponent("local")
        let folder = try recording("Memo", date: Date(), transcript: "hoi")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Memo"), withIntermediateDirectories: true)
        let copied = try await ICloudSync.copyRecording(folder, into: target)
        #expect(copied.lastPathComponent == "Memo 2")
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("Memo 2.json").path))
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent(".bandje.json").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Memo.json").path))   // the source stays
    }

    @Test func renameAndDeleteAreRefusedWhileAJobRuns() async throws {
        let folder = try recording("Opname bezig", date: Date(), transcript: "hoi")
        let library = await Library(root: { self.dir })
        await library.refresh()
        await MainActor.run { library.isBusy = { $0.standardizedFileURL == folder.standardizedFileURL } }
        let r = await library.recordings.first { $0.title == "Opname bezig" }!
        await #expect(throws: (any Error).self) { _ = try await library.rename(r, to: "Nieuw") }
        await #expect(throws: (any Error).self) { try await library.delete(r) }
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: Recordings not in iCloud yet (owner, 2026-11-09)

    /// A finished recording that could not move into iCloud stays in the staging folder and shows in
    /// the library from there; one still being recorded (or not converted yet) does not.
    @Test func stagingRecordingsShowUntilTheyMove() async throws {
        let cloud = dir.appendingPathComponent("cloud"), staging = dir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        func make(_ name: String, in parent: URL, recording: Bool? = nil, caf: Bool = false) throws -> URL {
            let f = parent.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            try RecordingMeta(created: Date(timeIntervalSince1970: Double(name.count) * 1_000), recording: recording).write(to: f)
            FileManager.default.createFile(atPath: f.appendingPathComponent("\(name).\(caf ? "caf" : "m4a")").path, contents: Data([0]))
            return f
        }
        _ = try make("In iCloud", in: cloud)
        let waiting = try make("Wacht op iCloud", in: staging)
        _ = try make("Neemt op", in: staging, recording: true, caf: true)
        #expect(Set(Library.scan(cloud, staging: staging).map(\.title)) == ["In iCloud", "Wacht op iCloud"])
        #expect(Library.scan(cloud).map(\.title) == ["In iCloud"])

        let library = await Library(root: { cloud }, staging: staging)
        await library.refresh()
        // Rename works where it is (delete is the same move to the Trash as for any folder).
        let r = try #require(await library.recordings.first { $0.folder.standardizedFileURL == waiting.standardizedFileURL })
        let renamed = try await library.rename(r, to: "Nieuwe naam")
        #expect(renamed.folder.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: renamed.folder.appendingPathComponent("Nieuwe naam.m4a").path))
        // Moved into iCloud later: shown once, from there.
        try FileManager.default.moveItem(at: renamed.folder, to: cloud.appendingPathComponent("Nieuwe naam"))
        await library.refresh()
        #expect(await library.recordings.map(\.title).sorted() == ["In iCloud", "Nieuwe naam"])
        #expect(await library.recordings.allSatisfy { $0.folder.deletingLastPathComponent().standardizedFileURL == cloud.standardizedFileURL })
    }

    @Test func renameMovesFolderAndEveryFileWithTheName() async throws {
        let folder = try recording("Opname 6 nov 14.32", date: Date(), transcript: "hoi")
        let renamed = try Library.renameFolder(folder, to: "Gesprek met Jan")
        let files = try FileManager.default.contentsOfDirectory(atPath: renamed.path).filter { !$0.hasSuffix(".html") }.sorted()
        #expect(renamed.lastPathComponent == "Gesprek met Jan")
        // The title follows: json, the markdown heading (and so a shared page).
        #expect(try TranscriptWriter.read(json: renamed.appendingPathComponent("Gesprek met Jan.json")).title == "Gesprek met Jan")
        #expect(try String(contentsOf: renamed.appendingPathComponent("Gesprek met Jan.md"), encoding: .utf8).hasPrefix("# Gesprek met Jan\n"))
        #expect(files == [".bandje.json", "Gesprek met Jan samenvatting Vergadering.md", "Gesprek met Jan.json",
                          "Gesprek met Jan.m4a", "Gesprek met Jan.md"])
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        // A name that is taken gets " 2".
        _ = try recording("Memo", date: Date())
        #expect(try Library.renameFolder(renamed, to: "Memo").lastPathComponent == "Memo 2")
    }

    /// A real 3 s AAC `.m4a` in its own folder.
    private func m4a(_ title: String) throws -> URL {
        let folder = dir.appendingPathComponent(title)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(title).m4a")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 144_000)!
        buffer.frameLength = 144_000
        for i in 0..<144_000 { buffer.floatChannelData![0][i] = 0.2 * sin(Float(i) * 0.05) }
        try file.write(from: buffer)
        return url
    }

    private func embeddedCover(_ audio: URL) async throws -> Data? {
        try await AVURLAsset(url: audio).load(.metadata).first { $0.identifier == .iTunesMetadataCoverArt }?.load(.dataValue)
    }

    @MainActor @Test func coverIsEmbeddedOnceAndRemadeForANewTitleOrColour() async throws {
        let audio = try m4a("Planning")
        let folder = audio.deletingLastPathComponent()
        await CoverArt.embed(in: folder, own: false)  // no cover yet: made, also when not our change
        let first = try #require(try await embeddedCover(audio))
        #expect(first.count > 20_000)
        let key = CoverArt.key(title: "Planning", duration: 3, color: .red)
        #expect(RecordingMeta.read(from: folder)?.coverKey == key)
        #expect(CoverArt.existing(in: folder)?.lastPathComponent == ".cover-\(key).jpg")
        #expect(abs(Library.duration(audio: audio, meta: nil, transcript: nil) - 3) < 0.05)  // not re-encoded

        // Unchanged: the file is left alone.
        let modified = try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        await CoverArt.embed(in: folder, own: true)
        #expect(try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)

        // Another colour: a new cover, in the file and next to it (the old one removed).
        try Library.setColor(.green, in: folder)
        await CoverArt.embed(in: folder, own: true)
        let green = try #require(try await embeddedCover(audio))
        #expect(green != first)
        #expect(RecordingMeta.read(from: folder)?.coverKey == CoverArt.key(title: "Planning", duration: 3, color: .green))

        // Renamed: the sticker's title changes, so the cover too.
        let renamed = try Library.renameFolder(folder, to: "Overleg")
        let renamedAudio = try #require(Library.audioFile(in: renamed))
        await CoverArt.embed(in: renamed, own: true)
        #expect(try await embeddedCover(renamedAudio) != green)
        // For a look at the artwork: build/cover-art.jpg.
        try? await embeddedCover(renamedAudio)?.write(to: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../build/cover-art.jpg").standardizedFileURL)
        #expect(RecordingMeta.read(from: renamed)?.coverKey == CoverArt.key(title: "Overleg", duration: 3, color: .green))
        let files = try FileManager.default.contentsOfDirectory(atPath: renamed.path)
        #expect(files.filter { $0.hasPrefix(".cover-") }.count == 1 && !files.contains { $0.hasPrefix(".embedding-") })
    }

    /// Rename and colour at once (here, in the rename sheet, or arriving from the iPhone): the rename
    /// starts a new cover, and the colour lands in `.bandje.json` while that cover is being written
    /// into the audio. Writing the cover's key must not put back the colour it read before.
    @MainActor @Test func coverDoesNotUndoAColourChangedWhileItIsMade() async throws {
        var caught = false
        for attempt in 0..<5 where !caught {
            let audio = try m4a("Race \(attempt)")
            let folder = audio.deletingLastPathComponent()
            let json: [String: Any] = ["created": "2026-11-10T10:00:00Z", "markers": [], "futureKey": "kept"]
            try JSONSerialization.data(withJSONObject: json).write(to: RecordingMeta.url(in: folder))
            let embedding = Task { @MainActor in await CoverArt.embed(in: folder, own: true) }
            // The cover's jpg is written just before the audio is: from then until the key is in
            // `.bandje.json`, the cover is being made. Change the colour in that window (on the main
            // actor, without suspending, so the cover cannot finish in between).
            for _ in 0..<2_000 {
                let started = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasPrefix(".cover-") }
                if started, RecordingMeta.read(from: folder)?.coverKey == nil {
                    try Library.setColor(.blue, in: folder)
                    caught = true
                    break
                }
                if RecordingMeta.read(from: folder)?.coverKey != nil { break }  // missed the window: again
                try await Task.sleep(for: .milliseconds(1))
            }
            await embedding.value
            guard caught else { continue }
            let meta = try #require(RecordingMeta.read(from: folder))
            #expect(meta.color == TapeColor.blue.stored)
            #expect(meta.coverKey == CoverArt.key(title: folder.lastPathComponent, duration: 3, color: .red))
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: RecordingMeta.url(in: folder))) as? [String: Any]
            #expect(raw?["futureKey"] as? String == "kept")
            // The next round makes the blue cover.
            await CoverArt.embed(in: folder, own: true)
            #expect(RecordingMeta.read(from: folder)?.color == TapeColor.blue.stored)
            #expect(RecordingMeta.read(from: folder)?.coverKey == CoverArt.key(title: folder.lastPathComponent, duration: 3, color: .blue))
        }
        #expect(caught, "never changed the colour while the cover was being made")
    }

    /// A rename or colour from the iPhone (owner, 2026-11-10): the iPhone writes that cover. This Mac
    /// leaves the audio and `.bandje.json` alone; when it reacted, its write (of a `.bandje.json` that
    /// may not have the iPhone's colour yet) won in iCloud and the colour flipped back on both.
    @MainActor @Test func coverIsNotRemadeForAChangeFromTheIPhone() async throws {
        let audio = try m4a("Van de iPhone")
        let folder = audio.deletingLastPathComponent()
        await CoverArt.embed(in: folder, own: false)
        let key = CoverArt.key(title: "Van de iPhone", duration: 3, color: .red)
        #expect(RecordingMeta.read(from: folder)?.coverKey == key)

        // The colour arrives in `.bandje.json`, then the folder's new name.
        try RecordingMeta.update(in: folder) { $0["color"] = "green"; return true }
        let renamed = try Library.renameFolder(folder, to: "Hernoemd op de iPhone")
        let renamedAudio = try #require(Library.audioFile(in: renamed))
        let modified = try renamedAudio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let before = try Data(contentsOf: RecordingMeta.url(in: renamed))
        await CoverArt.embed(in: renamed, own: false)
        #expect(try renamedAudio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(try Data(contentsOf: RecordingMeta.url(in: renamed)) == before)
        #expect(RecordingMeta.read(from: renamed)?.color == "green")
    }

    /// The library makes covers for this Mac's own renames and colours, and for recordings without
    /// one; a colour that arrives from the iPhone gets none here.
    @MainActor @Test func libraryMakesCoversOnlyForOwnChanges() async throws {
        let audio = try m4a("Bibliotheek")
        let folder = audio.deletingLastPathComponent()
        let root = folder.deletingLastPathComponent()
        let library = Library(root: { root })
        func waitForKey(_ key: String, in folder: URL) async throws -> Bool {
            for _ in 0..<200 {
                if RecordingMeta.read(from: folder)?.coverKey == key { return true }
                try await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
        await library.refresh()
        #expect(try await waitForKey(CoverArt.key(title: "Bibliotheek", duration: 3, color: .red), in: folder))

        // From the iPhone: a colour. A refresh, and time for a cover round: none.
        try RecordingMeta.update(in: folder) { $0["color"] = "green"; return true }
        let modified = try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        await library.refresh()
        try await Task.sleep(for: .milliseconds(500))
        #expect(try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(RecordingMeta.read(from: folder)?.coverKey == CoverArt.key(title: "Bibliotheek", duration: 3, color: .red))

        // Here: a new name and colour, as the rename sheet does it.
        let recording = try #require(library.recordings.first)
        let renamed = try await library.rename(recording, to: "Eigen naam")
        try await library.setColor(.blue, of: renamed)
        #expect(try await waitForKey(CoverArt.key(title: "Eigen naam", duration: 3, color: .blue), in: renamed.folder))
        #expect(RecordingMeta.read(from: renamed.folder)?.color == "blue")
    }

    // MARK: The length in `.bandje.json` (specs/icloud-sync.md)

    /// The length: the audio's own when it is here, else `.bandje.json`'s, else the transcript's, else 0.
    @Test func durationReadOrder() throws {
        let audio = try m4a("Lengte")  // 3 s
        let folder = audio.deletingLastPathComponent()
        let transcript = folder.appendingPathComponent("Lengte.json")
        try Data(#"{"duration": 61, "segments": []}"#.utf8).write(to: transcript)
        var meta = RecordingMeta(created: Date(timeIntervalSince1970: 5))
        meta.duration = 42.5
        #expect(abs(Library.duration(audio: audio, meta: meta, transcript: transcript) - 3) < 0.05)
        // Audio not here (or not readable): the hint, then the transcript, then 0.
        let missing = folder.appendingPathComponent("weg.m4a")
        #expect(Library.duration(audio: missing, meta: meta, transcript: transcript) == 42.5)
        #expect(Library.duration(audio: nil, meta: meta, transcript: transcript) == 42.5)
        #expect(Library.duration(audio: nil, meta: RecordingMeta(created: Date()), transcript: transcript) == 61)
        #expect(Library.duration(audio: nil, meta: nil, transcript: nil) == 0)
        try meta.write(to: folder)
        try FileManager.default.removeItem(at: audio)
        #expect(Library.scan(dir).first?.duration == 42.5)
    }

    /// Positions stay under the same `RecordingID`: the stored length (0.1 s, rounded down) rounds to
    /// the same whole second as the audio's own length, also at x.45 and x.5.
    @Test func storedDurationRoundsLikeTheAudio() {
        for seconds in [312.46, 312.45, 312.5, 312.54, 312.99, 0.96, 3.0, 3599.95, 7.049999999, 12.4999999999] {
            let stored = try! #require(RecordingMeta.storedDuration(seconds))
            #expect(Int(stored.rounded()) == Int(seconds.rounded()), "\(seconds) → \(stored)")
            #expect(stored <= seconds && seconds - stored < 0.1 + 1e-9)
            #expect(RecordingID(created: Date(timeIntervalSince1970: 9), duration: stored)
                    == RecordingID(created: Date(timeIntervalSince1970: 9), duration: seconds))
        }
        #expect(RecordingMeta.storedDuration(0) == nil)
        #expect(RecordingMeta.storedDuration(0.04) == nil)
        #expect(RecordingMeta.storedDuration(.nan) == nil)
    }

    /// `duration` is written as 312.4 (not 312.39999999999998), like the markers, and every key this
    /// version doesn't know stays.
    @Test func durationIsWrittenWithOneDecimalAndOtherKeysStay() throws {
        let folder = dir.appendingPathComponent("Sleutels")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"created": "2026-11-09T10:00:00Z", "markers": [1.5], "conversionAttempts": 2, "future": {"a": 1}}"#.utf8)
            .write(to: RecordingMeta.url(in: folder))
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.setDuration(312.46)
        meta.markers = [312.4, 0.1]
        try meta.write(to: folder)
        let text = try String(contentsOf: RecordingMeta.url(in: folder), encoding: .utf8)
        #expect(text.contains(#""duration" : 312.4,"#) || text.contains(#""duration" : 312.4\#n"#))
        #expect(!text.contains("312.39999") && !text.contains("0.10000"))
        #expect(text.contains(#""conversionAttempts" : 2"#) && text.contains(#""future""#))
        #expect(RecordingMeta.read(from: folder)?.duration == 312.4)
        #expect(RecordingMeta.read(from: folder)?.markers == [312.4, 0.1])
        // A file without it (or with something odd in it) still reads.
        try Data(#"{"created": "2026-11-09T10:00:00Z", "duration": "lang"}"#.utf8).write(to: RecordingMeta.url(in: folder))
        #expect(RecordingMeta.read(from: folder)?.duration == nil)
    }

    /// Older recordings get the length filled in when their audio is here: only that key changes,
    /// never in a recording in progress, never without `.bandje.json`, never over a length that is there.
    @Test func backfillWritesOnlyTheLength() throws {
        let audio = try m4a("Oud")
        let folder = audio.deletingLastPathComponent()
        try Data(#"{"created": "2026-11-09T10:00:00Z", "markers": [2.5], "color": "green", "future": true}"#.utf8)
            .write(to: RecordingMeta.url(in: folder))
        let busy = try m4a("Bezig")
        try RecordingMeta(created: Date(), recording: true).write(to: busy.deletingLastPathComponent())
        _ = try m4a("Zonder")  // no .bandje.json
        let found = Library.scan(dir)
        #expect(Library.backfillDurations(found).map(\.lastPathComponent) == ["Oud"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: RecordingMeta.url(in: folder))) as? [String: Any])
        #expect((object["duration"] as? Double).map { abs($0 - 3) < 0.05 } == true)
        #expect(object["color"] as? String == "green" && object["future"] as? Bool == true && object["markers"] as? [Double] == [2.5])
        #expect(RecordingMeta.read(from: busy.deletingLastPathComponent())?.duration == nil)
        #expect(!FileManager.default.fileExists(atPath: RecordingMeta.url(in: dir.appendingPathComponent("Zonder")).path))
        #expect(Library.backfillDurations(Library.scan(dir)).isEmpty)  // once
    }

    /// Finishing a recording (stop, crash recovery, quitting while recording) writes its length.
    @Test func finishingWritesTheLength() throws {
        let audio = try m4a("Klaar")
        let folder = audio.deletingLastPathComponent()
        try RecordingMeta(created: Date(timeIntervalSince1970: 7), recording: true).write(to: folder)
        OutputLocation.finishMeta(folder)
        let meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.recording == nil)
        #expect(meta.duration.map { abs($0 - 3) < 0.05 } == true)
    }

    /// The iPhone writes the same key for the same recording, so neither redoes the other's cover
    /// (bandje-ios `CoverArt.key`; change both together).
    @Test func coverKeyMatchesTheIPhone() {
        // FNV-1a of "Planning|3|3" and "Planning|3|green|3", base 36 (the iPhone's formula).
        #expect(CoverArt.key(title: "Planning", duration: 2.6, color: .red) == "cem01iczal30")
        #expect(CoverArt.key(title: "Planning", duration: 3, color: .green) == "2bulfyhwpopan")
    }
}

/// The list rows say how long a recording is in words, never as a clock (the iPhone does the same):
/// "10:30 · 0:54" read as a time span.
@Test func spokenDurationNeverUsesAColon() {
    let nl = Locale(identifier: "nl_NL"), en = Locale(identifier: "en_US")
    #expect(!spokenDuration(54, locale: nl).contains(":"))
    #expect(spokenDuration(54, locale: en).contains("54"))
    #expect(spokenDuration(54, locale: en).contains("sec"))
    #expect(spokenDuration(2 * 60 + 7, locale: en) == "2 min")
    #expect(spokenDuration(21 * 60 + 40, locale: en) == "22 min")
    #expect(spokenDuration(3600 + 2 * 60 + 10, locale: en) == "1 hr, 2 min")
    #expect(spokenDuration(.nan, locale: en).contains("0"))
}

/// The PDF share (as on the iPhone): a real PDF with the title, longer transcripts over several pages.
@Test func transcriptPDF() throws {
    func seg(_ who: String, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: who, channel: nil, words: [TimedWord(text: text, start: start, end: start + 0.5)])
    }
    var t = Transcript(title: "Planning", duration: 20, mode: "sprekers", vozVersion: "v", whoVersion: nil,
                       segments: [seg("Spreker 1", 1, "Goedemorgen"), seg("Spreker 2", 5, "Dag")])
    let pdf = WebExport.pdf(t)
    #expect(pdf.starts(with: Data("%PDF".utf8)))
    let short = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
    #expect(short.numberOfPages == 1)
    t.segments = (0..<400).map { seg($0 % 2 == 0 ? "Spreker 1" : "Spreker 2", Double($0), "Een zin die een paar keer terugkomt in dit lange gesprek.") }
    let long = try #require(CGPDFDocument(CGDataProvider(data: WebExport.pdf(t) as CFData)!))
    #expect(long.numberOfPages > 3)
    // Every page has the footer: made with Band·je, and "n / N".
    let pages = try #require(PDFDocument(data: WebExport.pdf(t)))
    let last = try #require(pages.page(at: pages.pageCount - 1)?.string)
    #expect(last.contains("band.je"))
    #expect(last.contains("\(pages.pageCount) / \(pages.pageCount)"))
    #expect(pages.page(at: 0)?.string?.contains("1 / \(pages.pageCount)") == true)
}

/// Loading the model has no progress of its own: the % is the elapsed time against the last load
/// on this Mac, never 100 before it is done.
@Test func modelLoadPercentIsAnEstimate() {
    #expect(Transcriber.loadPercent(elapsed: 0, expected: 20) == 0)
    #expect(Transcriber.loadPercent(elapsed: 10, expected: 20) == 50)
    #expect(Transcriber.loadPercent(elapsed: 40, expected: 20) == 95)
    #expect(Transcriber.loadPercent(elapsed: 1, expected: 0) == 95)
}

/// Old Mac names ("2026-11-05_14-30") become the iPhone's name for that moment, in this Mac's
/// language and region; other names stay, a taken name gets " 2", and the date is kept.
@Test func legacyNamesBecomeIPhoneNames() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    func folder(_ name: String) throws {
        let f = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: f.appendingPathComponent("\(name).m4a").path, contents: Data([0]))
    }
    try folder("2026-11-05_14-30")
    try folder("Interview")
    let nl = Locale(identifier: "nl_NL")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
    let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14, minute: 30))!
    let wanted = OutputLocation.defaultTitle(for: date, locale: nl)
    try folder(wanted)  // already taken: the old one becomes "<name> 2"
    let renamed = Library.renameLegacyFolders(in: dir, locale: nl, isBusy: { _ in false })
    #expect(renamed == 1)
    let names = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    #expect(names == ["Interview", wanted, wanted + " 2"])
    let moved = dir.appendingPathComponent(wanted + " 2")
    #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent(wanted + " 2.m4a").path))
    #expect(RecordingMeta.read(from: moved)?.created == date)
    #expect(Library.renameLegacyFolders(in: dir, locale: nl, isBusy: { _ in false }) == 0)
}

/// When the window opens at launch: always the first time (also at login); otherwise when started
/// by the user and the setting is on. The welcome (with the permissions)
/// shows the first time, and after an update only when a permission is missing.
@Test func launchOpensTheWindowAndWelcome() {
    typealias L = LaunchPolicy
    // The setting decides (owner): an update no longer opens the window; only the very first launch does.
    #expect(L.showWindow(atLogin: true, firstLaunch: true, setting: false))
    #expect(!L.showWindow(atLogin: false, firstLaunch: false, setting: false))
    #expect(L.showWindow(atLogin: false, firstLaunch: false, setting: true))
    #expect(!L.showWindow(atLogin: true, firstLaunch: false, setting: true))
    #expect(L.showWelcome(firstLaunch: true, updated: false, permissionMissing: false))
    #expect(L.showWelcome(firstLaunch: false, updated: true, permissionMissing: true))
    #expect(!L.showWelcome(firstLaunch: false, updated: true, permissionMissing: false))
    #expect(!L.showWelcome(firstLaunch: false, updated: false, permissionMissing: true))
    // The first time from the start; after an update (a permission missing) straight to Access.
    #expect(L.welcomeStep(firstLaunch: true) == 1)
    #expect(L.welcomeStep(firstLaunch: false) == 2)
    #expect(L.updated(lastBuild: "20261105.2303", build: "20261106.2057"))
    #expect(!L.updated(lastBuild: nil, build: "20261106.2057"))
    #expect(!L.updated(lastBuild: "20261106.2057", build: "20261106.2057"))
}

/// The welcome's Free to Start names only what the App Store confirmed: while it isn't known yet
/// whether this is an existing customer (everything unlocked meanwhile), it never says that
/// Band·je Dictation is unlocked.
@Test func welcomeFreeNamesOnlyKnownPurchases() {
    func free(_ o: Purchases.Override?, unlimited: Bool = false, dictation: Bool = false, existing: Bool?) -> Store.WelcomeFree {
        let k = Store.known(override: o, ownsUnlimited: unlimited, ownsDictation: dictation, existingCustomer: existing)
        return Store.welcomeFree(knowsUnlimited: k.unlimited, knowsDictation: k.dictation)
    }
    #expect(free(nil, existing: nil) == .free)
    #expect(free(nil, existing: false) == .free)
    #expect(free(nil, existing: true) == .unlocked)
    #expect(free(nil, dictation: true, existing: nil) == .dictationOwned)
    #expect(free(nil, unlimited: true, existing: false) == .unlocked)
    #expect(free(.dictation, existing: nil) == .dictationOwned)
    #expect(free(.existing, existing: nil) == .unlocked)
    #expect(free(.used, existing: nil) == .free)
}

/// Closing the window: a message that Band·je keeps running in the menu bar, until the user ticks
/// "Do not show this message again".
@Test func closeNoticeUntilSuppressed() {
    let defaults = UserDefaults(suiteName: "closeNotice-\(UUID().uuidString)")!
    #expect(LaunchPolicy.showsCloseNotice(defaults))
    LaunchPolicy.suppressCloseNotice(defaults)
    #expect(!LaunchPolicy.showsCloseNotice(defaults))
}

/// The open recording looks for its transcript in its folder each time (not in a possibly older copy
/// of the list): a transcript that arrives after the recording, even with no speech, is found.
@Test func transcriptIsFoundInTheFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let folder = dir.appendingPathComponent("Opname 6 nov 22.24")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(Library.transcriptFile(in: folder) == nil)
    let json = folder.appendingPathComponent("Opname 6 nov 22.24.json")
    try Data(#"{"segments":[],"title":"Opname 6 nov 22.24"}"#.utf8).write(to: json)
    #expect(Library.transcriptFile(in: folder)?.lastPathComponent == json.lastPathComponent)
    #expect(try TranscriptWriter.read(json: json).segments.isEmpty)
}

/// A Dock icon (and the app menu with ⌘Q) while the window is on screen or minimized (else it could
/// not come back from the Dock); otherwise only with Always in the Dock.
@Test func dockIconFollowsTheWindow() {
    #expect(LaunchPolicy.dockIcon(windowVisible: true, minimized: false, alwaysInDock: false))
    #expect(LaunchPolicy.dockIcon(windowVisible: false, minimized: true, alwaysInDock: false))
    #expect(!LaunchPolicy.dockIcon(windowVisible: false, minimized: false, alwaysInDock: false))
    #expect(LaunchPolicy.dockIcon(windowVisible: false, minimized: false, alwaysInDock: true))
}

/// Quitting while recording asks first; the answer stops the recording and quits once it is saved.
@Test func quitWhileRecordingAsks() {
    #expect(LaunchPolicy.quit(recording: true, finishing: 0) == .ask)
    #expect(LaunchPolicy.quit(recording: false, finishing: 1) == .waitForSave)
    #expect(LaunchPolicy.quit(recording: false, finishing: 0) == .now)
}
