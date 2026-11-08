// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import Observation
import Synchronization

/// Per-recording metadata that is not the transcript: `<folder>/.bandje.json` (hidden, moves with
/// the folder on rename). Markers are seconds of recording time (pauses excluded).
struct RecordingMeta: Codable, Equatable, Sendable {
    var created: Date
    var markers: [Double] = []
    /// True while the recording is in progress; a folder with this set and no running recorder
    /// is an unfinished recording (crash, forced quit) and gets recovered at launch.
    var recording: Bool? = nil
    /// Where the recording was started, when "Store GPS location" is on (coordinates only, never
    /// looked up online).
    var location: RecordedLocation? = nil
    /// The cover (`CoverArt.key`) that is in the `.m4a` itself.
    var coverKey: String? = nil
    /// The cassette label's colour by name (`TapeColor`); absent is the default red. Shared with the Mac.
    var color: String? = nil

    static let fileName = ".bandje.json"

    static func url(in folder: URL) -> URL { folder.appending(path: fileName) }

    static func read(from folder: URL) -> RecordingMeta? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? decoder.decode(RecordingMeta.self, from: data)
    }

    func write(to folder: URL) throws {
        let data = try Self.encoder.encode(self)
        try Storage.coordinated(writing: Self.url(in: folder), options: .forReplacing) { try data.write(to: $0, options: .atomic) }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

struct RecordedLocation: Codable, Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in metres.
    var accuracy: Double
}

/// One recording = one folder in Documents: `<title>/<title>.m4a` (+ `.json`, `.md` later).
struct Recording: Identifiable, Hashable, Sendable {
    let folder: URL
    var title: String { folder.lastPathComponent }
    var audio: URL?
    var date: Date
    var duration: TimeInterval
    var markers: [Double]
    /// `<name>.json` when the recording has been transcribed.
    var transcript: URL? = nil
    /// `<name> samenvatting.md` (or `<name> summary.md`) when a summary was made.
    var summary: URL? = nil
    var location: RecordedLocation? = nil
    var color: TapeColor = .red
    var id: URL { folder }
}

/// "iPhone" or "iPad", for texts like "Everything stays on this iPhone". From the hardware model
/// (no main actor needed); the simulator reports the model it simulates.
enum Device {
    static let name: String = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        return model.hasPrefix("iPad") ? "iPad" : "iPhone"
    }()
}

/// File naming and the folder layout in Documents. Pure functions where possible (unit-tested).
enum Storage {
    /// This iPhone's recordings (and where new recordings and imports start out).
    static var documents: URL { URL.documentsDirectory }

    /// iCloud Drive › Bandje while "Sync with iCloud" is on (set by `CloudSync`), else nil.
    static var cloud: URL? { cloudFolder.withLock { $0 } }
    static func setCloud(_ url: URL?) { cloudFolder.withLock { $0 = url } }
    private static let cloudFolder = Mutex<URL?>(nil)

    /// Where the library looks: this iPhone, plus iCloud when syncing.
    static var libraryFolders: [URL] { [documents] + (cloud.map { [$0] } ?? []) }

