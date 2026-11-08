import Carbon.HIToolbox

/// Global hotkeys via Carbon `RegisterEventHotKey`. Works from any app and needs no Accessibility
/// permission; a registered key is consumed (the frontmost app does not see it). Handlers run on
/// the main thread.
@MainActor
enum Hotkey {
    enum ID: UInt32 {
        case record = 1, dictate, dictateReturn, dictateEnter, dictateEscape
    }

    private struct Handlers {
        var pressed: () -> Void
        var released: (() -> Void)?
    }

    private static var handlers: [UInt32: Handlers] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var eventHandler: EventHandlerRef?

    /// Returns the OSStatus of the registration (noErr on success, also when already registered).
    @discardableResult
    static func register(_ id: ID, key: Int, modifiers: Int = 0, pressed: @escaping () -> Void,
                         released: (() -> Void)? = nil) -> OSStatus {
        if eventHandler == nil {
            var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                MainActor.assumeIsolated {
                    guard let h = Hotkey.handlers[hk.id] else { return }
                    if pressed { h.pressed() } else { h.released?() }
                }
                return noErr
            }, specs.count, &specs, nil, &eventHandler)
            guard status == noErr else { return status }
        }
        handlers[id.rawValue] = Handlers(pressed: pressed, released: released)
        if refs[id.rawValue] != nil { return noErr }
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x424E_444A), id: id.rawValue) // 'BNDJ'
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), hk, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id.rawValue] = ref } else { handlers[id.rawValue] = nil }
        return status
    }

    static func unregister(_ id: ID) {
        if let ref = refs.removeValue(forKey: id.rawValue) { UnregisterEventHotKey(ref) }
        handlers[id.rawValue] = nil
    }

    nonisolated static let controlOptionCommand = controlKey | optionKey | cmdKey
}
