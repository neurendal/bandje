// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import BandjeKit

// specs/player.md section 4, rules P1 to P16, with the fake engine. Each test names its rule.
// UI-only parts (where the mini player sits, tapping it) are on the manual checklist (spec 6).

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// Stands in for the iCloud download (P13): instant, blocking until released, or failing.
@MainActor
final class Downloads {
    var blocking = false
    var failure: Error?
    private(set) var asked: [URL] = []
    private var waiting: [CheckedContinuation<Void, Error>] = []

    func prepare(_ url: URL) async throws {
        asked.append(url)
        if let failure { throw failure }
        guard blocking else { return }
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    func release() {
        let all = waiting
        waiting = []
        all.forEach { $0.resume() }
    }

    var isWaiting: Bool { !waiting.isEmpty }
}

@MainActor
final class FakeRecorder {
    var isActive = true
}

struct DownloadFailed: LocalizedError {
    var errorDescription: String? { "The Internet connection appears to be offline." }
}

@MainActor
final class Harness {
    let engine = FakeAudioEngine()
    let suite = "BandjeKitTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: PlaybackPositionStore
    let clock = TestClock()
    let downloads = Downloads()
    let player: PlayerModel

    init() {
        defaults = UserDefaults(suiteName: suite)!
        store = PlaybackPositionStore(defaults: defaults)
        player = Self.makePlayer(engine: engine, store: store, clock: clock, downloads: downloads)
    }

    /// A second player on the same storage: the app after a relaunch.
    func relaunched() -> (PlayerModel, FakeAudioEngine) {
        let engine = FakeAudioEngine()
        return (Self.makePlayer(engine: engine, store: PlaybackPositionStore(defaults: defaults),
                                clock: clock, downloads: downloads), engine)
    }

    static func makePlayer(engine: FakeAudioEngine, store: PlaybackPositionStore, clock: TestClock,
                           downloads: Downloads) -> PlayerModel {
        PlayerModel(engine: engine, store: store,
                    prepare: { try await downloads.prepare($0) },
                    now: { clock.now })
    }

    func item(_ n: Int, duration: TimeInterval = 60) -> PlayableItem {
        let url = URL(filePath: "/recordings/Recording \(n)/Recording \(n).m4a")
        engine.durations[url] = duration
        return PlayableItem(id: RecordingID(created: Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 3600), duration: duration),
                            title: "Recording \(n)", url: url, duration: duration)
    }

    /// Wall-clock seconds pass while playing.
    func play(for seconds: TimeInterval) {
        clock.now += seconds
        engine.advance(by: seconds)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor @Suite("PlayerModel: specs/player.md P1 to P16")
struct PlayerTests {
    // MARK: P1, P2, P6: one player for the app

    @Test("P1: navigating to another screen keeps playing, the mini player shows")
    func p1KeepsPlaying() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        // The detail now shows b (or the list: nil); the player does not care.
        #expect(h.player.state == .playing)
        #expect(h.player.showsMiniPlayer(detail: b.id))
        #expect(h.player.showsMiniPlayer(detail: nil))
        h.play(for: 3)
        #expect(h.player.currentTime == 3)
    }

    @Test("P2: the mini player stands for the playing recording, not the last one viewed")
    func p2CurrentIsThePlayingRecording() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        _ = h.player.showsMiniPlayer(detail: b.id)  // viewing b
        #expect(h.player.current?.id == a.id)
    }

