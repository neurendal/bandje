// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import Bandje

/// Recordings from the Watch (docs/watch.md 4): the transfer metadata and the import.
@Suite(.serialized)
struct WatchReceiverTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let created = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func metadataRoundTrip() {
        let t = WatchTransfer(created: created, duration: 754.2, markers: [12.3, 300], title: "Opname 8 nov 10:30")
        #expect(WatchTransfer(metadata: t.metadata) == t)
        var newer = t.metadata
        newer["bandje"] = WatchTransfer.version + 1
        #expect(WatchTransfer(metadata: newer) == nil)  // a newer Watch app: not misread
        #expect(WatchTransfer(metadata: ["title": "x"]) == nil)
        #expect(WatchTransfer.fileName(for: "Opname 8 nov 10:30") == "Opname 8 nov 10.30.m4a")
        #expect(WatchTransfer.fileName(for: "../.x") == "-.x.m4a")
    }

    @Test func importMakesARecordingWithMarkersAndSkipsDuplicates() async throws {
        let inbox = try tempDir(), docs = try tempDir()
        defer { try? FileManager.default.removeItem(at: inbox); try? FileManager.default.removeItem(at: docs) }
        let t = WatchTransfer(created: created, duration: 30, markers: [5, 12.5], title: "Opname 8 nov 10:30")
        let received = inbox.appending(path: "received.m4a")
        try Data("audio".utf8).write(to: received)
        try WatchReceiver.keep(received, metadata: t.metadata, in: inbox)

        let folders = await Library.importWatchInbox(inbox, into: docs, existing: [])
        #expect(folders.count == 1)
        let folder = try #require(folders.first)
        #expect(folder.lastPathComponent == Storage.safeName("Opname 8 nov 10:30"))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(folder.lastPathComponent).m4a").path))
        let meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.created == created && meta.markers == [5, 12.5] && meta.imported == nil)
        #expect((try FileManager.default.contentsOfDirectory(atPath: inbox.path)).isEmpty)

        // Delivered twice (the Watch did not hear back): not imported again.
        let again = inbox.appending(path: "again.m4a")
        try Data("audio".utf8).write(to: again)
        try WatchReceiver.keep(again, metadata: t.metadata, in: inbox)
        #expect(await Library.importWatchInbox(inbox, into: docs, existing: [(created, 30)]).isEmpty)
        #expect((try FileManager.default.contentsOfDirectory(atPath: inbox.path)).isEmpty)
    }

    @Test func metadataWithoutAudioIsDropped() async throws {
        let inbox = try tempDir(), docs = try tempDir()
        defer { try? FileManager.default.removeItem(at: inbox); try? FileManager.default.removeItem(at: docs) }
        try JSONSerialization.data(withJSONObject: ["bandje": 99]).write(to: inbox.appending(path: "x.json"))
        #expect(await Library.importWatchInbox(inbox, into: docs, existing: []).isEmpty)
        #expect((try FileManager.default.contentsOfDirectory(atPath: inbox.path)).isEmpty)
    }

    /// Audio with metadata it can't read, or with none at all: imported with a fallback title,
    /// never dropped (the Watch has deleted its copy).
    @Test func audioWithUnknownOrNoMetadataIsKept() async throws {
        let inbox = try tempDir(), docs = try tempDir()
        defer { try? FileManager.default.removeItem(at: inbox); try? FileManager.default.removeItem(at: docs) }
        let unknown = inbox.appending(path: "received.aac")
        try Data("audio".utf8).write(to: unknown)
        try WatchReceiver.keep(unknown, metadata: ["bandje": 99, "odd": Date()], in: inbox)
        try Data("audio".utf8).write(to: inbox.appending(path: "orphan.m4a"))

        let folders = await Library.importWatchInbox(inbox, into: docs, existing: [])
        #expect(folders.count == 2)
        // The ADTS file that could not be remuxed (not real audio) is kept as it is.
        let files = folders.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? [] }
        #expect(files.contains { $0.hasSuffix(".aac") } && files.contains { $0.hasSuffix(".m4a") })
        #expect(folders.allSatisfy { RecordingMeta.read(from: $0)?.created != nil })
        #expect((try FileManager.default.contentsOfDirectory(atPath: inbox.path)).isEmpty)
    }

    /// Imported in the background, transcribed once the app is active (owner, 2026-11-09).
    @Test func waitingImportsStartOnceWhenActive() {
        func recording(_ name: String, _ date: Date, transcript: Bool = false) -> Recording {
            let folder = URL(filePath: "/tmp/\(name)", directoryHint: .isDirectory)
            return Recording(folder: folder, audio: folder.appending(path: "\(name).m4a"), date: date, duration: 30, markers: [],
                             transcript: transcript ? folder.appending(path: "\(name).json") : nil)
        }
        let now = created.addingTimeInterval(3_600)
        let a = recording("a", created), b = recording("b", created.addingTimeInterval(60))
        let done = recording("done", created.addingTimeInterval(120), transcript: true)
        let busy = recording("busy", created.addingTimeInterval(180))
        let all = [a, b, done, busy]
        let pending = [a, b, done, busy].map { Library.watchKey($0.date) } + [Library.watchKey(a.date)]

        let plan = Library.watchTranscriptionPlan(pending, recordings: all, running: [busy.folder.standardizedFileURL],
                                                  automatic: true, now: now)
        // Each once, oldest first; not one with a transcript or already transcribing.
        #expect(plan.start.map(\.folder) == [a.folder, b.folder])
        // Every found one leaves the list, so a transcript deleted later is not made again.
        #expect(plan.keep.isEmpty)
        #expect(Library.watchTranscriptionPlan(plan.keep, recordings: all, automatic: true, now: now).start.isEmpty)

        // Automatic transcription turned off meanwhile: nothing starts and the list is cleared.
        let off = Library.watchTranscriptionPlan(pending, recordings: all, automatic: false, now: now)
        #expect(off.start.isEmpty && off.keep.isEmpty)

        // Not in the library yet (iCloud still listing it): kept, for 30 days.
        let later = Library.watchKey(created.addingTimeInterval(600))
        #expect(Library.watchTranscriptionPlan([later], recordings: all, automatic: true, now: now).keep == [later])
        #expect(Library.watchTranscriptionPlan([later], recordings: all, automatic: true,
                                               now: now.addingTimeInterval(31 * 86_400)).keep.isEmpty)
    }
}
