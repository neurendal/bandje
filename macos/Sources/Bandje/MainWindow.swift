import AppKit
import BandjeKit
import SwiftUI

/// What Bandje is doing, for the window. `BandjeApp` keeps it up to date (in `updateMenu`) and
/// sets the actions; the window never starts jobs itself.
@MainActor @Observable
final class Activity {
    static let shared = Activity()

    var isRecording = false
    /// The recording in progress: its name and start (the row at the top of the list).
    var recordingTitle: String?
    var recordingStarted: Date?
    /// Flags set in the recording in progress (the record screen shows how many).
    var recordingMarkers = 0
    /// The audio file being transcribed, and the status line ("Transcriberen… 40%").
    var transcribing: URL?
    var transcriptionStatus = ""
    /// "Only the first time after installing or updating…" while a model loads for the first time.
    var transcriptionHint: String?
    /// 0…1 once the model is loaded (the progress bars), nil before.
    var transcriptionFraction: Double?
    /// The transcript being summarized, and its status line.
    var summarizing: URL?
    var summaryStatus = ""
    var summaryFraction: Double?
    /// Apple Intelligence is there (macOS 26): the window offers summaries.
    var summariesAvailable = false
    /// The welcome with the permissions fills the window (first launch; after an update when a
    /// permission is missing) until Begin.
    var showsWelcome = false
    /// The welcome's step: 1 getting to know, 2 access (after an update with a permission missing).
    var welcomeStep = 1
    /// Audio files being downloaded from iCloud right now (the window says so).
    var downloading: Set<URL> = []

    /// The summary templates' names (Vat samen, Samenvatten), read off the main thread: reading them
    /// is coordinated with iCloud and can wait, which froze the window when done in a view.
    var templateNames: [String] = []

    func reloadTemplates() async {
        let names = await Task.detached(priority: .utility) { Summaries.templates().map(\.name) }.value
        if names != templateNames { templateNames = names }
    }

    /// Runs `work` with `url` marked as downloading when it is still in iCloud.
    func whileDownloading<T>(_ url: URL?, _ work: () async throws -> T) async rethrows -> T {
        guard let url, !Library.isLocal(url) else { return try await work() }
        downloading.insert(url)
        defer { downloading.remove(url) }
        return try await work()
    }

    @ObservationIgnored var toggleRecording: () -> Void = {}
    /// Markeer dit moment in the recording in progress.
    @ObservationIgnored var mark: () -> Void = {}
    @ObservationIgnored var transcribe: (URL) -> Void = { _ in }
    @ObservationIgnored var summarize: (URL, String) -> Void = { _, _ in }
    @ObservationIgnored var openTemplates: () -> Void = {}
    @ObservationIgnored var restart: () -> Void = {}
    /// Turns iCloud sync on or off (with the same questions as in Instellingen); returns the new state.
    @ObservationIgnored var setSync: (Bool) -> Bool = { _ in false }
    /// The recording's current input level (the record screen's VU meter), read every frame.
    @ObservationIgnored var level: () -> Float = { 0 }
}