    /// Folders in Documents that are not recordings ("templates": the Mac's summary templates in iCloud).
    static let reserved: Set<String> = ["selftest", "inbox", "templates"]

    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "aifc", "caf", "aac", "mp4", "m4b", "mov", "3gp", "amr", "opus", "ogg", "flac"]

    /// "Recording 6 Nov 14.32" / "Opname 6 nov 14.32". The time uses a dot: a colon is not allowed
    /// in names shown by the Files app, and the title is also the folder and file name.
    static func defaultTitle(for date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let day = f.string(from: date).replacingOccurrences(of: ".", with: "")
        f.dateFormat = "HH.mm"
        let time = f.string(from: date)
        return String(localized: "Recording \(day) \(time)", comment: "Default title of a new recording: day and time")
    }

    /// A title made safe as a file name: no `/` or `:`, no leading dots, not empty, not reserved.
    static func safeName(_ title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Recording" }
        if reserved.contains(name.lowercased()) { name += " 1" }
        return name
    }

    /// A folder name in `dir` that is not taken yet: `name`, `name 2`, `name 3`…
    static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        var candidate = name, n = 2
        while fm.fileExists(atPath: dir.appending(path: candidate).path) {
            candidate = "\(name) \(n)"
            n += 1
        }
        return candidate
    }

    /// Creates `<dir>/<title>/` for a new recording and returns the `.caf` to write into.
    static func newRecording(title: String, date: Date, in dir: URL = documents) throws -> URL {
        let name = uniqueName(safeName(title), in: dir)
        let folder = dir.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingMeta(created: date, recording: true).write(to: folder)
        return folder.appending(path: "\(name).caf")
    }

    /// The audio file of a recording folder: `<name>.<audio ext>` first, else any audio file.
    /// Leftover `.caf` (unfinished) and `.converting.` files don't count.
    static func audioFile(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        let audio = files.filter {
            audioExtensions.contains($0.pathExtension.lowercased()) && $0.pathExtension != "caf"
                && !$0.lastPathComponent.contains(".converting.")
        }
        let name = folder.lastPathComponent
        return audio.first { $0.deletingPathExtension().lastPathComponent == name }
            ?? audio.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    /// The transcript of a recording folder: `<folder name>.json`.
    static func transcriptFile(in folder: URL) -> URL? {
        let json = folder.appending(path: "\(folder.lastPathComponent).json")
        return FileManager.default.fileExists(atPath: json.path) ? json : nil
    }

    /// Unfinished recordings: a `.caf` in a recording folder without a finished audio file.
    static func unfinished(in dir: URL = documents, except active: URL? = nil) -> [URL] {
        recordingFolders(in: dir).compactMap { folder -> URL? in
            guard folder.standardizedFileURL != active?.standardizedFileURL else { return nil }
            let caf = folder.appending(path: "\(folder.lastPathComponent).caf")
            guard FileManager.default.fileExists(atPath: caf.path), audioFile(in: folder) == nil else { return nil }
            return caf
        }
    }

    static func recordingFolders(in dir: URL = documents) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !reserved.contains($0.lastPathComponent.lowercased())
        }
    }

    /// Recovers unfinished recordings: repairs the CAF header, converts to `.m4a`, clears the
    /// `recording` flag. Returns the folders that were recovered. A CAF that can't be converted
    /// stays (a later launch tries again).
    @discardableResult
    static func recoverUnfinished(in dir: URL = documents, except active: URL? = nil) -> [URL] {
        var recovered: [URL] = []
        for caf in unfinished(in: dir, except: active) {
            let folder = caf.deletingLastPathComponent()
            CAFRepair.repair(caf)
            if isEmptyRecording(caf) {
                // Stopped or crashed before the first samples: nothing to keep.
                removeIfOnlyLeftovers(folder)
                continue
            }
            do {
                _ = try AudioExport.convertToM4A(caf)
                var meta = RecordingMeta.read(from: folder) ?? RecordingMeta(created: creationDate(of: folder))
                meta.recording = nil
                try? meta.write(to: folder)
                recovered.append(folder)
            } catch {
                print("Bandje: recovery failed for \(folder.lastPathComponent): \(error)")
            }
        }
        return recovered
    }

    /// A CAF without a single audio frame (or with less than a header).
    static func isEmptyRecording(_ caf: URL) -> Bool {
        if let file = try? AVAudioFile(forReading: caf) { return file.length == 0 }
        let size = (try? caf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size < 4_096
    }

    /// Removes a recording folder if it only holds what the recorder made (the CAF, the sidecar,
    /// a half conversion), never anything the user put there.
    static func removeIfOnlyLeftovers(_ folder: URL) {
        let name = folder.lastPathComponent
        let ours: Set<String> = ["\(name).caf", "\(name).converting.m4a", RecordingMeta.fileName]
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if items.allSatisfy({ ours.contains($0) || $0 == ".DS_Store" }) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Audio files put loose in Documents (Files app): each gets its own folder, so it becomes a
    /// recording like any other. Returns the new folders.
    @discardableResult
    static func adoptLooseFiles(in dir: URL = documents) -> [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        var adopted: [URL] = []
        for file in items where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            && audioExtensions.contains(file.pathExtension.lowercased()) {
            let name = uniqueName(safeName(file.deletingPathExtension().lastPathComponent), in: dir)
            let folder = dir.appending(path: name, directoryHint: .isDirectory)
            do {
                let created = creationDate(of: file)
                try fm.createDirectory(at: folder, withIntermediateDirectories: false)
                try fm.moveItem(at: file, to: folder.appending(path: "\(name).\(file.pathExtension)"))
                try? RecordingMeta(created: created).write(to: folder)
                adopted.append(folder)
            } catch {
                print("Bandje: could not adopt \(file.lastPathComponent): \(error)")
            }
        }
        return adopted
    }

    /// Renames a recording: the folder and every file in it that starts with the old name
    /// (`<old>.m4a`, `<old>.json`, `<old> samenvatting.md`…). Returns the new folder.
    static func rename(_ folder: URL, to title: String) throws -> URL {
        let fm = FileManager.default
        let old = folder.lastPathComponent
        let parent = folder.deletingLastPathComponent()
        let wanted = safeName(title)
        if wanted == old { return folder }
        // A change in case only: the (case-insensitive) old folder must not count as taken.
        let name = wanted.lowercased() == old.lowercased() ? wanted : uniqueName(wanted, in: parent)
        let target = parent.appending(path: name, directoryHint: .isDirectory)
        if name.lowercased() == old.lowercased() {
            let temp = parent.appending(path: ".rename-\(UUID().uuidString)", directoryHint: .isDirectory)
            try move(folder, to: temp)
            try move(temp, to: target)
        } else {
            try move(folder, to: target)
        }
        for file in try fm.contentsOfDirectory(atPath: target.path) where file.hasPrefix(old + ".") || file.hasPrefix(old + " ") {
            let renamed = name + file.dropFirst(old.count)
            try move(target.appending(path: file), to: target.appending(path: renamed))
        }
        return target
    }

    /// Deletes a recording: its whole folder.
    static func delete(_ folder: URL) throws {
        try coordinated(writing: folder, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
    }

    /// A move that iCloud (and another device editing the same recording) is told about: coordinated,
    /// as the iCloud design asks (docs/icloud-sync.md). Fine for local files too.
    static func move(_ from: URL, to: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing,
                               error: &coordinationError) { source, target in
            do {
                coordinator.item(at: source, willMoveTo: target)
                try FileManager.default.moveItem(at: source, to: target)
                coordinator.item(at: source, didMoveTo: target)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    /// Runs `write` on `url` under a coordinated write.
    static func coordinated(writing url: URL, options: NSFileCoordinator.WritingOptions = [], _ write: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try write(url) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Moves a finished recording folder to iCloud when syncing (same name, or " 2" when the name is
    /// taken there). Returns where it is now; on failure it stays on the iPhone. Not on the main
    /// thread (`setUbiquitous` may block).
    static func publish(_ folder: URL) -> URL {
        guard let cloud, folder.deletingLastPathComponent().standardizedFileURL != cloud.standardizedFileURL else { return folder }
        let target = cloud.appending(path: uniqueName(folder.lastPathComponent, in: cloud), directoryHint: .isDirectory)
        do {
            try FileManager.default.setUbiquitous(true, itemAt: folder, destinationURL: target)
            return target
        } catch {
            return folder
        }
    }

    /// All recordings in `dir`, newest first.
    static func scan(_ dir: URL = documents, except active: URL? = nil) -> [Recording] {
        recordingFolders(in: dir).compactMap { folder -> Recording? in
            guard folder.standardizedFileURL != active?.standardizedFileURL,
                  let audio = audioFile(in: folder) else { return nil }
            let meta = RecordingMeta.read(from: folder)
            return Recording(folder: folder, audio: audio, date: meta?.created ?? creationDate(of: audio),
                             duration: duration(of: audio), markers: meta?.markers ?? [],
                             transcript: transcriptFile(in: folder), summary: Summaries.file(in: folder),
                             location: meta?.location, color: TapeColor(meta?.color))
        }
        .sorted { $0.date > $1.date }
    }
}

struct ImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Audio from other apps ("Open in", the file picker, the share extension's inbox) becomes a
/// recording folder like any other. Audio that AVFoundation can read stays as it is; video and
/// audio it can only decode through an asset become `.m4a` (audio only).
enum Importer {
    static let appGroup = "group.com.neurendal.bandje"

    /// The share extension's inbox in the App Group container (nil without the entitlement).
    static var inbox: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Imports `source` as `<dir>/<title>/<title>.<ext>`, title = file name without extension,
    /// date = creation date from the metadata, else the file's. `move`: the source is ours (an
    /// inbox) and is removed. Nothing is left in `dir` when it fails.
    static func importFile(_ source: URL, into dir: URL = Storage.documents, move: Bool = false) async throws -> URL {
        let fm = FileManager.default
        let display = source.lastPathComponent
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        let fileDate = (try? source.resourceValues(forKeys: [.creationDateKey]).creationDate)
        let name = Storage.uniqueName(Storage.safeName(source.deletingPathExtension().lastPathComponent), in: dir)
        let folder = dir.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            // 1. A local copy, hidden from the library scan while it is `.converting.`.
            let local = folder.appending(path: "\(name).converting.\(ext.isEmpty ? "audio" : ext)")
            try copyIn(source, to: local, move: move)

            // 2. Keep it, or take the audio out of it.
            let asset = AVURLAsset(url: local)
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            guard !audioTracks.isEmpty else {
                throw ImportError(message: String(localized: "“\(display)” is not an audio or video file Bandje can open."))
            }
            let hasVideo = !((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty
            let created = await metadataDate(of: asset) ?? fileDate ?? Date()
            // `.caf` in a recording folder means "unfinished recording" (crash recovery), so an
            // imported CAF becomes `.m4a` like video does.
            if !hasVideo, ext != "caf", Storage.audioExtensions.contains(ext), isReadableAudio(local) {
                try fm.moveItem(at: local, to: folder.appending(path: "\(name).\(ext)"))
            } else {
                let temp = folder.appending(path: "\(name).converting.m4a")
                do {
                    try await extractAudio(asset, to: temp)
                } catch {
                    throw ImportError(message: String(localized: "Bandje can't convert the audio in “\(display)”."))
                }
                guard isReadableAudio(temp) else {
                    throw ImportError(message: String(localized: "Bandje can't convert the audio in “\(display)”."))
                }
                try fm.moveItem(at: temp, to: folder.appending(path: "\(name).m4a"))
                try? fm.removeItem(at: local)
            }
            try RecordingMeta(created: created).write(to: folder)
            return folder
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    /// Copies (or moves) through a file coordinator, so files from a provider (iCloud Drive and
    /// the like) are downloaded first.
    private static func copyIn(_ source: URL, to target: URL, move: Bool) throws {
        let fm = FileManager.default
        if move {
            try fm.moveItem(at: source, to: target)
            return
        }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do { try fm.copyItem(at: url, to: target) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError {
            throw ImportError(message: String(localized: "Bandje can't read “\(source.lastPathComponent)”: \(error.localizedDescription)"))
        }
    }

    /// Audio track(s) only, as AAC in `.m4a`.
    private static func extractAudio(_ asset: AVURLAsset, to target: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError(message: "export session")
        }
        try? FileManager.default.removeItem(at: target)
        try await session.export(to: target, as: .m4a)
    }

    /// AVAudioFile (and so AVAudioPlayer and the duration in the library) can read it.
    static func isReadableAudio(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0 && file.fileFormat.sampleRate > 0
    }

    private static func metadataDate(of asset: AVURLAsset) async -> Date? {
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    /// Imports every file in `inbox` (the share extension's drop folder) into `dir` and empties
    /// it, also when a file fails (the error is returned once, not on every launch). Hidden
    /// entries (the extension's half-written `.incoming`) are left alone.
    static func processInbox(_ inbox: URL, into dir: URL = Storage.documents) async -> (imported: [URL], errors: [String]) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { Storage.creationDate(of: $0) < Storage.creationDate(of: $1) }
        var imported: [URL] = [], errors: [String] = []
        for file in files {
            do {
                imported.append(try await importFile(file, into: dir, move: true))
            } catch {
                errors.append(error.localizedDescription)
            }
            try? fm.removeItem(at: file)
        }
        return (imported, errors)
    }
}

/// The list of recordings shown in the app.
@MainActor @Observable
final class Library {
    static let shared = Library()

    private(set) var recordings: [Recording] = []
    /// Transcript text per recording folder, for search.
    private(set) var searchTexts: [URL: String] = [:]
    /// Imports in progress (the toolbar shows a spinner).
    private(set) var importing = 0
    /// Import failures to show once; the view clears it.
    var importErrors: [String] = []
    /// A recording that was just stopped (in the app, from Siri or the Lock Screen): the view opens it.
    var justRecorded: URL?
    /// Recordings not opened yet get a dot in the list, as in a mailbox. By recording date (it stays
    /// when a recording is renamed or moves to iCloud); only on this device. Recordings older than
    /// the first launch with this feature count as seen.
    private(set) var seen: Set<Int> = Set((UserDefaults.standard.array(forKey: "seenRecordings") as? [Int]) ?? [])
    private let newSince: Date = {
        let key = "newRecordingsSince"
        if let date = UserDefaults.standard.object(forKey: key) as? Date { return date }
        UserDefaults.standard.set(Date(), forKey: key)
        return Date()
    }()

    func isNew(_ recording: Recording) -> Bool {
        recording.date > newSince && !seen.contains(Int(recording.date.timeIntervalSince1970))
    }

    func markSeen(_ recording: Recording) {
        guard isNew(recording) else { return }
        seen.insert(Int(recording.date.timeIntervalSince1970))
        // Only what can still be new is kept.
        let live = Set(recordings.filter { $0.date > newSince }.map { Int($0.date.timeIntervalSince1970) })
        UserDefaults.standard.set(Array(seen.intersection(live.union([Int(recording.date.timeIntervalSince1970)]))), forKey: "seenRecordings")
    }

    private var watcher: DispatchSourceFileSystemObject?
    private var pendingRefresh: Task<Void, Never>?
    private var pickingUpInbox = false

    /// Rescans Documents off the main actor (durations need the audio files opened). Loose audio
    /// files added via the Files app get their own folder first.
    func refresh(except active: URL? = nil) async {
        let cache = searchCache
        let (recordings, texts, previews, newCache) = await Task.detached(priority: .userInitiated) {
            Storage.adoptLooseFiles()
            let recordings = Storage.libraryFolders.flatMap { Storage.scan($0, except: active) }.sorted { $0.date > $1.date }
            var texts: [URL: String] = [:], previews: [URL: String] = [:], newCache: [URL: CachedText] = [:]
            for recording in recordings {
                guard let json = recording.transcript else { continue }
                // Only transcripts that changed since the last refresh are read again.
                let modified = (try? json.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let entry = cache[json].flatMap { $0.modified == modified ? $0 : nil }
                    ?? CachedText(modified: modified, texts: TranscriptWriter.searchText(json: json))
                newCache[json] = entry
                texts[recording.folder] = entry.texts?.search
                previews[recording.folder] = entry.texts?.preview
            }
            return (recordings, texts, previews, newCache)
        }.value
        self.recordings = recordings
        searchTexts = texts
        self.previews = previews
        makeCovers()
        searchCache = newCache
    }

    struct CachedText: Sendable {
        let modified: Date
        let texts: (search: String, preview: String)?
    }
    /// The start of each transcript, for the list.
    private(set) var previews: [URL: String] = [:]
    /// Search text per transcript file with its modification date.
    @ObservationIgnored private var searchCache: [URL: CachedText] = [:]

    /// Every recording gets its cover art right away (lock screen, sharing), and the cover goes into
    /// its `.m4a`; one at a time so the interface stays smooth.
    /// Asked again while busy (a rename and then a new colour right after it): another round follows
    /// with the current list, so the newest title and colour always get their cover.
    private func makeCovers() {
        coversAgain = true
        guard coverTask == nil else { return }
        coverTask = Task { [weak self] in
            defer { self?.coverTask = nil }
            while self?.coversAgain == true {
                self?.coversAgain = false
                for recording in self?.recordings ?? [] {
                    if Task.isCancelled { return }
                    _ = CoverArt.file(for: recording)
                    await AudioExport.embedCover(recording)
                    await Task.yield()
                }
            }
        }
    }
    @ObservationIgnored private var coverTask: Task<Void, Never>?
    @ObservationIgnored private var coversAgain = false

    /// Recordings (newest first) grouped per day: "Today", "Yesterday", a weekday within the last
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
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        // Only the first letter: "Woensdag 28 oktober", not "Woensdag 28 Oktober".
        func first(_ s: String) -> String { s.prefix(1).uppercased(with: .current) + s.dropFirst() }
        if days > 0, days < 7 { return first(date.formatted(.dateTime.weekday(.wide))) }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return first(sameYear ? date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                              : date.formatted(.dateTime.day().month(.wide).year()))
    }

    /// Recordings whose title or transcript contains `query` (all when it is empty).
    func search(_ query: String) -> [Recording] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return recordings }
        return recordings.filter {
            $0.title.localizedStandardContains(q) || (searchTexts[$0.folder]?.localizedStandardContains(q) ?? false)
        }
    }

    /// A short piece of the transcript around the first match, for the search results.
    func snippet(for recording: Recording, query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !recording.title.localizedStandardContains(q), let text = searchTexts[recording.folder],
              let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end].trimmingCharacters(in: .whitespaces) + (end < text.endIndex ? "…" : "")
    }

    /// At launch: recover unfinished recordings, then scan, then watch Documents.
    func launch(except active: URL? = nil) async {
        _ = await Task.detached(priority: .userInitiated) {
            Storage.recoverUnfinished(except: active)
        }.value
        await refresh(except: active)
        watchDocuments()
        await pickUpInbox()
    }

    /// Imports files (file picker, "Open in"). Returns the new recordings; failures go to
    /// `importErrors`.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> [Recording] {
        importing += 1
        defer { importing -= 1 }
        var folders: [URL] = []
        for url in urls {
            // "Copy to Bandje" from apps without open-in-place lands in Documents/Inbox: ours to move.
            let move = url.deletingLastPathComponent().standardizedFileURL
                == Storage.documents.appending(path: "Inbox").standardizedFileURL
            do {
                let folder = try await Importer.importFile(url, move: move)
                folders.append(await Task.detached { Storage.publish(folder) }.value)
            } catch {
                importErrors.append(error.localizedDescription)
            }
        }
        await refresh(except: Recorder.shared.folder)
        let imported = folders.compactMap { folder in
            recordings.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
        }
        Transcriptions.shared.startIfAutomatic(imported)
        return imported
    }

    /// "Open in" / a document URL: a file that already is a recording in our Documents opens
    /// that recording; anything else is imported.
    func openDocument(_ url: URL) async -> Recording? {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        if Storage.libraryFolders.contains(where: { $0.standardizedFileURL == folder.deletingLastPathComponent() }),
           let existing = recordings.first(where: { $0.folder.standardizedFileURL == folder }) {
            return existing
        }
        return await importFiles([url]).first
    }

    /// Imports what the share extension left in the App Group inbox (at launch and on `.active`).
    func pickUpInbox() async {
        guard !pickingUpInbox, let inbox = Importer.inbox else { return }
        pickingUpInbox = true
        importing += 1
        defer {
            pickingUpInbox = false
            importing -= 1
        }
        let result = await Importer.processInbox(inbox)
        importErrors += result.errors
        if !result.imported.isEmpty {
            let published = await Task.detached { result.imported.map(Storage.publish) }.value
            await refresh(except: Recorder.shared.folder)
            let folders = Set(published.map(\.standardizedFileURL))
            Transcriptions.shared.startIfAutomatic(recordings.filter { folders.contains($0.folder.standardizedFileURL) })
        }
    }

    func rename(_ recording: Recording, to title: String) async throws -> Recording {
        if Transcriptions.shared.isRunning(recording.folder) {
            throw ImportError(message: String(localized: "Wait until the transcription is done, or cancel it, before renaming."))
        }
        if SummaryJobs.shared.isRunning(recording.folder) {
            throw ImportError(message: String(localized: "Wait until the summary is done, or cancel it, before renaming."))
        }
        let folder = try Storage.rename(recording.folder, to: title)
        let renamed = Recording(folder: folder, audio: Storage.audioFile(in: folder), date: recording.date,
                                duration: recording.duration, markers: recording.markers,
                                transcript: Storage.transcriptFile(in: folder), summary: Summaries.file(in: folder),
                                location: recording.location, color: recording.color)
        Player.shared.renamed(from: recording.folder, to: renamed)
        await refresh(except: Recorder.shared.folder)
        return renamed
    }

    /// The cassette's colour: kept in `.bandje.json` (coordinated, so it syncs through iCloud).
    func setColor(_ color: TapeColor, of recording: Recording) async throws {
        var meta = RecordingMeta.read(from: recording.folder) ?? RecordingMeta(created: recording.date)
        meta.color = color.stored
        try meta.write(to: recording.folder)
        var updated = recording
        updated.color = color
        Player.shared.renamed(from: recording.folder, to: updated)
        await refresh(except: Recorder.shared.folder)
    }

    func delete(_ recording: Recording) async throws {
        Transcriptions.shared.cancel(recording.folder)
        SummaryJobs.shared.cancel(recording.folder)
        if Player.shared.recording?.folder == recording.folder { Player.shared.unload() }
        try Storage.delete(recording.folder)
        recordings.removeAll { $0.folder == recording.folder }
        await refresh(except: Recorder.shared.folder)
    }

    /// Files app changes (add, delete, rename at the top of Documents) while the app is open.
    /// Changes inside a recording folder are picked up at the next `.active` rescan.
    private func watchDocuments() {
        guard watcher == nil else { return }
        let fd = open(Storage.documents.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Coalesces bursts of file events into one rescan (also for iCloud changes).
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh(except: Recorder.shared.folder)
        }
    }
}

// MARK: - iCloud Drive (opt-in, docs/icloud-sync.md)

/// "Sync with iCloud" (About › Recordings, default off): recordings live in iCloud Drive › Bandje and
/// appear on every iPhone and Mac with the same Apple ID. Recording and importing still happen on
/// the iPhone first; the finished folder then moves to iCloud (`Storage.publish`). What other
/// devices add comes in through an `NSMetadataQuery` and is downloaded right away.
@MainActor @Observable
final class CloudSync {
    static let shared = CloudSync()
    static let settingKey = "iCloudSync"
    nonisolated static let container = "iCloud.com.neurendal.bandje"

    /// Signed in to iCloud (with iCloud Drive on).
    private(set) var isAvailable = FileManager.default.ubiquityIdentityToken != nil
    private(set) var isOn = false
    private(set) var isBusy = false
    var errorMessage: String?

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// At launch: resumes syncing when the setting is on and iCloud is there.
    func launch() async {
        isAvailable = FileManager.default.ubiquityIdentityToken != nil
        let local = Storage.documents.appending(path: "Templates", directoryHint: .isDirectory)
        await Task.detached {
            Summaries.seedIfMissing(local)  // the examples, once
            Summaries.addLaterExamples(in: local)
        }.value
        guard UserDefaults.standard.bool(forKey: Self.settingKey), let folder = await Self.cloudDocuments() else { return }
        Storage.setCloud(folder)
        isOn = true
        await Task.detached { Self.shareTemplates(from: local, to: folder) }.value
        startQuery()
    }

    /// Turns syncing on and moves this iPhone's recordings to iCloud.
    func turnOn() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        guard let folder = await Self.cloudDocuments() else {
            errorMessage = String(localized: "iCloud Drive is not available. Sign in to iCloud and turn on iCloud Drive in Settings.")
            return
        }
        Player.shared.unload()  // the files it has open are about to move
        Storage.setCloud(folder)
        UserDefaults.standard.set(true, forKey: Self.settingKey)
        isOn = true
        let local = Storage.documents.appending(path: "Templates", directoryHint: .isDirectory)
        await Task.detached { Self.shareTemplates(from: local, to: folder) }.value
        let active = Recorder.shared.folder?.standardizedFileURL
        await Task.detached {
            for local in Storage.recordingFolders(in: Storage.documents)
            where local.standardizedFileURL != active && Storage.audioFile(in: local) != nil {
                _ = Storage.publish(local)
            }
        }.value
        startQuery()
        await Library.shared.refresh(except: Recorder.shared.folder)
    }

    /// Turns syncing off. iCloud keeps everything; recordings that are fully on this iPhone are
    /// copied here so they stay in the library.
    func turnOff() async {
        guard !isBusy, let cloud = Storage.cloud else { return }
        isBusy = true
        defer { isBusy = false }
        stopQuery()
        Player.shared.unload()
        await Task.detached {
            let fm = FileManager.default
            for folder in Storage.recordingFolders(in: cloud) where Self.isDownloaded(folder) {
                let target = Storage.documents.appending(path: folder.lastPathComponent, directoryHint: .isDirectory)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try? fm.copyItem(at: folder, to: target)
            }
        }.value
        Storage.setCloud(nil)
        UserDefaults.standard.set(false, forKey: Self.settingKey)
        isOn = false
        await Library.shared.refresh(except: Recorder.shared.folder)
    }

    /// This device's templates join the shared `Templates` folder in iCloud (never overwriting one
    /// that is already there, e.g. from the Mac), as the Mac does when syncing is turned on.
    nonisolated static func shareTemplates(from local: URL, to cloudDocuments: URL) {
        Summaries.mergeTemplates(from: local, into: cloudDocuments.appending(path: "Templates", directoryHint: .isDirectory))
    }

    /// `<container>/Documents`, created if needed. Off the main thread: the first call can take a while.
    nonisolated static func cloudDocuments() async -> URL? {
        await Task.detached {
            guard let root = FileManager.default.url(forUbiquityContainerIdentifier: container) else { return nil }
            let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    /// Every file in the folder is on this device (none still waiting in iCloud).
    nonisolated static func isDownloaded(_ folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? []
        return files.allSatisfy { file in
            !file.lastPathComponent.hasSuffix(".icloud")
                && ((try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus) ?? .current) == .current
        }
    }

    private func startQuery() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { _ in
                MainActor.assumeIsolated { CloudSync.shared.queryChanged() }
            })
        }
        self.query = query
        query.start()
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Fetches whatever is not on this iPhone yet, then rescans.
    private func queryChanged() {
        guard let query else { return }
        query.disableUpdates()
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()
        Library.shared.scheduleRefresh()
    }
}
