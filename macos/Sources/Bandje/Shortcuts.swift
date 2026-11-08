import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreAudio
import SwiftUI

/// A global shortcut the user can change: Carbon key code + Carbon modifiers.
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int

    static let defaultRecord = Shortcut(keyCode: kVK_ANSI_R, modifiers: Hotkey.controlOptionCommand)
    static let defaultDictate = Shortcut(keyCode: kVK_ANSI_D, modifiers: Hotkey.controlOptionCommand)

    static var record: Shortcut {
        get { load("shortcut.record") ?? defaultRecord }
        set { save(newValue, "shortcut.record") }
    }
    static var dictate: Shortcut {
        get { load("shortcut.dictate") ?? defaultDictate }
        set { save(newValue, "shortcut.dictate") }
    }

    private static func load(_ key: String) -> Shortcut? {
        guard let d = UserDefaults.standard.dictionary(forKey: key),
              let code = d["keyCode"] as? Int, let mods = d["modifiers"] as? Int else { return nil }
        return Shortcut(keyCode: code, modifiers: mods)
    }

    private static func save(_ s: Shortcut, _ key: String) {
        UserDefaults.standard.set(["keyCode": s.keyCode, "modifiers": s.modifiers], forKey: key)
    }

    /// From a key press in the shortcut window. Needs ⌘, ⌃ or ⌥, except for F1–F20.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.shift) { mods |= shiftKey }
        let code = Int(event.keyCode)
        guard mods & (cmdKey | optionKey | controlKey) != 0 || Self.functionKeys[code] != nil else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// "⌃⌥⌘R", in Apple's modifier order.
    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName.uppercased()
    }

    /// For NSMenuItem: key equivalent and modifier mask, so the menu shows the same shortcut.
    var menuKey: (String, NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        if let f = Self.functionKeys[keyCode] {
            return (String(UnicodeScalar(UInt32(NSF1FunctionKey + f - 1))!), flags)
        }
        return (Self.special[keyCode] == nil ? keyName.lowercased() : "", flags)
    }

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8,
        kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
        kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20,
    ]
    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    /// The character of the key on the current keyboard layout (so AZERTY shows A where QWERTY has Q).
    private var keyName: String {
        if let f = Self.functionKeys[keyCode] { return "F\(f)" }
        if let s = Self.special[keyCode] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Interface language: one of the app's 10 languages, or nil to follow macOS.
/// Stored as Bandje's own `AppleLanguages`, so only Bandje changes; takes effect after a restart.
enum AppLanguage {
    static let codes = ["nl", "en", "de", "fr", "es", "it", "pt", "pl", "ru", "uk"]

    /// "Nederlands", "English", "Deutsch"… in the language itself.
    static func name(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
    }

    static var chosen: String? {
        get {
            let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            return (domain?["AppleLanguages"] as? [String])?.first.flatMap { code in
                codes.first { code == $0 || code.hasPrefix($0 + "-") }
            }
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: "AppleLanguages") }
            else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        }
    }
}

/// "Open Bandje bij inloggen": macOS's own login item for the app (works in the sandbox and from
/// the App Store). Only ever switched on by the user: in the welcome or in Instellingen.
@MainActor
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    /// Registered, but switched off under System Settings > General > Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Window "Instellingen…": tabs as in macOS Settings, each one short: Algemeen (starting,
/// language), Sneltoetsen, Transcriptie, Opslag (iCloud, folder) and Toegang (permissions). Rows
/// have the label left and the control right, in a card per section.
@MainActor
final class SettingsWindow {
    private static var window: NSWindow?

