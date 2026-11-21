// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Where the user stopped listening, per recording; the global speed; the last played recording.
/// Local only (UserDefaults), not synced in v1 (specs/player.md 3.2).
@MainActor
public final class PlaybackPositionStore {
    private let defaults: UserDefaults
    private let positionsKey: String
    private let rateKey: String
    private let lastKey: String

    public init(defaults: UserDefaults = .standard, prefix: String = "player.") {
        self.defaults = defaults
        positionsKey = prefix + "positions"
        rateKey = prefix + "rate"
        lastKey = prefix + "lastPlayed"
    }

    private var positions: [String: Double] {
        get { defaults.dictionary(forKey: positionsKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: positionsKey) }
    }

    public func position(for id: RecordingID) -> TimeInterval? {
        positions[id.key]
    }

    public func setPosition(_ time: TimeInterval, for id: RecordingID) {
        positions[id.key] = max(0, time)
    }

    public func removePosition(for id: RecordingID) {
        positions[id.key] = nil
    }

    /// 1 until the user picks another speed.
    public var rate: Float {
        get {
            let stored = defaults.float(forKey: rateKey)
            return stored > 0 ? stored : 1
        }
        set { defaults.set(newValue, forKey: rateKey) }
    }

    /// Restored, paused, at the next launch (P12).
    public var lastPlayed: RecordingID? {
        get { defaults.data(forKey: lastKey).flatMap { try? JSONDecoder().decode(RecordingID.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: lastKey)
            } else {
                defaults.removeObject(forKey: lastKey)
            }
        }
    }
}
