// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import Foundation
import Testing
@testable import Bandje

/// The disk-space fixes (owner, 2026-11-09): a recording stops and is kept when the disk gets full,
/// writing fails or it reaches 12 hours.
@Suite
struct RecorderLimitTests {
    @Test func stopsWhenTheDiskIsTooFull() {
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: false, disk: .tooLow) == .diskFull)
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: false, disk: .low) == nil)
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: false, disk: .ok) == nil)
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: false, disk: nil) == nil)
    }

    @Test func stopsWhenWritingFails() {
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: true, disk: nil) == .writeFailed)
        #expect(Recorder.autoStopReason(elapsed: 60, writeFailed: true, disk: .tooLow) == .diskFull)
    }

    @Test func stopsAfterTwelveHours() {
        #expect(Recorder.maxDuration == 12 * 3600)
        #expect(Recorder.autoStopReason(elapsed: Recorder.maxDuration - 1, writeFailed: false, disk: .ok) == nil)
        #expect(Recorder.autoStopReason(elapsed: Recorder.maxDuration, writeFailed: false, disk: .ok) == .maxLength)
    }

    @Test func everyReasonHasAMessage() {
        for reason in [Recorder.StopReason.diskFull, .writeFailed, .maxLength] {
            #expect(!Recorder.message(for: reason).isEmpty)
        }
        #expect(!RecorderError.diskFull.message.isEmpty)
    }
}

/// A `.caf` that could not be converted shows in the library and is not converted over and over.
@Suite(.serialized)
struct UnconvertedRecordingTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A recording folder with `seconds` of tone in its `.caf`, still marked `recording` (as after a crash).
    private func unfinished(_ title: String, seconds: Double, in dir: URL) throws -> URL {
        let caf = try Storage.newRecording(title: title, date: Date(), in: dir)
        let writer = try CAFWriter(url: caf)
        let rate = CAFWriter.sampleRate
        writer.append((0..<Int(seconds * rate)).map { Float(0.2 * sin(2 * Double.pi * 330 * Double($0) / rate)) }, rate: rate)
        writer.finish()
        return caf
    }

    @Test func roomToConvertIsATenthPlusTheFloor() {
        #expect(Storage.hasRoomToConvert(cafSize: 4_000_000_000, available: nil))
        #expect(Storage.hasRoomToConvert(cafSize: 4_000_000_000, available: 1_400_000_000))
        #expect(!Storage.hasRoomToConvert(cafSize: 4_000_000_000, available: 1_399_999_999))
        #expect(!Storage.hasRoomToConvert(cafSize: 1_000, available: 999_000_000))
    }

    @Test func withoutRoomTheCafStaysAndShowsInTheLibrary() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try unfinished("Full", seconds: 1, in: dir)
        let folder = caf.deletingLastPathComponent()
        // Still recording (or crashed and not recovered yet): not in the library.
        #expect(Storage.scan(dir).isEmpty)

        #expect(Storage.recoverUnfinished(in: dir, available: { _ in 500_000_000 }).isEmpty)
        #expect(FileManager.default.fileExists(atPath: caf.path))
        let meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.recording == nil)
        #expect(meta.conversionAttempts == nil)  // no room is not a failed attempt
        let shown = try #require(Storage.scan(dir).first)
        #expect(shown.isUnconverted)
        #expect(shown.audio?.lastPathComponent == "Full.caf")
        #expect(abs(shown.duration - 1) < 0.05)
        // Not synced half-done: iCloud only takes folders with a finished audio file.
        #expect(Storage.audioFile(in: folder) == nil)

        // With room, the next launch converts it.
        #expect(Storage.recoverUnfinished(in: dir, available: { _ in nil }) == [folder])
        let converted = try #require(Storage.scan(dir).first)
        #expect(!converted.isUnconverted)
        #expect(converted.audio?.pathExtension == "m4a")
        #expect(!FileManager.default.fileExists(atPath: caf.path))
    }

    @Test func anUnreadableCafIsNotTriedAgainAndCanBeDeleted() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Broken", date: Date(), in: dir)
        try Data(repeating: 0x5A, count: 16_384).write(to: caf)
        let folder = caf.deletingLastPathComponent()

        #expect(Storage.recoverUnfinished(in: dir, available: { _ in nil }).isEmpty)
        #expect(RecordingMeta.read(from: folder)?.conversionAttempts == Storage.maxConversionAttempts)
        #expect(RecordingMeta.read(from: folder)?.recording == nil)
        #expect(FileManager.default.fileExists(atPath: caf.path))
        #expect(Storage.scan(dir).first?.isUnconverted == true)

        // The next launch leaves it alone (it would only fail again).
        let before = try Data(contentsOf: RecordingMeta.url(in: folder))
        #expect(Storage.recoverUnfinished(in: dir, available: { _ in nil }).isEmpty)
        #expect(try Data(contentsOf: RecordingMeta.url(in: folder)) == before)

        try Storage.delete(folder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(Storage.scan(dir).isEmpty)
    }

    @Test func failedAttemptsAreCountedUpToTheLimit() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try unfinished("Counted", seconds: 0.5, in: dir)
        let folder = caf.deletingLastPathComponent()
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.conversionAttempts = Storage.maxConversionAttempts
        try meta.write(to: folder)
        // Given up: not converted, even with room.
        #expect(Storage.recoverUnfinished(in: dir, available: { _ in nil }).isEmpty)
        #expect(FileManager.default.fileExists(atPath: caf.path))
        #expect(Storage.scan(dir).first?.isUnconverted == true)
    }
}

