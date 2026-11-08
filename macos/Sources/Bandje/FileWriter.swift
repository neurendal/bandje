import AudioToolbox
import AVFoundation
import Foundation
import Synchronization

/// Writer thread: drains the ring buffer into a float32 48 kHz .caf via ExtAudioFile.
/// Input at another rate (e.g. AirPods at 16/24 kHz) goes through an AVAudioConverter first;
/// ExtAudioFile itself refuses a client format change once writing started (-66565), and the
/// input rate can change during a recording when the microphone changes.
final class FileWriter: @unchecked Sendable {
    static let fileSampleRate: Double = 48_000

    let url: URL
    private let channels: Int
    private let ring: RingBuffer
    private var file: ExtAudioFileRef?
    private let chunkSamples: Int
    private let chunk: UnsafeMutablePointer<Float>
    private let stopFlag = Atomic<Bool>(false)
    private let frames = Atomic<Int>(0)
    private let done = DispatchSemaphore(value: 0)
    private var thread: Thread?
    private let lastWriteError = Atomic<Int32>(noErr)
    /// New client sample rate requested by `setInputSampleRate` (Double bits, 0 = none).
    private let pendingRate = Atomic<UInt64>(0)
    private let rateApplied = DispatchSemaphore(value: 0)
    private(set) var inputSampleRate: Double
    // Sample-rate conversion, only when the input is not at 48 kHz. Writer thread only
    // (or the caller's thread while the writer thread is not running).
    private var converter: AVAudioConverter?
    private var converterIn: AVAudioPCMBuffer?
    private var converterOut: AVAudioPCMBuffer?

    /// Frames written to the file (at 48 kHz).
    var framesWritten: Int { frames.load(ordering: .relaxed) }
    /// Last ExtAudioFileWrite error (noErr if none), e.g. when the disk is full.
    var writeError: OSStatus { lastWriteError.load(ordering: .relaxed) }

