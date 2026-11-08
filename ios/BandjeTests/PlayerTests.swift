// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
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

    private func advance(rate: Float, after seconds: Double) async throws -> Double {
        let recording = try copy()
        let player = Player.shared
        player.volume = 0
        player.unload()
        player.load(recording)
        player.setRate(rate)
        player.play()
        try await Task.sleep(for: .seconds(seconds))
        player.pause()
        defer { player.setRate(1); player.unload() }
        return player.currentTime
    }

    @Test func doubleSpeedAdvancesTwiceAsFast() async throws {
        let normal = try await advance(rate: 1, after: 2)
        let double = try await advance(rate: 2, after: 2)
        #expect(normal > 1.5 && normal < 2.6)
        #expect(double > normal * 1.6)
    }

    @Test func changingSpeedWhilePlaying() async throws {
        let recording = try copy()
        let player = Player.shared
        player.volume = 0
        player.unload()
        player.load(recording)
        player.play()
        try await Task.sleep(for: .seconds(1))
        let start = player.currentTime
        player.setRate(2)
        try await Task.sleep(for: .seconds(2))
        player.pause()
        let advanced = player.currentTime - start
        player.setRate(1)
        player.unload()
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
