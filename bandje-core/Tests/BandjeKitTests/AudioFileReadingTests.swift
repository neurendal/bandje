// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import Testing
@testable import BandjeKit

/// A file that promises `extra` frames more than it holds, as AVAudioFile did for AAC taken out of
/// an MP4 (2 frames). Reading past the real end throws, as there.
private final class OverlongFile: AVAudioFile {
    var extra: AVAudioFramePosition = 2
    /// A read starting at this position throws (a damaged file), nil for none.
    var failAt: AVAudioFramePosition?

    override var length: AVAudioFramePosition { super.length + extra }

    override func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws {
        if let failAt, framePosition >= failAt { throw CocoaError(.fileReadCorruptFile) }
        if framePosition >= super.length { throw CocoaError(.fileReadUnknown) }
        try super.read(into: buffer, frameCount: min(frames, AVAudioFrameCount(super.length - framePosition)))
    }
}

@Suite("AVAudioFile.readNext: the end of a file that says it is longer")
struct AudioFileReadingTests {
    private func tone(frames: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "bandjekit-read-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        try file.write(from: buffer)
        return url
    }

    private func readAll(_ file: AVAudioFile) throws -> Int {
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32_768)!
        var total = 0
        while try file.readNext(into: buffer) { total += Int(buffer.frameLength) }
        return total
    }

    @Test("Two frames promised but missing at the end: everything is read, no error")
    func overlongEndIsTheEnd() throws {
        let url = try tone(frames: 100_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try OverlongFile(forReading: url)
        #expect(file.length == 100_002)
        #expect(try readAll(file) == 100_000)
    }

    @Test("An ordinary file reads to its end")
    func ordinaryFile() throws {
        let url = try tone(frames: 70_001)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try readAll(try AVAudioFile(forReading: url)) == 70_001)
    }

    @Test("A read that fails earlier than the last 0.1 s still fails")
    func damagedMiddleThrows() throws {
        let url = try tone(frames: 100_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try OverlongFile(forReading: url)
        file.failAt = 32_768
        #expect(throws: CocoaError.self) { try readAll(file) }
    }

    @Test("Too far from the end for slack: an error is an error")
    func farFromEndThrows() throws {
        let url = try tone(frames: 100_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try OverlongFile(forReading: url)
        file.extra = AVAudioFile.endSlack(sampleRate: 44_100) + 1  // more than 0.1 s promised
        #expect(throws: CocoaError.self) { try readAll(file) }
    }
}