/// Turning "Sync with iCloud" off and on again does not double the library (the cloud folder here
/// is a plain folder: what matters is the comparison, not iCloud itself).
@Suite(.serialized)
struct SyncRoundTripTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A finished recording `<dir>/<title>/<title>.m4a` with `.bandje.json`.
    private func recording(_ title: String, seconds: Double, created: Date, in dir: URL) throws -> URL {
        let caf = try Storage.newRecording(title: title, date: created, in: dir)
        let writer = try CAFWriter(url: caf)
        let rate = CAFWriter.sampleRate
        writer.append((0..<Int(seconds * rate)).map { Float(0.2 * sin(2 * Double.pi * 440 * Double($0) / rate)) }, rate: rate)
        writer.finish()
        _ = try AudioExport.convertToM4A(caf)
        let folder = caf.deletingLastPathComponent()
        var meta = try #require(RecordingMeta.read(from: folder))
        meta.recording = nil
        try meta.write(to: folder)
        return folder
    }

    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aCopyOfTheCloudRecordingIsRemovedNotPublished() throws {
        let local = try tempDir(), cloud = try tempDir()
        defer { [local, cloud].forEach { try? FileManager.default.removeItem(at: $0) } }
        let inCloud = try recording("Talk", seconds: 1, created: created, in: cloud)
        try Data("{}".utf8).write(to: inCloud.appending(path: "Talk.json"))
        try Data("cover".utf8).write(to: inCloud.appending(path: ".cover-abc.jpg"))
        // What turning syncing off does: a copy of the whole folder.
        let copy = local.appending(path: "Talk", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: inCloud, to: copy)
        try Data("other cover".utf8).write(to: copy.appending(path: ".cover-def.jpg"))  // covers don't count
        #expect(CloudSync.publishPlan(for: Storage.canonical(copy), cloud: cloud) == .removeLocal(cloud: Storage.canonical(inCloud)))
    }

    @Test func aCopyChangedOnThisIPhoneStaysAndIsNotPublished() throws {
        let local = try tempDir(), cloud = try tempDir()
        defer { [local, cloud].forEach { try? FileManager.default.removeItem(at: $0) } }
        let inCloud = try recording("Talk", seconds: 1, created: created, in: cloud)
        let copy = local.appending(path: "Talk", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: inCloud, to: copy)
        // Transcribed while syncing was off: only here.
        try Data("{\"segments\":[]}".utf8).write(to: copy.appending(path: "Talk.json"))
        #expect(CloudSync.publishPlan(for: copy, cloud: cloud) == .keepLocal)
        // The markers changed here: also kept.
        try FileManager.default.removeItem(at: copy.appending(path: "Talk.json"))
        var meta = try #require(RecordingMeta.read(from: copy))
        meta.markers = [1]
        try meta.write(to: copy)
        #expect(CloudSync.publishPlan(for: copy, cloud: cloud) == .keepLocal)
    }

    @Test func theSameRecordingRenamedInICloudIsRecognisedByItsStart() throws {
        let local = try tempDir(), cloud = try tempDir()
        defer { [local, cloud].forEach { try? FileManager.default.removeItem(at: $0) } }
        try recording("Talk", seconds: 1, created: created, in: local)
        let renamed = try recording("Interview", seconds: 1, created: created, in: cloud)
        #expect(CloudSync.sameRecording(as: local.appending(path: "Talk"), in: cloud) == Storage.canonical(renamed))
        // Not the same files by name: kept here rather than removed.
        #expect(CloudSync.publishPlan(for: local.appending(path: "Talk"), cloud: cloud) == .keepLocal)
    }

    @Test func otherRecordingsArePublished() throws {
        let local = try tempDir(), cloud = try tempDir()
        defer { [local, cloud].forEach { try? FileManager.default.removeItem(at: $0) } }
        // Same name, another recording (another length, another start): published (as "Talk 2").
        try recording("Talk", seconds: 2, created: created.addingTimeInterval(3600), in: local)
        try recording("Talk", seconds: 1, created: created, in: cloud)
        #expect(CloudSync.publishPlan(for: local.appending(path: "Talk"), cloud: cloud) == .publish)
        // Nothing like it in iCloud.
        try recording("New", seconds: 1, created: created.addingTimeInterval(7200), in: local)
        #expect(CloudSync.publishPlan(for: local.appending(path: "New"), cloud: cloud) == .publish)
    }
}

