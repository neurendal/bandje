// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import Foundation

// The app's one player (BandjeKit's PlayerModel, ../specs/player.md) and how recordings map onto
// it. Rule numbers P1 to P16 are the spec's (section 4). Only the recording on screen plays:
// leaving it stops playback and keeps its position (P1, spec section 9).

extension Recording {
    /// The ID positions are kept under (spec 3.3): `created` from `.bandje.json` plus the length.
    var playerID: RecordingID { RecordingID(created: date, duration: duration) }

    /// What the player plays; nil without an audio file. Makes the cover when missing (lock screen).
    @MainActor var playable: PlayableItem? {
        guard let audio else { return nil }
        return PlayableItem(id: playerID, title: title, url: audio, duration: duration,
                            artwork: CoverArt.file(for: self))
    }
}

@MainActor
enum Playback {
    static let engine = AVAudioPlayerEngine()

    static let player: PlayerModel = makePlayer()

    private static func makePlayer() -> PlayerModel {
        let player = PlayerModel(engine: engine, store: PlaybackPositionStore(defaults: defaults), prepare: { @MainActor url in
            // P13: audio still in iCloud is downloaded first (state .loading meanwhile).
            try await ensureDownloaded(url)
        }, now: { @MainActor in Date() })
        // Never while recording: the microphone would hear it (P7).
        player.shouldStartPlayback = { !Recorder.shared.isActive }
        return player
    }

    private static var session: AudioSessionController?
    private static var nowPlaying: NowPlayingController?

    /// Selftests keep their positions apart from the user's (`--reset` clears them).
    nonisolated static let selftestSuite = "com.neurendal.bandje.selftest"

    private static var defaults: UserDefaults {
        #if DEBUG
        if !Selftest.options.isEmpty, let own = UserDefaults(suiteName: selftestSuite) { return own }
        #endif
        return .standard
    }

    /// At launch: the audio session (background audio, interruptions P11, route changes P10) and
    /// Now Playing with the lock screen and Control Center commands. Nothing is loaded (P12).
    static func start() {
        guard session == nil else { return }
        session = AudioSessionController(player: player)
        nowPlaying = NowPlayingController(player: player)
    }

    /// The player's recording is the one in `folder` (also after a rename kept its ID).
    static func isCurrent(_ folder: URL) -> Bool {
        guard let url = player.current?.url else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
    }

    /// The ID to ask the player about for `recording`: the current one's when it is that recording.
    static func id(of recording: Recording) -> RecordingID {
        isCurrent(recording.folder) ? player.current?.id ?? recording.playerID : recording.playerID
    }

    /// Play/pause in the screen of `recording`; it starts where it was left (P3).
    static func toggle(_ recording: Recording) {
        if isCurrent(recording.folder) {
            player.togglePlayPause()
        } else if let item = recording.playable {
            player.play(item)
        }
    }

    /// ±15 s in the screen of `recording`, also before it played: from its saved position.
    static func skip(_ recording: Recording, by seconds: TimeInterval) {
        seek(recording, to: (player.savedPosition(for: id(of: recording)) ?? 0) + seconds)
    }

    /// The position bar or a tapped sentence: there, playing or not as it was (as before).
    static func seek(_ recording: Recording, to time: TimeInterval) {
        if isCurrent(recording.folder) {
            player.seek(to: time)
        } else if let item = recording.playable {
            player.cue(item, at: min(max(0, time), item.duration))
            player.seek(to: time)  // saves the position (P15)
        }
    }

    /// From `time`, playing (a speaker's clip in the naming sheet).
    @discardableResult
    static func play(_ recording: Recording, at time: TimeInterval) -> Task<Void, Never> {
        guard let item = recording.playable else { return Task {} }
        return player.play(isCurrent(recording.folder) ? player.current ?? item : item, at: time)
    }

    /// P1: the screen shows `shown` now (nil: the list, nothing). Playback of another recording
    /// stops; its position is kept.
    static func left(showing shown: URL?) {
        guard player.current != nil else { return }
        if let shown, isCurrent(shown) { return }
        stop()
    }

    /// Stops and lets other apps' audio continue (unless a recording holds the session).
    static func stop() {
        guard player.current != nil else { return }
        player.stop()
        if !Recorder.shared.isActive { session?.deactivate() }
    }

    /// The recording was deleted (P9).
    static func removed(_ recording: Recording) {
        let wasCurrent = isCurrent(recording.folder)
        player.itemWasRemoved(id: id(of: recording))
        if wasCurrent, !Recorder.shared.isActive { session?.deactivate() }
    }

    /// The recording was renamed or got another colour: it plays on, with the new title, file and
    /// cover on the lock screen.
    static func moved(from old: URL, to recording: Recording) {
        guard isCurrent(old), let current = player.current, let audio = recording.audio else { return }
        player.itemWasMoved(id: current.id, to: PlayableItem(id: current.id, title: recording.title, url: audio,
                                                             duration: current.duration,
                                                             artwork: CoverArt.file(for: recording)))
        nowPlaying?.artworkChanged()
    }

    /// The message for a failed start (P13), nil when nothing failed.
    static var failure: String? {
        guard case .failed(let reason) = player.state else { return nil }
        switch reason {
        case .notDownloaded: return String(localized: "The audio could not be downloaded from iCloud.")
        case .unplayable: return String(localized: "This recording can't be played.")
        }
    }

    /// P13: waits until an iCloud file is on this iPhone (it starts the download).
    nonisolated static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 300) async throws {
        func status() -> URLUbiquitousItemDownloadingStatus? {
            // Still in iCloud as `.<name>.icloud`: not downloaded. No file at all: `.current`, so
            // the caller fails on the missing file instead of waiting.
            if !FileManager.default.fileExists(atPath: url.path) {
                let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
                return FileManager.default.fileExists(atPath: placeholder.path) ? .notDownloaded : .current
            }
            var u = url
            u.removeAllCachedResourceValues()
            let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard v?.isUbiquitousItem == true else { return .current }
            return v?.ubiquitousItemDownloadingStatus
        }
        if status() == .current { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            if status() == .current { return }
        }
        throw CocoaError(.fileReadNoSuchFile)
    }
}
