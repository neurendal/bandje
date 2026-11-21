// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The markers of one recording and their notes (specs/markers.md), shared by the Mac and the
/// iPhone app.
///
/// - Times are seconds in the audio, 0.1 s, kept in `.bandje.json` `markers` as before, so older
///   app versions keep reading and writing them.
/// - Notes go into the hidden `.markers.json` next to it (the shipped iPhone version rewrites
///   `.bandje.json` and would drop a key it does not know; it never touches another file).
public struct Markers: Equatable, Sendable {
    /// Sorted, rounded to 0.1 s, no two closer than `mergeDistance`.
    public private(set) var times: [Double]
    /// By `Markers.key(time)`; only for times in `times`.
    public private(set) var notes: [String: String]

    public static let metaFileName = ".bandje.json"
    public static let notesFileName = ".markers.json"
    /// A new marker this close to an existing one is that one (a double tap, the same moment twice).
    public static let mergeDistance: Double = 1
    /// A note longer than this is cut (one line, specs/markers.md 5).
    public static let maxNoteLength = 200
    /// While playing, a note shows from this long before its marker…
    public static let chipLead: Double = 3
    /// …until this long after it (specs/markers.md 6).
    public static let chipTrail: Double = 5

    public init(times: [Double] = [], notes: [String: String] = [:]) {
        var clean: [Double] = []
        for t in times.map(Self.round).sorted() where t >= 0 {
            if let last = clean.last, t - last < Self.mergeDistance { continue }
            clean.append(t)
        }
        self.times = clean
        let keys = Set(clean.map(Self.key))
        self.notes = notes.compactMapValues(Self.clean).filter { keys.contains($0.key) }
    }

    public var isEmpty: Bool { times.isEmpty }
    public var count: Int { times.count }

    /// 0.1 s, as the iPhone stores them.
    public static func round(_ time: Double) -> Double { (time * 10).rounded() / 10 }

    /// The key of a time in `.markers.json`: one decimal, "95.0".
    public static func key(_ time: Double) -> String { String(format: "%.1f", round(time)) }

    public func note(at time: Double) -> String? { notes[Self.key(time)] }

    /// The marker at `time` (within 0.05 s), nil when there is none.
    public func marker(at time: Double) -> Double? {
        times.first { abs($0 - time) < 0.05 }
    }

    // MARK: Changing

    /// A marker at `time` (not before 0, not after `duration` when given). Close to an existing
    /// one (`mergeDistance`): that one, nothing added. Returns the marker's time.
    @discardableResult
    public mutating func add(at time: Double, duration: Double? = nil) -> Double {
        var t = Self.round(max(0, time))
        if let duration { t = min(t, Self.round(duration)) }
        if let near = times.min(by: { abs($0 - t) < abs($1 - t) }), abs(near - t) < Self.mergeDistance { return near }
        times.append(t)
        times.sort()
        return t
    }

    /// Removes the marker at `time` and its note.
    public mutating func remove(at time: Double) {
        guard let t = marker(at: time) else { return }
        times.removeAll { $0 == t }
        notes[Self.key(t)] = nil
    }

    /// Sets (or with nil/blank removes) the note of the marker at `time`; no marker, nothing.
    public mutating func setNote(_ text: String?, at time: Double) {
        guard let t = marker(at: time) else { return }
        notes[Self.key(t)] = text.flatMap(Self.clean)
    }

    /// One line, trimmed, at most `maxNoteLength` characters; nil when empty.
    static func clean(_ text: String) -> String? {
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxNoteLength))
    }

    // MARK: Where they show

    /// The marker with a note to show while playing at `position` (specs/markers.md 6): from
    /// `chipLead` before to `chipTrail` after it; the nearest when two overlap.
    public func noteNear(_ position: Double) -> (time: Double, text: String)? {
        times.filter { position >= $0 - Self.chipLead && position <= $0 + Self.chipTrail && note(at: $0) != nil }
            .min { abs($0 - position) < abs($1 - position) }
            .map { ($0, note(at: $0)!) }
    }

    /// For each marker, the index of the part of the transcript it falls in: the last part that
    /// starts at or before it (the first part for a marker before the first word). `starts` are the
    /// parts' start times in order (sentences or turns). Empty `starts`: nothing.
    public func placed(in starts: [Double]) -> [Int: [Double]] {
        guard !starts.isEmpty else { return [:] }
        var out: [Int: [Double]] = [:]
        for t in times {
            let i = (starts.lastIndex { $0 <= t + 0.05 }) ?? 0
            out[i, default: []].append(t)
        }
        return out
    }

    /// The line in a text export: "🚩 12:34 Actiepunt" (or "🚩 12:34" without a note). `clock`
    /// formats the time as the app does elsewhere.
    public func line(at time: Double, clock: (Double) -> String) -> String {
        "🚩 " + clock(time) + (note(at: time).map { " " + $0 } ?? "")
    }

    // MARK: Files

    /// The markers of the recording in `folder`: the times from `.bandje.json`, the notes from
    /// `.markers.json`. Missing or unreadable files: none.
    public static func read(from folder: URL) -> Markers {
        let meta = (try? Data(contentsOf: folder.appendingPathComponent(metaFileName)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let times = (meta?["markers"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        let notesObject = (try? Data(contentsOf: folder.appendingPathComponent(notesFileName)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let notes = (notesObject?["notes"] as? [String: String]) ?? [:]
        return Markers(times: times, notes: notes)
    }

    /// Writes the times into `.bandje.json` (every other key stays as it is; a folder without one
    /// gets none: the app makes that file) and the notes into `.markers.json` (removed when there
    /// are none). Coordinated, so iCloud Drive syncs it as one change.
    public func write(to folder: URL) throws {
        let metaURL = folder.appendingPathComponent(Self.metaFileName)
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try Self.coordinated(metaURL) { url in
                var meta = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                // As decimals: JSONSerialization writes 312.4 as 312.39999999999998.
                meta["markers"] = times.map { NSDecimalNumber(string: Self.key($0)) }
                try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    .write(to: url, options: .atomic)
            }
        }
        let notesURL = folder.appendingPathComponent(Self.notesFileName)
        try Self.coordinated(notesURL) { url in
            if notes.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else {
                try JSONSerialization.data(withJSONObject: ["notes": notes], options: [.prettyPrinted, .sortedKeys])
                    .write(to: url, options: .atomic)
            }
        }
    }

    private static func coordinated(_ url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
}
