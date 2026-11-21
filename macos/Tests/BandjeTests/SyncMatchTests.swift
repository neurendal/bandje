import Foundation
import Testing
@testable import Bandje

/// Turning sync off (Copy) and on (Move) never makes a recording a second time (owner, 2026-11-09).
final class SyncMatchTests {
    private let dir: URL
    private let local: URL
    private let cloud: URL
    private let created = Date(timeIntervalSince1970: 1_794_000_000)

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        local = dir.appendingPathComponent("local", isDirectory: true)
        cloud = dir.appendingPathComponent("cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    /// A recording folder with `.bandje.json`, audio of `audioBytes` and a transcript of `duration` s.
    @discardableResult
    private func recording(_ title: String, in parent: URL, created: Date? = nil, duration: Double? = 61,
                           audioBytes: Int = 10, extra: [String] = []) throws -> URL {
        let folder = parent.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingMeta(created: created ?? self.created).write(to: folder)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(title).m4a").path, contents: Data(count: audioBytes))
        if let duration {
            let json = try JSONSerialization.data(withJSONObject: ["duration": duration])
            try json.write(to: folder.appendingPathComponent("\(title).json"))
        }
        for name in extra { FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("x".utf8)) }
        return folder
    }

    @Test func sameCreatedAndLengthIsTheSameRecordingWhateverItsName() throws {
        let mine = try recording("Opname 9 nov 10.00", in: local)
        let theirs = try recording("Overleg", in: cloud, duration: 61.8)
        #expect(match(ICloudSync.counterpart(of: mine, in: ICloudSync.byCreated(cloud))) == .same(theirs.lastPathComponent))
    }

    @Test func otherCreatedIsNoMatch() throws {
        let mine = try recording("A", in: local)
        try recording("A", in: cloud, created: created.addingTimeInterval(60))
        #expect(match(ICloudSync.counterpart(of: mine, in: ICloudSync.byCreated(cloud))) == .none)
    }

    @Test func lengthApartOrUnknownIsDoubt() throws {
        let mine = try recording("A", in: local)
        let longer = try recording("B", in: cloud, duration: 63)
        #expect(match(ICloudSync.counterpart(of: mine, in: ICloudSync.byCreated(cloud))) == .doubt(longer.lastPathComponent))
        try FileManager.default.removeItem(at: longer)
        // Audio still in iCloud and no transcript: the length is unknown.
        let unknown = try recording("C", in: cloud, duration: nil)
        #expect(match(ICloudSync.counterpart(of: mine, in: ICloudSync.byCreated(cloud))) == .doubt(unknown.lastPathComponent))
    }

    @Test func aFolderWithoutMetaNeverMatches() throws {
        let mine = local.appendingPathComponent("Oud", isDirectory: true)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try recording("Oud", in: cloud)
        #expect(match(ICloudSync.counterpart(of: mine, in: ICloudSync.byCreated(cloud))) == .none)
    }

    @Test func holdsEverythingFollowsTheNameAndChecksSizes() throws {
        let mine = try recording("A", in: local, extra: ["A samenvatting Vergadering.md", ".markers.json", ".cover-abc.jpg"])
        let theirs = try recording("A 2", in: cloud, extra: ["A 2 samenvatting Vergadering.md", ".markers.json"])
        #expect(ICloudSync.holdsEverything(theirs, of: mine))  // the cover image does not count
        // A summary only on this Mac: not complete.
        FileManager.default.createFile(atPath: mine.appendingPathComponent("A samenvatting Sollicitatie.md").path, contents: Data("x".utf8))
        #expect(!ICloudSync.holdsEverything(theirs, of: mine))
    }

    @Test func otherAudioSizeIsNotComplete() throws {
        let mine = try recording("A", in: local, audioBytes: 10)
        let theirs = try recording("A", in: cloud, audioBytes: 11)
        #expect(!ICloudSync.holdsEverything(theirs, of: mine))
    }

    @Test func moveInTrashesOnlyACompleteDuplicate() throws {
        let index0 = ICloudSync.byCreated(cloud)
        // Nothing in iCloud yet: moved as before (publish needs iCloud, so only the decision here).
        #expect(match(ICloudSync.counterpart(of: try recording("Nieuw", in: local, created: created.addingTimeInterval(5)), in: index0)) == .none)

        let theirs = try recording("A", in: cloud)
        let complete = try recording("A", in: local)
        let index = ICloudSync.byCreated(cloud)
        // The test's own "Trash", so nothing lands in the user's.
        let trash = dir.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let toTrash: (URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) }
        #expect(try ICloudSync.moveIn(complete, into: cloud, index: index, toTrash: toTrash) == .alreadyThere)
        #expect(!FileManager.default.fileExists(atPath: complete.path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("A/A.m4a").path))
        #expect(FileManager.default.fileExists(atPath: theirs.path))

        let different = try recording("A", in: local, audioBytes: 99)
        #expect(try ICloudSync.moveIn(different, into: cloud, index: index, toTrash: toTrash) == .keptLocal)
        #expect(FileManager.default.fileExists(atPath: different.path))
        #expect(OutputLocation.recordingFolders(in: cloud).map(\.lastPathComponent) == ["A"])  // no "A 2"
    }

    /// The counterpart by folder name (the folders found may be under /private/var, made under /var).
    private enum Match: Equatable { case none, same(String), doubt(String) }
    private func match(_ c: ICloudSync.Counterpart) -> Match {
        switch c {
        case .none: .none
        case .same(let u): .same(u.lastPathComponent)
        case .doubt(let u): .doubt(u.lastPathComponent)
        }
    }
}
