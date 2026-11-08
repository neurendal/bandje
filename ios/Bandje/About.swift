// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Settings and about (SPEC 3.4): version, settings, privacy, phone calls, the Desert Ant Labs
/// attribution with the model licences (CLAUDE.md 6, texts from the Mac `About.swift`), and the
/// three links. These links are the only URLs in our code; they open the browser.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("detectSpeakers") private var detectSpeakers = true
    @AppStorage(LocationTag.settingKey) private var saveLocation = false
    private var sync = CloudSync.shared

    private static let neurendal = URL(string: "https://neurendal.com")!
    private static let website = URL(string: "https://band.je")!
    private static let support = URL(string: "https://band.je/support")!
    private static let privacy = URL(string: "https://band.je/privacy")!

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        CassetteView(state: CassetteState(title: "Band·je"))
                            .frame(width: 150)
                            .accessibilityHidden(true)
                        Text("Bandje")
                            .font(.title2.weight(.bold))
                        Text(version)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Records, transcribes and summarises on your \(Device.name).")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Transcribe automatically", isOn: $autoTranscribe)
                        .accessibilityIdentifier("autoTranscribeToggle")
                        .tint(.green)
                    Toggle("Recognise speakers", isOn: $detectSpeakers)
                        .tint(.green)
                    LabeledContent("Language", value: String(localized: "Automatic"))
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Automatically after recording and importing. The language is recognised by itself (25 languages).")
                }

                Section {
                    Toggle(isOn: Binding(get: { sync.isOn }, set: { on in
                        Task { on ? await sync.turnOn() : await sync.turnOff() }
                    })) {
                        HStack {
                            Text("Sync with iCloud")
                                // Unavailable (no iCloud Drive) reads differently from off.
                                .foregroundStyle(sync.isAvailable ? .primary : .secondary)
                            if sync.isBusy { ProgressView().padding(.leading, 4) }
                        }
                    }
                    .tint(.green)
                    .disabled(!sync.isAvailable || sync.isBusy)
                    .accessibilityIdentifier("iCloudToggle")
                    if let error = sync.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Recordings")
                } footer: {
                    Text(sync.isAvailable
                         ? "Recordings, transcripts and summaries go to iCloud Drive › Bandje and appear on your other devices. Apple encrypts them end to end when Advanced Data Protection is on. Turning it off keeps everything in iCloud."
                         : "Sign in to iCloud and turn on iCloud Drive in Settings to sync recordings with your other devices.")
                }

                if OnDeviceSummarizer.isAvailable {
                    Section {
                        NavigationLink {
                            TemplatesView()
                        } label: {
                            Label("Templates", systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityIdentifier("templatesLink")
                    } header: {
                        Text("Summaries")
                    } footer: {
                        Text("Pick a template when you summarise. With Sync with iCloud on, the templates are shared with Band·je on your Mac.")
                    }
                }

                Section {
                    Toggle("Store GPS location", isOn: $saveLocation)
                        .tint(.green)
                        .onChange(of: saveLocation) { _, on in
                            // Asks for permission now rather than at the next recording.
                            if on { Task { _ = await LocationTag.current(timeout: .seconds(30)) } }
                        }
                } footer: {
                    Text("Saves where a recording was made, with the recording on this \(Device.name). Not included when you share audio.")
                }

                // The privacy policy lives on band.je (owner, 6 Nov); it opens in Safari, as the other links do.
                Section("Privacy") {
                    Link(destination: Self.privacy) { Label("Privacy policy", systemImage: "hand.raised") }
                        .accessibilityIdentifier("privacyLink")
                    if !OnDeviceSummarizer.isAvailable {
                        Text("Summarising needs Apple Intelligence.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if Device.name == "iPhone" {
                    Section("Phone calls") {
                        Text("Phone call? Record it with the button in the Phone app, then share the recording from Notes to Bandje.")
                            .font(.subheadline)
                    }
                }

                Section {
                    Text("Speech recognition (Voz) and speaker recognition (Who) by Desert Ant Labs (https://desertant.com)")
                        .font(.subheadline)
                    model(String(localized: "Speech recognition"), "Voz \(Transcriber.vozVersion)", "NVIDIA Parakeet TDT 0.6B v3")
                    model(String(localized: "Speaker recognition"), "Who \(Transcriber.whoVersion)", "pyannote community-1")
                    LabeledContent("SDK", value: "desert-ant-core \(Transcriber.sdkVersion)")
                        .font(.subheadline)
                } header: {
                    Text("Models")
                }

                Section {
                    Link(destination: Self.support) { Label("Questions and support", systemImage: "questionmark.circle") }
                    Link(destination: Self.website) { Label("band.je", systemImage: "globe") }
                    Link(destination: Self.neurendal) { Label("neurendal.com", systemImage: "building.2") }
                } footer: {
                    Text("Made by Neurendal B.V. · © 2026 · Source code: GPL-3.0")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .tint(.accentColor)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("aboutDone")
                }
            }
        }
    }

    /// One model: what it does, name and version, what it is based on, and its licence.
    private func model(_ heading: String, _ name: String, _ basedOn: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.subheadline.weight(.medium))
            Text("Based on \(basedOn) · CC BY 4.0")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The summary templates: one per file in `Templates/` (shared with the Mac through iCloud).
struct TemplatesView: View {
    @State private var templates: [Summaries.Template] = []
    @State private var editing: Summaries.Template?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(templates, id: \.name) { template in
                    Button {
                        editing = template
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).foregroundStyle(.primary)
                            Text(headings(template))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .tint(.primary)  // names in the text colour, not the accent
                }
                .onDelete { offsets in
                    for i in offsets { Summaries.deleteTemplate(templates[i].name) }
                    reload()
                }
            } footer: {
                Text("A template is a list of headings (## Heading) with a line under each about what goes there. Keep it short: the model on your \(Device.name) has little room.")
            }
            Section {
                Button("Restore the examples", systemImage: "arrow.uturn.backward") {
                    Summaries.restoreExamples()
                    reload()
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New template", systemImage: "plus") { adding = true }
                    .accessibilityIdentifier("newTemplate")
            }
        }
        .sheet(item: Binding(get: { editing.map(EditedTemplate.init) }, set: { editing = $0?.template })) { item in
            TemplateEditor(original: item.template) { reload() }
        }
        .sheet(isPresented: $adding) {
            TemplateEditor(original: nil) { reload() }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        // The folder may not exist yet (no examples written): show what summaries would use.
        templates = Summaries.templates()
    }

    private func headings(_ t: Summaries.Template) -> String {
        t.text.split(separator: "\n").filter { $0.hasPrefix("#") }
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ")
    }

    private struct EditedTemplate: Identifiable {
        let template: Summaries.Template
        var id: String { template.name }
    }
}

