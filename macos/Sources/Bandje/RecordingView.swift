import AppKit
import BandjeKit
import PDFKit
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

// The open recording in the Bandje window, ported from the iPhone's RecordingView, TranscriptBody,
// TurnView, TranscriptSearchBar, SummaryBody and SpeakerNamingSheet (bandje-ios), adapted to the
// Mac: jobs run in BandjeApp (Activity), summaries per template, sharing via the share sheet.

struct RecordingView: View {
    let recording: Recording
    @Binding var nameSpeakers: Bool
    @Binding var openTab: String?
    /// The list's search when the recording was opened: the transcript's search bar starts with it.
    var searchQuery = ""
    let onMoved: (URL) -> Void
    let onDeleted: () -> Void
    @Environment(PlayerModel.self) private var player
    @Environment(Activity.self) private var activity
    @Environment(Library.self) private var library
    @Environment(\.requestReview) private var requestReview
    @State private var loaded: Loaded?
    /// Why the transcript could not be read (damaged `.json`): shown instead of an endless spinner.
    @State private var loadError: String?
    /// Counts `reload()` calls, so an older one that finishes later can't overwrite a newer one.
    @State private var reloadGeneration = 0
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
    /// The folder's markers and notes (specs/markers.md); `canMark`: it has a `.bandje.json` to keep them in.
    @State private var markers = Markers()
    @State private var canMark = false
    /// The marker just removed, for "Marker verwijderd · Herstel" (a few seconds).
    @State private var removed: RemovedMarker?
    @State private var noteEditing: NoteEdit?
    /// Share › PDF, Text, Markdown or Print with summaries: the chooser (specs/share.md).
    @State private var choosing: ShareAction?
    /// The summaries as they were when the chooser opened (a reload meanwhile does not shift its checkboxes).
    @State private var choosingSummaries: [WebExport.Summary] = []
    /// What the chooser picked; done once the sheet is gone (the share sheet needs the window).
    @State private var pendingShare: (action: ShareAction, format: ShareFormat, document: ShareDocument)?

    struct RemovedMarker: Equatable {
        let id = UUID()
        let time: Double
        let note: String?
    }

    struct NoteEdit: Identifiable {
        let time: Double
        var id: Double { time }
    }

    /// What Share › … does with the document (owner, 2026-11-11): Deel als…, Kopieer als…,
    /// Bewaar als… (each asks the format first) or Afdrukken….
    enum ShareAction: String, Identifiable {
        case share, copy, save, print
        var id: String { rawValue }
        /// The formats the chooser offers (copy too: a PDF pastes into Mail, Finder, chat apps; owner 2026-11-11).
        var formats: [ShareFormat] { [.pdf, .text, .markdown] }
    }

    enum ShareFormat: String {
        case pdf, text, markdown
    }

    struct Loaded: Equatable {
        let json: URL
        let transcript: Transcript
        let turns: [TranscriptTurn]
        static func == (a: Loaded, b: Loaded) -> Bool { a.json == b.json && a.turns == b.turns && a.transcript.speakerNames == b.transcript.speakerNames }
    }

