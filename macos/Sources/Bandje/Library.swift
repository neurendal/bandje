import AVFoundation
import Foundation
import Observation

/// One recording = one folder in the recordings folder: `<title>/<title>.m4a` (+ `.json`, `.md`,
/// summaries, `.bandje.json`), the same as on the iPhone.
struct Recording: Identifiable, Hashable {
    let folder: URL
    var title: String { folder.lastPathComponent }
    var audio: URL?
    var date: Date
    var duration: TimeInterval
    /// `<title>.json` when the recording has been transcribed.
    var transcript: URL? = nil
    /// The cassette's colour (`.bandje.json`, shared with the iPhone).
    var color: TapeColor = .red
    /// Seconds marked with the flag while recording (iPhone).
    var markers: [Double] = []
    var id: URL { folder }
}

/// The recordings shown in the Bandje window (ported from the iPhone's `Library`). Follows the
/// recordings folder (local or iCloud) through `.bandjeLibraryChanged`.
@MainActor @Observable
final class Library {
    static let shared = Library()

    private(set) var recordings: [Recording] = []
    /// Transcript text (words and speaker names) per recording folder, for search.
    private(set) var searchTexts: [URL: String] = [:]
    /// The start of each transcript, for the list.
    private(set) var previews: [URL: String] = [:]
    /// False until the recordings folder has been read once (with sync on: once iCloud answered),
    /// so the list says "Opnames laden…" instead of looking empty.
    private(set) var hasLoaded = false

    /// The folder shown; the selftest points it at its own folder.
    @ObservationIgnored var root: () -> URL
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Whether `root()` is the real recordings folder yet; the selftest's own folder always is.
    @ObservationIgnored var isRootKnown: () -> Bool = { !ICloudSync.isOn || ICloudSync.prepared }
    @ObservationIgnored private var refreshes = 0
    /// True while a job writes into that folder (transcription, summary): no rename or delete then.
    @ObservationIgnored var isBusy: (URL) -> Bool = { _ in false }

    struct BusyError: LocalizedError {
        var errorDescription: String? { tr("window.busy", "Wacht tot de transcriptie of samenvatting van deze opname klaar is.") }
    }

    /// The recordings folder (local, or iCloud once it answered).
    init() {
        root = { OutputLocation.directory }
    }

    /// A folder of its own (tests): known at once.
    init(root: @escaping () -> URL) {
        self.root = root
        isRootKnown = { true }
    }

