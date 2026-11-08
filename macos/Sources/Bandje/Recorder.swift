import AudioToolbox
import CoreAudio
import Foundation
import IOKit.pwr_mgt
import Synchronization

/// Single-producer / single-consumer lock-free ring buffer of Float samples.
/// The producer (realtime IOProc) never allocates, locks or blocks.
final class RingBuffer: @unchecked Sendable {
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let head = Atomic<Int>(0) // total samples written (producer)
    private let tail = Atomic<Int>(0) // total samples read (consumer)
    /// Samples dropped because the consumer fell behind.
    let dropped = Atomic<Int>(0)

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    /// Producer side, realtime-safe. Drops the whole block if it does not fit,
    /// so interleaved frames stay aligned.
    @discardableResult
    func write(_ src: UnsafePointer<Float>, count: Int) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        guard count <= capacity - (h - t) else {
            dropped.wrappingAdd(count, ordering: .relaxed)
            return false
        }
        let start = h % capacity
        let first = min(count, capacity - start)
        (storage + start).update(from: src, count: first)
        if first < count { storage.update(from: src + first, count: count - first) }
        head.store(h + count, ordering: .releasing)
        return true
    }

    /// Consumer side. Returns the number of samples copied.
    func read(into dst: UnsafeMutablePointer<Float>, maxCount: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        let count = min(h - t, maxCount)
        guard count > 0 else { return 0 }
        let start = t % capacity
        let first = min(count, capacity - start)
        dst.update(from: storage + start, count: first)
        if first < count { (dst + first).update(from: storage, count: count - first) }
        tail.store(t + count, ordering: .releasing)
        return count
    }
}

struct RecorderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static func coreAudio(_ what: String, _ status: OSStatus) -> RecorderError {
        RecorderError(message: tr("error.coreAudio", "%1$@ mislukt (fout %2$@).", what, "\(status)"))
    }
}

/// Counters shared with the realtime callback.
final class RecorderStats: Sendable {
    let callbacks = Atomic<Int>(0)
    let peakBits = Atomic<UInt32>(0)     // system audio (R)
    let micPeakBits = Atomic<UInt32>(0)  // microphone (L)
    let allCallbacks = Atomic<Int>(0)
    let emptyCallbacks = Atomic<Int>(0)
    /// Host time of the first input sample that reached the ring buffer (0 = none yet).
    let firstHostTime = Atomic<UInt64>(0)
    /// Host time and length of the most recent callback, to measure the gap of a rebuild.
    let lastHostTime = Atomic<UInt64>(0)
    let lastFrames = Atomic<Int>(0)
    /// Set by `rebuild`: host time right after the last sample of the old capture. The first
    /// callback of the new capture fills the time up to its own first sample with silence.
    let resumeHostTime = Atomic<UInt64>(0)
    /// Silence frames inserted for rebuild gaps (at the rate of the new capture).
    let gapFrames = Atomic<Int>(0)
    var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }
    var micPeak: Float { Float(bitPattern: micPeakBits.load(ordering: .relaxed)) }
    /// The louder channel's peak in the latest callback: the VU meter on the window's record screen.
    let levelBits = Atomic<UInt32>(0)
    var level: Float { Float(bitPattern: levelBits.load(ordering: .relaxed)) }
    /// Called from the IO callback: one atomic store, no allocation.
    func noteLevel(mic: Float, system: Float) {
        levelBits.store(max(mic, system).bitPattern, ordering: .relaxed)
    }

    /// Wall-clock time of the first recorded sample, if any.
    var firstSampleDate: Date? {
        let host = firstHostTime.load(ordering: .relaxed)
        guard host != 0 else { return nil }
        let deltaSeconds = (Double(host) - Double(mach_absolute_time())) * Self.hostTicksToSeconds
        return Date(timeIntervalSinceNow: deltaSeconds)
    }

    static let hostTicksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
}

