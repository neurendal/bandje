import AppKit
import BandjeKit
import Carbon.HIToolbox
import CoreAudio
import UniformTypeIdentifiers

/// Localized text. `key` is looked up in Localizable.strings of the user's language;
/// `nl` is the Dutch source text for translators and the fallback when no translation is found
/// (e.g. in unit tests). Placeholders `%@` or `%1$@`, `%2$@`… are filled from `args` in order.
func tr(_ key: String, _ nl: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nl, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// What goes over the network, for the About box, onboarding and dictation help.
var privacyLine: String {
    tr("privacy.online", "Audio en tekst verlaten je Mac nooit. Alleen een licentiecheck van Desert Ant Labs gaat over het netwerk: eens per maand per spraakmodel, zonder audio of tekst.")
}

@main
@MainActor
final class BandjeApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordItem: NSMenuItem!
    private var elapsedItem: NSMenuItem!
    /// "Markeer dit moment", only while recording (specs/markers.md 4).
    private var markItem: NSMenuItem!
    /// The flags of the recording in progress (for the record screen's count; the file is the source).
    private var recordingMarks = Markers()
    /// "Opname: <folder>": the recording the actions below it work on.
    private var currentItem: NSMenuItem!
    private var recorder: Recorder?
    private var timer: Timer?
    /// Free space on the running recording's disk, measured off the main thread every
    /// `DiskSpace.checkInterval` (nil: unknown); `diskChecking` while a measurement runs.
    private var recordingFreeBytes: Int64?
    private var diskCheckedAt = Date.distantPast
    private var diskChecking = false
    private var lastRecording: URL?
    /// Folder of the newest recording (`OutputLocation.latestRecording`) for the menu header's
    /// "Laatste opname". `updateMenu` runs every second while recording, so the folder is listed
    /// again only after the library changed or a recording stopped (`latestFolderStale`).
    private var latestFolderCache: URL?
    private var latestFolderStale = true
    private var latestRecordingFolder: URL? {
        if latestFolderStale {
            latestFolderCache = OutputLocation.latestRecording(in: OutputLocation.directory)?.deletingLastPathComponent().standardizedFileURL
            latestFolderStale = false
        }
        return latestFolderCache
    }
    private var transcribeItem: NSMenuItem!
    /// A file to transcribe; transcripts go to `directory`. `ownRecording` selects mode A/B over C.
    struct TranscriptionJob {
        var audio: URL
        var directory: URL? = nil
        var ownRecording = true
        /// Started by itself after a recording (Transcribe automatically): past the free limit it
        /// doesn't start and the window shows the short line, never the paywall.
        var automatic = false
    }
    /// Files waiting for transcription, oldest first; `transcribing` is the one in progress.
    private var transcriptionQueue: [TranscriptionJob] = []
    /// Stopped recordings still being converted (and moved into iCloud): sync can't be toggled then.
    private var finishing = 0

    /// A job writes into `folder`: being transcribed or queued, or summarized. Recordings still
    /// finishing are only counted (`finishing`), not checked here per folder; the staging flush
    /// skips them by their `.caf` and `recording: true` (`ICloudSync.flushStagingPlan`).
    private func isBusy(_ folder: URL) -> Bool {
        let f = folder.standardizedFileURL.path
        func inside(_ url: URL?) -> Bool { url.map { $0.deletingLastPathComponent().standardizedFileURL.path == f } ?? false }
        return inside(transcribing) || inside(summarizingJSON)
            || transcriptionQueue.contains { inside($0.audio) }
    }
    private var transcribing: URL?
    private var transcriptionStatus = ""
    /// Under the status while a model loads for the first time with this build (as on the iPhone).
    private var transcriptionHint: String?
    /// How far the transcription is (0…1), nil while the model loads.
    private var transcriptionFraction: Double?
    private var dictation: DictationCapture?
    /// True while Voz turns a dictation into text.
    private var dictationBusy = false
    private var dictationTimer: Timer?
    private var dictateItem: NSMenuItem!
    /// "Nog 5 gratis minuten dicteren": quiet, under Start dicteren, only while few free minutes are left.
    private var dictationFreeItem: NSMenuItem!
    /// A finished dictation passed the free warning point; said once Band·je is idle again.
    private var dictationWarningDue = false
    /// Until when "⌘V" shows next to the cassette after a dictation that wasn't pasted (`updateClock`).
    private var pasteHintUntil: Date?
    /// When the dictation shortcut went down; a release after `holdThreshold` means "hold to talk".
    private var dictatePressedAt: Date?
    private static let holdThreshold: TimeInterval = 0.4
    #if !APPSTORE
    private var accessibilityItem: NSMenuItem!
    #endif
    private var micMenu: NSMenu!
    private var micItem: NSMenuItem!
    private var outputMenu: NSMenu!
    private var outputItem: NSMenuItem!
    private var namingItem: NSMenuItem!
    private var helpItem: NSMenuItem!
    /// Submenu Recente opnames: the recent recordings with a transcript, and Andere….
    private var chooseMenu: NSMenu!
    /// `.json` of the newest transcript made or chosen in this session.
    private var lastTranscript: URL?
    /// Submenu `Samenvatten`, only shown when the on-device model is available.
    private var summarizeItem: NSMenuItem!
    private var summarizeMenu: NSMenu!
    private var summaryStatusItem: NSMenuItem!
    private var summarizing = false
    /// The transcript being summarized (for the window).
    private var summarizingJSON: URL?
    /// "Transcript klaar" / "Samenvatting klaar": a green check mark on the cassette in the menu bar
    /// and a menu line, both until the menu has been opened once (like a notification badge).
    private var done: (title: String, json: URL)?
    private var doneItem: NSMenuItem!
    /// Last whole percentage shown, so streamed progress updates the menu only when it changes.
    private var summaryPercent = -1
    private var openPlayerItem: NSMenuItem!
    private var shareItem: NSMenuItem!
    /// Reel angle of the menu bar cassette; turns while recording.
    private var reelAngle: CGFloat = 0
    private var reelTimer: Timer?
    /// When the current dictation started listening (for the menu bar clock).
    private var dictationStart: Date?
    /// Twice a second while recording or dictating: the clock next to the menu bar icon.
    private var clockTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = BandjeApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let folderReachable = OutputLocation.restoreChosen()
        #if DEBUG
        if CommandLine.arguments.contains("--check-system-audio") {
            Task {
                let r = await SystemAudioCheck.run()
                let dir = OutputLocation.defaultDirectory.appendingPathComponent("selftest")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? (r.map { $0 ? "allowed" : "denied" } ?? "unknown").write(to: dir.appendingPathComponent("system-audio-check.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--probe-permissions") {
            Task { await PermissionProbe.run() }
            return
        }
        if Selftest.runIfRequested() { return }
        #endif
        // Announce the help book now: Help Viewer only knows a book after its app registered it, and
        // an anchor (Hoe maak ik een template?) in an unknown book opens the general Mac help.
        NSHelpManager.shared.registerBooks(in: .main)
        // Freemium (App Store build): transactions, what is owned, the products.
        Store.start()
        setUpStatusItem()
        Playback.start()
        if let problem = registerShortcuts(Shortcut.record, Shortcut.dictate, Shortcut.mark, tryMark: false) {
            showAlert(tr("hotkey.taken.title", "Sneltoets niet beschikbaar"), problem)
        }
        if !folderReachable {
            showAlert(tr("folder.unreachable", "Opnamemap niet bereikbaar"),
                      tr("folder.unreachable.text", "De map die je koos in Instellingen is er niet (is de schijf aangesloten?). Nieuwe opnames gaan nu naar ~/Music/Bandje. Sluit de schijf aan en start Band·je opnieuw, of kies een andere map."))
        }
        // iCloud first (the container lookup can take a moment): then the recordings folder is known.
        // The app delegate lives as long as the process, so strong captures are fine here.
        Activity.shared.toggleRecording = { self.toggleRecording() }
        Activity.shared.mark = { self.markMoment() }
        Activity.shared.transcribe = { audio in self.transcribeFromWindow(audio) }
        Activity.shared.summarize = { json, template in self.summarizeFromPage(json, template: template) }
        Activity.shared.openTemplates = { self.openTemplates() }
        Activity.shared.restart = { self.restart() }
        Activity.shared.setSync = { on in self.setSync(on) }
        Activity.shared.level = { self.recorder?.stats.level ?? 0 }
        Library.shared.isBusy = { folder in self.isBusy(folder) }
        NotificationCenter.default.addObserver(forName: .bandjeWindowVisibility, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.updateDockPolicy() }
        }
        NotificationCenter.default.addObserver(forName: .bandjeLibraryChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.latestFolderStale = true
                Store.forgetKeys()
                self.updateMenu()
            }
        }
        NotificationCenter.default.addObserver(forName: .bandjeWindowSelection, object: nil, queue: .main) { note in
            guard let folder = note.object as? URL else { return }
            MainActor.assumeIsolated { self.followWindowSelection(folder) }
        }
        updateDockPolicy()
        // A recording that could not move into iCloud yet is tried again when iCloud may be back:
        // another account or iCloud Drive turned on, or Band·je comes to the front (space freed up).
        NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.retryPendingMoves(throttled: false) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.retryPendingMoves(throttled: true)
                Store.refresh()
            }
        }
        Task {
            await ICloudSync.prepare()
            handleFlush(await ICloudSync.flushStaging())
            // Old Mac names ("2026-11-05_14-30") become the iPhone's names, in this Mac's language and
            // region, so both show the same title. Nothing is recording or transcribing yet.
            let dir = OutputLocation.directory
            if await Task.detached(priority: .utility, operation: { Library.renameLegacyFolders(in: dir, isBusy: { _ in false }) }).value > 0 {
                lastRecording = OutputLocation.latestRecording(in: dir)
                latestFolderStale = true
                lastTranscript = nil
            }
            LibraryWatcher.shared.start()
            await Activity.shared.reloadTemplates()
            // Half files from a crash or kill (never a `.caf`, never anything touched in the last hour).
            let leftovers = [dir, ICloudSync.staging]
            Task.detached(priority: .utility) {
                let removed = OutputLocation.removeLeftovers(recordingDirs: leftovers, temp: FileManager.default.temporaryDirectory)
                if removed > 0 { NSLog("Bandje: removed \(removed) leftover temporary files") }
            }
            offerRecovery()
            updateMenu()
        }
        // Started by the user (Finder, Launchpad, Spotlight): the window opens, with the Dock icon.
        // Started at login: only the menu bar, quietly.
        let atLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue ?? false
        // The first time: the window with the welcome and the permissions, also at login. After
        // that the setting decides; after an update the welcome returns (when the window opens)
        // only when the microphone is missing. Automatic pasting is optional and never counts as
        // missing (App Review 2.4.5, 2026-11-17).
        let defaults = UserDefaults.standard
        ReviewPrompt.noteLaunch()
        let firstLaunch = defaults.integer(forKey: "onboardingVersion") < 1
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let updated = LaunchPolicy.updated(lastBuild: defaults.string(forKey: "lastLaunchedBuild"), build: build)
        defaults.set(1, forKey: "onboardingVersion")
        defaults.set(build, forKey: "lastLaunchedBuild")
        let missing = Permissions.microphone != .allowed
        Activity.shared.showsWelcome = LaunchPolicy.showWelcome(firstLaunch: firstLaunch, updated: updated, permissionMissing: missing)
        Activity.shared.welcomeStep = LaunchPolicy.welcomeStep(firstLaunch: firstLaunch)
        if LaunchPolicy.showWindow(atLogin: atLogin, firstLaunch: firstLaunch, setting: LaunchPolicy.windowAtLaunch) {
            MainWindow.show()
        } else {
            // Only the menu bar: no welcome waiting in a closed window; the usual check below says
            // what is missing.
            Activity.shared.showsWelcome = false
        }
        if !Activity.shared.showsWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.checkPermissionsAtLaunch() }
        }
        // Voz in the background a few seconds after launch, so the first dictation needs no wait.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard Transcriber.modelsPresent() else { return }
            Task.detached(priority: .utility) { await Transcriber.shared.preload() }
        }
    }

    /// Once, before the first recording: the law on recording conversations differs per country and
    /// use; the user is responsible for telling the other participants. Returns false on Cancel.
    private func confirmRecordingNotice() -> Bool {
        guard !UserDefaults.standard.bool(forKey: "recordingNoticeShown") else { return true }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("consent.title", "Vertel het als je opneemt")
        alert.informativeText = tr("consent.text", "In sommige landen, en bij zakelijk gebruik, ben je wettelijk verplicht om de andere deelnemers vooraf te vertellen dat je het gesprek opneemt, en soms om toestemming te vragen. Je bent zelf verantwoordelijk voor het naleven van de wet die voor jou geldt.")
        alert.addButton(withTitle: tr("consent.ok", "Begrepen, neem op"))
        alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: "recordingNoticeShown")
        return true
    }

    /// Every launch (not the first): a message when the microphone or the sound of the Mac isn't
    /// allowed. Automatic pasting is optional and never listed (App Review 2.4.5, 2026-11-17), with Open Settings, Later and the standard "Do not show this message
    /// again" (switch it back on in Instellingen > Toegang). The sound of the Mac only when Band·je's
    /// own check said no, checked again now (it may have been switched on since); a silent last
    /// recording proves nothing, it is normal for a meeting in a room.
    private func checkPermissionsAtLaunch() {
        guard Permissions.checkAtLaunch, recorder == nil, dictation == nil else { return }
        guard Permissions.systemAudio == .denied else { return showPermissionsAtLaunch(systemAudioDenied: false) }
        Task {
            let allowed = await SystemAudioCheck.run()
            showPermissionsAtLaunch(systemAudioDenied: allowed == false)
        }
    }

    private func showPermissionsAtLaunch(systemAudioDenied: Bool) {
        guard recorder == nil, dictation == nil else { return }
        var missing: [String] = []
        if Permissions.microphone == .denied {
            missing.append("• " + tr("permcheck.mic", "Microfoon: Band·je hoort jou niet bij opnemen en dicteren."))
        }
        if systemAudioDenied {
            missing.append("• " + tr("permcheck.system", "Geluid van je Mac: de andere kant van een gesprek komt niet in je opnames."))
        }
        guard !missing.isEmpty else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("permcheck.title", "Band·je mist toestemming")
        alert.informativeText = missing.joined(separator: "\n") + "\n\n" + tr("permcheck.text", "Zet Band·je aan in Systeeminstellingen. In Instellingen zie je per toestemming wat er nodig is.")
        alert.addButton(withTitle: tr("permcheck.open", "Open instellingen…"))
        alert.addButton(withTitle: tr("button.later", "Later"))
        alert.showsSuppressionButton = true // standard "Do not show this message again", localized by macOS
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { Permissions.checkAtLaunch = false }
        if answer == .alertFirstButtonReturn { showSettings() }
    }

    /// A `.caf` in the output folder at launch means a recording that never got converted
    /// (crash, forced quit, power loss, failed conversion). Offer to convert it.
    private func offerRecovery() {
        let leftovers = OutputLocation.unfinishedRecordings(in: OutputLocation.directory)
            + OutputLocation.unfinishedRecordings(in: ICloudSync.staging)
        guard !leftovers.isEmpty else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = leftovers.count == 1 ? tr("recovery.title.one", "Onafgemaakte opname gevonden") : tr("recovery.title.many", "Onafgemaakte opnames gevonden")
        alert.informativeText = leftovers.map(\.lastPathComponent).joined(separator: "\n")
            + "\n\n" + tr("recovery.text", "Band·je is tijdens het opnemen gestopt. Nu omzetten naar .m4a? Bij Later blijft het .caf-bestand staan.")
        alert.addButton(withTitle: tr("button.convert", "Zet om"))
        alert.addButton(withTitle: tr("button.later", "Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        finishing += 1  // as after a recording: sync can't be toggled and Band·je won't restart meanwhile
        Task {
            defer { finishing -= 1 }
            for caf in leftovers {
                do {
                    let m4a = try await Task.detached(priority: .userInitiated) { try AudioExport.convertToM4A(caf) }.value
                    OutputLocation.finishMeta(m4a.deletingLastPathComponent())
                    await CoverArt.embed(in: m4a.deletingLastPathComponent(), own: true)
                    lastRecording = m4a
                } catch {
                    showAlert(tr("convert.failed", "Omzetten mislukt"), error.localizedDescription)
                }
            }
            handleFlush(await ICloudSync.flushStaging(isBusy: isBusy))
            updateMenu()
        }
    }

    // MARK: Recordings not in iCloud yet (owner, 2026-11-09)

    /// After a flush of the staging folder: the window and the player follow what moved, the
    /// library refreshes, and the first time a recording has to stay on this Mac the user is told why.
    private func handleFlush(_ result: ICloudSync.FlushResult) {
        for (from, to) in result.moved {
            if from.lastPathComponent != to.lastPathComponent { Library.shared.noteOwnChange(to) }  // " 2": its cover follows
            MainWindow.followMove(from: from, to: to)
            Playback.moved(from: from, to: to)
            if let last = lastRecording, last.deletingLastPathComponent().standardizedFileURL == from.standardizedFileURL {
                lastRecording = Library.audioFile(in: to)
            }
        }
        if !result.moved.isEmpty { LibraryWatcher.shared.changed() }
        if let first = result.failed.first {
            notePending(first)
        } else if !result.moved.isEmpty || ICloudSync.flushStagingPlan().isEmpty {
            // Everything is where it belongs: a next problem is told again.
            UserDefaults.standard.removeObject(forKey: Self.pendingNoticeKey)
        }
    }

    private static let pendingNoticeKey = "iCloudPendingNoticeShown"

    /// A finished recording stays in the staging folder for now: said once (not at every retry or
    /// every recording), calmly, with the reason. The library shows it from where it is.
    private func notePending(_ error: Error?) {
        guard !UserDefaults.standard.bool(forKey: Self.pendingNoticeKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.pendingNoticeKey)
        showAlert(tr("icloud.pending.title", "Nog niet in iCloud"),
                  ICloudSync.pendingReason(error) + " "
                    + tr("icloud.pending.text", "Je opname staat veilig op deze Mac en staat gewoon in Band·je: je kunt hem afspelen, transcriberen, hernoemen en verwijderen. Band·je zet hem in iCloud zodra dat lukt."))
    }

    /// Tries the staging folder again (sync on and iCloud there; not while a recording finishes).
    /// `throttled`: at most once a minute (the app comes to the front often).
    private func retryPendingMoves(throttled: Bool) {
        guard ICloudSync.isActive, finishing == 0, recorder == nil else { return }
        if throttled, Date().timeIntervalSince(lastPendingRetry) < 60 { return }
        lastPendingRetry = Date()
        Task {
            guard await !Task.detached(priority: .utility, operation: { ICloudSync.flushStagingPlan().isEmpty }).value else { return }
            handleFlush(await ICloudSync.flushStaging(isBusy: isBusy))
            updateMenu()
        }
    }
    private var lastPendingRetry = Date.distantPast

    /// A click on the Dock icon (it shows with "Altijd in het Dock") opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Playback.player.saveNow()  // P15
        guard let rec = recorder else { return }
        rec.stop()
        MarkerFile.drainNow()  // the flags set just before quitting
        // Quitting during a recording: convert now (a few seconds for a long call). If that
        // fails or the process is killed, the .caf is offered for conversion at the next launch.
        // Converted: finished like any recording (else a folder in the staging folder that is still
        // marked `recording` would never move to iCloud).
        if let m4a = try? AudioExport.convertToM4A(rec.url) { OutputLocation.finishMeta(m4a.deletingLastPathComponent()) }
    }

    /// The menu, in four groups: the two actions with their status lines, the recordings,
    /// the settings, and help/about/quit.
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        func item(_ title: String, _ action: Selector?) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.target = self
            menu.addItem(it)
            return it
        }
        func status() -> NSMenuItem {
            let it = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            it.isEnabled = false
            it.indentationLevel = 1
            menu.addItem(it)
            return it
        }

        // 1. Actions
        recordItem = item(tr("menu.record.start", "Start opname"), #selector(toggleRecording))
        elapsedItem = status()
        markItem = item(tr("menu.mark", "Markeer dit moment"), #selector(markMoment))
        markItem.indentationLevel = 1
        markItem.isHidden = true
        dictateItem = item(tr("menu.dictate.start", "Start dicteren"), #selector(dictateFromMenu))
        dictationFreeItem = status()
        dictationFreeItem.isHidden = true
        _ = item(tr("menu.transcribeFile", "Transcribeer bestand…"), #selector(transcribeFile))
        transcribeItem = status()
        summaryStatusItem = status()
        doneItem = item("", #selector(openDone))
        doneItem.indentationLevel = 1
        doneItem.isHidden = true

        // 2. Recordings: the current one as the header, what you can do with it, then the recent ones.
        menu.addItem(.separator())
        currentItem = .sectionHeader(title: "")
        menu.addItem(currentItem)
        namingItem = item(tr("menu.nameSpeakers", "Benoem sprekers…"), #selector(nameSpeakers))
        summarizeMenu = NSMenu()
        summarizeMenu.delegate = self
        summarizeItem = item(tr("menu.summarize", "Samenvatten"), nil)
        summarizeItem.submenu = summarizeMenu
        openPlayerItem = item(tr("menu.openInBandje", "Open in Band·je"), #selector(openPlayer))
        shareItem = item(tr("export.share", "Deel als webpagina…"), #selector(shareWebPage))
        for it in [namingItem!, summarizeItem!, openPlayerItem!, shareItem!] { it.indentationLevel = 1 }
        chooseMenu = NSMenu()
        chooseMenu.delegate = self
        let chooseItem = item(tr("menu.choose", "Recente opnames"), nil)
        chooseItem.submenu = chooseMenu

        // 3. Devices
        menu.addItem(.separator())
        micMenu = NSMenu()
        micMenu.delegate = self
        micItem = item(tr("menu.mic", "Microfoon"), nil)
        micItem.submenu = micMenu
        outputMenu = NSMenu()
        outputMenu.delegate = self
        outputItem = item(tr("menu.output", "Geluidsuitvoer"), nil)
        outputItem.submenu = outputMenu
        // Automatic pasting only in a build from source (App Review 2.4.5, see `Paste`).
        #if !APPSTORE
        accessibilityItem = item(tr("menu.dictate.enablePaste", "Zet automatisch plakken aan…"), #selector(askAccessibility))
        #endif

        // 4. The window, settings, help, about, quit
        menu.addItem(.separator())
        let openWindow = item(tr("menu.openWindow", "Open Band·je"), #selector(openWindow))
        openWindow.keyEquivalent = "o"
        let settingsItem = item(tr("menu.settings", "Instellingen…"), #selector(showSettings))
        settingsItem.keyEquivalent = ","
        // "Help" with "I need somebody" (The Beatles) in small, until Help was opened once (owner).
        helpItem = item(tr("menu.help", "Help"), #selector(showHelp))
        if !UserDefaults.standard.bool(forKey: "helpOpened") { helpItem.subtitle = tr("menu.help.subtitle", "I need somebody") }
        _ = item(tr("menu.about", "Over Band·je"), #selector(showAbout))
        // Own selector instead of NSApplication.terminate(_:): macOS 26 adds an automatic symbol to
        // terminate: items, which indents the whole last group.
        let quitItem = item(tr("menu.quit", "Stop Band·je"), #selector(quit))
        quitItem.keyEquivalent = "q"

        statusItem.menu = menu
        lastRecording = OutputLocation.latestRecording(in: OutputLocation.directory)
        latestFolderStale = true
        updateMenu()
    }

    /// The menu's header for the current recording, without saying "Opname" twice: a default name
    /// ("Opname 6 nov 21.35") becomes its date, an own name stays. "Laatste opname" for the newest.
    nonisolated static func menuHeader(title: String, date: Date, latest: Bool, locale: Locale = TranscriptWriter.appLocale) -> String {
        let isDefault = title.hasPrefix(OutputLocation.defaultTitle(for: date, locale: locale))
            || title.hasPrefix(OutputLocation.defaultTitle(for: date, locale: TranscriptWriter.titleLocale()))
        let what = isDefault ? date.formatted(Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute().locale(locale)) : title
        return latest ? tr("menu.current.latest", "Laatste opname · %@", what) : tr("menu.current", "Opname · %@", what)
    }

    #if DEBUG
    func setUpForSnapshot() { setUpStatusItem() }

    /// `--selftest-gate`: Transcribe in the window, as clicked; did it start, did the paywall show.
    func transcribeForSelftest(_ audio: URL) async -> (started: Bool, paywall: Bool) {
        transcribeFromWindow(audio)
        for _ in 0..<20 where transcribing == nil && !Paywall.isShown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return (transcribing != nil, Paywall.isShown)
    }

    /// `--selftest-gate`: the dictation shortcut, only called when the gate stops it before the microphone.
    func dictateForSelftest() -> (started: Bool, paywall: Bool) {
        startDictation()
        return (dictation != nil, Paywall.isShown)
    }

    /// `--selftest-snapshot menu-open`: these device names instead of the real ones, and no
    /// paste-permission item (website screenshots of the menu).
    static var snapshotDevices: (String, String)?

    /// Opens the status menu as a click on the menu bar icon does (returns when it closes).
    func openMenuForSnapshot() {
        statusItem.menu?.appearance = NSApp.appearance  // a menu follows the system, not the app
        statusItem.button?.performClick(nil)
    }

    func closeMenuForSnapshot() { statusItem.menu?.cancelTracking() }

    /// `--select <json>`: that recording is the menu's current one.
    func selectForSnapshot(_ json: URL) {
        lastTranscript = json
        lastRecording = Library.audioFile(in: json.deletingLastPathComponent())
        updateMenu()
    }

    /// The menu bar icon as a PNG at 2x (black on transparent, as a template image is drawn).
    func statusIconForSnapshot() -> Data? {
        guard let image = statusItem.button?.image,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    func menuOutline() -> [String] {
        guard let menu = statusItem?.menu else { return [] }
        menuNeedsUpdate(menu)
        return menu.items.filter { !$0.isHidden }.map { item in
            if item.isSeparatorItem { return "----" }
            if item.isSectionHeader { return "[\(item.title)]" }
            let key = item.keyEquivalent.isEmpty ? "" : "  (\(item.keyEquivalentModifierMask.contains(.control) ? "⌃" : "")\(item.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")\(item.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")\(item.keyEquivalent.uppercased()))"
            let sub = item.subtitle.map { " — \($0)" } ?? ""
            return String(repeating: "  ", count: item.indentationLevel) + item.title + (item.submenu != nil ? " ▸" : "") + sub + key
        }
    }
    #endif

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Asking macOS about a permission is an IPC call; only when the menu opens, not on every
        // update (once a second while recording).
        if menu === statusItem?.menu {
            // Read when the menu opens (naming happens in the window): speakers still without a name.
            let unnamed = currentTranscript.flatMap { try? TranscriptWriter.read(json: $0) }?.unnamedSpeakers ?? 0
            namingItem.title = unnamed > 0 ? tr("menu.nameSpeakers.count", "Benoem sprekers… (%@ zonder naam)", "\(unnamed)")
                                           : tr("menu.nameSpeakers", "Benoem sprekers…")
            let few = Store.fewDictationMinutesLeft
            dictationFreeItem.isHidden = few == nil
            dictationFreeItem.title = few.map(Store.dictationMinutesLeftText) ?? ""
            #if !APPSTORE
            accessibilityItem.isHidden = Paste.allowed
            // After asking: macOS only reports the new state to a new process.
            accessibilityItem.title = Paste.askedThisLaunch
                ? tr("menu.dictate.pasteRestart", "Herstart Band·je voor automatisch plakken")
                : tr("menu.dictate.enablePaste", "Zet automatisch plakken aan…")
            #if DEBUG
            if Self.snapshotDevices != nil { accessibilityItem.isHidden = true }
            #endif
            #endif
        }
        if let items = Self.storeItems, menu === items.unlimited.menu {
            // The App Store's names once the products are loaded.
            items.unlimited.title = tr("menu.buy", "Koop %@…", Store.name(.unlimited))
            items.dictation.title = tr("menu.buy", "Koop %@…", Store.name(.dictation))
            items.unlimited.isHidden = Purchases.shared.hasUnlimited
            items.dictation.isHidden = Purchases.shared.hasDictation
            return
        }
        if menu === micMenu { fillMicMenu() }
        if menu === summarizeMenu { fillSummarizeMenu() }
        if menu === outputMenu { fillOutputMenu() }
        if menu === chooseMenu { fillChooseMenu() }
        updateMenu()
    }

    /// Menu Microfoon: every input device; choosing one sets the macOS default input,
    /// so calls (Continuity, FaceTime, Zoom) and Bandje use the same microphone.
    private func fillMicMenu() {
        micMenu.removeAllItems()
        let current = Recorder.inputDevice()
        let closed = Recorder.lidClosed()
        for device in Recorder.inputDevices() {
            var title = device.name
            if closed && Recorder.isBuiltIn(device.id) { title += " " + tr("menu.mic.lidClosed", "(uit: klep dicht)") }
            let item = NSMenuItem(title: title, action: #selector(chooseMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.id == current ? .on : .off
            micMenu.addItem(item)
        }
        if let chosen = Recorder.chosenMicUID, !Recorder.inputDevices().contains(where: { $0.uid == chosen }) {
            let missing = NSMenuItem(title: tr("menu.mic.missing", "Gekozen microfoon niet aangesloten, Band·je gebruikt de standaard"), action: nil, keyEquivalent: "")
            missing.isEnabled = false
            micMenu.addItem(missing)
        }
        micMenu.addItem(.separator())
        let note = NSMenuItem(title: tr("menu.mic.note", "Geldt voor alle apps, ook om te bellen"), action: nil, keyEquivalent: "")
        note.isEnabled = false
        micMenu.addItem(note)
    }

    /// Menu Geluidsuitvoer: every output device, check mark at the current one. Choosing one
    /// sets the macOS sound output; Bandje never changes it by itself.
    private func fillOutputMenu() {
        outputMenu.removeAllItems()
        let current = Recorder.outputDevice()
        for device in Recorder.outputDevices() {
            let item = NSMenuItem(title: device.name, action: #selector(chooseOutput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.id == current ? .on : .off
            outputMenu.addItem(item)
        }
    }

    @objc private func chooseOutput(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        if let problem = useOutput(uid: uid) { showAlert(tr("output.failed", "Geluid niet omgezet"), problem) }
    }

    /// Makes the output device `uid` the macOS sound output (menu and Settings); returns the
    /// problem when macOS refuses.
    private func useOutput(uid: String) -> String? {
        guard let device = Recorder.outputDevices().first(where: { $0.uid == uid }) else { return nil }
        let status = Recorder.setDefaultOutput(device.id)
        updateMenu()
        return status == noErr ? nil
            : tr("output.failed.text", "macOS weigert de uitvoer om te zetten naar %1$@ (fout %2$@). Kies het apparaat in Systeeminstellingen > Geluid.", device.name, "\(status)")
    }

    @objc private func chooseMic(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String,
              let device = Recorder.inputDevices().first(where: { $0.uid == uid }) else { return }
        useMicrophone(device.id, uid: uid)
    }

    /// Makes `device` the system microphone. If macOS refuses, Bandje alone uses it (old behaviour).
    /// A running recording follows the change (same file).
    private func useMicrophone(_ device: AudioObjectID, uid: String) {
        if Recorder.setDefaultInput(device) == noErr {
            Recorder.chosenMicUID = nil
        } else {
            Recorder.chosenMicUID = uid
        }
        recorder?.micSelectionChanged()
    }

    // MARK: Microphone warning

    /// Once per recording: warn when the microphone cannot be heard, by the other side of a call either.
    private var micWarningShown = false

    private func checkMicrophone(_ rec: Recorder, elapsed: TimeInterval) {
        guard !micWarningShown, recorder === rec else { return }
        let device = Recorder.inputDevice()
        let lidOff = Recorder.lidClosed() && Recorder.isBuiltIn(device)
        // Built-in mic with the lid closed is known to be off; otherwise wait for 6 s of digital silence.
        let silent = elapsed >= 6 && rec.stats.micPeak < 1e-5
        guard lidOff || silent else { return }
        micWarningShown = true
        let name = Recorder.deviceName(device) ?? "?"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("micwarn.title", "Je gesprekspartner hoort je misschien niet")
        alert.informativeText = lidOff
            ? tr("micwarn.lid", "macOS gebruikt “%@” als microfoon, maar die staat uit omdat de klep dicht is. Bel-apps en Band·je horen je dan niet.", name)
            : tr("micwarn.silent", "De microfoon “%@” geeft geen geluid. Bel-apps en Band·je horen je dan niet. Staat hij gedempt of is hij niet aangesloten?", name)
        let suggestion = Recorder.suggestedMicrophone(excluding: device)
        if let suggestion {
            alert.addButton(withTitle: tr("micwarn.use", "Gebruik “%@”", suggestion.name))
        }
        alert.addButton(withTitle: tr("micwarn.settings", "Open Geluid…"))
        alert.addButton(withTitle: tr("micwarn.ignore", "Negeer"))
        NSApp.activate()
        let response = alert.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn
        if let suggestion, response == first {
            useMicrophone(suggestion.id, uid: suggestion.uid)
        } else if response == (suggestion == nil ? first : .alertSecondButtonReturn) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }


    // MARK: System audio warning

    /// Once per recording: warn when macOS doesn't let Band·je record the Mac's sound
    /// (`SystemAudioCheck`, owner 2026-11-12). The recording goes on with the microphone only.
    private var systemAudioWarningShown = false
    /// Not before this moment: the next check because the Mac's sound stays silent while another app plays.
    private var systemAudioRecheckAt = Date.distantFuture

    /// At the start of a recording. On the first recording macOS asks for the permission now, and
    /// the check sees silence until it is answered: then (and after an earlier "allowed", against a
    /// fluke) Band·je checks again for a while before it warns.
    private func checkSystemAudio(_ rec: Recorder) {
        let before = Permissions.systemAudio
        Task {
            var allowed = await SystemAudioCheck.run()
            if allowed == false, before != .denied, recorder === rec {
                allowed = await SystemAudioCheck.runAllowingPrompt(patience: .seconds(before == .allowed ? 4 : 30))
            }
            if allowed == true, recorder === rec { systemAudioRecheckAt = .distantFuture }  // proven for this recording
            guard allowed == false else { return }
            warnSystemAudio(rec)
        }
    }

    /// Every second while recording: when nothing of the Mac's sound came in for 15 seconds while
    /// another app plays sound, check again (at most once a minute). Apps in a call often play
    /// silence, so only the check itself decides.
    private func recheckSystemAudioIfSilent(_ rec: Recorder) {
        guard !systemAudioWarningShown, Date() >= systemAudioRecheckAt, rec.stats.peak < 1e-6,
              SystemAudioCheck.otherProcessPlays() else { return }
        systemAudioRecheckAt = Date().addingTimeInterval(60)
        Task {
            switch await SystemAudioCheck.run() {
            case false?: warnSystemAudio(rec)
            case true?: if recorder === rec { systemAudioRecheckAt = .distantFuture }
            case nil: break
            }
        }
    }

    private func warnSystemAudio(_ rec: Recorder) {
        guard !systemAudioWarningShown, recorder === rec else { return }
        systemAudioWarningShown = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("syswarn.title", "Het geluid van je Mac wordt niet opgenomen")
        alert.informativeText = tr("syswarn.text", "macOS geeft Band·je geen toegang tot het geluid van je Mac. Deze opname heeft alleen je microfoon: de andere kant van een gesprek ontbreekt.\n\nZet Band·je aan bij Systeeminstellingen > Privacy en beveiliging > Scherm- en systeemaudio-opname en start de opname opnieuw.")
        alert.addButton(withTitle: tr("permcheck.open", "Open instellingen…"))
        alert.addButton(withTitle: tr("syswarn.continue", "Ga door met alleen microfoon"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { Permissions.openSettings("Privacy_ScreenCapture") }
    }

    // MARK: Shortcuts

    /// Registers the global shortcuts and saves them; returns a message when one is taken.
    /// On failure the old registration is gone, so callers re-apply the previous ones.
    /// Markeren is registered only while recording (`updateMarkShortcut`); `tryMark` (Settings)
    /// registers it a moment to find out whether another app has it, as the others are checked.
    @discardableResult
    private func registerShortcuts(_ record: Shortcut, _ dictate: Shortcut, _ mark: Shortcut, tryMark: Bool = true) -> String? {
        Hotkey.unregister(.record)
        Hotkey.unregister(.dictate)
        Hotkey.unregister(.mark)
        var problems: [String] = []
        let r = Hotkey.register(.record, key: record.keyCode, modifiers: record.modifiers,
                                pressed: { [weak self] in self?.toggleRecording() })
        if r == noErr { Shortcut.record = record } else {
            problems.append(tr("hotkey.record.taken", "%1$@ is al in gebruik door een andere app (fout %2$@). Start en stop opnames via het menu, of kies een andere sneltoets.", record.display, "\(r)"))
        }
        let d = Hotkey.register(.dictate, key: dictate.keyCode, modifiers: dictate.modifiers,
                                pressed: { [weak self] in self?.dictateKeyPressed() },
                                released: { [weak self] in self?.dictateKeyReleased() })
        if d == noErr { Shortcut.dictate = dictate } else {
            problems.append(tr("hotkey.dictate.taken", "%1$@ is al in gebruik door een andere app (fout %2$@). Dicteren kan via het menu, of kies een andere sneltoets.", dictate.display, "\(d)"))
        }
        if tryMark || recorder != nil {
            let m = Hotkey.register(.mark, key: mark.keyCode, modifiers: mark.modifiers, pressed: { [weak self] in self?.markMoment() })
            if m == noErr { Shortcut.mark = mark } else {
                problems.append(tr("hotkey.mark.taken", "%1$@ is al in gebruik door een andere app (fout %2$@). Markeren kan via het menu, of kies een andere sneltoets.", mark.display, "\(m)"))
            }
            if recorder == nil { Hotkey.unregister(.mark) }
        }
        updateMenu()
        return problems.isEmpty ? nil : problems.joined(separator: "\n\n")
    }

    @objc private func showSettings() { openSettings(tab: nil) }

    private func openSettings(tab: Int?) {
        SettingsWindow.show(
            apply: { [weak self] record, dictate, mark in self?.registerShortcuts(record, dictate, mark) },
            chooseFolder: { [weak self] reset in self?.chooseFolder(reset: reset) ?? false },
            restart: { [weak self] in self?.restart() },
            setSync: { [weak self] on in self?.setSync(on) ?? ICloudSync.isOn },
            chooseMic: { [weak self] uid in
                guard let device = Recorder.inputDevices().first(where: { $0.uid == uid }) else { return }
                self?.useMicrophone(device.id, uid: uid)
                self?.updateMenu()
            },
            chooseOutput: { [weak self] uid in self?.useOutput(uid: uid) },
            tab: tab)
    }

    /// Instellingen > iCloud. Returns the switch's new state.
    private func setSync(_ on: Bool) -> Bool {
        guard on != ICloudSync.isOn else { return ICloudSync.isOn }
        guard ICloudSync.canToggle(recording: recorder != nil, transcribing: transcribing != nil, summarizing: summarizing,
                                   finishing: finishing > 0) else {
            showAlert(tr("folder.busy", "Even wachten"), tr("icloud.busy", "Wacht tot de opname, transcriptie of samenvatting klaar is."))
            return ICloudSync.isOn
        }
        return on ? turnSyncOn() : turnSyncOff()
    }

    /// Asks whether the recordings in the chosen folder move along, then syncs.
    private func turnSyncOn() -> Bool {
        guard ICloudSync.availability == .available, let documents = ICloudSync.documents else { return false }
        let local = OutputLocation.localDirectory
        let folders = OutputLocation.recordingFolders(in: local)
        var move = false
        if !folders.isEmpty {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = tr("icloud.move.title", "Bestaande opnames naar iCloud verplaatsen?")
            alert.informativeText = tr("icloud.move.text", "Er staan %1$@ opnames in %2$@. Laat je ze staan, dan zie je ze in Band·je pas weer als je synchroniseren uitzet.",
                                       "\(folders.count)", local.path)
            alert.addButton(withTitle: tr("icloud.move.move", "Verplaats"))
            alert.addButton(withTitle: tr("icloud.move.leave", "Laat staan"))
            alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: move = true
            case .alertSecondButtonReturn: move = false
            default: return false
            }
        }
        ICloudSync.isOn = true
        try? Summaries.mergeTemplates(from: Summaries.localFolder, into: Summaries.folder, overwrite: false)
        LibraryWatcher.shared.start()
        updateMenu()
        Task {
            handleFlush(await ICloudSync.flushStaging(isBusy: isBusy))
            guard move else { return }
            var failed: [String] = [], kept: [String] = [], alreadyThere = 0
            // What is in iCloud already: a recording copied out earlier is not moved in again as "Name 2".
            let index = await Task.detached(priority: .userInitiated) { ICloudSync.byCreated(documents) }.value
            for folder in folders {
                do {
                    switch try await Task.detached(priority: .userInitiated, operation: { try ICloudSync.moveIn(folder, into: documents, index: index) }).value {
                    case .moved: break
                    case .alreadyThere: alreadyThere += 1
                    case .keptLocal: kept.append(folder.lastPathComponent)
                    }
                } catch {
                    failed.append(folder.lastPathComponent)
                }
            }
            if alreadyThere > 0 || !kept.isEmpty {
                NSLog("Bandje: sync on: \(alreadyThere) recordings already in iCloud (local folder to the Trash), \(kept.count) kept locally")
            }
            if !failed.isEmpty {
                showAlert(tr("icloud.publishFailed.title", "Niet naar iCloud verplaatst"), failed.joined(separator: "\n"))
            }
            if !kept.isEmpty {
                showAlert(tr("icloud.keptLocal.title", "Niet alles verplaatst"),
                          tr("icloud.keptLocal", "Deze opnames staan al in iCloud, maar Band·je weet niet zeker dat het dezelfde of volledige zijn. Ze blijven staan in %@, zodat er niets verloren gaat:", local.path)
                            + "\n" + kept.joined(separator: "\n"))
            }
            updateMenu()
        }
        return true
    }

    /// Back to the chosen folder; iCloud keeps everything. Offers to copy the recordings over.
    private func turnSyncOff() -> Bool {
        let documents = ICloudSync.documents
        let cloudTemplates = Summaries.folder
        ICloudSync.isOn = false
        if documents != nil { try? Summaries.mergeTemplates(from: cloudTemplates, into: Summaries.localFolder, overwrite: true) }
        LibraryWatcher.shared.start()
        updateMenu()
        // Recordings that were waiting for iCloud go to the chosen folder now.
        Task { handleFlush(await ICloudSync.flushStaging(isBusy: isBusy)) }
        guard let documents else { return false }
        let folders = OutputLocation.recordingFolders(in: documents)
        guard !folders.isEmpty else { return false }
        let local = OutputLocation.localDirectory
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("icloud.copy.title", "Opnames uit iCloud naar %@ kopiëren?", local.path)
        alert.informativeText = tr("icloud.copy.text", "In iCloud blijft alles staan. Opnames die nog niet op deze Mac staan, worden eerst gedownload.")
        alert.addButton(withTitle: tr("icloud.copy.copy", "Kopieer"))
        alert.addButton(withTitle: tr("icloud.copy.later", "Niet nu"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        Task {
            var failed: [String] = []
            // What is on this Mac already: a recording copied out earlier is not copied again as "Name 2".
            var index = await Task.detached(priority: .userInitiated) { ICloudSync.byCreated(local) }.value
            var alreadyHere = 0
            for (i, folder) in folders.enumerated() {
                let known = index
                let existing = await Task.detached(priority: .userInitiated) { ICloudSync.counterpart(of: folder, in: known) }.value
                if case .same = existing {
                    alreadyHere += 1
                    continue
                }
                // Copying can be gigabytes: stop before the disk gets too full (`DiskSpace`).
                let free = await Task.detached(priority: .utility) { Recorder.freeBytes(for: local) }.value
                if DiskSpace.level(free) == .tooLow {
                    failed += folders[i...].map(\.lastPathComponent)
                    showAlert(tr("icloud.copyFailed", "Niet alles gekopieerd"),
                              tr("icloud.copyDiskFull", "De schijf is bijna vol; Band·je is gestopt met kopiëren. Niet gekopieerd:") + "\n" + failed.joined(separator: "\n"))
                    updateMenu()
                    return
                }
                do {
                    let copy = try await ICloudSync.copyRecording(folder, into: local)
                    if let created = RecordingMeta.read(from: copy)?.created { index[created, default: []].append(copy) }
                } catch {
                    failed.append(folder.lastPathComponent)
                }
            }
            if alreadyHere > 0 { NSLog("Bandje: sync off: \(alreadyHere) recordings already on this Mac, not copied") }
            if !failed.isEmpty {
                showAlert(tr("icloud.copyFailed", "Niet alles gekopieerd"), failed.joined(separator: "\n"))
            }
            updateMenu()
        }
        return false
    }

    /// Instellingen > Map. `reset` goes back to ~/Music/Bandje. Returns true if it changed.
    private func chooseFolder(reset: Bool) -> Bool {
        guard recorder == nil, transcribing == nil, !summarizing else {
            showAlert(tr("folder.busy", "Even wachten"), tr("folder.busy.text", "Wijzig de map als Band·je niet opneemt, transcribeert of samenvat."))
            return false
        }
        var url: URL?
        if !reset {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = OutputLocation.directory
            panel.message = tr("folder.panel", "Kies de map voor nieuwe opnames. Bestaande opnames blijven waar ze staan.")
            panel.prompt = tr("folder.panel.prompt", "Kies")
            guard panel.runModal() == .OK, let picked = panel.url else { return false }
            if OutputLocation.isSynced(picked) {
                let alert = NSAlert()
                alert.messageText = tr("folder.synced", "Deze map wordt gesynchroniseerd")
                alert.informativeText = tr("folder.synced.text", "%@ staat in iCloud Drive of een andere clouddienst. Je opnames en transcripten gaan dan via die dienst van je Mac af. Toch deze map gebruiken?", picked.path)
                alert.addButton(withTitle: tr("folder.synced.use", "Gebruik toch"))
                alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
            }
            url = picked
        }
        do {
            try OutputLocation.choose(url)
        } catch {
            showAlert(tr("folder.notChosen", "Map niet gekozen"), error.localizedDescription)
            return false
        }
        lastTranscript = nil
        lastRecording = OutputLocation.latestRecording(in: OutputLocation.directory)
        latestFolderStale = true
        updateMenu()
        return true
    }

    /// After a language change: start a new instance, then quit this one.
    private func restart() {
        guard recorder == nil, transcribing == nil, !summarizing, dictation == nil, !dictationBusy, finishing == 0 else {
            showAlert(tr("restart.busy", "Nog niet herstarten"), tr("restart.busy.text", "Band·je is bezig. Herstart Band·je als de opname, transcriptie of samenvatting klaar is."))
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.showAlert(tr("restart.failed", "Herstarten mislukt"), error.localizedDescription)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    #if !APPSTORE
    @objc private func askAccessibility() {
        if Paste.askedThisLaunch { restart(); return }
        Paste.requestPermission()
    }
    #endif

    /// From the menu: like a tap, so Enter stops (the menu is gone before the user speaks).
    @objc private func dictateFromMenu() {
        if dictation != nil { finishDictation(paste: true) } else { startDictation() }
    }

    /// No mode to choose: a short tap keeps listening until Enter or a second tap;
    /// holding the shortcut for at least `holdThreshold` stops on release.
    private func dictateKeyPressed() {
        if dictation != nil {
            dictationLog.notice("stop: shortcut pressed again")
            dictatePressedAt = nil
            finishDictation(paste: true)
            return
        }
        dictatePressedAt = Date()
        startDictation()
    }

    private func dictateKeyReleased() {
        guard let pressed = dictatePressedAt else { return }
        dictatePressedAt = nil
        guard dictation != nil, Date().timeIntervalSince(pressed) >= Self.holdThreshold else { return }
        dictationLog.notice("stop: shortcut released after holding")
        finishDictation(paste: true)
    }

    /// Never shows an alert while the user dictates: that would take the focus from the target app.
    /// Problems before the start (no models, no microphone permission) are shown, because then
    /// nothing is being pasted anyway.
    private func startDictation() {
        guard dictation == nil else { return }
        guard !dictationBusy else { NSSound.beep(); return }
        // Freemium: the free minutes are used up. One that runs when they run out finished normally;
        // this one doesn't start (nothing listens, nothing is pasted) and the paywall comes to the front.
        guard Store.mayDictate else {
            dictationLog.notice("start: free dictation minutes used")
            dictatePressedAt = nil
            NSSound.beep()
            Paywall.show(.dictation)
            return
        }
        guard Transcriber.modelsPresent() else {
            showAlert(tr("dictate.notStarted", "Dicteren niet gestart"), Transcriber.missingModels)
            return
        }
        // P8: the microphone would hear the player; it stays paused afterwards.
        Playback.player.pause(reason: .dictationStarted)
        let capture = DictationCapture()
        dictation = capture // claims the slot now; the permission check below is async
        Task {
            guard await Permissions.microphoneAllowed() else {
                guard dictation === capture else { return } // cancelled or released meanwhile
                dictation = nil
                updateMenu()
                showAlert(tr("dictate.notStarted", "Dicteren niet gestart"), Permissions.microphoneDenied)
                return
            }
            guard dictation === capture else { return } // cancelled or released meanwhile
            do {
                try await capture.start()
            } catch {
                guard dictation === capture else { return }
                dictation = nil
                showAlert(tr("dictate.notStarted", "Dicteren niet gestart"), error.localizedDescription)
                updateMenu()
                return
            }
            guard dictation === capture else { return } // stopped while the microphone was starting
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            dictationLog.notice("start: listening, frontmost \(app, privacy: .public)")
            Hotkey.register(.dictateReturn, key: kVK_Return, pressed: {
                dictationLog.notice("stop: Return")
                self.finishDictation(paste: true)
            })
            Hotkey.register(.dictateEnter, key: kVK_ANSI_KeypadEnter, pressed: {
                dictationLog.notice("stop: Enter")
                self.finishDictation(paste: true)
            })
            Hotkey.register(.dictateEscape, key: kVK_Escape, pressed: { self.cancelDictation() })
            let t = Timer(timeInterval: DictationCapture.maxSeconds, repeats: false) { _ in
                MainActor.assumeIsolated { self.finishDictation(paste: false) }
            }
            RunLoop.main.add(t, forMode: .common)
            dictationTimer = t
            dictationStart = Date()
            updateMenu()
            Task.detached(priority: .userInitiated) { await Transcriber.shared.preload() }
        }
        updateMenu()
    }

    /// Stops the microphone; returns the samples (nil when nothing was running).
    private func endCapture() -> (samples: [Float], rate: Double, mic: String)? {
        guard let capture = dictation else { return nil }
        dictation = nil
        dictationStart = nil
        dictationTimer?.invalidate()
        dictationTimer = nil
        for id in [Hotkey.ID.dictateReturn, .dictateEnter, .dictateEscape] { Hotkey.unregister(id) }
        let (samples, rate) = capture.stop() // also when it never started: the start may still be running
        guard rate > 0 else { return nil } // released before the microphone started
        return (samples, rate, capture.micName)
    }

    private func cancelDictation() {
        _ = endCapture()
        updateMenu()
    }

    private func finishDictation(paste: Bool) {
        let dictationStartedAt = dictationStart
        guard let (samples, rate, mic) = endCapture() else {
            dictationLog.notice("finish: nothing was capturing")
            updateMenu()
            return
        }
        let seconds = rate > 0 ? Double(samples.count) / rate : 0
        dictationLog.notice("finish: \(seconds, format: .fixed(precision: 1), privacy: .public) s of audio, paste \(paste, privacy: .public)")
        guard Double(samples.count) > rate * 0.3 else {
            // A tap, not speech. But if the user spoke for a while and nothing came in, the
            // microphone failed: say so with a sound instead of silently doing nothing.
            if let start = dictationStartedAt, Date().timeIntervalSince(start) > 1 {
                dictationLog.error("finish: no audio came in")
                NSSound.beep()
            }
            updateMenu()
            return
        }
        if DictationCapture.isSilent(samples) {
            dictationLog.notice("finish: silent microphone")
            // Nothing will be pasted, so a message cannot take anything away from the target app.
            updateMenu()
            showAlert(tr("dictate.silent.title", "Niets gehoord"), tr("dictate.silent.text", "De microfoon “%@” gaf alleen stilte. Kies je microfoon in het menu Microfoon. Is de klep dicht, dan staat de ingebouwde microfoon uit.", mic.isEmpty ? "?" : mic))
            return
        }
        if Store.noteDictated(seconds) { dictationWarningDue = true }
        dictationBusy = true
        updateMenu()
        Task {
            // Whatever happens below: the free-minutes note comes after it (after the paste).
            defer { showDictationWarningWhenIdle() }
            var text = ""
            var failure: String?
            do {
                text = try await Task.detached(priority: .userInitiated) {
                    try await Transcriber.shared.dictate(samples, rate: rate)
                }.value
            } catch {
                failure = error.localizedDescription
            }
            dictationBusy = false
            updateMenu()
            if let failure {
                dictationLog.error("recognize: failed: \(failure, privacy: .public)")
                showAlert(tr("dictate.failed", "Dicteren mislukt"), failure)
                return
            }
            dictationLog.notice("recognize: \(text.count, privacy: .public) characters")
            guard !text.isEmpty else { NSSound.beep(); return }
            let outcome = await Paste.deliver(Self.withTrailingSpace(text), paste: paste)
            dictationLog.notice("deliver: \(outcome.rawValue, privacy: .public)")
            // Secure input: the text is on the clipboard; a sound says "paste it yourself" without
            // taking the focus. No paste permission: silent, pasting with ⌘V is the normal way and
            // automatic pasting optional (owner, 2026-11-17). Never ask for the permission here: a prompt or System
            // Settings right after dictating gets in the way (and App Review frowns on it). Band·je only
            // asks when the user turns automatic pasting on (welcome, menu or Settings).
            if outcome == .secureInput { NSSound(named: "Funk")?.play() }
            if outcome == .notAllowed || outcome == .secureInput { showPasteHint() }
        }
    }

    /// The once-only free dictation note (`Store.showDictationWarning`). It takes the focus, so only
    /// a moment after the paste (the target app handles ⌘V first) and never during a dictation; a
    /// dictation started meanwhile takes it along to its own end.
    private func showDictationWarningWhenIdle() {
        guard dictationWarningDue else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard dictationWarningDue, dictation == nil, !dictationBusy, !Paywall.isShown else { return }
            dictationWarningDue = false
            Store.showDictationWarning()
        }
    }

    @objc private func toggleRecording() {
        if let recorder {
            stopRecording(recorder)
            return
        }
        guard confirmRecordingNotice() else { return }
        Task {
            guard await Permissions.microphoneAllowed() else {
                showAlert(tr("record.notStarted", "Opname niet gestart"), Permissions.microphoneDenied)
                return
            }
            // System audio not known to be allowed (a first recording): let macOS ask now and wait
            // for the answer. A recording started while macOS's question is open fails (error
            // 268451843, measured 2026-11-12). Off: the recording starts anyway and warns at once.
            let systemAudio = Permissions.systemAudio
            if systemAudio != .allowed {
                _ = await SystemAudioCheck.runAllowingPrompt(patience: .seconds(systemAudio == .denied ? 0 : 30))
            }
            // Free space first, before the recording's folder is made: where the recording is
            // written and where it ends up (the chosen folder, another disk or iCloud Drive).
            let dir = OutputLocation.recordingDirectory
            let destination = OutputLocation.directory
            let free = await Task.detached(priority: .userInitiated) { () -> Int64? in
                let here = Recorder.freeBytes(for: dir), there = Recorder.freeBytes(for: destination)
                guard let here, let there else { return here ?? there }
                return min(here, there)
            }.value
            if let problem = Recorder.startProblem(freeBytes: free) {
                showAlert(tr("record.notStarted", "Opname niet gestart"), problem)
                return
            }
            guard recorder == nil else { return }
            do {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    throw RecorderError(message: tr("record.folderFailed", "Kan de opnamemap %@ niet maken. Kies een andere map in Instellingen.", dir.path))
                }
                let now = Date()
                let rec = Recorder(url: try OutputLocation.newRecording(title: OutputLocation.defaultTitle(for: now), date: now, in: dir))
                // The app delegate lives as long as the process, so capturing it strongly is fine.
                rec.onFailure = { [weak rec] message in
                    MainActor.assumeIsolated { // delivered on the main queue
                        guard let rec, self.recorder === rec else { return }
                        self.stopRecording(rec)
                        self.showAlert(tr("record.stopped", "Opname gestopt"), message)
                    }
                }
                // P7: the recording would take in the player's sound; it stays paused afterwards.
                Playback.player.pause(reason: .recordingStarted)
                try rec.start()
                recorder = rec
                recordingFreeBytes = free
                diskCheckedAt = Date()
                recordingMarks = Markers()
                Activity.shared.recordingMarkers = 0
                updateMarkShortcut()
                micWarningShown = false
                systemAudioWarningShown = false
                systemAudioRecheckAt = Date().addingTimeInterval(15)
                startTimer()
                checkMicrophone(rec, elapsed: 0)
                checkSystemAudio(rec)
            } catch {
                showAlert(tr("record.notStarted", "Opname niet gestart"), error.localizedDescription)
            }
            updateMenu()
        }
    }

    // MARK: Markers (specs/markers.md)

    /// ⌃⌥⌘M is Band·je's only while recording: outside a recording another app may use it.
    private func updateMarkShortcut() {
        guard recorder != nil else { Hotkey.unregister(.mark); return }
        let mark = Shortcut.mark
        Hotkey.register(.mark, key: mark.keyCode, modifiers: mark.modifiers, pressed: { [weak self] in self?.markMoment() })
    }

    /// Markeer dit moment (menu, shortcut, the record screen's flag): a marker at the time in the
    /// audio written so far, into the recording's `.bandje.json` at once (it survives a crash).
    @objc private func markMoment() {
        guard let rec = recorder, rec.startDate != nil else { NSSound.beep(); return }
        let time = Double(rec.framesWritten) / FileWriter.fileSampleRate
        let folder = rec.url.deletingLastPathComponent()
        MarkerFile.changeLater(in: folder, { $0.add(at: time) }, failed: { NSSound.beep() })
        recordingMarks.add(at: time)  // within a second of the last flag: that one (Markers.mergeDistance)
        Activity.shared.recordingMarkers = recordingMarks.count
        NSSound(named: "Tink")?.play()
    }

    private func stopRecording(_ rec: Recorder) {
        if let start = rec.startDate {
            Permissions.noteSystemAudio(peak: rec.stats.peak, seconds: Date().timeIntervalSince(start))
        }
        rec.stop()
        recorder = nil
        updateMarkShortcut()
        timer?.invalidate()
        timer = nil
        lastRecording = rec.url
        latestFolderStale = true
        updateMenu()
        let caf = rec.url
        finishing += 1
        Task {
            defer { finishing -= 1 }
            do {
                var m4a = try await Task.detached(priority: .userInitiated) { try AudioExport.convertToM4A(caf) }.value
                // The flags set while recording are on disk before `.bandje.json` is read and written again.
                await MarkerFile.drain()
                OutputLocation.finishMeta(m4a.deletingLastPathComponent())
                // The cover goes into the audio now, before it moves to iCloud or is transcribed.
                await CoverArt.embed(in: m4a.deletingLastPathComponent(), own: true)
                // Syncing: the finished recording moves from the staging folder into iCloud Drive.
                // When that fails, or iCloud isn't there (signed out, iCloud Drive off), it stays in
                // the staging folder: the library shows it from there, and it is moved later.
                let inStaging = ICloudSync.isStaged(m4a.deletingLastPathComponent())
                if ICloudSync.isActive, let documents = ICloudSync.documents {
                    let folder = m4a.deletingLastPathComponent()
                    do {
                        let moved = try await Task.detached(priority: .userInitiated) { try ICloudSync.publish(folder, into: documents) }.value
                        // Under a new name when it was taken in iCloud (" 2"): its cover follows.
                        m4a = Library.audioFile(in: moved) ?? moved.appendingPathComponent(m4a.lastPathComponent)
                        if moved.lastPathComponent != folder.lastPathComponent { Library.shared.noteOwnChange(moved) }
                        UserDefaults.standard.removeObject(forKey: Self.pendingNoticeKey)
                    } catch {
                        NSLog("Bandje: the recording stays in the staging folder for now: \(error.localizedDescription)")
                        notePending(error)
                    }
                } else if ICloudSync.isOn, inStaging {
                    notePending(nil)
                }
                // Recorded into staging, but sync was turned off since: the chosen folder.
                if !ICloudSync.isOn, inStaging {
                    let folder = m4a.deletingLastPathComponent(), local = OutputLocation.localDirectory
                    if let moved = try? await Task.detached(priority: .userInitiated, operation: { try ICloudSync.moveLocal(folder, into: local) }).value {
                        m4a = moved.appendingPathComponent(moved.lastPathComponent + ".m4a")
                    }
                }
                if lastRecording == caf { lastRecording = m4a }
                MainWindow.reveal(m4a, opening: true)  // the window opens with the recording just made
                if Self.autoTranscribe { enqueueTranscription(m4a) }
            } catch {
                showAlert(tr("convert.failed", "Omzetten mislukt"), error.localizedDescription)
            }
            latestFolderStale = true
            updateMenu()
        }
    }

    /// "Transcribeer" in the window, for a recording without transcript (from the iPhone, or an
    /// older one): audio still in iCloud is downloaded first. Mode A/B only for the Mac's own stereo recordings.
    private func transcribeFromWindow(_ audio: URL) {
        guard Store.mayTranscribe(audio: audio) else {
            Paywall.show(.transcribe) { [weak self] in self?.transcribeFromWindow(audio) }
            return
        }
        Task {
            do {
                try await Activity.shared.whileDownloading(audio) { try await ICloudSync.ensureDownloaded(audio) }
            } catch {
                showAlert(tr("transcribe.none", "Geen transcriptie"), error.localizedDescription)
                return
            }
            transcriptionQueue.append(TranscriptionJob(audio: audio, ownRecording: OutputLocation.isOwnRecording(audio)))
            runNextTranscription()
        }
    }

    /// Instellingen › Transcriptie › Transcribeer automatisch (on by default).
    static var autoTranscribe: Bool {
        UserDefaults.standard.object(forKey: "autoTranscribe") == nil || UserDefaults.standard.bool(forKey: "autoTranscribe")
    }

    /// Transcriptions run one at a time at low priority; a recording can start at any moment and
    /// is not affected (its capture runs on the Core Audio IO thread and its own writer thread).
    func enqueueTranscription(_ audio: URL) {
        transcriptionQueue.append(TranscriptionJob(audio: audio, automatic: true))
        runNextTranscription()
    }

    /// `Transcribeer bestand…`, e.g. a voice memo. The file may be anywhere (read-only
    /// access via the open panel); a copy, the transcript and the player go to the recordings folder
    /// under the file's name. A stereo file named like our own recordings goes through mode A/B, anything else mode C.
    @objc private func transcribeFile() {
        guard Store.mayTranscribeNew else {
            Paywall.show(.transcribe) { [weak self] in self?.transcribeFile() }
            return
        }
        NSApp.activate()
        let panel = NSOpenPanel()
        // Video too: only its sound is kept (OutputLocation.prepareImport), as on the iPhone.
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = tr("panel.transcribe.message", "Kies een of meer audiobestanden om te transcriberen.")
        panel.prompt = tr("panel.transcribe.prompt", "Transcribeer")
        guard panel.runModal() == .OK else { return }
        let dir = OutputLocation.directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            showAlert(tr("transcribe.none", "Geen transcriptie"), tr("transcribe.folderFailed", "Kan de opnamemap %@ niet maken.", dir.path))
            return
        }
        let urls = panel.urls
        Task {
            var first: URL?
            var problems: [String] = []
            for url in urls {
                let name = url.deletingPathExtension().lastPathComponent
                // An imported file gets its own folder with a copy of the audio, for the player.
                let (folder, copy) = OutputLocation.importFolder(for: url, in: dir)
                let audio: URL
                do {
                    audio = try await OutputLocation.prepareImport(folder: folder, copy: copy, original: url)
                } catch {
                    if copy != url { try? FileManager.default.removeItem(at: folder) }
                    problems.append(error.localizedDescription)
                    continue
                }
                if first == nil { first = audio }
                transcriptionQueue.append(TranscriptionJob(audio: audio, directory: folder,
                                                           ownRecording: TranscriptWriter.isRecordingName(name)))
            }
            runNextTranscription()
            // The window opens with the (first) file, so its progress shows there.
            if let first { MainWindow.reveal(first, opening: true) }
            if !problems.isEmpty { showAlert(tr("transcribe.none", "Geen transcriptie"), problems.joined(separator: "\n\n")) }
        }
    }

    private func runNextTranscription() {
        guard transcribing == nil, !transcriptionQueue.isEmpty else { return }
        guard Transcriber.modelsPresent() else {
            transcriptionQueue.removeAll()
            showAlert(tr("transcribe.none", "Geen transcriptie"), Transcriber.missingModels)
            return
        }
        let job = transcriptionQueue.removeFirst()
        // Freemium: checked again here, as a queued one may come after the last free one finished.
        // A manual one asks (and continues after a purchase); an automatic one just doesn't start.
        guard Store.mayTranscribe(audio: job.audio) else {
            if !job.automatic {
                Paywall.show(.transcribe) { [weak self] in
                    self?.transcriptionQueue.append(job)
                    self?.runNextTranscription()
                }
            }
            runNextTranscription()
            return
        }
        let audio = job.audio
        transcribing = audio
        transcriptionStatus = tr("status.transcribing", "Transcriberen…")
        transcriptionFraction = nil
        updateMenu()
        // The app delegate lives as long as the process, so strong captures are fine.
        Task.detached(priority: .utility) {
            let result: Result<URL, Error>
            do {
                result = .success(try await Transcriber.shared.transcribe(audio, in: job.directory,
                                                                          ownRecording: job.ownRecording) { status in
                    Task { @MainActor in self.show(status) }
                }.url)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.finishTranscription(audio, result) }
        }
    }

    /// Set while a model loads; the menu says so only after 1 s (a warm load is shorter), then
    /// with an estimated % every half second.
    private var loadingSince: Date?
    private var loadingTimer: Timer?

    private func show(_ status: Transcriber.Status) {
        guard transcribing != nil else { return }
        switch status {
        case .loading(let model, let firstTime, let expected):
            let since = Date()
            loadingSince = since
            loadingTimer?.invalidate()
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self, self.loadingSince == since, self.transcribing != nil else { timer.invalidate(); return }
                    let elapsed = Date().timeIntervalSince(since)
                    guard elapsed >= 1 else { return }
                    let percent = Transcriber.loadPercent(elapsed: elapsed, expected: expected)
                    self.transcriptionStatus = model == .speakers
                        ? tr("status.speakersPercent", "Sprekers herkennen… %@%%", "\(percent)")
                        : tr("status.speechPercent", "Spraakmodel voorbereiden… %@%%", "\(percent)")
                    self.transcriptionHint = firstTime ? Self.firstLoadHint : nil
                    self.updateMenu()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            loadingTimer = timer
            return
        case .transcribing(let f):
            loadingSince = nil
            loadingTimer?.invalidate()
            loadingTimer = nil
            transcriptionHint = nil
            transcriptionFraction = f
            transcriptionStatus = tr("status.progress", "Transcriberen… %@%%", "\(Int((f * 100).rounded()))")
        }
        updateMenu()
    }

    static var firstLoadHint: String {
        tr("status.firstLoad", "Alleen de eerste keer na installeren of bijwerken: dit duurt ongeveer een minuut.")
    }

    private func finishTranscription(_ audio: URL, _ result: Result<URL, Error>) {
        transcribing = nil
        loadingSince = nil
        loadingTimer?.invalidate()
        loadingTimer = nil
        transcriptionStatus = ""
        transcriptionHint = nil
        transcriptionFraction = nil
        switch result {
        case .failure(let error):
            showAlert(tr("transcribe.failed", "Transcriberen mislukt"), "\(audio.lastPathComponent): \(error.localizedDescription)")
        case .success(let md):
            let json = md.deletingPathExtension().appendingPathExtension("json")
            lastTranscript = json
            Store.noteTranscribed(json: json)
            announceDone(tr("done.transcript", "Transcript klaar: %@", recordingName(of: json)), json: json)
            LibraryWatcher.shared.changed()
        }
        updateMenu()
        runNextTranscription()
    }

    /// The newest transcript of this session, otherwise pick one in the recordings folder.
    @objc private func nameSpeakers() {
        guard let json = currentTranscript ?? chooseTranscript() else { return }
        MainWindow.show(select: json, nameSpeakers: true)
    }

    @objc private func openWindow() { MainWindow.show() }

    /// Wijzig › Zoek… (⌘F): search the open recording's transcript.
    @objc func findInTranscript() { NotificationCenter.default.post(name: .bandjeFind, object: nil) }

    /// The Dock icon (and the app's own menu bar) while the window is open, or always when the
    /// user chose that in Instellingen; otherwise menu bar only.
    private func updateDockPolicy() {
        let regular = LaunchPolicy.dockIcon(windowVisible: MainWindow.isOpen, minimized: MainWindow.isMinimized,
                                            alwaysInDock: UserDefaults.standard.bool(forKey: "showInDock"))
        if regular, NSApp.mainMenu == nil {
            NSApp.mainMenu = Self.makeMainMenu()
            NSApp.mainMenu?.items.first?.submenu?.delegate = self  // hides the Buy items already owned
        }
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
    }

    /// The main menu's Samenvatten (hidden without Apple Intelligence).
    private static var summariesMenuItem: NSMenuItem?
    /// The main menu's Archief › Start opname and Start dicteren, kept in step with the menu bar menu.
    private static var fileMenuItems: (record: NSMenuItem, dictate: NSMenuItem)?
    /// The app menu's Buy items (App Store build).
    private static var storeItems: (unlimited: NSMenuItem, dictation: NSMenuItem)?

    // MARK: Purchases (App Store build, specs/purchase.md)

    @objc private func buyUnlimited() { Paywall.show(.transcribe) }

    @objc private func buyDictation() { Paywall.show(.dictation) }

    @objc private func restorePurchases() { Task { await Store.restore(alert: true) } }

    /// Settings › Aankopen with the App Store's redeem sheet.
    @objc private func redeemCode() {
        PurchasesSettings.redeemOnAppear = true
        openSettings(tab: SettingsWindow.purchasesTab)
        NotificationCenter.default.post(name: .bandjeRedeemCode, object: nil)
    }

    /// The app menu bar for while Bandje has a window: About, Settings, Quit; Edit (so ⌘C/⌘V/⌘A work
    /// in the window's text fields); Window.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            holder.submenu = m
            main.addItem(holder)
        }
        func it(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        var app = [
            it(tr("menu.about", "Over Band·je"), #selector(BandjeApp.showAbout), ""),
            .separator(),
            it(tr("menu.settings", "Instellingen…"), #selector(BandjeApp.showSettings), ","),
        ]
        // Freemium (owner, 2026-11-11): the purchases after Settings, as the HIG puts them; only
        // in the App Store build. A Buy item hides once that product is owned.
        if Store.isActive {
            let unlimited = it(tr("menu.buy", "Koop %@…", tr("store.unlimited", "Band·je Onbeperkt")), #selector(BandjeApp.buyUnlimited), "")
            let dictation = it(tr("menu.buy", "Koop %@…", tr("store.dictation", "Band·je Dicteren")), #selector(BandjeApp.buyDictation), "")
            storeItems = (unlimited, dictation)
            app += [.separator(), unlimited, dictation,
                    it(tr("store.restore", "Herstel aankopen"), #selector(BandjeApp.restorePurchases), ""),
                    it(tr("store.redeem", "Wissel code in…"), #selector(BandjeApp.redeemCode), "")]
        }
        app += [
            .separator(),
            it(tr("menu.hide", "Verberg Band·je"), #selector(NSApplication.hide(_:)), "h"),
            it(tr("menu.quit", "Stop Band·je"), #selector(NSApplication.terminate(_:)), "q"),
        ]
        submenu("Band·je", app)
        // Open opnamemap lives here (owner: rarely used from the menu bar). Recording, dictating and
        // Transcribeer bestand… (⌘O) as in the menu bar menu (owner, 2026-11-12); their titles and
        // shortcuts follow it in `updateMenu`.
        let record = it(tr("menu.record.start", "Start opname"), #selector(BandjeApp.toggleRecording), "")
        let dictate = it(tr("menu.dictate.start", "Start dicteren"), #selector(BandjeApp.dictateFromMenu), "")
        fileMenuItems = (record, dictate)
        submenu(tr("menu.file", "Archief"), [
            record,
            dictate,
            it(tr("menu.transcribeFile", "Transcribeer bestand…"), #selector(BandjeApp.transcribeFile), "o"),
            .separator(),
            it(tr("menu.openFolder", "Open opnamemap"), #selector(BandjeApp.openFolder), ""),
            .separator(),
            it(tr("window.print", "Druk af…"), #selector(BandjeApp.printTranscript), "p"),
        ])
        // Templates for summaries (owner): only where summaries exist (see `summariesAvailable`).
        submenu(tr("menu.summarize", "Samenvatten"), [
            it(tr("menu.templates.new", "Nieuw template"), #selector(BandjeApp.newTemplate), ""),
            it(tr("menu.summarize.folder", "Open templatemap"), #selector(BandjeApp.openTemplates), ""),
            .separator(),
            it(tr("menu.templates.help", "Hulp bij templates"), #selector(BandjeApp.showTemplateHelp), ""),
        ])
        summariesMenuItem = main.items.last
        summariesMenuItem?.isHidden = !summariesAvailable
        submenu(tr("menu.edit", "Wijzig"), [
            it(tr("menu.undo", "Herstel"), Selector(("undo:")), "z"),
            it(tr("menu.redo", "Opnieuw"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            it(tr("menu.cut", "Knip"), #selector(NSText.cut(_:)), "x"),
            it(tr("menu.copy", "Kopieer"), #selector(NSText.copy(_:)), "c"),
            it(tr("menu.paste", "Plak"), #selector(NSText.paste(_:)), "v"),
            it(tr("menu.selectAll", "Selecteer alles"), #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            it(tr("menu.find", "Zoek…"), #selector(BandjeApp.findInTranscript), "f"),
        ])
        submenu(tr("menu.window", "Venster"), [
            it(tr("menu.minimize", "Minimaliseer"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            it(tr("menu.close", "Sluit"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.windowsMenu = main.items.last?.submenu
        submenu(tr("menu.help", "Help"), [
            it(tr("menu.helpBook", "Band·je-help"), #selector(BandjeApp.showHelp), "?"),
        ])
        NSApp.helpMenu = main.items.last?.submenu  // macOS adds its search field
        return main
    }

    // MARK: Summaries and player

    /// macOS 26 or later with Apple Intelligence on and its model present; otherwise the feature
    /// does not exist for the user (no menu item, no folder, no message).
    static var summariesAvailable: Bool {
        if #available(macOS 26.0, *) { return OnDeviceSummarizer.isAvailable }
        return false
    }

    /// `.json` of the newest transcript of this session, else that of the last recording.
    private var currentTranscript: URL? {
        if let json = lastTranscript, FileManager.default.fileExists(atPath: json.path) { return json }
        guard let audio = lastRecording else { return nil }
        let json = audio.deletingPathExtension().appendingPathExtension("json")
        return FileManager.default.fileExists(atPath: json.path) ? json : nil
    }

    /// Name of the current recording's folder (or its file name for an older recording directly in the folder).
    private var currentRecordingName: String? {
        guard let file = currentTranscript ?? lastRecording.flatMap({ FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }) else { return nil }
        return recordingName(of: file)
    }

    private func recordingName(of file: URL) -> String {
        let folder = file.deletingLastPathComponent()
        return folder.standardizedFileURL == OutputLocation.directory.standardizedFileURL
            ? file.deletingPathExtension().lastPathComponent : folder.lastPathComponent
    }

    private func fillSummarizeMenu() {
        summarizeMenu.removeAllItems()
        summarizeMenu.addItem(.sectionHeader(title: tr("menu.summarize.pick", "Kies een template")))
        if !ICloudSync.isActive || LibraryWatcher.shared.gathered { Summaries.seedIfMissing() }
        if #available(macOS 26.0, *) { OnDeviceSummarizer.prewarm() }
        // The names read in the background (iCloud can make reading wait); the first time, here.
        let cached = Activity.shared.templateNames
        let templates = cached.isEmpty ? Summaries.templates().map(\.name) : cached
        Task { await Activity.shared.reloadTemplates() }
        for name in templates {
            let it = NSMenuItem(title: name, action: #selector(summarizeLast(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = name
            it.isEnabled = !summarizing
            summarizeMenu.addItem(it)
        }
        if templates.isEmpty {
            let none = NSMenuItem(title: tr("menu.summarize.none", "Geen templates in de templatemap"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            summarizeMenu.addItem(none)
        }
        summarizeMenu.addItem(.separator())
        let folder = NSMenuItem(title: tr("menu.summarize.folder", "Open templatemap"), action: #selector(openTemplates), keyEquivalent: "")
        folder.target = self
        summarizeMenu.addItem(folder)
        let howTo = NSMenuItem(title: tr("menu.summarize.howTo", "Hoe maak ik een template?"), action: #selector(showTemplateHelp), keyEquivalent: "")
        howTo.target = self
        summarizeMenu.addItem(howTo)
    }

    @objc private func summarizeLast(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let template = Summaries.templates().first(where: { $0.name == name }) else { return }
        guard let json = currentTranscript ?? chooseTranscript() else { return }
        // Chosen in the menu: the window opens with the recording, its progress shows there.
        MainWindow.reveal(json, opening: true)
        summarize(json, template)
    }

    /// Menu Recente opnames: the eight most recent recordings with a transcript (by recording
    /// date, `OutputLocation.recordingDate`); choosing one makes
    /// it the current recording for Benoem sprekers, Samenvatten and the page.
    private func fillChooseMenu() {
        chooseMenu.removeAllItems()
        let current = currentTranscript?.standardizedFileURL
        for json in OutputLocation.recentTranscripts(in: OutputLocation.directory, limit: 8) {
            let it = NSMenuItem(title: recordingName(of: json), action: #selector(chooseRecording(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = json
            it.state = json.standardizedFileURL == current ? .on : .off
            chooseMenu.addItem(it)
        }
        if chooseMenu.items.isEmpty {
            let none = NSMenuItem(title: tr("menu.choose.none", "Nog geen transcripten"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            chooseMenu.addItem(none)
        }
        chooseMenu.addItem(.separator())
        let other = NSMenuItem(title: tr("menu.choose.other", "Andere…"), action: #selector(chooseRecording(_:)), keyEquivalent: "")
        other.target = self
        chooseMenu.addItem(other)
    }

    @objc private func chooseRecording(_ sender: NSMenuItem) {
        guard let json = (sender.representedObject as? URL) ?? chooseTranscript(),
              FileManager.default.fileExists(atPath: json.path) else { return }
        lastTranscript = json
        let audio = json.deletingPathExtension().appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: audio.path) { lastRecording = audio }
        updateMenu()
        MainWindow.reveal(json)  // the window follows the menu's choice
    }

    /// The window selected `folder`: it becomes the menu's current recording (Benoem sprekers,
    /// Samenvatten, Deel), so menu and window are about the same recording.
    private func followWindowSelection(_ folder: URL) {
        let json = folder.appendingPathComponent("\(folder.lastPathComponent).json")
        if FileManager.default.fileExists(atPath: json.path) {
            lastTranscript = json
        } else {
            lastTranscript = nil
        }
        lastRecording = Library.audioFile(in: folder)
        updateMenu()
    }

    /// Open panel in the recordings folder for a transcript (`.md` or `.json`); returns the `.json`.
    private func chooseTranscript() -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType("net.daringfireball.markdown") ?? .plainText]
        panel.directoryURL = OutputLocation.directory
        panel.message = tr("choose.panel", "Kies een transcript (.md of .json).")
        panel.prompt = tr("choose.panel.prompt", "Kies")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.deletingPathExtension().appendingPathExtension("json")
    }

    private func summarize(_ json: URL, _ template: Summaries.Template) {
        guard #available(macOS 26.0, *), !summarizing else { return }
        let transcript: Transcript
        do {
            transcript = try TranscriptWriter.read(json: json)
        } catch {
            showAlert(tr("summary.failed", "Samenvatten mislukt"), error.localizedDescription)
            return
        }
        summarizing = true
        summarizingJSON = json
        summaryPercent = -1
        summaryStatusItem.title = tr("status.summarizing", "Samenvatten…")
        updateMenu()
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                let body = try await OnDeviceSummarizer.summarize(transcript, template: template) { p in
                    Task { @MainActor in
                        let percent = Int((p * 100).rounded())
                        guard percent != self.summaryPercent, self.summarizing else { return }
                        self.summaryPercent = percent
                        self.summaryStatusItem.title = tr("status.summarizingProgress", "Samenvatten… %@%%", "\(percent)")
                        self.updateMenu()
                    }
                }
                let out = Summaries.outputURL(json: json, template: template.name)
                let doc = Summaries.document(transcript, template: template.name, body: body)
                try Files.write(Data(doc.utf8), to: out)
                result = .success(out)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                self.summarizing = false
                self.summarizingJSON = nil
                self.updateMenu()
                switch result {
                case .success:
                    self.announceDone(tr("done.summary", "Samenvatting klaar: %@", template.name), json: json)
                    LibraryWatcher.shared.changed()
                    // Only in a window that is open: a finished job never opens it (the check mark
                    // on the cassette and the menu line say it is done).
                    MainWindow.reveal(json)
                case .failure(let error): self.showAlert(tr("summary.failed", "Samenvatten mislukt"), error.localizedDescription)
                }
            }
        }
    }

    /// "Vat samen" in the window: only known templates, never while summarizing, and an existing
    /// summary is only replaced after the user says so.
    private func summarizeFromPage(_ json: URL, template name: String) {
        guard Self.summariesAvailable, let template = Summaries.templates().first(where: { $0.name == name }) else { return }
        guard !summarizing else { NSSound.beep(); return }
        if FileManager.default.fileExists(atPath: Summaries.outputURL(json: json, template: name).path) {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = tr("summary.replace", "Samenvatting vervangen?")
            alert.informativeText = tr("summary.replace.text", "Er is al een samenvatting met de template %@. Een nieuwe vervangt die.", name)
            alert.addButton(withTitle: tr("summary.replace.ok", "Vervang"))
            alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        lastTranscript = json
        summarize(json, template)
    }

    @objc private func openTemplates() {
        if !ICloudSync.isActive || LibraryWatcher.shared.gathered { Summaries.seedIfMissing() }
        if !NSWorkspace.shared.open(Summaries.folder) {
            showAlert(tr("folder.notOpened", "Map niet geopend"), tr("folder.notOpened.text", "Kan %@ niet openen.", Summaries.folder.path))
        }
    }

    /// The page of the current recording, written fresh each time (so older transcripts
    /// get the current page too; it takes milliseconds).
    /// "Deel als webpagina…": asks for the size, makes the page and shows the share sheet.
    @objc private func shareWebPage() {
        guard let json = currentTranscript else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("export.share", "Deel als webpagina…")
        alert.informativeText = tr("export.text", "Eén bestand met speler, transcript, samenvattingen en de audio. Werkt in elke browser, ook offline. Compact maakt de audio kleiner, zodat het in een mail past.")
        alert.addButton(withTitle: tr("export.compact", "Compact"))
        alert.addButton(withTitle: tr("export.full", "Zoals opgenomen"))
        alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
        let answer = alert.runModal()
        guard answer != .alertThirdButtonReturn else { return }
        Task {
            do {
                let page = try await WebExport.export(json: json, compact: answer == .alertFirstButtonReturn)
                guard let button = statusItem.button else { return }
                ShareText.show([page], kind: .webPage, title: recordingName(of: json), date: OutputLocation.recordingDate(json),
                               relativeTo: button.bounds, of: button)
            } catch {
                showAlert(tr("export.failed", "Audiopagina maken mislukt"), error.localizedDescription)
            }
        }
    }

    @objc private func openPlayer() {
        guard let json = currentTranscript else { return }
        MainWindow.show(select: json)
    }

    /// The Apple Help book in the bundle (`Bandje.help`, built from Resources/Help by scripts/make-help.py).
    @objc private func showHelp() {
        UserDefaults.standard.set(true, forKey: "helpOpened")
        helpItem?.subtitle = nil
        NSApp.activate()
        NSApp.showHelp(nil)
    }

    /// Help page "Making a template" (anchor `templates`, see Resources/Help).
    @objc private func showTemplateHelp() { Self.openHelp(anchor: "templates") }

    /// Archief › Druk af… (⌘P): the open recording in the window prints its transcript.
    @objc private func printTranscript() {
        NotificationCenter.default.post(name: .bandjePrint, object: nil)
    }

    /// Samenvatten › Nieuw template: a new file in the templates folder with two headings to
    /// change, opened in the app for .md files.
    @objc private func newTemplate() {
        if !ICloudSync.isActive || LibraryWatcher.shared.gathered { Summaries.seedIfMissing() }
        let language = TranscriptWriter.appLocale.language.languageCode?.identifier ?? "nl"
        Task {
            do {
                let url = try await Task.detached { try Summaries.newTemplate(language: language) }.value
                await Activity.shared.reloadTemplates()
                if !NSWorkspace.shared.open(url) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                showAlert(tr("templates.newFailed", "Template niet gemaakt"), error.localizedDescription)
            }
        }
    }

    /// Help on the page with `anchor` (`{#anchor}` in Resources/Help/<lang>.md).
    static func openHelp(anchor: String) {
        NSApp.activate()
        guard let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String else {
            NSApp.showHelp(nil)
            return
        }
        NSHelpManager.shared.openHelpAnchor(anchor, inBook: book)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// ⌘Q, Stop Band·je or a logout while recording: ask first (a recording must never get lost);
    /// while one is being saved, wait for it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch LaunchPolicy.quit(recording: recorder != nil, finishing: finishing) {
        case .now:
            return .terminateNow
        case .waitForSave:
            quitWhenSaved()
            return .terminateLater
        case .ask:
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = tr("quit.recording.title", "Band·je neemt op")
            alert.informativeText = tr("quit.recording.text", "Stop je Band·je nu, dan stopt ook de opname. Band·je bewaart hem eerst en stopt daarna.")
            alert.addButton(withTitle: tr("quit.recording.stop", "Stop opname en Band·je"))
            alert.addButton(withTitle: tr("button.cancel", "Annuleer"))
            guard alert.runModal() == .alertFirstButtonReturn, let rec = recorder else { return .terminateCancel }
            stopRecording(rec)
            quitWhenSaved()
            return .terminateLater
        }
    }

    /// Quits once the recording is converted and in its place.
    private func quitWhenSaved() {
        Task {
            while finishing > 0 { try? await Task.sleep(for: .milliseconds(200)) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    @objc private func showAbout() {
        AboutWindow.show()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common) // keeps ticking while the menu is open
        timer = t
    }

    /// Every second while recording: elapsed time, and stop (keeping the recording) on a write
    /// error, a full disk or after `AutoStop.maxDuration`.
    private func tick() {
        if let rec = recorder {
            let elapsed = rec.startDate.map { Date().timeIntervalSince($0) } ?? 0
            if let stop = AutoStop.check(writeError: rec.writeError, freeBytes: recordingFreeBytes, elapsed: elapsed) {
                stopRecording(rec)
                showAlert(tr("record.stopped", "Opname gestopt"), stop.message)
                return
            }
            checkDiskSpace(rec)
        }
        if let rec = recorder, let start = rec.startDate {
            checkMicrophone(rec, elapsed: Date().timeIntervalSince(start))
            recheckSystemAudioIfSilent(rec)
        }
        updateMenu()
    }

    /// Every `DiskSpace.checkInterval`: the free space on the recording's disk, measured off the main
    /// thread (on a nearly full disk macOS can take a while to answer). The next tick acts on it.
    private func checkDiskSpace(_ rec: Recorder) {
        guard !diskChecking, Date().timeIntervalSince(diskCheckedAt) >= DiskSpace.checkInterval else { return }
        diskChecking = true
        let folder = rec.url.deletingLastPathComponent()
        Task {
            let free = await Task.detached(priority: .utility) { Recorder.freeBytes(for: folder) }.value
            diskChecking = false
            diskCheckedAt = Date()
            guard recorder === rec else { return }
            recordingFreeBytes = free
        }
    }

    @objc private func openFolder() {
        let dir = OutputLocation.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !NSWorkspace.shared.open(dir) {
            showAlert(tr("folder.notOpened", "Map niet geopend"), tr("folder.notOpened.text", "Kan %@ niet openen.", dir.path))
        }
    }

    private func updateMenu() {
        // The window reads the same state.
        let window = Activity.shared
        window.isRecording = recorder != nil
        window.recordingTitle = recorder?.url.deletingLastPathComponent().lastPathComponent
        window.recordingStarted = recorder?.startDate
        window.transcribing = transcribing
        window.transcriptionStatus = transcriptionStatus
        window.transcriptionHint = transcriptionHint
        window.transcriptionFraction = transcriptionFraction
        window.summaryFraction = summarizing && summaryPercent >= 0 ? Double(summaryPercent) / 100 : nil
        window.summarizing = summarizingJSON
        window.summaryStatus = summaryStatusItem?.title ?? ""
        window.summariesAvailable = Self.summariesAvailable
        guard statusItem != nil else { return }
        let recording = recorder != nil
        recordItem.title = recording ? tr("menu.record.stop", "Stop opname") : tr("menu.record.start", "Start opname")
        elapsedItem.isHidden = !recording
        markItem.isHidden = !recording
        if let start = recorder?.startDate {
            elapsedItem.title = OutputLocation.elapsedString(Date().timeIntervalSince(start))
        }
        // A gentle warning while recording on a disk that is getting full (`DiskSpace.warningLevel`).
        let diskLow = recording && Recorder.diskLevel(recordingFreeBytes, floor: Recorder.minFreeBytesWhileRecording) == .low
        elapsedItem.subtitle = diskLow ? tr("record.diskLow", "Schijf bijna vol: de opname stopt vanzelf bij minder dan 1 GB vrij.") : nil
        if let name = currentRecordingName,
           let file = currentTranscript ?? lastRecording {
            let folder = file.deletingLastPathComponent()
            let latest = latestRecordingFolder == folder.standardizedFileURL
            currentItem.title = Self.menuHeader(title: name, date: OutputLocation.recordingDate(folder.appendingPathComponent("\(folder.lastPathComponent).json")),
                                                latest: latest)
        } else {
            currentItem.title = tr("menu.current.none", "Nog geen opname")
        }
        transcribeItem.isHidden = transcribing == nil
        transcribeItem.title = transcriptionStatus
        transcribeItem.subtitle = transcriptionHint
        summaryStatusItem.isHidden = !summarizing
        summarizeItem.isHidden = !Self.summariesAvailable
        Self.summariesMenuItem?.isHidden = !Self.summariesAvailable
        openPlayerItem.isEnabled = currentTranscript != nil
        shareItem.isEnabled = currentTranscript != nil
        micItem.subtitle = Recorder.deviceName(Recorder.inputDevice())
        outputItem.subtitle = Recorder.deviceName(Recorder.outputDevice())
        #if DEBUG
        if let names = Self.snapshotDevices { (micItem.subtitle, outputItem.subtitle) = names }
        #endif
        dictateItem.title = dictation != nil ? tr("menu.dictate.stop", "Stop dicteren") : (dictationBusy ? tr("menu.dictate.busy", "Tekst herkennen…") : tr("menu.dictate.start", "Start dicteren"))
        dictateItem.isEnabled = !dictationBusy
        (recordItem.keyEquivalent, recordItem.keyEquivalentModifierMask) = Shortcut.record.menuKey
        (dictateItem.keyEquivalent, dictateItem.keyEquivalentModifierMask) = Shortcut.dictate.menuKey
        (markItem.keyEquivalent, markItem.keyEquivalentModifierMask) = Shortcut.mark.menuKey
        if let (fileRecord, fileDictate) = Self.fileMenuItems {
            fileRecord.title = recordItem.title
            (fileRecord.keyEquivalent, fileRecord.keyEquivalentModifierMask) = Shortcut.record.menuKey
            fileDictate.title = dictateItem.title
            fileDictate.isEnabled = dictateItem.isEnabled
            (fileDictate.keyEquivalent, fileDictate.keyEquivalentModifierMask) = Shortcut.dictate.menuKey
        }
        updateReelAnimation(recording)
        updateClock()
        doneItem.isHidden = done == nil
        doneItem.title = done.map { "✓ " + $0.title } ?? ""
        let showDone = done != nil
        statusItem.button?.image = icon(recording: recording, transcribing: transcribing != nil || dictationBusy,
                                        summarizing: summarizing, dictating: dictation != nil, done: showDone)
        // Hover on the menu bar icon: what Bandje is doing, with progress.
        var activity: [String] = []
        if recording { activity.append(tr("a11y.recording", "Band·je neemt op") + " · " + elapsedItem.title) }
        if transcribing != nil { activity += [transcriptionStatus] + [transcriptionHint].compactMap { $0 } }
        if summarizing { activity.append(summaryStatusItem.title) }
        statusItem.button?.toolTip = activity.isEmpty ? "Bandje" : activity.joined(separator: "\n")
    }

    /// Menu bar cassette, 22×16 pt. Template (follows the menu bar) unless `color` is given;
    /// `angle` turns the reel spokes.
    static func cassette(angle: CGFloat, color: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            (color ?? .black).set()
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.2, width: 20, height: 13.6), xRadius: 2.6, yRadius: 2.6)
            body.lineWidth = 1.4
            body.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 5.5, y: 1.2))
            head.line(to: NSPoint(x: 7, y: 4.2))
            head.line(to: NSPoint(x: 15, y: 4.2))
            head.line(to: NSPoint(x: 16.5, y: 1.2))
            head.lineWidth = 1.1
            head.stroke()
            for x in [7.0, 15.0] {
                let c = NSPoint(x: x, y: 9.4)
                let reel = NSBezierPath(ovalIn: NSRect(x: c.x - 2.7, y: c.y - 2.7, width: 5.4, height: 5.4))
                reel.lineWidth = 1.2
                reel.stroke()
                let spokes = NSBezierPath()
                spokes.lineWidth = 1.1
                for i in 0..<3 {
                    let a = angle + CGFloat(i) * 2 * .pi / 3
                    spokes.move(to: c)
                    spokes.line(to: NSPoint(x: c.x + cos(a) * 2.7, y: c.y + sin(a) * 2.7))
                }
                spokes.stroke()
            }
            return true
        }
        image.isTemplate = color == nil
        return image
    }

    /// The cassette with a small green check mark badge at the top right. The image is 3 pt wider than
    /// the cassette so the badge sticks out like a notification badge. Not a template image (the badge
    /// stays green), so the cassette is drawn in `labelColor`, which follows the menu bar's appearance.
    static func doneIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 25, height: 16), flipped: false) { _ in
            cassette(angle: .pi / 2, color: .labelColor).draw(in: NSRect(x: 0, y: 0, width: 22, height: 16))
            let badge = NSRect(x: 16, y: 7, width: 9, height: 9)
            // A clear ring around the badge, so it reads as a separate dot on top of the cassette.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badge.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: badge).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: badge.minX + 2.3, y: badge.midY + 0.1))
            check.line(to: NSPoint(x: badge.minX + 3.9, y: badge.minY + 2.5))
            check.line(to: NSPoint(x: badge.maxX - 2.2, y: badge.maxY - 2.6))
            check.lineWidth = 1.4
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = tr("a11y.done", "Band·je is klaar")
        return image
    }

    /// While recording the reels turn (10 frames per second); stops with the recording.
    private func updateReelAnimation(_ recording: Bool) {
        if recording, reelTimer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reelAngle -= .pi / 15
                    if self.dictation == nil { self.statusItem.button?.image = Self.recordingIcon(self.reelAngle) }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            reelTimer = t
        } else if !recording {
            reelTimer?.invalidate()
            reelTimer = nil
        }
    }

    /// Elapsed time next to the menu bar icon: red while recording, orange while dictating (the
    /// dictation's clock blinks in its last 30 seconds). Digits of equal width, so the menu bar
    /// doesn't shift every second.
    private func updateClock() {
        guard let button = statusItem?.button else { return }
        let clock = Self.clock(recording: recorder?.startDate, dictating: dictation != nil ? dictationStart : nil, now: Date())
        let (text, color) = clock ?? ("", .clear)
        let running = clock != nil
        if running, clockTimer == nil {
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClock() }
            }
            RunLoop.main.add(t, forMode: .common)
            clockTimer = t
        } else if !running {
            clockTimer?.invalidate()
            clockTimer = nil
        }
        guard running else {
            if let until = pasteHintUntil, until > Date() {
                button.title = " ⌘V"
                button.imagePosition = .imageLeading
            } else {
                pasteHintUntil = nil
                if !button.title.isEmpty { button.title = "" }
                button.imagePosition = .imageOnly
            }
            return
        }
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
        ])
        button.imagePosition = .imageLeading
    }

    /// After a dictation that wasn't pasted (automatic pasting off, or secure input): "⌘V" next to
    /// the cassette for 3 seconds, so the user knows the text waits on the clipboard (owner,
    /// 2026-11-17). No focus taken, nothing asked. A recording's or dictation's clock wins.
    private func showPasteHint() {
        let until = Date().addingTimeInterval(3)
        pasteHintUntil = until
        updateClock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { [weak self] in
            guard let self, self.pasteHintUntil == until else { return }
            self.updateClock()
        }
    }

    /// A space after the dictated text, so the next dictation (or typing) doesn't stick to it
    /// ("ok.Next" becomes "ok. Next"). Not after a line break.
    static func withTrailingSpace(_ text: String) -> String {
        guard let last = text.last, !last.isWhitespace else { return text }
        return text + " "
    }

    private func announceDone(_ title: String, json: URL) {
        done = (title, json)
        updateMenu()
    }

    /// The menu line "Transcript klaar: …": opens that recording's page.
    @objc private func openDone() {
        guard let json = done?.json else { return }
        MainWindow.show(select: json)
    }

    /// The menu was seen: the "klaar" line has done its job.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem?.menu, done != nil else { return }
        done = nil
        updateMenu()
    }

    /// Text and color of the menu bar clock, nil when Bandje neither records nor dictates.
    /// Dictation wins (its icon is shown too); in its last 30 seconds every other half second is clear.
    static func clock(recording: Date?, dictating: Date?, now: Date) -> (String, NSColor)? {
        if let start = dictating {
            let elapsed = now.timeIntervalSince(start)
            let blinkOff = elapsed >= DictationCapture.maxSeconds - 30 && Int(now.timeIntervalSince1970 * 2) % 2 == 1
            return (OutputLocation.elapsedString(elapsed), blinkOff ? .clear : .systemOrange)
        }
        if let start = recording {
            return (OutputLocation.elapsedString(now.timeIntervalSince(start)), .systemRed)
        }
        return nil
    }

    private static func recordingIcon(_ angle: CGFloat) -> NSImage {
        let image = cassette(angle: angle, color: .systemRed)
        image.accessibilityDescription = tr("a11y.recording", "Band·je neemt op")
        return image
    }

    private func icon(recording: Bool, transcribing: Bool, summarizing: Bool, dictating: Bool, done: Bool) -> NSImage? {
        if dictating {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: tr("a11y.listening", "Band·je luistert"))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
            image?.isTemplate = false
            return image
        }
        if recording { return Self.recordingIcon(reelAngle) }
        if done, !summarizing, !transcribing {
            // Finished: the cassette with a green check mark badge, until the menu has been opened.
            return Self.doneIcon()
        }
        if summarizing {
            // Apple Intelligence works: sparkles in purple, like the orange waveform for dictation.
            let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: tr("a11y.summarizing", "Band·je vat samen"))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemPurple]))
            image?.isTemplate = false
            return image
        }
        if transcribing {
            return NSImage(systemSymbolName: "text.bubble", accessibilityDescription: tr("a11y.transcribing", "Band·je transcribeert"))
        }
        let image = Self.cassette(angle: .pi / 2, color: nil)
        image.accessibilityDescription = "Bandje"
        return image
    }

    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
