// Lists Core Audio devices and taps. Usage: swift scripts/dev/list-devices.swift [--leaks]
// With --leaks: exits 1 if any device or tap named "Bandje..." exists (private ones vanish with their process).
import CoreAudio
import Foundation

func addr(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func ids(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = addr(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
    var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &list)
    return list
}

func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var a = addr(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return "?" }
    return value.takeRetainedValue() as String
}

func u32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
    var a = addr(selector, scope)
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
    return v
}

func channels(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
    var a = addr(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, list) == noErr else { return 0 }
    return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
}

let defIn = ids(kAudioHardwarePropertyDefaultInputDevice).first ?? 0
let defOut = ids(kAudioHardwarePropertyDefaultOutputDevice).first ?? 0
let defSys = ids(kAudioHardwarePropertyDefaultSystemOutputDevice).first ?? 0
var leaks: [String] = []
for d in ids(kAudioHardwarePropertyDevices) {
    let name = string(d, kAudioObjectPropertyName)
    var flags: [String] = []
    if d == defIn { flags.append("default-in") }
    if d == defOut { flags.append("default-out") }
    if d == defSys { flags.append("system-out") }
    if u32(d, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0 { flags.append("running") }
    print("device \(d): \(name) in=\(channels(d, kAudioObjectPropertyScopeInput)) out=\(channels(d, kAudioObjectPropertyScopeOutput)) transport=\(String(format: "%08x", u32(d, kAudioDevicePropertyTransportType))) \(flags.joined(separator: ","))")
    if name.hasPrefix("Bandje") { leaks.append("device \(name)") }
}
for t in ids(kAudioHardwarePropertyTapList) {
    let name = string(t, kAudioObjectPropertyName)
    print("tap \(t): \(name)")
    if name.hasPrefix("Bandje") { leaks.append("tap \(name)") }
}
if CommandLine.arguments.contains("--leaks") {
    if leaks.isEmpty { print("LEAKS: none") } else { print("LEAKS: \(leaks)"); exit(1) }
}
