import BandjeKit
import Foundation

/// Per-recording metadata that is not the transcript: `<folder>/.bandje.json` (hidden, moves with the
/// folder). The same file as the iPhone app writes (bandje-ios `Library.swift`), so both read each other's.
struct RecordingMeta: Codable, Equatable {
    var created: Date
    /// Seconds of recording time the user marked (iPhone); kept, not made on the Mac.
    var markers: [Double] = []
    /// True while the recording is in progress; a folder with this set and no running recorder is unfinished.
    var recording: Bool? = nil
    /// Where the recording was started (iPhone, when the user turned that on).
    var location: RecordedLocation? = nil
    /// The cassette's colour, chosen on the iPhone or the Mac (`CassetteColor` names); nil = the default red.
    var color: String? = nil
    /// `CoverArt.key` of the cover in the recording's `.m4a` (iPhone or Mac), so it is made once per
    /// title, length and colour.
    var coverKey: String? = nil
    /// An imported file (Transcribe File… on the Mac, Open in / + on the iPhone), not a recording
    /// either app made: never split into me (left) and the other side (right), even in stereo.
    var imported: Bool? = nil
    /// The recording's length in seconds (0.1 s), a hint for when the audio is not on this Mac (still
    /// in iCloud): the audio's own length always comes first (`Library.duration`). Written when a
    /// recording is finished or imported, and filled in for older ones whose audio is here
    /// (`Library.backfillDurations`). The shipped iPhone 1.0 drops it when it rewrites this file;
    /// it is filled in again then.
    var duration: Double? = nil

    static let fileName = ".bandje.json"

    init(created: Date, markers: [Double] = [], recording: Bool? = nil, location: RecordedLocation? = nil) {
        self.created = created
        self.markers = markers
        self.recording = recording
        self.location = location
    }

    /// Only `created` is required: a file with just a date (older, or written by hand) still counts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = try c.decode(Date.self, forKey: .created)
        markers = try c.decodeIfPresent([Double].self, forKey: .markers) ?? []
        recording = try c.decodeIfPresent(Bool.self, forKey: .recording)
        location = try c.decodeIfPresent(RecordedLocation.self, forKey: .location)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        coverKey = try c.decodeIfPresent(String.self, forKey: .coverKey)
        imported = try c.decodeIfPresent(Bool.self, forKey: .imported)
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case created, markers, recording, location, color, coverKey, imported, duration
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

