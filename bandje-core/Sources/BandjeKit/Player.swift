// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

// The one player of the app (specs/player.md). Views read `current` and `currentTime` and call the
// commands; they never own an audio player. Rule numbers P1 to P16 refer to spec section 4.

/// Identifies a recording across renames, iCloud moves and devices: when it was created (to the
/// second, `created` in its `.bandje.json`) and its length in whole seconds (owner, 2026-11-08).
public struct RecordingID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let created: Int
    public let duration: Int

    public init(created: Date, duration: TimeInterval) {
        self.created = Int(created.timeIntervalSince1970.rounded(.down))
        self.duration = Int(duration.rounded())
    }

    public var key: String { "\(created)-\(duration)" }
    public var description: String { key }
}

/// What the player plays: one recording's audio file and what Now Playing shows.
public struct PlayableItem: Equatable, Sendable {
    public var id: RecordingID
    public var title: String
    public var url: URL
    public var duration: TimeInterval
    /// The cover for Now Playing (lock screen, Control Center); nil = none.
    public var artwork: URL?

    public init(id: RecordingID, title: String, url: URL, duration: TimeInterval, artwork: URL? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.duration = duration
        self.artwork = artwork
    }
}

/// Why playback could not start. The apps word it for the user.
public enum PlayerFailure: Equatable, Sendable {
    /// The file is in iCloud and could not be downloaded (P13).
    case notDownloaded(String)
    /// The file is there but can't be played.
    case unplayable(String)
}

@MainActor @Observable
public final class PlayerModel {
    public enum State: Equatable, Sendable {
        case idle, loading, playing, paused
        case failed(PlayerFailure)
    }

    public enum PauseReason: Equatable, Sendable {
        case user, recordingStarted, dictationStarted, interruption, routeChange
    }

    public nonisolated static let skipInterval: TimeInterval = 15
    public nonisolated static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    /// P15: the position is saved at least this often while playing.
    public nonisolated static let saveInterval: TimeInterval = 5
    /// P16: a saved position this close to the end resumes from the start.
    public nonisolated static let restartWindow: TimeInterval = 5

    public private(set) var current: PlayableItem?
    public private(set) var state: State = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// Global, persisted, applies at once to whatever plays (P14).
    public var rate: Float {
        didSet {
            engine.rate = rate
            store.rate = rate
        }
    }
    public private(set) var lastPauseReason: PauseReason?
    /// Set by seeks: the cassette spins fast for a moment, in the seek's direction.
    public private(set) var lastSeek = Date.distantPast
    public private(set) var lastSeekForward = true
    /// Counts seeks, so Now Playing can follow them without observing `currentTime`.
    public private(set) var seekCount = 0

    public var isPlaying: Bool { state == .playing }

    /// Asked before playback starts; false keeps the player paused (iOS: not while recording).
    @ObservationIgnored public var shouldStartPlayback: @MainActor () -> Bool = { true }
    /// Called right before playback starts (iOS: activates the audio session).
    @ObservationIgnored public var willStartPlayback: @MainActor () -> Void = {}

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let store: PlaybackPositionStore
    @ObservationIgnored private let prepare: @MainActor (URL) async throws -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    /// The engine holds `current`'s file.
    @ObservationIgnored private var loaded = false
    /// The latest load; an older one that finishes later (a download) is dropped.
    @ObservationIgnored private var loadGeneration = 0
    /// False when the user paused while the file was still loading.
    @ObservationIgnored private var playAfterLoad = true
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var resumeAfterInterruption = false
    /// The engine stopped by itself (iOS stops the audio before the interruption is reported).
    @ObservationIgnored private var stoppedBySystem = false
    /// Where the next load starts: set by `cue(_:at:)` and by a seek while the file loads.
    @ObservationIgnored private var cuedTime: TimeInterval?

