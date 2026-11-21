// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation

extension AVAudioFile {
    /// How close to the reported end a failing read counts as the end: 0.1 s.
    public static func endSlack(sampleRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(sampleRate / 10)
    }

    /// Reads the next frames into `buffer` (at most `frameCount`, else the buffer's capacity).
    /// Returns false at the end of the file.
    ///
    /// `read` throws at the end instead of returning 0 frames, and AVAudioFile can report a few
    /// frames more than it can decode: AAC taken out of a video by AVAssetExportSession said 2
    /// frames more (a 39 s MP4 from the owner, 2026-11-08), and the whole transcription failed
    /// on them. A read that fails within the last 0.1 s is the end, not an error.
    public func readNext(into buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount? = nil) throws -> Bool {
        let remaining = length - framePosition
        guard remaining > 0 else { return false }
        buffer.frameLength = 0
        let count = min(AVAudioFrameCount(clamping: remaining), frameCount ?? buffer.frameCapacity)
        do {
            try read(into: buffer, frameCount: count)
        } catch {
            if remaining <= Self.endSlack(sampleRate: processingFormat.sampleRate) { return false }
            throw error
        }
        return buffer.frameLength > 0
    }
}