    @Test("P6: no mini player while the playing recording's detail is on screen")
    func p6HiddenOnItsOwnDetail() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        #expect(!h.player.showsMiniPlayer(detail: nil))  // nothing playing
        await h.player.play(a).value
        #expect(!h.player.showsMiniPlayer(detail: a.id))
        #expect(h.player.showsMiniPlayer(detail: b.id))
        h.player.pause(reason: .user)
        #expect(!h.player.showsMiniPlayer(detail: a.id))
        #expect(h.player.showsMiniPlayer(detail: nil))  // paused still shows
    }

    @Test("Transcript highlighting follows the time only in the current recording")
    func highlightOnlyInCurrent() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        h.play(for: 7)
        #expect(h.player.time(in: a.id) == 7)
        #expect(h.player.time(in: b.id) == nil)
    }

    // MARK: P3, P4, P5: switching and the end

    @Test("P3: playing another recording saves the previous one's position; back to it resumes there")
    func p3SwitchSavesAndResumes() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        h.play(for: 20)
        await h.player.play(b).value
        #expect(h.player.current?.id == b.id)
        #expect(h.player.currentTime == 0)
        #expect(h.store.position(for: a.id) == 20)
        h.play(for: 4)
        await h.player.play(a).value
        #expect(h.player.currentTime == 20)
        #expect(h.player.state == .playing)
        #expect(h.store.position(for: b.id) == 4)
    }

    @Test("P4: at the end it stops, paused, saved position back to 0, no next recording")
    func p4StopsAtTheEnd() async {
        let h = Harness()
        let a = h.item(1, duration: 30)
        _ = h.item(2)
        await h.player.play(a).value
        h.play(for: 10)
        h.player.saveNow()
        h.play(for: 25)
        #expect(h.player.state == .paused)
        #expect(h.player.current?.id == a.id)
        #expect(h.player.currentTime == 30)
        #expect(h.store.position(for: a.id) == nil)
        #expect(!h.engine.isPlaying)
        // Play again: from the start.
        await h.player.togglePlayPause().value
        #expect(h.player.state == .playing)
        #expect(h.player.currentTime == 0)
    }

    @Test("P5: tapping a sentence in another recording switches and plays from that sentence")
    func p5SentenceInAnotherRecording() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        h.play(for: 12)
        await h.player.play(b, at: 42.5).value
        #expect(h.player.current?.id == b.id)
        #expect(h.player.currentTime == 42.5)
        #expect(h.engine.currentTime == 42.5)
        #expect(h.player.state == .playing)
        #expect(h.store.position(for: a.id) == 12)
    }

    @Test("P5: tapping a sentence in the playing recording seeks there")
    func p5SentenceInCurrent() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        h.player.pause(reason: .user)
        await h.player.play(a, at: 33).value
        #expect(h.player.currentTime == 33)
        #expect(h.player.state == .playing)
    }

    // MARK: P7, P8: recording and dictation

    @Test("P7, P8: starting a recording or dictation pauses, and nothing resumes it afterwards",
          arguments: [PlayerModel.PauseReason.recordingStarted, .dictationStarted])
    func p7p8PauseWithoutResume(reason: PlayerModel.PauseReason) async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.play(for: 5)
        h.player.pause(reason: reason)
        #expect(h.player.state == .paused)
        #expect(h.player.lastPauseReason == reason)
        #expect(h.store.position(for: h.item(1).id) == 5)
        // An interruption ending with "should resume" does not undo it.
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .paused)
    }

    @Test("P7: while recording, playback does not start (iOS)")
    func p7NoPlaybackWhileRecording() async {
        let h = Harness()
        let recorder = FakeRecorder()
        h.player.shouldStartPlayback = { !recorder.isActive }
        await h.player.play(h.item(1)).value
        #expect(h.player.state == .paused)
        #expect(!h.engine.isPlaying)
        recorder.isActive = false
        await h.player.togglePlayPause().value
        #expect(h.player.state == .playing)
    }

    @Test("P8: pausing for dictation while paused changes nothing")
    func p8AlreadyPaused() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.pause(reason: .user)
        h.player.pause(reason: .dictationStarted)
        #expect(h.player.state == .paused)
    }

    // MARK: P9: deleted

    @Test("P9: the playing recording is deleted: stop, mini player gone, position removed")
    func p9PlayingRecordingRemoved() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        h.play(for: 9)
        h.player.saveNow()
        h.player.itemWasRemoved(id: a.id)
        #expect(h.player.current == nil)
        #expect(h.player.state == .idle)
        #expect(!h.player.showsMiniPlayer(detail: nil))
        #expect(h.store.position(for: a.id) == nil)
        #expect(h.store.lastPlayed == nil)
        #expect(h.engine.loadedURL == nil)
    }

    @Test("P9: another recording is deleted: playback goes on, its position is removed")
    func p9OtherRecordingRemoved() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(b).value
        h.play(for: 6)
        await h.player.play(a).value
        h.player.itemWasRemoved(id: b.id)
        #expect(h.player.current?.id == a.id)
        #expect(h.player.state == .playing)
        #expect(h.store.position(for: b.id) == nil)
    }

    @Test("Renamed or moved by iCloud: same recording, new URL and title, keeps playing")
    func movedKeepsPlaying() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        var renamed = a
        renamed.title = "Client call"
        renamed.url = URL(filePath: "/recordings/Client call/Client call.m4a")
        h.player.itemWasMoved(id: a.id, to: renamed)
        #expect(h.player.current?.title == "Client call")
        #expect(h.player.state == .playing)
    }

    // MARK: P10, P11: route changes and interruptions

    @Test("P10: headphones disconnected: pause, and it stays paused")
    func p10RouteChangePauses() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.outputDeviceRemoved()
        #expect(h.player.state == .paused)
        #expect(h.player.lastPauseReason == .routeChange)
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .paused)
    }

    @Test("P11: interruption while playing, system says resume: plays again")
    func p11ResumesWhenAsked() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.interruptionBegan()
        #expect(h.player.state == .paused)
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .playing)
        #expect(h.engine.isPlaying)
    }

    @Test("P11: interruption ends without shouldResume: stays paused")
    func p11NoResumeWithoutPermission() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.interruptionBegan()
        h.player.interruptionEnded(shouldResume: false)
        #expect(h.player.state == .paused)
    }

    @Test("P11: interruption while paused: nothing starts afterwards")
    func p11WasNotPlaying() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.pause(reason: .user)
        h.player.interruptionBegan()
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .paused)
    }

    @Test("P11: the user pauses during the interruption: no resume")
    func p11UserPauseWins() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.interruptionBegan()
        h.player.pause(reason: .user)
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .paused)
    }

    @Test("P11: the system stops the audio before it reports the interruption: still resumes")
    func p11StoppedBeforeReported() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.play(for: 8)
        h.engine.stopBySystem()
        #expect(h.player.state == .paused)
        #expect(h.store.position(for: h.item(1).id) == 8)
        h.player.interruptionBegan()
        h.player.interruptionEnded(shouldResume: true)
        #expect(h.player.state == .playing)
    }

    // MARK: P12: relaunch

    @Test("P12: after a relaunch the last recording is back, paused at its position")
    func p12RestoresPaused() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        h.player.rate = 1.5
        h.play(for: 14)
        h.player.saveNow()  // the app goes to the background

        let (player, engine) = h.relaunched()
        player.restore { $0 == a.id ? a : nil }
        #expect(player.current?.id == a.id)
        #expect(player.state == .paused)
        #expect(player.currentTime == 21)  // 14 s at 1.5×
        #expect(player.rate == 1.5)
        #expect(player.showsMiniPlayer(detail: nil))
        #expect(engine.loadedURL == nil)  // nothing loaded (or downloaded) at launch
        await player.togglePlayPause().value
        #expect(player.state == .playing)
        #expect(engine.currentTime == 21)
        #expect(engine.rate == 1.5)
    }

    @Test("P12: the last recording is gone (missing file): nothing restored")
    func p12NothingWhenMissing() async {
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.saveNow()
        let (player, _) = h.relaunched()
        player.restore { _ in nil }
        #expect(player.current == nil)
        #expect(player.state == .idle)
        #expect(h.store.lastPlayed == nil)
    }

    @Test("P12: after Stop (the ✕) nothing is restored")
    func p12NothingAfterStop() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        h.play(for: 5)
        h.player.stop()
        #expect(h.player.current == nil)
        #expect(h.store.position(for: a.id) == 5)  // the position stays for the next time
        let (player, _) = h.relaunched()
        player.restore { _ in a }
        #expect(player.current == nil)
    }

    // MARK: Cue (selftest, screenshots) and the saved position views show

    @Test("cue: paused at the given time, nothing loaded or saved; play starts there")
    func cueStartsThere() async {
        let h = Harness()
        let a = h.item(1)
        h.player.cue(a, at: 20)
        #expect(h.player.current?.id == a.id)
        #expect(h.player.state == .paused)
        #expect(h.player.currentTime == 20)
        #expect(h.engine.loadedURL == nil)
        #expect(h.store.position(for: a.id) == nil)
        #expect(h.store.lastPlayed == nil)
        await h.player.togglePlayPause().value
        #expect(h.player.state == .playing)
        #expect(h.engine.currentTime == 20)
    }

    @Test("cue over another cued recording saves nothing for either")
    func cueTwiceSavesNothing() {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        h.player.cue(a, at: 24)
        h.player.cue(b, at: 10)
        #expect(h.store.position(for: a.id) == nil)
        #expect(h.store.position(for: b.id) == nil)
    }

    @Test("cue, then seek: play starts at the seek")
    func cueThenSeek() async {
        let h = Harness()
        let a = h.item(1)
        h.player.cue(a, at: 20)
        h.player.seek(to: 30)
        await h.player.togglePlayPause().value
        #expect(h.engine.currentTime == 30)
    }

    @Test("P3: the saved position of another recording, for its detail view")
    func savedPositionForViews() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        #expect(h.player.savedPosition(for: a.id) == nil)
        await h.player.play(a).value
        h.play(for: 12)
        #expect(h.player.savedPosition(for: a.id) == 12)  // current: the live time
        await h.player.play(b).value
        #expect(h.player.savedPosition(for: a.id) == 12)
    }

    // MARK: P13: iCloud placeholder

    @Test("P13: file still in iCloud: loading while it downloads, then plays")
    func p13DownloadsThenPlays() async {
        let h = Harness()
        let a = h.item(1)
        h.downloads.blocking = true
        let task = h.player.play(a)
        #expect(h.player.state == .loading)
        #expect(h.player.current?.id == a.id)
        while !h.downloads.isWaiting { await Task.yield() }
        h.downloads.release()
        await task.value
        #expect(h.player.state == .playing)
        #expect(h.downloads.asked == [a.url])
    }

    @Test("P13: the download fails: failed, with the reason")
    func p13DownloadFails() async {
        let h = Harness()
        h.downloads.failure = DownloadFailed()
        await h.player.play(h.item(1)).value
        #expect(h.player.state == .failed(.notDownloaded("The Internet connection appears to be offline.")))
        #expect(h.player.current != nil)  // the mini player shows the error
        // Trying again after the problem is gone works.
        h.downloads.failure = nil
        await h.player.togglePlayPause().value
        #expect(h.player.state == .playing)
    }

    @Test("P13: a file that can't be opened: failed, unplayable")
    func p13Unplayable() async {
        let h = Harness()
        let a = h.item(1)
        h.engine.unplayable = [a.url]
        await h.player.play(a).value
        #expect(h.player.state == .failed(.unplayable("Can't open the file")))
    }

    @Test("P13: another recording chosen while the first still downloads: the first is dropped")
    func p13StaleDownloadDropped() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        h.downloads.blocking = true
        let first = h.player.play(a)
        while !h.downloads.isWaiting { await Task.yield() }
        h.downloads.blocking = false
        await h.player.play(b).value
        h.downloads.release()
        await first.value
        #expect(h.player.current?.id == b.id)
        #expect(h.engine.loadedURL == b.url)
        #expect(h.player.state == .playing)
    }

    @Test("P13: paused while downloading: loads, but does not start")
    func p13PausedWhileLoading() async {
        let h = Harness()
        h.downloads.blocking = true
        let task = h.player.play(h.item(1))
        while !h.downloads.isWaiting { await Task.yield() }
        h.player.pause(reason: .recordingStarted)
        h.downloads.release()
        await task.value
        #expect(h.player.state == .paused)
        #expect(!h.engine.isPlaying)
    }

    @Test("P13: a seek while downloading is where playback starts")
    func p13SeekWhileLoading() async {
        let h = Harness()
        let a = h.item(1)
        h.downloads.blocking = true
        let task = h.player.play(a, at: 10)
        while !h.downloads.isWaiting { await Task.yield() }
        h.player.seek(to: 42)
        #expect(h.player.currentTime == 42)
        h.downloads.release()
        await task.value
        #expect(h.player.state == .playing)
        #expect(h.engine.currentTime == 42)
        #expect(h.player.currentTime == 42)
    }

    @Test("P13: paused and seeked while downloading: loads there, paused")
    func p13SeekWhilePausedLoading() async {
        let h = Harness()
        h.downloads.blocking = true
        let task = h.player.play(h.item(1))
        while !h.downloads.isWaiting { await Task.yield() }
        h.player.pause(reason: .user)
        h.player.seek(to: 30)
        h.downloads.release()
        await task.value
        #expect(h.player.state == .paused)
        #expect(h.engine.currentTime == 30)
        #expect(h.player.savedPosition(for: h.item(1).id) == 30)
    }

    // MARK: P14: speed

    @Test("P14: a speed change applies at once and to every recording, and is remembered")
    func p14GlobalRate() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        h.player.rate = 2
        #expect(h.engine.rate == 2)
        h.play(for: 5)
        #expect(h.player.currentTime == 10)
        await h.player.play(b).value
        #expect(h.engine.rate == 2)
        #expect(h.store.rate == 2)
        #expect(h.relaunched().0.rate == 2)
    }

    @Test("Speeds are 0.5 to 2 (owner, 2026-11-08); skips are 15 s")
    func speedsAndSkips() async {
        #expect(PlayerModel.rates == [0.5, 0.75, 1, 1.25, 1.5, 2])
        let h = Harness()
        await h.player.play(h.item(1)).value
        h.player.skip(by: PlayerModel.skipInterval)
        #expect(h.player.currentTime == 15)
        h.player.skip(by: -PlayerModel.skipInterval * 2)
        #expect(h.player.currentTime == 0)
        h.player.skip(by: 1000)
        #expect(h.player.currentTime == 60)
    }

    // MARK: P15: saving the position

    @Test("P15: saved on pause, seek, switch and when the app goes to the background")
    func p15SavedOnEvents() async {
        let h = Harness()
        let a = h.item(1), b = h.item(2)
        await h.player.play(a).value
        h.play(for: 2)
        h.player.pause(reason: .user)
        #expect(h.store.position(for: a.id) == 2)
        h.player.seek(to: 30)
        #expect(h.store.position(for: a.id) == 30)
        await h.player.togglePlayPause().value
        h.play(for: 3)
        h.player.saveNow()
        #expect(h.store.position(for: a.id) == 33)
        h.play(for: 1)
        await h.player.play(b).value
        #expect(h.store.position(for: a.id) == 34)
    }

    @Test("P15: saved every 5 seconds while playing")
    func p15SavedRegularly() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a).value
        h.play(for: 4)
        #expect(h.store.position(for: a.id) == nil)
        h.play(for: 1)
        #expect(h.store.position(for: a.id) == 5)
        h.play(for: 4)
        #expect(h.store.position(for: a.id) == 5)
        h.play(for: 1)
        #expect(h.store.position(for: a.id) == 10)
    }

    // MARK: P16: near the end

    @Test("P16: a saved position in the last 5 seconds resumes from the start",
          arguments: [(54.0, 54.0), (55.5, 0.0), (59.0, 0.0)])
    func p16NearTheEnd(saved: Double, expected: Double) async {
        let h = Harness()
        let a = h.item(1)
        h.store.setPosition(saved, for: a.id)
        await h.player.play(a).value
        #expect(h.player.currentTime == expected)
    }

    @Test("P16: an explicit time near the end (a tapped sentence) is kept")
    func p16ExplicitTimeKept() async {
        let h = Harness()
        let a = h.item(1)
        await h.player.play(a, at: 57).value
        #expect(h.player.currentTime == 57)
    }

    // MARK: Identity and storage

    @Test("RecordingID: created to the second plus whole seconds; the same after a rename")
    func recordingID() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.75)
        let id = RecordingID(created: date, duration: 59.6)
        #expect(id.key == "1700000000-60")
        #expect(RecordingID(created: Date(timeIntervalSince1970: 1_700_000_000.1), duration: 60.4) == id)
        #expect(RecordingID(created: date, duration: 61) != id)
    }
}