    /// `apply` registers the shortcuts and returns an error text when that fails (taken by another
    /// app); `chooseFolder(reset)` returns true when the folder changed; `restart` relaunches Bandje.
    /// `tab`: the tab to show (0…4; the selftest's screenshots).
    static func show(apply: @escaping (_ record: Shortcut, _ dictate: Shortcut) -> String?,
                     chooseFolder: @escaping (_ reset: Bool) -> Bool,
                     restart: @escaping () -> Void,
                     setSync: @escaping (Bool) -> Bool = { _ in false },
                     chooseMic: @escaping (String) -> Void = { _ in },
                     chooseOutput: @escaping (String) -> String? = { _ in nil },
                     tab: Int? = nil) {
        if let window {
            if let tab, let tabs = window.contentViewController as? NSTabViewController { tabs.selectedTabViewItemIndex = tab }
            window.makeKeyAndOrderFront(nil); NSApp.activate(); return
        }
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func add(_ title: String, _ symbol: String, _ view: some View) {
            // The selected tab, buttons and links take the app's accent (Band·je red, readable in
            // dark mode too); only the switches are band.je navy (RowToggle).
            let host = NSHostingController(rootView: view.frame(width: 460).padding(20))
            host.sizingOptions = .preferredContentSize
            host.title = title  // the window's title follows the tab (was "Untitled")
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(tr("settings.tab.general", "Algemeen"), "gearshape", GeneralSettings(restart: restart))
        add(tr("settings.shortcuts", "Sneltoetsen"), "command", ShortcutSettings(apply: apply))
        add(tr("settings.tab.sound", "Geluid"), "speaker.wave.2", SoundSettings(chooseMic: chooseMic, chooseOutput: chooseOutput))
        add(tr("settings.tab.transcription", "Transcriptie"), "text.quote", TranscriptionSettings())
        add(tr("settings.tab.storage", "Opslag"), "externaldrive", StorageSettings(chooseFolder: chooseFolder, setSync: setSync))
        add(tr("welcome.access", "Toegang"), "hand.raised", AccessSettings(restart: restart))
        if let tab { tabs.selectedTabViewItemIndex = tab }
        let w = NSWindow(contentViewController: tabs)
        w.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label  // as after a tab switch
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window = nil }
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: Parts

/// A section: a small grey heading, a card with rows, a short grey note under it.
private struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    var red = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(red ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row: the label (and an optional note under it) left, the control right.
private struct SettingsRow<Control: View>: View {
    let label: String
    var note: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 9)
    }
}

/// A switch on the right of a row, as in macOS Settings.
private struct RowToggle: View {
    @Binding var isOn: Bool
    var body: some View { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Color.navy) }
}

// MARK: Algemeen