    init(url: URL, channels: Int, inputSampleRate: Double, ring: RingBuffer) throws {
        self.url = url
        self.channels = channels
        self.ring = ring
        self.inputSampleRate = inputSampleRate
        chunkSamples = 4_096 * channels
        chunk = .allocate(capacity: chunkSamples)

        var fileFormat = Self.floatFormat(rate: Self.fileSampleRate, channels: channels)
        var ref: ExtAudioFileRef?
        // Each recording has its own folder.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var status = ExtAudioFileCreateWithURL(url as CFURL, kAudioFileCAFType, &fileFormat, nil,
                                               AudioFileFlags.eraseFile.rawValue, &ref)
        guard status == noErr, let ref else {
            chunk.deallocate()
            throw RecorderError(message: tr("error.fileCreate", "Kan het opnamebestand niet maken in %1$@ (fout %2$@).", url.deletingLastPathComponent().path, "\(status)"))
        }
        var clientFormat = fileFormat
        status = ExtAudioFileSetProperty(ref, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat)
        guard status == noErr else {
            ExtAudioFileDispose(ref)
            chunk.deallocate()
            throw RecorderError.coreAudio(tr("step.format", "Audioformaat instellen"), status)
        }
        file = ref
        makeConverter(for: inputSampleRate)
    }

    deinit {
        finish()
        chunk.deallocate()
    }

    func start() {
        let t = Thread { [self] in
            while !stopFlag.load(ordering: .acquiring) {
                drain()
                let rate = pendingRate.exchange(0, ordering: .acquiringAndReleasing)
                if rate != 0 {
                    drain()
                    makeConverter(for: Double(bitPattern: rate))
                    rateApplied.signal()
                    continue
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            drain()
            close()
            done.signal()
        }
        t.name = "Bandje writer"
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
    }

    /// Stops the thread after a final drain and closes the file. Safe to call repeatedly.
    func finish() {
        guard thread != nil else {
            close()
            return
        }
        stopFlag.store(true, ordering: .releasing)
        done.wait()
        thread = nil
    }

    /// Switches the sample rate of incoming samples (after a capture rebuild with another
    /// microphone). The caller must have stopped the producer: everything already in the ring
    /// is written at the old rate first. Blocks until the writer thread applied the change.
    func setInputSampleRate(_ rate: Double) {
        guard rate != inputSampleRate else { return }
        inputSampleRate = rate
        if thread == nil {
            makeConverter(for: rate)
            return
        }
        pendingRate.store(rate.bitPattern, ordering: .releasing)
        rateApplied.wait()
    }

    /// Flushes the old converter's tail into the file and sets up one for `rate`
    /// (none at 48 kHz).
    private func makeConverter(for rate: Double) {
        if let converter { convert(converter, input: nil) }
        converter = nil
        converterIn = nil
        converterOut = nil
        guard rate != Self.fileSampleRate,
              let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                           channels: AVAudioChannelCount(channels), interleaved: true),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.fileSampleRate,
                                            channels: AVAudioChannelCount(channels), interleaved: true),
              let conv = AVAudioConverter(from: inFormat, to: outFormat) else { return }
        let inFrames = chunkSamples / channels
        converter = conv
        converterIn = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(inFrames))
        converterOut = AVAudioPCMBuffer(pcmFormat: outFormat,
                                        frameCapacity: AVAudioFrameCount(Double(inFrames) * Self.fileSampleRate / rate) + 4_096)
    }

    /// Runs `input` (nil = end of stream: flush) through the converter and writes the output.
    private func convert(_ conv: AVAudioConverter, input: AVAudioPCMBuffer?) {
        guard let out = converterOut else { return }
        var supplied = false
        while true {
            out.frameLength = 0
            var error: NSError?
            let status = conv.convert(to: out, error: &error) { _, inputStatus in
                guard let input, !supplied else {
                    inputStatus.pointee = input == nil ? .endOfStream : .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            if out.frameLength > 0, let data = out.floatChannelData?[0] {
                write(data, frameCount: Int(out.frameLength))
            }
            if status == .error { lastWriteError.store(-1, ordering: .relaxed) }
            if status != .haveData { return } // .inputRanDry, .endOfStream or .error
        }
    }

    private func drain() {
        guard file != nil else { return }
        while true {
            var n = ring.read(into: chunk, maxCount: chunkSamples)
            n -= n % channels
            guard n > 0 else { return }
            let frameCount = n / channels
            if let converter, let input = converterIn, let data = input.floatChannelData?[0] {
                data.update(from: chunk, count: n) // interleaved: one buffer
                input.frameLength = AVAudioFrameCount(frameCount)
                convert(converter, input: input)
            } else {
                write(chunk, frameCount: frameCount)
            }
        }
    }

    private func write(_ data: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard let file else { return }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: UInt32(channels), mDataByteSize: UInt32(frameCount * channels * MemoryLayout<Float>.size),
            mData: data))
        let status = ExtAudioFileWrite(file, UInt32(frameCount), &list)
        if status != noErr { lastWriteError.store(status, ordering: .relaxed) }
        frames.wrappingAdd(frameCount, ordering: .relaxed)
    }

    /// Flushes the converter and closes the file.
    private func close() {
        if let converter { convert(converter, input: nil) }
        converter = nil
        if let file { ExtAudioFileDispose(file) }
        file = nil
    }

    static func floatFormat(rate: Double, channels: Int) -> AudioStreamBasicDescription {
        let bytes = UInt32(MemoryLayout<Float>.size * channels)
        return AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytes, mFramesPerPacket: 1, mBytesPerFrame: bytes,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
    }
}