    /// - Parameters:
    ///   - prepare: makes the file local before it is loaded (iCloud download, P13).
    ///   - now: the clock for the regular save (P15); tests pass their own.
    public init(engine: AudioEngine, store: PlaybackPositionStore,
                prepare: @escaping @MainActor (URL) async throws -> Void = { _ in },
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.engine = engine
        self.store = store
        self.prepare = prepare
        self.now = now
        rate = store.rate
        engine.rate = rate
        engine.onTime = { [weak self] time in self?.engineTime(time) }
        engine.onEnd = { [weak self] in self?.engineEnded() }
        engine.onExternalStop = { [weak self] in self?.engineStoppedBySystem() }
        engine.onFailure = { [weak self] error in self?.engineFailed(error) }
    }

    // MARK: Commands

    /// Plays `item`. `time` nil resumes its saved position (P3, P16); a time plays from there (P5).
    /// Another recording replaces the current one after saving its position (P3).
    @discardableResult
    public func play(_ item: PlayableItem, at time: TimeInterval? = nil) -> Task<Void, Never> {
        if current?.id == item.id, loaded, state != .loading {
            current = item
            if let time { seek(to: time) }
            return resume()
        }
        if current?.id != item.id {
            savePosition()  // P3
        }
        unloadEngine()
        current = item
        duration = item.duration
        currentTime = time ?? store.position(for: item.id) ?? 0
        store.lastPlayed = item.id
        return load(item, at: time)
    }

    @discardableResult
    public func togglePlayPause() -> Task<Void, Never> {
        if state == .playing || state == .loading {
            pause(reason: .user)
            return Task {}
        }
        return resume()
    }

    public func pause(reason: PauseReason) {
        lastPauseReason = reason
        if reason != .interruption { resumeAfterInterruption = false }
        stoppedBySystem = false
        switch state {
        case .loading:
            playAfterLoad = false
        case .playing:
            engine.pause()
            currentTime = engine.currentTime
            state = .paused
            savePosition()  // P15
        default:
            break
        }
    }

