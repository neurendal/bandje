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
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case created, markers, recording, location, color, coverKey
    }

    static func url(in folder: URL) -> URL { folder.appendingPathComponent(fileName) }

    static func read(from folder: URL) -> RecordingMeta? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? decoder.decode(RecordingMeta.self, from: data)
    }

    /// Writes our keys over the file that is there, so keys a newer iPhone (or Mac) wrote and this
    /// version doesn't know survive. A key of ours that is nil now is removed.
    func write(to folder: URL) throws {
        let url = Self.url(in: folder)
        var out = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        for key in CodingKeys.allCases { out[key.rawValue] = nil }
        let ours = try JSONSerialization.jsonObject(with: Self.encoder.encode(self)) as? [String: Any] ?? [:]
        out.merge(ours) { _, new in new }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url, options: .atomic)
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
