// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import ImageIO
import Foundation
import MediaPlayer
import Testing
@testable import BandjeKit

@MainActor @Suite("AVAudioPlayerEngine and Now Playing", .serialized)
struct EngineTests {
    /// A short stereo tone, left and right different (as a Mac recording: microphone left, system right).
    private func tone(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "bandjekit-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = 0.1 * sin(Float(i) * 0.05)
            buffer.floatChannelData![1][i] = 0.1 * sin(Float(i) * 0.08)
        }
        try file.write(from: buffer)
        return url
    }

    @Test("P4 with the real engine: a stereo file plays to the end and reports it once")
    func realEngineEnds() async throws {
        let url = try tone(seconds: 1.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVAudioPlayerEngine()
        engine.volume = 0  // never out loud on the machine running the tests
        var ends = 0
        var ticks = 0
        engine.onEnd = { ends += 1 }
        engine.onTime = { _ in ticks += 1 }
        let duration = try engine.load(url)
        #expect(abs(duration - 1.5) < 0.05)
        engine.rate = 2
        #expect(engine.play())
        for _ in 0..<60 where ends == 0 { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(300))  // a late delegate call must not count twice
        #expect(ends == 1)
        #expect(ticks > 3)
    }

    @Test("Real engine: a late delegate call about a file no longer loaded is dropped")
    func realEngineDropsStaleDelegateCalls() async throws {
        let url = try tone(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVAudioPlayerEngine()
        engine.volume = 0
        var failures = 0, ends = 0
        engine.onFailure = { _ in failures += 1 }
        engine.onEnd = { ends += 1 }
        _ = try engine.load(url)
        #expect(engine.play())
        let old = try AVAudioPlayer(contentsOf: url)
        engine.audioPlayerDecodeErrorDidOccur(old, error: nil)
        engine.audioPlayerDidFinishPlaying(old, successfully: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(failures == 0)
        #expect(ends == 0)
        engine.unload()
    }

    @Test("Real engine: seek and pause")
    func realEngineSeek() throws {
        let url = try tone(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVAudioPlayerEngine()
        engine.volume = 0
        _ = try engine.load(url)
        engine.seek(to: 2)
        #expect(abs(engine.currentTime - 2) < 0.01)
        engine.unload()
        #expect(engine.currentTime == 0)
        #expect(!engine.play())
    }

    @Test("Now Playing info: title, length, position, rate 0 when paused")
    func nowPlayingInfo() async {
        let h = Harness()
        #expect(NowPlayingController.info(for: h.player, artist: "Band·je") == nil)
        let a = h.item(1)
        await h.player.play(a).value
        h.player.rate = 1.5
        h.play(for: 4)
        var info = NowPlayingController.info(for: h.player, artist: "Band·je")
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Recording 1")
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? Double == 60)
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 6)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)
        h.player.pause(reason: .user)
        info = NowPlayingController.info(for: h.player, artist: "Band·je")
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }

    @Test("The cover is handed to Media Player off the main actor (its background queue asks for it)")
    func artworkOffTheMainActor() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "bandjekit-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        // Not Sendable; handed over as Media Player does, to one other queue.
        nonisolated(unsafe) let artwork = try #require(NowPlayingController.artwork(contentsOf: url))
        // A main-actor request handler traps here (it did on iOS: crash when playback started).
        let found = await withCheckedContinuation { done in
            DispatchQueue.global().async { done.resume(returning: artwork.image(at: CGSize(width: 8, height: 8)) != nil) }
        }
        #expect(found)
    }

    #if os(iOS)
    @Test("P11 and P10: reading the audio session's notifications")
    func sessionNotifications() {
        typealias C = AudioSessionController
        #expect(C.interruption([AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]) == .began)
        #expect(C.interruption([AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
                == .ended(shouldResume: true))
        #expect(C.interruption([AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]) == .ended(shouldResume: false))
        #expect(C.outputRemoved([AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]))
        #expect(!C.outputRemoved([AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]))
    }
    #endif
}
