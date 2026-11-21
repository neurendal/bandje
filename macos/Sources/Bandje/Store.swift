import AppKit
import BandjeKit
import StoreKit
import SwiftUI

// Freemium (../specs/purchase.md, owner 2026-11-11): recording is always free; transcribing is free
// for `FreeAllowance.transcriptions` recordings (5, owner 2026-11-12), dictation for 15 minutes (a
// one-time note at 10); Band·je Onbeperkt and Band·je Dicteren unlock the rest.
// The rules and StoreKit live in BandjeKit (`Purchases`); this file holds the Mac's gates and screens.
// Only the App Store build has a store. A build from source has everything unlocked and shows none
// of this, except a DEBUG build started with `-purchaseState free|used|unlimited|dictation|existing`
// (selftest, screenshots; with `free`, `-freeDictationUsed <seconds>` starts with that much dictated).

@MainActor
enum Store {
    /// The App Store build, or a DEBUG build with `-purchaseState`.
    static let isActive: Bool = {
        #if APPSTORE
        return true
        #elseif DEBUG
        return override != nil
        #else
        return false
        #endif
    }()

    /// `-purchaseState <state>` (DEBUG only; a release binary never reads it).
    static let override: Purchases.Override? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "purchaseState").flatMap(Purchases.Override.init(rawValue:))
        #else
        return nil
        #endif
    }()

    static var purchases: Purchases { Purchases.shared }

    /// At launch: transactions, what is owned, the products.
    static func start() {
        guard isActive else { return }
        purchases.start(override: override)
        #if APPSTORE
        if override == nil { Task.detached { await ProStatusExporter.shared.start() } }
        #endif
        #if DEBUG
        // `-purchaseState free -freeDictationUsed 590`: start with that many seconds of free
        // dictation used (in memory, as every override), to see the warning at 10 minutes and the
        // menu line without dictating for ten minutes. 600 or more: the warning shows at launch.
        if override == .free, let used = UserDefaults.standard.string(forKey: "freeDictationUsed").flatMap(Double.init), used > 0,
           purchases.noteDictated(used) {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showDictationWarning()
            }
        }
        #endif
    }

    /// When Band·je comes to the front (a purchase on another device, Ask to Buy approved, a refund).
    static func refresh() {
        guard isActive else { return }
        Task {
            await purchases.refresh()
            exportProStatus()
        }
    }

    /// Writes or removes the shared proof of purchase (`ProStatusExporter`), off the main thread.
    /// Not with an override (DEBUG): that owns nothing in StoreKit.
    static func exportProStatus() {
        #if APPSTORE
        guard override == nil else { return }
        Task.detached { await ProStatusExporter.shared.export() }
        #endif
    }

    // MARK: Transcribing

    /// Transcribing without limit (or no store at all).
    static var transcribesFreely: Bool { !isActive || purchases.hasUnlimited }

    /// Onbeperkt bought, or known to be an existing customer. Unlike `hasUnlimited`, an existing
    /// customer that isn't known yet counts as no: the welcome thanks only who really has it, and
    /// a new user's first launch (before `AppTransaction` is read) shows what is free.
    static var knowsUnlimited: Bool { known.unlimited }

    /// Dicteren (or Onbeperkt) known to be bought; as `knowsUnlimited`, never the benefit of the
    /// doubt while `existingCustomer` is unknown (`hasDictation` is true then).
    static var knowsDictation: Bool { known.dictation }

    private static var known: (unlimited: Bool, dictation: Bool) {
        known(override: purchases.override, ownsUnlimited: purchases.ownsUnlimited,
              ownsDictation: purchases.ownsDictation, existingCustomer: purchases.existingCustomer)
    }

    /// What is known to be bought. Only what the App Store said: an unknown `existingCustomer`
    /// (not read yet, or unreadable) unlocks everything, but must never read as "you bought X".
    nonisolated static func known(override: Purchases.Override?, ownsUnlimited: Bool, ownsDictation: Bool,
                                  existingCustomer: Bool?) -> (unlimited: Bool, dictation: Bool) {
        switch override {
        case .unlimited?, .existing?: return (true, true)
        case .dictation?: return (false, true)
        case .free?, .used?: return (false, false)
        case nil:
            let unlimited = ownsUnlimited || existingCustomer == true
            return (unlimited, unlimited || ownsDictation)
        }
    }

    /// What the welcome's Free to Start section says; nil without a store (a build from source).
    enum WelcomeFree: String { case free, dictationOwned, unlocked }
    static var welcomeFree: WelcomeFree? {
        guard isActive else { return nil }
        return welcomeFree(knowsUnlimited: knowsUnlimited, knowsDictation: knowsDictation)
    }

    nonisolated static func welcomeFree(knowsUnlimited: Bool, knowsDictation: Bool) -> WelcomeFree {
        knowsUnlimited ? .unlocked : knowsDictation ? .dictationOwned : .free
    }

    /// The recording's key for the count: its creation date in `.bandje.json`, else its name.
    /// Cached once the date is known (the window asks on every redraw); forgotten when the library
    /// changes (`forgetKeys`), since another recording can take a path after a rename or delete.
    private static var keys: [String: String] = [:]

    static func forgetKeys() { keys = [:] }

    static func key(folder: URL, name: String) -> String {
        if let known = keys[folder.path] { return known }
        let created = RecordingMeta.read(from: folder)?.created
        let key = PurchaseRules.recordingKey(created: created, folderName: name)
        if created != nil { keys[folder.path] = key }
        return key
    }

    static func key(audio: URL) -> String {
        key(folder: audio.deletingLastPathComponent(), name: audio.deletingPathExtension().lastPathComponent)
    }

    /// May this recording be transcribed: unlocked, counted before, or free ones left.
    static func mayTranscribe(audio: URL) -> Bool {
        transcribesFreely || purchases.mayTranscribe(key(audio: audio))
    }

    /// A new file (Transcribe File…): it can't have been counted.
    static var mayTranscribeNew: Bool { transcribesFreely || purchases.transcriptionsLeft > 0 }

    /// Counted before: transcribing it again is free.
    static func isCounted(folder: URL) -> Bool {
        purchases.usage.transcribed.contains(key(folder: folder, name: folder.lastPathComponent))
    }

    /// A transcription finished: the recording counts (once).
    static func noteTranscribed(json: URL) {
        guard isActive else { return }
        purchases.noteTranscribed(key(folder: json.deletingLastPathComponent(), name: json.deletingPathExtension().lastPathComponent))
    }

    // MARK: Dictation

    static var mayDictate: Bool { !isActive || purchases.mayDictate }

    /// A dictation finished. True when it took the free dictation past the warning point
    /// (`FreeAllowance.dictationWarnSeconds`, once per device): show `showDictationWarning()`
    /// after the text is pasted.
    static func noteDictated(_ seconds: Double) -> Bool {
        guard isActive else { return false }
        return purchases.noteDictated(seconds)
    }

    /// Free dictation minutes left, rounded up, while they are few (at most the minutes after the
    /// warning point) and dictation is not unlocked; nil otherwise (the menu bar's quiet line).
    static var fewDictationMinutesLeft: Int? {
        guard isActive, !purchases.hasDictation else { return nil }
        let left = purchases.dictationSecondsLeft
        guard left > 0, left <= FreeAllowance.dictationSeconds - FreeAllowance.dictationWarnSeconds else { return nil }
        return Int((left / 60).rounded(.up))
    }

    /// "Nog 5 gratis minuten dicteren" (the warning's title and the menu line).
    static func dictationMinutesLeftText(_ minutes: Int) -> String {
        tr("store.dictation.left", "Nog %@ gratis minuten dicteren", "\(minutes)")
    }

    /// Once, when the free dictation passes the warning point: how much is left and what comes
    /// after. Calm: OK is the default; See… opens the dictation paywall. Only after the text was
    /// pasted (it takes the focus).
    static func showDictationWarning() {
        guard let minutes = fewDictationMinutesLeft else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = dictationMinutesLeftText(minutes)
        alert.informativeText = tr("store.dictation.warning", "Daarna kun je verder met %1$@ of %2$@, één keer betalen.",
                                   name(.dictation), name(.unlimited))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: tr("store.dictation.warning.see", "Bekijk…"))
        if alert.runModal() == .alertSecondButtonReturn { Paywall.show(.dictation) }
    }

    // MARK: Products

    /// The product's name in the app's language (StoreKit's `displayName` follows the storefront's
    /// language, so a Dutch storefront gave Dutch names in an English app). Same names as in App Store Connect.
    static func name(_ id: BandjeProduct) -> String {
        switch id {
        case .unlimited: return tr("store.unlimited", "Band·je Onbeperkt")
        case .dictation: return tr("store.dictation", "Band·je Dicteren")
        }
    }

    /// The price from the App Store; nil while it loads (or when the App Store can't be reached).
    static func price(_ id: BandjeProduct) -> String? {
        if let product = purchases.product(id) { return product.displayPrice }
        #if DEBUG
        // Screenshots of a DEBUG build: there is no App Store product without a StoreKit
        // configuration, so show where the price goes (never in a release build).
        if override != nil, CommandLine.arguments.contains("--selftest-snapshot") {
            return Decimal(id == .unlimited ? 19.99 : 9.99).formatted(.currency(code: "EUR"))
        }
        #endif
        return nil
    }

    /// Restore Purchases (menu, paywall, Settings): asks the App Store, then says what it found.
    /// Returns true when something is unlocked now.
    @discardableResult
    static func restore(alert: Bool) async -> Bool {
        do {
            try await purchases.restore()
            exportProStatus()
        } catch {
            if alert { show(tr("store.restore.failed", "Herstellen mislukt"), error.localizedDescription) }
            return false
        }
        // Only what the App Store confirmed: "restored" never on the benefit of the doubt.
        let unlocked = knowsUnlimited || knowsDictation
        if alert {
            show(unlocked ? tr("store.restore.done", "Aankopen hersteld") : tr("store.restore.none", "Geen aankopen gevonden"),
                 unlocked ? statusLine : tr("store.restore.none.text", "Dit Apple-account heeft Band·je Onbeperkt of Band·je Dicteren niet gekocht."))
        }
        return unlocked
    }

    /// One line on what is unlocked or how much is left (Settings, after Restore).
    static var statusLine: String {
        if override == .existing || (override == nil && purchases.existingCustomer == true && !purchases.ownsUnlimited) {
            return tr("store.status.existing", "Je kocht Band·je voordat het gratis werd: alles is ontgrendeld.")
        }
        if knowsUnlimited { return tr("store.status.unlocked", "Ontgrendeld. Dank je wel!") }
        // Not known yet whether this is an existing customer: unlocked, but no purchase named.
        if purchases.hasUnlimited { return tr("store.status.unknown", "Alles is ontgrendeld.") }
        let left = purchases.transcriptionsLeft
        var line = left > 0
            ? tr("store.status.free", "Gratis: nog %1$@ van %2$@ transcripties.", "\(left)", "\(FreeAllowance.transcriptions)")
            : tr("paywall.transcribe.used", "Je %@ gratis transcripties zijn gebruikt.", "\(FreeAllowance.transcriptions)")
        let minutes = Int(FreeAllowance.dictationSeconds / 60)
        if knowsDictation {
            line += " " + tr("store.status.dictationUnlocked", "Dicteren is ontgrendeld.")
        } else if purchases.dictationSecondsLeft > 0 {
            // Rounded up: "nog 1 van 15 minuten" until the last second is used.
            line += " " + tr("store.status.dictationFree", "Dicteren: nog %1$@ van %2$@ minuten.",
                             "\(Int((purchases.dictationSecondsLeft / 60).rounded(.up)))", "\(minutes)")
        } else {
            line += " " + tr("paywall.dictation.used", "Je %@ gratis minuten dicteren zijn op.", "\(minutes)")
        }
        return line
    }

    private static func show(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}

