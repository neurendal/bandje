// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Plays one recording at a time: transport, ±15 s, speed, Now Playing and the lock-screen /
/// Control Center commands. Position is polled while playing (AVAudioPlayer has no callback).
@MainActor @Observable
final class Player {
    static let shared = Player()

    nonisolated static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    nonisolated static let skipInterval: TimeInterval = 15

    private(set) var recording: Recording?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    var errorMessage: String?
    /// 0 in DEBUG selftests and unit tests (never play out loud on the Mac running the simulator).
    var volume: Float = 1 { didSet { audio?.volume = volume } }
    /// Set by `skip`/`seek`: the cassette spins fast for a moment, in the seek's direction.
    private(set) var lastSeek = Date.distantPast
    private(set) var lastSeekForward = true

    private var audio: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var commandsInstalled = false
    /// The recording's cover art for the lock screen and the Dynamic Island.
    private var artwork: MPMediaItemArtwork?

    /// Loads `recording` (if it is not the current one) without playing.
    func load(_ recording: Recording) {
        if self.recording?.folder == recording.folder, audio != nil { return }
        unload()
        guard let url = recording.audio else { return }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.enableRate = true
            audio.rate = rate
            audio.volume = volume
            audio.prepareToPlay()
            self.audio = audio
            self.recording = recording
            artwork = CoverArt.file(for: recording).flatMap(Self.artwork)
            duration = audio.duration
            currentTime = 0
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "This recording can't be played.")
        }
    }

    /// The recording was renamed (its folder moved) or got another colour: keep playing, update the
    /// title, URL and the cover on the lock screen (its sticker shows the title and the colour).
    func renamed(from old: URL, to recording: Recording) {
        guard self.recording?.folder == old else { return }
        self.recording = recording
        artwork = CoverArt.file(for: recording).flatMap(Self.artwork)
        updateNowPlaying()
    }

    func unload() {
        audio?.stop()
        audio = nil
        ticker?.cancel()
        ticker = nil
        recording = nil
        artwork = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if !Recorder.shared.isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func play() {
        guard let audio, !isPlaying, !Recorder.shared.isActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        installCommands()
        audio.rate = rate
        guard audio.play() else {
            errorMessage = String(localized: "This recording can't be played.")
            return
        }
        isPlaying = true
        updateNowPlaying()
        startTicker()
    }

    func pause() {
        guard let audio else { return }
        audio.pause()
        isPlaying = false
        currentTime = audio.currentTime
        ticker?.cancel()
        updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : play() }

    func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        guard let audio else { return }
        let target = Self.clamp(time, duration: duration)
        lastSeekForward = target >= currentTime
        audio.currentTime = target
        currentTime = target
        lastSeek = Date()
        updateNowPlaying()
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        audio?.rate = rate
        updateNowPlaying()
    }

    /// Not on the main actor: Media Player asks for the image on a background queue.
    nonisolated static func artwork(_ file: URL) -> MPMediaItemArtwork? {
        guard let image = UIImage(contentsOfFile: file.path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    nonisolated static func clamp(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, time), max(0, duration))
    }

    // MARK: Now Playing

    /// The lock-screen info for the current state (unit-tested).
    var nowPlayingInfo: [String: Any]? {
        guard let recording else { return nil }
        let playbackRate: Double = isPlaying ? Double(rate) : 0
        return [
            MPMediaItemPropertyTitle: recording.title,
            MPMediaItemPropertyArtist: "Band·je",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ].merging(artwork.map { [MPMediaItemPropertyArtwork: $0] } ?? [:]) { a, _ in a }
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let audio else { return }
        currentTime = audio.currentTime
        // Ended, or paused by the system (interruption, headphones unplugged).
        if isPlaying, !audio.isPlaying {
            isPlaying = false
            ticker?.cancel()
            updateNowPlaying()
        }
    }

    /// Lock screen and Control Center. Handlers come in on the main thread; they hop to the
    /// main actor explicitly so Swift 6 never traps on an unexpected queue.
    private func installCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in Player.shared.play() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in Player.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in Player.shared.toggle() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in Player.shared.skip(Player.skipInterval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in Player.shared.skip(-Player.skipInterval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in Player.shared.seek(to: position) }
            return .success
        }
    }
}