    /// Starts following the recordings folder (the window calls this once). With sync on, iCloud's
    /// answer at launch (`.bandjeICloudReady`) refreshes at once, without waiting for the watcher.
    func start() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.bandjeLibraryChanged, .bandjeICloudReady] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = Task { await self?.refresh() } }
            })
        }
        Task { await refresh() }
    }

    /// Rescans the recordings folder off the main actor: first the list (folders, dates, lengths),
    /// shown at once; then the transcripts' text for the previews and search.
    func refresh() async {
        // Sync on but iCloud has not answered yet: the folder is not known, so nothing is shown yet
        // (the local folder would show the wrong recordings, or none).
        guard isRootKnown() else { return }
        refreshes += 1
        let mine = refreshes
        let dir = root()
        let found = await Task.detached(priority: .userInitiated) { Library.scan(dir) }.value
        guard mine == refreshes else { return }  // a newer refresh is on its way
        recordings = found
        hasLoaded = true
        makeCovers()
        let (texts, previews) = await Task.detached(priority: .utility) { Library.texts(found) }.value
        guard mine == refreshes else { return }
        searchTexts = texts
        self.previews = previews
    }

    /// Every recording gets its cover in its `.m4a` (a new one after a rename or another colour,
    /// here or on the iPhone), one at a time in the background. Asked again while busy: another
    /// round follows with the current list, so the newest title and colour always get their cover.
    private func makeCovers() {
        coversAgain = true
        guard coverTask == nil else { return }
        coverTask = Task { [weak self] in
            defer { self?.coverTask = nil }
            while self?.coversAgain == true {
                self?.coversAgain = false
                for recording in self?.recordings ?? [] {
                    if Task.isCancelled { return }
                    guard let self, !self.isBusy(recording.folder) else { continue }
                    await CoverArt.embed(in: recording.folder)
                    await Task.yield()
                }
            }
        }
    }
    @ObservationIgnored private var coverTask: Task<Void, Never>?
    @ObservationIgnored private var coversAgain = false

    /// The transcripts' text per recording folder: everything (for search) and the start (the list).
    nonisolated static func texts(_ recordings: [Recording]) -> (search: [URL: String], previews: [URL: String]) {
        var texts: [URL: String] = [:], previews: [URL: String] = [:]
        for r in recordings {
            guard let json = r.transcript, let t = try? TranscriptWriter.read(json: json) else { continue }
            let words = t.segments.map(\.text)
            texts[r.folder] = (Array(t.speakerNames.values) + words).joined(separator: " ")
            previews[r.folder] = String(words.joined(separator: " ").prefix(160))
        }
        return (texts, previews)
    }

    /// The recordings in `dir`, newest first. The length comes from the transcript when there is
    /// one, else from the audio only when it is on this Mac (opening audio that is still in iCloud
    /// would download it).
    nonisolated static func scan(_ dir: URL) -> [Recording] {
        OutputLocation.recordingFolders(in: dir).compactMap { folder -> Recording? in
            let audio = audioFile(in: folder)
            let transcript = transcriptFile(in: folder)
            guard audio != nil || transcript != nil else { return nil }
            let meta = RecordingMeta.read(from: folder)
            return Recording(folder: folder, audio: audio, date: OutputLocation.recordingDate(folder.appendingPathComponent("\(folder.lastPathComponent).json")),
                             duration: duration(transcript: transcript, audio: audio), transcript: transcript,
                             color: TapeColor(meta?.color), markers: meta?.markers ?? [])
        }
        .sorted { $0.date > $1.date }
    }

    /// `<folder>/<title>.json` when the recording has been transcribed.
    nonisolated static func transcriptFile(in folder: URL) -> URL? {
        let json = folder.appendingPathComponent("\(folder.lastPathComponent).json")
        return FileManager.default.fileExists(atPath: json.path) ? json : nil
    }

    nonisolated static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "aifc", "aac", "mp4", "m4b", "mov", "flac"]

    /// `<title>.<audio>` first, else any audio file (never a leftover `.caf` or `.converting.`).
    nonisolated static func audioFile(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        let audio = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.contains(".converting.") }
        return audio.first { $0.deletingPathExtension().lastPathComponent == folder.lastPathComponent }
            ?? audio.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    nonisolated static func duration(transcript: URL?, audio: URL?) -> TimeInterval {
        if let transcript, let data = try? Files.read(transcript),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = o["duration"] as? Double {
            return d
        }
        guard let audio, isLocal(audio), let file = try? AVAudioFile(forReading: audio), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// A file that is not in iCloud, or fully downloaded.
    nonisolated static func isLocal(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return v?.isUbiquitousItem != true || v?.ubiquitousItemDownloadingStatus == .current
    }

    // MARK: Days and search

    /// Recordings (newest first) grouped per day: "Vandaag", "Gisteren", a weekday within the last
    /// week, else the date.
    nonisolated static func days(_ recordings: [Recording], now: Date = .now, calendar: Calendar = .current) -> [(title: String, recordings: [Recording])] {
        var out: [(title: String, recordings: [Recording])] = []
        for recording in recordings {
            let title = dayTitle(recording.date, now: now, calendar: calendar)
            if out.last?.title == title { out[out.count - 1].recordings.append(recording) } else { out.append((title, [recording])) }
        }
        return out
    }

    nonisolated static func dayTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let locale = TranscriptWriter.appLocale
        if calendar.isDate(date, inSameDayAs: now) { return tr("library.today", "Vandaag") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return tr("library.yesterday", "Gisteren")
        }
        var style = Date.FormatStyle.dateTime.locale(locale)
        style.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if days > 0, days < 7 { return date.formatted(style.weekday(.wide)).capitalized(with: locale) }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(style.weekday(.wide).day().month(.wide)).capitalized(with: locale)
                        : date.formatted(style.day().month(.wide).year())
    }

    /// Recordings whose title or transcript contains `query` (all when it is empty).
    func search(_ query: String) -> [Recording] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return recordings }
        return recordings.filter { $0.title.localizedStandardContains(q) || (searchTexts[$0.folder]?.localizedStandardContains(q) ?? false) }
    }

    func preview(for recording: Recording) -> String? { previews[recording.folder] }

    // MARK: Rename and delete

    /// Renames a recording: the folder and every file in it that starts with the old name
    /// (`<old>.m4a`, `<old>.json`, `<old> samenvatting ….md`). A taken name gets ` 2`.
    nonisolated static func renameFolder(_ folder: URL, to title: String) throws -> URL {
        let old = folder.lastPathComponent
        let parent = folder.deletingLastPathComponent()
        let wanted = OutputLocation.safeName(title)
        if wanted == old { return folder }
        // An old Mac recording (`2026-11-05_14-30`) keeps its date and its me/other-side channels
        // after a rename: they came from the name, so they go into `.bandje.json` first.
        if RecordingMeta.read(from: folder) == nil, TranscriptWriter.isRecordingName(old) {
            let date = OutputLocation.recordingDate(folder.appendingPathComponent("\(old).json"))
            try? RecordingMeta(created: date).write(to: folder)
        }
        let caseOnly = wanted.lowercased() == old.lowercased()
        let name = caseOnly ? wanted : OutputLocation.uniqueName(wanted, in: parent)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        if caseOnly {
            let temp = parent.appendingPathComponent(".rename-\(UUID().uuidString)", isDirectory: true)
            try Files.move(folder, to: temp)
            do {
                try Files.move(temp, to: target)
            } catch {
                try? Files.move(temp, to: folder)  // never leave it hidden
                throw error
            }
        } else {
            try Files.move(folder, to: target)
        }
        try renameFiles(in: target, from: old, to: name)
        return target
    }

    /// Renames every file in `folder` that starts with `old` (`<old>.m4a`, `<old>.json`,
    /// `<old> samenvatting ….md`) to start with `new`; the transcript's title and audio name follow,
    /// and its Markdown is rewritten (the heading is the title).
    nonisolated static func renameFiles(in folder: URL, from old: String, to new: String) throws {
        guard old != new else { return }
        for file in try FileManager.default.contentsOfDirectory(atPath: folder.path) where file.hasPrefix(old + ".") || file.hasPrefix(old + " ") {
            try Files.move(folder.appendingPathComponent(file), to: folder.appendingPathComponent(new + file.dropFirst(old.count)))
        }
        let json = folder.appendingPathComponent("\(new).json")
        if var t = try? TranscriptWriter.read(json: json) {
            if let audio = t.audioFile, audio.hasPrefix(old) { t.audioFile = new + audio.dropFirst(old.count) }
            t.title = new
            try? TranscriptWriter.rewrite(t, json: json)
        }
    }

    /// Old Mac names ("2026-11-05_14-30") become the iPhone's name for that moment ("Opname 5 nov
    /// 14.30"), with the date in this Mac's language and region (owner: the computer's own setting),
    /// so the iPhone and the Mac show the same title. A taken name gets " 2"; the date goes into
    /// `.bandje.json` first (`renameFolder`). Skips folders a job is writing to. Returns how many.
    @discardableResult
    nonisolated static func renameLegacyFolders(in dir: URL, locale: Locale = .current, isBusy: (URL) -> Bool) -> Int {
        var count = 0
        for folder in OutputLocation.recordingFolders(in: dir) where TranscriptWriter.isRecordingName(folder.lastPathComponent) && !isBusy(folder) {
            let date = OutputLocation.recordingDate(folder.appendingPathComponent("\(folder.lastPathComponent).json"))
            if (try? renameFolder(folder, to: OutputLocation.defaultTitle(for: date, locale: locale))) != nil { count += 1 }
        }
        return count
    }

    /// Gives the recording's cassette `color` (red = the default: no key). A folder without
    /// `.bandje.json` gets one with its recording date.
    nonisolated static func setColor(_ color: TapeColor, in folder: URL) throws {
        var meta = RecordingMeta.read(from: folder)
            ?? RecordingMeta(created: OutputLocation.recordingDate(folder.appendingPathComponent("\(folder.lastPathComponent).json")))
        meta.color = color.stored
        try meta.write(to: folder)
    }

    func setColor(_ color: TapeColor, of recording: Recording) async throws {
        guard !isBusy(recording.folder) else { throw BusyError() }
        try await Task.detached { try Library.setColor(color, in: recording.folder) }.value
        await refresh()
    }

    func rename(_ recording: Recording, to title: String) async throws -> Recording {
        guard !isBusy(recording.folder) else { throw BusyError() }
        let folder = try await Task.detached { try Library.renameFolder(recording.folder, to: title) }.value
        await refresh()
        return recordings.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
            ?? Recording(folder: folder, audio: Library.audioFile(in: folder), date: recording.date, duration: recording.duration)
    }

    /// Moves the recording's folder to the Trash (also in iCloud: the Trash keeps it for a while).
    func delete(_ recording: Recording) async throws {
        guard !isBusy(recording.folder) else { throw BusyError() }
        try FileManager.default.trashItem(at: recording.folder, resultingItemURL: nil)
        await refresh()
    }
}
