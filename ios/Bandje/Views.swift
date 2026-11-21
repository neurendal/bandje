// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BandjeKit
import LinkPresentation
import MapKit
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Library.self) private var library
    @Environment(Recorder.self) private var recorder
    @State private var showRecorder = false
    @State private var startError: String?
    @State private var renaming: Recording?
    @State private var deleting: Recording?
    /// The open recording: pushed on an iPhone, the right-hand column on an iPad.
    @State private var selection: Recording?
    @State private var showImporter = false
    @State private var showAbout = false
    @State private var showConsent = false
    @State private var showOnboarding = false
    @State private var query = ""
    /// Open and standing (a portrait wide screen): the sidebar steps aside once a recording opens;
    /// lying down the list and the recording stay side by side, the fold between them.
    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var portrait = true

    private func row(_ recording: Recording) -> some View {
        // A list beside the recording (iPad, an unfolded iPhone Duo): the open one is selected in navy.
        let selected = sizeClass == .regular && selection?.folder == recording.folder
        return NavigationLink(value: recording) {
            RecordingRow(recording: recording,
                         snippet: library.snippet(for: recording, query: query) ?? library.previews[recording.folder],
                         selected: selected, isNew: library.isNew(recording))
                .environment(\.colorScheme, selected ? .dark : colorScheme)
        }
        // The open recording on an iPad: band.je navy, inset with round corners (as on the Mac).
        .listRowBackground(selected ? RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.selection).padding(.horizontal, 8) : nil)
        .swipeActions(edge: .trailing) {
            Button {
                deleting = recording
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .deleteConfirmation(for: recording, deleting: $deleting)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = recording }
            AudioShareLink(recording: recording) { Label("Share", systemImage: "square.and.arrow.up") }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = recording }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Group {
                if library.recordings.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 20) {
                            CassetteView(state: CassetteState(), blankSticker: true)
                                .frame(width: 200)
                            Text("No recordings yet")
                                .font(.title2.weight(.semibold))
                        }
                    } description: {
                        VStack(spacing: 12) {
                            Text("Record something, or open audio from another app in Bandje.")
                            if Device.name == "iPhone" {
                                Text("Phone call? Where the Phone app can record calls, tap its record button, then share the recording from Notes to Band·je. Not every country has this, the EU for example.")
                                    .font(.footnote)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        // Points at the record button just below.
                        Image(systemName: "arrow.down")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color("ButtonAccent"))
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                    }
                } else {
                    let results = library.search(query)
                    List(selection: $selection) {
                        ForEach(Library.days(results), id: \.title) { day in
                            Section(day.title) {
                                ForEach(day.recordings) { row($0) }
                            }
                        }
                    }
                    // iPad: the sidebar's rounded, inset selection; iPhone: the plain list.
                    .modifier(LibraryListStyle())
                    .overlay {
                        if results.isEmpty { ContentUnavailableView.search(text: query) }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Band·je"))
            .navigationBarTitleDisplayMode(.large)
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            .toolbar {
                // band.je's wordmark as the large title: it lines up with the list, clear of the corner.
                ToolbarItem(placement: .largeTitle) {
                    BrandMark(size: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showAbout = true }
                        .accessibilityIdentifier("aboutButton")
                    if library.importing > 0 {
                        ProgressView().accessibilityLabel(Text("Importing"))
                    } else {
                        Button("Import", systemImage: "plus") { showImporter = true }
                            .accessibilityIdentifier("importButton")
                    }
                }
            }
            .modifier(LibrarySearch(query: $query))
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    let imported = await library.importFiles(urls)
                    if urls.count == 1, let recording = imported.first { selection = recording }
                }
            }
            .onOpenURL { url in
                Task {
                    if let recording = await library.openDocument(url) { selection = recording }
                }
            }
            .alert(library.importErrors.count > 1 ? Text("Some files could not be imported") : Text("Can't import"),
                   isPresented: Binding(get: { !library.importErrors.isEmpty }, set: { if !$0 { library.importErrors = [] } })) {
                Button("OK") {}
            } message: {
                Text(library.importErrors.joined(separator: "\n"))
            }
            .recordingActions(renaming: $renaming)
            .safeAreaBar(edge: .bottom) {
                RecordButton(isRecording: recorder.isActive) {
                    if recorder.isActive {
                        showRecorder = true
                    } else if !RecordingCommands.consentShown {
                        showConsent = true
                    } else {
                        Task { await startRecording() }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // iPhone: a sheet. Wide (iPad, an open Duo): the whole screen, so the cassette and the time
            // sit above the fold and the buttons below it (a sheet there is a narrow card).
            .sheet(isPresented: Binding(get: { showRecorder && sizeClass != .regular }, set: { showRecorder = $0 })) {
                RecordView()
                    .interactiveDismissDisabled(recorder.isActive)
            }
            .fullScreenCover(isPresented: Binding(get: { showRecorder && sizeClass == .regular }, set: { showRecorder = $0 })) {
                RecordView()
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .alert("Can't record", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
                Button("OK") {}
            } message: {
                Text(startError ?? "")
            }
            // The recording stopped by itself (the disk got full, writing failed, 12 hours), or could
            // not be converted: also when that happened while Bandje was in the background.
            .alert("Recording stopped", isPresented: Binding(get: { recorder.stopNotice != nil && !recorder.isActive },
                                                             set: { if !$0 { recorder.stopNotice = nil } })) {
                Button("OK") {}
            } message: {
                Text(recorder.stopNotice ?? "")
            }
            // One-time notice before the first recording (SPEC 9, as in the Mac app).
            .alert("Tell people you are recording", isPresented: $showConsent) {
                Button("Understood, record") {
                    RecordingCommands.consentShown = true
                    Task { await startRecording() }
                }
                .accessibilityIdentifier("consentOK")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("In some countries, and at work, the law requires you to tell the other participants before you record a conversation, and sometimes to ask for their consent. You are responsible for following the law that applies to you.")
            }
            // A recording started from Siri, Shortcuts, the Action button or the Control.
            .onChange(of: recorder.isActive) { _, active in
                if !active { showRecorder = false }
            }
            .onChange(of: library.recordings) { _, recordings in
                // The open recording was deleted, renamed or moved (iCloud): follow it, or close it.
                guard let open = selection, !recordings.contains(where: { $0.folder == open.folder }) else { return }
                selection = recordings.first { $0.date == open.date && abs($0.duration - open.duration) < 0.5 }
            }
        } detail: {
            if let selection {
                RecordingView(recording: selection, search: query)
                    .id(selection.folder)
            } else {
                ContentUnavailableView("Choose a recording", systemImage: "recordingtape",
                                       description: Text("Or record something new."))
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width } action: { tall in
            portrait = tall
            columns = tall && selection != nil && query.isEmpty ? .detailOnly : .automatic
        }
        // Searching (also a search set from outside): the list with the results stays in view.
        .onChange(of: query) { _, q in
            if !q.isEmpty, sizeClass == .regular, columns == .detailOnly { columns = .all }
        }
        .onChange(of: selection) { _, open in
            // P1: back to the list or another recording stops playback; its position is kept.
            // A rename keeps playing (Library.rename moved the player first).
            Playback.left(showing: open?.folder)
            if let open { library.markSeen(open) }
            if sizeClass == .regular, portrait, open != nil, query.isEmpty { columns = .detailOnly }
        }
        // Stopped: the new recording opens right away.
        .onChange(of: library.justRecorded) { _, folder in
            guard let folder else { return }
            library.justRecorded = nil
            if let recording = library.recordings.first(where: { $0.folder == folder }) { selection = recording }
        }
        // Wide, the detail is never empty: the newest recording opens (also when a Duo unfolds).
        .onChange(of: sizeClass) { _, size in openNewestIfWide(size) }
        .onChange(of: library.recordings.isEmpty) { _, _ in openNewestIfWide(sizeClass) }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            showOnboarding = OnboardingView.isNeeded
            await CloudSync.shared.launch()  // before the first scan, so it includes iCloud
            await library.launch(except: recorder.folder)
            LiveRecording.shared.cleanUpAfterLaunch()
            openNewestIfWide(sizeClass)
            #if DEBUG
            if let imported = await Selftest.run(recorder: recorder, library: library) { selection = imported }
            if let search = Selftest.options.search { query = search }  // screenshots
            if let name = Selftest.options.demoState {
                switch await Selftest.demo(name, recorder: recorder, library: library) {
                case .open(let recording): selection = recording
                case .record: showRecorder = true
                case .about: showAbout = true
                case .onboarding: showOnboarding = true
                case .none: break
                }
                // `-demoScrollBottom YES`: Settings or the welcome scrolled to the end (screenshots).
                if UserDefaults.standard.bool(forKey: "demoScrollBottom") { Selftest.scrollToBottomSoon() }
            }
            #endif
        }
    }

    private func openNewestIfWide(_ size: UserInterfaceSizeClass?) {
        if size == .regular, selection == nil { selection = library.recordings.first }
    }

    private func startRecording() async {
        do {
            try await RecordingCommands.start()
            showRecorder = true
        } catch {
            startError = error.localizedDescription
        }
    }
}

struct RecordingRow: View {
    @Environment(Transcriptions.self) private var transcriptions
    @Environment(\.dynamicTypeSize) private var typeSize
    let recording: Recording
    var snippet: String? = nil
    /// On the navy selection (iPad): white text, not the sidebar's red selection tint.
    var selected = false
    /// Not opened yet: a dot before it, as in a mailbox.
    var isNew = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                // The tape itself, with its sticker: the list reads as a stack of cassettes.
                CassetteView(state: CassetteState(duration: recording.duration, title: recording.title, color: recording.color))
                    .frame(width: 64)
                    .accessibilityHidden(true)
            }
            details
        }
        // The dot hangs in the margin left of the cassette, so rows stay aligned.
        .overlay(alignment: .leading) {
            if isNew {
                Circle()
                    .fill(Color("ButtonAccent"))
                    .frame(width: 9, height: 9)
                    .offset(x: -14)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isNew ? Text("New") : Text(verbatim: ""))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recording.title)
                .font(.headline)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            // One text, so it wraps as a sentence at large text sizes; the status gets its own
            // line there.
            // The day is the section header; the row has the time.
            let metadata = Text(verbatim: "\(recording.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))  ·  \(spokenDuration(recording.duration))")
                .monospacedDigit()
            Group {
                if typeSize.isAccessibilitySize {
                    metadata
                    status
                } else {
                    HStack {
                        metadata
                        Spacer(minLength: 0)
                        status
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(.secondary))
            if let snippet {
                Text(snippet)
                    .font(.footnote)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
        }
    }

    /// Transcript ready / in progress / none.
    @ViewBuilder private var status: some View {
        if let phase = transcriptions.phase(of: recording.folder) {
            Text(Transcriptions.fraction(phase), format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(Color.progress)
                .accessibilityLabel(Text("Transcribing"))
                .accessibilityIdentifier("rowProgress")
        } else if recording.transcript != nil {
            Image(systemName: "text.quote")
                .accessibilityLabel(Text("Transcript"))
        }
    }
}

/// "48 sec", "20 min", "1 hr 5 min": a length that doesn't read like a time of day.
func spokenDuration(_ seconds: TimeInterval) -> String {
    let t = max(0, seconds.isFinite ? seconds : 0).rounded()
    let units: Set<Duration.UnitsFormatStyle.Unit> = t < 60 ? [.seconds] : t < 3600 ? [.minutes] : [.hours, .minutes]
    return Duration.seconds(t).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2,
                                                fractionalPart: .hide(rounded: .toNearestOrEven)))
}

