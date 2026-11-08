// SPDX-License-Identifier: GPL-3.0-only
// Makes a small video file (black frames, H.264) with the audio of a WAV, for import tests (M4).
// Usage: swift scripts/dev/make-mp4.swift <in.wav> <out.mp4|out.mov>
// Video-only track via AVAssetWriter, then composed with the audio and exported as H.264 + AAC.
import AVFoundation
import CoreVideo

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: make-mp4.swift <in.wav> <out.mp4|out.mov>")
    exit(2)
}
let input = URL(filePath: args[1])
let output = URL(filePath: args[2])
let videoOnly = FileManager.default.temporaryDirectory.appending(path: "bandje-video-\(UUID().uuidString).mov")

func fail(_ message: String) -> Never {
    print("make-mp4: \(message)")
    exit(1)
}

let audioAsset = AVURLAsset(url: input)
guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else { fail("no audio in \(input.path)") }
let duration = try await audioAsset.load(.duration)

// 1. Black video, 2 frames per second, as long as the audio.
let writer = try AVAssetWriter(outputURL: videoOnly, fileType: .mov)
let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120,
])
writer.add(videoInput)
guard writer.startWriting() else { fail("writer: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
let frames = Int(duration.seconds * 2) + 1
for frame in 0..<frames {
    while !videoInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { fail("pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 2))
}
videoInput.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { fail("writer: \(String(describing: writer.error))") }

// 2. Video + audio → H.264 + AAC.
let videoAsset = AVURLAsset(url: videoOnly)
guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else { fail("no video track") }
let composition = AVMutableComposition()
let range = CMTimeRange(start: .zero, duration: duration)
try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
    .insertTimeRange(range, of: videoTrack, at: .zero)
try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
    .insertTimeRange(range, of: audioTrack, at: .zero)
guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality) else {
    fail("export session")
}
try? FileManager.default.removeItem(at: output)
try await export.export(to: output, as: output.pathExtension.lowercased() == "mov" ? .mov : .mp4)
try? FileManager.default.removeItem(at: videoOnly)
print("\(output.path) (\(String(format: "%.1f", duration.seconds)) s, video + audio)")
