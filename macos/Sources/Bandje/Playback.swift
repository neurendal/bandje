import AppKit
import BandjeKit
import Foundation
import Observation

// The app's one player (BandjeKit's PlayerModel, ../specs/player.md) and how Mac recordings map
// onto it. Rule numbers P1 to P16 are the spec's (section 4).

extension Recording {
    /// The ID positions are kept under (spec 3.3): `created` from `.bandje.json` plus the length.
    var playerID: RecordingID { RecordingID(created: date, duration: duration) }

    /// What the player plays; nil without an audio file.
    var playable: PlayableItem? {
        guard let audio else { return nil }
        return PlayableItem(id: playerID, title: title, url: audio, duration: duration,
                            artwork: CoverArt.existing(in: folder))
    }
}

@MainActor
enum Playback {
    static let player: PlayerModel = {
        let player = PlayerModel(engine: AVAudioPlayerEngine(), store: PlaybackPositionStore(defaults: defaults), prepare: { url in
            // P13: audio still in iCloud is downloaded first; the window says so meanwhile.
            try await Activity.shared.whileDownloading(url) { try await ICloudSync.ensureDownloaded(url) }
        })
        // Not while recording: the Mac's own sound would end up in the recording (P7).
        player.shouldStartPlayback = { !Activity.shared.isRecording }
        return player
    }()

    private static var nowPlaying: NowPlayingController?

    /// The selftest (DEBUG, `--selftest…`) keeps its positions apart from the user's.
    private static var defaults: UserDefaults {
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") }),
           let own = UserDefaults(suiteName: "com.neurendal.bandje.selftest") { return own }
        #endif
        return .standard
    }

    /// At launch: Now Playing and the remote commands (media keys, AirPods) and following the
    /// library (P9, renames). Nothing is loaded (P12): each recording opens at its saved position.
    static func start() {
        guard nowPlaying == nil else { return }
        nowPlaying = NowPlayingController(player: player)
        followLibrary()
    }

    /// The player's recording is the one in `folder` (also when its length, and so its ID, changed).
    static func isCurrent(_ folder: URL) -> Bool {
        guard let url = player.current?.url else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
    }

    /// The ID to ask the player about for `recording`: the current one's when it is that recording.
    static func id(of recording: Recording) -> RecordingID {
        isCurrent(recording.folder) ? player.current?.id ?? recording.playerID : recording.playerID
    }

    /// Play/pause for the detail of `recording`: its own toggle when it is the current one,
    /// otherwise it starts, where it was left (P3).
    static func toggle(_ recording: Recording) {
        if isCurrent(recording.folder) {
            player.togglePlayPause()
        } else if let item = recording.playable {
            player.play(item)
        }
    }

    /// ±15 s in the detail of `recording`; another recording starts at its saved position ± 15.
    static func skip(_ recording: Recording, by seconds: TimeInterval) {
        if isCurrent(recording.folder) {
            player.skip(by: seconds)
        } else if let item = recording.playable {
            player.play(item, at: max(0, (player.savedPosition(for: item.id) ?? 0) + seconds))
        }
    }

    /// Scrubbing or a tapped sentence: there, playing (P5).
    static func play(_ recording: Recording, at time: TimeInterval) {
        guard let item = recording.playable else { return }
        if isCurrent(recording.folder) {
            player.seek(to: time)
            if player.state != .playing, player.state != .loading { player.togglePlayPause() }
        } else {
            player.play(item, at: time)
        }
    }

    /// The recording was deleted here (P9).
    static func removed(_ recording: Recording) {
        player.itemWasRemoved(id: id(of: recording))
    }

    /// The recording's folder moved (renamed here, in Finder or on the iPhone): playback goes on
    /// from the new place.
    static func moved(from old: URL, to folder: URL) {
        guard isCurrent(old), let current = player.current, let audio = Library.audioFile(in: folder) else { return }
        player.itemWasMoved(id: current.id, to: PlayableItem(id: current.id, title: folder.lastPathComponent, url: audio,
                                                             duration: current.duration, artwork: CoverArt.existing(in: folder)))
    }

    /// A new cover was put into the recording in `folder` (`CoverArt.embed`).
    static func coverChanged(in folder: URL) {
        guard isCurrent(folder), let current = player.current else { return }
        var item = current
        item.artwork = CoverArt.existing(in: folder)
        player.itemWasMoved(id: current.id, to: item)
        nowPlaying?.artworkChanged()
    }

    /// The message for a failed start (P13), nil when nothing failed.
    static var failure: String? {
        guard case .failed(let reason) = player.state else { return nil }
        switch reason {
        case .notDownloaded: return tr("player.failed.download", "De audio kon niet uit iCloud worden opgehaald.")
        case .unplayable: return tr("player.failed.play", "Deze audio kan niet worden afgespeeld.")
        }
    }

    /// P1: the window no longer shows the recording in the player (another one was selected, the
    /// record screen opened, the window closed): playback stops, its position is kept. `shown` is
    /// the folder the detail shows now, nil for none.
    static func left(showing shown: URL?) {
        guard player.current != nil else { return }
        if let shown, isCurrent(shown) { return }
        player.stop()
    }

    // MARK: Library

    /// Each library refresh: a recording that was renamed or moved by iCloud plays on from its new
    /// place; one whose file is gone stops the player (P9). A file that is still there but not in
    /// the list (another recordings folder) is left alone.
    private static func followLibrary() {
        withObservationTracking {
            _ = Library.shared.recordings
        } onChange: {
            Task { @MainActor in
                reconcile(Library.shared.recordings)
                followLibrary()
            }
        }
    }

    static func reconcile(_ recordings: [Recording]) {
        guard let current = player.current, Library.shared.hasLoaded else { return }
        let match = recordings.first { $0.playerID == current.id }
            ?? recordings.first { isCurrent($0.folder) }
        if let match, let item = match.playable {
            if item.url != current.url || item.title != current.title || item.artwork != current.artwork {
                player.itemWasMoved(id: current.id, to: PlayableItem(id: current.id, title: item.title, url: item.url,
                                                                     duration: current.duration, artwork: item.artwork))
            }
        } else if !FileManager.default.fileExists(atPath: current.url.path) {
            player.itemWasRemoved(id: current.id)
        }
    }
}
