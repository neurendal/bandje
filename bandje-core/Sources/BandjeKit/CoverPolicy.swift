// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// When a device writes a recording's cover into its `.m4a` and the cover's key (`coverKey`) into
/// its `.bandje.json` (specs/icloud-sync.md, owner 2026-11-10). The same rule on the Mac and the
/// iPhone, so a device never undoes a change made on another one.
///
/// A rename or a new colour that arrives through iCloud is never a reason to make a cover: the
/// device that made the change writes the new audio and key, and those sync. A device that reacted
/// itself would write into its own copy of `.bandje.json`, which may not have the other device's
/// newest keys yet; that write is newer, wins in iCloud and syncs back (a colour chosen together
/// with a new name flipped back on both devices).
public enum CoverPolicy {
    public enum Plan: Equatable, Sendable {
        /// Leave the audio and `.bandje.json` as they are.
        case leave
        /// Write the cover for the current title, length and colour into the audio, and its key.
        case embed
        /// Remove `coverKey`: this device changed the title or colour but does not have the audio
        /// here, so the cover in the audio is old; a device that has the audio fills it in (a
        /// recording without `coverKey` gets one where its files are current).
        case clearKey
    }

    /// - Parameters:
    ///   - storedKey: `coverKey` in `.bandje.json` (nil: none, or no file).
    ///   - currentKey: the key for the recording's title, length and colour as this device sees them.
    ///   - ownChange: this device just made the recording, imported it, renamed it or changed its
    ///     colour (not: the library saw a change that came from iCloud).
    ///   - metaIsCurrent: `.bandje.json` is not waiting in iCloud (`isUpToDate`).
    ///   - audioIsCurrent: the audio is on this device and the newest version (`isUpToDate`).
    public static func plan(storedKey: String?, currentKey: String, ownChange: Bool,
                            metaIsCurrent: Bool, audioIsCurrent: Bool) -> Plan {
        // Never write into a `.bandje.json` that is older than the one in iCloud.
        guard metaIsCurrent, storedKey != currentKey else { return .leave }
        guard audioIsCurrent else { return ownChange && storedKey != nil ? .clearKey : .leave }
        // Our own change, or a recording that never had a cover (older ones, a new one).
        return ownChange || storedKey == nil ? .embed : .leave
    }

    /// `url` is not waiting in iCloud: it is on this device and the newest version, or not in
    /// iCloud at all; or it does not exist and no iCloud placeholder (`.<name>.icloud`, iOS) stands
    /// for it. A file whose newer version is still coming (`.downloaded`, not `.current`) is not.
    public static func isUpToDate(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
            return !fm.fileExists(atPath: placeholder.path)
        }
        var u = url
        u.removeAllCachedResourceValues()
        guard let values = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) else {
            return false
        }
        return values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus == .current
    }
}