/// `.caf` (float32 stereo) -> `.m4a` (AAC 48 kHz stereo). Writes to `<name>.converting.m4a`
/// and renames on success, then removes the `.caf`. On failure the `.caf` stays.
enum AudioExport {
    static func convertToM4A(_ caf: URL) throws -> URL {
        let target = caf.deletingPathExtension().appendingPathExtension("m4a")
        let temp = caf.deletingPathExtension().appendingPathExtension("converting.m4a")
        let fm = FileManager.default
        try? fm.removeItem(at: temp)
        do {
            try encode(from: caf, to: temp)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try? fm.removeItem(at: caf)
        return target
    }

    private static func encode(from src: URL, to dst: URL) throws {
        func fail(_ status: OSStatus) -> RecorderError {
            RecorderError(message: tr("error.convert", "Omzetten naar .m4a mislukt (fout %1$@). Het .caf-bestand blijft staan: %2$@", "\(status)", src.path))
        }
        var inRef: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(src as CFURL, &inRef)
        guard status == noErr, let inRef else { throw fail(status) }
        defer { ExtAudioFileDispose(inRef) }

        var client = FileWriter.floatFormat(rate: FileWriter.fileSampleRate, channels: 2)
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileSetProperty(inRef, kExtAudioFileProperty_ClientDataFormat, asbdSize, &client)
        guard status == noErr else { throw fail(status) }

        var aac = AudioStreamBasicDescription(
            mSampleRate: FileWriter.fileSampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        var outRef: ExtAudioFileRef?
        status = ExtAudioFileCreateWithURL(dst as CFURL, kAudioFileM4AType, &aac, nil,
                                           AudioFileFlags.eraseFile.rawValue, &outRef)
        guard status == noErr, let outRef else { throw fail(status) }
        var closed = false
        defer { if !closed { ExtAudioFileDispose(outRef) } }
        status = ExtAudioFileSetProperty(outRef, kExtAudioFileProperty_ClientDataFormat, asbdSize, &client)
        guard status == noErr else { throw fail(status) }

        let chunkFrames: UInt32 = 8_192
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(chunkFrames) * 2)
        defer { buffer.deallocate() }
        while true {
            var frames = chunkFrames
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: chunkFrames * 8, mData: buffer))
            status = ExtAudioFileRead(inRef, &frames, &list)
            guard status == noErr else { throw fail(status) }
            if frames == 0 { break }
            status = ExtAudioFileWrite(outRef, frames, &list)
            guard status == noErr else { throw fail(status) }
        }
        closed = true
        status = ExtAudioFileDispose(outRef)
        guard status == noErr else { throw fail(status) }
    }
}

enum OutputLocation {
    /// The user's real home directory, also inside the App Sandbox
    /// (where NSHomeDirectory() points at the container).
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var defaultDirectory: URL { realHome.appendingPathComponent("Music/Bandje", isDirectory: true) }

    /// Folder chosen in Instellingen, kept as a security-scoped bookmark so the
    /// sandbox lets Bandje write there after a restart. Nil: not chosen, or no longer reachable.
    nonisolated(unsafe) private static var chosen: URL?
    #if DEBUG
    /// `--selftest-snapshot menu-open --library <folder>`: the recordings folder the menu shows.
    nonisolated(unsafe) static var snapshotDirectory: URL?
    #endif
    private static let bookmarkKey = "outputBookmark"

