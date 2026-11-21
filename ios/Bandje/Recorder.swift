// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BandjeKit
import CoreLocation
import Foundation
import Observation
import Synchronization
import UIKit

/// `CustomLocalizedStringResourceConvertible`: an intent (Siri, the Action button, the Control)
/// that throws it shows this message instead of a generic error.
struct RecorderError: LocalizedError, CustomLocalizedStringResourceConvertible {
    let message: String
    var errorDescription: String? { message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }

    static var permissionDenied: RecorderError {
        RecorderError(message: String(localized: "Bandje has no access to the microphone. Allow it in Settings > Apps > Bandje."))
    }
    static var noInput: RecorderError {
        RecorderError(message: String(localized: "No microphone available."))
    }
    static var diskFull: RecorderError {
        RecorderError(message: String(localized: "There is not enough free space on this \(Device.name) to record. Free up space and try again."))
    }
}

// MARK: - Recorder

/// Records mono audio into `Documents/<title>/<title>.caf` (crash-safe PCM) and converts it to
/// `.m4a` (AAC 48 kHz mono 64 kbit/s) at stop. One recording at a time.
@MainActor @Observable
final class Recorder {
    static let shared = Recorder()

    enum State: Equatable { case idle, recording, paused, finishing }

    /// Why a recording stopped by itself; it is kept (stopped, converted and saved as usual).
    enum StopReason: Equatable { case diskFull, writeFailed, maxLength }

    /// The longest recording (owner, 2026-11-09): about 4 GB of CAF before it becomes `.m4a`.
    nonisolated static let maxDuration: TimeInterval = 12 * 3600

    private(set) var state: State = .idle
    /// Recorded time, pauses excluded.
    private(set) var elapsed: TimeInterval = 0
    /// RMS of the latest buffer, 0…1.
    private(set) var level: Float = 0
    private(set) var markers: [Double] = []
    private(set) var folder: URL?
    /// An interruption paused the recording and iOS did not ask to resume: tell the user.
    var interruptionNotice = false
    var errorMessage: String?
    /// The disk is getting full (`DiskSpace.Level.low`): a gentle warning while recording.
    private(set) var diskLow = false
    /// Why the last recording stopped by itself (or could not be converted): an alert in the
    /// library, also when the app comes to the front later. The view clears it.
    var stopNotice: String?
    /// Inputs to choose from (only shown when there is more than one).
    private(set) var inputs: [AVAudioSessionPortDescription] = []
    private(set) var currentInput: String?
    #if DEBUG
    /// What happened, for the selftests.
    private(set) var events: [String] = []
    #endif

    var isActive: Bool { state == .recording || state == .paused }
    var title: String { folder?.lastPathComponent ?? "" }