/// The Bandje window: the library on the left, the open recording on the right.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static let selection = Selection()

    @Observable final class Selection {
        var folder: URL?
        /// Set by the menu's Benoem sprekers…: the recording view opens its sheet and clears it.
        var nameSpeakers = false
        /// A summary tab to open (by template name), for the selftest's screenshots.
        var tab: String?
        /// The record screen (running tape) instead of a recording, while one is being made.
        var showsRecorder = false
    }

    static var isOpen: Bool { window?.isVisible == true }
    static var isMinimized: Bool { window?.isMiniaturized == true }

    /// Opens (or brings forward) the window; `json` selects that recording.
    static func show(select json: URL? = nil, nameSpeakers: Bool = false, tab: String? = nil) {
        if let json { selection.folder = json.deletingLastPathComponent() }
        selection.nameSpeakers = nameSpeakers
        selection.tab = tab
        if window == nil {
            let root = MainView(selection: selection)
                .environment(Library.shared)
                .environment(Playback.player)
                .environment(Activity.shared)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Band·je"  // the Window menu and Mission Control; not shown in the window
            w.titleVisibility = .hidden
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 980, height: 680))
            w.contentMinSize = NSSize(width: 760, height: 480)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("BandjeMain")
            w.center()
            if Activity.shared.showsWelcome {
                // The welcome is one column in two steps, the same size for both (and with or
                // without the store): fits a 13-inch MacBook's screen without scrolling.
                w.contentMinSize = NSSize(width: 520, height: 520)
                let room = (w.screen ?? NSScreen.main).map { $0.visibleFrame.height - (w.frame.height - w.contentLayoutRect.height) } ?? welcomeHeight
                w.setContentSize(NSSize(width: 560, height: min(welcomeHeight, room)))
                w.center()
            }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // P1: closing the window stops playback; the position is kept (specs/player.md 9).
                    Playback.left(showing: nil)
                    // After the close, so isOpen is false when the Dock icon is updated.
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .bandjeWindowVisibility, object: nil)
                        closeNotice()
                    }
                }
            }
            window = w
            // No focus in the search field at first (macOS gives it to the first text field): space
            // plays and pauses, and the field showed its focus ring before you clicked it.
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
            Library.shared.start()
            // Space plays and pauses, ⌘← and ⌘→ skip 15 s (specs/player.md 5.1), but never while
            // typing (search fields, renaming: there ⌘← goes to the start of the line).
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // The Mark This Moment shortcut (⌃⌥⌘M) in the window: a marker where the player is, as ⌘D.
                // While recording the global hotkey takes it before it gets here.
                if let pressed = Shortcut(event: event) {
                    let number = event.windowNumber
                    let handled = MainActor.assumeIsolated { () -> Bool in
                        guard pressed == Shortcut.mark, let window, number == window.windowNumber,
                              window.attachedSheet == nil else { return false }
                        NotificationCenter.default.post(name: .bandjeAddMarker, object: nil)
                        return true
                    }
                    if handled { return nil }
                }
                guard let key = PlayerKey(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return event }
                let number = event.windowNumber
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let window, number == window.windowNumber, !(window.firstResponder is NSText),
                          window.attachedSheet == nil else { return false }
                    switch key {
                    case .playPause: NotificationCenter.default.post(name: .bandjeTogglePlay, object: nil)
                    case .back: Playback.player.skip(by: -PlayerModel.skipInterval)
                    case .forward: Playback.player.skip(by: PlayerModel.skipInterval)
                    }
                    return true
                }
                return handled ? nil : event
            }
        }
        window?.makeKeyAndOrderFront(nil)
        // At launch Band·je is still a menu bar app, and macOS may turn down the activation: the
        // window then stayed hidden behind other apps. Bring it to the front regardless.
        window?.orderFrontRegardless()
        // Only now that the window is on screen: the Dock icon and the app menu (with ⌘Q) follow
        // it. Posted before, the window counted as closed and Band·je stayed a menu bar app.
        NotificationCenter.default.post(name: .bandjeWindowVisibility, object: nil)
        NSApp.activate()
    }

    /// The window closed, Band·je didn't: say where it is now (standard "Do not show this message
    /// again" checkbox, localized by macOS).
    private static func closeNotice() {
        guard LaunchPolicy.showsCloseNotice() else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("window.closed.title", "Band·je draait nog")
        alert.informativeText = tr("window.closed.text2", "Je vindt Band·je in de menubalk. Opnemen en dicteren met sneltoetsen blijven werken.")
        // The menu bar icon itself, as it looks up there: says more than words where to look.
        let icon = BandjeApp.cassette(angle: .pi / 2, color: nil)
        icon.isTemplate = true
        let badge = NSHostingView(rootView:
            Image(nsImage: icon).resizable().renderingMode(.template)
                .frame(width: 33, height: 24)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel(Text(tr("window.closed.icon", "Het Band·je-icoon in de menubalk"))))
        badge.frame.size = badge.fittingSize
        alert.accessoryView = badge
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: tr("menu.quit", "Stop Band·je"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = tr("window.closed.dontShow", "Niet meer tonen")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { LaunchPolicy.suppressCloseNotice() }
        // Stop Band·je: the usual quit (asks first while recording, waits for a save).
        if response == .alertSecondButtonReturn { NSApp.terminate(nil) }
    }

    /// The welcome's height below the title bar.
    static let welcomeHeight: CGFloat = 600

    /// Begin on the welcome: the library, in a window of the usual size.
    static func endWelcome() {
        Activity.shared.showsWelcome = false
        guard let window else { return }
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.setContentSize(NSSize(width: 980, height: 680))
        window.center()
    }

    /// Show the recording `file` is in. `opening`: also when the window is closed (a recording just
    /// stopped, Transcribe or Summarize chosen in the menu; owner, 2026-11-08). Without it (a job
    /// that finished, the menu's choice) only a window that is already open follows.
    static func reveal(_ file: URL, opening: Bool = false) {
        if !isOpen {
            guard opening else { return }
            show()
        }
        let path = file.deletingLastPathComponent().standardizedFileURL.path
        Task {
            await Library.shared.refresh()
            if let r = Library.shared.recordings.first(where: { $0.folder.standardizedFileURL.path == path }) {
                selection.folder = r.folder
            }
        }
    }

    /// A recording moved by Band·je itself (from the staging folder into iCloud): the window keeps
    /// showing it, from its new place.
    static func followMove(from old: URL, to new: URL) {
        guard selection.folder?.standardizedFileURL == old.standardizedFileURL else { return }
        selection.folder = new
    }

    /// The window itself (printing; the selftest's snapshot).
    static var nsWindow: NSWindow? { window }
}

