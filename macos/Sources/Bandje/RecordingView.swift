import AppKit
import PDFKit
import StoreKit
import SwiftUI

// The open recording in the Bandje window, ported from the iPhone's RecordingView, TranscriptBody,
// TurnView, TranscriptSearchBar, SummaryBody and SpeakerNamingSheet (bandje-ios), adapted to the
// Mac: jobs run in BandjeApp (Activity), summaries per template, sharing via the share sheet.

struct RecordingView: View {
    let recording: Recording
    @Binding var nameSpeakers: Bool
    @Binding var openTab: String?
    let onMoved: (URL) -> Void
    let onDeleted: () -> Void
    @Environment(AudioPlayer.self) private var player
    @Environment(Activity.self) private var activity
    @Environment(Library.self) private var library
    @Environment(\.requestReview) private var requestReview
    @State private var loaded: Loaded?
    @State private var summaries: [WebExport.Summary] = []
    @State private var tab = "transcript"
    @State private var searching = false
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var naming = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var error: String?
    @State private var deletedElsewhere = false
    @State private var presenter: FolderPresenter?
    @State private var exporting = false

    struct Loaded: Equatable {
        let json: URL
        let transcript: Transcript
        let turns: [TranscriptTurn]
        static func == (a: Loaded, b: Loaded) -> Bool { a.json == b.json && a.turns == b.turns && a.transcript.speakerNames == b.transcript.speakerNames }
    }

    private var isCurrent: Bool { player.url != nil && player.url == recording.audio }
    private var position: TimeInterval { isCurrent ? player.time : 0 }
    private var duration: TimeInterval { isCurrent && player.duration > 0 ? player.duration : recording.duration }
    private var isTranscribing: Bool { activity.transcribing?.deletingLastPathComponent() == recording.folder }
    private var isSummarizing: Bool { activity.summarizing?.deletingLastPathComponent() == recording.folder }
    private var isDownloading: Bool { recording.audio.map { activity.downloading.contains($0) } ?? false }
    /// A job writes into this folder: no rename, delete or new names then.
    private var isBusy: Bool { library.isBusy(recording.folder) || isTranscribing || isSummarizing }