private struct GeneralSettings: View {
    let restart: () -> Void
    @State private var windowAtLaunch = LaunchPolicy.windowAtLaunch
    @State private var showInDock = UserDefaults.standard.bool(forKey: "showInDock")
    @State private var loginOn = LoginItem.isOn
    @State private var loginApproval = LoginItem.needsApproval
    @State private var loginError: String?
    @State private var language = AppLanguage.chosen ?? ""
    @State private var languageChanged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: tr("settings.login", "Starten"),
                         footer: loginApproval ? tr("settings.login.approval", "Uitgezet in Systeeminstellingen. Zet Band·je daar aan onder Inlogonderdelen en extensies.") : loginError,
                         red: loginError != nil) {
                SettingsRow(label: tr("settings.window.atLaunch", "Toon het Band·je-venster bij het starten"),
                            note: tr("settings.window.atLaunch.hint", "Uit: alleen het cassettebandje in de menubalk.")) {
                    RowToggle(isOn: $windowAtLaunch)
                }
                Divider()
                SettingsRow(label: tr("settings.dock", "Altijd in het Dock")) { RowToggle(isOn: $showInDock) }
                Divider()
                SettingsRow(label: tr("settings.login.toggle", "Open Band·je bij inloggen")) {
                    if loginApproval {
                        Button(tr("settings.permissions.open", "Open instellingen…")) { SMAppService.openSystemSettingsLoginItems() }
                    } else {
                        RowToggle(isOn: Binding(get: { loginOn }, set: { on in
                            do { try LoginItem.set(on); loginError = nil } catch { loginError = error.localizedDescription }
                            refresh()
                        }))
                    }
                }
            }
            SettingsCard(title: tr("settings.language", "Taal"),
                         footer: languageChanged ? tr("settings.language.restart", "De nieuwe taal geldt na een herstart van Band·je.")
                                                 : tr("settings.language.hint", "Menu's, vensters, transcripten en Help.")) {
                SettingsRow(label: tr("settings.language", "Taal")) {
                    Picker("", selection: $language) {
                        Text(tr("settings.language.system", "Zoals macOS")).tag("")
                        Divider()
                        ForEach(AppLanguage.codes, id: \.self) { Text(AppLanguage.name($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if languageChanged {
                    Divider()
                    SettingsRow(label: "") {
                        Button(tr("settings.language.restartNow", "Herstart Band·je")) { restart() }
                    }
                }
            }
        }
        .onChange(of: windowAtLaunch) { LaunchPolicy.windowAtLaunch = windowAtLaunch }
        .onChange(of: showInDock) {
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            NotificationCenter.default.post(name: .bandjeWindowVisibility, object: nil)
        }
        .onChange(of: language) {
            AppLanguage.chosen = language.isEmpty ? nil : language
            languageChanged = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        loginOn = LoginItem.isOn
        loginApproval = LoginItem.needsApproval
    }
}

// MARK: Sneltoetsen

private struct ShortcutSettings: View {
    let apply: (Shortcut, Shortcut) -> String?
    @State private var record = Shortcut.record
    @State private var dictate = Shortcut.dictate
    @State private var editing: Field?
    @State private var error: String?
    @State private var monitor: Any?

    enum Field { case record, dictate }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(footer: error ?? tr("shortcuts.hint", "Klik op een sneltoets en druk de nieuwe combinatie, met ⌘, ⌃ of ⌥. Esc annuleert."),
                         red: error != nil) {
                SettingsRow(label: tr("shortcuts.record", "Opnemen")) { recorder(.record, record) }
                Divider()
                SettingsRow(label: tr("shortcuts.dictate", "Dicteren")) { recorder(.dictate, dictate) }
            }
            Button(tr("shortcuts.reset", "Herstel standaard")) {
                stopEditing()
                commit(.defaultRecord, .defaultDictate)
            }
        }
        .onDisappear { stopEditing() }
    }

    private func recorder(_ field: Field, _ value: Shortcut) -> some View {
        Button {
            editing == field ? stopEditing() : startEditing(field)
        } label: {
            Text(editing == field ? tr("shortcuts.press", "Druk op toetsen…") : value.display)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(width: 120)
        }
        .buttonStyle(.bordered)
        .tint(editing == field ? .accentColor : nil)
    }

    private func startEditing(_ field: Field) {
        stopEditing()
        error = nil
        editing = field
        // The global hotkeys would swallow the current combination; off while recording a new one.
        Hotkey.unregister(.record)
        Hotkey.unregister(.dictate)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                stopEditing()
                return nil
            }
            guard let shortcut = Shortcut(event: event) else {
                error = tr("shortcuts.needModifier", "Gebruik ⌘, ⌃ of ⌥ in de combinatie.")
                return nil
            }
            let other = field == .record ? dictate : record
            if shortcut == other {
                error = tr("shortcuts.duplicate", "Deze combinatie is al in gebruik voor de andere sneltoets.")
                return nil
            }
            editing = nil
            removeMonitor()
            commit(field == .record ? shortcut : record, field == .dictate ? shortcut : dictate)
            return nil
        }
    }

    private func stopEditing() {
        editing = nil
        removeMonitor()
        _ = apply(record, dictate) // re-register the unchanged shortcuts
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func commit(_ newRecord: Shortcut, _ newDictate: Shortcut) {
        if let problem = apply(newRecord, newDictate) {
            error = problem
            _ = apply(record, dictate)
            return
        }
        record = newRecord
        dictate = newDictate
        error = nil
    }
}

// MARK: Geluid

/// Microfoon and Geluidsuitvoer, as in the menu bar menu: the choice sets the macOS default device
/// (for all apps). The lists follow devices plugged in or out when Band·je becomes active again.
private struct SoundSettings: View {
    let chooseMic: (String) -> Void
    let chooseOutput: (String) -> String?
    @State private var inputs: [Device] = []
    @State private var outputs: [Device] = []
    @State private var mic = ""
    @State private var output = ""
    @State private var error: String?

    struct Device: Hashable {
        let uid: String
        let name: String
    }