    private var writer: CAFWriter?
    private var source: (any CaptureSource)?
    private var meta: RecordingMeta?
    private var ticker: Task<Void, Never>?
    private var diskWatch: Task<Void, Never>?
    private var autoStopping = false
    /// Between the start request and the recording running (the microphone question is awaited):
    /// a second start meanwhile does nothing.
    private var starting = false
    private var pausedByInterruption = false
    /// Where finished recordings went when syncing moved them to iCloud (for a late location fix).
    private var published: [URL: URL] = [:]
    /// The interruption ended with "should resume" while Bandje could not take the microphone
    /// back (still behind the Phone app): resume when Bandje is in front again.
    private var resumeWhenActive = false

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated { self?.interruption(type, shouldResume: options?.contains(.shouldResume) ?? false) }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInputs() }
        }
        // The audio daemon restarted: the engine is gone. Keep what was recorded.
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mediaServicesReset() }
        }
    }

    private func mediaServicesReset() {
        guard isActive else { return }
        log("media-services-reset")
        Task {
            await RecordingCommands.stop()
            errorMessage = String(localized: "The audio system restarted. The recording so far has been saved.")
        }
    }

    /// Starts a new recording from the microphone, or from `source` (the DEBUG fake mic).
    func start(source given: (any CaptureSource)? = nil) async throws {
        guard state == .idle, !starting else { return }
        starting = true
        defer { starting = false }
        // P7: the microphone would hear the player; it stays paused afterwards.
        Playback.player.pause(reason: .recordingStarted)
        let source: any CaptureSource
        if let given {
            source = given
        } else {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
            let mic = MicSource()
            mic.onRestartFailed = { [weak self] in self?.inputLost() }
            source = mic
        }
        // Not when the disk is (almost) full: a recording needs room, and so does iOS.
        let disk = DiskSpace.level(at: Storage.documents)
        guard disk != .tooLow else { throw RecorderError.diskFull }
        let date = Date()
        let caf = try Storage.newRecording(title: Storage.defaultTitle(for: date), date: date)
        let folder = caf.deletingLastPathComponent()
        let writer: CAFWriter
        do {
            writer = try CAFWriter(url: caf)
            try source.start(sink: { [writer] samples, rate in writer.append(samples, rate: rate) },
                             onEnd: { [weak self] in Task { @MainActor in _ = await self?.stop() } })
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        self.writer = writer
        self.source = source
        self.folder = folder
        meta = RecordingMeta.read(from: folder)
        markers = []
        elapsed = 0
        interruptionNotice = false
        pausedByInterruption = false
        resumeWhenActive = false
        errorMessage = nil
        diskLow = disk == .low
        autoStopping = false
        state = .recording
        log("started")
        refreshInputs()
        LiveRecording.shared.sync(self)
        if LocationTag.isEnabled {
            Task { [weak self] in
                guard let location = await LocationTag.current() else { return }
                self?.tag(location, folder: folder)
            }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        diskWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DiskSpace.checkInterval))
                guard !Task.isCancelled, let self, self.isActive, let folder = self.folder else { return }
                let level = await Task.detached(priority: .utility) { DiskSpace.level(at: folder) }.value
                self.diskChecked(level)
            }
        }
    }

    /// Every `DiskSpace.checkInterval` while recording.
    private func diskChecked(_ level: DiskSpace.Level) {
        guard isActive else { return }
        diskLow = level != .ok
        if let reason = Self.autoStopReason(elapsed: elapsed, writeFailed: false, disk: level) { autoStop(reason) }
    }

    /// Whether a running recording must stop by itself: the disk is too full, writing failed, or it
    /// reached the maximum length. Pure (unit-tested).
    nonisolated static func autoStopReason(elapsed: TimeInterval, writeFailed: Bool, disk: DiskSpace.Level?) -> StopReason? {
        if disk == .tooLow { return .diskFull }
        if writeFailed { return .writeFailed }
        if elapsed >= maxDuration { return .maxLength }
        return nil
    }

    /// Stops the normal way (converted, saved, opened, transcribed when that is on) and says why:
    /// an alert in the app (shown when Bandje is next in front).
    private func autoStop(_ reason: StopReason) {
        guard isActive, !autoStopping else { return }
        autoStopping = true
        log("auto-stop")
        Task {
            stopNotice = nil
            await RecordingCommands.stop()
            autoStopping = false
            // After the reason, what stop() said (a conversion that failed).
            let message = [Self.message(for: reason), stopNotice].compactMap { $0 }.joined(separator: "\n\n")
            stopNotice = message
        }
    }

    nonisolated static func message(for reason: StopReason) -> String {
        switch reason {
        case .diskFull:
            String(localized: "The recording stopped because this \(Device.name) is almost full. What was recorded has been saved.")
        case .writeFailed:
            String(localized: "The recording stopped because writing it failed. What was recorded has been saved.")
        case .maxLength:
            String(localized: "The recording stopped after 12 hours, the longest a recording can be. It has been saved.")
        }
    }

    func pause() {
        guard state == .recording else { return }
        source?.pause()
        tick()
        state = .paused
        level = 0
        log("paused")
        LiveRecording.shared.sync(self)
    }

    func resume() {
        guard state == .paused else { return }
        resumeWhenActive = false
        do {
            try source?.resume()
            resumed()
        } catch {
            // Usually another app (a call) still holds the microphone.
            errorMessage = String(localized: "The microphone is in use by another app. Try again in a moment.")
        }
    }

    /// Saves where the recording was made (the fix may arrive after it stopped).
    private func tag(_ location: RecordedLocation, folder: URL) {
        if self.folder == folder, meta != nil {
            meta?.location = location
            try? meta?.write(to: folder)
        } else {
            // Already stopped, and maybe moved to iCloud since.
            let now = published[folder] ?? folder
            if var saved = RecordingMeta.read(from: now) {
                saved.location = location
                try? saved.write(to: now)
            }
        }
        log("location")
    }

    /// Recording again after a pause (by the user or an interruption).
    private func resumed() {
        state = .recording
        pausedByInterruption = false
        interruptionNotice = false
        errorMessage = nil
        log("resumed")
        LiveRecording.shared.sync(self)
    }

    /// The microphone could not be taken back after the input changed (AirPods in or out), also
    /// not on a second try: paused, with the interruption notice; Resume goes on.
    private func inputLost() {
        guard state == .recording else { return }
        log("input-lost")
        pause()
        interruptionNotice = true
    }

    /// After an interruption: resume if possible, else wait until Bandje is in front again.
    private func resumeAfterInterruption() {
        guard state == .paused, let source else { return }
        do {
            try source.resume()
            resumed()
        } catch {
            log("resume-deferred")
            interruptionNotice = true
            resumeWhenActive = UIApplication.shared.applicationState != .active
        }
    }

    private func becameActive() {
        guard resumeWhenActive, state == .paused else { return }
        resumeAfterInterruption()
    }

    /// Marks the current moment; saved to the sidecar right away (survives a crash).
    func addMarker() {
        guard isActive, let folder else { return }
        tick()
        markers.append((elapsed * 10).rounded() / 10)
        meta?.markers = markers
        try? meta?.write(to: folder)
        log("marker")
    }

    /// Stops, closes the CAF and converts it to `.m4a`. Returns the recording's folder.
    @discardableResult
    func stop() async -> URL? {
        guard isActive, let writer, let folder else { return nil }
        // Stopped from the Lock Screen, Siri or the Control, Bandje may be in the background:
        // converting and saving must finish before iOS suspends it.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Stop recording")
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
        state = .finishing
        resumeWhenActive = false
        pausedByInterruption = false
        source?.stop()
        source = nil
        ticker?.cancel()
        diskWatch?.cancel()
        diskWatch = nil
        tick()
        LiveRecording.shared.sync(self)  // ends the Live Activity right away, before converting
        log("stopping")
        let caf = writer.url
        let (result, seconds) = await Task.detached(priority: .userInitiated) {
            writer.finish()
            let result = Result { try AudioExport.convertToM4A(caf) }
            // The length goes into `.bandje.json`: the Mac shows it while the audio is still in iCloud.
            return (result, Storage.duration(of: (try? result.get()) ?? caf))
        }.value
        meta?.setDuration(seconds)
        if case .failure(let error) = result {
            // The CAF stays: the library shows it (playable, deletable), and the next launch tries
            // again when there is room (recovery). Not `recording` any more.
            errorMessage = error.localizedDescription
            meta?.recording = nil
            try? meta?.write(to: folder)
            if stopNotice == nil {
                stopNotice = String(localized: "The recording has been saved, but could not be converted yet. Bandje tries again at the next launch, when there is enough free space.")
            }
            log("convert-failed")
        } else {
            meta?.recording = nil
            try? meta?.write(to: folder)
            log("stopped")
        }
        self.writer = nil
        self.folder = nil
        meta = nil
        level = 0
        diskLow = false
        // Syncing: the finished recording moves to iCloud (an unconverted CAF stays for recovery).
        let converted = (try? result.get()) != nil
        let final = converted ? await Task.detached { Storage.publish(folder) }.value : folder
        if final != folder { published[folder] = final }
        state = .idle
        return Storage.canonical(final)
    }

    func selectInput(_ port: AVAudioSessionPortDescription) {
        try? AVAudioSession.sharedInstance().setPreferredInput(port)
        refreshInputs()
    }

    private func tick() {
        guard let writer else { return }
        elapsed = writer.seconds
        level = state == .recording ? writer.level : 0
        guard isActive else { return }
        // Writing failed (the disk is full, or the file is gone), or the maximum length: stop and keep it.
        if let reason = Self.autoStopReason(elapsed: elapsed, writeFailed: writer.failed, disk: nil) { autoStop(reason) }
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began:
            guard state == .recording else { return }
            log("interruption-began")
            pause()
            pausedByInterruption = true
        case .ended:
            guard pausedByInterruption else { return }
            pausedByInterruption = false
            log("interruption-ended")
            if shouldResume { resumeAfterInterruption() } else { interruptionNotice = true }
        default:
            break
        }
    }

    private func refreshInputs() {
        let session = AVAudioSession.sharedInstance()
        inputs = isActive ? (session.availableInputs ?? []) : []
        currentInput = session.currentRoute.inputs.first?.uid
    }

    private func log(_ event: String) {
        #if DEBUG
        events.append(event)
        #endif
    }
}

