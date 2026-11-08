// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import Testing
@testable import Bandje

/// Import of the fixtures from `scripts/dev/make-fixtures.sh` (`make test` makes them first).
/// The simulator test host reads them straight from the repo's `build/fixtures`.
@Suite(.serialized)
struct ImportTests {
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/fixtures")

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtures.appending(path: name)
        try #require(FileManager.default.fileExists(atPath: url.path), "missing \(name): run make fixtures")
        return url
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func visible(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Duration of the WAV the fixture was made from.
    private func sourceDuration(_ wav: String) throws -> Double {
        let duration = Storage.duration(of: try fixture(wav))
        try #require(duration > 20)
        return duration
    }

    // MARK: Formats

    @Test(arguments: [
        ("import_nl.m4a", "m4a", "nl_dialogue.wav"),
        ("import_nl.mp3", "mp3", "nl_dialogue.wav"),
        ("import_en.wav", "wav", "en_dialogue.wav"),
        ("import_en.aiff", "aiff", "en_dialogue.wav"),
        ("import_nl.caf", "m4a", "nl_dialogue.wav"),  // .caf is reserved for unfinished recordings
        ("import_en.mp4", "m4a", "en_dialogue.wav"),  // video: audio only, as m4a
        ("import_nl.mov", "m4a", "nl_dialogue.wav"),
    ])
    func importsEachFormat(file: String, keptExtension: String, source: String) async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try fixture(file)
        let expected = try sourceDuration(source)

        let folder = try await Importer.importFile(input, into: dir)

        let title = input.deletingPathExtension().lastPathComponent
        #expect(folder.lastPathComponent == title)
        #expect(visible(folder) == ["\(title).\(keptExtension)"])
        #expect(FileManager.default.fileExists(atPath: input.path), "the original stays where it was")
        let recordings = Storage.scan(dir)
        #expect(recordings.map(\.title) == [title])
        let recording = try #require(recordings.first)
        // mp3 and AAC encoders add a few ms of padding; video export rounds to the video track.
        #expect(abs(recording.duration - expected) < 0.3, "\(file): \(recording.duration) vs \(expected)")
        let player = try AVAudioPlayer(contentsOf: try #require(recording.audio))
        #expect(player.prepareToPlay() && player.duration > 20)
        #expect(RecordingMeta.read(from: folder)?.recording == nil)
    }

    @Test func videoKeepsOnlyTheAudio() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try await Importer.importFile(try fixture("import_en.mp4"), into: dir)
        let audio = try #require(Storage.audioFile(in: folder))
        let asset = AVURLAsset(url: audio)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    @Test func sameFileTwiceGetsASuffix() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try fixture("import_nl.m4a")
        _ = try await Importer.importFile(input, into: dir)
        let second = try await Importer.importFile(input, into: dir)
        #expect(second.lastPathComponent == "import_nl 2")
        #expect(visible(second) == ["import_nl 2.m4a"])
        #expect(Set(Storage.scan(dir).map(\.title)) == ["import_nl", "import_nl 2"])
    }

    @Test func dateComesFromTheFileWhenThereIsNoMetadata() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appending(path: "old.wav")
        try FileManager.default.copyItem(at: try fixture("import_en.wav"), to: input)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: input.path)
        let target = dir.appending(path: "lib")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let folder = try await Importer.importFile(input, into: target)

        let created = try #require(RecordingMeta.read(from: folder)?.created)
        #expect(abs(created.timeIntervalSince(old)) < 1)
    }

    // MARK: Broken files

    @Test(arguments: ["corrupt.m4a", "notes.mp3"])
    func brokenFileGivesAClearErrorAndLeavesNothing(file: String) async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await Importer.importFile(try fixture(file), into: dir)
            Issue.record("\(file) should not import")
        } catch let error as ImportError {
            #expect(error.localizedDescription.contains(file))
        }
        #expect(visible(dir).isEmpty)
        #expect(Storage.scan(dir).isEmpty)
    }

    // MARK: App Group inbox

    @Test func inboxIsImportedAndEmptied() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appending(path: "Inbox"), docs = root.appending(path: "Documents")
        let incoming = inbox.appending(path: ".incoming")
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try fixture("import_nl.m4a"), to: inbox.appending(path: "Voice memo.m4a"))
        try FileManager.default.copyItem(at: try fixture("import_en.mp4"), to: inbox.appending(path: "Clip.mp4"))
        try FileManager.default.copyItem(at: try fixture("corrupt.m4a"), to: inbox.appending(path: "broken.m4a"))
        // Half-written by the extension: not touched.
        try Data("x".utf8).write(to: incoming.appending(path: "partial.m4a"))

        let result = await Importer.processInbox(inbox, into: docs)

        #expect(Set(result.imported.map(\.lastPathComponent)) == ["Voice memo", "Clip"])
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.contains("broken.m4a") == true)
        #expect(visible(inbox).isEmpty, "inbox is empty afterwards")
        #expect(FileManager.default.fileExists(atPath: incoming.appending(path: "partial.m4a").path))
        #expect(Set(Storage.scan(docs).map(\.title)) == ["Voice memo", "Clip"])
        #expect(visible(docs.appending(path: "Clip")) == ["Clip.m4a"])

        // A second pickup finds nothing.
        let again = await Importer.processInbox(inbox, into: docs)
        #expect(again.imported.isEmpty && again.errors.isEmpty)
    }

    @Test func coverIsEmbeddedInTheRecordingOnce() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = dir.appending(path: "import_nl.m4a")
        try FileManager.default.copyItem(at: try fixture("import_nl.m4a"), to: audio)
        let recording = Recording(folder: dir, audio: audio, date: .now, duration: 30, markers: [])
        let before = try await AVURLAsset(url: audio).load(.duration).seconds
        await AudioExport.embedCover(recording)
        let metadata = try await AVURLAsset(url: audio).load(.metadata)
        let data = try await metadata.first { $0.identifier == .iTunesMetadataCoverArt }?.load(.dataValue)
        #expect((data?.count ?? 0) > 20_000)
        // For a look at the artwork: build/cover-art.jpg (the test host can write the repo's build/).
        try data?.write(to: Self.fixtures.deletingLastPathComponent().appending(path: "cover-art.jpg"))
        // Same audio, not re-encoded; the key is noted so it happens once.
        let after = try await AVURLAsset(url: audio).load(.duration).seconds
        #expect(abs(before - after) < 0.05)
        #expect(RecordingMeta.read(from: dir)?.coverKey == CoverArt.key(title: recording.title, duration: 30))
        let modified = try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        await AudioExport.embedCover(recording)
        #expect(try audio.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.filter { $0.hasPrefix(".cover-") }.count == 1 && !files.contains { $0.hasPrefix(".embedding-") })

        // Another colour: a new cover, in the file and next to it (the old one removed).
        let renamed = Recording(folder: dir, audio: audio, date: recording.date, duration: 30, markers: [],
                                color: .green)
        let oldCover = try #require(await CoverArt.file(for: recording))
        let newCover = try #require(await CoverArt.file(for: renamed))
        #expect(oldCover != newCover && !FileManager.default.fileExists(atPath: oldCover.path))
        await AudioExport.embedCover(renamed)
        #expect(RecordingMeta.read(from: dir)?.coverKey == CoverArt.key(for: renamed))
        let embedded = try await AVURLAsset(url: audio).load(.metadata).first { $0.identifier == .iTunesMetadataCoverArt }?.load(.dataValue)
        #expect(embedded == (try Data(contentsOf: newCover)))
    }

}