extension Color {
    /// band.je's button colour (--btn): navy #262B4F in light, #F5F5F7 in dark. The play button and
    /// every progress bar (position, transcribing, summarising) use it, on iPhone, iPad and Mac alike.
    static let brand = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
        : UIColor(red: 0x26 / 255, green: 0x2B / 255, blue: 0x4F / 255, alpha: 1) })
    /// Ink on `brand` (--btnInk).
    static let brandInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        : .white })
    /// Every progress bar (position, transcribing, summarising, the % in the list): the app's red
    /// accent, on iPhone, iPad and Mac alike (owner: not navy/white).
    static let progress = Color.accentColor
    /// Selected list row and tab: band.je navy, lighter in dark so it stays visible (as on the Mac).
    static let selection = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3D / 255, green: 0x44 / 255, blue: 0x78 / 255, alpha: 1)
        : UIColor(red: 0x26 / 255, green: 0x2B / 255, blue: 0x4F / 255, alpha: 1) })
}

/// Wide (iPad, an unfolded iPhone Duo): the sidebar style, an inset selection with round corners like
/// the panel; narrow (iPhone, a folded Duo): plain. By size class, not by device, so a foldable follows
/// its screen.
private struct LibraryListStyle: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular { content.listStyle(.sidebar) } else { content.listStyle(.plain) }
    }
}

/// Search titles and transcripts with the system's search field (at the bottom on an iPhone, under the
/// title in a sidebar). Always attached: a split view doesn't pick up one added later.
private struct LibrarySearch: ViewModifier {
    @Binding var query: String
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .searchable(text: $query, isPresented: $presented,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text("Titles and transcripts"))
            .onChange(of: query, initial: true) { _, q in if !q.isEmpty { presented = true } }  // set from outside
    }
}

/// "1:05" or "1:02:05".
func clock(_ seconds: TimeInterval) -> String {
    let t = max(0, seconds.isFinite ? seconds : 0)
    return Duration.seconds(t).formatted(.time(pattern: t >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

// MARK: - Rename and delete (list and detail)

extension View {
    /// The delete confirmation, attached to what was tapped or swiped (a row, the ••• menu): since
    /// iOS 26 it is a popover whose arrow points at the view it hangs on.
    func deleteConfirmation(for recording: Recording, deleting: Binding<Recording?>,
                            onDone: @escaping () -> Void = {}) -> some View {
        modifier(DeleteConfirmation(recording: recording, deleting: deleting, onDone: onDone))
    }

    /// The label sheet (title and colour) for a recording. `onDone` gets the renamed recording.
    func recordingActions(renaming: Binding<Recording?>,
                          onDone: @escaping (Recording?) -> Void = { _ in }) -> some View {
        modifier(RecordingActions(renaming: renaming, onDone: onDone))
    }
}

private struct DeleteConfirmation: ViewModifier {
    @Environment(Library.self) private var library
    let recording: Recording
    @Binding var deleting: Recording?
    let onDone: () -> Void
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Text("Delete “\(recording.title)”?"),
                                isPresented: Binding(get: { deleting?.folder == recording.folder },
                                                     set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await library.delete(recording)
                            onDone()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("The recording and its transcript will be removed from this \(Device.name).")
            }
            .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
    }
}

private struct RecordingActions: ViewModifier {
    @Environment(Library.self) private var library
    @Binding var renaming: Recording?
    let onDone: (Recording?) -> Void
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            // The title and the cassette's colour together (the sticker and the menu's Rename open it).
            .sheet(item: $renaming) { recording in
                LabelSheet(recording: recording) { title, color in
                    Task {
                        do {
                            var current = recording
                            if title.trimmingCharacters(in: .whitespaces) != recording.title {
                                current = try await library.rename(recording, to: title)
                            }
                            if color != current.color {
                                try await library.setColor(color, of: current)
                                current.color = color
                            }
                            onDone(current)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
    }
}

/// Rename a recording and pick its cassette's colour; the cassette shows both as you go.
struct LabelSheet: View {
    let recording: Recording
    let save: (String, TapeColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = TapeColor.red
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                CassetteView(state: CassetteState(duration: recording.duration, title: title, color: color))
                    .frame(maxWidth: 220)
                    .animation(.smooth, value: color)
                    .accessibilityHidden(true)
                TextField("Title", text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(done)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("titleField")
                HStack(spacing: 12) {
                    ForEach(TapeColor.allCases, id: \.self) { option in
                        Button {
                            color = option
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: option.gradient.top), Color(hex: option.gradient.bottom)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if option == color {
                                        Circle().strokeBorder(.background, lineWidth: 3)
                                        Circle().strokeBorder(Color(hex: option.gradient.bottom), lineWidth: 1.5).padding(-3)
                                    }
                                }
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.name))
                        .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: done)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveLabel")
                }
            }
        }
        .presentationDetents([.height(400)])
        .onAppear {
            title = recording.title
            color = recording.color
            focused = true
        }
    }

    private func done() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        save(title, color)
        dismiss()
    }
}