/// The window's player keys (specs/player.md 5.1): space, ⌘←, ⌘→.
enum PlayerKey: Equatable {
    case playPause, back, forward

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // The arrows carry .numericPad and .function; only the user's modifiers count.
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, mods) {
        case (49, []): self = .playPause
        case (123, .command): self = .back
        case (124, .command): self = .forward
        default: return nil
        }
    }
}

extension Notification.Name {
    /// The Bandje window opened or closed (the Dock icon follows).
    static let bandjeWindowVisibility = Notification.Name("bandjeWindowVisibility")
    /// Space in the window (not in a text field): play or pause the open recording, else the player's.
    static let bandjeTogglePlay = Notification.Name("bandjeTogglePlay")
    /// The Mark This Moment shortcut in the window: a marker in the open recording, as ⌘D.
    static let bandjeAddMarker = Notification.Name("bandjeAddMarker")
    /// Wijzig › Zoek… (⌘F): the search bar above the open recording's transcript.
    static let bandjeFind = Notification.Name("bandjeFind")
    /// Archief › Druk af… (⌘P): print the open recording's transcript.
    static let bandjePrint = Notification.Name("bandjePrint")
    /// The window selected a recording (object: its folder); the menu's current recording follows.
    static let bandjeWindowSelection = Notification.Name("bandjeWindowSelection")
    /// Open the Name and Colour sheet of the open recording (the selftest's screenshot).
    static let bandjeRename = Notification.Name("bandjeRename")
}

private struct MainView: View {
    @Bindable var selection: MainWindow.Selection
    @Environment(Library.self) private var library
    @Environment(Activity.self) private var activity
    @Environment(PlayerModel.self) private var player
    @State private var query = ""

    var body: some View {
        if activity.showsWelcome {
            WelcomeView()
        } else {
            splitView
                .onReceive(NotificationCenter.default.publisher(for: .bandjeTogglePlay)) { _ in togglePlay() }
        }
    }

    /// The recording the detail shows (not the record screen).
    private var detail: Recording? {
        guard !(activity.isRecording && selection.showsRecorder), let folder = selection.folder else { return nil }
        return library.recordings.first { $0.folder == folder }
    }

    /// Space: the open recording (it starts when it isn't playing yet), else whatever plays.
    private func togglePlay() {
        if let detail, detail.audio != nil {
            Playback.toggle(detail)
        } else if player.current != nil {
            player.togglePlayPause()
        }
    }

    private func showRecorder() {
        selection.folder = nil
        selection.showsRecorder = true
    }

