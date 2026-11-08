// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import Testing
@testable import Bandje

@Suite(.serialized)
struct RecorderTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bandje-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A finished CAF with `seconds` of a 440 Hz tone, written by our own writer.
    private func writeTone(to caf: URL, seconds: Double, rate: Double = CAFWriter.sampleRate) throws {
        let writer = try CAFWriter(url: caf)
        let n = Int(seconds * rate)
        let samples = (0..<n).map { Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / rate)) }
        writer.append(samples, rate: rate)
        writer.finish()
    }

    // MARK: Naming

    @Test func defaultTitleHasDayAndTimeWithoutColon() throws {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2026, 11, 6, 14, 32)
        let date = try #require(Calendar.current.date(from: c))
        let nl = Storage.defaultTitle(for: date, locale: Locale(identifier: "nl_NL"))
        #expect(nl.contains("6 nov 14.32"))
        #expect(!nl.contains(":"))
        let en = Storage.defaultTitle(for: date, locale: Locale(identifier: "en_GB"))
        #expect(en.contains("6 Nov 14.32"))
    }

    @Test func libraryIsGroupedPerDay() throws {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 11, 6, 12)
        let cal = Calendar(identifier: .gregorian)
        let now = try #require(cal.date(from: c))
        func rec(_ hoursAgo: Double) -> Recording {
            Recording(folder: URL(filePath: "/tmp/\(hoursAgo)"), audio: nil, date: now.addingTimeInterval(-hoursAgo * 3600),
                      duration: 1, markers: [])
        }
        let days = Library.days([rec(1), rec(2), rec(20), rec(24 * 3), rec(24 * 40)], now: now, calendar: cal)
        #expect(days.map(\.recordings.count) == [2, 1, 1, 1])
        #expect(days[0].title == Library.dayTitle(now, now: now, calendar: cal))
        #expect(days[1].title != days[0].title && days[2].title != days[3].title)
        let meta = RecordingMeta(created: now, location: RecordedLocation(latitude: 52.37, longitude: 4.89, accuracy: 12))
        let dir = try tempDir()
        try meta.write(to: dir)
        #expect(RecordingMeta.read(from: dir)?.location == meta.location)
    }

    @Test func stickerPlacementIsStableAndBounded() {
        let titles = ["Interview Anna", "Bandje", "Overleg", "x", "Opname 6 nov 07.54", "Mixtape"]
        var sides = Set<Bool>()
        for t in titles {
            let p = Sticker.placement(for: t)
            #expect(p.degrees == Sticker.placement(for: t).degrees)
            #expect((0.8...3.5).contains(abs(p.degrees)))
            #expect(abs(p.dx) <= 8 && abs(p.dy) <= 3)
            sides.insert(p.degrees > 0)
        }
        #expect(sides.count == 2)  // some lean left, some right
    }

    @Test func safeNames() {
        #expect(Storage.safeName("a/b:c") == "a-b.c")
        #expect(Storage.safeName("  ..hidden ") == "hidden")
        #expect(Storage.safeName("") == "Recording")
        #expect(Storage.safeName("Selftest") == "Selftest 1")
        #expect(Storage.safeName("Opname 6 nov 14.32") == "Opname 6 nov 14.32")
    }

    @Test func uniqueNamesAndNewFolder() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try Storage.newRecording(title: "Talk", date: date, in: dir)
        let second = try Storage.newRecording(title: "Talk", date: date, in: dir)
        let third = try Storage.newRecording(title: "Talk", date: date, in: dir)
        #expect(first.lastPathComponent == "Talk.caf")
        #expect(second.deletingLastPathComponent().lastPathComponent == "Talk 2")
        #expect(second.lastPathComponent == "Talk 2.caf")
        #expect(third.deletingLastPathComponent().lastPathComponent == "Talk 3")
        let meta = try #require(RecordingMeta.read(from: first.deletingLastPathComponent()))
        #expect(meta.recording == true)
        #expect(meta.created == date)
    }

    // MARK: Recovery

    @Test func recoversUnfinishedRecordingWithBrokenHeader() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Crashed", date: Date(), in: dir)
        try writeTone(to: caf, seconds: 2)
        // Simulate a crash before the header was finalised: data chunk size 0.
        var bytes = try Data(contentsOf: caf)
        let data = try #require(bytes.firstRange(of: Data("data".utf8)))
        bytes.replaceSubrange(data.upperBound..<data.upperBound + 8, with: Data(count: 8))
        try bytes.write(to: caf)
        #expect(Storage.unfinished(in: dir) == [caf])

        let recovered = Storage.recoverUnfinished(in: dir)

        let folder = caf.deletingLastPathComponent()
        #expect(recovered.map(\.lastPathComponent) == ["Crashed"])
        let m4a = folder.appending(path: "Crashed.m4a")
        #expect(FileManager.default.fileExists(atPath: m4a.path))
        #expect(!FileManager.default.fileExists(atPath: caf.path))
        #expect(abs(Storage.duration(of: m4a) - 2) < 0.05)
        #expect(RecordingMeta.read(from: folder)?.recording == nil)
        let scanned = Storage.scan(dir)
        #expect(scanned.map(\.title) == ["Crashed"])
    }

    @Test func repairLeavesCompleteFileAlone() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = dir.appending(path: "ok.caf")
        try writeTone(to: caf, seconds: 1)
        let before = try Data(contentsOf: caf)
        #expect(CAFRepair.repair(caf) == false)
        #expect(try Data(contentsOf: caf) == before)
    }

    @Test func activeRecordingIsNotRecovered() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = try Storage.newRecording(title: "Live", date: Date(), in: dir)
        try writeTone(to: caf, seconds: 0.5)
        #expect(Storage.unfinished(in: dir, except: caf.deletingLastPathComponent()).isEmpty)
        #expect(Storage.scan(dir, except: caf.deletingLastPathComponent()).isEmpty)
    }

    @Test func writerResamplesOtherRates() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = dir.appending(path: "mixed.caf")
        let writer = try CAFWriter(url: caf)
        writer.append([Float](repeating: 0.1, count: 48_000), rate: 48_000) // 1 s at 48 kHz
        writer.append([Float](repeating: 0.1, count: 16_000), rate: 16_000) // 1 s at 16 kHz (AirPods)
        writer.finish()
        #expect(abs(Storage.duration(of: caf) - 2) < 0.05)
        #expect(!writer.failed)
    }

    // MARK: Markers (full recorder with the fake mic)

    @MainActor @Test func markersAreSavedDuringRecording() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "source.caf")
        try writeTone(to: source, seconds: 3)

        let recorder = Recorder()
        try await recorder.start(source: FakeMicSource(url: source))
        let folder = try #require(recorder.folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Task.sleep(for: .milliseconds(1_200))
        recorder.addMarker()
        // Saved right away, before the recording ends (survives a crash).
        let saved = try #require(RecordingMeta.read(from: folder))
        #expect(saved.markers.count == 1)
        #expect(saved.recording == true)
        #expect(saved.markers[0] > 0.8 && saved.markers[0] < 2)

        await recorder.stop()
        #expect(recorder.state == .idle)
        let meta = try #require(RecordingMeta.read(from: folder))
        #expect(meta.markers == saved.markers)
        #expect(meta.recording == nil)
        let m4a = folder.appending(path: "\(folder.lastPathComponent).m4a")
        #expect(Storage.duration(of: m4a) > 1)
    }
}