    /// This recording is the player's (specs/player.md): the controls and transcript follow it.
    private var isCurrent: Bool { player.current != nil && Playback.isCurrent(recording.folder) }
    /// The live time when current, else where it was left (P3).
    private var position: TimeInterval { player.savedPosition(for: Playback.id(of: recording)) ?? 0 }
    private var duration: TimeInterval { isCurrent && player.duration > 0 ? player.duration : recording.duration }
    private var isPlaying: Bool { isCurrent && (player.state == .playing || player.state == .loading) }
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
            if isCurrent, let failure = Playback.failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
            if isDownloading {
                ProgressView(tr("window.downloading", "Ophalen uit iCloud…")).controlSize(.small)
            }
            if exporting {
                ProgressView(tr("export.busy", "Audiopagina maken…")).controlSize(.small)
            }
            if deletedElsewhere {
                Text(tr("window.deleted", "Deze opname is verwijderd.")).foregroundStyle(.secondary)
            }
            content.frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 12)
        .toolbar { toolbar }
        // Wijzig › Zoek… (⌘F): the search bar right above the transcript (the sidebar's field searches
        // all recordings).
        .onReceive(NotificationCenter.default.publisher(for: .bandjeFind)) { _ in
            guard loaded != nil else { return }
            tab = "transcript"
            searching = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeAddMarker)) { _ in
            guard recording.audio != nil, !activity.isRecording else { return }
            addMarker()
        }
        .onAppear {
            // Opened from a search in the list: the same words in the transcript's search bar.
            let q = searchQuery.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return }
            query = q
            searching = true
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
                Playback.moved(from: recording.folder, to: folder)
                onMoved(folder)
            }
            p.onChange = { Task { await reload() } }
            p.onDelete = {
                // Deleted elsewhere: say so here; the library drops it on its next refresh (P9).
                Playback.removed(recording)
                deletedElsewhere = true
            }
            presenter = p
        }
        .onDisappear { presenter?.stop(); presenter = nil }
        .onReceive(NotificationCenter.default.publisher(for: .bandjePrint)) { _ in
            if loaded != nil { startShare(.print) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandjeRename)) { _ in if !isBusy { startRename() } }
        .onChange(of: nameSpeakers, initial: true) { _, on in
            guard on else { return }
            nameSpeakers = false
            if recording.transcript != nil { naming = true }
        }
        .sheet(isPresented: $naming) {
            if let loaded, let item = recording.playable {
                SpeakerNamingSheet(transcript: loaded.transcript, json: loaded.json, item: item, folder: recording.folder) { await reload() }
            }
        }
        .sheet(item: $choosing, onDismiss: {
            guard let pending = pendingShare else { return }
            pendingShare = nil
            // On the next turn of the run loop, when the sheet's window is gone: the share picker,
            // print panel and save panel attach to the main window, not to the closing sheet.
            DispatchQueue.main.async { perform(pending.action, pending.format, pending.document) }
        }) { action in
            ShareChooser(action: action, summaries: choosingSummaries) { format, picked, transcript in
                guard let loaded else { return }
                pendingShare = (action, format, ShareDocument(transcript: withMarkers(loaded.transcript), summaries: picked, includesTranscript: transcript))
            }
        }
        .sheet(item: $noteEditing) { edit in
            MarkerNoteSheet(time: edit.time, note: markers.note(at: edit.time)) { text in saveNote(text, at: edit.time) }
        }
        .overlay(alignment: .bottom) {
            if removed != nil {
                HStack(spacing: 10) {
                    Text(tr("marker.removed", "Marker verwijderd"))
                    Button(tr("marker.undo", "Herstel"), action: undoRemove)
                        .buttonStyle(.borderless)
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $renaming) {
            RenameSheet(recording: recording) { title, color in rename(to: title, color: color) }
        }
        .confirmationDialog(tr("window.delete.title", "%@ verwijderen?", recording.title), isPresented: $deleting) {
            Button(tr("window.delete.ok", "Zet in prullenmand"), role: .destructive) {
                Task {
                    do {
                        try await library.delete(recording)
                        Playback.removed(recording)  // P9
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
                Scrubber(position: position, duration: duration, markers: markers.times) { time in Playback.play(recording, at: time) }
                    .frame(height: 20)
                    // A marker's note while playing passes it (specs/markers.md 6), above the bar.
                    .overlay(alignment: .top) {
                        if let note = playingNote {
                            HStack(spacing: 5) {
                                Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xD2442A))
                                Text(note.text).lineLimit(1)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.quaternary))
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: -30)
                            .id(note.time)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: playingNote?.time)
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
                Button { Playback.skip(recording, by: -PlayerModel.skipInterval) } label: {
                    Image(systemName: "gobackward.15").font(.title2)
                }
                .accessibilityLabel(Text(tr("window.back15", "15 seconden terug")))
                Button { Playback.toggle(recording) } label: {
                    // Filled in band.je's button colour, so the main button looks like one.
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brandInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.brand))
                }
                .accessibilityLabel(Text(isPlaying ? tr("window.pause", "Pauze") : tr("window.play", "Speel af")))
                Button { Playback.skip(recording, by: PlayerModel.skipInterval) } label: {
                    Image(systemName: "goforward.15").font(.title2)
                }
                .accessibilityLabel(Text(tr("window.forward15", "15 seconden vooruit")))
            }
            .buttonStyle(.borderless)
            .disabled(recording.audio == nil || activity.isRecording)
            .frame(maxWidth: .infinity)
            // A marker at the current position: one click or ⌘D, no questions (specs/markers.md 4).
            .overlay(alignment: .trailing) {
                Button(action: addMarker) {
                    Image(systemName: "flag").font(.title3)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("d")
                .disabled(!canMark || deletedElsewhere)
                .help(tr("window.mark.help2", "Zet een marker op deze plek (⌘D of %@)", Shortcut.mark.display))
                .accessibilityLabel(Text(tr("window.mark", "Zet een marker")))
                .padding(.trailing, 24)
            }
        }
        // The window's navy tint is for selections; the transport stays in the text colour.
        .tint(.primary)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlayerModel.rates, id: \.self) { rate in
                Button(rateLabel(rate)) { player.rate = rate }  // P14: every recording
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
                if let hint = activity.transcriptionHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                }
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
                    HStack {
                        Spacer()
                        // The summary's body only (no heading, no metadata line), as written.
                        Button { Self.copy(summary.markdown) } label: {
                            Label(tr("window.copy", "Kopieer"), systemImage: "doc.on.doc")
                        }
                        .fixedSize()
                        if activity.summariesAvailable {
                            summarizeMenu(tr("window.summarize.another", "Nog een samenvatting"), prominent: false)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
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
                    TranscriptBody(transcript: loaded.transcript, turns: loaded.turns, position: isCurrent ? player.currentTime : 0,
                                   following: isCurrent && player.isPlaying, query: searching ? query : "",
                                   matchIndex: matchIndex, markers: markers,
                                   onEditNote: { noteEditing = NoteEdit(time: $0) }, onRemoveMarker: removeMarker,
                                   onCopyTranscript: {
                                       Self.copy(TranscriptWriter.plainText(TranscriptWriter.withFolderMarkers(loaded.transcript, json: loaded.json)))
                                   }) { time in
                        Playback.play(recording, at: time)  // P5
                    }
                }
            }
        } else if recording.transcript != nil, let loadError {
            VStack(spacing: 10) {
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let audio = recording.audio {
                    Button {
                        activity.transcribe(audio)
                    } label: {
                        Label(tr("window.transcribeAgain", "Transcribeer opnieuw"), systemImage: "text.quote").frame(minWidth: 140)
                    }
                    .controlSize(.large)
                    .disabled(activity.transcribing != nil || isDownloading)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
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
                // Freemium (App Store build): how many free ones are left, or the short line once used.
                FreeTranscriptionNote(folder: recording.folder)
                Text(tr("window.transcribe.hint", "De taal wordt vanzelf herkend. Alles gebeurt op deze Mac."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // No transcript to put them in: the markers as a list.
                if !markers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(markers.times, id: \.self) { time in
                            MarkerRow(time: time, note: markers.note(at: time),
                                      onPlay: { Playback.play(recording, at: time) },
                                      onEdit: { noteEditing = NoteEdit(time: time) },
                                      onRemove: { removeMarker(time) })
                        }
                    }
                    .padding(.top, 16)
                }
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
                // The same short menu as on the iPhone (specs/share.md); copying is in the transcript's
                // right-click menu and next to a summary.
                if let json = loaded?.json {
                    Button(tr("export.menu", "Audiopagina…")) { shareWebPage(json, compact: false) }
                    Button(tr("export.menu.compact", "Audiopagina, compact (voor mail)…")) { shareWebPage(json, compact: true) }
                    Divider()
                    // The document (summaries and transcript): the chooser asks PDF, Text or Markdown.
                    Button(tr("window.share.shareAs", "Deel als…")) { startShare(.share) }
                    Button(tr("window.share.copyAs", "Kopieer als…")) { startShare(.copy) }
                    Button(tr("window.share.saveAs", "Bewaar als…")) { startShare(.save) }
                    Button(tr("window.share.print", "Afdrukken…")) { startShare(.print) }
                }
            } label: {
                Label(tr("window.share", "Deel"), systemImage: "square.and.arrow.up")
            }
            // The window's navy tint is for selections: toolbar icons stay in the text colour (in dark mode it would hide them).
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
            // The window's navy tint is for selections: toolbar icons stay in the text colour (in dark mode it would hide them).
            .tint(.primary)
        }
    }

    // MARK: Actions

    private var cassette: CassetteState {
        CassetteState(mode: isCurrent && player.isPlaying ? .playing : .stopped, position: position, duration: duration,
                      title: recording.title, color: recording.color, lastSeek: isCurrent ? player.lastSeek : .distantPast,
                      seekForward: player.lastSeekForward)
    }

    /// Looks in the folder itself: a reload started from an older copy of this view (from before the
    /// transcript existed) must not clear a transcript that is there now (it left a spinner).
    private func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let folder = recording.folder
        let (m, meta) = await Task.detached {
            (Markers.read(from: folder), FileManager.default.fileExists(atPath: folder.appendingPathComponent(Markers.metaFileName).path))
        }.value
        guard generation == reloadGeneration else { return }  // a newer reload is on its way
        markers = m
        canMark = meta
        guard let json = await Task.detached(operation: { Library.transcriptFile(in: folder) }).value else {
            guard generation == reloadGeneration else { return }
            loaded = nil; loadError = nil; summaries = []; return
        }
        let (t, s) = await Task.detached { () -> (Result<Transcript, Error>, [WebExport.Summary]) in
            (Result { try TranscriptWriter.read(json: json) }, WebExport.summaries(for: json))
        }.value
        guard generation == reloadGeneration else { return }
        switch t {
        case .success(let transcript):
            loaded = Loaded(json: json, transcript: transcript, turns: TranscriptLayout.turns(transcript))
            loadError = nil
        case .failure(let error):
            loaded = nil
            loadError = error.localizedDescription
        }
        summaries = s
        askForReviewIfDue()
    }

    private func startRename() { renaming = true }

    // MARK: Markers (specs/markers.md)

    /// The note to show above the position bar while this recording plays near its marker.
    private var playingNote: (time: Double, text: String)? {
        guard isCurrent, player.isPlaying else { return nil }
        return markers.noteNear(player.currentTime)
    }

    /// The flag button, ⌘D and the Mark This Moment shortcut: a marker where the player is (or was left) in this recording.
    private func addMarker() {
        guard canMark, !deletedElsewhere else { return }
        let time = position, limit = duration > 0 ? duration : nil
        Task { await changeMarkers { $0.add(at: time, duration: limit) } }
    }

    private func removeMarker(_ time: Double) {
        let note = markers.note(at: time)
        Task {
            guard await changeMarkers({ $0.remove(at: time) }) != nil else { return }
            let gone = RemovedMarker(time: time, note: note)
            withAnimation(.easeInOut(duration: 0.2)) { removed = gone }
            try? await Task.sleep(for: .seconds(5))
            if removed == gone { withAnimation(.easeInOut(duration: 0.2)) { removed = nil } }
        }
    }

    /// Herstel: the removed marker back, with its note (unless another marker is that close now).
    private func undoRemove() {
        guard let gone = removed else { return }
        withAnimation(.easeInOut(duration: 0.2)) { removed = nil }
        Task {
            await changeMarkers { m in
                let t = m.add(at: gone.time)
                if let note = gone.note, abs(t - gone.time) < 0.05 { m.setNote(note, at: t) }
            }
        }
    }

    /// Empty: the note goes, the marker stays.
    private func saveNote(_ text: String, at time: Double) {
        Task { await changeMarkers { $0.setNote(text, at: time) } }
    }

    /// Changes the folder's markers (`MarkerFile`), then the transcript's copy in its `.json` and
    /// `.md`, as naming speakers does; not while a job writes that transcript (exports read the
    /// folder's markers anyway). Nil when writing failed (said in an alert).
    @discardableResult
    private func changeMarkers(_ body: @escaping @Sendable (inout Markers) -> Void) async -> Markers? {
        let folder = recording.folder
        let json = isBusy ? nil : loaded?.json
        do {
            let changed = try await MarkerFile.change(in: folder, body)
            markers = changed
            if let json { try await Task.detached { try Self.rewriteTranscript(json, markers: changed) }.value }
            return changed
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    nonisolated static func rewriteTranscript(_ json: URL, markers: Markers) throws {
        var t = try TranscriptWriter.read(json: json)
        guard TranscriptWriter.markers(of: t) != markers else { return }
        TranscriptWriter.apply(markers, to: &t)
        try TranscriptWriter.rewrite(t, json: json)
    }

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
        Task {
            do {
                var current = recording
                if !title.isEmpty, title != recording.title {
                    current = try await library.rename(recording, to: title)
                    Playback.moved(from: recording.folder, to: current.folder)
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

    /// Share › Deel als…, Kopieer als…, Bewaar als… (the chooser: format, and with summaries what
    /// goes in) and Afdrukken… / ⌘P (the chooser only with summaries, else straight to print).
    private func startShare(_ action: ShareAction) {
        // ⌘P while the chooser is open: it stays as it is.
        guard let loaded, choosing == nil else { return }
        if action == .print, summaries.isEmpty {
            perform(.print, .pdf, ShareDocument(transcript: withMarkers(loaded.transcript)))
        } else {
            choosingSummaries = summaries
            choosing = action
        }
    }

    private func perform(_ action: ShareAction, _ format: ShareFormat, _ document: ShareDocument) {
        switch (action, format) {
        case (.print, _): printDocument(document)
        case (.copy, .markdown): Self.copy(document.markdown())
        case (.copy, .text): Self.copy(document.plainText())
        case (.copy, .pdf): copyPDF(document.pdf(cassette: WebExport.pdfCassette()))
        case (.share, .pdf): shareFile(document.pdf(cassette: WebExport.pdfCassette()), extension: "pdf", document.kind)
        case (.share, .text): shareFile(Data(document.plainText().utf8), extension: "txt", document.kind)
        case (.share, .markdown): shareFile(Data(document.markdown().utf8), extension: "md", document.kind)
        case (.save, .pdf): saveFile(document.pdf(cassette: WebExport.pdfCassette()), extension: "pdf", type: .pdf)
        case (.save, .text): saveFile(Data(document.plainText().utf8), extension: "txt", type: .plainText)
        case (.save, .markdown): saveFile(Data(document.markdown().utf8), extension: "md",
                                          type: UTType(filenameExtension: "md") ?? .plainText)
        }
    }

    /// The window the share picker, print panel and save panel belong to: the main window (not the
    /// chooser sheet, which may still be key while it closes).
    private var hostWindow: NSWindow? {
        MainWindow.nsWindow.flatMap { $0.isVisible ? $0 : nil } ?? NSApp.keyWindow
    }

    /// Kopieer als › PDF: the PDF on the clipboard both as a file named after the recording (Finder,
    /// Mail, chat apps take it as an attachment) and as PDF data (Preview, Pages, Notes).
    private func copyPDF(_ data: Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share/\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent(recording.title).appendingPathExtension("pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setData(data, forType: .pdf)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// Bewaar als… (PDF, Tekst, Markdown): the save panel, named after the recording.
    private func saveFile(_ data: Data, extension ext: String, type: UTType) {
        guard let window = hostWindow else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(recording.title).\(ext)"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// The document as a file named after the recording, in a temporary folder, then the share sheet.
    private func shareFile(_ data: Data, extension ext: String, _ kind: ShareText.Kind) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share/\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent(recording.title).appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            share([file], kind)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The transcript with the folder's markers as they are now (another device may have changed them).
    private func withMarkers(_ transcript: Transcript) -> Transcript {
        guard let json = loaded?.json else { return transcript }
        return TranscriptWriter.withFolderMarkers(transcript, json: json)
    }

    /// Afdrukken… (⌘P): the same PDF as Deel › PDF, in the print panel.
    private func printDocument(_ shared: ShareDocument) {
        guard let window = hostWindow,
              let document = PDFDocument(data: shared.pdf(cassette: WebExport.pdfCassette())),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { return }
        operation.jobTitle = recording.title
        operation.showsPrintPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Kopieer (a summary, a turn, the transcript): plain text on the clipboard.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The share sheet, with the app icon (audio: its cover) and the recording's title as its
    /// preview (not a tiny thumbnail of the file).
    private func share(_ items: [URL], _ kind: ShareText.Kind) {
        guard let view = hostWindow?.contentView else { return }
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
            onSeek(position + (direction == .increment ? PlayerModel.skipInterval : -PlayerModel.skipInterval))
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
    var markers = Markers()
    var onEditNote: (Double) -> Void = { _ in }
    var onRemoveMarker: (Double) -> Void = { _ in }
    /// Right-click › Kopieer transcript (the whole transcript as plain text, with the folder's markers).
    var onCopyTranscript: () -> Void = {}
    let onSeek: (TimeInterval) -> Void

    /// Right-click › Kopieer (this turn): "0:12 · Anna" and the turn's text on the next line.
    static func copyText(of turn: TranscriptTurn, in transcript: Transcript) -> String {
        let time = TranscriptWriter.shortClock(turn.start)
        let label = turn.speaker.isEmpty ? time : "\(time) · \(transcript.name(of: turn.speaker))"
        return label + "\n" + turn.sentences.map(\.text).joined(separator: " ")
    }

    /// Per turn the markers in it (specs/markers.md 6): the sentence each falls in (the one whose
    /// start ≤ time < next start) and the marker's time.
    nonisolated static func flags(_ markers: Markers, in turns: [TranscriptTurn]) -> [Int: [TurnView.Flag]] {
        let sentences = turns.flatMap { turn in turn.sentences.indices.map { (turn: turn.id, sentence: $0, start: turn.sentences[$0].start) } }
        var out: [Int: [TurnView.Flag]] = [:]
        for (i, times) in markers.placed(in: sentences.map(\.start)) {
            out[sentences[i].turn, default: []] += times.map { TurnView.Flag(sentence: sentences[i].sentence, time: $0) }
        }
        return out.mapValues { $0.sorted { $0.time < $1.time } }
    }

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
        let flags = Self.flags(markers, in: turns)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if turns.isEmpty {
                        Text(tr("transcript.noSpeech", "Geen spraak herkend.")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        // No sentence to put them before: all of them here.
                        markerRows(markers.times)
                    }
                    ForEach(turns) { turn in
                        let turnFlags = flags[turn.id] ?? []
                        VStack(alignment: .leading, spacing: 6) {
                            TurnView(turn: turn,
                                     name: turn.speaker.isEmpty || turn.continued ? "" : transcript.name(of: turn.speaker),
                                     time: clock(turn.start),
                                     activeSentence: active?.turn == turn.id ? active?.sentence : nil,
                                     query: query,
                                     currentMatch: current?.turn == turn.id ? current?.sentence : nil,
                                     flags: turnFlags)
                                .equatable()
                                .contextMenu {
                                    Button(tr("window.copy.turn", "Kopieer")) {
                                        RecordingView.copy(Self.copyText(of: turn, in: transcript))
                                    }
                                    Button(tr("window.copy.transcript", "Kopieer alles"), action: onCopyTranscript)
                                }
                            // Under the paragraph a line per marker: its time (play) and note (edit).
                            markerRows(turnFlags.map(\.time))
                        }
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

    @ViewBuilder private func markerRows(_ times: [Double]) -> some View {
        ForEach(times, id: \.self) { time in
            MarkerRow(time: time, note: markers.note(at: time), onPlay: { onSeek(time) },
                      onEdit: { onEditNote(time) }, onRemove: { onRemoveMarker(time) })
        }
    }
}

/// One marker: the flag and time (click: play from there) and the note, or a dimmed "Notitie
/// toevoegen…" (click: edit). Right-click: Notitie…, Verwijder marker.
struct MarkerRow: View {
    let time: Double
    let note: String?
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xD2442A))
                    Text(TranscriptWriter.shortClock(time)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .help(tr("marker.play", "Speel af vanaf deze marker"))
            Button(action: onEdit) {
                Text(note ?? tr("marker.addNote", "Notitie toevoegen…"))
                    .foregroundStyle(note == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .multilineTextAlignment(.leading)
            }
        }
        .font(.callout)
        .buttonStyle(.plain)
        .contextMenu {
            Button(tr("marker.note", "Notitie…"), action: onEdit)
            Button(tr("marker.remove", "Verwijder marker"), role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(tr("marker.note", "Notitie…")), onEdit)
        .accessibilityAction(named: Text(tr("marker.remove", "Verwijder marker")), onRemove)
    }
}

/// A marker's note: one line, empty removes the note (not the marker).
struct MarkerNoteSheet: View {
    let time: Double
    let note: String?
    let save: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(tr("marker.noteTitle", "Notitie bij %@", TranscriptWriter.shortClock(time))).font(.headline)
            TextField(tr("marker.addNote", "Notitie toevoegen…"), text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(done)
                .onChange(of: text) { _, new in
                    if new.count > Markers.maxNoteLength { text = String(new.prefix(Markers.maxNoteLength)) }
                }
            HStack {
                Button(tr("button.cancel", "Annuleer"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("button.save", "Bewaar"), action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { text = note ?? "" }
    }

    private func done() {
        save(text)
        dismiss()
    }
}

/// The chooser before Deel als…, Kopieer als… and Bewaar als… (owner, 2026-11-11): PDF, Text or
/// Markdown, the last choice per action remembered; with summaries also a
/// checkbox per summary and the transcript, all checked each time, in the document's order
/// (specs/share.md). Before Afdrukken… only with summaries, then only the checkboxes. The button is
/// off when nothing is checked.
struct ShareChooser: View {
    let action: RecordingView.ShareAction
    let summaries: [WebExport.Summary]
    let done: (_ format: RecordingView.ShareFormat, _ summaries: [WebExport.Summary], _ transcript: Bool) -> Void
    @State private var chosen: Set<Int>
    @State private var transcript = true
    @AppStorage private var format: String
    @Environment(\.dismiss) private var dismiss

    init(action: RecordingView.ShareAction, summaries: [WebExport.Summary],
         done: @escaping (_ format: RecordingView.ShareFormat, _ summaries: [WebExport.Summary], _ transcript: Bool) -> Void) {
        self.action = action
        self.summaries = summaries
        self.done = done
        _chosen = State(initialValue: Set(summaries.indices))
        _format = AppStorage(wrappedValue: action.formats[0].rawValue, "shareFormat.\(action.rawValue)")
    }

    /// The remembered format, if this action still offers it.
    private var picked: RecordingView.ShareFormat {
        RecordingView.ShareFormat(rawValue: format).flatMap { action.formats.contains($0) ? $0 : nil } ?? action.formats[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading).font(.headline)
            if action != .print {
                Picker(selection: Binding(get: { picked }, set: { format = $0.rawValue })) {
                    ForEach(action.formats, id: \.self) { f in
                        Text(Self.name(of: f)).tag(f)
                    }
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if !summaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summaries.indices, id: \.self) { i in
                        Toggle(summaries[i].name, isOn: Binding(
                            get: { chosen.contains(i) },
                            set: { if $0 { chosen.insert(i) } else { chosen.remove(i) } }))
                    }
                    Toggle(tr("window.transcript", "Transcript"), isOn: $transcript)
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                Spacer()
                Button(tr("button.cancel", "Annuleer"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: share) { Text(buttonTitle) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!summaries.isEmpty && chosen.isEmpty && !transcript)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        // The system's own look (owner: calmer than the window's navy, also in dark).
        .tint(nil)
    }

    static func name(of format: RecordingView.ShareFormat) -> String {
        switch format {
        case .pdf: "PDF"
        case .text: tr("share.format.text", "Tekst")
        case .markdown: "Markdown"
        }
    }

    private var buttonTitle: String {
        switch action {
        case .share: tr("share.choose.share", "Deel")
        case .copy: tr("share.choose.copy", "Kopieer")
        case .save: tr("share.choose.save", "Bewaar…")
        case .print: tr("share.choose.print", "Afdrukken")
        }
    }

    private var heading: String {
        switch action {
        case .share: tr("share.choose.titleShare", "Deel als")
        case .copy: tr("share.choose.titleCopy", "Kopieer als")
        case .save: tr("share.choose.titleSave", "Bewaar als")
        case .print: tr("share.choose.title", "Wat wil je delen?")
        }
    }

    private func share() {
        guard summaries.isEmpty || !chosen.isEmpty || transcript else { return }
        done(picked, summaries.indices.filter(chosen.contains).map { summaries[$0] }, summaries.isEmpty || transcript)
        dismiss()
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
    var flags: [Flag] = []

    /// A marker before sentence `sentence` (specs/markers.md 6).
    struct Flag: Equatable {
        let sentence: Int
        let time: Double
    }

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
            // A small red flag before the sentence a marker falls in; click: play from the marker.
            for flag in flags where flag.sentence == i {
                var mark = AttributedString("🚩\u{2009}")
                mark.link = URL(string: "\(TranscriptBody.seekScheme):\(flag.time)")
                mark.font = .caption
                text += mark
            }
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
                            Text(verbatim: "•").foregroundStyle(.secondary)
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
    /// The recording; its clips play in the app's player.
    let item: PlayableItem
    let folder: URL
    let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerModel.self) private var player
    @State private var rows: [Row] = []
    @State private var playing: String?
    /// Starts a clip (the player may first load the audio); cancelled by `stopClip`.
    @State private var clipStart: Task<Void, Never>?
    @State private var clipStop: Task<Void, Never>?
    @State private var error: String?
    @State private var saving = false

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
                    .disabled(saving)
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
        clipStart = Task {
            let start = max(0, row.start - 0.2)
            if Playback.isCurrent(folder), let current = player.current {
                player.play(current, at: start)
            } else {
                await player.play(item, at: start).value
            }
            // Stopped (or the sheet closed) while the audio loaded: it must not play on. Another
            // clip started meanwhile plays its own fragment.
            guard !Task.isCancelled else {
                if playing == nil { player.pause(reason: .user) }
                return
            }
            if let failure = Playback.failure {
                error = failure
                playing = nil
                return
            }
            let length = min(row.end - row.start + 0.4, Self.clipSeconds)
            clipStop = Task {
                try? await Task.sleep(for: .seconds(length))
                guard !Task.isCancelled else { return }
                stopClip()
            }
        }
    }

    private func stopClip() {
        clipStart?.cancel()
        clipStart = nil
        clipStop?.cancel()
        clipStop = nil
        if playing != nil { player.pause(reason: .user) }
        playing = nil
    }

    private func save() {
        guard !saving else { return }
        stopClip()
        var names: [String: String] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[row.label] = name }
        }
        let json = json
        saving = true
        Task {
            defer { saving = false }
            do {
                try await Task.detached { try Self.setSpeakerNames(names, json: json) }.value
                Task { await onSave() }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Reads the transcript as it is on disk now and changes only its speaker names (off the main
    /// thread: the coordinated write may wait for iCloud). The sheet's copy may be older: markers set
    /// or another device's changes since it opened stay.
    nonisolated static func setSpeakerNames(_ names: [String: String], json: URL) throws {
        var t = try TranscriptWriter.read(json: json)
        guard t.speakerNames != names else { return }
        t.speakerNames = names
        try TranscriptWriter.rewrite(t, json: json)
    }
}
