import AppKit
import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Plays one recording at a time in the Bandje window (ported from the iPhone's `Player`, without
/// the audio session). Shows in Now Playing (Control Centre, the menu bar) with the recording's
/// cover and title; its play, pause, ±15 s and scrub commands work there too. The position is
/// polled while playing.
@MainActor @Observable
final class AudioPlayer {
    static let shared = AudioPlayer()

    nonisolated static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    nonisolated static let skipInterval: TimeInterval = 15

    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    /// Set by `seek`: the cassette spins fast for a moment, in the seek's direction.
    private(set) var lastSeek = Date.distantPast
    private(set) var lastSeekForward = true

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// The latest load; an older one that finishes later (a download) is dropped.
    @ObservationIgnored private var loading = 0
    @ObservationIgnored private var commandsInstalled = false
    /// The cover shown in Now Playing and the file it came from.
    @ObservationIgnored private var artwork: (file: URL, item: MPMediaItemArtwork)?

    /// Loads `url` without playing; audio still in iCloud is downloaded first.
    func load(_ url: URL) async throws {
        if self.url == url, audio != nil { return }
        unload()
        loading += 1
        let mine = loading
        try await Activity.shared.whileDownloading(url) { try await ICloudSync.ensureDownloaded(url) }
        guard mine == loading else { throw CancellationError() }
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.enableRate = true
        audio.rate = rate
        audio.prepareToPlay()
        self.audio = audio
        self.url = url
        duration = audio.duration
        time = 0
        installCommands()
        updateNowPlaying()
    }

    /// The recording's folder was renamed: keep playing from the new place.
    func renamed(to url: URL) {
        self.url = url
        updateNowPlaying()
    }

    /// A new cover was put into the recording in `folder` (`CoverArt.embed`).
    func coverChanged(in folder: URL) {
        guard url?.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return }
        updateNowPlaying()
    }

    func unload() {
        audio?.stop()
        audio = nil
        ticker?.cancel()
        ticker = nil
        url = nil
        isPlaying = false
        time = 0
        duration = 0
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func play() {
        guard let audio, !isPlaying else { return }
        audio.rate = rate
        guard audio.play() else { return }
        isPlaying = true
        updateNowPlaying()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.tick()
            }
        }
    }

    func pause() {
        guard let audio else { return }
        audio.pause()
        isPlaying = false
        time = audio.currentTime
        ticker?.cancel()
        updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : play() }

    func skip(_ seconds: TimeInterval) { seek(time + seconds) }

    func seek(_ target: TimeInterval) {
        guard let audio else { return }
        let t = min(max(0, target), max(0, duration))
        lastSeekForward = t >= time
        audio.currentTime = t
        time = t
        lastSeek = Date()
        updateNowPlaying()
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        audio?.rate = rate
        updateNowPlaying()
    }

    private func tick() {
        guard let audio else { return }
        time = audio.currentTime
        if isPlaying, !audio.isPlaying {  // ended
            isPlaying = false
            ticker?.cancel()
            updateNowPlaying()
        }
    }

    /// Title, cover, length, position and rate for Now Playing (it runs the clock from the rate).
    private func updateNowPlaying() {
        guard let url else { return }
        let folder = url.deletingLastPathComponent()
        if let file = CoverArt.existing(in: folder) {
            if artwork?.file != file, let image = NSImage(contentsOf: file) {
                artwork = (file, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
            }
        } else {
            artwork = nil
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: folder.lastPathComponent,
            MPMediaItemPropertyArtist: "Band·je",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio?.currentTime ?? time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork.item }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func installCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in AudioPlayer.shared.play() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in AudioPlayer.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in AudioPlayer.shared.toggle() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in AudioPlayer.shared.skip(AudioPlayer.skipInterval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in AudioPlayer.shared.skip(-AudioPlayer.skipInterval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in AudioPlayer.shared.seek(position) }
            return .success
        }
    }
}
