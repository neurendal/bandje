// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A transcript read from disk, with its display layout computed once.
struct LoadedTranscript: Equatable {
    let json: URL
    let transcript: Transcript
    let turns: [TranscriptTurn]

    init(json: URL, transcript: Transcript) {
        self.json = json
        self.transcript = transcript
        turns = TranscriptLayout.turns(transcript)
    }
}

/// The transcript: one paragraph per turn with the speaker and time. The sentence that is
/// playing is highlighted and scrolled to while playing; tapping a sentence seeks to it.
struct TranscriptBody: View {
    @Environment(\.colorScheme) private var colorScheme
    let transcript: Transcript
    let turns: [TranscriptTurn]
    let position: TimeInterval
    let following: Bool
    let query: String
    let matchIndex: Int
    /// How far the text is scrolled (the player folds when reading on).
    var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }
    let onSeek: (TimeInterval) -> Void

    nonisolated static let seekScheme = "bandje-seek"

    /// Sentences containing `query`, in order (turn, sentence).
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
                LazyVStack(alignment: .leading, spacing: 20) {
                    if turns.isEmpty {
                        Text("No speech recognised.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(turns) { turn in
                        TurnView(turn: turn, dark: colorScheme == .dark,
                                 name: turn.speaker.isEmpty || turn.continued ? "" : transcript.name(of: turn.speaker),
                                 time: clock(turn.start),
                                 activeSentence: active?.turn == turn.id ? active?.sentence : nil,
                                 query: query,
                                 currentMatch: current?.turn == turn.id ? current?.sentence : nil)
                            .equatable()
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .reportsUserScroll(onScroll)
            .fadingTopEdge()
            .onAppear {
                // Opened halfway (playing or paused there): start at the current sentence.
                guard position > 0, query.isEmpty, let turn = active?.turn else { return }
                proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25))
            }
            .onChange(of: active?.turn) { _, turn in
                guard following, query.isEmpty, let turn else { return }
                withAnimation(.smooth) { proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25)) }
            }
            .onChange(of: current?.turn) { _, turn in
                guard let turn else { return }
                withAnimation(.smooth) { proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25)) }
            }
            .onChange(of: matchIndex) { _, _ in
                guard let turn = current?.turn else { return }
                withAnimation(.smooth) { proxy.scrollTo(turn, anchor: UnitPoint(x: 0.5, y: 0.25)) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.seekScheme,
                  let time = Double(url.absoluteString.dropFirst(Self.seekScheme.count + 1)) else { return .systemAction }
            onSeek(time)
            return .handled
        })
    }
}

