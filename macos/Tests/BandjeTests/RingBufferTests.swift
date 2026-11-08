import Foundation
import Testing
@testable import Bandje

// Swift Testing, not XCTest: XCTest enumerates every Objective-C class at start
// (objc_copyClassList), which realizes the SDK's macOS 27-only CoreAI session class
// and crashes on macOS 26.
struct RingBufferTests {
    @Test func writeReadWrapsAround() {
        let ring = RingBuffer(capacity: 8)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        defer { out.deallocate() }

        #expect(ring.write([1, 2, 3, 4, 5, 6], count: 6))
        #expect(ring.read(into: out, maxCount: 4) == 4)
        #expect(Array(UnsafeBufferPointer(start: out, count: 4)) == [1, 2, 3, 4])
        // Wraps past the end of storage.
        #expect(ring.write([7, 8, 9, 10, 11], count: 5))
        #expect(ring.read(into: out, maxCount: 8) == 7)
        #expect(Array(UnsafeBufferPointer(start: out, count: 7)) == [5, 6, 7, 8, 9, 10, 11])
        #expect(ring.read(into: out, maxCount: 8) == 0)
    }

    @Test func overflowDropsWholeBlock() {
        let ring = RingBuffer(capacity: 4)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { out.deallocate() }

        #expect(ring.write([1, 2, 3], count: 3))
        #expect(!ring.write([4, 5], count: 2))
        #expect(ring.dropped.load(ordering: .relaxed) == 2)
        #expect(ring.read(into: out, maxCount: 4) == 3)
        #expect(Array(UnsafeBufferPointer(start: out, count: 3)) == [1, 2, 3])
    }
}

/// The record screen's VU meter reads the level of the latest audio callback (both channels),
/// not the peak of the whole recording.
@Test func recorderStatsKeepTheCurrentLevel() {
    let stats = RecorderStats()
    #expect(stats.level == 0)
    stats.noteLevel(mic: 0.2, system: 0.05)
    #expect(stats.level == 0.2)
    stats.noteLevel(mic: 0.01, system: 0.03)
    #expect(stats.level == 0.03)
}
