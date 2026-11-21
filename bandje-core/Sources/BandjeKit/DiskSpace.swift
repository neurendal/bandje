// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Free space for recording (owner, 2026-11-09, after a tester's iPhone filled up): a recording
/// does not start, and a running one stops and is kept, when the disk gets this low. The same
/// limit on the Mac and the iPhone; the Watch has its own (200 MB, bandje-ios/docs/watch.md).
public enum DiskSpace {
    /// Below this, recording stops (and does not start): iOS and macOS need room themselves, and
    /// the app needs room to finish the recording (conversion, metadata).
    public static let recordingFloor: Int64 = 1_000_000_000
    /// Below this, the app warns that the disk is getting full.
    public static let warningLevel: Int64 = 2_000_000_000
    /// How often a running recording checks.
    public static let checkInterval: TimeInterval = 10

    public enum Level: Equatable, Sendable {
        case ok, low, tooLow
    }

    /// The bytes the system would make free for something important (purgeable space counted),
    /// on the volume of `url`; nil when it can't be read.
    public static func available(at url: URL) -> Int64? {
        var u = url
        u.removeAllCachedResourceValues()
        let values = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                     .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// The level for `bytes` free. Unknown (nil) is `.ok`: never stop a recording on a failed read.
    public static func level(_ bytes: Int64?) -> Level {
        guard let bytes else { return .ok }
        if bytes < recordingFloor { return .tooLow }
        if bytes < warningLevel { return .low }
        return .ok
    }

    /// The level on the volume of `url`.
    public static func level(at url: URL) -> Level { level(available(at: url)) }
}
