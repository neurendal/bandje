import Foundation

/// Reads and writes in the recordings folder through `NSFileCoordinator`: with iCloud sync on, other
/// devices change the same files, and a coordinated read downloads a file that is still in iCloud.
/// Harmless (and cheap) for local folders.
enum Files {
    static func write(_ data: Data, to url: URL) throws {
        try coordinate(writing: url, options: .forReplacing) { try data.write(to: $0, options: .atomic) }
    }

    static func read(_ url: URL) throws -> Data {
        var data = Data()
        try coordinate(reading: url) { data = try Data(contentsOf: $0) }
        return data
    }

    static func readString(_ url: URL) -> String? {
        (try? read(url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func copy(_ source: URL, to target: URL) throws {
        try coordinate(reading: source) { try FileManager.default.copyItem(at: $0, to: target) }
    }

    /// Swaps `temp` in for `url` (same folder), e.g. the audio with its cover put in.
    static func replace(_ url: URL, with temp: URL) throws {
        try coordinate(writing: url, options: .forReplacing) { _ = try FileManager.default.replaceItemAt($0, withItemAt: temp) }
    }

    static func move(_ source: URL, to target: URL) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing,
                                       error: &coordinationError) { from, to in
            do { try FileManager.default.moveItem(at: from, to: to) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    private static func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    private static func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
}

/// "Synchroniseer via iCloud" (Instellingen, default off; CLAUDE.md limit 8). Recordings,
/// transcripts, summaries and templates then live in the user's iCloud Drive › Band·je, shared with
/// the iPhone app (bandje-ios docs/icloud-sync.md). Recording happens in a local staging folder;
/// the finished folder moves to iCloud with `setUbiquitous`. macOS syncs; our code has no network.
enum ICloudSync {
    static let containerID = "iCloud.com.neurendal.bandje"
    static let settingKey = "iCloudSync"

    enum Availability { case available, noAccount, noContainer }

    /// Resolved once at launch by `prepare()` (the lookup can block). Nil without an iCloud account,
    /// with iCloud Drive off, or in a build without the iCloud entitlement (local `make` builds).
    nonisolated(unsafe) private(set) static var container: URL?
    /// True once `prepare()` has asked iCloud (whatever the answer): from then on `directory` is final.
    nonisolated(unsafe) private(set) static var prepared = false

    static var availability: Availability {
        if FileManager.default.ubiquityIdentityToken == nil { return .noAccount }
        return container == nil ? .noContainer : .available
    }

    static var documents: URL? { container?.appendingPathComponent("Documents", isDirectory: true) }

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: settingKey) }
        set { UserDefaults.standard.set(newValue, forKey: settingKey) }
    }

    /// Syncing: the setting is on and iCloud Drive is there.
    static var isActive: Bool { isOn && documents != nil }

    /// Where recordings are made while syncing: local, so a crash never leaves half a file in iCloud.
    static var staging: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Bandje/Recording", isDirectory: true)
    }

