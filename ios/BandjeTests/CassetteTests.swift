// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import Bandje

struct CassetteTests {
    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    /// The label colour: stored by name in `.bandje.json`, absent for the default, unknown names
    /// (a later version) read as the default; covers made before colours keep their key.
    @Test func tapeColour() throws {
        #expect(TapeColor(nil) == .red)
        #expect(TapeColor("teal") == .red)
        #expect(TapeColor("green") == .green)
        #expect(TapeColor.red.stored == nil)
        #expect(TapeColor.navy.stored == "navy")
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-colour-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var meta = RecordingMeta(created: Date(timeIntervalSince1970: 0))
        meta.color = TapeColor.blue.stored
        try meta.write(to: dir)
        #expect(String(decoding: try Data(contentsOf: RecordingMeta.url(in: dir)), as: UTF8.self).contains("\"color\" : \"blue\""))
        #expect(TapeColor(RecordingMeta.read(from: dir)?.color) == .blue)
        #expect(CoverArt.key(title: "A", duration: 60) == CoverArt.key(title: "A", duration: 60, color: .red))
        #expect(CoverArt.key(title: "A", duration: 60) != CoverArt.key(title: "A", duration: 60, color: .green))
    }

    @Test func reelsAtBeginning() {
        let r = Reels.radii(fraction: Reels.fraction(position: 0, duration: 750))
        #expect(close(r.left, Reels.full))
        #expect(close(r.right, Reels.core))
    }

    @Test func reelsInTheMiddle() {
        let r = Reels.radii(fraction: Reels.fraction(position: 375, duration: 750))
        #expect(close(r.left, r.right))
        // Half the tape area on each reel, so the radius is not simply the average.
        let expected = ((Reels.core * Reels.core + Reels.full * Reels.full) / 2).squareRoot()
        #expect(close(r.left, expected))
        #expect(r.left > (Reels.core + Reels.full) / 2)
    }

    @Test func reelsAtEnd() {
        let r = Reels.radii(fraction: Reels.fraction(position: 750, duration: 750))
        #expect(close(r.left, Reels.core))
        #expect(close(r.right, Reels.full))
    }

    @Test func zeroOrUnknownDuration() {
        #expect(Reels.fraction(position: 0, duration: 0) == 0)
        #expect(Reels.fraction(position: 12, duration: 0) == 0)
        #expect(Reels.fraction(position: .nan, duration: 10) == 0)
        #expect(Reels.fraction(position: 5, duration: .infinity) == 0)
        let r = Reels.radii(fraction: .nan)
        #expect(close(r.left, Reels.full) && close(r.right, Reels.core))
    }

    @Test func positionIsClamped() {
        #expect(Reels.fraction(position: -3, duration: 10) == 0)
        #expect(Reels.fraction(position: 30, duration: 10) == 1)
    }

    @Test func tapeAreaIsConserved() {
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            let r = Reels.radii(fraction: f)
            #expect(close(r.left * r.left + r.right * r.right, Reels.core * Reels.core + Reels.full * Reels.full, 1e-6))
        }
    }

    @Test func tapeMovesRightWithPosition() {
        var previous = Reels.radii(fraction: 0)
        for position in stride(from: 60.0, through: 750, by: 60) {
            let r = Reels.radii(fraction: Reels.fraction(position: position, duration: 750))
            #expect(r.left < previous.left && r.right > previous.right)
            previous = r
        }
    }

    @Test func rightReelGrowsWhileRecording() {
        #expect(Reels.recordingFraction(elapsed: 0) == 0)
        let oneMinute = Reels.recordingFraction(elapsed: 60)
        let halfHour = Reels.recordingFraction(elapsed: 1800)
        let twoHours = Reels.recordingFraction(elapsed: 7200)
        #expect(oneMinute > 0.02 && oneMinute < halfHour && halfHour < twoHours && twoHours < 1)
        #expect(close(halfHour, 1 - exp(-1)))
        let state = CassetteState(mode: .recording, position: 1800, duration: 0)
        #expect(close(state.fraction, halfHour))
    }

    @Test func spinTargets() {
        let now = Date()
        var state = CassetteState(mode: .stopped, position: 10, duration: 100)
        #expect(Reels.targetSpeed(state, at: now, reduceMotion: false) == 0)
        state.mode = .playing
        #expect(Reels.targetSpeed(state, at: now, reduceMotion: false) == 1)
        state.mode = .recordingPaused
        #expect(Reels.targetSpeed(state, at: now, reduceMotion: false) == 0)
        state.mode = .recording
        #expect(Reels.targetSpeed(state, at: now, reduceMotion: false) == 1)
        // A seek spins hard for a moment, in its direction, then back to normal.
        state.mode = .playing
        state.lastSeek = now
        #expect(Reels.targetSpeed(state, at: now.addingTimeInterval(0.1), reduceMotion: false) == Reels.seekSpeed)
        state.seekForward = false
        #expect(Reels.targetSpeed(state, at: now.addingTimeInterval(0.1), reduceMotion: false) == -Reels.seekSpeed)
        #expect(Reels.targetSpeed(state, at: now.addingTimeInterval(1), reduceMotion: false) == 1)
        // Reduce Motion: never spins.
        #expect(Reels.targetSpeed(state, at: now.addingTimeInterval(0.1), reduceMotion: true) == 0)
    }

    @Test func spinUpAndDownAreGradual() {
        var speed = 0.0
        speed = Reels.eased(speed, toward: 1, dt: 1.0 / 60)
        #expect(speed > 0 && speed < 0.2)
        for _ in 0..<24 { speed = Reels.eased(speed, toward: 1, dt: 1.0 / 60) }  // 0.42 s
        #expect(speed > 0.94 && speed < 1)
        // Frame-rate independent: two half steps equal one whole step.
        let half = Reels.eased(Reels.eased(0, toward: 1, dt: 0.05), toward: 1, dt: 0.05)
        #expect(close(half, Reels.eased(0, toward: 1, dt: 0.1)))
    }

    @MainActor @Test func motionFollowsState() {
        let motion = ReelMotion()
        let start = Date()
        let state = CassetteState(mode: .playing, position: 0, duration: 100)
        for i in 0...60 { motion.advance(to: start.addingTimeInterval(Double(i) / 60), state: state, reduceMotion: false) }
        #expect(motion.speed > 0.99)
        // Both reels turn counter-clockwise; the empty (small) right reel turns faster.
        #expect(motion.leftAngle < 0 && motion.rightAngle < motion.leftAngle)

        let reduced = ReelMotion()
        for i in 0...60 { reduced.advance(to: start.addingTimeInterval(Double(i) / 60), state: state, reduceMotion: true) }
        #expect(reduced.speed == 0 && reduced.leftAngle == 0 && reduced.rightAngle == 0)
    }

    @Test func meterCurve() {
        #expect(Reels.meter(0) == 0)
        #expect(Reels.meter(1) == 1)
        #expect(Reels.meter(-1) == 0)
        #expect(Reels.meter(0.03) > 0.25)
    }
}
