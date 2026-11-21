import AppKit
import AVFoundation
import CoreAudio
import SwiftUI
import Synchronization

enum Permissions {
    static var microphoneDenied: String { tr("error.micDenied", "Band·je mag de microfoon niet gebruiken. Zet Band·je aan bij Systeeminstellingen > Privacy en beveiliging > Microfoon.") }

    /// Asks for microphone access the first time; afterwards returns the stored decision.
    static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// One line in Instellingen > Toegang.
    enum State { case allowed, denied, notAsked, unknown }

    static var microphone: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// macOS has no public way to read the system-audio permission. Band·je knows it from its own
    /// check (`SystemAudioCheck`, the latest outcome) and from whether sound from the Mac came in
    /// during the last recording (`noteSystemAudio`): sound means allowed; silence can also mean
    /// nothing played.
    static var systemAudio: State {
        let defaults = UserDefaults.standard
        if let checked = defaults.object(forKey: "systemAudioChecked") as? Bool { return checked ? .allowed : .denied }
        guard let heard = defaults.object(forKey: "systemAudioHeard") as? Bool else { return .notAsked }
        return heard ? .allowed : .unknown
    }

    /// The outcome of the latest `SystemAudioCheck`.
    static func noteSystemAudioCheck(_ allowed: Bool) {
        UserDefaults.standard.set(allowed, forKey: "systemAudioChecked")
    }

    /// After every recording of at least 5 seconds: did the right channel (the Mac's sound) get any signal?
    /// Sound proves the permission; silence proves nothing, so it doesn't overrule a check.
    static func noteSystemAudio(peak: Float, seconds: TimeInterval) {
        guard seconds >= 5 else { return }
        let heard = peak > 0.0001
        UserDefaults.standard.set(heard, forKey: "systemAudioHeard")
        if heard { noteSystemAudioCheck(true) }
    }

