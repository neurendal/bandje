// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// What the Watch sends with a recording through `WCSession.transferFile(_:metadata:)`
/// (docs/watch.md 4). Compiled into the Watch app and the iPhone app, so both read and write the
/// same keys. The file itself is `<title>.aac` (ADTS; `.m4a` from earlier versions): mono AAC, 48 kHz,
/// 64 kbit/s.
struct WatchTransfer: Equatable, Sendable {
    /// Bumped when the keys change incompatibly; the iPhone skips versions it does not know.
    static let version = 1

    /// When recording started (to the second: it becomes `created` in `.bandje.json`).
    var created: Date
    /// Seconds of audio.
    var duration: Double
    /// Marker times in seconds of audio, 0.1 s (`../specs/markers.md`).
    var markers: [Double]
    /// The default title, in the Watch's language ("Opname 8 nov 10:30").
    var title: String

    var metadata: [String: Any] {
        [
            "bandje": Self.version,
            "created": Self.formatter.string(from: created),
            "duration": duration,
            "markers": markers,
            "title": title,
        ]
    }

    init(created: Date, duration: Double, markers: [Double], title: String) {
        self.created = created
        self.duration = duration
        self.markers = markers
        self.title = title
    }

    /// nil when it is not a Band·je transfer or a newer, unknown version.
    init?(metadata: [String: Any]?) {
        guard let m = metadata, (m["bandje"] as? Int) == Self.version,
              let created = (m["created"] as? String).flatMap(Self.formatter.date(from:)),
              let duration = (m["duration"] as? NSNumber)?.doubleValue,
              let title = m["title"] as? String, !title.isEmpty else { return nil }
        self.created = created
        self.duration = duration
        self.markers = ((m["markers"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        self.title = title
    }

    /// A file name for the title: no path separators or a leading dot.
    static func fileName(for title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        while name.hasPrefix(".") { name.removeFirst() }
        return (name.isEmpty ? "Watch" : name) + ".m4a"
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