    private var splitView: some View {
        NavigationSplitView {
            LibraryList(selection: $selection.folder, showsRecorder: $selection.showsRecorder, query: query)
                // As on the iPhone: Band●je top left, the search field under it.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        BrandMark(size: 26)
                        SearchField(text: $query, prompt: tr("window.search", "Titels en transcripten"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                // Recording makes a new recording, so it lives with the list, not with the open one.
                .safeAreaInset(edge: .bottom) {
                    // As on the iPhone and iPad: while recording, the button shows the record screen.
                    RecordButton(isRecording: activity.isRecording) {
                        if activity.isRecording { showRecorder() } else { activity.toggleRecording() }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
        } detail: {
            if activity.isRecording, selection.showsRecorder {
                RecordScreen()
            } else if let recording = detail {
                RecordingView(recording: recording, nameSpeakers: $selection.nameSpeakers, openTab: $selection.tab,
                              searchQuery: query,
                              onMoved: { selection.folder = $0 }, onDeleted: { selection.folder = nil })
                    .id(recording.folder)
            } else if !library.hasLoaded {
                Color.clear  // the list says "Opnames laden…"
            } else {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        CassetteView(state: CassetteState(), blankSticker: true).frame(width: 180)
                        Text(library.recordings.isEmpty ? tr("window.empty", "Nog geen opnames") : tr("window.pick", "Kies een opname"))
                            .font(.title2.weight(.semibold))
                    }
                } description: {
                    if library.recordings.isEmpty {
                        Text(tr("window.empty.text", "Neem op met de knop hierboven of met %@.", Shortcut.record.display))
                    }
                }
            }
        }
        // No "Band·je" text in the toolbar: the Band●je mark tops the sidebar, as on the iPhone.
        .toolbar(removing: .title)
        // band.je navy for the selection and selected tab instead of the system accent (owner).
        .tint(Color.navy)
        .onChange(of: selection.folder) { _, folder in
            // P1: another recording (or none) in the detail stops the one playing. A rename moves
            // the player first (Playback.moved), so the renamed recording plays on.
            Playback.left(showing: selection.showsRecorder ? nil : folder)
            if let folder {
                selection.showsRecorder = false
                NotificationCenter.default.post(name: .bandjeWindowSelection, object: folder)
            }
        }
        // A recording starts (here, from the menu or the shortcut): the window shows the running tape.
        .onChange(of: activity.isRecording, initial: true) { _, recording in
            if recording { showRecorder() } else { selection.showsRecorder = false }
        }
    }
}

/// When the window opens at launch, and when it starts with the welcome (pure, for the tests).
enum LaunchPolicy {
    /// The very first time (the welcome, also at login); otherwise only when the user started
    /// Band·je and Settings › Show the window at launch is on. The setting decides, also after an
    /// update (owner).
    static func showWindow(atLogin: Bool, firstLaunch: Bool, setting: Bool) -> Bool {
        firstLaunch || (!atLogin && setting)
    }

    /// A Dock icon (and with it the app menu and ⌘Q) while the window is on screen or minimized
    /// (else a minimized window could not come back); otherwise only with Always in the Dock.
    static func dockIcon(windowVisible: Bool, minimized: Bool, alwaysInDock: Bool) -> Bool {
        windowVisible || minimized || alwaysInDock
    }

    enum Quit: Equatable { case now, ask, waitForSave }

    /// Quitting while a recording runs asks first; while one is being saved (converted, moved to
    /// iCloud) Band·je waits for that, so nothing is lost.
    static func quit(recording: Bool, finishing: Int) -> Quit {
        recording ? .ask : finishing > 0 ? .waitForSave : .now
    }

    /// Closing the window says once that Band·je keeps running in the menu bar, until "Do not show
    /// this message again".
    static func showsCloseNotice(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: "closeNoticeSuppressed")
    }

    static func suppressCloseNotice(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: "closeNoticeSuppressed")
    }

    static func showWelcome(firstLaunch: Bool, updated: Bool, permissionMissing: Bool) -> Bool {
        firstLaunch || (updated && permissionMissing)
    }

    /// The welcome's first step: getting to know the first time; after an update (it only shows
    /// then when a permission is missing) straight to Access.
    static func welcomeStep(firstLaunch: Bool) -> Int {
        firstLaunch ? 1 : 2
    }

    /// Another build than last time (not the first launch: then there was no last build).
    static func updated(lastBuild: String?, build: String) -> Bool {
        lastBuild.map { $0 != build } ?? false
    }

    /// Settings › Show the window at launch (default on).
    static var windowAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "showWindowAtLaunch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showWindowAtLaunch") }
    }
}

/// The sidebar's search field (AppKit's, so it looks and behaves as in Finder and Mail).
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @MainActor @objc func changed(_ field: NSSearchField) { text.wrappedValue = field.stringValue }
    }
}

/// "Band●je": the name with the dot drawn as the record mark (band.je's brand).
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "Band")
            RecordMark()
                .frame(width: size * 0.48, height: size * 0.48)
                .padding(.horizontal, size * 0.05)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size * 0.02 }
            Text(verbatim: "je")
        }
        .font(.system(size: size, weight: .bold))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Band·je"))
    }
}

/// The dot in "Band●je": a red disc with a ring and a centre cut out (the background shows through).
private struct RecordMark: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
            var p = Path()
            for f in [1, 0.92, 0.84, 0.3] as [CGFloat] {
                p.addEllipse(in: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f))
            }
            context.fill(p, with: .color(Color(hex: 0xD2442A)), style: FillStyle(eoFill: true))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The first screen of the window, in two steps in one window of a fixed size (owner, 2026-11-12).
/// 1. Getting to know: the cassette and a welcome, the two shortcuts, Free to Start (App Store build)
///    and a word from the makers; Next.
/// 2. Access: the permissions with a button each and a check mark once allowed; automatic pasting
///    and iCloud apart under "Optional" (App Review 2.4.5, 2026-11-17); privacy in one line;
///    Back and Start.
/// Open at login is under both steps (one toggle). Everything left-aligned in one 500 pt column.
private struct WelcomeView: View {
    @Environment(Activity.self) private var activity
    @State private var mic = Permissions.microphone
    @State private var paste = Paste.allowed
    @State private var askedPaste = false
    @State private var sync = ICloudSync.isOn
    @State private var iCloud = ICloudSync.availability
    @State private var login = false
    @State private var loginError: String?
    @State private var restoring = false