// MARK: Paywall

/// The paywall in its own small window: as a sheet on the Band·je window when that is open (and it
/// is about transcribing), otherwise on its own in front (dictation happens in other apps).
@MainActor
enum Paywall {
    private static var window: NSWindow?
    private static var kind: PaywallView.Kind?
    /// What the user asked for, done after a purchase (the transcription starts).
    private static var actions: [() -> Void] = []

    static var isShown: Bool { window != nil }

    static func show(_ kind: PaywallView.Kind, then action: (() -> Void)? = nil) {
        guard Store.isActive else { action?(); return }
        if let window, self.kind == kind {
            if let action { actions.append(action) }
            NSApp.activate()
            (window.sheetParent ?? window).makeKeyAndOrderFront(nil)
            return
        }
        close(bought: false)
        self.kind = kind
        actions = action.map { [$0] } ?? []
        let host = NSHostingController(rootView: PaywallView(kind: kind) { bought in close(bought: bought) })
        host.sizingOptions = .preferredContentSize
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = Store.name(.unlimited)
        w.isReleasedWhenClosed = false
        window = w
        w.onClose { [weak w] in
            // The close button: as Not Now.
            guard let w, window === w else { return }
            window = nil
            self.kind = nil
            actions = []
        }
        NSApp.activate()
        if kind == .transcribe, let main = MainWindow.nsWindow, main.isVisible, !main.isMiniaturized, main.attachedSheet == nil {
            main.makeKeyAndOrderFront(nil)
            main.beginSheet(w)
        } else {
            w.center()
            w.level = .floating  // in front of the app the user dictates into
            w.makeKeyAndOrderFront(nil)
        }
    }

