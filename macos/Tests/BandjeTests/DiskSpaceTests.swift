import AudioToolbox
import BandjeKit
import Foundation
import Testing
@testable import Bandje

/// Free space and the other reasons a recording stops by itself (owner, 2026-11-09).
struct DiskSpaceTests {
    private let gb: Int64 = 1_000_000_000

    @Test func recordingGoesOnWithRoomAndUnknownSpace() {
        #expect(AutoStop.check(writeError: noErr, freeBytes: 50 * gb, floor: gb, elapsed: 60) == nil)
        // A failed read never stops a recording.
        #expect(AutoStop.check(writeError: noErr, freeBytes: nil, floor: gb, elapsed: 60) == nil)
        // Low (below 2 GB) only warns.
        #expect(AutoStop.check(writeError: noErr, freeBytes: gb + 1, floor: gb, elapsed: 60) == nil)
        #expect(Recorder.diskLevel(gb + 1, floor: gb) == .low)
    }

    @Test func recordingStopsBelowTheFloor() {
        #expect(AutoStop.check(writeError: noErr, freeBytes: gb - 1, floor: gb, elapsed: 60) == .diskFull(freeBytes: gb - 1))
        // The floor is never below DiskSpace's, also when a lower one is passed.
        #expect(AutoStop.check(writeError: noErr, freeBytes: 500_000_000, floor: 0, elapsed: 60) == .diskFull(freeBytes: 500_000_000))
        // A raised floor (selftest) stops with plenty of room.
        #expect(AutoStop.check(writeError: noErr, freeBytes: 50 * gb, floor: 100 * gb, elapsed: 60) == .diskFull(freeBytes: 50 * gb))
    }

    @Test func writeErrorStopsFirst() {
        #expect(AutoStop.check(writeError: -1, freeBytes: 50 * gb, floor: gb, elapsed: 60) == .writeFailed(-1))
        #expect(AutoStop.check(writeError: -1, freeBytes: 1, floor: gb, elapsed: AutoStop.maxDuration) == .writeFailed(-1))
    }

    @Test func recordingStopsAfterTwelveHours() {
        #expect(AutoStop.maxDuration == 12 * 3600)
        #expect(AutoStop.check(writeError: noErr, freeBytes: 50 * gb, floor: gb, elapsed: AutoStop.maxDuration - 1) == nil)
        #expect(AutoStop.check(writeError: noErr, freeBytes: 50 * gb, floor: gb, elapsed: AutoStop.maxDuration) == .tooLong)
        // A full disk is the reason when both apply.
        #expect(AutoStop.check(writeError: noErr, freeBytes: 1, floor: gb, elapsed: AutoStop.maxDuration) == .diskFull(freeBytes: 1))
    }

    @Test func messagesSayWhatHappened() {
        #expect(AutoStop.diskFull(freeBytes: 900_000_000).message.contains("900"))
        #expect(AutoStop.writeFailed(-34).message.contains("-34"))
        #expect(!AutoStop.tooLong.message.isEmpty)
    }

    @Test func startNeedsTheFloor() {
        #expect(Recorder.startProblem(freeBytes: 50 * gb, floor: gb) == nil)
        #expect(Recorder.startProblem(freeBytes: nil, floor: gb) == nil)
        #expect(Recorder.startProblem(freeBytes: gb + 1, floor: gb) == nil)  // low: starts
        let problem = Recorder.startProblem(freeBytes: 900_000_000, floor: gb)
        #expect(problem?.contains("900") == true)
        #expect(problem?.contains("1000") == true)
    }

    @Test func freeBytesForAFolderNotMadeYet() {
        let notYet = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Opname 9 nov 10.00", isDirectory: true)
        #expect((Recorder.freeBytes(for: notYet) ?? 0) > 0)
    }

    /// Launch cleanup: only half files older than an hour; never a `.caf`, the audio or anything recent.
    @Test func leftoversOlderThanAnHourAreRemoved() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let lib = root.appendingPathComponent("lib", isDirectory: true)
        let temp = root.appendingPathComponent("tmp", isDirectory: true)
        let rec = lib.appendingPathComponent("Opname 9 nov 10.00", isDirectory: true)
        try fm.createDirectory(at: rec, withIntermediateDirectories: true)
        try fm.createDirectory(at: temp.appendingPathComponent("Share/A", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: temp.appendingPathComponent("Bandje-share-B", isDirectory: true), withIntermediateDirectories: true)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        func make(_ url: URL, old: Bool = true) {
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
            if old { try? fm.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: url.path) }
        }
        func age(_ url: URL) { try? fm.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: url.path) }
        let gone = [rec.appendingPathComponent("Opname 9 nov 10.00.converting.m4a"),
                    rec.appendingPathComponent(".embedding-1234.m4a"),
                    lib.appendingPathComponent("2026-11-05_14-30.converting.m4a"),
                    temp.appendingPathComponent("bandje-import-1.m4a"),
                    temp.appendingPathComponent("compact-1.m4a")]
        let kept = [rec.appendingPathComponent("Opname 9 nov 10.00.caf"),
                    rec.appendingPathComponent("Opname 9 nov 10.00.m4a"),
                    rec.appendingPathComponent(".bandje.json"),
                    temp.appendingPathComponent("other.m4a")]
        gone.forEach { make($0) }
        kept.forEach { make($0) }
        let fresh = rec.appendingPathComponent(".embedding-5678.m4a")
        make(fresh, old: false)
        let share = temp.appendingPathComponent("Share/A"), page = temp.appendingPathComponent("Bandje-share-B")
        age(share)
        age(page)
        let freshShare = temp.appendingPathComponent("Share/C", isDirectory: true)
        try fm.createDirectory(at: freshShare, withIntermediateDirectories: true)

        #expect(OutputLocation.removeLeftovers(recordingDirs: [lib], temp: temp) == gone.count + 2)
        for url in gone + [share, page] { #expect(!fm.fileExists(atPath: url.path), "\(url.lastPathComponent)") }
        for url in kept + [fresh, freshShare, rec] { #expect(fm.fileExists(atPath: url.path), "\(url.lastPathComponent)") }
    }
}
