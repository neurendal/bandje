// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BandjeKit
import Foundation
import MediaPlayer
import Testing
@testable import Bandje

@Suite(.serialized)
struct LibraryTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A finished recording folder `<dir>/<title>/<title>.m4a` with `seconds` of tone.
    @discardableResult
    private func makeRecording(_ title: String, seconds: Double = 1, in dir: URL, date: Date = Date()) throws -> URL {
        let caf = try Storage.newRecording(title: title, date: date, in: dir)
        let writer = try CAFWriter(url: caf)
        let rate = CAFWriter.sampleRate
        writer.append((0..<Int(seconds * rate)).map { Float(0.2 * sin(2 * Double.pi * 330 * Double($0) / rate)) }, rate: rate)
        writer.finish()
        _ = try AudioExport.convertToM4A(caf)
        let folder = caf.deletingLastPathComponent()
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.recording = nil
        meta.markers = [0.5]
        try meta.write(to: folder)
        return folder
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: One spelling per folder

    /// The folder the recorder returns and the folder a library scan finds must be equal URLs,
    /// also when one path goes through a symlink (`/var` vs `/private/var` on a device; `/tmp` vs
    /// `/private/tmp` on the Mac that runs the simulator). Otherwise a new recording does not open
    /// and is not transcribed automatically.
    @Test func scanAndRecorderSpellTheSameFolderTheSame() throws {
        let name = "bandje-canon-\(UUID().uuidString)"
        let viaSymlink = URL(filePath: "/tmp/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: viaSymlink, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: viaSymlink) }
        let real = URL(filePath: "/private/tmp/\(name)", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: real.path), "this Mac has no /tmp → /private/tmp link")
        #expect(viaSymlink != real)
        #expect(Storage.canonical(viaSymlink) == Storage.canonical(real))
        #expect(Storage.canonical(URL(filePath: "/tmp/\(name)")) == Storage.canonical(real))  // no trailing slash
        // A scan of the parent spells it the same way.
        let scanned = Storage.recordingFolders(in: URL(filePath: "/private/tmp")).filter { $0.lastPathComponent == name }
        #expect(scanned == [Storage.canonical(viaSymlink)])
    }

    // MARK: Rename

    @Test func renameMovesFolderAndAllFilesWithTheOldName() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try makeRecording("Talk", in: dir)
        // Transcript and summary as they will exist after M5/M6, plus a file with another name.
        try Data("{}".utf8).write(to: folder.appending(path: "Talk.json"))
        try Data("# s".utf8).write(to: folder.appending(path: "Talk samenvatting.md"))
        try Data("x".utf8).write(to: folder.appending(path: "notes.txt"))
        try Data("x".utf8).write(to: folder.appending(path: "Talking points.txt"))

        let renamed = try Storage.rename(folder, to: "Meeting: budget/2027")

        #expect(renamed.lastPathComponent == "Meeting. budget-2027")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try files(in: renamed) == [".bandje.json", "Meeting. budget-2027 samenvatting.md",
                                           "Meeting. budget-2027.json", "Meeting. budget-2027.m4a", "Talking points.txt", "notes.txt"])
        let scanned = Storage.scan(dir)
        #expect(scanned.map(\.title) == ["Meeting. budget-2027"])
        #expect(scanned.first?.markers == [0.5])
        #expect(scanned.first?.audio?.lastPathComponent == "Meeting. budget-2027.m4a")
    }

    @Test func renameToTakenNameGetsSuffixAndCaseOnlyRenameWorks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeRecording("A", in: dir)
        let b = try makeRecording("B", in: dir)
        let renamed = try Storage.rename(b, to: "A")
        #expect(renamed.lastPathComponent == "A 2")
        #expect(try files(in: renamed).contains("A 2.m4a"))

        let lower = try Storage.rename(renamed, to: "a 2")
        #expect(lower.lastPathComponent == "a 2")
        #expect(try files(in: lower).contains("a 2.m4a"))
        #expect(Set(Storage.scan(dir).map(\.title)) == ["A", "a 2"])

        // Same name: nothing happens.
        #expect(try Storage.rename(lower, to: "a 2") == lower)
    }

    // MARK: Delete

    @Test func iCloudFoldersAndTemplates() throws {
        let dir = try tempDir()
        for name in ["Overleg", "Templates", "templates 2"] {
            try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: true)
        }
        // The Mac's summary templates in iCloud are not a recording.
        #expect(Storage.recordingFolders(in: dir).map(\.lastPathComponent).sorted() == ["Overleg", "templates 2"])
        // Not syncing: only this iPhone, and publish leaves a folder where it is.
        Storage.setCloud(nil)
        #expect(Storage.libraryFolders == [Storage.documents])
        let folder = dir.appending(path: "Overleg")
        #expect(Storage.publish(folder) == folder)
        // Syncing: the folder moves to the cloud folder; a name that is taken there gets " 2".
        let cloud = try tempDir()
        try FileManager.default.createDirectory(at: cloud.appending(path: "Overleg"), withIntermediateDirectories: true)
        Storage.setCloud(cloud)
        defer { Storage.setCloud(nil) }
        #expect(Storage.libraryFolders == [Storage.documents, cloud])
        let moved = Storage.publish(folder)
        #expect(moved.lastPathComponent == "Overleg 2")
        #expect(moved.deletingLastPathComponent().standardizedFileURL == cloud.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        // Already in the cloud folder: nothing happens.
        #expect(Storage.publish(moved) == moved)
    }

    @Test func deleteRemovesTheFolder() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = try makeRecording("Keep", in: dir)
        let gone = try makeRecording("Gone", in: dir)
        try Storage.delete(gone)
        #expect(!FileManager.default.fileExists(atPath: gone.path))
        #expect(Storage.scan(dir).map(\.folder.lastPathComponent) == [keep.lastPathComponent])
    }

    // MARK: Scan (Files app changes)

    @Test func scanSortsNewestFirstAndSkipsReservedAndNonAudio() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeRecording("Old", in: dir, date: Date(timeIntervalSince1970: 1_700_000_000))
        try makeRecording("New", in: dir, date: Date(timeIntervalSince1970: 1_800_000_000))
        // A folder the user made in Files without audio, and the selftest folder.
        try FileManager.default.createDirectory(at: dir.appending(path: "Photos"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "selftest"), withIntermediateDirectories: true)
        let scanned = Storage.scan(dir)
        #expect(scanned.map(\.title) == ["New", "Old"])
        #expect(abs(scanned[0].duration - 1) < 0.05)
    }

    @Test func folderAddedInFilesWithoutSidecarIsARecording() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeRecording("Source", in: dir)
        let added = dir.appending(path: "Interview")
        try FileManager.default.createDirectory(at: added, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appending(path: "Source.m4a"), to: added.appending(path: "whatever.m4a"))
        let scanned = Storage.scan(dir).first { $0.title == "Interview" }
        #expect(scanned?.audio?.lastPathComponent == "whatever.m4a")
        #expect(scanned?.markers == [])
    }

    @Test func looseAudioFileGetsItsOwnFolder() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeRecording("Source", in: dir)
        try FileManager.default.copyItem(at: source.appending(path: "Source.m4a"), to: dir.appending(path: "Voice memo.m4a"))
        try Data("x".utf8).write(to: dir.appending(path: "readme.txt"))

        let adopted = Storage.adoptLooseFiles(in: dir)

        #expect(adopted.map(\.lastPathComponent) == ["Voice memo"])
        #expect(try files(in: dir.appending(path: "Voice memo")) == [".bandje.json", "Voice memo.m4a"])
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "readme.txt").path))
        #expect(Set(Storage.scan(dir).map(\.title)) == ["Source", "Voice memo"])
    }

    @Test func emptyUnfinishedRecordingIsRemovedNotRecovered() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Empty", date: Date(), in: dir)
        try CAFWriter(url: caf).finish()
        #expect(Storage.unfinished(in: dir) == [caf])
        #expect(Storage.recoverUnfinished(in: dir).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: caf.deletingLastPathComponent().path))
    }

    @Test func emptyUnfinishedRecordingWithUserFilesStays() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Empty", date: Date(), in: dir)
        try CAFWriter(url: caf).finish()
        try Data("x".utf8).write(to: caf.deletingLastPathComponent().appending(path: "mine.txt"))
        Storage.recoverUnfinished(in: dir)
        #expect(FileManager.default.fileExists(atPath: caf.deletingLastPathComponent().appending(path: "mine.txt").path))
    }

    // MARK: The length in `.bandje.json` (specs/icloud-sync.md)

    /// The length: the audio's own when it is here, else `.bandje.json`'s, else the transcript's, else 0.
    @Test func durationReadOrder() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try makeRecording("Lengte", seconds: 3, in: dir)
        let audio = try #require(Storage.audioFile(in: folder))
        try Data(#"{"duration": 61, "segments": [], "title": "Lengte"}"#.utf8).write(to: folder.appending(path: "Lengte.json"))
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.duration = 42.5
        #expect(abs(Storage.duration(audio: audio, local: true, meta: meta, folder: folder) - 3) < 0.05)
        // Audio not here (still in iCloud): the hint, then the transcript, then 0.
        #expect(Storage.duration(audio: audio, local: false, meta: meta, folder: folder) == 42.5)
        meta.duration = nil
        #expect(Storage.duration(audio: audio, local: false, meta: meta, folder: folder) == 61)
        #expect(Storage.duration(audio: audio, local: false, meta: nil, folder: dir) == 0)
        // Local but unreadable: not 0 when something else knows.
        let broken = folder.appending(path: "kapot.m4a")
        try Data([0]).write(to: broken)
        #expect(Storage.duration(audio: broken, local: true, meta: nil, folder: folder) == 61)
    }

    /// Positions stay under the same `RecordingID`: the stored length (0.1 s, rounded down) rounds to
    /// the same whole second as the audio's own length, also at x.45 and x.5.
    @Test func storedDurationRoundsLikeTheAudio() throws {
        for seconds in [312.46, 312.45, 312.5, 312.54, 312.99, 0.96, 3.0, 3599.95, 7.049999999, 12.4999999999] {
            let stored = try #require(RecordingMeta.storedDuration(seconds))
            #expect(Int(stored.rounded()) == Int(seconds.rounded()), "\(seconds) → \(stored)")
            #expect(stored <= seconds && seconds - stored < 0.1 + 1e-9)
            #expect(RecordingID(created: Date(timeIntervalSince1970: 9), duration: stored)
                    == RecordingID(created: Date(timeIntervalSince1970: 9), duration: seconds))
        }
        #expect(RecordingMeta.storedDuration(0) == nil)
        #expect(RecordingMeta.storedDuration(0.04) == nil)
        #expect(RecordingMeta.storedDuration(.nan) == nil)
    }

    /// `duration` is written as 312.4 (not 312.39999999999998), like the markers, and keys this
    /// version doesn't know (a newer iPhone, the Mac) stay when the file is rewritten.
    @Test func durationIsWrittenWithOneDecimalAndOtherKeysStay() throws {
        let folder = try tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"created": "2026-11-09T10:00:00Z", "markers": [1.5], "future": {"a": 1}, "color": "blue"}"#.utf8)
            .write(to: RecordingMeta.url(in: folder))
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.setDuration(312.46)
        meta.markers = [312.4, 0.1]
        meta.color = nil
        try meta.write(to: folder)
        let text = try String(contentsOf: RecordingMeta.url(in: folder), encoding: .utf8)
        #expect(text.contains(#""duration" : 312.4"#))
        #expect(!text.contains("312.39999") && !text.contains("0.10000"))
        #expect(text.contains(#""future""#))
        #expect(!text.contains("color"))  // ours, nil now: removed
        let back = try #require(RecordingMeta.read(from: folder))
        #expect(back.duration == 312.4 && back.markers == [312.4, 0.1])
        #expect(back.created == ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z"))
        // Something odd in it never makes the file unreadable.
        try Data(#"{"created": "2026-11-09T10:00:00Z", "markers": [], "duration": "lang"}"#.utf8).write(to: RecordingMeta.url(in: folder))
        #expect(RecordingMeta.read(from: folder)?.duration == nil)
    }

    /// Older recordings get the length filled in when their audio is here: only that key changes,
    /// never without `.bandje.json`, never over a length that is there.
    @Test func backfillWritesOnlyTheLength() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try makeRecording("Oud", seconds: 2, in: dir)
        // As written before this version: no duration, plus a key from elsewhere.
        try Data(#"{"created": "2026-11-09T10:00:00Z", "markers": [0.5], "future": true}"#.utf8).write(to: RecordingMeta.url(in: folder))
        let bare = try makeRecording("Zonder", seconds: 1, in: dir)
        try FileManager.default.removeItem(at: RecordingMeta.url(in: bare))
        #expect(Storage.backfillDurations(Storage.scan(dir)).map(\.lastPathComponent) == ["Oud"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: RecordingMeta.url(in: folder))) as? [String: Any])
        #expect((object["duration"] as? Double).map { abs($0 - 2) < 0.05 } == true)
        #expect(object["future"] as? Bool == true && object["markers"] as? [Double] == [0.5])
        #expect(!FileManager.default.fileExists(atPath: RecordingMeta.url(in: bare).path))
        #expect(Storage.backfillDurations(Storage.scan(dir)).isEmpty)  // once
        // Not here (still in iCloud): nothing.
        var remote = try #require(Storage.scan(dir).first { $0.title == "Zonder" })
        remote.audioIsLocal = false
        #expect(Storage.backfillDurations([remote]).isEmpty)
    }

    /// Crash recovery and imports write the length.
    @Test func recoveryAndImportWriteTheLength() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Crash", date: Date(), in: dir)
        let writer = try CAFWriter(url: caf)
        writer.append([Float](repeating: 0.1, count: Int(2 * CAFWriter.sampleRate)), rate: CAFWriter.sampleRate)
        writer.finish()
        #expect(Storage.recoverUnfinished(in: dir) == [caf.deletingLastPathComponent()])
        #expect(RecordingMeta.read(from: caf.deletingLastPathComponent())?.duration.map { abs($0 - 2) < 0.05 } == true)

        let source = try tempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let loose = source.appending(path: "Memo.m4a")
        try FileManager.default.copyItem(at: try #require(Storage.audioFile(in: caf.deletingLastPathComponent())), to: loose)
        let imported = try await Importer.importFile(loose, into: dir)
        #expect(RecordingMeta.read(from: imported)?.duration.map { abs($0 - 2) < 0.05 } == true)
    }

    // MARK: Player

    @MainActor @Test func playerPlaysSeeksAndFillsNowPlaying() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeRecording("Tone", seconds: 30, in: dir)
        let recording = try #require(Storage.scan(dir).first)
        let engine = AVAudioPlayerEngine()
        engine.volume = 0
        let player = PlayerModel(engine: engine, store: PlaybackPositionStore(defaults: UserDefaults(suiteName: "bandje-tests-\(UUID().uuidString)")!))

        let item = try #require(recording.playable)
        player.cue(item, at: 15)
        player.rate = 1.5
        var info = try #require(NowPlayingController.info(for: player, artist: "Band·je"))
        #expect(info[MPMediaItemPropertyTitle] as? String == "Tone")
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 15)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

        await player.togglePlayPause().value
        #expect(player.isPlaying)
        try await Task.sleep(for: .milliseconds(800))
        #expect(player.currentTime > 15.3)
        info = try #require(NowPlayingController.info(for: player, artist: "Band·je"))
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)

        player.skip(by: -PlayerModel.skipInterval)
        #expect(player.currentTime < 2)
        player.skip(by: 100)
        #expect(abs(player.currentTime - player.duration) < 0.01)
        player.pause(reason: .user)
        #expect(!player.isPlaying)
        player.stop()
        #expect(player.current == nil)
        #expect(NowPlayingController.info(for: player, artist: "Band·je") == nil)
    }

    /// P1 and P3 with the app's player: leaving the recording stops it and keeps its position;
    /// back in it, it resumes there. A rename keeps it playing.
    @MainActor @Test func leavingStopsAndKeepsThePosition() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeRecording("Leave", seconds: 30, in: dir)
        let recording = try #require(Storage.scan(dir).first)
        Playback.engine.volume = 0
        defer { Playback.removed(recording) }

        Playback.seek(recording, to: 12)  // the position bar before playing: no sound yet
        #expect(Playback.isCurrent(recording.folder))
        #expect(!Playback.player.isPlaying)
        Playback.left(showing: recording.folder)  // still on screen
        #expect(Playback.player.current != nil)

        Playback.left(showing: nil)  // back to the list
        #expect(Playback.player.current == nil)
        #expect(Playback.player.savedPosition(for: recording.playerID) == 12)

        Playback.skip(recording, by: 15)  // reopened: ±15 from where it was
        #expect(Playback.player.currentTime == 27)
        Playback.left(showing: dir.appending(path: "Other"))  // another recording
        #expect(Playback.player.current == nil)
        #expect(Playback.player.savedPosition(for: recording.playerID) == 27)
    }
}
