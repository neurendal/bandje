import Foundation
import NaturalLanguage
import FoundationModels

/// Summaries with Apple's on-device model. Everything here that does not touch the model
/// (templates, language, chunks, prompts, output) is plain code, testable on any macOS.
enum Summaries {
    struct Template: Equatable {
        var name: String
        var text: String
    }

    // MARK: Templates

    /// One source of truth: `iCloud Drive › Band·je › Templates` while syncing (the iPhone reads the same
    /// folder), else `~/Music/Bandje/Templates` (also when recordings go to another folder).
    static var folder: URL {
        if ICloudSync.isActive, let documents = ICloudSync.documents {
            return documents.appendingPathComponent("Templates", isDirectory: true)
        }
        return localFolder
    }

    static var localFolder: URL { OutputLocation.defaultDirectory.appendingPathComponent("Templates", isDirectory: true) }

    /// Copies the `.md`/`.txt` templates from `source` into `target` (created when missing); a name
    /// that exists in `target` is kept unless `overwrite`. Turning sync on merges the local templates
    /// into iCloud (keep); turning it off copies iCloud's back (iCloud's version wins).
    static func mergeTemplates(from source: URL, into target: URL, overwrite: Bool) throws {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files where ["md", "txt"].contains(file.pathExtension.lowercased()) {
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                guard overwrite else { continue }
                try Files.write(try Files.read(file), to: destination)
            } else {
                try Files.copy(file, to: destination)
            }
        }
    }

    /// `.md` and `.txt` files in `folder`, sorted by name as Finder does. Empty files are skipped.
    static func templates(in folder: URL = folder) -> [Template] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> Template? in
                guard let text = Files.readString(url),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Template(name: url.deletingPathExtension().lastPathComponent, text: text)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Creates `folder` with the examples when it does not exist yet; an existing folder (also an
    /// empty one) is the user's: it only gets an example added later (`laterExamples`), once, as on
    /// the iPhone: never over a file of that name, and a flag per name so a deleted one stays gone.
    /// Through iCloud the first app to add it shares it with the other.
    static func seedIfMissing(_ folder: URL = folder, language: String = TranscriptWriter.appLocale.language.languageCode?.identifier ?? "nl",
                              defaults: UserDefaults = .standard) {
        let examples = examples(language: language)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for t in examples {
                try? Data(t.text.utf8).write(to: folder.appendingPathComponent(t.name + ".md"), options: .withoutOverwriting)
            }
            for name in laterExamples { defaults.set(true, forKey: "templateAdded." + name) }
            return
        }
        for t in examples where laterExamples.contains(t.name) && !defaults.bool(forKey: "templateAdded." + t.name) {
            try? Data(t.text.utf8).write(to: folder.appendingPathComponent(t.name + ".md"), options: .withoutOverwriting)
            defaults.set(true, forKey: "templateAdded." + t.name)
        }
    }

    /// Samenvatten › Nieuw template: "Nieuw template.md" ("New template" in other languages; " 2"…
    /// when taken) in `folder`, with two headings to change. Returns the file.
    static func newTemplate(in folder: URL = folder, language: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dutch = language == "nl"
        let base = dutch ? "Nieuw template" : "New template"
        var name = base, n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".md").path) {
            name = "\(base) \(n)"
            n += 1
        }
        let url = folder.appendingPathComponent(name + ".md")
        let text = dutch
            ? "## Kern\nDe belangrijkste uitkomst van het gesprek in twee of drie zinnen.\n\n## Actiepunten\nPer actiepunt een opsommingsteken: wie, wat en wanneer, als dat gezegd is.\n"
            : "## Key points\nThe main outcome of the conversation in two or three sentences.\n\n## Action items\nOne bullet per action item: who, what and when, if that was said.\n"
        try Files.write(Data(text.utf8), to: url)
        return url
    }

    // MARK: Example data (the iPhone's SummaryTemplates.json, see SummaryTemplates.swift)

    private struct LanguageData: Decodable {
        struct Example: Decodable { let name: String; let text: String }
        let fileWord: String
        let templates: [Example]
    }

    private static let data: [String: LanguageData] =
        (try? JSONDecoder().decode([String: LanguageData].self, from: Data(SummaryTemplateData.json.utf8))) ?? [:]

    /// `code` when there are examples in that language, else English (as on the iPhone).
    static func dataLanguage(_ code: String?) -> String {
        code.flatMap { data[$0] == nil ? nil : $0 } ?? "en"
    }

    /// Examples added after the first version (the generic summary, the 4th of every language):
    /// existing template folders get them once.
    static let laterExamples: Set<String> = Set(data.values.compactMap { $0.templates.last?.name })

    /// The four example templates in that language, or English when there are none.
    static func examples(language: String) -> [Template] {
        (data[dataLanguage(language)]?.templates ?? []).map { Template(name: $0.name, text: $0.text) }
    }

    // MARK: Transcript as text

    /// One line per turn, `[mm:ss] Name: text`, with the names the user gave.
    static func lines(_ t: Transcript) -> [String] {
        let long = t.duration >= 3600
        return TranscriptWriter.joinConsecutive(t.segments).map {
            $0.speaker.isEmpty ? "[\(TranscriptWriter.clock($0.start, long: long))] \($0.text)"
                               : "[\(TranscriptWriter.clock($0.start, long: long))] \(t.name(of: $0.speaker)): \($0.text)"
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

    private static func split(_ line: String, limit: Int, tokens: (String) -> Int) -> [String] {
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

    // MARK: Prompts

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
    /// ("Wat de kandidaat zelf vroeg, en het antwoord:") or as a lead-in before a colon ("Andere
    /// gesprekken van de kandidaat: Bol"). Such lines are removed, lead-ins cut off.
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

    // MARK: Output

    /// The summary file's name word ("samenvatting"); the player finds summaries by `<base> ` prefix.
    static var fileWord: String { fileWord(language: TranscriptWriter.appLocale.language.languageCode?.identifier) }

    static func fileWord(language: String?) -> String { data[dataLanguage(language)]?.fileWord ?? "summary" }

    /// `<base> samenvatting <template>.md` next to the transcript's `.json`.
    static func outputURL(json: URL, template: String) -> URL {
        let base = json.deletingPathExtension().lastPathComponent
        let safe = template.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return json.deletingLastPathComponent().appendingPathComponent("\(base) \(fileWord) \(safe).md")
    }

    /// Title, one line of metadata, a rule, the model's text (no logo: the same as the iPhone).
    static func document(_ t: Transcript, template: String, body: String, date: Date = Date(),
                         locale: Locale = TranscriptWriter.appLocale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMMMyyyyHHmm")
        var out = "# " + tr("summary.title", "Samenvatting %@", TranscriptWriter.displayTitle(t.title, locale: locale)) + "\n\n"
        out += "_" + tr("summary.meta", "Template %1$@ · %2$@ · gemaakt op deze Mac met Apple Intelligence", template, f.string(from: date)) + "_\n\n---\n\n"
        out += body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        return out
    }

    /// The model's text from a summary file written by `document` (everything after the first rule).
    static func body(ofDocument md: String) -> String {
        guard let r = md.range(of: "\n---\n") else { return md }
        return String(md[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The on-device model. Only `SystemLanguageModel`: never Private Cloud Compute.
@available(macOS 26.0, *)
enum OnDeviceSummarizer {
    /// Transcripts are content to transform, so the permissive guardrails for that use apply.
    private static var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func supports(language: String) -> Bool {
        SystemLanguageModel.default.supportsLocale(Locale(identifier: language))
    }

    /// Warms the model up while the user is still choosing a template.
    static func prewarm() {
        LanguageModelSession(model: model).prewarm()
    }

    enum Progress: Sendable { case step(Int, of: Int) }

    /// The summary text for `t` with `template`. A conversation that does not fit the context window
    /// is cut into parts on turn boundaries: notes per part, then the summary from all notes.
    static func summarize(_ t: Transcript, template: Summaries.Template,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let lines = Summaries.lines(t)
        guard !lines.isEmpty else { throw TranscriberError(message: tr("summary.empty", "Dit transcript bevat geen tekst om samen te vatten.")) }
        let text = lines.joined(separator: "\n")
        guard let language = Summaries.language(of: text) else {
            throw TranscriberError(message: tr("summary.noLanguage", "Band·je kan de taal van dit gesprek niet bepalen."))
        }
        guard supports(language: language) else {
            throw TranscriberError(message: tr("summary.unsupportedLanguage", "Samenvatten in het %@ kan Apple Intelligence (nog) niet.",
                                               Locale.current.localizedString(forLanguageCode: language) ?? language))
        }
        let context = SystemLanguageModel.default.contextSize
        // Room for the instructions (±500 tokens with a long template) and the answer (±1000).
        var budget = max(800, context - 1600)
        for attempt in 0..<3 {
            do {
                return try await run(lines, template: template, language: language, budget: budget, progress: progress)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, attempt < 2 { budget = budget * 2 / 3; continue }
                throw TranscriberError(message: describe(error))
            }
        }
        throw TranscriberError(message: tr("summary.tooLong", "Dit gesprek is te lang om samen te vatten."))
    }

    private static func run(_ lines: [String], template: Summaries.Template, language: String, budget: Int,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        // Greedy: the same transcript and template give the same summary.
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1200)
        var input = Summaries.chunks(lines, limit: budget)
        var fromNotes = false
        var done = 0.0
        let steps = Double(input.count > 1 ? input.count + 1 : 1)
        // Progress within one answer: its length so far against a typical length (streamed).
        let headings = max(1, template.text.split(separator: "\n").filter { $0.hasPrefix("#") }.count)
        func report(_ partial: Double) { progress(min(0.97, (done + min(partial, 0.95)) / steps)) }
        // Notes per part until everything fits in one part (one round for any normal conversation).
        while input.count > 1 {
            var notes: [String] = []
            for (i, part) in input.enumerated() {
                let session = LanguageModelSession(model: model, instructions: Summaries.noteInstructions(
                    template: template, language: language, part: i + 1, of: input.count))
                notes.append(try await stream(session, "Transcript part \(i + 1):\n" + part, options, expected: 900, report))
                done += 1
                report(0)
            }
            let noteLines = notes.flatMap { $0.split(separator: "\n").map(String.init) }
            let next = Summaries.chunks(noteLines, limit: budget)
            if next.count >= input.count { input = [noteLines.joined(separator: "\n")]; fromNotes = true; break } // no progress: stop shrinking
            input = next
            fromNotes = true
        }
        let session = LanguageModelSession(model: model, instructions: Summaries.instructions(
            template: template, language: language, fromNotes: fromNotes))
        let answer = try await stream(session, (fromNotes ? "Notes:\n" : "Transcript:\n") + (input.first ?? ""), options,
                                      expected: 120 + 160 * headings, report)
        progress(1)
        return Summaries.removeTemplateEcho(answer, template: template)
    }

    /// The answer, streamed so `partial` can follow its length (`expected` characters = 1).
    private static func stream(_ session: LanguageModelSession, _ prompt: String, _ options: GenerationOptions,
                               expected: Int, _ partial: (Double) -> Void) async throws -> String {
        var text = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            text = snapshot.content
            partial(Double(text.count) / Double(expected))
        }
        return text
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation:
            tr("summary.guardrail", "Het veiligheidsfilter van Apple weigert dit gesprek samen te vatten.")
        case .unsupportedLanguageOrLocale:
            tr("summary.unsupportedLanguageGeneric", "Apple Intelligence ondersteunt de taal van dit gesprek (nog) niet.")
        case .assetsUnavailable:
            tr("summary.unavailable", "Apple Intelligence is nu niet beschikbaar. Staat het aan in Systeeminstellingen?")
        default:
            tr("summary.failedReason", "Samenvatten mislukt (%@).", error.localizedDescription)
        }
    }
}