// MARK: - Sources

/// Delivers mono Float32 samples (at any rate) to the sink, on any thread.
protocol CaptureSource: AnyObject {
    func start(sink: @escaping @Sendable ([Float], Double) -> Void, onEnd: @escaping @Sendable () -> Void) throws
    func pause()
    func resume() throws
    func stop()
}

extension AVAudioPCMBuffer {
    /// The buffer's channels averaged into one.
    var monoSamples: [Float] {
        let n = Int(frameLength), channels = Int(format.channelCount)
        guard n > 0, channels > 0, let data = floatChannelData else { return [] }
        if channels == 1 { return Array(UnsafeBufferPointer(start: data[0], count: n)) }
        var out = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            let ch = data[c]
            for i in 0..<n { out[i] += ch[i] }
        }
        let scale = 1 / Float(channels)
        for i in 0..<n { out[i] *= scale }
        return out
    }
}

/// The microphone via AVAudioEngine. Owns the audio session while recording.
/// Main thread only (except the tap block, which only touches the sink); hence unchecked.
final class MicSource: CaptureSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sink: (@Sendable ([Float], Double) -> Void)?
    private var running = false
    private var observer: NSObjectProtocol?
    /// Called (on the main thread) when the input could not be restarted, also after a retry.
    var onRestartFailed: (@MainActor () -> Void)?

    func start(sink: @escaping @Sendable ([Float], Double) -> Void, onEnd: @escaping @Sendable () -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .bluetoothHighQualityRecording])
        try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try session.setActive(true)
        self.sink = sink
        // The engine stops itself when the input changes (AirPods in/out): rebuild the tap at
        // the new format. The writer converts any rate to the file's.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
        do {
            try run()
        } catch {
            stop()  // gives the session back, so other audio can resume
            throw error
        }
    }

    func pause() {
        engine.stop()
        running = false
    }

    func resume() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try run()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func run() throws {
        guard let sink else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        input.removeTap(onBus: 0)
        // Runs on an internal (not real-time) thread: copy out the samples and hand them on.
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            sink(buffer.monoSamples, buffer.format.sampleRate)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    private func restart() {
        guard running else { return }
        engine.stop()
        do {
            try run()
        } catch {
            // Often the new route is not ready yet: once more after a moment, then tell the recorder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }  // stopped or paused meanwhile
                    do {
                        try self.run()
                    } catch {
                        self.running = false
                        self.onRestartFailed?()
                    }
                }
            }
        }
    }
}