/// Edit or add a template: its name (the file name) and its text.
struct TemplateEditor: View {
    let original: Summaries.Template?
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("templateName")
                }
                Section {
                    TextEditor(text: $text)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 280)
                        .accessibilityIdentifier("templateText")
                } header: {
                    Text("Template")
                } footer: {
                    Text("## Heading, then a line about what goes under it.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(original == nil ? Text("New template") : Text(original!.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(Summaries.safeName(name).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveTemplate")
                }
            }
        }
        .onAppear {
            name = original?.name ?? ""
            text = original?.text ?? "## \(String(localized: "Summary"))\n\(String(localized: "The main points in two or three sentences."))\n\n"
        }
    }

    private func save() {
        do {
            // Make sure the folder (and the other examples) exist before writing the first own one.
            Summaries.seedIfMissing()
            try Summaries.saveTemplate(Summaries.Template(name: Summaries.safeName(name), text: text), replacing: original?.name)
            saved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Apple's review prompt (StoreKit `requestReview`, no network in our code): after the 3rd and the
/// 10th finished transcription, when leaving that recording; at most once per app version. Apple
/// itself shows it at most three times a year, or not at all. Never in tests or selftests.
enum ReviewPrompt {
    static let thresholds = [3, 10]
    private static let countKey = "finishedTranscriptions", askedKey = "reviewAskedAt", versionKey = "reviewAskedVersion"

    static func transcriptionDone(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static func shouldAsk(defaults: UserDefaults = .standard, version: String = appVersion, automated: Bool = isAutomated) -> Bool {
        guard !automated else { return false }
        let count = defaults.integer(forKey: countKey)
        let asked = defaults.integer(forKey: askedKey)
        guard let due = thresholds.last(where: { count >= $0 }), due > asked else { return false }
        return defaults.string(forKey: versionKey) != version
    }

    static func markAsked(defaults: UserDefaults = .standard, version: String = appVersion) {
        let count = defaults.integer(forKey: countKey)
        defaults.set(thresholds.last(where: { count >= $0 }) ?? 0, forKey: askedKey)
        defaults.set(version, forKey: versionKey)
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    static var isAutomated: Bool {
        #if DEBUG
        if !Selftest.options.isEmpty { return true }
        #endif
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// The welcome, once: what Band·je does, iCloud and location (both off unless turned on here), and
/// the notice about telling people you record (which replaces the alert before the first recording).
/// The microphone is asked for at the first recording, as Apple wants.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocationTag.settingKey) private var saveLocation = false
    @State private var syncOn = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var sync = CloudSync.shared

    static let doneKey = "onboarded"

    /// First launch only. People who already recorded (the notice was shown) don't see it, nor do
    /// tests and selftests (they start with arguments).
    static var isNeeded: Bool {
        if UserDefaults.standard.bool(forKey: doneKey) { return false }
        if RecordingCommands.consentShown {
            UserDefaults.standard.set(true, forKey: doneKey)
            return false
        }
        return !ReviewPrompt.isAutomated
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 14) {
                    // Closed and lying down (a low screen): a smaller cassette, or none.
                    ViewThatFits(in: .vertical) {
                        CassetteView(state: CassetteState(title: "Band·je")).frame(width: 200)
                        CassetteView(state: CassetteState(title: "Band·je")).frame(width: 120)
                        EmptyView()
                    }
                    .frame(maxHeight: verticalSizeClass == .compact ? 80 : 140)
                    .accessibilityHidden(true)
                    Text("Welcome to Band·je")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, verticalSizeClass == .compact ? 12 : 36)

                VStack(alignment: .leading, spacing: 18) {
                    point("record.circle", "Record with one tap", "From the app, Control Centre, the Lock Screen or with Siri.")
                    point("text.quote", "Who said what", "Transcription in 25 languages, with the speakers, on this device.")
                    if OnDeviceSummarizer.isAvailable {
                        point("sparkles", "Summaries in your template", "Made by Apple Intelligence on this device.")
                    }
                }
                .frame(maxWidth: Self.width, alignment: .leading)

                // GPS and iCloud together, as one list with a header.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Options")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 16)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        if sync.isAvailable {
                            Toggle(isOn: $syncOn) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sync with iCloud")
                                    Text("Your recordings on your Mac and iPad too.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .tint(.green)
                            .padding(.vertical, 12)
                            Divider()
                        }
                        Toggle(isOn: $saveLocation) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Store GPS location")
                                Text("Where a recording was made, with the recording.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: Self.width)

                Label {
                    Text("Tell people you are recording. In some countries, and at work, the law requires it, and sometimes their consent.")
                } icon: {
                    Image(systemName: "person.wave.2")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: Self.width, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)  // the last line scrolls clear of the button
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button(action: start) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: Self.width)  // as wide as the content above it
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .accessibilityIdentifier("onboardingStart")
        }
        // Open (iPad, an unfolded iPhone Duo): a form sheet, not over the whole screen.
        .presentationSizing(.form)
    }

    private static let width: CGFloat = 460

    private func point(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color("ButtonAccent"))
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        RecordingCommands.consentShown = true  // the notice was on this screen
        if syncOn { Task { await sync.turnOn() } }
        dismiss()
    }
}
