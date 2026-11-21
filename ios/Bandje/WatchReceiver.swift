// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import UIKit
import os
import WatchConnectivity

/// Recordings from the Watch (docs/watch.md 4). WatchConnectivity is Apple's own Watch–iPhone link
/// (Bluetooth or the pair's local Wi-Fi); no networking code of ours. The system delivers a file
/// also when Band·je is not running (it is woken in the background): the delegate moves it into
/// `WatchReceiver.inbox` at once (the file is gone when the delegate returns), then the library
/// imports it like a recording made here.
final class WatchReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchReceiver()

    /// Received, not yet imported: `<id>.aac` (or `.m4a`) with `<id>.json` (the transfer's
    /// metadata). Outside Documents, so the library never shows a half-received file.
    static var inbox: URL {
        URL.applicationSupportDirectory.appending(path: "WatchInbox", directoryHint: .isDirectory)
    }

    /// At launch: the session (the system delivers what waited).
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in await Library.shared.importFromWatch() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another Watch: the new one needs an active session too.
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// Every file is kept, also with metadata that can't be read: the Watch deletes its copy once
    /// the delivery succeeded, so this is the only one left.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            try Self.keep(file.fileURL, metadata: file.metadata ?? [:], in: Self.inbox)
        } catch {
            Logger(subsystem: "com.neurendal.bandje", category: "watch")
                .error("Could not keep a recording from the Watch: \(error.localizedDescription, privacy: .public)")
            return
        }
        Task { @MainActor in await Library.shared.importFromWatch() }
    }

    /// Held while a received file is moved in and while the import lists the inbox, so the import
    /// never sees a pair half-written.
    static let inboxLock = NSLock()

    /// Moves (or else copies) a received file into `inbox` as `<id>.<ext>` next to `<id>.json`
    /// (json last). Metadata that is not valid JSON is written as `{}`: the import then uses a
    /// fallback title and date.
    static func keep(_ file: URL, metadata: [String: Any], in inbox: URL) throws {
        let fm = FileManager.default
        try inboxLock.withLock {
            try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            let id = UUID().uuidString
            let ext = file.pathExtension.isEmpty ? "m4a" : file.pathExtension.lowercased()
            let target = inbox.appending(path: "\(id).\(ext)")
            do {
                try fm.moveItem(at: file, to: target)
            } catch {
                try fm.copyItem(at: file, to: target)
            }
            let data = (try? JSONSerialization.data(withJSONObject: JSONSerialization.isValidJSONObject(metadata) ? metadata : [:]))
                ?? Data("{}".utf8)
            try data.write(to: inbox.appending(path: "\(id).json"), options: .atomic)
        }
    }
}

extension Library {
    /// Imports what the Watch sent (`WatchReceiver.inbox`): each becomes a recording as one made on
    /// this iPhone (a folder with the audio and `.bandje.json` with the start and the markers),
    /// moved to iCloud when syncing, and transcribed when that is on. A recording that
    /// is already in the library (the same start to the second and length) is not imported twice.
    /// Transcribing runs only with Band·je in front (owner, 2026-11-09): imported in the background,
    /// it waits in `watchImportsToTranscribe` until the app is active.
    func importFromWatch() async {
        // A delivery during an import: that import runs once more when it is done.
        guard !importingFromWatch else {
            importFromWatchAgain = true
            return
        }
        importingFromWatch = true
        defer { importingFromWatch = false }
        repeat {
            importFromWatchAgain = false
            await importWatchInboxOnce()
        } while importFromWatchAgain
    }

    private func importWatchInboxOnce() async {
        await CloudSync.shared.resolveFolder()
        let inbox = WatchReceiver.inbox
        let existing = recordings.map { (date: $0.date, duration: $0.duration) }
        let folders = await Task.detached { await Self.importWatchInbox(inbox, existing: existing) }.value
        guard !folders.isEmpty else { return }
        await refresh(except: Recorder.shared.folder)
        let wanted = Set(folders.map(\.standardizedFileURL))
        transcribeAutomatically(recordings.filter { wanted.contains($0.folder.standardizedFileURL) })
    }

    /// "Transcribe automatically" for new recordings (from the Watch, or stopped from the Lock
    /// Screen): now with Band·je in front, else they wait in `watchImportsToTranscribe` until it is.
    func transcribeAutomatically(_ recordings: [Recording]) {
        let waiting = UserDefaults.standard.bool(forKey: "autoTranscribe") && UIApplication.shared.applicationState != .active
        if waiting {
            let keys = Self.watchImportsToTranscribe + recordings.map { Self.watchKey($0.date) }
            UserDefaults.standard.set(keys, forKey: Self.watchImportsKey)
        } else {
            Transcriptions.shared.startIfAutomatic(recordings)
        }
    }