/// One speaker turn. Equatable so only the turn whose highlight changes is redrawn.
struct TurnView: View, Equatable {
    let turn: TranscriptTurn
    /// Dark mode: a stronger highlight (a property, so the view stays Equatable).
    var dark = false
    let name: String
    let time: String
    let activeSentence: Int?
    let query: String
    let currentMatch: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !name.isEmpty {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(attributed)
                .tint(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Each sentence is a link to its start time (tap = seek).
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
                // The sentence playing (owner: following the sentence reads better than the block).
                // On black a faint red disappears: stronger in dark mode.
                part.backgroundColor = Color.accentColor.opacity(dark ? 0.42 : 0.18)
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
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcript", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { next(1) }
                    .accessibilityIdentifier("transcriptSearchField")
                if !query.isEmpty {
                    Text(count == 0 ? "0" : "\(min(matchIndex, count - 1) + 1)/\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary, in: Capsule())
            Button("Previous match", systemImage: "chevron.up") { next(-1) }
                .labelStyle(.iconOnly)
                .disabled(count < 2)
            Button("Next match", systemImage: "chevron.down") { next(1) }
                .labelStyle(.iconOnly)
                .disabled(count < 2)
            Button("Done", action: close)
        }
        .onChange(of: query) { _, _ in matchIndex = 0 }
        .onAppear { focused = true }
    }

    private func next(_ step: Int) {
        guard count > 0 else { return }
        matchIndex = (matchIndex + step + count) % count
    }
}

/// No transcript yet: one button, whether to recognise speakers, one line about language.
struct TranscribePrompt: View {
    let error: String?
    let start: (Bool) -> Void
    @AppStorage("detectSpeakers") private var detectSpeakers = true

    var body: some View {
        VStack(spacing: 14) {
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                start(detectSpeakers)
            } label: {
                Label("Transcribe", systemImage: "text.quote")
                    .frame(minWidth: 160)
            }
            // Quieter than play, the main action on this screen.
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityIdentifier("transcribeButton")
            Toggle("Recognise speakers", isOn: $detectSpeakers)
                .tint(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 420)
                .padding(.top, 4)
            Text("The language is recognised automatically. Everything stays on this \(Device.name).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct TranscriptionProgress: View {
    let phase: Transcriber.Phase
    let cancel: () -> Void

    var body: some View {
        let fraction = Transcriptions.fraction(phase)
        VStack(spacing: 10) {
            ProgressView(value: fraction)
                .tint(Color.progress)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if firstTime {
                        Text("Only the first time after installing or updating: this takes about a minute.")
                            .font(.caption)
                    }
                }
                Spacer()
                if showsPercent {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .accessibilityIdentifier("transcriptionPercent")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel, action: cancel)
                .buttonStyle(.glass)
                .accessibilityIdentifier("cancelTranscription")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcriptionProgress")
    }

    private var showsPercent: Bool {
        switch phase {
        case .transcribing, .speakers: true
        default: false
        }
    }

    private var firstTime: Bool {
        switch phase {
        case .loading(let first), .speakers(let first, _): first
        default: false
        }
    }

    private var label: LocalizedStringKey {
        switch phase {
        case .waiting: "Waiting…"
        case .loading: "Preparing the speech model…"
        case .transcribing: "Transcribing…"
        case .speakers: "Recognising speakers…"
        }
    }
}

extension View {
    /// The scroll offset while the reader scrolls (not when the app scrolls to the sentence playing).
    func reportsUserScroll(_ action: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        modifier(UserScroll(action: action))
    }

    /// Text that scrolls under the top edge fades out instead of being cut through a line.
    func fadingTopEdge(_ height: CGFloat = 32) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: height)
                Rectangle()
            }
        }
    }
}

private struct UserScroll: ViewModifier {
    /// Offset and overflow (content height beyond the visible height).
    let action: (CGFloat, CGFloat) -> Void
    @State private var byUser = false

    struct Metrics: Equatable {
        var y: CGFloat
        var overflow: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in byUser = phase == .interacting || phase == .decelerating || phase == .tracking }
            .onScrollGeometryChange(for: Metrics.self) { g in
                Metrics(y: g.contentOffset.y + g.contentInsets.top,
                        overflow: g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height)
            } action: { _, m in
                if byUser { action(m.y, m.overflow) }
            }
    }
}

// MARK: - Summary

/// Identifies the summary to load: its file and how many summaries were written since launch.
struct SummaryKey: Hashable {
    let file: URL?
    let generation: Int
}

