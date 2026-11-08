// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import FoundationModels
import NaturalLanguage
import Observation

// MARK: - Summaries (ported from the Mac app's Summarizer.swift)

/// Everything about summaries that does not touch the model (template, language, chunks,
/// prompts, output). Plain code, unit-tested.
enum Summaries {
    struct Template: Equatable, Sendable {
        var name: String
        var text: String
    }

    /// The app's language, which picks the example templates and the summary file's word; a
    /// language without its own examples gets the English ones.
    static var appLanguage: String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return catalog[language] != nil ? language : "en"
    }

    /// `SummaryTemplates.json`: per language the file word (the Mac app's, "samenvatting",
    /// "Zusammenfassung" …) and the example templates (scripts/dev/make-summary-templates.py).
    private static let catalog: [String: (word: String, templates: [Template])] = {
        struct Entry: Decodable {
            struct T: Decodable { let name: String; let text: String }
            let fileWord: String
            let templates: [T]
        }
        guard let url = Bundle.main.url(forResource: "SummaryTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries.mapValues { (word: $0.fileWord, templates: $0.templates.map { Template(name: $0.name, text: $0.text) }) }
    }()

    /// The default template: the first example ("Vergadering" / "Meeting").
    static func template(language: String = appLanguage) -> Template {
        examples(language: language)[0]
    }

    // MARK: Templates (the same files and examples as the Mac app)

    /// One source of truth, shared with the Mac (docs/icloud-sync.md): `iCloud Drive › Band·je ›
    /// Templates` while syncing, else `Documents/Templates` on this device (visible in Files).
    /// One `.md` or `.txt` file per template; the file name is the template's name.
    static var templatesFolder: URL {
        (Storage.cloud ?? Storage.documents).appending(path: "Templates", directoryHint: .isDirectory)
    }

    /// The templates in `folder`, sorted by name as Files does; empty files are skipped. Files
    /// still in iCloud start downloading. No templates at all: the built-in examples.
    static func templates(in folder: URL = templatesFolder, language: String = appLanguage) -> [Template] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for placeholder in files where placeholder.lastPathComponent.hasPrefix(".") && placeholder.pathExtension == "icloud" {
            let real = folder.appending(path: String(placeholder.deletingPathExtension().lastPathComponent.dropFirst()))
            try? fm.startDownloadingUbiquitousItem(at: real)
        }
        let found = files
            .filter { !$0.lastPathComponent.hasPrefix(".") && ["md", "txt"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> Template? in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Template(name: url.deletingPathExtension().lastPathComponent, text: text)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return found.isEmpty ? examples(language: language) : found
    }

    /// Creates `folder` with the three examples when it does not exist yet; an existing folder
    /// (also an empty one) is the user's and stays as it is (as on the Mac).
    static func seedIfMissing(_ folder: URL = templatesFolder, language: String = appLanguage) {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for t in examples(language: language) {
            try? Data(t.text.utf8).write(to: folder.appending(path: t.name + ".md"), options: .withoutOverwriting)
        }
    }

    /// Writes a template (new or edited) as `<name>.md`; renaming removes the old file.
    static func saveTemplate(_ template: Template, replacing old: String? = nil, in folder: URL = templatesFolder) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: safeName(template.name) + ".md")
        try Storage.coordinated(writing: url, options: .forReplacing) { try Data(template.text.utf8).write(to: $0, options: .atomic) }
        if let old, safeName(old) != safeName(template.name) { deleteTemplate(old, in: folder) }
    }

    static func deleteTemplate(_ name: String, in folder: URL = templatesFolder) {
        for ext in ["md", "txt"] {
            let url = folder.appending(path: safeName(name) + "." + ext)
            if FileManager.default.fileExists(atPath: url.path) {
                try? Storage.coordinated(writing: url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
            }
        }
    }

    /// Examples added in a later version ("Generic summary", 6 Nov 2026): written once into an
    /// existing folder (never over a file of that name), so people who had the folder get them too.
    static var laterExamples: Set<String> { Set(catalog.values.compactMap { $0.templates.count > 3 ? $0.templates[3].name : nil }) }

    static func addLaterExamples(in folder: URL = templatesFolder, language: String = appLanguage,
                                 defaults: UserDefaults = .standard) {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        for t in examples(language: language) where laterExamples.contains(t.name) {
            let key = "templateAdded.\(t.name)"
            guard !defaults.bool(forKey: key) else { continue }
            try? Data(t.text.utf8).write(to: folder.appending(path: t.name + ".md"), options: .withoutOverwriting)
            defaults.set(true, forKey: key)
        }
    }

    /// Puts the examples back (only the ones that are missing; edited ones stay).
    static func restoreExamples(in folder: URL = templatesFolder, language: String = appLanguage) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for t in examples(language: language) {
            try? Data(t.text.utf8).write(to: folder.appending(path: t.name + ".md"), options: .withoutOverwriting)
        }
    }

    /// Copies the templates from `source` into `target` without overwriting (sync turned on: this
    /// device's templates join the shared ones).
    static func mergeTemplates(from source: URL, into target: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files where ["md", "txt"].contains(file.pathExtension.lowercased()) {
            let destination = target.appending(path: file.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) { try? fm.copyItem(at: file, to: destination) }
        }
    }

    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last template chosen; the menu offers it first.
    static var lastTemplate: String? {
        get { UserDefaults.standard.string(forKey: "summaryTemplate") }
        set { UserDefaults.standard.set(newValue, forKey: "summaryTemplate") }
    }

    /// The example templates in `language` (English where it has none). Dutch and English are the
    /// Mac's, word for word.
    static func examples(language: String) -> [Template] {
        catalog[language]?.templates ?? catalog["en"]?.templates ?? []
    }



    // MARK: Transcript as text

    /// One line per turn, `[mm:ss] Name: text`, with the names the user gave.
    static func lines(_ t: Transcript) -> [String] {
        let long = t.duration >= 3600
        return TranscriptWriter.joinConsecutive(t.segments).map { seg in
            let time = "[\(TranscriptWriter.clock(seg.start, long: long))]"
            return seg.speaker.isEmpty ? "\(time) \(seg.text)" : "\(time) \(t.name(of: seg.speaker)): \(seg.text)"
        }
    }

    /// The language of the conversation, from the text itself; nil when unclear.
    static func language(of text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(20_000)))
        return r.dominantLanguage?.rawValue
    }

    /// The language's English name ("Dutch"), for the instructions.
    static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// Rough token count for packing chunks: about 3 characters per token is on the safe side for
    /// European languages (measured ±3.5 for Dutch).
    static func estimatedTokens(_ s: String) -> Int { s.count / 3 + 1 }

    /// Packs whole lines into chunks of at most `limit` tokens. A single line over the limit is cut
    /// at word boundaries, so no chunk is ever larger than the limit.
    static func chunks(_ lines: [String], limit: Int, tokens: (String) -> Int = estimatedTokens) -> [String] {
        var out: [String] = []
        var current: [String] = []
        var size = 0
        func flush() { if !current.isEmpty { out.append(current.joined(separator: "\n")); current = []; size = 0 } }
        for line in lines.flatMap({ split($0, limit: limit, tokens: tokens) }) {
            let n = tokens(line) + 1
            if size + n > limit { flush() }
            current.append(line)
            size += n
        }
        flush()
        return out
    }

    static func split(_ line: String, limit: Int, tokens: (String) -> Int) -> [String] {
        guard tokens(line) > limit else { return [line] }
        var parts: [String] = []
        var current = ""
        for word in line.split(separator: " ") {
            let next = current.isEmpty ? String(word) : current + " " + word
            if tokens(next) > limit, !current.isEmpty { parts.append(current); current = String(word) } else { current = next }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: Prompts (identical to the Mac app)

    /// The fixed rules plus the template. `fromNotes`: the input is notes, not a transcript.
    static func instructions(template: Template, language: String, fromNotes: Bool = false) -> String {
        let lang = languageName(language)
        let source = fromNotes ? "the notes" : "the transcript"
        return """
        You write a summary of a conversation for the person who recorded it.
        Rules:
        - Write in \(lang).
        - Use only information from \(source). Never invent names, numbers, amounts, dates or facts.
        - Follow the template below exactly: the same headings in the same order, in Markdown.
        - If \(source) has nothing for a heading, write "not discussed" in \(lang) under it.
        - Refer to people by the speaker names used in \(source).
        - Keep exact numbers, amounts and dates as they were said.
        - No introduction, no closing remarks, no remarks about these rules.

        Template:
        \(template.text.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    /// For one part of a long conversation: the facts that belong in the template, as bullets.
    static func noteInstructions(template: Template, language: String, part: Int, of parts: Int) -> String {
        let lang = languageName(language)
        return """
        You take notes from part \(part) of \(parts) of a conversation transcript. The notes are used later \
        to write a summary with the template below.
        Rules:
        - Write short bullets in \(lang), one fact per bullet, with the time [mm:ss] where it was said.
        - Note every fact from this part that belongs under any heading of the template: names, numbers, \
        amounts, dates, decisions, agreements, open questions, notable quotes.
        - Only facts from this part. Never invent anything. Use the speaker names from the transcript.
        - No headings, no introduction, nothing else.

        Template:
        \(template.text.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    /// The model sometimes copies a heading's description from the template into its answer, whole
    /// or as a lead-in before a colon. Such lines are removed, lead-ins cut off.
    static func removeTemplateEcho(_ body: String, template: Template) -> String {
        func norm(_ s: some StringProtocol) -> String {
            s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".:"))).lowercased()
        }
        let guidance = template.text.split(separator: "\n").map(norm).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        func isEcho(_ s: String) -> Bool { s.count >= 12 && guidance.contains { $0 == s || $0.hasPrefix(s) } }
        var out: [String] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if isEcho(norm(line)) { continue }
            if let colon = line.firstIndex(of: ":"), isEcho(norm(line[..<colon])) {
                line = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty, out.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true { continue }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Notes must be plain facts; headings in them (the model sometimes writes the template per
    /// part) make the final answer repeat the template once per part. Headings and empty lines go.
    static func cleanNotes(_ notes: String) -> [String] {
        notes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The template once: the answer is cut where a heading comes back that was already written
    /// (greedy decoding can loop through the template until the token limit).
    static func firstPass(_ body: String) -> String {
        var seen: Set<String> = []
        var out: [Substring] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") {
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                if !seen.insert(heading).inserted { break }
            }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Files

    /// The summary file's name word: "samenvatting" (NL) or "summary" (EN).
    static func fileWord(language: String = appLanguage) -> String { catalog[language]?.word ?? "summary" }

    /// Where a summary goes: `<folder>/<name> samenvatting <template>.md`, as the Mac names it (one
    /// file per template). Without a template: `<name> samenvatting.md` (older iPhone summaries).
    static func outputURL(in folder: URL, template: String? = nil, language: String = appLanguage) -> URL {
        let suffix = template.map { " " + safeName($0) } ?? ""
        return folder.appending(path: "\(folder.lastPathComponent) \(fileWord(language: language))\(suffix).md")
    }

    /// The summary of a recording folder: the newest `<name> <word>[ <template>].md` (Mac or iPhone),
    /// so a summary with another template shows right after it was made.
    static func file(in folder: URL) -> URL? {
        let fm = FileManager.default
        let prefix = folder.lastPathComponent + " "
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension.lowercased() == "md" }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.max { (modified($0), $1.lastPathComponent) < (modified($1), $0.lastPathComponent) }
    }

    /// The template a summary file was made with, from its name (`<name> samenvatting <template>.md`).
    static func templateName(of file: URL, in folder: URL) -> String? {
        let name = file.deletingPathExtension().lastPathComponent
        for word in Set(catalog.values.map(\.word)) {
            let prefix = "\(folder.lastPathComponent) \(word) "
            if name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Title, one line of metadata, a rule, the model's text.
    static func document(title: String, template: String, body: String, date: Date = Date(), locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMMMyyyyHHmm")
        let heading = String(localized: "Summary \(title)", comment: "Heading of a summary file: the recording's title")
        let meta = String(localized: "Template \(template) · \(f.string(from: date)) · made on this \(Device.name) with Apple Intelligence")
        return "# \(heading)\n\n_\(meta)_\n\n---\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// The model's text from a summary file written by `document` (everything after the first rule).
    static func body(ofDocument md: String) -> String {
        guard let r = md.range(of: "\n---\n") else { return md.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(md[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The body as blocks for display: headings, bullets and paragraphs (inline Markdown kept).
    enum Block: Equatable, Sendable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    static func blocks(_ body: String) -> [Block] {
        body.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") {
                return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
            }
            for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) {
                return .bullet(line.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces))
            }
            return .paragraph(line)
        }
    }
}

// MARK: - The on-device model (only SystemLanguageModel, never Private Cloud Compute)

enum OnDeviceSummarizer {
    /// Transcripts are content to transform, so the permissive guardrails for that use apply.
    private static var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    static var isAvailable: Bool {
        #if DEBUG
        if Selftest.options.fmUnavailable { return false }
        #endif
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// For the selftest: "available" or the reason it is not.
    static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available: "available"
        case .unavailable(let reason): "unavailable: \(reason)"
        }
    }

    static func supports(language: String) -> Bool {
        SystemLanguageModel.default.supportsLocale(Locale(identifier: language))
    }

    static func prewarm() {
        LanguageModelSession(model: model).prewarm()
    }

    /// The summary text for `t`. A conversation that does not fit the context window is cut into
    /// parts on turn boundaries: notes per part, then the summary from all notes.
    static func summarize(_ t: Transcript, template: Summaries.Template,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let lines = Summaries.lines(t)
        guard !lines.isEmpty else { throw TranscriptionError(message: String(localized: "This transcript has no text to summarise.")) }
        let text = lines.joined(separator: "\n")
        guard let language = Summaries.language(of: text) else {
            throw TranscriptionError(message: String(localized: "Bandje can’t tell which language this conversation is in."))
        }
        guard supports(language: language) else {
            let name = Locale.current.localizedString(forLanguageCode: language) ?? language
            throw TranscriptionError(message: String(localized: "Apple Intelligence can’t summarise \(name) (yet)."))
        }
        let context = SystemLanguageModel.default.contextSize
        // Room for the instructions (±500 tokens) and the answer (±1000).
        var budget = max(800, context - 1600)
        for attempt in 0..<3 {
            do {
                return try await run(lines, template: template, language: language, budget: budget, progress: progress)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, attempt < 2 { budget = budget * 2 / 3; continue }
                throw TranscriptionError(message: describe(error))
            }
        }
        throw TranscriptionError(message: String(localized: "This conversation is too long to summarise."))
    }

    private static func run(_ lines: [String], template: Summaries.Template, language: String, budget: Int,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        // Greedy: the same transcript gives the same summary.
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1200)
        var input = Summaries.chunks(lines, limit: budget)
        var fromNotes = false
        var done = 0.0
        let steps = Double(input.count > 1 ? input.count + 1 : 1)
        let headings = max(1, template.text.split(separator: "\n").filter { $0.hasPrefix("#") }.count)
        func report(_ partial: Double) { progress(min(0.97, (done + min(partial, 0.95)) / steps)) }
        // Notes per part until everything fits in one part (one round for any normal conversation).
        while input.count > 1 {
            var notes: [String] = []
            for (i, part) in input.enumerated() {
                try Task.checkCancellation()
                let session = LanguageModelSession(model: model, instructions: Summaries.noteInstructions(
                    template: template, language: language, part: i + 1, of: input.count))
                notes.append(try await stream(session, "Transcript part \(i + 1):\n" + part, options, expected: 900, report))
                done += 1
                report(0)
            }
            let noteLines = notes.flatMap(Summaries.cleanNotes)
            let next = Summaries.chunks(noteLines, limit: budget)
            if next.count >= input.count { input = [noteLines.joined(separator: "\n")]; fromNotes = true; break } // no progress: stop shrinking
            input = next
            fromNotes = true
        }
        try Task.checkCancellation()
        let session = LanguageModelSession(model: model, instructions: Summaries.instructions(
            template: template, language: language, fromNotes: fromNotes))
        let answer = try await stream(session, (fromNotes ? "Notes:\n" : "Transcript:\n") + (input.first ?? ""), options,
                                      expected: 120 + 160 * headings, report)
        progress(1)
        return Summaries.removeTemplateEcho(Summaries.firstPass(answer), template: template)
    }

    /// The answer, streamed so `partial` can follow its length (`expected` characters = 1).
    private static func stream(_ session: LanguageModelSession, _ prompt: String, _ options: GenerationOptions,
                               expected: Int, _ partial: (Double) -> Void) async throws -> String {
        var text = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            try Task.checkCancellation()
            text = snapshot.content
            partial(Double(text.count) / Double(expected))
        }
        return text
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation:
            String(localized: "Apple’s safety filter won’t summarise this conversation.")
        case .unsupportedLanguageOrLocale:
            String(localized: "Apple Intelligence doesn’t support the language of this conversation (yet).")
        case .assetsUnavailable:
            String(localized: "Apple Intelligence isn’t available right now. Is it turned on in Settings?")
        default:
            String(localized: "Summarising failed (\(error.localizedDescription)).")
        }
    }
}

// MARK: - Jobs (one at a time, progress per recording)

@MainActor @Observable
final class SummaryJobs {
    static let shared = SummaryJobs()

    /// Progress 0…1 of running or queued jobs by recording folder.
    private(set) var progress: [URL: Double] = [:]
    /// The last failure per folder (shown until the next attempt).
    var errors: [URL: String] = [:]
    /// Counts written summaries, so a view reloads a file that was overwritten in place.
    private(set) var generation = 0

    private var tasks: [URL: Task<Void, Never>] = [:]
    private var last: Task<Void, Never>?

    func fraction(of folder: URL) -> Double? { progress[folder.standardizedFileURL] }
    func isRunning(_ folder: URL) -> Bool { fraction(of: folder) != nil }

    /// Starts (or queues) a summary of the transcript in `recording`; replaces an older summary
    /// only when the new one is done.
    func start(_ recording: Recording, template: Summaries.Template = Summaries.template()) {
        let folder = recording.folder.standardizedFileURL
        guard tasks[folder] == nil, let json = recording.transcript else { return }
        errors[folder] = nil
        progress[folder] = 0
        Summaries.lastTemplate = template.name
        let previous = last
        let task = Task { [weak self] in
            await previous?.value
            await self?.run(folder: folder, json: json, title: recording.title, old: recording.summary, template: template)
        }
        tasks[folder] = task
        last = task
    }

    func cancel(_ folder: URL) {
        tasks[folder.standardizedFileURL]?.cancel()
    }

    func wait(_ folder: URL) async {
        await tasks[folder.standardizedFileURL]?.value
    }

    private func run(folder: URL, json: URL, title: String, old: URL?, template: Summaries.Template) async {
        defer {
            progress[folder] = nil
            tasks[folder] = nil
        }
        guard !Task.isCancelled else { return }
        do {
            let transcript = try await Task.detached { try TranscriptWriter.read(json: json) }.value
            let body = try await OnDeviceSummarizer.summarize(transcript, template: template) { value in
                Task { @MainActor in SummaryJobs.shared.update(folder, value) }
            }
            try Task.checkCancellation()
            let document = Summaries.document(title: title, template: template.name, body: body)
            // One file per template, as on the Mac: another template doesn't replace this one's summary.
            let target = Summaries.outputURL(in: folder, template: template.name)
            try await Task.detached {
                try Storage.coordinated(writing: target, options: .forReplacing) { try Data(document.utf8).write(to: $0, options: .atomic) }
                // An older iPhone summary without a template name gives way to the new one.
                if let old, old.standardizedFileURL != target.standardizedFileURL,
                   old.lastPathComponent == Summaries.outputURL(in: folder).lastPathComponent {
                    try? FileManager.default.removeItem(at: old)
                }
            }.value
            generation += 1
        } catch is CancellationError {
            // Nothing written: the file is only written at the very end.
        } catch {
            errors[folder] = error.localizedDescription
        }
        await Library.shared.refresh(except: Recorder.shared.folder)
    }

    private func update(_ folder: URL, _ value: Double) {
        guard progress[folder] != nil, tasks[folder]?.isCancelled != true else { return }
        progress[folder] = value
    }
}