    var body: some View {
        SettingsCard(footer: error ?? tr("menu.mic.note", "Geldt voor alle apps, ook om te bellen"), red: error != nil) {
            SettingsRow(label: tr("menu.mic", "Microfoon")) { picker($mic, inputs) }
            Divider()
            SettingsRow(label: tr("menu.output", "Geluidsuitvoer")) { picker($output, outputs) }
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
        .onChange(of: mic) { _, uid in
            guard !uid.isEmpty, uid != Self.uid(Recorder.inputDevice(), in: Recorder.inputDevices()) else { return }
            chooseMic(uid)
            error = nil
        }
        .onChange(of: output) { _, uid in
            guard !uid.isEmpty, uid != Self.uid(Recorder.outputDevice(), in: Recorder.outputDevices()) else { return }
            error = chooseOutput(uid)
            if error != nil { load() }
        }
    }

    private func picker(_ selection: Binding<String>, _ devices: [Device]) -> some View {
        Picker("", selection: selection) {
            ForEach(devices, id: \.uid) { Text($0.name).tag($0.uid) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func load() {
        let ins = Recorder.inputDevices(), outs = Recorder.outputDevices()
        inputs = ins.map { Device(uid: $0.uid, name: $0.name) }
        outputs = outs.map { Device(uid: $0.uid, name: $0.name) }
        mic = Self.uid(Recorder.inputDevice(), in: ins)
        output = Self.uid(Recorder.outputDevice(), in: outs)
    }

    private static func uid(_ id: AudioObjectID, in devices: [(id: AudioObjectID, uid: String, name: String)]) -> String {
        devices.first { $0.id == id }?.uid ?? ""
    }
}

// MARK: Transcriptie

private struct TranscriptionSettings: View {
    @State private var auto = BandjeApp.autoTranscribe
    @State private var speakers = Transcriber.detectSpeakers

    var body: some View {
        SettingsCard(footer: tr("settings.transcription.hint", "De taal wordt vanzelf herkend (25 talen). Alles gebeurt op deze Mac.")) {
            SettingsRow(label: tr("settings.transcription.auto", "Transcribeer automatisch"),
                        note: tr("settings.transcription.auto.note", "Na elke opname.")) {
                RowToggle(isOn: $auto)
            }
            Divider()
            SettingsRow(label: tr("settings.transcription.speakers", "Sprekers herkennen"),
                        note: tr("settings.transcription.speakers.note", "Uit: alleen %1$@ en %2$@, zonder sprekernummers.",
                                  TranscriptWriter.me, TranscriptWriter.otherSide)) {
                RowToggle(isOn: $speakers)
            }
            Divider()
            SettingsRow(label: tr("settings.language", "Taal")) {
                Text(tr("settings.transcription.automatic", "Automatisch")).foregroundStyle(.secondary)
            }
        }
        .onChange(of: auto) { UserDefaults.standard.set(auto, forKey: "autoTranscribe") }
        .onChange(of: speakers) { Transcriber.detectSpeakers = speakers }
    }
}

// MARK: Opslag

private struct StorageSettings: View {
    let chooseFolder: (Bool) -> Bool
    let setSync: (Bool) -> Bool
    @State private var folder = OutputLocation.directory
    @State private var syncOn = ICloudSync.isOn
    @State private var availability = ICloudSync.availability

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: "iCloud", footer: footer) {
                SettingsRow(label: tr("settings.icloud.toggle", "Synchroniseer via iCloud")) {
                    RowToggle(isOn: Binding(get: { syncOn }, set: { on in
                        syncOn = setSync(on)
                        folder = OutputLocation.directory
                    }))
                    .disabled(availability != .available && !syncOn)
                }
            }
            // While syncing, recordings are in iCloud Drive › Band·je: no folder to choose.
            if !syncOn {
                SettingsCard(title: tr("settings.folder", "Opnamemap"),
                             footer: tr("settings.folder.hint", "Nieuwe opnames komen hier. Bestaande opnames, templates en spraakmodellen blijven waar ze staan.")) {
                    SettingsRow(label: display(folder)) {
                        Button(tr("settings.folder.change", "Wijzig…")) {
                            if chooseFolder(false) { folder = OutputLocation.directory }
                        }
                    }
                    if folder.standardizedFileURL != OutputLocation.defaultDirectory.standardizedFileURL {
                        Divider()
                        SettingsRow(label: "") {
                            Button(tr("settings.folder.default", "Gebruik ~/Music/Bandje")) {
                                if chooseFolder(true) { folder = OutputLocation.directory }
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeICloudReady)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var footer: String {
        switch availability {
        case .available: tr("settings.icloud.short", "Opnames, transcripten en samenvattingen staan in iCloud Drive en synchroniseren met je andere toestellen.")
        case .noAccount: tr("settings.icloud.noAccount", "Log in bij iCloud en zet iCloud Drive aan in Systeeminstellingen.")
        case .noContainer: tr("settings.icloud.noContainer", "iCloud Drive is niet beschikbaar voor Band·je. Zet iCloud Drive aan in Systeeminstellingen > [je naam] > iCloud.")
        }
    }

    private func refresh() {
        syncOn = ICloudSync.isOn
        availability = ICloudSync.availability
        folder = OutputLocation.directory
    }

    /// `~/…` for folders in the home folder.
    private func display(_ url: URL) -> String {
        let home = OutputLocation.realHome.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: Toegang

/// The permissions with the welcome's words; the state refreshes by itself when Band·je becomes
/// active again (back from System Settings).
private struct AccessSettings: View {
    let restart: () -> Void
    @State private var mic = Permissions.microphone
    @State private var system = Permissions.systemAudio
    @State private var paste = Permissions.paste
    @State private var pasteAsked = Paste.askedThisLaunch
    @State private var checkAtLaunch = Permissions.checkAtLaunch

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(footer: system == .unknown ? tr("settings.permissions.silent.hint", "Bij de laatste opname kwam er geen geluid van je Mac binnen. Speelde er niets af, dan is dat normaal. Anders: klik bij Geluid van je Mac op Open instellingen… en zet Band·je aan.") : nil) {
                SettingsRow(label: tr("settings.permissions.mic", "Microfoon"), note: tr("welcome.mic", "Om jou te horen bij opnemen en dicteren.")) {
                    switch mic {
                    case .allowed: allowed
                    case .notAsked: Button(tr("welcome.allow", "Sta toe…")) { Task { _ = await Permissions.microphoneAllowed(); refresh() } }
                    default: Button(tr("settings.permissions.open", "Open instellingen…")) { Permissions.openSettings("Privacy_Microphone") }
                    }
                }
                Divider()
                SettingsRow(label: tr("settings.permissions.paste", "Automatisch plakken"),
                            note: paste != .allowed && pasteAsked ? tr("settings.permissions.paste.restart", "Net aangezet? macOS laat het Band·je pas zien na een herstart.")
                                                                  : tr("welcome.paste", "Om gedicteerde tekst voor je te plakken (⌘V). Zonder staat de tekst op het klembord.")) {
                    if paste == .allowed {
                        allowed
                    } else if pasteAsked {
                        Button(tr("settings.language.restartNow", "Herstart Band·je")) { restart() }
                    } else {
                        Button(tr("welcome.allow", "Sta toe…")) { Paste.requestPermission(); refresh() }
                    }
                }
                Divider()
                SettingsRow(label: tr("settings.permissions.system", "Geluid van je Mac"), note: tr("welcome.system", "Om het geluid van je Mac op te nemen: de andere kant van een gesprek.")) {
                    switch system {
                    case .allowed: allowed
                    case .notAsked: Text(tr("welcome.system.later", "Bij eerste opname")).foregroundStyle(.secondary)
                    default: Button(tr("settings.permissions.open", "Open instellingen…")) { Permissions.openSettings("Privacy_ScreenCapture") }
                    }
                }
            }
            SettingsCard {
                SettingsRow(label: tr("settings.permissions.atLaunch", "Waarschuw bij het starten als er iets ontbreekt")) {
                    RowToggle(isOn: $checkAtLaunch)
                }
            }
        }
        .onChange(of: checkAtLaunch) { Permissions.checkAtLaunch = checkAtLaunch }
        // Back from System Settings: show the new state.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var allowed: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.green)
            .accessibilityLabel(Text(tr("settings.permissions.allowed", "Toegestaan")))
    }

    private func refresh() {
        mic = Permissions.microphone
        system = Permissions.systemAudio
        paste = Permissions.paste
        pasteAsked = Paste.askedThisLaunch
    }
}
