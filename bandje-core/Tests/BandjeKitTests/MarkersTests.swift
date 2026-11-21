// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import BandjeKit

@Suite("Markers: specs/markers.md")
struct MarkersTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandjekit-markers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Times are rounded to 0.1 s, sorted, and merged within a second")
    func cleanTimes() {
        let m = Markers(times: [312.44, 95, 95.6, -3, 540.04])
        #expect(m.times == [95, 312.4, 540])
    }

    @Test("Adding: rounded, clamped, and a tap close to an existing marker is that marker")
    func adding() {
        var m = Markers(times: [95])
        #expect(m.add(at: 95.7) == 95)
        #expect(m.count == 1)
        #expect(m.add(at: 200.04) == 200)
        #expect(m.add(at: -2) == 0)
        #expect(m.add(at: 999, duration: 750.06) == 750.1)
        #expect(m.times == [0, 95, 200, 750.1])
    }

    @Test("Removing a marker removes its note; notes are one trimmed line, blank removes")
    func notes() {
        var m = Markers(times: [95, 312.4])
        m.setNote("  Actiepunt\nDaan  ", at: 95)
        #expect(m.note(at: 95) == "Actiepunt Daan")
        m.setNote(String(repeating: "x", count: 500), at: 312.4)
        #expect(m.note(at: 312.4)?.count == Markers.maxNoteLength)
        m.setNote("  ", at: 312.4)
        #expect(m.note(at: 312.4) == nil)
        m.setNote("geen marker", at: 10)
        #expect(m.notes.count == 1)
        m.remove(at: 95)
        #expect(m.times == [312.4])
        #expect(m.notes.isEmpty)
    }

    @Test("A note without its marker (removed by an older version) is dropped")
    func orphanNotes() {
        let m = Markers(times: [95], notes: ["95.0": "blijft", "312.4": "weg"])
        #expect(m.notes == ["95.0": "blijft"])
    }

    @Test("The note shows from 3 s before to 5 s after its marker, the nearest wins")
    func chip() {
        var m = Markers(times: [100, 104, 200])
        m.setNote("eerste", at: 100)
        m.setNote("tweede", at: 104)
        #expect(m.noteNear(96.9) == nil)
        #expect(m.noteNear(97)?.text == "eerste")
        #expect(m.noteNear(102.5)?.text == "tweede")
        #expect(m.noteNear(109)?.text == "tweede")
        #expect(m.noteNear(109.1) == nil)
        #expect(m.noteNear(200) == nil)  // no note
    }

    @Test("Placed in the transcript: the last part starting at or before the marker")
    func placing() {
        let m = Markers(times: [0.5, 12, 30, 95])
        #expect(m.placed(in: [1, 10, 30, 60]) == [0: [0.5], 1: [12], 2: [30], 3: [95]])
        #expect(m.placed(in: []).isEmpty)
    }

    @Test("The export line")
    func line() {
        var m = Markers(times: [754])
        #expect(m.line(at: 754) { _ in "12:34" } == "🚩 12:34")
        m.setNote("Prijs?", at: 754)
        #expect(m.line(at: 754) { _ in "12:34" } == "🚩 12:34 Prijs?")
    }

    @Test("Files: times into .bandje.json keeping its other keys, notes into .markers.json")
    func files() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let meta = dir.appending(path: ".bandje.json")
        try Data(#"{"created":"2026-11-08T10:30:00Z","color":"blue","future":{"x":1},"markers":[95]}"#.utf8).write(to: meta)

        var m = Markers.read(from: dir)
        #expect(m.times == [95])
        m.add(at: 312.4)
        m.setNote("Prijs?", at: 312.4)
        try m.write(to: dir)

        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: meta)) as? [String: Any])
        #expect(written["created"] as? String == "2026-11-08T10:30:00Z")
        #expect(written["color"] as? String == "blue")
        #expect((written["future"] as? [String: Any])?["x"] as? Int == 1)
        #expect(written["markers"] as? [Double] == [95, 312.4])
        // 312.4 stays 312.4 in the file (no 312.39999…), as the iPhone writes it.
        #expect(try String(contentsOf: meta, encoding: .utf8).contains("312.4"))
        #expect(!(try String(contentsOf: meta, encoding: .utf8).contains("312.39")))
        #expect(Markers.read(from: dir) == m)

        m.setNote(nil, at: 312.4)
        try m.write(to: dir)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: ".markers.json").path))
    }

    @Test("A folder without .bandje.json gets none (the app makes it); nothing to read is no markers")
    func noMeta() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Markers.read(from: dir).isEmpty)
        try Markers(times: [5]).write(to: dir)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: ".bandje.json").path))
    }
}
