// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
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

    // MARK: Player

    @Test func seekClamps() {
        #expect(Player.clamp(-3, duration: 10) == 0)
        #expect(Player.clamp(12, duration: 10) == 10)
        #expect(Player.clamp(4, duration: 10) == 4)
    }

    @MainActor @Test func playerPlaysSeeksAndFillsNowPlaying() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeRecording("Tone", seconds: 30, in: dir)
        let recording = try #require(Storage.scan(dir).first)

        let player = Player()
        player.volume = 0
        player.load(recording)
        #expect(abs(player.duration - 30) < 0.1)
        player.seek(to: 15)
        player.setRate(1.5)
        var info = try #require(player.nowPlayingInfo)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Tone")
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 15)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

        player.play()
        #expect(player.isPlaying)
        try await Task.sleep(for: .milliseconds(800))
        #expect(player.currentTime > 15.3)
        info = try #require(player.nowPlayingInfo)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)

        player.skip(-Player.skipInterval)
        #expect(player.currentTime < 2)
        player.skip(100)
        #expect(player.currentTime == player.duration)
        player.pause()
        #expect(!player.isPlaying)
        player.unload()
        #expect(player.recording == nil)
        #expect(player.nowPlayingInfo == nil)
    }
}