    /// At launch: resolve the bookmark and keep access open for the app's lifetime. Returns false
    /// when a folder was chosen but can't be reached (an external disk that isn't connected, a
    /// deleted folder): recordings then go to ~/Music/Bandje this session; the choice is kept.
    @discardableResult
    static func restoreChosen() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return true }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path),
              url.startAccessingSecurityScopedResource() else { return false }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        chosen = url
        return true
    }

    /// `url` from an open panel becomes the recordings folder; nil goes back to `~/Music/Bandje`.
    static func choose(_ url: URL?) throws {
        if let old = chosen { old.stopAccessingSecurityScopedResource() }
        chosen = nil
        guard let url else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        let data = try url.bookmarkData(options: .withSecurityScope)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "outputDir")
        _ = url.startAccessingSecurityScopedResource()
        chosen = url
    }

    /// True for folders that a sync service copies off the Mac (iCloud Drive, Dropbox, OneDrive, Google Drive…).
    static func isSynced(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = realHome.path
        if path.hasPrefix(home + "/Library/Mobile Documents") || path.hasPrefix(home + "/Library/CloudStorage") { return true }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return true }
        // Desktop and Documents in iCloud Drive look like local paths.
        for name in ["Desktop", "Documents"] where path == home + "/" + name || path.hasPrefix(home + "/" + name + "/") {
            let mobile = home + "/Library/Mobile Documents/com~apple~CloudDocs/" + name
            if FileManager.default.fileExists(atPath: mobile) { return true }
        }
        return false
    }

    /// The folder chosen in Instellingen, else `defaults write com.neurendal.bandje outputDir <path>`
    /// (a leading `~` means the real home; only under ~/Music), else `~/Music/Bandje`.
    static var directory: URL {
        #if DEBUG
        if let snapshotDirectory { return snapshotDirectory }
        #endif
        if ICloudSync.isActive, let documents = ICloudSync.documents { return documents }
        return localDirectory
    }

    /// Where a new recording is made: the local staging folder while sync is on (also before iCloud
    /// answered at launch; `ICloudSync.flushStaging` moves it later), else the recordings folder.
    static var recordingDirectory: URL { ICloudSync.isOn ? ICloudSync.staging : directory }

    /// The folder the user chose (or ~/Music/Bandje), also while sync is on: where sync moves
    /// recordings from when turned on, and copies them to when turned off.
    static var localDirectory: URL {
        if let chosen { return chosen }
        guard let custom = UserDefaults.standard.string(forKey: "outputDir"), !custom.isEmpty else { return defaultDirectory }
        return resolve(custom, home: realHome)
    }

    static func resolve(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The recording folders in `dir`: subfolders that are not hidden and not reserved (Templates…).
    static func recordingFolders(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !reserved.contains($0.lastPathComponent.lowercased())
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Files in `dir` and in its subfolders one level down: since M7 each recording has its own
    /// folder; older recordings lie directly in `dir`.
    static func recordingFiles(in dir: URL, keys: [URLResourceKey] = []) -> [URL] {
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys + [.isDirectoryKey],
                                                    options: .skipsHiddenFiles) else { return [] }
        var out: [URL] = []
        for item in top {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                out += (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
            } else {
                out.append(item)
            }
        }
        return out
    }

    /// Transcripts (`.json`) in `dir`, newest first, for the menu Recente opnames.
    static func recentTranscripts(in dir: URL, limit: Int) -> [URL] {
        let fm = FileManager.default
        // The selftests (DEBUG builds) write their transcripts to `<dir>/selftest`.
        let skip = Set(["selftest", "Templates"].map { dir.appendingPathComponent($0).standardizedFileURL.path })
        let transcripts = recordingFiles(in: dir).filter { json in
            json.pathExtension == "json"
                && !skip.contains(json.deletingLastPathComponent().standardizedFileURL.path)
                && fm.fileExists(atPath: json.deletingPathExtension().appendingPathExtension("md").path)
        }
        return Array(transcripts.map { ($0, recordingDate($0)) }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }

    /// When a recording was made, for sorting. Not the folder name (the user may rename it) and not
    /// the files' dates (rewritten when speakers get names): first `.bandje.json` (Mac and iPhone),
    /// then `recorded` in the transcript, then the date in the old Mac names (`2026-11-05_16-02`),
    /// then the audio's creation date (an imported file keeps that of the original), then the folder's.
    static func recordingDate(_ json: URL) -> Date {
        let folder = json.deletingLastPathComponent()
        if let meta = RecordingMeta.read(from: folder) { return meta.created }
        if let data = try? Data(contentsOf: json),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let recorded = (o["recorded"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) {
            return recorded
        }
        let base = json.deletingPathExtension().lastPathComponent
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        if let date = f.date(from: String(base.prefix(16))) { return date }
        func created(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }
        for ext in ["m4a", "caf"] {
            if let date = created(json.deletingPathExtension().appendingPathExtension(ext)) { return date }
        }
        return created(folder) ?? created(json) ?? .distantPast
    }

    /// Newest `.m4a` (or leftover `.caf`) in the directory, for "Toon laatste opname in Finder".
    static func latestRecording(in dir: URL) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        return recordingFiles(in: dir, keys: keys)
            .filter { ["m4a", "caf"].contains($0.pathExtension) && !$0.lastPathComponent.contains(".converting.") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    /// `.caf` files left behind by a crash, a forced quit or a failed conversion
    /// (call only while not recording). Sorted by name, so oldest first.
    static func unfinishedRecordings(in dir: URL) -> [URL] {
        recordingFiles(in: dir).filter { $0.pathExtension == "caf" && !$0.lastPathComponent.contains(".converting.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Free space on the volume of `dir` (space the system can make available), nil if unknown.
    /// `dir` may not exist yet (a recording's folder is made when its file is written): then the
    /// nearest folder above it that does exist is asked.
    /// The plain free space is quick; the space for "important usage" (which counts purgeable space
    /// too) can take minutes the first time macOS works it out. So when the plain free space is
    /// already `enough`, that is the answer, and the slow figure is only asked for on a nearly full disk.
    static func freeBytes(at dir: URL, enough: Int64 = .max) -> Int64? {
        var dir = dir.standardizedFileURL
        while !FileManager.default.fileExists(atPath: dir.path), dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
        }
        let plain = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
        if let plain, plain >= enough { return plain }
        let important = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        if let important, important > 0 { return max(important, plain ?? 0) }
        return plain
    }

    /// `Transcribeer bestand…` gives the file its own folder `<dir>/<name>/` and copies the
    /// audio into it, so transcript, player and audio sit together (the original stays where it was).
    /// Returns the folder and the audio to transcribe: the copy, or the original when copying fails.
    /// A new folder in `dir` for an imported file, named after it, with a copy of the audio.
    /// Never reuses an existing folder (that would replace a recording or its transcript): when the
    /// name is taken it becomes `<name>_2`, `_3`… Names Bandje uses itself (Templates, selftest) and
    /// names starting with a dot (hidden, like `.models`) are avoided. A file that already lies in
    /// its own folder in `dir` (transcribing an import again) is used as is.
    static func importFolder(for url: URL, in dir: URL) -> (folder: URL, audio: URL) {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if parent.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL,
           parent.lastPathComponent == url.deletingPathExtension().lastPathComponent {
            return (parent, url)
        }
        var base = url.deletingPathExtension().lastPathComponent
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Import" }
        let name = uniqueName(base, in: dir)
        let folder = dir.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(name + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension))
        guard (try? fm.copyItem(at: url, to: copy)) != nil else { return (folder, url) }
        return (folder, copy)
    }

    /// The Bandje logo in the app bundle (nil in unit tests).
    static var bundledLogo: URL? { Bundle.main.url(forResource: "Logo", withExtension: "png") }


    /// `mm:ss` below an hour, `h:mm:ss` from an hour on.
    static func elapsedString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Folder names that are not recordings (also on the iPhone): compared case-insensitively.
    static let reserved: Set<String> = ["selftest", "inbox", "templates"]

    /// "Opname 6 nov 14.32" / "Recording 6 Nov 14.32": the iPhone's title for a new recording. The time
    /// has a dot: a colon is not allowed in names in Files, and the title is also the folder and file name.
    static func defaultTitle(for date: Date, locale: Locale = TranscriptWriter.titleLocale(), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let day = f.string(from: date).replacingOccurrences(of: ".", with: "")
        f.dateFormat = "HH.mm"
        return tr("recording.defaultTitle", "Opname %1$@ %2$@", day, f.string(from: date))
    }

    /// A title made safe as a file name: no `/` or `:`, no leading dots, not empty, not reserved.
    static func safeName(_ title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = tr("recording.untitled", "Opname") }
        return name
    }

    /// A folder name in `dir` that is not taken and not reserved: `name`, `name 2`, `name 3`…
    /// (an older recording lying directly in `dir` as `<name>.m4a` also takes the name).
    static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        func taken(_ n: String) -> Bool {
            reserved.contains(n.lowercased()) || fm.fileExists(atPath: dir.appendingPathComponent(n).path)
                || ["caf", "m4a"].contains { fm.fileExists(atPath: dir.appendingPathComponent("\(n).\($0)").path) }
        }
        var candidate = name, n = 2
        while taken(candidate) {
            candidate = "\(name) \(n)"
            n += 1
        }
        return candidate
    }

    /// Creates `<dir>/<title>/` with `.bandje.json` (`recording: true`) for a new recording and
    /// returns the `.caf` to write into.
    static func newRecording(title: String, date: Date, in dir: URL) throws -> URL {
        let name = uniqueName(safeName(title), in: dir)
        let folder = dir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingMeta(created: date, recording: true).write(to: folder)
        return folder.appendingPathComponent("\(name).caf")
    }

    /// The recording in `folder` is finished: `recording` goes off in `.bandje.json`.
    static func finishMeta(_ folder: URL) {
        guard var meta = RecordingMeta.read(from: folder) else { return }
        meta.recording = nil
        try? meta.write(to: folder)
    }

    /// Mode A/B (left = me, right = the other side) applies to a stereo recording this Mac made
    /// (its folder has `.bandje.json`), and to recordings with the old Mac names (`2026-11-05_14-30`).
    /// A recording from the iPhone is mono; an imported file goes through Transcribe File… as mode C.
    static func isOwnRecording(_ audio: URL) -> Bool {
        if TranscriptWriter.isRecordingName(audio.deletingPathExtension().lastPathComponent) { return true }
        guard RecordingMeta.read(from: audio.deletingLastPathComponent()) != nil,
              let file = try? AVAudioFile(forReading: audio) else { return false }
        return file.fileFormat.channelCount == 2
    }
}