// MARK: - Recording (detail)

struct RecordingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(Transcriptions.self) private var transcriptions
    @Environment(SummaryJobs.self) private var summaries
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State var recording: Recording
    /// The library's search when the recording was opened: the transcript search starts with it.
    var search = ""
    @State private var renaming: Recording?
    @State private var deleting: Recording?
    @State private var loaded: LoadedTranscript?
    /// The transcript file could not be read (`loadTranscript`).
    @State private var loadError: (json: URL, message: String)?
    @State private var tab = DetailTab.transcript
    @State private var summaryBlocks: [Summaries.Block]?
    /// The summary's body as text, for "Copy All".
    @State private var summaryText: String?
    @State private var naming = false
    @State private var searching = false
    @State private var query = ""
    @State private var matchIndex = 0
    /// "Share as web page": made on demand (the audio is re-encoded), then the share sheet.
    @State private var webPage: SharedFile?
    @State private var makingWebPage = false
    @State private var webPageError: String?
    /// The chooser before sharing or printing the document, when there are summaries (specs/share.md).
    @State private var choosing: ShareChoice?
    /// Print chosen in the chooser: printed once the chooser has gone.
    @State private var printAfterChooser: (summaries: [Summaries.Part], turns: Bool)?
    /// Scrolled into the transcript or summary: the player folds into one bar, so there's room to read.
    @State private var compact = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var lastFold = Date.distantPast
    /// The summary templates (read when the view appears; the menus don't touch the disk).
    @State private var templates: [Summaries.Template] = []
    @State private var managingTemplates = false
    /// The recording's markers and notes (specs/markers.md), from its folder.
    @State private var markers = Markers()
    /// The marker whose note is being edited, and the text field's text.
    @State private var editingNote: Double?
    @State private var noteText = ""
    /// The marker just removed, for "Undo" (a few seconds).
    @State private var removedMarker: RemovedMarker?
    @State private var markerError: String?
    /// Counts the user's marks, for the haptic (not on loading the markers).
    @State private var marks = 0
    /// Marker writes run one after another; while one is pending, a reload from disk (which may
    /// not have it yet) is skipped, so a quick second mark never builds on an older state.
    @State private var markerWrites: Task<Void, Never>?
    @State private var pendingMarkerWrites = 0
    /// The paywall, for the transcription the user asked for (it starts once unlocked).
    @State private var paywall: PaywallRequest?

    struct PaywallRequest: Identifiable {
        let id = UUID()
        let speakers: Bool
    }

    struct RemovedMarker: Equatable {
        let time: Double
        let note: String?
    }

    /// The recording as the library knows it now (the transcript appears after a job).
    private var live: Recording {
        library.recordings.first { $0.folder == recording.folder } ?? recording
    }
    private var isCurrent: Bool { player.current != nil && Playback.isCurrent(recording.folder) }
    /// Where it plays, or where it would resume (P3).
    private var position: TimeInterval { player.savedPosition(for: Playback.id(of: recording)) ?? 0 }
    private var duration: TimeInterval { isCurrent && player.duration > 0 ? player.duration : recording.duration }
    /// Playing, or about to (downloading from iCloud, P13): the button pauses.
    private var isPlaying: Bool { isCurrent && (player.state == .playing || player.state == .loading) }
    private var transcript: Transcript? { loaded?.json == live.transcript ? loaded?.transcript : nil }
    /// Summaries exist only with a transcript and when Apple Intelligence is available (SPEC 7).
    private var canSummarise: Bool { transcript != nil && OnDeviceSummarizer.isAvailable }
    /// A summary that exists stays readable when the model is briefly not ready ("modelNotReady"
    /// right after launch, or while Apple updates it); only making one needs Apple Intelligence.
    private var hasSummaryTab: Bool { transcript != nil && (canSummarise || live.summary != nil) }
    private var showingSummary: Bool { hasSummaryTab && tab == .summary }

    enum DetailTab: Hashable { case transcript, summary }

    /// Transcribe (or again): past the free transcriptions nothing starts and the paywall opens.
    private func transcribe(speakers: Bool) {
        if !transcriptions.start(live, speakers: speakers) { paywall = PaywallRequest(speakers: speakers) }
    }

    var body: some View {
        Group {
            if sizeClass == .regular, #available(iOS 27.1, *) {
                // Wide (iPad, iPhone Duo open or half open): the player and the text side by side or
                // one above the other, as the system arranges them around the fold.
                ArrangementView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 0)
                        header
                        fullPlayer
                        playerError
                        Spacer(minLength: 0)
                    }
                } secondary: {
                    transcriptArea
                        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .top)
                        .frame(maxWidth: .infinity)
                }
                .arrangementViewStyle(.split)
            } else {
                VStack(spacing: compact ? 10 : 16) {
                    if !compact { header }
                    if compact { compactPlayer } else { fullPlayer }
                    playerError
                    transcriptArea
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: 680)  // readable lines on an iPad
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $paywall) { request in
            PaywallView { transcriptions.start(live, speakers: request.speakers) }
        }
        .sheet(item: $webPage) { page in
            ShareSheet(items: [WebPageItem(url: page.url, title: live.title)]).presentationDetents([.medium, .large])
        }
        .sheet(item: $choosing, onDismiss: {
            if let p = printAfterChooser {
                printAfterChooser = nil
                printDocument(p.summaries, turns: p.turns)
            }
        }) { choice in
            if let transcript {
                ShareChooser(format: choice.format, parts: choice.parts, transcript: exported(transcript)) { summaries, turns in
                    printAfterChooser = (summaries, turns)
                    choosing = nil
                }
            }
        }
        .alert("Can't make the audio page", isPresented: Binding(get: { webPageError != nil }, set: { if !$0 { webPageError = nil } })) {
            Button("OK") {}
        } message: {
            Text(webPageError ?? "")
        }
        .recordingActions(renaming: $renaming) { renamed in
            if let renamed { recording = renamed }
        }
        .sheet(isPresented: $managingTemplates, onDismiss: { templates = Summaries.templates() }) { TemplatesSheet() }
        .sheet(isPresented: $naming) {
            if let transcript, let json = live.transcript {
                SpeakerNamingSheet(transcript: transcript, json: json, recording: live) { saved in
                    loaded = LoadedTranscript(json: json, transcript: saved)
                }
            }
        }
        .task(id: MarkersKey(folder: live.folder, scan: library.scans)) {
            // Again after every library scan: iCloud brought changes from the other device (also a
            // note alone, which changes no marker time).
            let folder = live.folder
            guard pendingMarkerWrites == 0 else { return }
            let read = await Task.detached { Markers.read(from: folder) }.value
            if pendingMarkerWrites == 0, !Task.isCancelled { markers = read }
        }
        .alert("Note", isPresented: Binding(get: { editingNote != nil }, set: { if !$0 { editingNote = nil } })) {
            TextField("Note", text: $noteText)
            Button("Save") {
                if let time = editingNote {
                    var m = markers
                    m.setNote(noteText, at: time)
                    saveMarkers(m)
                }
                editingNote = nil
            }
            Button("Cancel", role: .cancel) { editingNote = nil }
        } message: {
            Text(editingNote.map { String(localized: "Marker at \(clock($0))") } ?? "")
        }
        .alert("Can't save the marker", isPresented: Binding(get: { markerError != nil }, set: { if !$0 { markerError = nil } })) {
            Button("OK") {}
        } message: {
            Text(markerError ?? "")
        }
        .overlay(alignment: .bottom) { undoToast }
        .sensoryFeedback(.impact(weight: .medium), trigger: marks)
        .task(id: TranscriptKey(json: live.transcript, generation: transcriptions.generation(of: recording.folder))) {
            guard let json = live.transcript else { loaded = nil; return }
            let read = await loadTranscript(json)
            #if DEBUG
            // Screenshots: the speaker-naming sheet or the web page's share sheet, opened.
            if let t = read {
                switch Selftest.options.openSheet ?? Selftest.options.demoState {
                case "speakers": naming = true
                case "share": makeWebPage(t)
                case "summary-tab": tab = .summary
                case "compact": compact = true
                case "templates": tab = .summary; managingTemplates = true
                default: break
                }
            }
            #endif
        }
        .task(id: SummaryKey(file: live.summary, generation: summaries.generation)) {
            guard let file = live.summary else { summaryBlocks = nil; summaryText = nil; return }
            await loadSummary(file)
        }
        .onDisappear {
            // Back from a finished transcript: the moment for Apple's review prompt (3rd and 10th).
            if transcript != nil, ReviewPrompt.shouldAsk() {
                ReviewPrompt.markAsked()
                requestReview()
            }
        }
        .onAppear {
            templates = Summaries.templates()
            // Opened from a library search: the transcript search open with that term, at its first match.
            let term = search.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty {
                query = term
                searching = true
            }
            #if DEBUG
            if Selftest.options.summarize != nil || Selftest.options.demoState == "summary" { tab = .summary }  // screenshots
            if Selftest.options.openSheet == "paywall" { paywall = PaywallRequest(speakers: true) }  // screenshots
            #endif
        }
    }

    @ViewBuilder private var playerError: some View {
        if isCurrent, let error = Playback.failure {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    /// Title, date, place and the cassette.
    @ViewBuilder private var header: some View {
        VStack(spacing: live.transcript == nil ? 16 : 10) {
            VStack(spacing: 2) {
                Text(recording.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("detailTitle")
                Text(recording.date, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let location = live.location {
                    Button {
                        let item = MKMapItem(location: CLLocation(latitude: location.latitude, longitude: location.longitude), address: nil)
                        item.name = live.title
                        item.openInMaps()
                    } label: {
                        Label(String(format: "%.4f, %.4f", location.latitude, location.longitude), systemImage: "location.fill")
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(Text("Show in Maps"))
                }
            }
            .padding(.horizontal, 24)

            // Smaller once there's text to read: more room for the transcript under it.
            CassetteView(state: cassette) { renaming = live }
                .frame(maxWidth: live.transcript == nil ? 320 : 170)
                .animation(.smooth, value: live.transcript == nil)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// The position bar, the times with the speed between them, and the transport.
    @ViewBuilder private var fullPlayer: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Scrubber(position: position, duration: duration, markers: markers.times) { time in
                    Playback.seek(recording, to: time)
                }
                HStack {
                    Text(clock(position))
                        .accessibilityIdentifier("position")
                    Spacer()
                    Text("-\(clock(duration - position))")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .overlay(alignment: .top) { markerChip.offset(y: -36) }
            .padding(.horizontal, 24)

            // The speed at the left of the transport, balanced by an empty slot at the right.
            HStack(spacing: 0) {
                SpeedMenu().frame(width: 64, alignment: .leading)
                Spacer(minLength: 0)
                transport
                Spacer(minLength: 0)
                markButton.frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 24)
        }
    }

    /// While reading: a small cassette left of the title, speed and play at the right, and one line
    /// with the times either side of the position bar. Tapping the cassette unfolds the player.
    private var compactPlayer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { compact = false }
                } label: {
                    CassetteView(state: cassette).frame(width: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Show the player"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(live.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(recording.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                markButton
                SpeedMenu()
                playButton(size: 44)
            }
            HStack(spacing: 8) {
                Text(clock(position))
                Scrubber(position: position, duration: duration, markers: markers.times) { time in
                    Playback.seek(recording, to: time)
                }
                Text("-\(clock(duration - position))")
            }
            .overlay(alignment: .top) { markerChip.offset(y: -30) }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    /// Scrolling down in the text folds the player; back at the top it unfolds.
    /// `y` is the scroll offset, `overflow` how much taller the text is than its view. Text that is
    /// only just too long never folds the player: folding makes the view taller, the text would fit,
    /// snap back to the top and unfold it again. After a fold or unfold the next half second is ignored.
    fileprivate func scrolled(_ y: CGFloat, _ overflow: CGFloat) {
        guard Date().timeIntervalSince(lastFold) > 0.5 else { return }
        if y > 60, !compact, overflow > 340 {
            lastFold = Date()
            withAnimation(.smooth(duration: 0.3)) { compact = true }
        } else if y < 2, compact {
            lastFold = Date()
            withAnimation(.smooth(duration: 0.3)) { compact = false }
        }
    }

    private func summariseAgain(_ template: Summaries.Template) {
        tab = .summary
        summaries.start(live, template: template)
    }

    private var transport: some View {
        HStack(spacing: 28) {
            Button {
                Playback.skip(recording, by: -PlayerModel.skipInterval)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel("Back 15 seconds")

            playButton(size: 60)

            Button {
                Playback.skip(recording, by: PlayerModel.skipInterval)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel("Forward 15 seconds")
        }
        .tint(.primary)  // the accent stays on the position bar and the cassette
        .disabled(recorder.isActive || recording.audio == nil)
    }

    /// The most important button, filled: navy on light, cream on dark (the cassette's colours).
    private func playButton(size: CGFloat) -> some View {
        Button {
            Playback.toggle(recording)
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color.brandInk)
                .frame(width: size, height: size)
                .background(Color.brand, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(recorder.isActive || recording.audio == nil)
        .opacity(recorder.isActive || recording.audio == nil ? 0.4 : 1)
        .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
        .accessibilityIdentifier("playButton")
    }

    // MARK: Transcript area

    @ViewBuilder private var transcriptArea: some View {
        if let phase = transcriptions.phase(of: recording.folder) {
            ScrollView {
                TranscriptionProgress(phase: phase) { transcriptions.cancel(recording.folder) }
                    .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else if let transcript {
            VStack(spacing: 0) {
                if hasSummaryTab {
                    Picker("Show", selection: $tab) {
                        Text("Transcript").tag(DetailTab.transcript)
                        Text("Summary").tag(DetailTab.summary)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("detailTabs")
                }
                if showingSummary {
                    Divider()
                    summaryArea
                } else {
                    transcriptContent(transcript)
                }
            }
        } else if let json = live.transcript {
            if let loadError, loadError.json == json {
                // The file can't be read (damaged, or from a newer version): say so, and offer to
                // make it again instead of a spinner that never ends.
                ScrollView {
                    transcribePrompt(error: loadError.message)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                // The transcript exists but is not loaded yet. Load it from here too: SwiftUI does not
                // always restart the screen's `.task(id:)` when the transcript appears (a recording that
                // opened by itself after Stop and was transcribed at once kept this spinner for good).
                ProgressView()
                    .task(id: json) { _ = await loadTranscript(json) }
            }
        } else {
            // Scrolls when large text sizes don't leave room under the player.
            ScrollView {
                if live.isUnconverted {
                    // A `.caf` that was never converted (the disk was full): play or delete it.
                    Text("This recording has not been converted yet, so it can't be transcribed. Bandje tries again at the next launch, when there is enough free space. You can play it or delete it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                } else {
                    transcribePrompt(error: transcriptions.errors[recording.folder.standardizedFileURL])
                }
                // No transcript yet: the markers as a list, to play from, note or remove.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(markers.times, id: \.self) { time in
                        MarkerRow(time: time, note: markers.note(at: time), onSeek: { Playback.seek(recording, to: time) },
                                  onEdit: { editNote(time) }, onRemove: { removeMarker(time) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private var summaryArea: some View {
        let folder = recording.folder.standardizedFileURL
        if let fraction = summaries.fraction(of: folder) {
            SummaryProgress(fraction: fraction) { summaries.cancel(folder) }
                .padding(.horizontal, 24)
                .padding(.top, 24)
        } else if let summaryBlocks, live.summary != nil {
            SummaryBody(blocks: summaryBlocks, template: live.summary.flatMap { Summaries.templateName(of: $0, in: live.folder) },
                        copyText: summaryText,
                        templates: canSummarise ? templates : [], again: summariseAgain,
                        manage: { managingTemplates = true }, onScroll: scrolled)
        } else if let file = live.summary {
            // Loads by itself, like the transcript spinner (the screen's task does not always restart).
            ProgressView().padding(.top, 24)
                .task(id: SummaryKey(file: file, generation: summaries.generation)) { await loadSummary(file) }
        } else {
            SummarizePrompt(error: summaries.errors[folder]) { summaries.start(live, template: $0) }
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    private func transcribePrompt(error: String?) -> some View {
        TranscribePrompt(error: error, mayTranscribe: transcriptions.mayTranscribe(live)) { speakers in
            transcribe(speakers: speakers)
        } showPaywall: {
            paywall = PaywallRequest(speakers: UserDefaults.standard.object(forKey: "detectSpeakers") as? Bool ?? true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// Reads `json` off the main actor and shows it, unless a newer transcript (or a newer spelling
    /// of it) replaced it meanwhile: an older read never overwrites a newer one. Returns what it read.
    /// A file that can't be read leaves `loadError` (the screen offers to transcribe again).
    @discardableResult
    private func loadTranscript(_ json: URL) async -> Transcript? {
        let result = await Task.detached { Result { try TranscriptWriter.read(json: json) } }.value
        guard !Task.isCancelled, json == live.transcript else { return nil }
        switch result {
        case .success(let read):
            loaded = LoadedTranscript(json: json, transcript: read)
            loadError = nil
            return read
        case .failure(let error):
            loaded = nil
            loadError = (json, error.localizedDescription)
            return nil
        }
    }

    /// Reads the summary off the main actor and shows it, unless a newer one replaced it meanwhile.
    private func loadSummary(_ file: URL) async {
        let md = await Task.detached { try? String(contentsOf: file, encoding: .utf8) }.value
        guard !Task.isCancelled, file == live.summary else { return }
        summaryText = md.map { Summaries.body(ofDocument: $0) }
        summaryBlocks = summaryText.map { Summaries.blocks($0) }
    }

    @ViewBuilder private func transcriptContent(_ transcript: Transcript) -> some View {
        VStack(spacing: 0) {
                if searching {
                    TranscriptSearchBar(query: $query, matchIndex: $matchIndex,
                                        count: TranscriptBody.matches(in: loaded?.turns ?? [], query: query).count) {
                        searching = false
                        query = ""
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                Divider()
                TranscriptBody(transcript: transcript, turns: loaded?.turns ?? [], position: position,
                               following: isCurrent && player.isPlaying, query: searching ? query : "",
                               matchIndex: matchIndex, onScroll: scrolled, markers: markers,
                               onEditNote: editNote, onRemoveMarker: removeMarker,
                               onCopyTranscript: { UIPasteboard.general.string = TranscriptWriter.plainText(exported(transcript)) }) { time in
                    Playback.seek(recording, to: time)
                }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if transcript != nil, !showingSummary {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search transcript", systemImage: "magnifyingglass") {
                    searching.toggle()
                    if !searching { query = "" }
                }
                .accessibilityIdentifier("searchTranscript")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                AudioShareLink(recording: recording) { Label("Audio", systemImage: "waveform") }
                    .accessibilityIdentifier("shareAudio")
                if let transcript {
                    // One document: the summaries, then the transcript (specs/share.md). With a
                    // summary a chooser comes first; without one, straight to the share sheet.
                    if live.summary != nil {
                        Button("PDF", systemImage: "doc.text") { choose(.pdf) }
                            .accessibilityIdentifier("sharePDF")
                        Button("Text", systemImage: "doc.plaintext") { choose(.text) }
                            .accessibilityIdentifier("shareText")
                        Button("Markdown", systemImage: "doc.richtext") { choose(.markdown) }
                            .accessibilityIdentifier("shareMarkdown")
                    } else {
                        ShareLink(item: SharedPDF(transcript: exported(transcript)), preview: SharePreview(live.title)) {
                            Label("PDF", systemImage: "doc.text")
                        }
                        .accessibilityIdentifier("sharePDF")
                        // A named .txt file: Drive, Docs and Files need a file, not loose text.
                        ShareLink(item: SharedText(transcript: exported(transcript)),
                                  preview: SharePreview(live.title)) {
                            Label("Text", systemImage: "doc.plaintext")
                        }
                        .accessibilityIdentifier("shareText")
                        ShareLink(item: SharedText(transcript: exported(transcript), markdown: true),
                                  preview: SharePreview(live.title)) {
                            Label("Markdown", systemImage: "doc.richtext")
                        }
                        .accessibilityIdentifier("shareMarkdown")
                    }
                    // A page with the audio that plays in any browser (an .html file).
                    Button("Audio Page", systemImage: "globe") { makeWebPage(transcript) }
                        .disabled(makingWebPage)
                        .accessibilityIdentifier("shareWebPage")
                    Button("Print", systemImage: "printer") {
                        if live.summary != nil { choose(.print) } else { printDocument([], turns: true) }
                    }
                    .accessibilityIdentifier("sharePrint")
                }
            } label: {
                if makingWebPage {
                    ProgressView().accessibilityLabel(Text("Making the audio page"))
                } else {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .accessibilityIdentifier("shareMenu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rename", systemImage: "pencil") { renaming = recording }
                if let transcript, !transcript.speakerLabels.isEmpty {
                    Button("Name speakers", systemImage: "person.2") { naming = true }
                }
                if transcript != nil, !transcriptions.isRunning(recording.folder) {
                    Button("Transcribe again", systemImage: "arrow.clockwise") {
                        transcribe(speakers: UserDefaults.standard.object(forKey: "detectSpeakers") as? Bool ?? true)
                    }
                }
                if canSummarise, live.summary != nil, !summaries.isRunning(recording.folder) {
                    Menu {
                        TemplateChoices(templates: templates, choose: summariseAgain) { managingTemplates = true }
                    } label: {
                        Label("Summarise again", systemImage: "arrow.clockwise")
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = recording }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .deleteConfirmation(for: live, deleting: $deleting) { dismiss() }
            .accessibilityIdentifier("moreMenu")
        }
    }

    private var cassette: CassetteState {
        CassetteState(mode: isCurrent && player.isPlaying ? .playing : .stopped, position: position,
                      duration: duration, title: live.title, color: live.color,
                      lastSeek: isCurrent ? player.lastSeek : .distantPast, seekForward: player.lastSeekForward)
    }

    /// Reads the summaries (newest first) and opens the chooser.
    private func choose(_ format: ShareFormat) {
        let folder = live.folder
        Task {
            let parts = await Task.detached { Summaries.parts(in: folder) }.value
            choosing = ShareChoice(format: format, parts: parts)
        }
    }

    /// The document as a PDF, to the system's print dialog.
    private func printDocument(_ summaries: [Summaries.Part], turns: Bool) {
        guard let transcript else { return }
        let t = exported(transcript)
        Task {
            let brand = SharedPDF.brandImages()
            let data = await Task.detached {
                SharedPDF.pdf(t, summaries: summaries, turns: turns, wordmark: brand.wordmark, cassette: brand.cassette)
            }.value
            ShareChooser.print(data, title: t.title)
        }
    }

    private func makeWebPage(_ transcript: Transcript) {
        makingWebPage = true
        let recording = live, t = exported(transcript)
        Task {
            defer { makingWebPage = false }
            do {
                webPage = SharedFile(url: try await WebExport.export(recording, transcript: t))
            } catch {
                webPageError = error.localizedDescription
            }
        }
    }

    /// The transcript with the title, date and place as they are now (older transcripts lack them).
    private func exported(_ transcript: Transcript) -> Transcript {
        var t = transcript
        t.title = live.title
        t.recorded = t.recorded ?? live.date
        t.location = t.location ?? live.location
        t.markerSet = markers  // the folder's, also changes made after the transcript was written
        return t
    }

    // MARK: Markers (specs/markers.md)

    /// The flag: a marker where the position is (also before playing: where it would resume).
    private var markButton: some View {
        Button {
            var m = markers
            m.add(at: position, duration: duration)
            saveMarkers(m)
            marks += 1
        } label: {
            Image(systemName: "flag")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .tint(.primary)
        .disabled(recording.audio == nil)
        .accessibilityLabel(Text("Mark this moment"))
        .accessibilityIdentifier("markButton")
    }

    /// While playing past a marker with a note: the note, just above the position bar.
    @ViewBuilder private var markerChip: some View {
        let near = isCurrent && player.isPlaying ? markers.noteNear(position) : nil
        ZStack {
            if let near {
                Label(near.text, systemImage: "flag.fill")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .id(near.time)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.smooth(duration: 0.25), value: near?.time)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var undoToast: some View {
        if let removed = removedMarker {
            HStack(spacing: 14) {
                Text("Marker removed")
                Button("Undo") {
                    var m = markers
                    let time = m.add(at: removed.time)
                    m.setNote(removed.note, at: time)
                    saveMarkers(m)
                    withAnimation { removedMarker = nil }
                }
                .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: removed) {
                try? await Task.sleep(for: .seconds(5))
                if removedMarker == removed { withAnimation { removedMarker = nil } }
            }
        }
    }

    private func editNote(_ time: Double) {
        noteText = markers.note(at: time) ?? ""
        editingNote = time
    }

    private func removeMarker(_ time: Double) {
        let note = markers.note(at: time)
        var m = markers
        m.remove(at: time)
        saveMarkers(m)
        withAnimation { removedMarker = RemovedMarker(time: time, note: note) }
    }

    /// Shows `m` at once, then writes it into the folder (times in `.bandje.json`, notes in
    /// `.markers.json`) and into the transcript's `.json` and `.md` when there is one.
    private func saveMarkers(_ m: Markers) {
        markers = m
        let folder = live.folder
        let json = transcript == nil ? nil : live.transcript
        if let transcript, let json {
            var t = transcript
            t.markerSet = m
            loaded = LoadedTranscript(json: json, transcript: t)
        }
        let previous = markerWrites
        pendingMarkerWrites += 1
        markerWrites = Task {
            await previous?.value
            do {
                try await Task.detached {
                    try m.write(to: folder)
                    // Read again here: the transcript on disk may be newer than the one shown
                    // (transcribed again meanwhile); only its markers change.
                    if let json {
                        var t = try TranscriptWriter.read(json: json)
                        t.markerSet = m
                        try TranscriptWriter.write(t, json: json)
                    }
                }.value
            } catch {
                markerError = error.localizedDescription
            }
            pendingMarkerWrites -= 1
            await library.refresh(except: recorder.folder)
        }
    }

}

/// The playback speed. Its own view, reading only the rate: in the detail view, which redraws with
/// every tick of the position, the menu lost its tap while playing.
struct SpeedMenu: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {  // P14
                ForEach(PlayerModel.rates, id: \.self) { rate in
                    Text(Self.label(rate)).tag(rate)
                }
            }
        } label: {
            Text(Self.label(player.rate))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Speed")
        .accessibilityValue(Self.label(player.rate))
        .accessibilityIdentifier("speedMenu")
    }

    static func label(_ rate: Float) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

/// Position bar with the markers on it. Drag or tap to seek; VoiceOver adjusts in 15 s steps.
struct Scrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let markers: [Double]
    let onSeek: (TimeInterval) -> Void
    @State private var dragging: TimeInterval?

    var body: some View {
        let shown = dragging ?? position
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: TimeInterval) in duration > 0 ? width * min(1, max(0, t / duration)) : 0 }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(Color.progress).frame(width: x(shown), height: 4)
                // The moments marked with the flag while recording: a small flag above the bar.
                ForEach(markers, id: \.self) { marker in
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color("ButtonAccent"))
                        .offset(x: x(marker) - 1, y: -10)
                }
                Circle()
                    .fill(Color.progress)
                    .frame(width: dragging == nil ? 12 : 20, height: dragging == nil ? 12 : 20)
                    .offset(x: x(shown) - (dragging == nil ? 6 : 10))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, width > 0 else { return }
                        dragging = min(1, max(0, value.location.x / width)) * duration
                    }
                    .onEnded { _ in
                        if let dragging { onSeek(dragging) }
                        dragging = nil
                    }
            )
            .animation(.snappy(duration: 0.15), value: dragging == nil)
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(markers.isEmpty ? Text("\(clock(position)) of \(clock(duration))")
                            : Text("\(clock(position)) of \(clock(duration)), markers: \(markers.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(position + PlayerModel.skipInterval)
            case .decrement: onSeek(position - PlayerModel.skipInterval)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("scrubber")
    }
}

/// The library's record button, floating over the list; while a recording runs it shows the
/// waveform and opens the recording screen.
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // band.je's record button: a red ring and dot on glass; while recording, the waveform
            // on a red disc.
            Group {
                if isRecording {
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Color("ButtonAccent"), in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                } else {
                    // On glass, like the search field: the list shows through, blurred, in the
                    // ring's gap and the centre (owner: not an opaque black disc in dark mode).
                    RecordMark(ringOuter: 0.92, ringInner: 0.84, centre: 0.3)
                        .fill(Color("ButtonAccent"), style: FillStyle(eoFill: true))
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isRecording ? Text("Show recording") : Text("Record"))
        .accessibilityIdentifier("recordButton")
    }
}

/// The record screen: the cassette, the time, mark / stop / pause.
struct RecordView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder private var display: some View {
        CassetteView(state: CassetteState(
            mode: recorder.state == .recording ? .recording : recorder.state == .paused ? .recordingPaused : .stopped,
            position: recorder.elapsed, level: recorder.level, title: recorder.title))
            // Wide: smaller, so the cassette and the time fit in one half, clear of the fold.
            .frame(maxWidth: sizeClass == .regular ? 280 : 400)
            .padding(.horizontal, 8)
        Text(clock(recorder.elapsed))
            .font(.system(size: sizeClass == .regular ? 52 : 64, weight: .light, design: .rounded))
            .monospacedDigit()
            .accessibilityIdentifier("elapsed")
        if recorder.interruptionNotice {
            Label("Recording paused by an interruption", systemImage: "pause.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let error = recorder.errorMessage {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        if recorder.diskLow {
            Label("This \(Device.name) is almost full.", systemImage: "externaldrive.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if !recorder.markers.isEmpty {
            Text("Markers: \(recorder.markers.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 40) {
            Button {
                recorder.addMarker()
            } label: {
                Image(systemName: "flag")
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Mark this moment")
            .disabled(!recorder.isActive)

            Button {
                Task {
                    await RecordingCommands.stop()
                    dismiss()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                    .frame(width: 72, height: 72)
            }
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("stopButton")
            .disabled(!recorder.isActive)

            Button {
                RecordingCommands.togglePause()
            } label: {
                Image(systemName: recorder.state == .paused ? "record.circle" : "pause.fill")
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(recorder.state == .paused ? Text("Resume") : Text("Pause"))
            .disabled(!recorder.isActive)
        }
        .font(.title2)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular, #available(iOS 27.1, *) {
                    // Wide (iPhone Duo open or half open, iPad): the system's split arrangement, side by
                    // side like a book, one above the other like a laptop, clear of the fold.
                    ArrangementView {
                        VStack(spacing: 24) { display }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } secondary: {
                        controls
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .arrangementViewStyle(.split)
                } else {
                    VStack(spacing: 32) {
                        Spacer(minLength: 0)
                        display
                        Spacer()
                        controls
                    }
                }
            }
            .padding()
            .toolbar {
                if recorder.inputs.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(recorder.inputs, id: \.uid) { port in
                                Button {
                                    recorder.selectInput(port)
                                } label: {
                                    if port.uid == recorder.currentInput {
                                        Label(port.portName, systemImage: "checkmark")
                                    } else {
                                        Text(port.portName)
                                    }
                                }
                            }
                        } label: {
                            Label("Microphone", systemImage: "mic")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hide", systemImage: "chevron.down") { dismiss() }
                }
            }
            // Start and stop (SPEC 2); pausing and resuming stay silent.
            .sensoryFeedback(trigger: recorder.state) { old, new in
                switch (old, new) {
                case (.idle, .recording): .start
                case (_, .finishing): .stop
                default: nil
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: recorder.markers.count)
        }
    }
}

#Preview {
    LibraryView()
        .environment(Library())
        .environment(Recorder())
        .environment(Playback.player)
        .environment(Transcriptions())
        .environment(SummaryJobs())
}

// MARK: - Sharing audio with cover art

/// Shares a recording's audio file as it is: the cover is already in it (`AudioExport.embedCover`),
/// so the share sheet opens at once. The preview shows the cover when it has been made.
struct AudioShareLink<Label: View>: View {
    let recording: Recording
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let audio = recording.audio, !recording.audioIsLocal {
            // Still in iCloud: download it first; the next time this menu opens, it shares.
            Button("Download audio", systemImage: "icloud.and.arrow.down") {
                Task {
                    try? await Playback.ensureDownloaded(audio)
                    await Library.shared.refresh(except: Recorder.shared.folder)
                }
            }
        } else if let audio = recording.audio {
            if let cover = coverImage {
                ShareLink(item: audio, preview: SharePreview(recording.title, image: cover), label: label)
            } else {
                ShareLink(item: audio, label: label)
            }
        }
    }

    private var coverImage: Image? {
        let name = ".cover-\(CoverArt.key(for: recording)).jpg"
        return UIImage(contentsOfFile: recording.folder.appending(path: name).path).map(Image.init(uiImage:))
    }
}

/// What the share menu makes of the document (specs/share.md).
enum ShareFormat {
    case pdf, text, markdown, print
}

struct ShareChoice: Identifiable {
    let id = UUID()
    let format: ShareFormat
    let parts: [Summaries.Part]
}

/// "What do you want to share?": a check per summary and the transcript, all on (not
/// remembered), and one button that shares or prints what is checked (specs/share.md).
struct ShareChooser: View {
    let format: ShareFormat
    let parts: [Summaries.Part]
    let transcript: Transcript
    let onPrint: ([Summaries.Part], Bool) -> Void
    @State private var unchecked: Set<URL> = []
    @State private var withTranscript = true
    @Environment(\.dismiss) private var dismiss

    private var chosen: [Summaries.Part] { parts.filter { !unchecked.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(parts) { part in
                    row(part.name, isOn: !unchecked.contains(part.id)) {
                        if unchecked.contains(part.id) { unchecked.remove(part.id) } else { unchecked.insert(part.id) }
                    }
                }
                row(String(localized: "Transcript"), isOn: withTranscript) { withTranscript.toggle() }
                    .accessibilityIdentifier("chooserTranscript")
            }
            .navigationTitle("What do you want to share?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // The system close button (an xmark) leaves room for the whole question.
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("chooserClose")
                }
            }
            .safeAreaInset(edge: .bottom) {
                action
                    .buttonStyle(.glassProminent)
                    .tint(Color("ButtonAccent"))
                    .controlSize(.large)
                    .disabled(chosen.isEmpty && !withTranscript)
                    .accessibilityIdentifier("shareChooserButton")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .presentationDetents([.height(fittedHeight), .large])
    }

    /// Tall enough for the rows and the button, no empty space below them.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 52
    private var fittedHeight: CGFloat { CGFloat(parts.count + 1) * rowHeight + 210 }

    private func row(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        // Plain: the label in the primary colour, not the tint (only the check is tinted).
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private var action: some View {
        let summaries = chosen, turns = withTranscript
        switch format {
        case .pdf:
            ShareLink(item: SharedPDF(transcript: transcript, summaries: summaries, turns: turns),
                      preview: SharePreview(transcript.title)) { label("Share PDF") }
        case .text:
            ShareLink(item: SharedText(transcript: transcript, summaries: summaries, turns: turns),
                      preview: SharePreview(transcript.title)) { label("Share Text") }
        case .markdown:
            ShareLink(item: SharedText(transcript: transcript, summaries: summaries, turns: turns, markdown: true),
                      preview: SharePreview(transcript.title)) { label("Share Markdown") }
        case .print:
            Button { onPrint(summaries, turns) } label: { label("Print") }
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title).frame(maxWidth: .infinity)
    }

    /// The system's print dialog for a PDF (a popover from the toolbar on iPad).
    static func print(_ pdf: Data, title: String) {
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = title
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        if UIDevice.current.userInterfaceIdiom == .pad, let view = window?.rootViewController?.view {
            let anchor = CGRect(x: view.bounds.maxX - 60, y: view.safeAreaInsets.top + 8, width: 1, height: 1)
            _ = controller.present(from: anchor, in: view, animated: true)
        } else {
            _ = controller.present(animated: true)
        }
    }
}

struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The web page for the share sheet, with Band·je's cassette and the recording's title in the
/// sheet's header instead of a tiny page thumbnail.
final class WebPageItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    private let icon: UIImage?

    @MainActor init(url: URL, title: String) {
        self.url = url
        self.title = title
        icon = WebExport.logoPNG().flatMap(UIImage.init(data:))
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { url }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { url }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        if let icon { metadata.iconProvider = NSItemProvider(object: icon) }
        return metadata
    }
}

/// The system share sheet for a file that is made first (the web page).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The transcript as text, `<title>.txt` (or `.md`), made and written only when shared.
struct SharedText: Transferable {
    let transcript: Transcript
    /// The chosen summaries, before the turns (specs/share.md); `turns: false` leaves the turns out.
    var summaries: [Summaries.Part] = []
    var turns = true
    var markdown = false

    static var transferRepresentation: some TransferRepresentation {
        // `UTType.markdown` needs iOS 27; the system declares the type itself.
        FileRepresentation(exportedContentType: UTType(importedAs: "net.daringfireball.markdown", conformingTo: .utf8PlainText)) { item in try file(item) }
            .exportingCondition { $0.markdown }
        FileRepresentation(exportedContentType: .utf8PlainText) { item in try file(item) }
            .exportingCondition { !$0.markdown }
    }

    private static func file(_ item: SharedText) throws -> SentTransferredFile {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Share/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(Storage.safeName(item.transcript.title)).\(item.markdown ? "md" : "txt")")
        // Made only when shared, not on every pass of the menu that offers it.
        let text = item.markdown ? TranscriptWriter.markdown(item.transcript, summaries: item.summaries, turns: item.turns)
                                 : TranscriptWriter.plainText(item.transcript, summaries: item.summaries, turns: item.turns)
        try Data(text.utf8).write(to: file, options: .atomic)
        return SentTransferredFile(file)
    }
}


/// The transcript as a PDF (A4): the title, the header lines, then per turn the time and speaker
/// in bold with the text under it. Made on the device when shared.
struct SharedPDF: Transferable {
    let transcript: Transcript
    /// The chosen summaries, before the turns (specs/share.md); `turns: false` leaves the turns out.
    var summaries: [Summaries.Part] = []
    var turns = true

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let folder = FileManager.default.temporaryDirectory.appending(path: "Share/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "\(Storage.safeName(item.transcript.title)).pdf")
            let brand = await MainActor.run { SharedPDF.brandImages() }
            try pdf(item.transcript, summaries: item.summaries, turns: item.turns,
                    wordmark: brand.wordmark, cassette: brand.cassette).write(to: file, options: .atomic)
            return SentTransferredFile(file)
        }
    }

    /// The Band●je wordmark and the cassette, rendered light (the PDF is white paper).
    @MainActor static func brandImages() -> (wordmark: UIImage?, cassette: UIImage?) {
        func render(_ view: some View) -> UIImage? {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
            renderer.scale = 4
            return renderer.uiImage
        }
        return (render(BrandMark(size: 22).foregroundStyle(.black).padding(1)),
                render(CassetteView(state: CassetteState()).frame(width: 64)))
    }

    nonisolated static func pdf(_ t: Transcript, summaries: [Summaries.Part] = [], turns includeTurns: Bool = true,
                                wordmark: UIImage? = nil, cassette: UIImage? = nil) -> Data {
        let text = NSMutableAttributedString()
        func add(_ string: String, _ font: UIFont, _ color: UIColor = .black, after: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.lineSpacing = 2
            text.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        /// A summary line with its inline Markdown: bold and italic kept, the markup itself not.
        func addInline(_ markdown: String, size: CGFloat, weight: UIFont.Weight = .regular, prefix: String = "",
                       indent: CGFloat = 0, after: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.lineSpacing = 2
            style.headIndent = indent
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let line = NSMutableAttributedString(string: prefix, attributes: [.font: base, .foregroundColor: UIColor.black, .paragraphStyle: style])
            let parsed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(markdown)
            for run in parsed.runs {
                var font = base
                let intent = run.inlinePresentationIntent ?? []
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if !traits.isEmpty, let d = base.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: d, size: size) }
                line.append(NSAttributedString(string: String(parsed[run.range].characters),
                                               attributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style]))
            }
            line.append(NSAttributedString(string: "\n", attributes: [.font: base, .paragraphStyle: style]))
            text.append(line)
        }
        let grey = UIColor(white: 0.4, alpha: 1)
        add(t.title, .systemFont(ofSize: 20, weight: .bold), after: 6)
        let header = TranscriptWriter.headerLines(t)
        for (i, line) in header.enumerated() {
            add(line, .systemFont(ofSize: 10), grey, after: i == header.count - 1 ? 18 : 1)
        }
        for summary in summaries {
            add(summary.heading, .systemFont(ofSize: 15, weight: .bold), after: 8)
            let blocks = Summaries.blocks(summary.body)
            for (i, block) in blocks.enumerated() {
                let last = i == blocks.count - 1
                switch block {
                case .heading(let s): addInline(s, size: 12.5, weight: .semibold, after: last ? 22 : 4)
                case .bullet(let s): addInline(s, size: 11.5, prefix: "•  ", indent: 12, after: last ? 22 : 3)
                case .paragraph(let s): addInline(s, size: 11.5, after: last ? 22 : 8)
                }
            }
            if blocks.isEmpty { add("", .systemFont(ofSize: 11.5), after: 14) }
        }
        let turns = includeTurns ? TranscriptWriter.joinConsecutive(t.segments) : []
        if includeTurns, !summaries.isEmpty { add(String(localized: "Transcript"), .systemFont(ofSize: 15, weight: .bold), after: 8) }
        if includeTurns, turns.isEmpty { add(String(localized: "No speech recognised."), .italicSystemFont(ofSize: 11), grey) }
        let flags = TranscriptWriter.markerLines(t, turns: turns)
        // The markers in Band·je's red (specs/markers.md 6).
        let red = UIColor(red: 0xD2 / 255, green: 0x44 / 255, blue: 0x2A / 255, alpha: 1)
        for (i, seg) in turns.enumerated() {
            let time = TranscriptWriter.shortClock(seg.start)
            add(seg.speaker.isEmpty ? time : "\(time) · \(t.name(of: seg.speaker))", .systemFont(ofSize: 10.5, weight: .semibold), grey, after: 2)
            let lines = flags[i] ?? []
            add(seg.text, .systemFont(ofSize: 11.5), after: lines.isEmpty ? 12 : 4)
            // Under the paragraph, as in the transcript screen.
            for (n, line) in lines.enumerated() {
                add(line, .systemFont(ofSize: 10.5, weight: .medium), red, after: n == lines.count - 1 ? 12 : 4)
            }
        }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842), margin: CGFloat = 56
        let brandBand: CGFloat = 54, footer: CGFloat = 30  // the brand above the title (page 1), the footer line
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let top = containers.isEmpty ? brandBand : 0
            let container = NSTextContainer(size: CGSize(width: page.width - 2 * margin, height: page.height - 2 * margin - top - footer))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 2000

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: t.title, kCGPDFContextCreator as String: "Band·je"]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            let accent = UIColor(red: 0xD2 / 255, green: 0x44 / 255, blue: 0x2A / 255, alpha: 1)
            let navy = UIColor(red: 0x26 / 255, green: 0x2B / 255, blue: 0x4F / 255, alpha: 1)
            for (n, container) in containers.enumerated() {
                context.beginPage()
                if n == 0 {
                    // Band●je top left, the cassette top right, a red rule under them.
                    if let wordmark {
                        let h: CGFloat = 26, w = h * wordmark.size.width / max(1, wordmark.size.height)
                        wordmark.draw(in: CGRect(x: margin, y: margin, width: w, height: h))
                    }
                    if let cassette {
                        let w: CGFloat = 48, h = w * cassette.size.height / max(1, cassette.size.width)
                        cassette.draw(in: CGRect(x: page.width - margin - w, y: margin - 2, width: w, height: h))
                    }
                    accent.setFill()
                    UIRectFill(CGRect(x: margin, y: margin + brandBand - 14, width: page.width - 2 * margin, height: 1.5))
                }
                let range = layout.glyphRange(for: container)
                let origin = CGPoint(x: margin, y: margin + (n == 0 ? brandBand : 0))
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
                // Footer: where it was made, and the page.
                let y = page.height - margin + 4
                UIColor(white: 0.85, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y - 8, width: page.width - 2 * margin, height: 0.5))
                let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5, weight: .medium), .foregroundColor: navy]
                NSAttributedString(string: String(localized: "Recorded with Bandje · band.je"), attributes: small)
                    .draw(at: CGPoint(x: margin, y: y))
                let number = NSAttributedString(string: "\(n + 1) / \(containers.count)", attributes: small)
                number.draw(at: CGPoint(x: page.width - margin - number.size().width, y: y))
            }
        }
    }
}

/// Reload the markers when the recording changes or the library rescanned.
private struct MarkersKey: Equatable {
    let folder: URL
    let scan: Int
}