/// Audio from another device stays in iCloud until it is played or transcribed; the library still
/// shows the recording, with the transcript's length.
@Suite(.serialized)
struct AudioInICloudTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-icloud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func placeholderNames() {
        #expect(Storage.visibleName(".Talk.m4a.icloud") == "Talk.m4a")
        #expect(Storage.visibleName("Talk.m4a") == "Talk.m4a")
        #expect(Storage.visibleName(".bandje.json") == nil)
        #expect(Storage.visibleName("..bandje.json.icloud") == nil)  // a hidden file still in iCloud
        #expect(Storage.visibleName(".icloud") == nil)
    }

    @MainActor @Test func aRecordingWhoseAudioIsStillInICloudIsListedWithoutOpeningIt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Talk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: ".Talk.m4a.icloud"))
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        try RecordingMeta(created: created).write(to: folder)
        try Data("{\"duration\": 42.5, \"segments\": []}".utf8).write(to: folder.appending(path: "Talk.json"))

        let recording = try #require(Storage.scan(dir).first)
        #expect(recording.audio?.lastPathComponent == "Talk.m4a")
        #expect(!recording.audioIsLocal)
        #expect(recording.duration == 42.5)
        #expect(recording.date == created)
        #expect(!recording.isUnconverted)
        // No cover yet: its key needs the real length.
        #expect(CoverArt.file(for: recording) == nil)
    }

    @Test func downloadingWaitsForAPlaceholderButNotForAMissingFile() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appending(path: ".Talk.m4a.icloud"))
        await #expect(throws: (any Error).self) {
            try await Playback.ensureDownloaded(dir.appending(path: "Talk.m4a"), timeout: 1)
        }
        try await Playback.ensureDownloaded(dir.appending(path: "Gone.m4a"), timeout: 1)
        let local = dir.appending(path: "Here.m4a")
        try Data("x".utf8).write(to: local)
        try await Playback.ensureDownloaded(local, timeout: 1)
        #expect(Storage.isLocal(local))
        #expect(!Storage.isLocal(dir.appending(path: "Talk.m4a")))
    }
}