    /// A number as JSON writes it: `312.4`, not `312.39999999999998` (JSONSerialization's way with a
    /// Double), as `Markers.write` (BandjeKit) writes the markers.
    static func decimal(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: "\(value)")
    }

    static func url(in folder: URL) -> URL { folder.appendingPathComponent(fileName) }

    static func read(from folder: URL) -> RecordingMeta? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? decoder.decode(RecordingMeta.self, from: data)
    }

    /// Writes our keys over the file that is there, so keys a newer iPhone (or Mac) wrote and this
    /// version doesn't know survive. A key of ours that is nil now is removed. Read and written in
    /// one coordinated go, as `update` (`Files`); in iCloud that can wait, so off the main thread
    /// there (the app writes it on the main thread only in the local or staging folder).
    func write(to folder: URL) throws {
        let ours = try json()
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: Self.url(in: folder), options: .forReplacing, error: &coordinationError) { url in
            do {
                var out = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                for key in CodingKeys.allCases { out[key.rawValue] = nil }
                out.merge(ours) { _, new in new }
                try Self.writeJSON(out, to: url)
            } catch {
                bodyError = error
            }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    /// Our keys as they go into the file.
    private func json() throws -> [String: Any] {
        var ours = try JSONSerialization.jsonObject(with: Self.encoder.encode(self)) as? [String: Any] ?? [:]
        ours["markers"] = markers.map(Self.decimal)
        if let duration { ours["duration"] = Self.decimal(duration) }
        return ours
    }

    /// The file as both apps write it: sorted keys, readable, slashes as they are.
    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url, options: .atomic)
    }

    /// Puts `duration` (already `storedDuration`) into the folder's `.bandje.json` when it has none
    /// yet; every other key stays as it is (`update`). No file, or one whose newer version is still
    /// coming from iCloud: nothing (the app makes that file; the other device's keys must not be
    /// undone). Returns true when it wrote.
    static func fillIn(duration: Double, in folder: URL) throws -> Bool {
        try update(in: folder, onlyIfCurrent: true) { out in
            guard out["created"] != nil, out["duration"] == nil, out["recording"] as? Bool != true else { return false }
            out["duration"] = decimal(duration)
            return true
        }
    }

    /// Changes only the keys `body` sets (nil removes one) in the folder's `.bandje.json`, read and
    /// written in one coordinated go (the file may be in iCloud), so whatever else is in it right now
    /// stays: a colour or marker written meanwhile here, or one arriving from the iPhone. Never from
    /// a `RecordingMeta` read earlier: that would put its old values back (a cover made after a rename
    /// put back the colour chosen while it was made). `body` returns false to leave the file as it is.
    /// No file: one with just `created` when that is given, else nothing. `onlyIfCurrent`: nothing
    /// either when the file here is not the newest one in iCloud (`CoverPolicy.isUpToDate`): writes
    /// this Mac makes by itself (a cover's key, a length) never go over a change from the iPhone that
    /// has not arrived yet. Returns true when it wrote.
    @discardableResult
    static func update(in folder: URL, created: Date? = nil, onlyIfCurrent: Bool = false,
                       _ body: (inout [String: Any]) -> Bool) throws -> Bool {
        let url = url(in: folder)
        var wrote = false
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do {
                if onlyIfCurrent, !CoverPolicy.isUpToDate(url) { return }
                var out: [String: Any]
                if FileManager.default.fileExists(atPath: url.path) {
                    guard let read = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { return }
                    out = read
                } else if let created {
                    out = try RecordingMeta(created: created).json()
                } else {
                    return
                }
                guard body(&out) else { return }
                try writeJSON(out, to: url)
                wrote = true
            } catch {
                bodyError = error
            }
        }
        if let error = coordinationError ?? bodyError { throw error }
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

struct RecordedLocation: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in metres.
    var accuracy: Double
}

/// Every marker change of the app (flags set while recording, the window's add, remove, note and
/// undo) goes through one serial queue: each reads the folder's markers, changes them and writes
/// them back (`Markers`, BandjeKit), so two quick changes never overwrite each other. Not the main
/// queue: `Markers.write` is coordinated, and the window's `FolderPresenter` runs on the main queue.
enum MarkerFile {
    private static let queue = DispatchQueue(label: "com.neurendal.bandje.markers")

    /// Changes the markers in `folder` on the queue and returns them as written (unchanged: not written).
    static func change(in folder: URL, _ body: @escaping @Sendable (inout Markers) -> Void) async throws -> Markers {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try changeNow(in: folder, body)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// The same without waiting (a flag while recording): `failed` runs on the main queue when the write fails.
    static func changeLater(in folder: URL, _ body: @escaping @Sendable (inout Markers) -> Void, failed: @escaping @Sendable () -> Void) {
        queue.async {
            do { _ = try changeNow(in: folder, body) } catch { DispatchQueue.main.async(execute: failed) }
        }
    }

    /// Waits until every change asked for so far is on disk (before `.bandje.json` is read and
    /// written again when a recording finishes).
    static func drain() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    /// The same, blocking (quitting during a recording).
    static func drainNow() { queue.sync {} }

    private static func changeNow(in folder: URL, _ body: (inout Markers) -> Void) throws -> Markers {
        let before = Markers.read(from: folder)
        var markers = before
        body(&markers)
        if markers != before { try markers.write(to: folder) }
        return markers
    }
}
