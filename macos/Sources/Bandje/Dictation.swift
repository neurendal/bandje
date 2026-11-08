import AppKit
import AVFoundation
import AudioToolbox
import Carbon.HIToolbox
import os

/// Dictation steps in the unified log (`log show --predicate 'subsystem == "com.neurendal.bandje"'`).
/// Lengths, durations, app names and outcomes only, never the dictated text.
let dictationLog = Logger(subsystem: "com.neurendal.bandje", category: "dictation")

/// Dictation: default microphone into memory, mono floats at the device rate.
/// Nothing is written to disk.
final class DictationCapture: @unchecked Sendable {
    static let maxSeconds: Double = 5 * 60

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var rate: Double = 0
    /// Name of the microphone used, for the "heard nothing" message.
    private(set) var micName = ""
    /// How often the engine was restarted because no audio came in (see `start`).
    private(set) var restarts = 0

    /// The microphone chosen at start; re-applied when the engine restarts.
    private var device: AudioObjectID = 0
    private var observer: NSObjectProtocol?
    private var stopped = false
    /// All engine work runs here, never on the main thread: `inputNode` and `start()` are IPC
    /// calls to coreaudiod, which can stall for a minute (seen with OBS capturing audio at the
    /// same time). Serial, so a stop waits for a start that is still running.
    private let queue = DispatchQueue(label: "com.neurendal.bandje.dictation", qos: .userInitiated)

    /// Starts the microphone on `queue`; the caller only waits asynchronously.
    func start() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.startOnQueue(); done.resume() } catch { done.resume(throwing: error) }
            }
        }
    }

    private func startOnQueue() throws {
        lock.lock(); let released = stopped; lock.unlock()
        guard !released else { return } // released before the queue got to it
        // Same microphone as recordings (menu Microfoon). Must be set before the format is read.
        device = Recorder.inputDevice()
        micName = Recorder.deviceName(device) ?? ""
        try run()
        // Switching the engine to that microphone can reach Core Audio just after the start; the
        // engine then stops itself ("iounit configuration changed") and no audio comes in. Restart it.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.restart() }
        }
    }

    private func run() throws {
        let input = engine.inputNode
        var device = self.device
        if let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioObjectID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError(message: tr("error.noMic", "Geen microfoon gevonden."))
        }
        lock.lock()
        // The first rate wins; later buffers at another rate are converted to it (see append).
        if rate == 0 || samples.isEmpty { rate = format.sampleRate }
        let target = rate
        lock.unlock()
        samples.reserveCapacity(Int(target * 30))
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer, targetRate: target)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError(message: tr("error.micStart", "Microfoon starten mislukt (%@).", error.localizedDescription))
        }
    }

    private func restart() {
        lock.lock(); let released = stopped; lock.unlock()
        guard !released, restarts < 5 else { return }
        restarts += 1
        dictationLog.notice("capture: audio configuration changed, restarting the microphone (\(self.restarts, privacy: .public))")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try run()
        } catch {
            dictationLog.error("capture: restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer, targetRate: Double) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        var mono = [Float](UnsafeBufferPointer(start: data[0], count: n))
        if channels > 1 {
            for c in 1..<channels { for i in 0..<n { mono[i] += data[c][i] } }
            let scale = 1 / Float(channels)
            for i in 0..<n { mono[i] *= scale }
        }
        if buffer.format.sampleRate != targetRate {
            mono = Self.resample(mono, from: buffer.format.sampleRate, to: targetRate)
        }
        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()
    }

    /// Returns everything captured so far and stops the microphone in the background (on `queue`,
    /// after a start that may still be running), so the caller never waits for Core Audio.
    func stop() -> (samples: [Float], rate: Double) {
        lock.lock()
        stopped = true
        let result = (samples, rate)
        lock.unlock()
        queue.async {
            if let observer = self.observer { NotificationCenter.default.removeObserver(observer) }
            self.observer = nil
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
        return result
    }

    /// True when the samples are (nearly) digital silence: a muted or switched-off microphone.
    static func isSilent(_ samples: [Float]) -> Bool {
        (samples.lazy.map { abs($0) }.max() ?? 0) <= 1e-4
    }

    /// Resamples mono audio with AVAudioConverter (one input block).
    static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !samples.isEmpty,
              let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * to / from) + 4096)
        else { return samples }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var fed = false
        _ = converter.convert(to: outBuf, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }
}

/// Puts dictated text on the clipboard and, with Accessibility permission, sends ⌘V to the
/// frontmost app.
@MainActor
enum Paste {
    /// Posting key events needs the "post event" permission (listed under Accessibility).
    /// `AXIsProcessTrusted` is the wrong check for a sandboxed app: its prompt never appears there.
    static var allowed: Bool { CGPreflightPostEventAccess() }

    /// macOS answers `CGPreflightPostEventAccess` once per process: switching Bandje on in System
    /// Settings only shows (and works) after Bandje restarts. True once this launch asked for the
    /// permission, so the menu and settings can offer that restart.
    @MainActor static var askedThisLaunch = false

    /// Asks macOS for the permission (system dialog the first time, which adds Bandje to the
    /// Accessibility list) and opens that list in System Settings, where the user switches Bandje on.
    static func requestPermission() {
        askedThisLaunch = true
        if CGRequestPostEventAccess() { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    enum Outcome: String { case pasted, clipboardOnly, notAllowed, secureInput }

    /// Puts `text` on the clipboard and, when allowed, sends ⌘V to the frontmost app.
    static func deliver(_ text: String, paste: Bool) async -> Outcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard paste else { return .clipboardOnly }
        guard allowed else { return .notAllowed }
        // In "hold" mode the user may still hold ⌃⌥⌘; with Return the key may still be down. Wait
        // until they are released (max 2 s), otherwise the target app would see ⌃⌥⌘V.
        var waited = 0
        while waited < 40, !NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        // A password field, Terminal's Secure Keyboard Entry or a password manager turns on secure
        // input; macOS then drops synthetic key events, so ⌘V would vanish silently.
        if IsSecureEventInputEnabled() {
            dictationLog.notice("paste: secure input is on, text left on the clipboard")
            return .secureInput
        }
        // Short pauses: some apps read the clipboard late or miss a key down and up in the same instant.
        try? await Task.sleep(nanoseconds: 30_000_000)
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 15_000_000)
        up?.post(tap: .cghidEventTap)
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        dictationLog.notice("paste: ⌘V sent to \(app, privacy: .public) after waiting \(waited * 50) ms for modifiers")
        return .pasted
    }
}