    /// At launch, off the main thread: find the container and make sure `Documents` exists.
    @MainActor static func prepare() async {
        let url = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: containerID) }.value
        container = url
        prepared = true
        if let documents { try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true) }
        NotificationCenter.default.post(name: .bandjeICloudReady, object: nil)
    }

    /// Turning sync on or off moves the recordings folder: never while something writes into it.
    static func canToggle(recording: Bool, transcribing: Bool, summarizing: Bool, finishing: Bool = false) -> Bool {
        !recording && !transcribing && !summarizing && !finishing
    }

    struct DownloadError: LocalizedError {
        let file: String
        var errorDescription: String? { tr("icloud.downloadFailed", "%@ staat nog in iCloud en kon niet worden opgehaald.", file) }
    }

    /// Makes sure `url` is on this Mac: returns at once for a local or downloaded file, else starts
    /// the download and waits until it is there (audio from the iPhone before playing or transcribing).
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 300) async throws {
        func status() -> URLUbiquitousItemDownloadingStatus? {
            var u = url
            u.removeAllCachedResourceValues()
            let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard v?.isUbiquitousItem == true else { return .current }
            return v?.ubiquitousItemDownloadingStatus
        }
        if status() == .current { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            if status() == .current { return }
        }
        throw DownloadError(file: url.lastPathComponent)
    }

    /// The name `folder` gets in `target`: the same, or ` 2`, ` 3`… when taken there.
    static func publishName(for name: String, in target: URL) -> String {
        OutputLocation.uniqueName(name, in: target)
    }

    /// Moves a finished recording folder into iCloud (`target` = `documents`); returns the new folder.
    /// `setUbiquitous` can block: never call this on the main thread.
    nonisolated static func publish(_ folder: URL, into target: URL) throws -> URL {
        let ready = try preparePublish(folder, into: target)
        let destination = target.appendingPathComponent(ready.lastPathComponent, isDirectory: true)
        try FileManager.default.setUbiquitous(true, itemAt: ready, destinationURL: destination)
        return destination
    }

    /// When the name is taken in `target`, renames the local folder and its files to the free name
    /// first (` 2`), so folder and files keep matching. Returns the folder to move.
    nonisolated static func preparePublish(_ folder: URL, into target: URL) throws -> URL {
        let name = publishName(for: folder.lastPathComponent, in: target)
        guard name != folder.lastPathComponent else { return folder }
        let renamed = folder.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        try Files.move(folder, to: renamed)
        try Library.renameFiles(in: renamed, from: folder.lastPathComponent, to: name)
        return renamed
    }

    /// Copies a recording folder into `target` (downloading what is still in iCloud), under a free
    /// name; files follow a new name. Off the main thread: it can be gigabytes.
    static func copyRecording(_ folder: URL, into target: URL) async throws -> URL {
        let name = OutputLocation.uniqueName(folder.lastPathComponent, in: target)
        let destination = target.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try await ensureDownloaded(file)
            try await Task.detached(priority: .utility) { try Files.copy(file, to: destination.appendingPathComponent(file.lastPathComponent)) }.value
        }
        try Library.renameFiles(in: destination, from: folder.lastPathComponent, to: name)
        return destination
    }

    /// Staging folders that are finished (converted to `.m4a`, `.bandje.json` no longer recording):
    /// left behind by a crash or a failed move.
    static func flushStagingPlan(staging: URL = staging) -> [URL] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: .skipsHiddenFiles)) ?? []
        return folders.filter { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            return !files.contains { $0.hasSuffix(".caf") } && files.contains { $0.hasSuffix(".m4a") }
                && RecordingMeta.read(from: folder)?.recording != true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Moves the finished staging folders to the recordings folder: into iCloud when syncing,
    /// else to the local recordings folder (sync was turned off in the meantime).
    static func flushStaging() async {
        let target = OutputLocation.directory
        let active = isActive
        for folder in flushStagingPlan() {
            _ = try? await Task.detached {
                if active { return try publish(folder, into: target) }
                let destination = target.appendingPathComponent(OutputLocation.uniqueName(folder.lastPathComponent, in: target))
                try FileManager.default.moveItem(at: folder, to: destination)
                return destination
            }.value
        }
    }
}

extension Notification.Name {
    /// Something changed in the recordings folder (this Mac or another device): the menu and the
    /// window refresh. Coalesced: at most one per 300 ms.
    static let bandjeLibraryChanged = Notification.Name("bandjeLibraryChanged")
    /// iCloud answered at launch (container known or not): Settings show the real state.
    static let bandjeICloudReady = Notification.Name("bandjeICloudReady")
}

/// Watches the recordings folder and posts `.bandjeLibraryChanged`. Syncing: an `NSMetadataQuery`
/// over iCloud Drive › Band·je, which also downloads transcripts, `.bandje.json` and templates right
/// away (audio only when it is played or transcribed). Not syncing: one FSEvents stream on the folder
/// (recursive; no open file per recording, so hundreds of recordings cost nothing).
@MainActor
final class LibraryWatcher {
    static let shared = LibraryWatcher()

    /// True once the metadata query has gathered what is in iCloud (or right away when not syncing):
    /// only then may Bandje create the example templates, so two devices don't both do it.
    private(set) var gathered = false
    private var query: NSMetadataQuery?
    private var stream: FSEventStreamRef?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// The folder to watch; nil = the recordings folder (tests pass their own).
    private var root: URL?

    /// (Re)starts watching the current recordings folder; call after turning sync on or off.
    func start(root: URL? = nil) {
        stop()
        self.root = root
        if root == nil, ICloudSync.isActive {
            let q = NSMetadataQuery()
            q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
            for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.queryChanged() }
                })
            }
            query = q
            q.start()
        } else {
            gathered = true
            watchFolders()
        }
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        gathered = false
    }

    /// Posts `.bandjeLibraryChanged` once for a burst of events.
    func changed() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .bandjeLibraryChanged, object: nil)
        }
    }

    private func queryChanged() {
        guard let q = query else { return }
        q.disableUpdates()
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let small = ["json", "md", "txt"].contains(url.pathExtension.lowercased()) || url.lastPathComponent == RecordingMeta.fileName
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if small, status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        q.enableUpdates()
        if !gathered {
            gathered = true
            Summaries.seedIfMissing()
        }
        changed()
    }

    private func watchFolders() {
        let dir = root ?? OutputLocation.directory
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<LibraryWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.changed() }  // the stream runs on the main queue
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [dir.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
