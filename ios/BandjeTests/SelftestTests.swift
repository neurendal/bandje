// SPDX-License-Identifier: GPL-3.0-only
import Testing
@testable import Bandje

struct SelftestTests {
    @Test func parsesFlagsAndValues() {
        let o = SelftestOptions(arguments: ["Bandje", "--fake-mic", "/tmp/a.wav", "--record", "60", "--reset", "--demo-state", "empty"])
        #expect(o.fakeMic == "/tmp/a.wav")
        #expect(o.record == 60)
        #expect(o.reset)
        #expect(o.demoState == "empty")
        #expect(o.killAfter == nil)
    }

    @Test func ignoresUnknownAndMissingValues() {
        let o = SelftestOptions(arguments: ["Bandje", "-NSDoubleLocalizedStrings", "YES", "--import", "--reset"])
        #expect(o.importPath == nil)
        #expect(o.reset)
    }

    @Test func emptyWithoutFlags() {
        #expect(SelftestOptions(arguments: ["Bandje"]).isEmpty)
    }
}