    static func close(bought: Bool) {
        guard let w = window else { return }
        window = nil
        kind = nil
        let done = actions
        actions = []
        if let parent = w.sheetParent { parent.endSheet(w) } else { w.close() }
        if bought { done.forEach { $0() } }
    }

    #if DEBUG
    static var nsWindow: NSWindow? { window }
    #endif
}

/// Calm and short: what it unlocks, one payment, Restore, Not Now. Prices only from StoreKit.
struct PaywallView: View {
    enum Kind { case transcribe, dictation }

    let kind: Kind
    let done: (_ bought: Bool) -> Void
    @Environment(\.purchase) private var purchase
    @State private var busy = false
    @State private var message: String?
    private var purchases: Purchases { Purchases.shared }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(kind == .transcribe ? Store.name(.unlimited) : tr("paywall.dictation.title", "Blijf dicteren"))
                    .font(.title2.weight(.semibold))
                if let reason {
                    Text(reason).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            switch kind {
            case .transcribe: transcribeBody
            case .dictation: dictationBody
            }
            if purchases.pending {
                Label(tr("paywall.pending", "Wacht op goedkeuring. Band·je gaat verder zodra de aankoop rond is."), systemImage: "clock")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(tr("store.restore", "Herstel aankopen")) { restore() }
                    .disabled(busy)
                Spacer()
                Button(tr("paywall.notNow", "Niet nu")) { done(false) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(width: kind == .transcribe ? 380 : 440)
        .task { await purchases.loadProducts() }
        // Bought on another device or approved (Ask to Buy) while this is open.
        .onChange(of: unlocked) { if unlocked { done(true) } }
    }

    /// Why this shows now: the free part is used up (nothing when opened from the menu before that).
    private var reason: String? {
        switch kind {
        case .transcribe:
            guard purchases.transcriptionsLeft == 0 else { return nil }
            return tr("paywall.transcribe.used", "Je %@ gratis transcripties zijn gebruikt.", "\(FreeAllowance.transcriptions)")
        case .dictation:
            guard purchases.dictationSecondsLeft <= 0 else { return nil }
            return tr("paywall.dictation.used", "Je %@ gratis minuten dicteren zijn op.", "\(Int(FreeAllowance.dictationSeconds / 60))")
        }
    }

    private var unlocked: Bool {
        kind == .transcribe ? purchases.hasUnlimited : purchases.hasDictation
    }

    @ViewBuilder private var transcribeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            line("infinity", tr("paywall.line.unlimited", "Transcribeer zoveel opnames als je wilt, en dicteer zonder limiet."))
            line("checkmark.seal", tr("paywall.line.once", "Eén keer betalen, geen abonnement. Alles blijft op je Mac."))
            line("recordingtape", tr("paywall.line.free", "Opnemen blijft gratis, en wat je al hebt blijft van jou."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        buyButton(.unlimited, prominent: true)
            .padding(.top, 2)
    }

    @ViewBuilder private var dictationBody: some View {
        VStack(spacing: 10) {
            offer(.dictation, tr("paywall.offer.dictation", "Dicteren zonder limiet."), prominent: false)
            offer(.unlimited, tr("paywall.offer.unlimited", "Dicteren én transcriberen zonder limiet."), prominent: true)
        }
        Text(tr("paywall.line.once", "Eén keer betalen, geen abonnement. Alles blijft op je Mac."))
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accent).frame(width: 20)
        }
    }

    private func offer(_ id: BandjeProduct, _ text: String, prominent: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Store.name(id)).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            buyButton(id, prominent: prominent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func buyButton(_ id: BandjeProduct, prominent: Bool) -> some View {
        if let price = Store.price(id) {
            let button = Button(tr("store.buyFor", "Koop voor %@", price)) { buy(id) }
                .controlSize(prominent && kind == .transcribe ? .large : .regular)
                .disabled(busy)
            if prominent {
                button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                button.buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(tr("store.loading", "Prijs laden…")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func buy(_ id: BandjeProduct) {
        guard let product = purchases.product(id) else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let result = try await purchase(product)
                let bought = await purchases.handle(result)
                Store.exportProStatus()
                if bought { done(true) }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            let found = await Store.restore(alert: false)
            if unlocked {
                done(true)
            } else if found {
                // Something was bought, but not what this paywall unlocks (Dictation, asked to transcribe).
                message = tr("store.restore.other", "%1$@ is hersteld. Onbeperkt transcriberen zit alleen in %2$@.",
                             Store.name(.dictation), Store.name(.unlimited))
            } else {
                message = tr("store.restore.none.text", "Dit Apple-account heeft Band·je Onbeperkt of Band·je Dicteren niet gekocht.")
            }
        }
    }
}

// MARK: Under the Transcribe button

/// "Nog 4 van 5 gratis transcripties", or, once they are used, the short line with Band·je
/// Onbeperkt… instead of the progress (an automatic transcription did not start).
struct FreeTranscriptionNote: View {
    let folder: URL
    private var purchases: Purchases { Purchases.shared }

    var body: some View {
        if Store.isActive, !purchases.hasUnlimited, !Store.isCounted(folder: folder) {
            if purchases.transcriptionsLeft > 0 {
                Text(tr("store.left", "Nog %1$@ van %2$@ gratis transcripties", "\(purchases.transcriptionsLeft)", "\(FreeAllowance.transcriptions)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text(tr("store.used", "%@ gratis transcripties gebruikt ·", "\(FreeAllowance.transcriptions)"))
                        .foregroundStyle(.secondary)
                    Button(Store.name(.unlimited) + "…") { Paywall.show(.transcribe) }
                        .buttonStyle(.link)
                }
                .font(.footnote)
            }
        }
    }
}

// MARK: Settings

/// Settings › Aankopen: what is unlocked, both products, Restore and Redeem Code.
struct PurchasesSettings: View {
    @Environment(\.purchase) private var purchase
    @State private var busy = false
    @State private var message: String?
    @State private var redeeming = false
    private var purchases: Purchases { Purchases.shared }

    /// Redeem Code… in the app menu opens this pane with the redeem sheet.
    static var redeemOnAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(footer: purchases.pending ? tr("paywall.pending", "Wacht op goedkeuring. Band·je gaat verder zodra de aankoop rond is.") : nil) {
                SettingsRow(label: Store.statusLine) { EmptyView() }
            }
            SettingsCard(footer: message ?? tr("store.footer", "Eén keer betalen, geen abonnement. Opnemen blijft altijd gratis, en wat je al hebt blijft van jou.")) {
                row(.unlimited, tr("paywall.offer.unlimitedLong", "Transcriberen en dicteren zonder limiet."), owned: purchases.hasUnlimited)
                Divider()
                row(.dictation, tr("paywall.offer.dictation", "Dicteren zonder limiet."), owned: purchases.hasDictation)
            }
            HStack {
                Button(tr("store.restore", "Herstel aankopen")) {
                    busy = true
                    Task { await Store.restore(alert: true); busy = false }
                }
                .disabled(busy)
                Button(tr("store.redeem", "Wissel code in…")) { redeeming = true }
                Spacer()
            }
        }
        .task { await purchases.loadProducts() }
        .onAppear(perform: redeemIfAsked)
        .onReceive(NotificationCenter.default.publisher(for: .bandjeRedeemCode)) { _ in redeemIfAsked() }
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await purchases.refreshEntitlements() }
        }
    }

    private func redeemIfAsked() {
        guard Self.redeemOnAppear else { return }
        Self.redeemOnAppear = false
        redeeming = true
    }

    private func row(_ id: BandjeProduct, _ note: String, owned: Bool) -> some View {
        SettingsRow(label: Store.name(id), note: note) {
            if owned {
                Label(tr("store.unlocked", "Ontgrendeld"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else if let price = Store.price(id) {
                Button(tr("store.buyFor", "Koop voor %@", price)) { buy(id) }
                    .disabled(busy)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func buy(_ id: BandjeProduct) {
        guard let product = purchases.product(id) else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                _ = await purchases.handle(try await purchase(product))
                Store.exportProStatus()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

extension Notification.Name {
    /// Redeem Code… in the app menu, for Settings › Aankopen.
    static let bandjeRedeemCode = Notification.Name("bandjeRedeemCode")
}
