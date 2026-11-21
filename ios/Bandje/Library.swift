// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import BandjeKit
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
    /// An imported file, not a recording made here or on the Mac: the Mac never splits it into me
    /// (left) and the other side (right). Kept here so rewriting this file does not drop it.
    var imported: Bool? = nil
    /// Launches that tried to convert this folder's leftover `.caf` and failed (only on this
    /// device: a folder with a `.caf` never goes to iCloud). Removed once it is converted.
    var conversionAttempts: Int? = nil
    /// The recording's length in seconds (0.1 s), a hint for when the audio is not on this device
    /// (still in iCloud): the audio's own length always comes first (`Storage.duration(audio:meta:transcript:)`).
    /// Written when a recording is finished or imported, and filled in for older ones whose audio is
    /// here (`Storage.backfillDurations`). The shipped 1.0 drops it when it rewrites this file; it is
    /// filled in again then.
    var duration: Double? = nil

    static let fileName = ".bandje.json"

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case created, markers, recording, location, coverKey, color, imported, conversionAttempts, duration
    }

    init(created: Date, markers: [Double] = [], recording: Bool? = nil, location: RecordedLocation? = nil) {
        self.created = created
        self.markers = markers
        self.recording = recording
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = try c.decode(Date.self, forKey: .created)
        markers = try c.decode([Double].self, forKey: .markers)
        recording = try c.decodeIfPresent(Bool.self, forKey: .recording)
        location = try c.decodeIfPresent(RecordedLocation.self, forKey: .location)
        coverKey = try c.decodeIfPresent(String.self, forKey: .coverKey)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        imported = try c.decodeIfPresent(Bool.self, forKey: .imported)
        conversionAttempts = try c.decodeIfPresent(Int.self, forKey: .conversionAttempts)
        // Only a hint: something odd there never makes the whole file unreadable.
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
    }

    static func url(in folder: URL) -> URL { folder.appending(path: fileName) }

    static func read(from folder: URL) -> RecordingMeta? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? decoder.decode(RecordingMeta.self, from: data)
    }

    /// Writes our keys over the file that is there (read under the same coordinated write), so keys
    /// a newer version (here or on the Mac) wrote and this one doesn't know survive. A key of ours
    /// that is nil now is removed. Numbers as decimals: 312.4, not 312.39999999999998.
    func write(to folder: URL) throws {
        try Storage.coordinated(writing: Self.url(in: folder), options: .forReplacing) { try merge(into: $0) }
    }

    /// Changes the folder's `.bandje.json` as it is now: read, changed and written under one
    /// coordinated write, so whatever was written since an earlier read (a colour set during a
    /// cover export, a change from the other device) is not put back. No readable file: a new one
    /// with `created`. `onlyIfCurrent`: nothing when the file here is not the newest one in iCloud
    /// (`CoverPolicy.isUpToDate`): writes this device makes by itself (a cover's key) never go over a
    /// change from the other device that has not arrived yet. Returns true when it wrote.
    @discardableResult
    static func update(in folder: URL, created: Date, onlyIfCurrent: Bool = false,
                       _ change: (inout RecordingMeta) -> Void) throws -> Bool {
        var wrote = false
        try Storage.coordinated(writing: url(in: folder), options: .forReplacing) { url in
            if onlyIfCurrent, !CoverPolicy.isUpToDate(url) { return }
            var meta = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(RecordingMeta.self, from: $0) }
                ?? RecordingMeta(created: created)
            change(&meta)
            try meta.merge(into: url)
            wrote = true
        }
        return wrote
    }

    /// Our keys over the file at `url` (inside a coordinated write).
    private func merge(into url: URL) throws {
        var ours = try JSONSerialization.jsonObject(with: Self.encoder.encode(self)) as? [String: Any] ?? [:]
        ours["markers"] = markers.map(Self.decimal)
        if let duration { ours["duration"] = Self.decimal(duration) }
        var out = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        for key in CodingKeys.allCases { out[key.rawValue] = nil }
        out.merge(ours) { _, new in new }
        try Self.writeJSON(out, to: url)
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url, options: .atomic)
    }

    /// `seconds` as it is kept in `duration`: 0.1 s, rounded down, so that it rounds to the same whole
    /// second as the audio's own length (`RecordingID` keeps saved positions under that). Nil when
    /// there is no length.
    static func storedDuration(_ seconds: TimeInterval) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        var tenths = (seconds * 10).rounded(.down)
        // Floating point can put 312.4999… on 312.5: never round differently than the audio does.
        if (tenths / 10).rounded() != seconds.rounded() { tenths -= 1 }
        return tenths > 0 ? tenths / 10 : nil
    }

    /// Sets `duration` from the audio's length (`storedDuration`).
    mutating func setDuration(_ seconds: TimeInterval) {
        duration = Self.storedDuration(seconds)
    }

    /// A number as JSON writes it, as `Markers.write` (BandjeKit) writes the markers.
    static func decimal(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: "\(value)")
    }

    /// Puts `duration` (already `storedDuration`) into the folder's `.bandje.json` when it has none
    /// yet; every other key stays as it is. Coordinated and read inside the same write, so a marker
    /// written at the same moment is not lost. No file, a recording in progress, or a file whose
    /// newer version is still coming from iCloud (the other device's keys must not be undone):
    /// nothing. Returns true when it wrote.
    static func fillIn(duration: Double, in folder: URL) throws -> Bool {
        let url = url(in: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var wrote = false
        try Storage.coordinated(writing: url, options: .forReplacing) { url in
            guard CoverPolicy.isUpToDate(url) else { return }
            guard var out = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  out["created"] != nil, out["duration"] == nil, out["recording"] as? Bool != true else { return }
            out["duration"] = decimal(duration)
            try writeJSON(out, to: url)
            wrote = true
        }
        return wrote
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
    /// The audio is on this device. False for a recording from another device whose audio is still
    /// in iCloud: it downloads when it is played or transcribed (docs/icloud-sync.md).
    var audioIsLocal = true
    var id: URL { folder }

    /// The audio is the recorder's `.caf`, not converted (the disk was full, or the file is
    /// damaged): it plays and can be deleted, but is not transcribed or synced.
    var isUnconverted: Bool { audio?.pathExtension.lowercased() == "caf" }
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
    /// Leftover `.caf` (unfinished) and `.converting.` files don't count. A file still in iCloud
    /// (shown as `.<name>.icloud`) counts under its own name.
    static func audioFile(in folder: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let files = Set(names.compactMap(visibleName)).map { folder.appending(path: $0) }
        let audio = files.filter {
            audioExtensions.contains($0.pathExtension.lowercased()) && $0.pathExtension != "caf"
                && !$0.lastPathComponent.contains(".converting.")
        }
        let name = folder.lastPathComponent
        return audio.first { $0.deletingPathExtension().lastPathComponent == name }
            ?? audio.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    /// The name a directory entry stands for: itself, or for an iCloud placeholder
    /// (`.<name>.icloud`) the file it stands for. Nil for hidden files.
    static func visibleName(_ entry: String) -> String? {
        if entry.hasPrefix("."), entry.hasSuffix(".icloud") {
            let name = String(entry.dropFirst().dropLast(".icloud".count))
            return name.isEmpty || name.hasPrefix(".") ? nil : name
        }
        return entry.hasPrefix(".") ? nil : entry
    }

    /// The length the transcript gives (`duration` in `<name>.json`), for audio that is not on
    /// this device: opening it would download it.
    static func transcriptDuration(in folder: URL) -> TimeInterval? {
        guard let json = transcriptFile(in: folder), let data = try? Data(contentsOf: json),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["duration"] as? Double
    }

    /// The transcript of a recording folder: `<folder name>.json`.
    static func transcriptFile(in folder: URL) -> URL? {
        let json = folder.appending(path: "\(folder.lastPathComponent).json")
        return FileManager.default.fileExists(atPath: json.path) ? json : nil
    }

    /// A recording whose `.caf` was not converted (and is not being recorded): the library shows
    /// it, so it can be played or deleted instead of filling the disk unseen.
    static func unconvertedAudio(in folder: URL) -> URL? {
        let caf = folder.appending(path: "\(folder.lastPathComponent).caf")
        guard FileManager.default.fileExists(atPath: caf.path), RecordingMeta.read(from: folder)?.recording != true else { return nil }
        return caf
    }

    /// A conversion is not tried more often than this (an unreadable file would fail at every launch).
    static let maxConversionAttempts = 3

    /// Room to turn a `.caf` of `cafSize` bytes into `.m4a` (about a tenth of its size) and still
    /// keep the recording floor free. Unknown free space counts as room.
    static func hasRoomToConvert(cafSize: Int64, available: Int64?) -> Bool {
        guard let available else { return true }
        return available >= cafSize / 10 + DiskSpace.recordingFloor
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
        .map(canonical)
    }

    /// One spelling per recording folder, so `==` works everywhere (the recorder, the library, the
    /// transcription jobs, the open screen). On a device the app's container is `/var/mobile/…` but
    /// directory listings say `/private/var/mobile/…`: the same folder, yet unequal URLs. That kept a
    /// new recording from opening (and from transcribing automatically), and gave the open screen
    /// two names for one transcript (a lasting spinner).
    nonisolated static func canonical(_ folder: URL) -> URL {
        URL(filePath: folder.standardizedFileURL.path(percentEncoded: false), directoryHint: .isDirectory)
    }

    /// Recovers unfinished recordings: repairs the CAF header, converts to `.m4a`, clears the
    /// `recording` flag. Returns the folders that were recovered. A CAF that can't be converted
    /// stays and shows in the library (`unconvertedAudio`). A later launch tries again, only when
    /// there is room for the `.m4a` (`hasRoomToConvert`), and at most `maxConversionAttempts`
    /// times; an unreadable file is not tried again.
    @discardableResult
    static func recoverUnfinished(in dir: URL = documents, except active: URL? = nil,
                                  available: (URL) -> Int64? = { DiskSpace.available(at: $0) }) -> [URL] {
        var recovered: [URL] = []
        for caf in unfinished(in: dir, except: active) {
            let folder = caf.deletingLastPathComponent()
            CAFRepair.repair(caf)
            if isEmptyRecording(caf) {
                // Stopped or crashed before the first samples: nothing to keep.
                removeIfOnlyLeftovers(folder)
                continue
            }
            var meta = RecordingMeta.read(from: folder) ?? RecordingMeta(created: creationDate(of: folder))
            let before = meta
            let attempts = meta.conversionAttempts ?? 0
            let size = Int64(fileSize(caf) ?? 0)
            if attempts < maxConversionAttempts, hasRoomToConvert(cafSize: size, available: available(folder)) {
                do {
                    let m4a = try AudioExport.convertToM4A(caf)
                    meta.recording = nil
                    meta.conversionAttempts = nil
                    meta.setDuration(duration(of: m4a))
                    try? meta.write(to: folder)
                    recovered.append(folder)
                    continue
                } catch {
                    print("Bandje: recovery failed for \(folder.lastPathComponent): \(error)")
                    // A file AVFoundation can't open at all will never convert: don't try again.
                    let unreadable = (try? AVAudioFile(forReading: caf)) == nil
                    meta.conversionAttempts = unreadable ? maxConversionAttempts : attempts + 1
                }
            }
            // Kept as it is: no longer `recording`, so the library shows it.
            meta.recording = nil
            if meta.duration == nil { meta.setDuration(duration(of: caf)) }
            if meta != before { try? meta.write(to: folder) }
        }
        return recovered
    }

    /// Half files that a kill (or a crash) left behind, older than `age`: `.embedding-*.m4a` from
    /// putting the cover in, `<name>.converting.*` from an import or a conversion (on this iPhone
    /// only), and the folder of an import that was cut off before its audio was in place. Never in
    /// the recording that is running or a folder still marked `recording` (recovery's job).
    /// Returns what was removed.
    @discardableResult
    static func removeLeftovers(in dirs: [URL] = libraryFolders, local: URL = documents, except active: URL? = nil,
                                olderThan age: TimeInterval = 3_600, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        var removed: [URL] = []
        func remove(_ url: URL) -> Bool {
            guard (try? coordinated(writing: url, options: .forDeleting, { try fm.removeItem(at: $0) })) != nil else { return false }
            removed.append(url)
            return true
        }
        for dir in dirs {
            let onThisDevice = dir.standardizedFileURL == local.standardizedFileURL
            for folder in recordingFolders(in: dir)
            where folder.standardizedFileURL != active?.standardizedFileURL && RecordingMeta.read(from: folder)?.recording != true {
                let name = folder.lastPathComponent
                var removedConverting = false
                for entry in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
                    let embedding = entry.hasPrefix(".embedding-") && entry.hasSuffix(".m4a")
                    let converting = onThisDevice && entry.hasPrefix("\(name).converting.")
                    let file = folder.appending(path: entry)
                    guard embedding || converting, isOlder(file, than: age, now: now) else { continue }
                    if remove(file), converting { removedConverting = true }
                }
                let rest = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
                if removedConverting, rest.allSatisfy({ $0 == ".DS_Store" }) { _ = remove(folder) }
            }
        }
        return removed
    }

    /// Last changed more than `age` ago (unknown: no).
    static func isOlder(_ url: URL, than age: TimeInterval, now: Date = Date()) -> Bool {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
        return now.timeIntervalSince(date) > age
    }

    /// A CAF without a single audio frame (or with less than a header).
    static func isEmptyRecording(_ caf: URL) -> Bool {
        if let file = try? AVAudioFile(forReading: caf) { return file.length == 0 }
        return (fileSize(caf) ?? 0) < 4_096
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
                let audio = folder.appending(path: "\(name).\(file.pathExtension)")
                try fm.moveItem(at: file, to: audio)
                var meta = RecordingMeta(created: created)
                meta.setDuration(duration(of: audio))
                try? meta.write(to: folder)
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

    /// A file that is on this device: not in iCloud, or downloaded (reading one that is not would
    /// download it, or fail).
    static func isLocal(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var u = url
        u.removeAllCachedResourceValues()
        let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return v?.isUbiquitousItem != true || v?.ubiquitousItemDownloadingStatus == .current
            || v?.ubiquitousItemDownloadingStatus == .downloaded
    }

    static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// A recording's length (as on the Mac, ../specs/icloud-sync.md): the audio's own when it is on
    /// this device (`local`; opening audio still in iCloud would download it), else `duration` in
    /// `.bandje.json`, else the transcript's, else 0. The audio comes first, so the `RecordingID` of
    /// a local recording (saved positions) stays what it was.
    static func duration(audio: URL, local: Bool, meta: RecordingMeta?, folder: URL) -> TimeInterval {
        if local {
            let seconds = duration(of: audio)
            if seconds > 0 { return seconds }
        }
        if let d = meta?.duration, d > 0 { return d }
        return transcriptDuration(in: folder) ?? 0
    }

    /// Writes `duration` into the `.bandje.json` of each recording that has that file without it,
    /// when its audio is on this device (never downloads; `Recording.audioIsLocal`). Only that key
    /// changes, coordinated. Not for an unconverted `.caf` (recovery finishes those). Returns the
    /// folders written. Off the main actor.
    @discardableResult
    static func backfillDurations(_ recordings: [Recording]) -> [URL] {
        var written: [URL] = []
        for r in recordings where r.audioIsLocal && !r.isUnconverted {
            guard let audio = r.audio, let meta = RecordingMeta.read(from: r.folder), meta.duration == nil, meta.recording != true,
                  let stored = RecordingMeta.storedDuration(duration(of: audio)) else { continue }
            if (try? RecordingMeta.fillIn(duration: stored, in: r.folder)) == true { written.append(r.folder) }
        }
        return written
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
                  let audio = audioFile(in: folder) ?? unconvertedAudio(in: folder) else { return nil }
            let meta = RecordingMeta.read(from: folder)
            // Audio still in iCloud is not opened (that would download it): `.bandje.json`'s or the transcript's length.
            let local = isLocal(audio)
            return Recording(folder: folder, audio: audio, date: meta?.created
                                 ?? (try? audio.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? creationDate(of: folder),
                             duration: duration(audio: audio, local: local, meta: meta, folder: folder),
                             markers: meta?.markers ?? [],
                             transcript: transcriptFile(in: folder), summary: Summaries.file(in: folder),
                             location: meta?.location, color: TapeColor(meta?.color), audioIsLocal: local)
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
            let audio: URL
            if !hasVideo, ext != "caf", Storage.audioExtensions.contains(ext), isReadableAudio(local) {
                audio = folder.appending(path: "\(name).\(ext)")
                try fm.moveItem(at: local, to: audio)
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
                audio = folder.appending(path: "\(name).m4a")
                try fm.moveItem(at: temp, to: audio)
                try? fm.removeItem(at: local)
            }
            var meta = RecordingMeta(created: created)
            meta.imported = true  // the Mac never treats it as its own stereo recording
            meta.setDuration(Storage.duration(of: audio))
            try meta.write(to: folder)
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

    /// Removes what the share extension was still copying into `inbox/.incoming` when it was
    /// killed, older than `age`. Returns what was removed.
    @discardableResult
    static func removeStaleIncoming(in inbox: URL, olderThan age: TimeInterval = 3_600, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        let incoming = inbox.appending(path: ".incoming", directoryHint: .isDirectory)
        let files = (try? fm.contentsOfDirectory(at: incoming, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { Storage.isOlder($0, than: age, now: now) && (try? fm.removeItem(at: $0)) != nil }
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
    /// An import from the Watch is running (`importFromWatch`); one at a time.
    @ObservationIgnored var importingFromWatch = false
    /// A delivery came while `importingFromWatch`: import once more afterwards.
    @ObservationIgnored var importFromWatchAgain = false
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

    /// Rescans the library. Refreshes come from several places at once (the folder watcher, a
    /// finished transcription, iCloud); they run one after another, in the order asked, so an older
    /// scan never lands after a newer one (that brought back a state from before a transcript was
    /// written: a lasting spinner on the open recording). Returns when this refresh has landed.
    func refresh(except active: URL? = nil) async {
        let previous = lastRefresh
        let task = Task { [weak self] in
            await previous?.value
            await self?.rescan(except: active)
        }
        lastRefresh = task
        await task.value
    }
    @ObservationIgnored private var lastRefresh: Task<Void, Never>?

    /// Rescans Documents off the main actor (durations need the audio files opened). Loose audio
    /// files added via the Files app get their own folder first.
    private func rescan(except active: URL?) async {
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
        scans += 1
        backfill(recordings)
    }

    /// Older recordings get their length in `.bandje.json` (a hint for the other device while the
    /// audio is still in iCloud there), in the background, one round at a time.
    private func backfill(_ recordings: [Recording]) {
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            _ = await Task.detached(priority: .utility) { Storage.backfillDurations(recordings) }.value
            self?.backfillTask = nil
        }
    }
    @ObservationIgnored private var backfillTask: Task<Void, Never>?

    /// Counts finished scans: an open recording reads its markers again after each one, so a note
    /// changed on the Mac (only `.markers.json` changes) shows without reopening it.
    private(set) var scans = 0

    struct CachedText: Sendable {
        let modified: Date
        let texts: (search: String, preview: String)?
    }
    /// The start of each transcript, for the list.
    private(set) var previews: [URL: String] = [:]
    /// Search text per transcript file with its modification date.
    @ObservationIgnored private var searchCache: [URL: CachedText] = [:]

    /// Covers in the `.m4a`s, one at a time so the interface stays smooth (`AudioExport.embedCover`):
    /// a new one after a rename or colour made on this device (`ownChanges`), and one for a recording
    /// that never had one. A rename or colour from the Mac gets its cover there (../specs/icloud-sync.md).
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
                    guard let self else { return }
                    let own = self.ownChanges.remove(Storage.canonical(recording.folder)) != nil
                    guard own || recording.audioIsLocal else { continue }
                    await AudioExport.embedCover(recording, own: own)
                    await Task.yield()
                }
            }
        }
    }
    @ObservationIgnored private var coverTask: Task<Void, Never>?
    @ObservationIgnored private var coversAgain = false
    /// Folders whose title or colour this device changed itself, waiting for their new cover.
    @ObservationIgnored private var ownChanges: Set<URL> = []

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

    /// At launch: clear half files a kill left, recover unfinished recordings, then scan, then
    /// watch Documents.
    func launch(except active: URL? = nil) async {
        _ = await Task.detached(priority: .userInitiated) {
            Storage.removeLeftovers(except: active)
            if let inbox = Importer.inbox { Importer.removeStaleIncoming(in: inbox) }
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
        await CloudSync.shared.resolveFolder()  // may run before the library's own launch
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
        let folder = Storage.canonical(try Storage.rename(recording.folder, to: title))
        let renamed = Recording(folder: folder, audio: Storage.audioFile(in: folder), date: recording.date,
                                duration: recording.duration, markers: recording.markers,
                                transcript: Storage.transcriptFile(in: folder), summary: Summaries.file(in: folder),
                                location: recording.location, color: recording.color, audioIsLocal: recording.audioIsLocal)
        Playback.moved(from: recording.folder, to: renamed)
        ownChanges.insert(folder)
        await refresh(except: Recorder.shared.folder)
        return renamed
    }

    /// The cassette's colour: kept in `.bandje.json` (coordinated, so it syncs through iCloud).
    func setColor(_ color: TapeColor, of recording: Recording) async throws {
        try RecordingMeta.update(in: recording.folder, created: recording.date) { $0.color = color.stored }
        ownChanges.insert(Storage.canonical(recording.folder))
        var updated = recording
        updated.color = color
        Playback.moved(from: recording.folder, to: updated)
        await refresh(except: Recorder.shared.folder)
    }

    func delete(_ recording: Recording) async throws {
        Transcriptions.shared.cancel(recording.folder)
        SummaryJobs.shared.cancel(recording.folder)
        Playback.removed(recording)  // P9
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
/// devices add comes in through an `NSMetadataQuery`: the small files (metadata, transcripts,
/// summaries, covers, markers) download right away, audio only when it is played or transcribed.
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

    private init() {
        // Signed in or out of iCloud (or iCloud Drive turned on or off) while Bandje runs: the
        // setting's availability follows. Syncing itself is not switched by this.
        NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                CloudSync.shared.isAvailable = FileManager.default.ubiquityIdentityToken != nil
            }
        }
    }

    /// At launch: resumes syncing when the setting is on and iCloud is there.
    func launch() async {
        isAvailable = FileManager.default.ubiquityIdentityToken != nil
        let local = Storage.documents.appending(path: "Templates", directoryHint: .isDirectory)
        await Task.detached {
            Summaries.seedIfMissing(local)  // the examples, once
            Summaries.addLaterExamples(in: local)
        }.value
        await resolveFolder()
        guard UserDefaults.standard.bool(forKey: Self.settingKey), let folder = Storage.cloud else { return }
        isOn = true
        await Task.detached { Self.shareTemplates(from: local, to: folder) }.value
        // Recordings saved here while syncing was on but not reached (a job ran when it was
        // turned on, or the folder could not move then).
        await publishLocalRecordings(to: folder)
        startQuery()
    }

    /// Sets `Storage.cloud` from the setting if that has not happened yet. Before anything is saved
    /// that may run before the library appears (a Watch recording received with Band·je woken in
    /// the background, a recording stopped from the Lock Screen), so it goes to iCloud too.
    func resolveFolder() async {
        guard Storage.cloud == nil, UserDefaults.standard.bool(forKey: Self.settingKey),
              let folder = await Self.cloudDocuments(),
              UserDefaults.standard.bool(forKey: Self.settingKey) else { return }  // not turned off meanwhile
        Storage.setCloud(folder)
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
        Playback.stop()  // the files it has open are about to move
        Storage.setCloud(folder)
        UserDefaults.standard.set(true, forKey: Self.settingKey)
        isOn = true
        let local = Storage.documents.appending(path: "Templates", directoryHint: .isDirectory)
        await Task.detached { Self.shareTemplates(from: local, to: folder) }.value
        await publishLocalRecordings(to: folder)
        startQuery()
        await Library.shared.refresh(except: Recorder.shared.folder)
    }

    /// A transcription or summary is running or queued (its files are written at the end).
    static var jobsRunning: Bool { Transcriptions.shared.isBusy || SummaryJobs.shared.isBusy }

    /// Moves the finished recordings on this iPhone to iCloud (`publishPlan`). Not the one being
    /// recorded, and not one a transcription or summary is working on (it would write into a
    /// folder that moved): those follow at the next launch.
    private func publishLocalRecordings(to cloud: URL) async {
        var skip = Set([Recorder.shared.folder].compactMap { $0?.standardizedFileURL })
        for folder in Storage.recordingFolders(in: Storage.documents)
        where Transcriptions.shared.isRunning(folder) || SummaryJobs.shared.isRunning(folder) {
            skip.insert(folder.standardizedFileURL)
        }
        let busy = skip
        await Task.detached {
            for local in Storage.recordingFolders(in: Storage.documents)
            where !busy.contains(local.standardizedFileURL) && Storage.audioFile(in: local) != nil {
                switch Self.publishPlan(for: local, cloud: cloud) {
                case .publish: _ = Storage.publish(local)
                case .removeLocal: try? Storage.delete(local)
                case .keepLocal: break
                }
            }
        }.value
    }

    /// Turns syncing off. iCloud keeps everything; recordings that are fully on this iPhone are
    /// copied here so they stay in the library.
    func turnOff() async {
        guard !isBusy, let cloud = Storage.cloud else { return }
        isBusy = true
        defer { isBusy = false }
        stopQuery()
        Playback.stop()
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

    /// What turning syncing on does with a recording on this iPhone.
    enum PublishPlan: Equatable {
        /// Not in iCloud yet: move it there.
        case publish
        /// Already in iCloud, complete and the same to the byte (turning syncing off copied it
        /// here): the copy on this iPhone goes, the one in iCloud stays.
        case removeLocal(cloud: URL)
        /// Probably in iCloud already, but not certainly the same or not complete there (still
        /// downloading, or changed here since): it stays on this iPhone and is not copied again.
        case keepLocal
    }

    /// Turning syncing off copies the recordings in iCloud back to this iPhone; turning it on again
    /// must not publish those copies as new recordings (`A 2`, `A 3`… with every round). Never
    /// removes anything that is not also in iCloud.
    nonisolated static func publishPlan(for local: URL, cloud: URL) -> PublishPlan {
        guard let twin = sameRecording(as: local, in: cloud) else { return .publish }
        return isCompleteCopy(of: local, in: twin) ? .removeLocal(cloud: twin) : .keepLocal
    }

    /// The folder in `cloud` with the same recording as `local`: the same start (`created` in
    /// `.bandje.json`, to the second) and length, or the same folder name and an audio file of
    /// the same size. When the length or size in iCloud can't be read without downloading, a
    /// folder with the same start or name counts as the same (the plan then keeps the local copy).
    nonisolated static func sameRecording(as local: URL, in cloud: URL) -> URL? {
        let localMeta = RecordingMeta.read(from: local)
        let localAudio = Storage.audioFile(in: local)
        for folder in Storage.recordingFolders(in: cloud) {
            let cloudAudio = Storage.audioFile(in: folder)
            if folder.lastPathComponent == local.lastPathComponent {
                guard let localAudio, let cloudAudio, Storage.isLocal(cloudAudio) else { return folder }
                if Storage.fileSize(localAudio) == Storage.fileSize(cloudAudio) { return folder }
            }
            if let created = localMeta?.created, let other = RecordingMeta.read(from: folder)?.created,
               abs(created.timeIntervalSince(other)) < 1 {
                guard let localAudio, let cloudAudio, Storage.isLocal(cloudAudio) else { return folder }
                if abs(Storage.duration(of: localAudio) - Storage.duration(of: cloudAudio)) < 1 { return folder }
            }
        }
        return nil
    }

    /// Every file of `local` is in `cloud` (downloaded) with the same name and the same bytes.
    /// Covers are left out: they are made again from the title, length and colour.
    nonisolated static func isCompleteCopy(of local: URL, in cloud: URL) -> Bool {
        let fm = FileManager.default
        guard isDownloaded(cloud),
              let files = try? fm.contentsOfDirectory(atPath: local.path) else { return false }
        var complete = true
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: cloud, options: [], error: &coordinationError) { cloud in
            for name in files where name != ".DS_Store" && !name.hasPrefix(".cover-") && !name.hasPrefix(".embedding-") {
                let mine = local.appending(path: name), theirs = cloud.appending(path: name)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: mine.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                      fm.contentsEqual(atPath: mine.path, andPath: theirs.path) else {
                    complete = false
                    return
                }
            }
        }
        return coordinationError == nil && complete
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

    /// Fetches the small files that are not on this iPhone yet, then rescans. Audio stays in
    /// iCloud until it is played or transcribed (`Playback.ensureDownloaded`): a library of hours
    /// of recordings would fill the iPhone otherwise.
    private func queryChanged() {
        guard let query else { return }
        query.disableUpdates()
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  !Storage.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()
        Library.shared.scheduleRefresh()
    }
}