// MARK: - Writer

/// Writes mono samples to a CAF (LPCM Int16, 48 kHz) on its own serial queue. A CAF that was
/// never closed (crash, forced quit) is still readable after `CAFRepair.repair`.
final class CAFWriter: @unchecked Sendable {
    static let sampleRate: Double = 48_000
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    let url: URL
    private let queue = DispatchQueue(label: "com.neurendal.bandje.writer", qos: .userInitiated)
    // Queue-confined.
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?

    private struct Stats { var frames = 0; var level: Float = 0; var failed = false }
    private let stats = Mutex(Stats())

    var seconds: Double { Double(stats.withLock { $0.frames }) / Self.sampleRate }
    var level: Float { stats.withLock { $0.level } }
    var failed: Bool { stats.withLock { $0.failed } }

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.url = url
    }

    /// Any thread. `samples` is mono at `rate`.
    func append(_ samples: [Float], rate: Double) {
        guard !samples.isEmpty, rate > 0 else { return }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        stats.withLock { $0.level = min(1, rms) }
        queue.async { self.write(samples, rate: rate) }
    }

    /// Writes everything still queued and closes the file. Blocks; call off the main actor.
    func finish() {
        queue.sync {
            if let converter { try? run(converter, input: nil) }
            converter = nil
            file?.close()
            file = nil
        }
    }

    private func write(_ samples: [Float], rate: Double) {
        guard let file,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        do {
            if rate == Self.sampleRate {
                if let converter { try run(converter, input: nil); self.converter = nil }
                try file.write(from: buffer)
                stats.withLock { $0.frames += samples.count }
            } else {
                if let converter, converter.inputFormat.sampleRate != rate {
                    try run(converter, input: nil)
                    self.converter = nil
                }
                if converter == nil { converter = AVAudioConverter(from: format, to: Self.format) }
                guard let converter else { throw RecorderError(message: "converter") }
                try run(converter, input: buffer)
            }
        } catch {
            stats.withLock { $0.failed = true }
        }
    }

    /// Runs `input` (nil = end of stream: flush) through the converter into the file.
    private func run(_ converter: AVAudioConverter, input: AVAudioPCMBuffer?) throws {
        let inFrames = Double(input?.frameLength ?? 4_096)
        let capacity = AVAudioFrameCount(inFrames * Self.sampleRate / converter.inputFormat.sampleRate) + 1_024
        nonisolated(unsafe) var supplied = false
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, inputStatus in
                if let input, !supplied {
                    supplied = true
                    inputStatus.pointee = .haveData
                    return input
                }
                inputStatus.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            if out.frameLength > 0 {
                try file?.write(from: out)
                stats.withLock { $0.frames += Int(out.frameLength) }
            }
            if status == .error { throw error ?? RecorderError(message: "convert") }
            if status != .haveData { return }
        }
    }
}