    var body: some View {
        VStack(spacing: 14) {
            header
            CassetteView(state: cassette, onTapLabel: isBusy ? nil : { startRename() })
                // From the recording itself, not from loading its transcript: opening a recording
                // drew the cassette large and then shrank it once the transcript was read (a jump).
                .frame(maxWidth: recording.transcript == nil && !isTranscribing ? 300 : 200)
                .animation(.easeInOut(duration: 0.25), value: recording.transcript == nil)
            playerControls
            if isDownloading {
                ProgressView(tr("window.downloading", "Ophalen uit iCloud…")).controlSize(.small)
            }
            if exporting {
                ProgressView(tr("export.busy", "Webpagina maken…")).controlSize(.small)
            }
            if deletedElsewhere {
                Text(tr("window.deleted", "Deze opname is verwijderd.")).foregroundStyle(.secondary)
            }
            content.frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 12)
        .toolbar { toolbar }
        // ⌘F: the search bar right above the transcript (the sidebar's field searches all recordings).
        .background {
            Button("") {
                guard loaded != nil else { return }
                tab = "transcript"
                searching = true
            }
            .keyboardShortcut("f")
            .opacity(0)
            .accessibilityHidden(true)
        }
        .task(id: recording.transcript) {
            // As the menu bar's Samenvatten: the Templates folder (and examples added later) first.
            if !ICloudSync.isActive || LibraryWatcher.shared.gathered { Summaries.seedIfMissing() }
            await reload()
            await activity.reloadTemplates()
            if let t = openTab, summaries.contains(where: { $0.name == t }) { tab = t; openTab = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeLibraryChanged)) { _ in
            Task {
                await reload()
                await activity.reloadTemplates()
            }
        }
        .onAppear {
            let p = FolderPresenter(folder: recording.folder)
            p.onMove = { folder in
                // Renamed elsewhere (Finder, the iPhone): the player keeps playing from the new place.
                if isCurrent, let name = player.url?.lastPathComponent {
                    let old = recording.folder.lastPathComponent
                    player.renamed(to: folder.appendingPathComponent(name.hasPrefix(old) ? folder.lastPathComponent + name.dropFirst(old.count) : name))
                }
                onMoved(folder)
            }
            p.onChange = { Task { await reload() } }
            p.onDelete = {
                // Deleted elsewhere: say so here; the library drops it on its next refresh.
                if isCurrent { player.unload() }
                deletedElsewhere = true
            }
            presenter = p
        }
        .onDisappear { presenter?.stop(); presenter = nil }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeTogglePlay)) { _ in withPlayer { player.toggle() } }
        .onReceive(NotificationCenter.default.publisher(for: .bandjePrint)) { _ in
            if let loaded { printTranscript(loaded.transcript) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeRename)) { _ in if !isBusy { startRename() } }
        .onChange(of: nameSpeakers, initial: true) { _, on in
            guard on else { return }
            nameSpeakers = false
            if recording.transcript != nil { naming = true }
        }
        .sheet(isPresented: $naming) {
            if let loaded, let audio = recording.audio {
                SpeakerNamingSheet(transcript: loaded.transcript, json: loaded.json, audio: audio) { await reload() }
            }
        }
        .sheet(isPresented: $renaming) {
            RenameSheet(recording: recording) { title, color in rename(to: title, color: color) }
        }
        .confirmationDialog(tr("window.delete.title", "%@ verwijderen?", recording.title), isPresented: $deleting) {
            Button(tr("window.delete.ok", "Zet in prullenmand"), role: .destructive) {
                Task {
                    do {
                        if isCurrent { player.unload() }
                        try await library.delete(recording)
                        onDeleted()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(ICloudSync.isActive ? tr("window.delete.icloud", "De opname gaat naar de prullenmand, ook op je andere apparaten.")
                                     : tr("window.delete.text", "De opname met transcript en samenvattingen gaat naar de prullenmand."))
        }
        .alert(tr("window.error", "Er ging iets mis"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 2) {
            Text(recording.title).font(.title3.weight(.semibold)).lineLimit(2)
                .onTapGesture(count: 2) { if !isBusy { startRename() } }
                .help(tr("window.rename.doubleClick", "Dubbelklik om de naam en kleur te wijzigen"))
            Text(recording.date.formatted(Date.FormatStyle.dateTime.weekday(.wide).day().month().year().hour().minute()
                .locale(TranscriptWriter.appLocale)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }

    private var playerControls: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Scrubber(position: position, duration: duration, markers: recording.markers) { time in withPlayer { player.seek(time) } }
                    .frame(height: 20)
                HStack {
                    Text(clock(position))
                    Spacer()
                    Text("-\(clock(max(0, duration - position)))")
                }
                .overlay { speedMenu }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 28) {
                Button { withPlayer { player.skip(-AudioPlayer.skipInterval) } } label: {
                    Image(systemName: "gobackward.15").font(.title2)
                }
                .accessibilityLabel(Text(tr("window.back15", "15 seconden terug")))
                Button { withPlayer { player.toggle() } } label: {
                    // Filled in band.je's button colour, so the main button looks like one.
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brandInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.brand))
                }
                .accessibilityLabel(Text(isCurrent && player.isPlaying ? tr("window.pause", "Pauze") : tr("window.play", "Speel af")))
                Button { withPlayer { player.skip(AudioPlayer.skipInterval) } } label: {
                    Image(systemName: "goforward.15").font(.title2)
                }
                .accessibilityLabel(Text(tr("window.forward15", "15 seconden vooruit")))
            }
            .buttonStyle(.borderless)
            .disabled(recording.audio == nil || activity.isRecording)
        }
        // The window's navy tint is for selections; the transport stays in the text colour.
        .tint(.primary)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(AudioPlayer.rates, id: \.self) { rate in
                Button(rateLabel(rate)) { player.setRate(rate) }
            }
        } label: {
            Text(rateLabel(player.rate)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder private var content: some View {
        if isTranscribing {
            VStack(spacing: 8) {
                ProgressView(value: activity.transcriptionFraction ?? 0).tint(Color.accent).frame(maxWidth: 320)
                Text(activity.transcriptionStatus).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.top, 24)
        } else if let loaded {
            VStack(spacing: 0) {
                // Tabs only (Transcript | Samenvatting); summarizing is an action inside the summary tab.
                if !summaries.isEmpty || activity.summariesAvailable {
                    Picker("", selection: $tab) {
                        Text(tr("window.transcript", "Transcript")).tag("transcript")
                        if summaries.isEmpty {
                            Text(tr("summary.tab", "Samenvatting")).tag(Self.emptySummaryTab)
                        }
                        ForEach(summaries, id: \.name) { Text(WebExport.tabTitle($0.name, count: summaries.count)).tag($0.name) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.bottom, 8)
                }
                if isSummarizing {
                    VStack(spacing: 8) {
                        ProgressView(value: activity.summaryFraction ?? 0).tint(Color.accent).frame(maxWidth: 320)
                        Text(activity.summaryStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                } else if let summary = summaries.first(where: { $0.name == tab }) {
                    Divider()
                    if activity.summariesAvailable {
                        HStack {
                            Spacer()
                            summarizeMenu(tr("window.summarize.another", "Nog een samenvatting"), prominent: false)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    SummaryBody(blocks: SummaryBlock.parse(summary.markdown))
                } else if tab == Self.emptySummaryTab {
                    Divider()
                    VStack(spacing: 10) {
                        summarizeMenu(tr("window.summarize", "Vat samen"), prominent: true)
                        Text(tr("window.summarize.hint", "Kies een template. De samenvatting wordt op deze Mac gemaakt met Apple Intelligence."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                } else {
                    if searching {
                        TranscriptSearchBar(query: $query, matchIndex: $matchIndex,
                                            count: TranscriptBody.matches(in: loaded.turns, query: query).count) {
                            searching = false
                            query = ""
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    Divider()
                    TranscriptBody(transcript: loaded.transcript, turns: loaded.turns, position: position,
                                   following: isCurrent && player.isPlaying, query: searching ? query : "",
                                   matchIndex: matchIndex) { time in withPlayer { player.seek(time); player.play() } }
                }
            }
        } else if recording.transcript != nil {
            ProgressView().padding(.top, 24)
        } else if let audio = recording.audio {
            VStack(spacing: 10) {
                Button {
                    activity.transcribe(audio)
                } label: {
                    Label(tr("window.transcribe", "Transcribeer"), systemImage: "text.quote").frame(minWidth: 140)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(activity.transcribing != nil || isDownloading)
                Text(tr("window.transcribe.hint", "De taal wordt vanzelf herkend. Alles gebeurt op deze Mac."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
        }
    }

    /// The tab shown before there is a summary: it holds the Vat samen button.
    static let emptySummaryTab = "\u{1}summary"

    @ViewBuilder private func summarizeMenu(_ title: String, prominent: Bool) -> some View {
        let menu = Menu {
            ForEach(activity.templateNames, id: \.self) { name in
                Button(name) {
                    guard let json = recording.transcript else { return }
                    tab = name
                    activity.summarize(json, name)
                }
            }
            // As in the menu bar's Samenvatten: the templates themselves, and how to make one.
            Divider()
            Button(tr("menu.summarize.folder", "Open templatemap")) { activity.openTemplates() }
            Button(tr("menu.summarize.howTo", "Hoe maak ik een template?")) { BandjeApp.openHelp(anchor: "templates") }
        } label: {
            Label(title, systemImage: "sparkles")
        }
        .fixedSize()
        .disabled(activity.summarizing != nil)
        if prominent { menu.menuStyle(.button).buttonStyle(.borderedProminent).controlSize(.large) } else { menu }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                if let audio = recording.audio {
                    Button(tr("window.share.audio", "Audio…")) { share([audio], .audio) }
                }
                if let md = loaded.map({ $0.json.deletingPathExtension().appendingPathExtension("md") }) {
                    Button(tr("window.share.md", "Transcript (.md)…")) { share([md], .transcript) }
                }
                if let loaded {
                    Button(tr("window.share.pdf", "Transcript als pdf…")) { sharePDF(loaded.transcript) }
                    Button(tr("window.print", "Druk af…")) { printTranscript(loaded.transcript) }
                }
                if let json = loaded?.json {
                    Divider()
                    Button(tr("export.menu", "Webpagina met audio…")) { shareWebPage(json, compact: false) }
                    Button(tr("export.menu.compact", "Webpagina met audio, compact (voor mail)…")) { shareWebPage(json, compact: true) }
                }
            } label: {
                Label(tr("window.share", "Deel"), systemImage: "square.and.arrow.up")
            }
            // The window's navy tint is for selections: in dark it would hide these.
            .tint(.primary)
            // The window's navy is for selections; toolbar icons stay in the text colour (dark mode).
            .tint(.primary)
            Menu {
                Button(tr("window.rename.menu", "Naam en kleur…")) { startRename() }.disabled(isBusy)
                if let loaded, !loaded.transcript.speakerLabels.isEmpty, recording.audio != nil {
                    Button(tr("menu.nameSpeakers", "Benoem sprekers…")) { naming = true }.disabled(isBusy)
                }
                Button(tr("window.showInFinder", "Toon in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.audio ?? recording.folder])
                }
                Divider()
                Button(tr("window.delete", "Verwijder…"), role: .destructive) { deleting = true }.disabled(isBusy)
            } label: {
                Label(tr("window.more", "Meer"), systemImage: "ellipsis.circle")
            }
            // The window's navy tint is for selections: in dark it would hide these.
            .tint(.primary)
            // The window's navy is for selections; toolbar icons stay in the text colour (dark mode).
            .tint(.primary)
        }
    }

    // MARK: Actions

    private var cassette: CassetteState {
        CassetteState(mode: isCurrent && player.isPlaying ? .playing : .stopped, position: position, duration: duration,
                      title: recording.title, color: recording.color, lastSeek: isCurrent ? player.lastSeek : .distantPast,
                      seekForward: player.lastSeekForward)
    }

    /// Loads this recording into the player first (downloading it from iCloud when needed).
    private func withPlayer(_ action: @escaping () -> Void) {
        guard let audio = recording.audio else { return }
        Task {
            do {
                try await player.load(audio)
                action()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Looks in the folder itself: a reload started from an older copy of this view (from before the
    /// transcript existed) must not clear a transcript that is there now (it left a spinner).
    private func reload() async {
        let folder = recording.folder
        guard let json = await Task.detached(operation: { Library.transcriptFile(in: folder) }).value else {
            loaded = nil; summaries = []; return
        }
        let (t, s) = await Task.detached { (try? TranscriptWriter.read(json: json), WebExport.summaries(for: json)) }.value
        loaded = t.map { Loaded(json: json, transcript: $0, turns: TranscriptLayout.turns($0)) }
        summaries = s
        askForReviewIfDue()
    }

    private func startRename() { renaming = true }

    /// A transcript with words just opened: the moment for the App Store's review request
    /// (`ReviewPrompt`), App Store build only.
    private func askForReviewIfDue() {
        #if APPSTORE
        guard let loaded, !loaded.transcript.segments.isEmpty,
              ReviewPrompt.shouldAsk(transcripts: library.recordings.filter { $0.transcript != nil }.count,
                                     firstLaunch: ReviewPrompt.firstLaunch, now: Date(), askedVersion: ReviewPrompt.askedVersion,
                                     version: ReviewPrompt.version,
                                     busy: activity.isRecording || activity.transcribing != nil || activity.summarizing != nil)
        else { return }
        ReviewPrompt.noteAsked()
        requestReview()
        #endif
    }

    /// Save in the rename sheet: the new name when it changed, then the colour (as on the iPhone).
    private func rename(to newTitle: String, color: TapeColor) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasCurrent = isCurrent
        Task {
            do {
                var current = recording
                if !title.isEmpty, title != recording.title {
                    current = try await library.rename(recording, to: title)
                    if wasCurrent, let audio = current.audio { player.renamed(to: audio) }
                    onMoved(current.folder)
                }
                if color != recording.color { try await library.setColor(color, of: current) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// "Deel als webpagina": one self-contained page with the audio in it (WebExport).
    private func shareWebPage(_ json: URL, compact: Bool) {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let page = try await activity.whileDownloading(recording.audio) { try await WebExport.export(json: json, compact: compact) }
                share([page], .webPage)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// The transcript as a PDF named after the recording, in a temporary folder, then the share sheet.
    private func sharePDF(_ transcript: Transcript) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share/\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent("\(recording.title).pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try WebExport.pdf(transcript, cassette: WebExport.pdfCassette()).write(to: file, options: .atomic)
            share([file], .transcript)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Druk af… (⌘P): the same PDF as Deel › Transcript als pdf, in the print panel.
    private func printTranscript(_ transcript: Transcript) {
        guard let window = NSApp.keyWindow ?? MainWindow.nsWindow,
              let document = PDFDocument(data: WebExport.pdf(transcript, cassette: WebExport.pdfCassette())),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { return }
        operation.jobTitle = recording.title
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// The share sheet, with the app icon (audio: its cover) and the recording's title as its
    /// preview (not a tiny thumbnail of the file).
    private func share(_ items: [URL], _ kind: ShareText.Kind) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let anchor = NSRect(x: view.bounds.maxX - 120, y: view.bounds.maxY - 40, width: 1, height: 1)
        Task {
            do {
                let files = try await activity.whileDownloading(items.first) { try await ShareText.localCopies(items) }
                // Audio: its cover (already in the file) as the preview.
                let cover = kind == .audio ? CoverArt.existing(in: recording.folder).flatMap(NSImage.init(contentsOf:)) : nil
                ShareText.show(files, kind: kind, title: recording.title, date: recording.date, image: cover, relativeTo: anchor, of: view)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

/// Follows the open recording's folder: renamed (here or on another device), changed, deleted.
final class FolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    /// Read by the file coordinator on its own threads, changed on the main queue: behind a lock.
    private let lock = NSLock()
    private var url: URL?
    var presentedItemURL: URL? { lock.withLock { url } }
    let presentedItemOperationQueue = OperationQueue.main
    var onMove: (URL) -> Void = { _ in }
    var onChange: () -> Void = {}
    var onDelete: () -> Void = {}

    init(folder: URL) {
        url = folder
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedItemDidMove(to newURL: URL) {
        lock.withLock { url = newURL }
        onMove(newURL)
    }

    func presentedSubitemDidChange(at url: URL) { onChange() }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onDelete()
        completionHandler(nil)
    }
}

/// Position bar. Drag or click to seek.
struct Scrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    /// The flags set while recording (iPhone): a small red flag above the bar at each.
    var markers: [Double] = []
    let onSeek: (TimeInterval) -> Void
    @State private var dragging: TimeInterval?

    var body: some View {
        let shown = dragging ?? position
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: TimeInterval) in duration > 0 ? width * min(1, max(0, t / duration)) : 0 }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(Color.accent).frame(width: x(shown), height: 4)
                ForEach(markers, id: \.self) { marker in
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: 0xD2442A))
                        .offset(x: x(marker) - 1, y: -10)
                }
                Circle().fill(Color.accent).frame(width: 12, height: 12).offset(x: x(shown) - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard duration > 0, width > 0 else { return }
                    dragging = min(1, max(0, value.location.x / width)) * duration
                }
                .onEnded { _ in
                    if let dragging { onSeek(dragging) }
                    dragging = nil
                })
        }
        .accessibilityElement()
        .accessibilityLabel(Text(tr("window.position", "Positie")))
        .accessibilityValue(Text(markers.isEmpty ? clock(position) : clock(position) + ", " + tr("window.markers", "%@ markeringen", "\(markers.count)")))
        .accessibilityAdjustableAction { direction in
            onSeek(position + (direction == .increment ? AudioPlayer.skipInterval : -AudioPlayer.skipInterval))
        }
    }
}

/// The transcript: one paragraph per turn with the speaker and time. The sentence that is
/// playing is highlighted and scrolled to while playing; clicking a sentence plays from there.
struct TranscriptBody: View {
    let transcript: Transcript
    let turns: [TranscriptTurn]
    let position: TimeInterval
    let following: Bool
    let query: String
    let matchIndex: Int
    let onSeek: (TimeInterval) -> Void

    /// In-view links only (never registered with macOS): `bandje-seek:<seconds>`.
    nonisolated static let seekScheme = "bandje-seek"

    nonisolated static func matches(in turns: [TranscriptTurn], query: String) -> [(turn: Int, sentence: Int)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return turns.flatMap { turn in
            turn.sentences.indices.filter { turn.sentences[$0].text.localizedStandardContains(q) }.map { (turn.id, $0) }
        }
    }

    var body: some View {
        let active = TranscriptLayout.active(at: position, in: turns)
        let matches = Self.matches(in: turns, query: query)
        let current = matches.isEmpty ? nil : matches[min(max(0, matchIndex), matches.count - 1)]
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if turns.isEmpty {
                        Text(tr("transcript.noSpeech", "Geen spraak herkend.")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(turns) { turn in
                        TurnView(turn: turn,
                                 name: turn.speaker.isEmpty || turn.continued ? "" : transcript.name(of: turn.speaker),
                                 time: clock(turn.start),
                                 activeSentence: active?.turn == turn.id ? active?.sentence : nil,
                                 query: query,
                                 currentMatch: current?.turn == turn.id ? current?.sentence : nil)
                            .equatable()
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: active?.turn) { _, turn in
                guard following, query.isEmpty, let turn else { return }
                withAnimation(.smooth) { proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25)) }
            }
            .onChange(of: current?.turn) { _, turn in
                guard let turn else { return }
                withAnimation(.smooth) { proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25)) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.seekScheme,
                  let time = Double(url.absoluteString.dropFirst(Self.seekScheme.count + 1)) else { return .discarded }
            onSeek(time)
            return .handled
        })
    }
}

/// One speaker turn. Equatable so only the turn whose highlight changes is redrawn.
struct TurnView: View, Equatable {
    let turn: TranscriptTurn
    let name: String
    let time: String
    let activeSentence: Int?
    let query: String
    let currentMatch: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !name.isEmpty { Text(name).font(.subheadline.weight(.semibold)) }
                Text(time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(attributed)
                .tint(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Each sentence is a link to its start time (click = play from there).
    private var attributed: AttributedString {
        var text = AttributedString()
        let q = query.trimmingCharacters(in: .whitespaces)
        for (i, sentence) in turn.sentences.enumerated() {
            var part = AttributedString(sentence.text)
            part.link = URL(string: "\(TranscriptBody.seekScheme):\(sentence.start)")
            if i == currentMatch {
                part.backgroundColor = Color.yellow.opacity(0.55)
            } else if !q.isEmpty, sentence.text.localizedStandardContains(q) {
                part.backgroundColor = Color.yellow.opacity(0.22)
            } else if i == activeSentence {
                part.backgroundColor = Color.sentenceHighlight
            }
            text += part
            if i < turn.sentences.count - 1 { text += AttributedString(" ") }
        }
        return text
    }
}

struct TranscriptSearchBar: View {
    @Binding var query: String
    @Binding var matchIndex: Int
    let count: Int
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(tr("window.searchTranscript", "Zoek in transcript"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { next(1) }
            if !query.isEmpty {
                Text(count == 0 ? "0" : tr("window.search.count", "%1$@ van %2$@", "\(min(matchIndex, count - 1) + 1)", "\(count)"))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { next(-1) } label: { Image(systemName: "chevron.up") }.disabled(count < 2)
            Button { next(1) } label: { Image(systemName: "chevron.down") }.disabled(count < 2)
            Button(tr("button.done", "Klaar"), action: close).keyboardShortcut(.escape, modifiers: [])
        }
        .onChange(of: query) { _, _ in matchIndex = 0 }
        .onAppear { focused = true }
    }

    private func next(_ step: Int) {
        guard count > 0 else { return }
        matchIndex = (matchIndex + step + count) % count
    }
}

/// A summary: headings, bullets and paragraphs, selectable.
struct SummaryBody: View {
    let blocks: [SummaryBlock]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks.indices, id: \.self) { i in
                    switch blocks[i] {
                    case .heading(let text):
                        Text(Self.inline(text)).font(.headline).padding(.top, i == 0 ? 0 : 12)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "•").foregroundStyle(.tint)
                            Text(Self.inline(text))
                        }
                    case .paragraph(let text):
                        Text(Self.inline(text))
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Per speaker the longest turn as a quote and a clip (≤ 12 s), and a name field. Saving
/// rewrites the `.json` and `.md`; one name changes every label of that speaker.
/// Name and colour of a recording: the cassette as it will look, the name, and the seven colours
/// as round swatches (the iPhone's rename sheet).
struct RenameSheet: View {
    let recording: Recording
    let save: (String, TapeColor) -> Void
    @State private var title = ""
    @State private var color = TapeColor.red
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(tr("window.rename.sheet", "Naam en kleur")).font(.headline)
            CassetteView(state: CassetteState(duration: recording.duration, title: title.isEmpty ? recording.title : title, color: color))
                .frame(width: 220)
                .accessibilityHidden(true)
            TextField(tr("window.rename.field", "Naam"), text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(done)
            HStack(spacing: 10) {
                ForEach(TapeColor.allCases, id: \.self) { c in
                    Button { color = c } label: {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: c.gradient.top), Color(hex: c.gradient.bottom)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(c == color ? 0.7 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(c.name)
                    .accessibilityLabel(Text(c.name))
                    .accessibilityAddTraits(c == color ? .isSelected : [])
                }
            }
            HStack {
                Button(tr("button.cancel", "Annuleer"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("window.rename.save", "Bewaar"), action: done)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .onAppear {
            title = recording.title
            color = recording.color
        }
    }

    private func done() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        save(title, color)
        dismiss()
    }
}

struct SpeakerNamingSheet: View {
    let transcript: Transcript
    let json: URL
    let audio: URL
    let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayer.self) private var player
    @State private var rows: [Row] = []
    @State private var playing: String?
    @State private var clipStop: Task<Void, Never>?
    @State private var error: String?

    static let clipSeconds = 12.0

    struct Row: Identifiable {
        let label: String
        let quote: String
        let start: Double
        let end: Double
        var name: String
        var id: String { label }
    }

    static func rows(for transcript: Transcript) -> [Row] {
        let joined = TranscriptWriter.joinConsecutive(transcript.segments)
        return transcript.speakerLabels.map { label in
            let best = joined.filter { $0.speaker == label }.max { ($0.end - $0.start) < ($1.end - $1.start) }
            return Row(label: label, quote: best?.text ?? "", start: best?.start ?? 0, end: best?.end ?? 0,
                       name: transcript.speakerNames[label] ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("speakers.title", "Sprekers benoemen")).font(.title3.weight(.semibold))
            Text(tr("speakers.hint", "Luister naar een fragment en typ een naam. Elk label van die spreker verandert mee."))
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 12) {
                            Button { toggle(row) } label: {
                                Image(systemName: playing == row.label ? "stop.fill" : "play.fill").frame(width: 22, height: 22)
                            }
                            .accessibilityLabel(Text(tr("speakers.play", "Speel %@ af", row.label)))
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(row.label, text: $row.name, prompt: Text(row.label))
                                    .textFieldStyle(.roundedBorder)
                                Text("“\(row.quote)”").font(.footnote).italic().foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(tr("button.cancel", "Annuleer"), role: .cancel) { stopClip(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("button.save", "Bewaar"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // As high as the speakers need (about 46 pt each, measured), up to 560.
        .frame(width: 520, height: min(560, CGFloat(160 + transcript.speakerLabels.count * 46)))
        .onAppear { rows = Self.rows(for: transcript) }
        .onDisappear { stopClip() }
    }

    private func toggle(_ row: Row) {
        if playing == row.label { stopClip(); return }
        stopClip()
        playing = row.label
        Task {
            do {
                try await player.load(audio)
            } catch {
                self.error = error.localizedDescription
                playing = nil
                return
            }
            player.seek(max(0, row.start - 0.2))
            player.play()
            let length = min(row.end - row.start + 0.4, Self.clipSeconds)
            clipStop = Task {
                try? await Task.sleep(for: .seconds(length))
                guard !Task.isCancelled else { return }
                stopClip()
            }
        }
    }

    private func stopClip() {
        clipStop?.cancel()
        clipStop = nil
        if playing != nil { player.pause() }
        playing = nil
    }

    private func save() {
        stopClip()
        var updated = transcript
        var names: [String: String] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[row.label] = name }
        }
        updated.speakerNames = names
        do {
            try TranscriptWriter.rewrite(updated, json: json)
            Task { await onSave() }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
