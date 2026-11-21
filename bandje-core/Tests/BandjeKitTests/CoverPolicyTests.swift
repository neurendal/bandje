// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import BandjeKit

@Suite("CoverPolicy: a device makes a cover only for its own changes (specs/icloud-sync.md)")
struct CoverPolicyTests {
    private func plan(stored: String?, current: String = "new", own: Bool, meta: Bool = true, audio: Bool = true) -> CoverPolicy.Plan {
        CoverPolicy.plan(storedKey: stored, currentKey: current, ownChange: own, metaIsCurrent: meta, audioIsCurrent: audio)
    }

    @Test("Own rename or colour, files here and current: make the cover")
    func ownChange() {
        #expect(plan(stored: "old", own: true) == .embed)
    }

    @Test("A rename or colour from the other device: leave it, that device writes the cover")
    func remoteChange() {
        #expect(plan(stored: "old", own: false) == .leave)
        // Also while the newer files are still coming (the case that flipped the colour back).
        #expect(plan(stored: "old", own: false, meta: false) == .leave)
        #expect(plan(stored: "old", own: false, audio: false) == .leave)
    }

    @Test("No coverKey (older or new recording): a cover where .bandje.json and the audio are current")
    func backfill() {
        #expect(plan(stored: nil, own: false) == .embed)
        #expect(plan(stored: nil, own: false, audio: false) == .leave)
        #expect(plan(stored: nil, own: false, meta: false) == .leave)
        #expect(plan(stored: nil, own: true) == .embed)
    }

    @Test("Own change without the audio here: remove the key, so a device with the audio makes it")
    func ownChangeWithoutAudio() {
        #expect(plan(stored: "old", own: true, audio: false) == .clearKey)
        #expect(plan(stored: nil, own: true, audio: false) == .leave)
    }

    @Test("Never a write into .bandje.json that is not current, not even for an own change")
    func staleMeta() {
        #expect(plan(stored: "old", own: true, meta: false) == .leave)
        #expect(plan(stored: "old", own: true, meta: false, audio: false) == .leave)
    }

    @Test("The cover is already the current one: nothing")
    func upToDate() {
        #expect(plan(stored: "new", own: true) == .leave)
        #expect(plan(stored: "new", own: false) == .leave)
        #expect(plan(stored: "new", own: true, audio: false) == .leave)
    }

    @Test("Local files are up to date; a missing file only when no iCloud placeholder stands for it")
    func upToDateFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CoverPolicy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let meta = dir.appendingPathComponent(".bandje.json")
        #expect(CoverPolicy.isUpToDate(meta))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("..bandje.json.icloud"))
        #expect(!CoverPolicy.isUpToDate(meta))
        try Data("{}".utf8).write(to: meta)
        #expect(CoverPolicy.isUpToDate(meta))
    }
}