    public func seek(to time: TimeInterval) {
        guard current != nil else { return }
        let target = min(max(0, time), max(0, duration))
        lastSeekForward = target >= currentTime
        if loaded {
            engine.seek(to: target)
        } else {
            // While loading, the load starts here; otherwise the saved position below is used.
            cuedTime = state == .loading ? target : nil
        }
        currentTime = target
        lastSeek = now()
        seekCount += 1
        if state != .loading { savePosition() }  // P15
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    /// Clears the current recording and hides the mini player (the ✕); nothing restores at relaunch.
    public func stop() {
        savePosition()
        unloadEngine()
        clearCurrent()
    }

    /// The recording was deleted, here or by iCloud sync (P9).
    public func itemWasRemoved(id: RecordingID) {
        store.removePosition(for: id)
        if store.lastPlayed == id { store.lastPlayed = nil }
        guard current?.id == id else { return }
        unloadEngine()
        clearCurrent()
    }

    /// The recording was renamed or moved by iCloud: new URL and title; playback goes on.
    public func itemWasMoved(id: RecordingID, to item: PlayableItem) {
        guard current?.id == id else { return }
        current = item
    }

    /// Saves the position now: the app goes to the background or quits (P15).
    public func saveNow() {
        savePosition()
    }

    // MARK: System events (AudioSessionController on iOS)

    /// An interruption began (call, Siri, other audio): pause (P11).
    public func interruptionBegan() {
        let wasPlaying = state == .playing || stoppedBySystem
        pause(reason: .interruption)
        resumeAfterInterruption = wasPlaying
    }

    /// Resumes only when the system says so and we were playing; a pause for another reason
    /// in between (the user, a recording) wins (P11, P7).
    public func interruptionEnded(shouldResume: Bool) {
        defer { resumeAfterInterruption = false }
        guard shouldResume, resumeAfterInterruption, lastPauseReason == .interruption,
              state == .paused, loaded else { return }
        startEngine()
    }

    /// Headphones or another output were disconnected (P10).
    public func outputDeviceRemoved() {
        pause(reason: .routeChange)
    }

    // MARK: Relaunch (P12)

    /// Restores the last played recording, paused at its saved position, without loading it.
    /// `resolve` finds the recording by ID; nil (deleted, file missing) restores nothing.
    public func restore(resolve: (RecordingID) -> PlayableItem?) {
        guard current == nil, let id = store.lastPlayed else { return }
        guard let item = resolve(id) else {
            store.lastPlayed = nil
            return
        }
        current = item
        duration = item.duration
        currentTime = store.position(for: id) ?? 0
        state = .paused
    }

    /// Shows `item` paused at `time` (nil: its saved position) without loading it and without
    /// saving anything: screenshots and selftests. Play starts there.
    public func cue(_ item: PlayableItem, at time: TimeInterval? = nil) {
        unloadEngine()
        current = item
        duration = item.duration
        currentTime = time ?? store.position(for: item.id) ?? 0
        cuedTime = time
        state = .paused
    }

    // MARK: Questions views ask

    /// Where `id` would resume (P3), for a recording that is not the current one; nil = from the start.
    public func savedPosition(for id: RecordingID) -> TimeInterval? {
        current?.id == id ? currentTime : store.position(for: id)
    }

    /// P6: the mini player shows unless the screen shows the playing recording itself.
    public func showsMiniPlayer(detail: RecordingID?) -> Bool {
        guard let current else { return false }
        return current.id != detail
    }

    /// The position to highlight in `id`'s transcript: only when `id` is the current recording.
    public func time(in id: RecordingID) -> TimeInterval? {
        current?.id == id ? currentTime : nil
    }

    // MARK: Private

    private func resume() -> Task<Void, Never> {
        guard let current else { return Task {} }
        if !loaded || state == .loading {
            return load(current, at: cuedTime)
        }
        guard state != .playing else { return Task {} }
        // Ended (P4): from the start.
        if currentTime >= duration - 0.05 { seek(to: 0) }
        startEngine()
        return Task {}
    }

    private func load(_ item: PlayableItem, at time: TimeInterval?) -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        cuedTime = nil
        playAfterLoad = true
        state = .loading
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await prepare(item.url)  // P13
            } catch {
                guard generation == loadGeneration else { return }
                state = .failed(.notDownloaded(error.localizedDescription))
                return
            }
            guard generation == loadGeneration else { return }
            let length: TimeInterval
            do {
                length = try engine.load(item.url)
            } catch {
                state = .failed(.unplayable(error.localizedDescription))
                return
            }
            loaded = true
            duration = length
            // A seek while loading wins over where the load was asked to start.
            let asked = cuedTime ?? time
            cuedTime = nil
            var start = asked ?? store.position(for: item.id) ?? 0
            if asked == nil, start >= length - Self.restartWindow { start = 0 }  // P16
            start = min(max(0, start), length)
            engine.rate = rate
            engine.seek(to: start)
            currentTime = start
            if playAfterLoad {
                startEngine()
            } else {
                state = .paused
            }
        }
    }

    private func startEngine() {
        guard shouldStartPlayback() else {
            state = .paused
            return
        }
        willStartPlayback()
        stoppedBySystem = false
        if engine.play() {
            state = .playing
            lastSave = now()
        } else {
            state = .failed(.unplayable(""))
        }
    }

    private func unloadEngine() {
        engine.unload()
        loaded = false
        loadGeneration += 1
    }

    private func clearCurrent() {
        current = nil
        state = .idle
        currentTime = 0
        duration = 0
        lastPauseReason = nil
        resumeAfterInterruption = false
        stoppedBySystem = false
        cuedTime = nil
        store.lastPlayed = nil
    }

    private func savePosition() {
        guard let current, state != .loading else { return }
        if case .failed = state { return }
        store.setPosition(loaded ? engine.currentTime : currentTime, for: current.id)
        lastSave = now()
    }

    private func engineTime(_ time: TimeInterval) {
        currentTime = time
        if now().timeIntervalSince(lastSave) >= Self.saveInterval { savePosition() }  // P15
    }

    /// P4: stop at the end, paused; the saved position starts over; no next recording.
    private func engineEnded() {
        guard let current else { return }
        currentTime = duration
        state = .paused
        lastPauseReason = nil
        store.removePosition(for: current.id)
    }

    private func engineStoppedBySystem() {
        guard state == .playing else { return }
        currentTime = engine.currentTime
        state = .paused
        stoppedBySystem = true
        lastPauseReason = .interruption
        savePosition()
    }

    private func engineFailed(_ error: Error) {
        state = .failed(.unplayable(error.localizedDescription))
    }
}