    /// The check at launch (BandjeApp.checkPermissionsAtLaunch); off after "Do not show this message again".
    static var checkAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "permissionsCheckAtLaunch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "permissionsCheckAtLaunch") }
    }

    @MainActor static var paste: State { Paste.allowed ? .allowed : .denied }

    /// System Settings > Privacy & Security, on the list for `anchor`
    /// (`Privacy_Microphone`, `Privacy_ScreenCapture`, `Privacy_Accessibility`).
    static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Is the system-audio permission on? (owner, 2026-11-12: a tester's first call recording lacked the
/// other side.) macOS has no API to read it, but it hands a process tap only zeros while it is off,
/// also a tap of Band·je's own sound. So Band·je plays an inaudible signal (-70 dB, and muted by the
/// tap itself, so it never reaches the speakers) for half a second and taps its own process:
/// signal = allowed, zeros = not allowed. Measured 2026-11-12 on macOS 26: allowed 0.050 for a
/// 0.050 tone, denied 0 (own process and global tap alike), also with the output muted or at
/// volume 0. The signal goes to the built-in speakers when there are some, so AirPods are never
/// woken or switched over from another device.
///
/// The first run makes macOS ask ("Band·je would like to record your system audio"); while that
/// question is open the result is zeros too, so callers that may have caused it check again.
enum SystemAudioCheck {
    /// true: allowed; false: not allowed, or macOS's question is still open; nil: could not tell.
    static func run() async -> Bool? {
        let result = await Task.detached(priority: .userInitiated) { await measure() }.value
        if let result { Permissions.noteSystemAudioCheck(result) }
        return result
    }

    /// For a moment that may have made macOS ask (Sta toe…, the first recording): while the answer
    /// is "not allowed", checks again every 2 seconds for up to `patience`, time to answer the question.
    static func runAllowingPrompt(patience: Duration) async -> Bool? {
        let deadline = ContinuousClock.now + patience
        while true {
            let result = await run()
            if result != false || ContinuousClock.now >= deadline || Task.isCancelled { return result }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// True when another app is playing sound (a call, a video) right now.
    static func otherProcessPlays() -> Bool {
        let own = Recorder.ownProcessObject()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
        addr.mSelector = kAudioProcessPropertyIsRunningOutput
        return ids.contains { id in
            guard id != own else { return false }
            var running: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &running) == noErr && running != 0
        }
    }

    private final class Box: @unchecked Sendable {
        let peak = Atomic<UInt32>(0)
        let playing = Atomic<Bool>(false)
        var phase: Double = 0  // only touched by the output IO thread
    }

    private static let amplitude: Float = 0.0003

    private static func measure() async -> Bool? {
        guard let own = Recorder.ownProcessObject() else { return nil }
        let output = outputDevice()
        guard output != kAudioObjectUnknown, let format = floatFormat(output) else { return nil }
        let box = Box()

        // The tap: Band·je's own sound only, muted while tapped.
        let desc = CATapDescription(stereoMixdownOfProcesses: [own])
        desc.name = "Bandje check"
        desc.isPrivate = true
        desc.muteBehavior = .muted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return nil }
        defer { AudioHardwareDestroyProcessTap(tap) }
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Bandje check",
            kAudioAggregateDeviceUIDKey: "com.neurendal.bandje.check." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregate) == noErr else { return nil }
        defer { AudioHardwareDestroyAggregateDevice(aggregate) }
        var tapProc: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcIDWithBlock(&tapProc, aggregate, nil, { _, input, _, _, _ in
            guard box.playing.load(ordering: .relaxed) else { return }
            var peak: Float = 0
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let p = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size { peak = max(peak, abs(p[i])) }
            }
            if peak > Float(bitPattern: box.peak.load(ordering: .relaxed)) { box.peak.store(peak.bitPattern, ordering: .relaxed) }
        }) == noErr, let tapProc else { return nil }
        defer { AudioDeviceDestroyIOProcID(aggregate, tapProc) }

        // The signal: a 440 Hz sine straight into the output device.
        var outProc: AudioDeviceIOProcID?
        let rate = format.mSampleRate
        guard AudioDeviceCreateIOProcIDWithBlock(&outProc, output, nil, { _, _, _, outData, _ in
            let on = box.playing.load(ordering: .relaxed)
            for buffer in UnsafeMutableAudioBufferListPointer(outData) {
                guard let p = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = max(Int(buffer.mNumberChannels), 1)
                let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                var phase = box.phase
                for f in 0..<frames {
                    let v = on ? amplitude * Float(sin(phase)) : 0
                    for c in 0..<channels { p[f * channels + c] = v }
                    phase += 2 * .pi * 440 / rate
                }
                box.phase = phase.truncatingRemainder(dividingBy: 2 * .pi)
            }
        }) == noErr, let outProc else { return nil }
        defer { AudioDeviceDestroyIOProcID(output, outProc) }

        guard AudioDeviceStart(aggregate, tapProc) == noErr else { return nil }
        defer { AudioDeviceStop(aggregate, tapProc) }
        guard AudioDeviceStart(output, outProc) == noErr else { return nil }
        defer { AudioDeviceStop(output, outProc) }
        try? await Task.sleep(for: .milliseconds(150))
        box.playing.store(true, ordering: .relaxed)
        try? await Task.sleep(for: .milliseconds(500))
        box.playing.store(false, ordering: .relaxed)
        try? await Task.sleep(for: .milliseconds(50))
        return Float(bitPattern: box.peak.load(ordering: .relaxed)) > amplitude / 4
    }

    /// The built-in speakers when there are some (never AirPods), else the default output.
    private static func outputDevice() -> AudioObjectID {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--check-output"), i + 1 < CommandLine.arguments.count,
           let d = Recorder.outputDevices().first(where: { $0.name.localizedCaseInsensitiveContains(CommandLine.arguments[i + 1]) }) {
            return d.id
        }
        #endif
        if let speakers = Recorder.outputDevices().first(where: { Recorder.isBuiltIn($0.id) }) { return speakers.id }
        return Recorder.outputDevice()
    }

    /// The device's output format, when it takes 32-bit float (Core Audio's usual IO format).
    private static func floatFormat(_ device: AudioObjectID) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioObjectPropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else { return nil }
        return format
    }
}

/// "Geluid van je Mac" in the welcome and in Instellingen > Toegang: Sta toe… runs the check (macOS
/// asks then), a check mark once allowed, Open instellingen… when not; after that Band·je looks
/// again every 3 seconds, and offers a restart in case macOS wants one.
struct SystemAudioPermissionControl: View {
    let restart: () -> Void
    @State private var state = Permissions.systemAudio
    @State private var checking = false
    @State private var openedSettings = false

