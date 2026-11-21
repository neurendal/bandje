// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BandjeKit
import Foundation
import Testing
@testable import Bandje

/// Playback speed: the position must advance faster at 2× than at 1×.
@MainActor @Suite(.serialized)
struct PlayerTests {
    /// The fixture in a folder of its own (playing makes its cover next to it).
    private func copy() throws -> Recording {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-player-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let audio = dir.appending(path: "import_nl.m4a")
        try FileManager.default.copyItem(at: ImportTests.fixtures.appending(path: "import_nl.m4a"), to: audio)
        return Recording(folder: dir, audio: audio, date: .now, duration: 30, markers: [])
    }

    /// A player of its own (silent, positions in a throwaway suite), as the app's (BandjeKit).
    private func makePlayer() -> (PlayerModel, AVAudioPlayerEngine) {
        let engine = AVAudioPlayerEngine()
        engine.volume = 0
        let defaults = UserDefaults(suiteName: "bandje-tests-\(UUID().uuidString)")!
        return (PlayerModel(engine: engine, store: PlaybackPositionStore(defaults: defaults)), engine)
    }

    private func advance(rate: Float, after seconds: Double) async throws -> Double {
        let recording = try copy()
        let (player, _) = makePlayer()
        player.rate = rate
        await player.play(try #require(recording.playable), at: 0).value
        try await Task.sleep(for: .seconds(seconds))
        player.pause(reason: .user)
        defer { player.stop() }
        return player.currentTime
    }

    @Test func doubleSpeedAdvancesTwiceAsFast() async throws {
        let normal = try await advance(rate: 1, after: 2)
        let double = try await advance(rate: 2, after: 2)
        #expect(normal > 1.5 && normal < 2.6)
        #expect(double > normal * 1.6)
    }

    /// P14: a new speed applies at once.
    @Test func changingSpeedWhilePlaying() async throws {
        let recording = try copy()
        let (player, _) = makePlayer()
        await player.play(try #require(recording.playable), at: 0).value
        try await Task.sleep(for: .seconds(1))
        let start = player.currentTime
        player.rate = 2
        try await Task.sleep(for: .seconds(2))
        player.pause(reason: .user)
        let advanced = player.currentTime - start
        player.stop()
        #expect(advanced > 3.2)
    }

    @Test func speakerProgressKeepsMovingButNeverFinishes() {
        let estimate = Transcriber.estimatedWhoSeconds(duration: 600, firstTime: false)
        #expect(abs(estimate - 18) < 0.001)
        #expect(abs(Transcriber.estimatedWhoSeconds(duration: 600, firstTime: true) - 73) < 0.001)
        var last = -1.0
        for t in stride(from: 0.0, through: 300, by: 1) {
            let f = Transcriber.whoFraction(elapsed: t, estimate: estimate)
            #expect(f >= last && f < 0.99)
            last = f
        }
        #expect(abs(Transcriber.whoFraction(elapsed: 9, estimate: 18) - 0.475) < 0.001)
    }
}
