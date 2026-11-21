// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation

/// What `PlayerModel` needs from an audio player. One file at a time, local files only (the model
/// downloads from iCloud first). Callbacks come on the main actor.
@MainActor
public protocol AudioEngine: AnyObject {
    /// The position while playing, several times a second.
    var onTime: ((TimeInterval) -> Void)? { get set }
    /// Played to the end.
    var onEnd: (() -> Void)? { get set }
    /// Stopped without being asked (iOS: an interruption, a lost output).
    var onExternalStop: (() -> Void)? { get set }
    /// The file could not be decoded while playing.
    var onFailure: ((Error) -> Void)? { get set }

    var currentTime: TimeInterval { get }
    var rate: Float { get set }
    var volume: Float { get set }

    /// Opens `url`, ready to play at 0. Returns its duration.
    func load(_ url: URL) throws -> TimeInterval
    func unload()
    /// Starts or resumes; false when it could not start.
    func play() -> Bool
    func pause()
    func seek(to time: TimeInterval)
}

/// The real engine: AVAudioPlayer, as both apps used before. Stereo files play as they are
/// (Mac recordings: microphone left, system audio right). The position is polled while playing.
@MainActor
public final class AVAudioPlayerEngine: NSObject, AudioEngine, AVAudioPlayerDelegate {
    public var onTime: ((TimeInterval) -> Void)?
    public var onEnd: (() -> Void)?
    public var onExternalStop: (() -> Void)?
    public var onFailure: ((Error) -> Void)?

    public var rate: Float = 1 { didSet { audio?.rate = rate } }
    public var volume: Float = 1 { didSet { audio?.volume = volume } }
    public var currentTime: TimeInterval { audio?.currentTime ?? 0 }

    private var audio: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    /// True between `play()` and a pause, the end or a stop.
    private var expectsPlaying = false
    private var lastTick: TimeInterval = 0

    public override init() {
        super.init()
    }

    public func load(_ url: URL) throws -> TimeInterval {
        unload()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.enableRate = true
        audio.rate = rate
        audio.volume = volume
        audio.delegate = self
        audio.prepareToPlay()
        self.audio = audio
        lastTick = 0
        return audio.duration
    }

    public func unload() {
        stopTicker()
        expectsPlaying = false
        audio?.stop()
        audio = nil
    }

    public func play() -> Bool {
        guard let audio else { return false }
        audio.rate = rate
        guard audio.play() else { return false }
        expectsPlaying = true
        lastTick = audio.currentTime
        startTicker()
        return true
    }

    public func pause() {
        expectsPlaying = false
        stopTicker()
        audio?.pause()
    }

    public func seek(to time: TimeInterval) {
        audio?.currentTime = time
        lastTick = time
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let audio, expectsPlaying else { return }
        if !audio.isPlaying {
            // Played to the end (the delegate may come later), or stopped by the system.
            let atEnd = lastTick >= audio.duration - 0.5 || audio.currentTime >= audio.duration - 0.05
            atEnd ? finished() : stoppedBySystem()
            return
        }
        lastTick = audio.currentTime
        onTime?(lastTick)
    }

    private func finished() {
        guard expectsPlaying else { return }
        expectsPlaying = false
        stopTicker()
        onEnd?()
    }

    private func stoppedBySystem() {
        expectsPlaying = false
        stopTicker()
        onExternalStop?()
    }

    // The delegate calls hop to the main actor; by then another file may be loaded, so a call
    // about a player that is no longer `audio` is dropped.

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let sent = SentPlayer(player: player)
        Task { @MainActor in
            guard sent.player === self.audio else { return }
            self.finished()
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "decode error"
        let sent = SentPlayer(player: player)
        Task { @MainActor in
            guard sent.player === self.audio else { return }
            self.expectsPlaying = false
            self.stopTicker()
            self.onFailure?(EngineError(message: message))
        }
    }

    /// AVAudioPlayer is Sendable in the iOS SDK but not in the macOS one; it is only compared here.
    private struct SentPlayer: @unchecked Sendable { let player: AVAudioPlayer }

    struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

/// An engine without audio, for tests, selftests and screenshots: time moves only with `advance`.
@MainActor
public final class FakeAudioEngine: AudioEngine {
    public var onTime: ((TimeInterval) -> Void)?
    public var onEnd: (() -> Void)?
    public var onExternalStop: (() -> Void)?
    public var onFailure: ((Error) -> Void)?

    public var rate: Float = 1
    public var volume: Float = 1
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var loadedURL: URL?
    public private(set) var duration: TimeInterval = 0

    /// Durations per file; others last `defaultDuration`.
    public var durations: [URL: TimeInterval] = [:]
    public var defaultDuration: TimeInterval = 60
    /// Files that fail to load.
    public var unplayable: Set<URL> = []

    public struct LoadError: LocalizedError {
        public var errorDescription: String? { "Can't open the file" }
    }

    public init() {}

    public func load(_ url: URL) throws -> TimeInterval {
        unload()
        if unplayable.contains(url) { throw LoadError() }
        loadedURL = url
        duration = durations[url] ?? defaultDuration
        currentTime = 0
        return duration
    }

    public func unload() {
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    public func play() -> Bool {
        guard loadedURL != nil else { return false }
        isPlaying = true
        return true
    }

    public func pause() {
        isPlaying = false
    }

    public func seek(to time: TimeInterval) {
        currentTime = min(max(0, time), duration)
    }

    /// Plays `seconds` of wall-clock time at the current rate.
    public func advance(by seconds: TimeInterval) {
        guard isPlaying else { return }
        currentTime += seconds * Double(rate)
        if currentTime >= duration {
            currentTime = duration
            isPlaying = false
            onEnd?()
        } else {
            onTime?(currentTime)
        }
    }

    /// The system stops playback (iOS interruption before it is reported).
    public func stopBySystem() {
        guard isPlaying else { return }
        isPlaying = false
        onExternalStop?()
    }
}