/// The summary: headings, bullets and paragraphs, selectable.
struct SummaryBody: View {
    let blocks: [Summaries.Block]
    var template: String? = nil
    /// "Summarise again" under the summary, with a template of choice (empty: not offered).
    var templates: [Summaries.Template] = []
    var again: (Summaries.Template) -> Void = { _ in }
    var manage: (() -> Void)? = nil
    var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let template {
                    Label(template, systemImage: "doc.text")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                        .accessibilityLabel(Text("Template \(template)"))
                }
                ForEach(blocks.indices, id: \.self) { i in
                    switch blocks[i] {
                    case .heading(let text):
                        Text(Self.inline(text))
                            .font(.headline)
                            .padding(.top, i == 0 ? 0 : 12)
                            .accessibilityAddTraits(.isHeader)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "•").foregroundStyle(.tint)
                            Text(Self.inline(text))
                        }
                    case .paragraph(let text):
                        Text(Self.inline(text))
                    }
                }
                Text("Made with Apple Intelligence on this \(Device.name).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                if !templates.isEmpty {
                    Menu {
                        TemplateChoices(templates: templates, choose: again, manage: manage)
                    } label: {
                        Label("Summarise again", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
                    .accessibilityIdentifier("summarizeAgain")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .reportsUserScroll(onScroll)
        .fadingTopEdge()
        .accessibilityIdentifier("summaryBody")
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// No summary yet: a button that opens the templates, and one line about where it is made.
struct SummarizePrompt: View {
    let error: String?
    let start: (Summaries.Template) -> Void
    @State private var templates: [Summaries.Template] = []
    @State private var managing = false

    var body: some View {
        VStack(spacing: 14) {
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Menu {
                TemplateChoices(templates: templates, choose: start) { managing = true }
            } label: {
                Label("Summarise", systemImage: "sparkles")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.glassProminent)
            .tint(Color("ButtonAccent"))  // white text at ≥ 4.5:1 in light and dark
            .controlSize(.large)
            .accessibilityIdentifier("summarizeButton")
            Text("Apple Intelligence makes the summary on this \(Device.name).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            OnDeviceSummarizer.prewarm()
            templates = Summaries.templates()
        }
        .sheet(isPresented: $managing, onDismiss: { templates = Summaries.templates() }) { TemplatesSheet() }
    }
}

/// The templates as menu items: the last one used first, then the rest by name.
struct TemplateChoices: View {
    let templates: [Summaries.Template]
    let choose: (Summaries.Template) -> Void
    /// "Edit templates…" at the bottom: the templates in a sheet.
    var manage: (() -> Void)? = nil

    var body: some View {
        let last = Summaries.lastTemplate
        let ordered = templates.filter { $0.name == last } + templates.filter { $0.name != last }
        Section("Template") {
            ForEach(ordered, id: \.name) { template in
                Button(template.name) { choose(template) }
            }
        }
        if let manage {
            Button("Edit templates…", systemImage: "square.and.pencil", action: manage)
        }
    }
}

/// Settings › Templates on its own, from the template menus.
struct TemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TemplatesView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct SummaryProgress: View {
    let fraction: Double
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: fraction)
                .tint(Color.progress)
            HStack {
                Text("Summarising…")
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel, action: cancel)
                .buttonStyle(.glass)
                .accessibilityIdentifier("cancelSummary")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summaryProgress")
    }
}

// MARK: - Naming speakers

/// Per speaker the longest turn as a quote and a clip (≤ 12 s), and a name field. Saving
/// rewrites the `.json` and `.md`; one name changes every label of that speaker.
struct SpeakerNamingSheet: View {
    let transcript: Transcript
    let json: URL
    let recording: Recording
    let onSave: (Transcript) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(Player.self) private var player
    @Environment(Recorder.self) private var recorder
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
        NavigationStack {
            Form {
                Section {
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                toggle(row)
                            } label: {
                                Image(systemName: playing == row.label ? "stop.fill" : "play.fill")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .disabled(recorder.isActive)
                            .accessibilityLabel(Text("Play \(row.label)"))
                            VStack(alignment: .leading, spacing: 6) {
                                // A visible field: you can see the name is yours to type.
                                TextField(row.label, text: $row.name, prompt: Text(row.label))
                                    .font(.headline)
                                    .textInputAutocapitalization(.words)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .trailing) {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(.tertiary)
                                            .padding(.trailing, 10)
                                            .accessibilityHidden(true)
                                    }
                                Text("“\(row.quote)”")
                                    .font(.footnote)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Listen to a fragment and type a name. Every label of that speaker changes along.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Name speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveSpeakers")
                }
            }
        }
        // As tall as its content (a few speakers leave no empty half sheet); more speakers scroll.
        .presentationDetents([.height(CGFloat(170 + 132 * max(1, Self.rows(for: transcript).count))), .large])
        .onAppear { rows = Self.rows(for: transcript) }
        .onDisappear { stopClip() }
    }

    private func toggle(_ row: Row) {
        if playing == row.label { stopClip(); return }
        stopClip()
        player.load(recording)
        player.seek(to: max(0, row.start - 0.2))
        player.play()
        playing = row.label
        let length = min(row.end - row.start + 0.4, Self.clipSeconds)
        clipStop = Task {
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            stopClip()
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
            try TranscriptWriter.write(updated, json: json)
            onSave(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