    var body: some View {
        Group {
            if checking {
                ProgressView().controlSize(.small)
            } else {
                switch state {
                case .allowed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text(tr("settings.permissions.allowed", "Toegestaan")))
                case .denied:
                    if openedSettings {
                        Button(tr("settings.language.restartNow", "Herstart Band·je")) { restart() }
                            .help(tr("settings.permissions.system.restart", "Net aangezet? Werkt het nog niet, dan herstart Band·je."))
                    } else {
                        Button(tr("settings.permissions.open", "Open instellingen…")) {
                            Permissions.openSettings("Privacy_ScreenCapture")
                            openedSettings = true
                        }
                    }
                default:
                    Button(tr("welcome.allow", "Sta toe…")) {
                        checking = true
                        Task {
                            _ = await SystemAudioCheck.runAllowingPrompt(patience: .seconds(30))
                            state = Permissions.systemAudio
                            checking = false
                        }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                if !checking { state = Permissions.systemAudio }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // After Open instellingen…: look again every 3 seconds, so switching it on shows here.
        .task(id: openedSettings) {
            guard openedSettings else { return }
            while !Task.isCancelled, Permissions.systemAudio == .denied {
                try? await Task.sleep(for: .seconds(3))
                if !checking, !Task.isCancelled { _ = await SystemAudioCheck.run() }
            }
        }
    }
}

#if DEBUG
/// DEBUG-only `--probe-permissions`: asks for microphone access, then creates a
/// process tap + private aggregate device, runs it briefly so macOS asks for
/// system-audio permission, tears everything down and writes the outcome to
/// ~/Music/Bandje/selftest/last.json.
@MainActor
enum PermissionProbe {
    final class Stats: Sendable {
        let callbacks = Atomic<Int>(0)
        let peakBits = Atomic<UInt32>(0)
    }

    static func run() async {
        var result: [String: Any] = ["mode": "probe-permissions", "date": ISO8601DateFormatter().string(from: Date())]
        var errors: [String] = []

        // 1. Microphone
        let micBefore = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool
        if micBefore == .notDetermined {
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            micGranted = micBefore == .authorized
        }
        result["microphone"] = micGranted ? "authorized" : "denied"
        if !micGranted { errors.append("microphone not authorized") }

        // 2. System audio: tap + aggregate + short IO
        let stats = Stats()
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "Bandje probe"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        result["tapStatus"] = Int(tapStatus)

        var aggID = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        if tapStatus == noErr {
            var aggDesc: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Bandje probe",
                kAudioAggregateDeviceUIDKey: "com.neurendal.bandje.probe." + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            if let outUID = defaultOutputDeviceUID() {
                aggDesc[kAudioAggregateDeviceMainSubDeviceKey] = outUID
                aggDesc[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outUID]]
            }
            let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
            result["aggregateStatus"] = Int(aggStatus)

            if aggStatus == noErr {
                let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, _, _ in
                    stats.callbacks.wrappingAdd(1, ordering: .relaxed)
                    var peak: Float = 0
                    for buf in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)) {
                        guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        for i in 0..<Int(buf.mDataByteSize) / MemoryLayout<Float>.size { peak = max(peak, abs(p[i])) }
                    }
                    if peak > Float(bitPattern: stats.peakBits.load(ordering: .relaxed)) {
                        stats.peakBits.store(peak.bitPattern, ordering: .relaxed)
                    }
                }
                result["ioProcStatus"] = Int(ioStatus)
                if ioStatus == noErr, let procID {
                    result["ioStartStatus"] = Int(AudioDeviceStart(aggID, procID))
                }
            } else {
                errors.append("AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
            }
        } else {
            errors.append("AudioHardwareCreateProcessTap failed: \(tapStatus)")
        }

        // 3. Let the user answer the system prompt(s)
        NSApp.activate()
        let wait = NSAlert()
        wait.messageText = "Bandje: toestemmingen"
        wait.informativeText = "Klik bij de vragen over microfoon en systeemaudio-opname op 'Sta toe'. Klik daarna hier op Klaar."
        wait.addButton(withTitle: "Klaar")
        wait.runModal()

        // 4. Tear down
        if let procID {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
        }
        if aggID != kAudioObjectUnknown { result["aggregateDestroyStatus"] = Int(AudioHardwareDestroyAggregateDevice(aggID)) }
        if tapID != kAudioObjectUnknown { result["tapDestroyStatus"] = Int(AudioHardwareDestroyProcessTap(tapID)) }

        let peak = Float(bitPattern: stats.peakBits.load(ordering: .relaxed))
        result["ioCallbacks"] = stats.callbacks.load(ordering: .relaxed)
        result["tapPeak"] = Double(peak)
        result["errors"] = errors
        let path = writeResult(result)

        let done = NSAlert()
        done.messageText = errors.isEmpty ? "Probe klaar" : "Probe klaar, met fouten"
        done.informativeText = """
        Microfoon: \(micGranted ? "toegestaan" : "geweigerd")
        Systeemaudio-tap: \(tapStatus == noErr ? "gemaakt en verwijderd" : "fout \(tapStatus)")
        Controleer in Systeeminstellingen > Privacy en beveiliging dat Bandje bij Microfoon en bij Systeemaudio-opname aan staat.
        Resultaat: \(path)
        """
        done.runModal()
        NSApp.terminate(nil)
    }

    private static func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func writeResult(_ result: [String: Any]) -> String {
        // Real home: inside the sandbox homeDirectoryForCurrentUser is the container.
        let dir = OutputLocation.defaultDirectory.appendingPathComponent("selftest")
        let file = dir.appendingPathComponent("last.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file)
        } catch {
            NSLog("Bandje probe: could not write result: \(error)")
        }
        return file.path
    }
}
#endif
