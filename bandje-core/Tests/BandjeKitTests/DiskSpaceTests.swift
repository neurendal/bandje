// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import BandjeKit

@Suite("DiskSpace: stop recording before the disk is full")
struct DiskSpaceTests {
    @Test("Levels: below 1 GB too low, below 2 GB low, unknown is ok")
    func levels() {
        #expect(DiskSpace.level(nil) == .ok)
        #expect(DiskSpace.level(0) == .tooLow)
        #expect(DiskSpace.level(999_999_999) == .tooLow)
        #expect(DiskSpace.level(1_000_000_000) == .low)
        #expect(DiskSpace.level(1_999_999_999) == .low)
        #expect(DiskSpace.level(2_000_000_000) == .ok)
    }

    @Test("The temporary directory's volume has a readable free space")
    func readsVolume() {
        let free = DiskSpace.available(at: FileManager.default.temporaryDirectory)
        #expect(free != nil)
        #expect((free ?? 0) > 0)
    }
}