    /// The column's width; the window is 560 wide.
    private static let column: CGFloat = 500

    private var step: Int { activity.welcomeStep }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    Group {
                        if step == 2 { accessStep } else { introStep }
                    }
                    .frame(width: Self.column, alignment: .leading)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    // As tall as the window, so the last line sits at the bottom; scrolls only when
                    // the window is made smaller than its content.
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            pageDots
            Divider()
            bottomBar
        }
        // macOS doesn't tell when a permission changes in System Settings: look again every second.
        .task {
            while !Task.isCancelled {
                mic = Permissions.microphone
                paste = Paste.allowed
                iCloud = ICloudSync.availability  // known once the container lookup at launch is done
                sync = ICloudSync.isOn
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Step 1, getting to know

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            // No sticker: the cassette as the picture, the words next to it.
            header(tr("welcome.title", "Welkom bij Bandje"),
                   tr("welcome.menubar", "Band·je staat rechtsboven in de menubalk: het cassettebandje.")) {
                CassetteView(state: CassetteState())
            }
            group(tr("welcome.shortcuts", "Sneltoetsen")) {
                shortcut(Shortcut.record.display, tr("welcome.record", "Neemt een gesprek op: je microfoon en het geluid van je Mac. Daarna maakt Band·je er een transcript van."))
                Divider()
                // Without automatic pasting (optional) the user pastes: say so here (owner, 2026-11-17).
                shortcut(Shortcut.dictate.display, paste ? tr("welcome.dictate", "Dicteren: praat, en de tekst komt waar je cursor staat.")
                                                         : tr("welcome.dictate.clipboard", "Dicteren: praat, en je tekst staat op het klembord. Plak hem met ⌘V waar je cursor staat."))
            } footer: {
                tr("welcome.shortcuts.change", "Aan te passen in Instellingen.")
            }
            if let free = Store.welcomeFree {
                VStack(alignment: .leading, spacing: 6) {
                    heading(tr("welcome.free", "Gratis beginnen"))
                    freeToStart(free)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(tr("welcome.madeBy", "Met liefde gemaakt door"))
                Link("Neurendal", destination: AboutView.neurendal)
                    .foregroundStyle(Color.accent)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Step 2, access

    private var accessStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            // A big check mark in the cassette's place, so both headers line up.
            header(tr("welcome.permissions", "Toegang"),
                   tr("welcome.permissions.intro", "Wat Band·je nodig heeft om op te nemen, te dicteren en te synchroniseren.")) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accent)
            }
            group(nil) {
                permission(tr("settings.permissions.mic", "Microfoon"), icon: "mic",
                           note: tr("welcome.mic", "Om jou te horen bij opnemen en dicteren.")) {
                    if mic == .allowed {
                        allowed
                    } else if mic == .notAsked {
                        Button(tr("welcome.allow", "Sta toe…")) {
                            Task { _ = await Permissions.microphoneAllowed(); mic = Permissions.microphone }
                        }
                    } else {
                        Button(tr("settings.permissions.open", "Open instellingen…")) { Permissions.openSettings("Privacy_Microphone") }
                    }
                }
                Divider()
                permission(tr("settings.permissions.system", "Geluid van je Mac"), icon: "speaker.wave.2",
                           note: tr("welcome.system", "Om het geluid van je Mac op te nemen: de andere kant van een gesprek.")) {
                    SystemAudioPermissionControl(restart: { activity.restart() })
                }
            } footer: {
                nil
            }
            // Optional extras, apart from what recording needs (App Review 2.4.5, 2026-11-17):
            // Band·je works fully without them.
            group(tr("welcome.optional", "Optioneel")) {
                // Automatic pasting only in a build from source (App Review 2.4.5, see `Paste`).
                #if !APPSTORE
                permission(tr("settings.permissions.paste", "Automatisch plakken"), icon: "keyboard",
                           note: askedPaste ? tr("settings.permissions.paste.restart", "Net aangezet? macOS laat het Band·je pas zien na een herstart.")
                                            : tr("welcome.paste", "Om gedicteerde tekst voor je te plakken (⌘V). Zonder staat de tekst op het klembord.")) {
                    if paste {
                        allowed
                    } else if askedPaste {
                        Button(tr("settings.language.restartNow", "Herstart Band·je")) { activity.restart() }
                    } else {
                        Button(tr("welcome.paste.on", "Zet aan…")) {
                            Paste.requestPermission()
                            askedPaste = true
                        }
                    }
                }
                Divider()
                #endif
                permission("iCloud", icon: "icloud",
                           note: tr("welcome.icloud", "Je opnames ook op je iPhone en je andere Macs, via iCloud Drive. Kan ook later, in Instellingen.")) {
                    if sync {
                        allowed
                    } else if iCloud == .available {
                        Button(tr("welcome.icloud.on", "Zet aan…")) { sync = activity.setSync(true) }
                    } else {
                        // No iCloud account or iCloud Drive off: nothing to click here.
                        Text(tr("welcome.icloud.unavailable", "Niet beschikbaar")).foregroundStyle(.secondary)
                            .help(iCloud == .noAccount ? tr("settings.icloud.noAccount", "Log in bij iCloud en zet iCloud Drive aan in Systeeminstellingen.")
                                                       : tr("settings.icloud.noContainer", "iCloud Drive is niet beschikbaar voor Band·je. Zet iCloud Drive aan in Systeeminstellingen > [je naam] > iCloud."))
                    }
                }
            } footer: {
                (Paste.available ? tr("welcome.optional.footer", "Band·je werkt volledig zonder. Zonder automatisch plakken staat gedicteerde tekst op het klembord en plak je zelf met ⌘V.") + "\n\n" : "")
                    + tr("welcome.privacy", "Alles blijft op je Mac, of in je eigen iCloud als je die aanzet. Verder gaat alleen een maandelijkse licentiecheck van het bedrijf achter het spraakmodel online, zonder audio of tekst.")
            }
        }
    }

    // MARK: Bottom

    /// Two small dots: where you are.
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(1...2, id: \.self) { n in
                Circle()
                    .fill(n == step ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 12)
        .accessibilityElement()
        .accessibilityLabel(Text(tr("welcome.step", "Stap %1$@ van %2$@", "\(step)", "2")))
    }

    /// Back (step 2), Open at login, and Next or Start; under Start that the permissions can wait.
    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                if step == 2 {
                    Button {
                        go(to: 1)
                    } label: {
                        Label(tr("welcome.back", "Terug"), systemImage: "chevron.left")
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .background {
                        // ⌘[ as in Finder and Safari, besides Esc.
                        Button("") { go(to: 1) }
                            .keyboardShortcut("[", modifiers: .command)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                }
                // Off unless ticked (App Review: nothing starts at login without consent).
                Toggle(tr("settings.login.toggle", "Open Band·je bij inloggen"), isOn: $login)
                Spacer(minLength: 8)
                Button {
                    if step == 2 { start() } else { go(to: 2) }
                } label: {
                    Text(step == 2 ? tr("welcome.start", "Begin") : tr("welcome.next", "Volgende")).frame(minWidth: 96)
                }
                .buttonStyle(.borderedProminent)
                // A darker red than the accent: white on it has enough contrast.
                .tint(Color(hex: 0xB0341C))
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            // One line under the buttons, also when empty, so the bar doesn't move between the steps.
            HStack(alignment: .firstTextBaseline) {
                if let loginError {
                    Text(tr("settings.login.failed", "Openen bij inloggen lukte niet") + ": " + loginError)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text(tr("welcome.later", "Je kunt dit later toestaan."))
                    .foregroundStyle(.secondary)
                    .opacity(step == 2 && mic != .allowed ? 1 : 0)
                    .accessibilityHidden(!(step == 2 && mic != .allowed))
            }
            .font(.caption)
        }
        .frame(width: Self.column)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private func go(to page: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { activity.welcomeStep = page }
    }

    private func start() {
        if login {
            do { try LoginItem.set(true) } catch { loginError = error.localizedDescription; login = false; return }
        }
        MainWindow.endWelcome()
    }

    /// What is free and what comes after (App Store build only), with Restore for who bought it
    /// already; once everything is unlocked, only a thank-you.
    @ViewBuilder private func freeToStart(_ free: Store.WelcomeFree) -> some View {
        if free == .unlocked {
            Label {
                Text(tr("welcome.free.unlocked", "Alles is ontgrendeld. Dank je wel!"))
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if free == .dictationOwned {
                        // Band·je Dicteren bought: only transcribing is still limited.
                        Text(tr("welcome.free.dictationOwned", "Opnemen is altijd gratis, en je eerste %1$@ transcripties krijg je van ons, alles op je Mac. %2$@ is ontgrendeld; onbeperkt transcriberen zit in %3$@: één keer betalen, geen abonnement.",
                                "\(FreeAllowance.transcriptions)", Store.name(.dictation), Store.name(.unlimited)))
                    } else {
                        Text(tr("welcome.free.text", "Opnemen is altijd gratis, en je eerste %1$@ transcripties en %2$@ minuten dicteren krijg je van ons, alles op je Mac. Daarna kies je %3$@ (alles) of %4$@: één keer betalen, geen abonnement.",
                                "\(FreeAllowance.transcriptions)", "\(Int(FreeAllowance.dictationSeconds / 60))",
                                Store.name(.unlimited), Store.name(.dictation)))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button(tr("welcome.free.restore", "Al gekocht? Herstel aankopen")) {
                        restoring = true
                        // The same as Settings: asks the App Store, then says what it found.
                        Task { await Store.restore(alert: true); restoring = false }
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accent)  // as the Neurendal link
                    .disabled(restoring)
                    if restoring { ProgressView().controlSize(.small) }
                }
                .font(.callout)
            }
        }
    }

    private var allowed: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.green)
            .accessibilityLabel(Text(tr("settings.permissions.allowed", "Toegestaan")))
    }

    /// A step's top: a picture in a 96 × 64 slot, a big title and a line under it.
    private func header(_ title: String, _ subtitle: String, @ViewBuilder picture: () -> some View) -> some View {
        HStack(spacing: 16) {
            picture()
                .frame(width: 96, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title.weight(.bold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// A small grey heading (optional), a card with rows, and a small grey line under it (optional).
    private func group(_ title: String?, @ViewBuilder _ rows: () -> some View, footer: () -> String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { heading(title) }
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if let footer = footer() {
                Text(footer).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The keys as separate keycaps on the left, what they do on the right.
    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(String(key))
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary))
                }
            }
            .frame(width: 112, alignment: .leading)
            .accessibilityLabel(Text(keys))
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func permission(_ name: String, icon: String, note: String, @ViewBuilder status: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            status()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

/// band.je's record button, as on the iPhone and iPad: the red record mark on the app's background;
/// while recording, a red disc with the waveform (then it shows the record screen).
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isRecording {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color(hex: 0xD2442A), in: Circle())
                } else {
                    ZStack {
                        Circle().fill(Color(nsColor: .textBackgroundColor))
                        RecordMark()
                    }
                    .frame(width: 64, height: 64)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(isRecording ? tr("window.showRecording", "Toon opname") : tr("menu.record.start", "Start opname") + "  " + Shortcut.record.display)
        .accessibilityLabel(Text(isRecording ? tr("window.showRecording", "Toon opname") : tr("menu.record.start", "Start opname")))
    }
}

/// The record screen in the window (the iPhone's): the tape running with the VU meter and the
/// name on the sticker, the time, and Stop.
private struct RecordScreen: View {
    @Environment(Activity.self) private var activity

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            TimelineView(.animation) { context in
                let elapsed = activity.recordingStarted.map { context.date.timeIntervalSince($0) } ?? 0
                VStack(spacing: 28) {
                    // The latest peak, scaled to the meter's speech range (Reels.meter).
                    CassetteView(state: CassetteState(mode: .recording, position: elapsed, level: activity.level() * 0.3,
                                                      title: activity.recordingTitle ?? ""))
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 24)
                    Text(clock(elapsed))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
            }
            // How many flags (Markeer dit moment); the line keeps its place so nothing jumps.
            Text(Self.markerCount(activity.recordingMarkers))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(activity.recordingMarkers > 0 ? 1 : 0)
                .accessibilityHidden(activity.recordingMarkers == 0)
            Spacer(minLength: 0)
            HStack(spacing: 32) {
                Button {
                    activity.mark()
                } label: {
                    Image(systemName: "flag.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: 0xD2442A))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help(tr("menu.mark", "Markeer dit moment") + "  " + Shortcut.mark.display)
                .accessibilityLabel(Text(tr("menu.mark", "Markeer dit moment")))
                Button {
                    activity.toggleRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help(tr("menu.record.stop", "Stop opname") + "  " + Shortcut.record.display)
                .accessibilityLabel(Text(tr("menu.record.stop", "Stop opname")))
                // As wide as the flag, so Stop stays in the middle.
                Color.clear.frame(width: 52, height: 52).accessibilityHidden(true)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func markerCount(_ n: Int) -> String {
        n == 1 ? tr("record.markers.one", "1 markering") : tr("window.markers", "%@ markeringen", "\(n)")
    }
}

/// The recording in progress, at the top of the list: a red dot, its name and the time.
private struct RecordingNowRow: View {
    let title: String
    let started: Date?

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.accent).frame(width: 10, height: 10).padding(.horizontal, 23)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let started {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(tr("window.recordingNow", "Neemt op · %@", clock(context.date.timeIntervalSince(started))))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .selectionDisabled()
    }
}

/// The library: recordings per day with a mini cassette, the time, length and the transcript's start.
private struct LibraryList: View {
    @Binding var selection: URL?
    @Binding var showsRecorder: Bool
    let query: String
    @Environment(Library.self) private var library
    @Environment(Activity.self) private var activity
    /// The recording to confirm deleting (right-click › Verwijder…, or Delete in the list).
    @State private var toDelete: Recording?
    @State private var error: String?

    var body: some View {
        let results = library.search(query)
        // Our own selection (band.je navy) instead of List's, which always takes the system accent.
        List {
            if activity.isRecording, let title = activity.recordingTitle {
                Section {
                    RecordingNowRow(title: title, started: activity.recordingStarted)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = nil
                            showsRecorder = true
                        }
                }
            }
            ForEach(Library.days(results), id: \.title) { day in
                Section(day.title) {
                    ForEach(day.recordings) { recording in
                        let selected = recording.folder == selection
                        row(recording, selected: selected)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = recording.folder }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected ? Color.navy : .clear)
                                    .padding(.horizontal, 10)
                            )
                            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                            .contextMenu {
                                Button(tr("window.delete", "Verwijder…"), role: .destructive) { toDelete = recording }
                                    .disabled(library.isBusy(recording.folder))
                            }
                    }
                }
            }
        }
        .overlay {
            if !library.hasLoaded {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("library.loading", "Opnames laden…")).foregroundStyle(.secondary)
                }
            } else if !query.isEmpty, results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if library.recordings.isEmpty, !activity.isRecording {
                Text(tr("library.none", "Geen opnames")).foregroundStyle(.secondary)
            }
        }
        // ↑ and ↓ move the selection, as in a normal list.
        .focusable()
        .focusEffectDisabled()
        // Delete (⌫) proposes to delete the selected recording, as in Finder; it asks first.
        .onDeleteCommand {
            guard let folder = selection, !library.isBusy(folder),
                  let recording = library.recordings.first(where: { $0.folder == folder }) else { return }
            toDelete = recording
        }
        .confirmationDialog(tr("window.delete.title", "%@ verwijderen?", toDelete?.title ?? ""),
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            presenting: toDelete) { recording in
            Button(tr("window.delete.ok", "Zet in prullenmand"), role: .destructive) { delete(recording) }
        } message: { _ in
            Text(ICloudSync.isActive ? tr("window.delete.icloud", "De opname gaat naar de prullenmand, ook op je andere apparaten.")
                                     : tr("window.delete.text", "De opname met transcript en samenvattingen gaat naar de prullenmand."))
        }
        .alert(tr("window.error", "Er ging iets mis"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
        .onMoveCommand { direction in
            let all = results.map(\.folder)
            guard !all.isEmpty else { return }
            let i = selection.flatMap { all.firstIndex(of: $0) }
            switch direction {
            case .up: selection = all[max(0, (i ?? 1) - 1)]
            case .down: selection = all[min(all.count - 1, (i ?? -1) + 1)]
            default: break
            }
        }
    }

    private func delete(_ recording: Recording) {
        Task {
            do {
                try await library.delete(recording)
                Playback.removed(recording)  // P9
                if selection == recording.folder { selection = nil }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func row(_ recording: Recording, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CassetteView(state: CassetteState(duration: recording.duration, title: recording.title, color: recording.color))
                .frame(width: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.headline).lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                HStack {
                    // The full date, then the length in words (as on the iPhone): "6 nov 2026, 17:52 · 47 min".
                    Text(verbatim: "\(recording.date.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).year().hour().minute().locale(TranscriptWriter.appLocale)))  ·  \(spokenDuration(recording.duration))")
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if activity.transcribing?.deletingLastPathComponent() == recording.folder {
                        if let f = activity.transcriptionFraction {
                            Text(f, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(selected ? Color.white : Color.accent)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    } else if recording.transcript != nil {
                        Image(systemName: "text.quote").accessibilityLabel(Text(tr("window.transcript", "Transcript")))
                    }
                    if ICloudSync.isWaiting(recording.folder) {
                        Image(systemName: "icloud.slash")
                            .help(tr("icloud.pending.title", "Nog niet in iCloud"))
                            .accessibilityLabel(Text(tr("icloud.pending.title", "Nog niet in iCloud")))
                    }
                }
                .font(.caption)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                if let preview = library.preview(for: recording) {
                    Text(preview).font(.footnote).lineLimit(2)
                        .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