    /// New recordings (Watch imports, or stopped in the background) that wait for the app to be active to be transcribed, by start to the second
    /// (as `seen`: it stays when a recording is renamed or moves to iCloud). Only on this device, so
    /// another device that sees the recording in iCloud never transcribes it as well. An entry goes
    /// once its transcription starts, so a transcript deleted later is not made again.
    private static let watchImportsKey = "watchImportsToTranscribe"
    private static var watchImportsToTranscribe: [Int] {
        UserDefaults.standard.array(forKey: watchImportsKey) as? [Int] ?? []
    }
    nonisolated static func watchKey(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    /// When the app is active: starts the Watch imports that waited (`importFromWatch`).
    func transcribeWaitingWatchImports() {
        let pending = Self.watchImportsToTranscribe
        guard !pending.isEmpty else { return }
        let running = Set(recordings.map(\.folder).filter(Transcriptions.shared.isRunning).map(\.standardizedFileURL))
        let plan = Self.watchTranscriptionPlan(pending, recordings: recordings, running: running,
                                               automatic: UserDefaults.standard.bool(forKey: "autoTranscribe"))
        UserDefaults.standard.set(plan.keep, forKey: Self.watchImportsKey)
        Transcriptions.shared.startIfAutomatic(plan.start)
    }

    /// Which waiting Watch imports to start now, and which keys to keep (tested). Automatic
    /// transcription turned off meanwhile: none, and the list is cleared (turning it on later does
    /// not reach back). A recording found is started only without a transcript and not
    /// transcribing already (`running`, standardized folders), and leaves the list either way. One
    /// not in the library (yet: iCloud may still be listing it) stays for 30 days.
    nonisolated static func watchTranscriptionPlan(_ pending: [Int], recordings: [Recording], running: Set<URL> = [],
                                                   automatic: Bool, now: Date = Date()) -> (start: [Recording], keep: [Int]) {
        guard automatic else { return ([], []) }
        var start: [Recording] = []
        var keep: [Int] = []
        for key in Set(pending) {
            if let recording = recordings.first(where: { watchKey($0.date) == key }) {
                if recording.transcript == nil, !running.contains(recording.folder.standardizedFileURL) { start.append(recording) }
            } else if now.timeIntervalSince1970 - Double(key) < 30 * 86_400 {
                keep.append(key)
            }
        }
        return (start.sorted { $0.date < $1.date }, keep.sorted())
    }

    /// The file work of `importFromWatch` (off the main actor; tested): returns the new folders.
    /// A file whose metadata can't be read, or that has none (a crash between the two writes), is
    /// imported with its file date and the default title: nothing delivered is dropped. ADTS
    /// (`.aac`, the Watch's format) becomes `.m4a` without re-encoding; if that fails it is
    /// imported as `.aac`.
    nonisolated static func importWatchInbox(_ inbox: URL, into dir: URL = Storage.documents,
                                             existing: [(date: Date, duration: Double)]) async -> [URL] {
        let fm = FileManager.default
        let remuxSuffix = ".remux.m4a"
        // Listed under the lock: a file being moved in is either complete or not seen yet.
        let pairs: [(audio: URL, json: URL)] = WatchReceiver.inboxLock.withLock {
            let files = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
            var pairs: [(audio: URL, json: URL)] = []
            for file in files {
                if file.lastPathComponent.hasSuffix(remuxSuffix) {
                    try? fm.removeItem(at: file)  // left by a remux that was cut off
                    continue
                }
                let json = file.deletingPathExtension().appendingPathExtension("json")
                if file.pathExtension == "json" {
                    let hasAudio = files.contains { $0 != file && $0.deletingPathExtension() == file.deletingPathExtension() }
                    if !hasAudio { try? fm.removeItem(at: file) }  // its audio was imported or never came
                } else {
                    pairs.append((file, json))
                }
            }
            return pairs.sorted { $0.audio.lastPathComponent < $1.audio.lastPathComponent }
        }
        var known = existing
        var folders: [URL] = []
        for (audio, json) in pairs {
            let metadata = (try? Data(contentsOf: json)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let sent = WatchTransfer(metadata: metadata)
            let transfer = sent ?? fallbackTransfer(for: audio)
            // Only the Watch's own start and length tell a second delivery; a fallback date is a guess.
            if sent != nil, known.contains(where: { abs($0.date.timeIntervalSince(transfer.created)) < 1 && abs($0.duration - transfer.duration) < 1 }) {
                try? fm.removeItem(at: audio)
                try? fm.removeItem(at: json)
                continue
            }
            do {
                var source = audio
                if audio.pathExtension.lowercased() == "aac" {
                    let remuxed = inbox.appending(path: audio.deletingPathExtension().lastPathComponent + remuxSuffix)
                    if let session = AVAssetExportSession(asset: AVURLAsset(url: audio), presetName: AVAssetExportPresetPassthrough),
                       (try? await session.export(to: remuxed, as: .m4a)) != nil {
                        source = remuxed
                    } else {
                        try? fm.removeItem(at: remuxed)
                    }
                }
                let name = Storage.uniqueName(Storage.safeName(transfer.title), in: dir)
                let folder = dir.appending(path: name, directoryHint: .isDirectory)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let ext = source == audio ? audio.pathExtension.lowercased() : "m4a"
                let target = folder.appending(path: "\(name).\(ext)")
                try fm.moveItem(at: source, to: target)
                var meta = RecordingMeta(created: transfer.created)
                meta.markers = transfer.markers
                meta.setDuration(Storage.duration(of: target))
                try meta.write(to: folder)
                if source != audio { try? fm.removeItem(at: audio) }
                try? fm.removeItem(at: json)
                known.append((transfer.created, transfer.duration))
                folders.append(Storage.publish(folder))
            } catch {
                continue  // stays in the inbox; tried again at the next launch or delivery
            }
        }
        return folders
    }

    /// For a received file without readable metadata: its file date (to the second) and the
    /// default title for it.
    nonisolated static func fallbackTransfer(for audio: URL) -> WatchTransfer {
        let values = try? audio.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate ?? values?.contentModificationDate ?? Date()
        let created = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        return WatchTransfer(created: created, duration: Storage.duration(of: audio), markers: [],
                             title: Storage.defaultTitle(for: created))
    }
}