// MARK: - Export and repair

/// "Store GPS location" (off by default): one location fix when a recording starts, coordinates only.
/// Nothing is looked up online; "Show in Maps" hands the coordinates to the Maps app.
enum LocationTag {
    static let settingKey = "saveLocation"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// One fix within `timeout`, asking for When In Use permission the first time. Nil when it is
    /// denied, unavailable (e.g. started from the lock screen) or too inaccurate.
    static func current(timeout: Duration = .seconds(15)) async -> RecordedLocation? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        return await withTaskGroup(of: RecordedLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                            return nil
                        }
                        if let l = update.location, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 200 {
                            return RecordedLocation(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude,
                                                    accuracy: l.horizontalAccuracy)
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

enum AudioExport {
    /// Puts the cassette cover (and the title) into the recording's own `.m4a`, once per title,
    /// length and colour, in the background: sharing then hands over the file right away, and Files,
    /// Finder and music apps show the cover too. Passthrough (the audio is not re-encoded), written
    /// next to the file and swapped in. Other formats are left as they are.
    /// Only when `CoverPolicy.plan` says so (../specs/icloud-sync.md, owner 2026-11-10): for a change
    /// made on this device (`own`: its rename or colour), or for a recording that never had a cover;
    /// never as a reaction to a rename or colour from the Mac (the Mac writes that cover), and only
    /// while `.bandje.json` and the audio are the newest versions here. Own change with the audio
    /// still in iCloud: the key is removed, so a device that has the audio makes the cover.
    /// `afterExport` runs between the export and noting the key (tests: a colour set meanwhile).
    static func embedCover(_ recording: Recording, own: Bool, afterExport: () async -> Void = {}) async {
        guard let audio = recording.audio, audio.pathExtension.lowercased() == "m4a" else { return }
        let metaFile = RecordingMeta.url(in: recording.folder)
        // Strict: a copy here whose newer version is still coming (`.downloaded`) is not current.
        let audioIsCurrent = recording.audioIsLocal && FileManager.default.fileExists(atPath: audio.path)
            && CoverPolicy.isUpToDate(audio)
        let key = CoverArt.key(for: recording)
        switch CoverPolicy.plan(storedKey: RecordingMeta.read(from: recording.folder)?.coverKey, currentKey: key, ownChange: own,
                                metaIsCurrent: CoverPolicy.isUpToDate(metaFile), audioIsCurrent: audioIsCurrent) {
        case .leave:
            return
        case .clearKey:
            _ = try? RecordingMeta.update(in: recording.folder, created: recording.date, onlyIfCurrent: true) { $0.coverKey = nil }
            return
        case .embed:
            break
        }
        guard let cover = await CoverArt.file(for: recording), let art = try? Data(contentsOf: cover) else { return }
        let asset = AVURLAsset(url: audio)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .iTunesMetadataCoverArt
        artwork.dataType = kCMMetadataBaseDataType_JPEG as String
        artwork.value = art as NSData
        let name = AVMutableMetadataItem()
        name.identifier = .iTunesMetadataSongName
        name.value = recording.title as NSString
        session.metadata = [artwork, name]
        let temp = recording.folder.appending(path: ".embedding-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: temp, as: .m4a)
            await afterExport()
            // The export takes seconds: a newer `.bandje.json` or audio from the Mac that started
            // coming meanwhile wins, this cover is dropped.
            guard CoverPolicy.isUpToDate(metaFile), CoverPolicy.isUpToDate(audio) else {
                try? FileManager.default.removeItem(at: temp)
                return
            }
            try Storage.coordinated(writing: audio, options: .forReplacing) { _ = try FileManager.default.replaceItemAt($0, withItemAt: temp) }
            // Only the key, into the file as it is now: the export takes seconds, and a colour (or
            // anything else) written meanwhile must stay (a rename and a new colour together).
            try RecordingMeta.update(in: recording.folder, created: recording.date, onlyIfCurrent: true) { $0.coverKey = key }
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    /// `<name>.caf` → `<name>.m4a` (AAC, mono, 64 kbit/s, same rate) via `<name>.converting.m4a`,
    /// then removes the CAF. On failure the CAF stays. An empty CAF is removed with its folder's
    /// other leftovers and throws.
    static func convertToM4A(_ caf: URL) throws -> URL {
        let target = caf.deletingPathExtension().appendingPathExtension("m4a")
        let temp = caf.deletingPathExtension().appendingPathExtension("converting.m4a")
        let fm = FileManager.default
        try? fm.removeItem(at: temp)
        do {
            let input = try AVAudioFile(forReading: caf)
            guard input.length > 0 else {
                throw RecorderError(message: String(localized: "The recording is empty."))
            }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: input.fileFormat.sampleRate,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ]
            let format = input.processingFormat
            let output = try AVAudioFile(forWriting: temp, settings: settings, commonFormat: format.commonFormat,
                                         interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
                throw RecorderError(message: "buffer")
            }
            while try input.readNext(into: buffer) {  // BandjeKit: the end, also of a file that says it is longer
                try output.write(from: buffer)
            }
            output.close()
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try? fm.removeItem(at: caf)
        return target
    }
}

/// Makes a CAF that was never closed readable: if the `data` chunk is the last chunk and its
/// size does not match the bytes on disk, set it to -1 ("until the end of the file", allowed by
/// the CAF spec for the last chunk). A properly closed file is left alone.
enum CAFRepair {
    @discardableResult
    static func repair(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 8 else { return false }
        try? handle.seek(toOffset: 0)
        guard let magic = try? handle.read(upToCount: 8), magic.prefix(4) == Data("caff".utf8) else { return false }
        var offset: UInt64 = 8
        while offset + 12 <= size {
            try? handle.seek(toOffset: offset)
            guard let header = try? handle.read(upToCount: 12), header.count == 12 else { return false }
            let type = header.prefix(4)
            let chunkSize = header.dropFirst(4).reduce(Int64(0)) { $0 << 8 | Int64($1) }
            let remaining = Int64(size - offset - 12)
            if type == Data("data".utf8) {
                if chunkSize == -1 || chunkSize == remaining { return false }
                if chunkSize < remaining, isChunkHeader(handle, at: offset + 12 + UInt64(chunkSize), size: size) {
                    return false // another chunk follows: a complete file
                }
                try? handle.seek(toOffset: offset + 4)
                try? handle.write(contentsOf: Data(repeating: 0xFF, count: 8))
                return true
            }
            guard chunkSize >= 0 else { return false }
            offset += 12 + UInt64(chunkSize)
        }
        return false
    }

    private static func isChunkHeader(_ handle: FileHandle, at offset: UInt64, size: UInt64) -> Bool {
        guard offset + 12 <= size else { return false }
        try? handle.seek(toOffset: offset)
        guard let type = try? handle.read(upToCount: 4), type.count == 4 else { return false }
        return type.allSatisfy { (0x20...0x7E).contains($0) }
    }
}

#if DEBUG
// MARK: - Fake microphone (DEBUG)

/// Plays a file into the recorder at real-time pace, instead of the microphone (`--fake-mic`).
/// Same path after the source: mono samples → writer → level. Ends the recording at the end.
final class FakeMicSource: CaptureSource, @unchecked Sendable {
    private let file: AVAudioFile
    private let queue = DispatchQueue(label: "com.neurendal.bandje.fakemic", qos: .userInitiated)
    // Queue-confined.
    private var timer: DispatchSourceTimer?
    private var emitted: AVAudioFramePosition = 0
    private var startedAt: TimeInterval = 0
    private var sink: (@Sendable ([Float], Double) -> Void)?
    private var onEnd: (@Sendable () -> Void)?

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
    }

    func start(sink: @escaping @Sendable ([Float], Double) -> Void, onEnd: @escaping @Sendable () -> Void) throws {
        queue.sync {
            self.sink = sink
            self.onEnd = onEnd
        }
        try resume()
    }

    func pause() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    func resume() throws {
        queue.sync {
            guard timer == nil else { return }
            let rate = file.processingFormat.sampleRate
            startedAt = ProcessInfo.processInfo.systemUptime - Double(emitted) / rate
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(20))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    func stop() { pause() }

    private func tick() {
        let rate = file.processingFormat.sampleRate
        let due = AVAudioFramePosition((ProcessInfo.processInfo.systemUptime - startedAt) * rate) - emitted
        let count = min(due, file.length - file.framePosition)
        if count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) {
            try? file.read(into: buffer, frameCount: AVAudioFrameCount(count))
            emitted += AVAudioFramePosition(buffer.frameLength)
            sink?(buffer.monoSamples, rate)
        }
        if file.framePosition >= file.length {
            timer?.cancel()
            timer = nil
            onEnd?()
        }
    }
}
#endif
