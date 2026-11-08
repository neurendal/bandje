import AppKit
import AVFoundation
import CoreAudio
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

    /// One line in Instellingen > Toestemmingen.
    enum State { case allowed, denied, notAsked, unknown }

    static var microphone: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// macOS has no public way to read the system-audio permission. What Bandje knows is whether
    /// sound from the Mac came in during the last recording (`noteSystemAudio`): yes means allowed;
    /// silence can also mean nothing played.
    static var systemAudio: State {
        guard let heard = UserDefaults.standard.object(forKey: "systemAudioHeard") as? Bool else { return .notAsked }
        return heard ? .allowed : .unknown
    }

    /// After every recording of at least 5 seconds: did the right channel (the Mac's sound) get any signal?
    static func noteSystemAudio(peak: Float, seconds: TimeInterval) {
        guard seconds >= 5 else { return }
        UserDefaults.standard.set(peak > 0.0001, forKey: "systemAudioHeard")
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