/// Half files left by a kill are removed at launch, only when old, never from a running recording.
@Suite(.serialized)
struct LeftoverTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-left-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let fm = FileManager.default
    private let twoHoursAgo = Date().addingTimeInterval(-7_200)

    @discardableResult
    private func file(_ name: String, in folder: URL, old: Bool) throws -> URL {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("x".utf8).write(to: url)
        if old { try fm.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: url.path) }
        return url
    }

    @Test func oldHalfFilesGoNewOnesAndRecordingsStay() throws {
        let local = try tempDir(), cloud = try tempDir()
        defer { [local, cloud].forEach { try? fm.removeItem(at: $0) } }
        // A finished recording with an old cover embed and an old import conversion next to it.
        let done = local.appending(path: "Done", directoryHint: .isDirectory)
        let audio = try file("Done.m4a", in: done, old: true)
        try RecordingMeta(created: Date()).write(to: done)
        let embedding = try file(".embedding-1.m4a", in: done, old: true)
        let converting = try file("Done.converting.m4a", in: done, old: true)
        let fresh = try file(".embedding-2.m4a", in: done, old: false)
        // An import cut off before its audio was in place: the folder goes.
        let cut = local.appending(path: "Cut", directoryHint: .isDirectory)
        try file("Cut.converting.mp4", in: cut, old: true)
        // The running recording, and one still marked recording (recovery's): untouched.
        let running = local.appending(path: "Running", directoryHint: .isDirectory)
        let runningTemp = try file("Running.converting.m4a", in: running, old: true)
        let crashed = local.appending(path: "Crashed", directoryHint: .isDirectory)
        let crashedTemp = try file("Crashed.converting.m4a", in: crashed, old: true)
        try RecordingMeta(created: Date(), recording: true).write(to: crashed)
        // A user's file whose name only looks like ours.
        let user = local.appending(path: "My.converting", directoryHint: .isDirectory)
        let userAudio = try file("My.converting.m4a", in: user, old: true)
        // In iCloud: an old cover embed goes; `.converting.` is not ours there.
        let shared = cloud.appending(path: "Shared", directoryHint: .isDirectory)
        let cloudEmbedding = try file(".embedding-3.m4a", in: shared, old: true)
        let cloudConverting = try file("Shared.converting.m4a", in: shared, old: true)

        Storage.removeLeftovers(in: [local, cloud], local: local, except: running)

        for gone in [embedding, converting, cut, cloudEmbedding] { #expect(!fm.fileExists(atPath: gone.path), "\(gone.lastPathComponent)") }
        for kept in [audio, fresh, runningTemp, crashedTemp, userAudio, cloudConverting, RecordingMeta.url(in: done)] {
            #expect(fm.fileExists(atPath: kept.path), "\(kept.lastPathComponent)")
        }
    }

    @Test func oldIncomingFilesOfTheShareExtensionGo() throws {
        let inbox = try tempDir()
        defer { try? fm.removeItem(at: inbox) }
        let incoming = inbox.appending(path: ".incoming", directoryHint: .isDirectory)
        let old = try file("A.m4a", in: incoming, old: true)
        let new = try file("B.m4a", in: incoming, old: false)
        let waiting = try file("C.m4a", in: inbox, old: true)  // complete: imported, not removed
        #expect(Importer.removeStaleIncoming(in: inbox).map(\.lastPathComponent) == ["A.m4a"])
        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: new.path) && fm.fileExists(atPath: waiting.path))
    }
}