/// Records microphone (left) and system audio of all processes except Bandje (right)
/// to a stereo float32 .caf. The default input device is the clock (main sub-device) of a
/// private aggregate device; the process tap is added to it with drift compensation, so
/// both arrive in one IO callback on the same timeline.
///
/// When the default input device changes during a recording (AirPods on or off), the
/// aggregate and IOProc are rebuilt with the new microphone while tap, ring buffer and
/// writer keep running, so the recording continues in the same file. The gap is filled
/// with silence, so the file stays on the wall-clock timeline. Without any input device the
/// default output device becomes the clock and the left channel stays silent.
///
/// Use from the main thread only (the device listener is delivered on the main queue).
final class Recorder {
    let url: URL
    let stats = RecorderStats()
    private(set) var sampleRate: Double = 0
    private(set) var startDate: Date?
    private(set) var bufferLayout: [Int] = []
    private(set) var micName = ""
    /// One entry per capture rebuild, for diagnostics and the selftest.
    private(set) var rebuildLog: [[String: Any]] = []
    /// Called on the main thread when a rebuild failed; the recording must then be stopped.
    var onFailure: ((String) -> Void)?

    /// Recording does not start with less free space than this.
    static var minFreeBytesToStart: Int64 = 500_000_000 // about 20 minutes of float32 stereo
    /// A running recording stops below this, so the file and its conversion stay intact.
    static var minFreeBytesWhileRecording: Int64 = 200_000_000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var micUID: String? // nil = no microphone, output device is the clock
    /// Selftest "nomic" rebuild: the listener must not switch the microphone back on by itself
    /// (every rebuild changes the device list, because it creates a new private aggregate).
    private var micForcedOff = false
    private var writer: FileWriter?
    private let ring = RingBuffer(capacity: 48_000 * 2 * 10) // 10 s stereo at 48 kHz
    private static let scratchFrames = 8_192 // stereo frames per callback, more than any IO buffer
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Recorder.scratchFrames * 2)
    private var sleepAssertion = IOPMAssertionID(0)
    private(set) var sleepAssertionStatus: IOReturn = -1
    private var activity: NSObjectProtocol?
    private var inputListener: AudioObjectPropertyListenerBlock?
    private var pendingRebuild: DispatchWorkItem?

    #if DEBUG
    /// Selftest only: replaces the microphone samples with this file (`--selftest-fake-mic`).
    var fakeMicURL: URL?
    private var fakeMic: FakeMic?
    #endif

    init(url: URL) {
        self.url = url
        scratch.initialize(repeating: 0, count: Recorder.scratchFrames * 2)
    }

    deinit {
        stop()
        scratch.deallocate()
    }

    var droppedSamples: Int { ring.dropped.load(ordering: .relaxed) }
    var framesWritten: Int { writer?.framesWritten ?? 0 }

    func start() throws {
        let dir = url.deletingLastPathComponent()
        if let free = OutputLocation.freeBytes(at: dir, enough: Self.minFreeBytesToStart), free < Self.minFreeBytesToStart {
            throw RecorderError(message: tr("error.diskStart", "Te weinig schijfruimte: nog %@ MB vrij. Een opname gebruikt ongeveer 25 MB per minuut. Maak ruimte vrij en probeer opnieuw.", "\(free / 1_000_000)"))
        }
        do {
            try createTap()
            try createAggregate(allowNoMic: false)
            sampleRate = Self.nominalSampleRate(aggregateID) ?? 48_000
            let writer = try FileWriter(url: url, channels: 2, inputSampleRate: sampleRate, ring: ring)
            self.writer = writer
            #if DEBUG
            fakeMic = try fakeMicURL.map { try FakeMic(url: $0, sampleRate: sampleRate) }
            #endif
            writer.start()
            try startIO()
        } catch {
            stop()
            // Nothing was recorded; an empty .caf would show up as "unfinished recording" at the next launch.
            if writer != nil {
                try? FileManager.default.removeItem(at: url)
                let folder = url.deletingLastPathComponent()
                if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                    try? FileManager.default.removeItem(at: folder) // the recording's own, now empty folder
                }
            }
            writer = nil
            throw error
        }
        preventSleep()
        listenForInputChanges()
        startDate = Date()
    }

    /// Stops IO, destroys all Core Audio objects and closes the file. Safe to call repeatedly.
    func stop() {
        stopListening()
        stopIO()
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        writer?.finish()
        allowSleep()
    }

    /// Message when the recording must stop: write error or (almost) full disk.
    func healthProblem() -> String? {
        if let status = writer?.writeError, status != noErr {
            return tr("error.writeFailed", "Schrijven naar het opnamebestand mislukt (fout %@). De opname is gestopt; wat tot nu toe is opgenomen, blijft bewaard.", "\(status)")
        }
        if let free = OutputLocation.freeBytes(at: url.deletingLastPathComponent(), enough: Self.minFreeBytesWhileRecording), free < Self.minFreeBytesWhileRecording {
            return tr("error.diskFull", "De schijf is bijna vol (nog %@ MB vrij). De opname is gestopt; wat tot nu toe is opgenomen, blijft bewaard.", "\(free / 1_000_000)")
        }
        return nil
    }

    /// Rebuilds aggregate and IOProc with the current default input device. The tap, ring
    /// buffer and writer keep running, so the file continues. `forceNoMic` (selftest) uses the
    /// output device as the clock, as when no input device is left.
    func rebuild(forceNoMic: Bool = false) throws {
        guard tapID != kAudioObjectUnknown, let writer else { return }
        micForcedOff = forceNoMic
        let started = Date()
        let oldRate = sampleRate
        stopIO()
        // End of the last old sample, as host time. The new capture fills up to here with silence.
        let lastHost = stats.lastHostTime.load(ordering: .relaxed)
        if lastHost != 0, oldRate > 0 {
            let seconds = Double(stats.lastFrames.load(ordering: .relaxed)) / oldRate
            stats.resumeHostTime.store(lastHost + UInt64(seconds / RecorderStats.hostTicksToSeconds), ordering: .relaxed)
        }
        do {
            try createAggregate(allowNoMic: true, forceNoMic: forceNoMic)
            sampleRate = Self.nominalSampleRate(aggregateID) ?? oldRate
            writer.setInputSampleRate(sampleRate)
            try startIO()
        } catch {
            stopIO()
            throw error
        }
        rebuildLog.append(["mic": micName, "sampleRate": sampleRate, "layout": bufferLayout,
                           "seconds": Date().timeIntervalSince(started)])
    }

    // MARK: - Setup

    private var tapUUID = UUID()

    private func createTap() throws {
        let exclude = Self.ownProcessObject().map { [$0] } ?? []
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        desc.name = "Bandje"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        tapUUID = desc.uuid
        let status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            throw RecorderError(message: tr("error.tap", "Systeemaudio opnemen lukt niet (fout %@). Zet Band·je aan bij Systeeminstellingen > Privacy en beveiliging > Scherm- en systeemaudio-opname.", "\(status)"))
        }
    }

    private func createAggregate(allowNoMic: Bool, forceNoMic: Bool = false) throws {
        // The chosen microphone (menu Microfoon, else the default input) is the only sub-device and provides the clock.
        let mic = forceNoMic ? nil : Self.deviceUID(Self.inputDevice())
        guard mic != nil || allowNoMic else {
            throw RecorderError(message: tr("error.noMicRecord", "Geen microfoon gevonden. Kies een microfoon in het menu Microfoon of in Systeeminstellingen > Geluid."))
        }
        let output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard let clockUID = mic ?? Self.deviceUID(output) else {
            throw RecorderError(message: tr("error.noDevice", "Geen audioapparaat gevonden. Kies een invoerapparaat in Systeeminstellingen > Geluid."))
        }
        micUID = mic
        micName = mic.map { uid in Self.deviceName(Self.inputDevice()) ?? uid } ?? ""
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Bandje",
            kAudioAggregateDeviceUIDKey: "com.neurendal.bandje.aggregate." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // With TapAutoStart = true the aggregate only runs IO while some process plays
            // audio, so silence would be missing from the file (measured in M1).
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockUID]],
        ]
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateID)
        guard status == noErr else {
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            throw RecorderError.coreAudio(tr("step.createDevice", "Opnameapparaat maken"), status)
        }
    }

    private func startIO() throws {
        let layout = Self.inputBufferChannels(aggregateID)
        bufferLayout = layout
        // Callback buffer order (measured in M1/M2): the microphone stream(s) first, the tap
        // stream last. Without a microphone the left channel stays silent.
        guard !layout.isEmpty else { throw RecorderError(message: tr("error.deviceNoInput", "Het opnameapparaat levert geen invoer.")) }
        guard micUID == nil || layout.count >= 2 else { throw RecorderError(message: tr("error.micNoInput", "De microfoon levert geen invoer.")) }
        let tapIndex = layout.count - 1
        let hasMic = micUID != nil

        let ring = self.ring
        let scratch = self.scratch
        let maxFrames = Self.scratchFrames
        let stats = self.stats
        let rate = sampleRate
        let ticksToSeconds = RecorderStats.hostTicksToSeconds
        let maxGapFrames = Int(rate * 5) // the ring holds 10 s; a rebuild takes well under a second
        #if DEBUG
        let fakeMic = self.fakeMic
        #endif
        // Realtime callback: no allocation, locks, logging or file IO.
        // Microphone (first buffer, channels averaged) -> left, tap (channels averaged) -> right.
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inData, inTime, _, _ in
            stats.allCallbacks.wrappingAdd(1, ordering: .relaxed)
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard tapIndex < list.count else { return }
            let tap = list[tapIndex]
            guard let tapSrc = tap.mData?.assumingMemoryBound(to: Float.self), tap.mDataByteSize > 0 else {
                stats.emptyCallbacks.wrappingAdd(1, ordering: .relaxed)
                return
            }
            let tapCh = Int(max(tap.mNumberChannels, 1))
            let frames = min(Int(tap.mDataByteSize) / (MemoryLayout<Float>.size * tapCh), maxFrames)
            let host = inTime.pointee.mHostTime != 0 ? inTime.pointee.mHostTime : mach_absolute_time()

            // First callback after a rebuild: silence for the time the capture was down.
            let resume = stats.resumeHostTime.load(ordering: .relaxed)
            if resume != 0 {
                stats.resumeHostTime.store(0, ordering: .relaxed)
                if host > resume {
                    var gap = min(Int(Double(host - resume) * ticksToSeconds * rate), maxGapFrames)
                    stats.gapFrames.wrappingAdd(gap, ordering: .relaxed)
                    scratch.update(repeating: 0, count: maxFrames * 2)
                    while gap > 0 {
                        let n = min(gap, maxFrames)
                        ring.write(scratch, count: n * 2)
                        gap -= n
                    }
                }
            }

            let mic = list[0]
            let micSrc = hasMic ? mic.mData?.assumingMemoryBound(to: Float.self) : nil
            let micCh = Int(max(mic.mNumberChannels, 1))
            let micFrames = micSrc == nil ? 0 : Int(mic.mDataByteSize) / (MemoryLayout<Float>.size * micCh)
            let tapScale = 1 / Float(tapCh)
            let micScale = 1 / Float(micCh)
            var tapPeak: Float = 0
            var micPeak: Float = 0
            var f = 0
            while f < frames {
                var left: Float = 0
                if let micSrc, f < micFrames {
                    var c = 0
                    while c < micCh { left += micSrc[f * micCh + c]; c += 1 }
                    left *= micScale
                }
                var right: Float = 0
                var c = 0
                while c < tapCh { right += tapSrc[f * tapCh + c]; c += 1 }
                right *= tapScale
                scratch[2 * f] = left
                scratch[2 * f + 1] = right
                micPeak = max(micPeak, abs(left))
                tapPeak = max(tapPeak, abs(right))
                f += 1
            }
            #if DEBUG
            if let fakeMic {
                micPeak = fakeMic.fill(scratch, frames: frames)
            }
            #endif
            if ring.write(scratch, count: frames * 2), stats.firstHostTime.load(ordering: .relaxed) == 0 {
                stats.firstHostTime.store(host, ordering: .relaxed)
            }
            stats.lastHostTime.store(host, ordering: .relaxed)
            stats.lastFrames.store(frames, ordering: .relaxed)
            stats.callbacks.wrappingAdd(1, ordering: .relaxed)
            if tapPeak > Float(bitPattern: stats.peakBits.load(ordering: .relaxed)) {
                stats.peakBits.store(tapPeak.bitPattern, ordering: .relaxed)
            }
            if micPeak > Float(bitPattern: stats.micPeakBits.load(ordering: .relaxed)) {
                stats.micPeakBits.store(micPeak.bitPattern, ordering: .relaxed)
            }
            stats.noteLevel(mic: micPeak, system: tapPeak)
        }
        guard status == noErr, let procID else { throw RecorderError.coreAudio(tr("step.ioProc", "Audiocallback maken"), status) }
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw RecorderError(message: tr("error.startFailed", "Opname starten mislukt (fout %@). Controleer de toestemming bij Systeeminstellingen > Privacy en beveiliging > Scherm- en systeemaudio-opname.", "\(startStatus)"))
        }
    }

    /// Stops and destroys IOProc and aggregate (not the tap). AudioDeviceStop returns after
    /// the last callback, so afterwards nothing writes into the ring buffer.
    private func stopIO() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - Sleep and device changes

    private func preventSleep() {
        sleepAssertionStatus = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            // ASCII: pmset and Activity Monitor show a "·" as a broken character.
            "Bandje neemt op" as CFString, &sleepAssertion)
        // Also keeps App Nap from stretching timers (a 600 s selftest took 640 s without it).
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Bandje neemt op")
    }

    private func allowSleep() {
        if sleepAssertionStatus == kIOReturnSuccess {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertionStatus = -1
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private static var inputDeviceAddress = address(kAudioHardwarePropertyDefaultInputDevice)
    /// Device list changed: the chosen microphone may have been plugged in or out.
    private static var devicesAddress = address(kAudioHardwarePropertyDevices)

    private func listenForInputChanges() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.inputChanged() }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if AudioObjectAddPropertyListenerBlock(system, &Self.inputDeviceAddress, DispatchQueue.main, block) == noErr {
            if AudioObjectAddPropertyListenerBlock(system, &Self.devicesAddress, DispatchQueue.main, block) != noErr {
                AudioObjectRemovePropertyListenerBlock(system, &Self.inputDeviceAddress, DispatchQueue.main, block)
                return
            }
            inputListener = block
        }
    }

    private func stopListening() {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        if let block = inputListener {
            let system = AudioObjectID(kAudioObjectSystemObject)
            AudioObjectRemovePropertyListenerBlock(system, &Self.inputDeviceAddress, DispatchQueue.main, block)
            AudioObjectRemovePropertyListenerBlock(system, &Self.devicesAddress, DispatchQueue.main, block)
            inputListener = nil
        }
    }

    /// The user picked another microphone in the menu: same path as a device change.
    func micSelectionChanged() { inputChanged() }

    /// The microphone changed (default input, chosen mic plugged in or out, or a new choice). Connecting AirPods fires several changes in a row, so wait
    /// briefly and rebuild once if the microphone really is a different one.
    private func inputChanged() {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.procID != nil || self.tapID != kAudioObjectUnknown, !self.micForcedOff else { return }
            let uid = Self.deviceUID(Self.inputDevice())
            guard uid != self.micUID else { return }
            do {
                try self.rebuild()
            } catch {
                self.onFailure?(tr("error.micSwitch", "Wisselen van microfoon is mislukt: %@ De opname is gestopt; wat tot nu toe is opgenomen, blijft bewaard.", error.localizedDescription))
            }
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(selector)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return device
    }

    /// UID of the microphone chosen in the menu (nil = system default). `defaults` key `micUID`.
    static var chosenMicUID: String? {
        get { UserDefaults.standard.string(forKey: "micUID") }
        set { UserDefaults.standard.set(newValue, forKey: "micUID") }
    }

    /// Makes `device` the macOS default input, for every app (calls included).
    @discardableResult
    static func setDefaultInput(_ device: AudioObjectID) -> OSStatus {
        var addr = inputDeviceAddress
        var id = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    static func transportType(_ device: AudioObjectID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value
    }

    static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        transportType(device) == kAudioDeviceTransportTypeBuiltIn
    }

    /// The best microphone to switch to when the current one is silent: USB first, then Bluetooth,
    /// then other external inputs, and an iPhone via Continuity Camera last (during a call relayed
    /// from that iPhone it is a confusing choice). Never built-in, virtual or aggregate devices.
    static func suggestedMicrophone(excluding current: AudioObjectID) -> (id: AudioObjectID, uid: String, name: String)? {
        func rank(_ t: UInt32) -> Int {
            switch t {
            case kAudioDeviceTransportTypeUSB: 0
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: 1
            case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: 3
            default: 2
            }
        }
        return inputDevices()
            .filter { d in
                let t = transportType(d.id)
                return d.id != current && !isBuiltIn(d.id) && t != kAudioDeviceTransportTypeVirtual
                    && t != kAudioDeviceTransportTypeAggregate
            }
            .min { rank(transportType($0.id)) < rank(transportType($1.id)) }
    }

    /// True when the MacBook lid is closed: then macOS switches the built-in microphone off.
    static func lidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    /// The chosen microphone when it is connected, otherwise the default input device.
    static func inputDevice() -> AudioObjectID {
        if let uid = chosenMicUID, let device = inputDevices().first(where: { $0.uid == uid }) { return device.id }
        return defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// All devices with at least one input channel, by name.
    static func inputDevices() -> [(id: AudioObjectID, uid: String, name: String)] {
        var addr = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputBufferChannels(id).reduce(0, +) > 0, let uid = deviceUID(id), isUserFacing(id, uid: uid) else { return nil }
            return (id, uid, deviceName(id) ?? uid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Devices that can play sound (menu Geluidsuitvoer). A USB microphone with a headphone
    /// jack is one too, which is why macOS can switch the sound to it when AirPods go away.
    static func outputDevices() -> [(id: AudioObjectID, uid: String, name: String)] {
        var addr = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard bufferChannels(id, kAudioObjectPropertyScopeOutput).reduce(0, +) > 0, let uid = deviceUID(id), isUserFacing(id, uid: uid) else { return nil }
            return (id, uid, deviceName(id) ?? uid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// False for devices nobody chose: the aggregates Core Audio makes for an app that uses the default
    /// devices (`CADefaultDeviceAggregate-<pid>-<n>`, also for Bandje itself), Bandje's own private
    /// aggregates, and hidden devices. Aggregates made in Audio MIDI Setup stay.
    static func isUserFacing(_ id: AudioObjectID, uid: String) -> Bool {
        let name = deviceName(id) ?? ""
        for prefix in ["CADefaultDeviceAggregate", "com.neurendal.bandje.", "nl.celenation.bandje."]
        where uid.hasPrefix(prefix) || name.hasPrefix(prefix) {
            return false
        }
        var addr = address(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &hidden) == noErr, hidden != 0 { return false }
        return true
    }

    static func outputDevice() -> AudioObjectID { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }

    /// Sets the macOS sound output, as Control Center does. Only on the user's choice.
    static func setDefaultOutput(_ device: AudioObjectID) -> OSStatus {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        guard device != kAudioObjectUnknown else { return nil }
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = address(kAudioDevicePropertyDeviceUID)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    /// Channel count per input buffer of a device, in callback order.
    static func inputBufferChannels(_ device: AudioObjectID) -> [Int] { bufferChannels(device, kAudioObjectPropertyScopeInput) }

    static func bufferChannels(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, listPtr) == noErr else { return [] }
        return UnsafeMutableAudioBufferListPointer(listPtr).map { Int($0.mNumberChannels) }
    }
}

#if DEBUG
/// Selftest only: an audio file, preloaded as mono at the device rate, that replaces the
/// microphone samples from the first IO callback on. Silence after the file ends.
/// `fill` runs on the realtime thread and only touches preallocated memory.
final class FakeMic: @unchecked Sendable {
    private let samples: UnsafeMutablePointer<Float>
    private let count: Int
    private var position = 0 // only touched by the IO thread

    init(url: URL, sampleRate: Double) throws {
        var ref: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &ref) == noErr, let ref else {
            throw RecorderError(message: "Fake mic: kan \(url.path) niet openen.")
        }
        defer { ExtAudioFileDispose(ref) }
        var fileFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(ref, kExtAudioFileProperty_FileDataFormat, &size, &fileFormat)
        var fileFrames: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(ref, kExtAudioFileProperty_FileLengthFrames, &size, &fileFrames)
        var client = FileWriter.floatFormat(rate: sampleRate, channels: 1)
        ExtAudioFileSetProperty(ref, kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        let capacity = Int(Double(fileFrames) * sampleRate / max(fileFormat.mSampleRate, 1)) + 4_096
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
        var total = 0
        while total < capacity {
            var frames = UInt32(min(4_096, capacity - total))
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: frames * 4, mData: samples + total))
            guard ExtAudioFileRead(ref, &frames, &list) == noErr, frames > 0 else { break }
            total += Int(frames)
        }
        count = total
    }

    deinit { samples.deallocate() }

    /// Overwrites the left channel of `frames` interleaved stereo frames. Returns the peak.
    func fill(_ stereo: UnsafeMutablePointer<Float>, frames: Int) -> Float {
        var peak: Float = 0
        var f = 0
        while f < frames {
            let v: Float = position < count ? samples[position] : 0
            stereo[2 * f] = v
            peak = max(peak, abs(v))
            position += 1
            f += 1
        }
        return peak
    }
}
#endif
