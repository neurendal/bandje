// SPDX-License-Identifier: GPL-3.0-only
import AVFAudio
import Foundation
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit
import os

/// A recording on the Watch: in progress, or done and waiting for the iPhone. Each lives in its own
/// folder (`Documents/Pending/<id>/<title>.aac`), so equal titles never collide and the iPhone
/// receives the file under its title. ADTS AAC, not `.m4a`: an `.m4a` (or AAC in `.caf`) cut off
/// by a kill has no index and cannot be read; ADTS frames stand on their own, so everything up to
/// the kill is kept. The iPhone turns it into `.m4a` without re-encoding.
struct WatchRecording: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// Start of the recording, to the second.
    var created: Date
    var title: String
    /// Seconds of audio.
    var duration: Double
    /// Marker times in seconds of audio, 0.1 s.
    var markers: [Double]

    var folder: URL { WatchRecorder.pendingDirectory.appending(path: id.uuidString, directoryHint: .isDirectory) }
    var url: URL {
        let m4a = folder.appending(path: WatchTransfer.fileName(for: title), directoryHint: .notDirectory)
        // Recorded by an earlier version (still waiting for the iPhone): `.m4a`.
        if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
        return m4a.deletingPathExtension().appendingPathExtension("aac")
    }
    var transfer: WatchTransfer { WatchTransfer(created: created, duration: duration, markers: markers, title: title) }
}

/// The Watch app's one model (design: `WatchRecorder`): records, marks, stops at the limits and
/// hands finished recordings to the iPhone (docs/watch.md 3, 4).
@MainActor @Observable
final class WatchRecorder {
    enum Phase: Equatable {
        case idle
        /// The one-time notice about telling people (SPEC 9), before the first recording.
        case onboarding
        case recording
        case stopped(WatchRecording)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Below 200 MB free: stopped (with what was kept) or refused to start (nil).
        case storage(WatchRecording?)
        /// Below 10 % battery: stopped (with what was kept) or refused to start (nil).
        case battery(WatchRecording?)
        case micDenied
        /// The recorder could not start (microphone busy, audio session refused).
        case cannotRecord
    }

    private enum StopReason { case user, storage, battery }

    static let shared = WatchRecorder()

    static let maxDuration: TimeInterval = 2 * 3600
    static let warnAt: TimeInterval = maxDuration - 5 * 60
    static let minFreeBytes: Int64 = 200_000_000
    static let minBattery: Float = 0.10

    nonisolated static let pendingDirectory = URL.documentsDirectory.appending(path: "Pending", directoryHint: .isDirectory)

    /// Mono AAC, 48 kHz, 64 kbit/s (docs/watch.md 3, owner 8 Nov 2026), in ADTS (the `.aac` url).
    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
    ]

    private(set) var phase: Phase = .idle
    /// Start of the timer that shows the recorded time (`Text(timerInterval:)`); nil when idle.
    private(set) var timerStart: Date?
    private(set) var markers: [Double] = []
    /// Paused with the middle button: the file stays open, the clock stands still. Also when the
    /// system stopped the recorder (`pausedByInterruption`).
    private(set) var isPaused = false
    /// The marker number shown on the Mark button for 1.2 s after marking.
    private(set) var markerFlash: Int?
    /// "5 minutes left" card (G1), shown for 5 s.
    private(set) var showsLimitWarning = false
    /// Recorded time for VoiceOver, updated every 10 s (a live region that does not chatter).
    private(set) var spokenElapsed: TimeInterval = 0
    /// Finished recordings the iPhone does not have yet, oldest first.
    private(set) var pending: [WatchRecording] = []
    /// "Sent to your iPhone": a transfer completed while the app was running (owner, 2026-11-10).
    var showsSent = false

    var consentGiven: Bool {
        get { access(keyPath: \.consentGiven); return UserDefaults.standard.bool(forKey: Keys.consent) }
        set { withMutation(keyPath: \.consentGiven) { UserDefaults.standard.set(newValue, forKey: Keys.consent) } }
    }

    @ObservationIgnored private var current: WatchRecording?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var lastElapsed: TimeInterval = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var warned = false
    @ObservationIgnored private var starting = false
    /// Paused because the system stopped the recorder (a call, Siri), not by the user: resumed when
    /// the interruption ends or the app comes back to the front.
    @ObservationIgnored private var pausedByInterruption = false
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var warningTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let link = PhoneLink()
    @ObservationIgnored private let log = Logger(subsystem: "com.neurendal.bandje.watchkitapp", category: "recorder")

    private enum Keys {
        static let consent = "consentShown"
        static let pending = "pending"
        static let inProgress = "inProgress"
    }

    /// Persisted while recording, so a recording survives the app being killed.
    private struct InProgress: Codable {
        var recording: WatchRecording
    }

    private init() {}

    // MARK: - Launch

    /// Once per process: the waiting list, a recording cut off by a kill, the iPhone link.
    func launch() {
        guard !launched else { return }
        launched = true
        if let data = UserDefaults.standard.data(forKey: Keys.pending),
           let list = try? JSONDecoder().decode([WatchRecording].self, from: data) {
            pending = list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
        recoverInterrupted()
        removeOrphans()
        observeAudioSession()
        link.activate()
        savePending()
        publishStatus()
        #if DEBUG
        debugScenario()
        #endif
    }

    #if DEBUG
    /// Screenshot demo (`-demoElapsed <s>`): seconds added to the recorder's clock, so the screen
    /// shows a recording well under way.
    @ObservationIgnored private var demoElapsed: TimeInterval = 0
    /// Screenshot demo (`-demoLevel 0…1`): a steady input level for the meter (the simulator's
    /// microphone gives silence).
    @ObservationIgnored private var demoLevel: Float?

    /// Simulator checks and screenshots only: `-scenario recording|marker|paused|stopped|onboarding`
    /// records (and stops after 3 s), skipping the notice; `idle` only skips the notice. For the App
    /// Store screenshots (scripts/dev/watch-shots.sh): `-demoElapsed`, `-demoLevel` and
    /// `-demoMarkers <n>` (markers already set before the scenario's own); with `marker` the flash
    /// on the Mark button then stays.
    private func debugScenario() {
        let defaults = UserDefaults.standard
        guard let scenario = defaults.string(forKey: "scenario") else { return }
        if scenario == "onboarding" {
            consentGiven = false
            phase = .onboarding
            return
        }
        consentGiven = true
        if scenario == "idle" { return }
        demoElapsed = defaults.double(forKey: "demoElapsed")
        if defaults.object(forKey: "demoLevel") != nil { demoLevel = defaults.float(forKey: "demoLevel") }
        let preset = defaults.integer(forKey: "demoMarkers")
        Task {
            // The simulator's microphone question cannot be answered from a script: start directly.
            begin()
            if demoElapsed > 0 {
                timerStart = Date().addingTimeInterval(-demoElapsed)
                spokenElapsed = demoElapsed
                // Spread over the time so far, at whole tenths, as the Mark button stores them.
                markers = (0..<preset).map { (demoElapsed * Double($0 + 1) / Double(preset + 1) * 10).rounded() / 10 }
                persistProgress()
                publishStatus()
            }
            if scenario == "stopped" {
                try? await Task.sleep(for: .seconds(3))
                mark()
                try? await Task.sleep(for: .seconds(1.5))
                stop()
            } else if scenario == "marker" {
                try? await Task.sleep(for: .seconds(3))
                mark()
                if demoElapsed > 0 { flashTask?.cancel() }
            } else if scenario == "paused" {
                try? await Task.sleep(for: .seconds(3))
                togglePause()
            }
        }
    }
    #endif

    /// The app was killed while recording: queue what is in the file. Audio that can't be read
    /// here is sent all the same (with the length last saved): the iPhone may manage, and nothing
    /// recorded is thrown away. Only an empty or missing file goes.
    private func recoverInterrupted() {
        guard let data = UserDefaults.standard.data(forKey: Keys.inProgress) else { return }
        if var rec = (try? JSONDecoder().decode(InProgress.self, from: data))?.recording {
            if let seconds = Self.audioDuration(rec.url), seconds > 0 {
                rec.duration = seconds
                rec.markers = rec.markers.filter { $0 <= seconds }
                pending.append(rec)
                log.notice("Recovered a recording cut off by a relaunch (\(Int(seconds)) s)")
            } else if Self.hasAudio(rec.url) {
                pending.append(rec)
                log.error("A recording cut off by a relaunch could not be read; sent as it is")
            } else {
                try? FileManager.default.removeItem(at: rec.folder)
            }
            savePending()
        }
        // Only now: until the list is saved, this is what knows about the recording.
        UserDefaults.standard.removeObject(forKey: Keys.inProgress)
    }

    /// Folders under Pending that no list knows about (a crash between steps). One with audio is
    /// queued after all (by its file name and date); only empty ones are removed.
    private func removeOrphans() {
        let fm = FileManager.default
        let known = Set(pending.map(\.id.uuidString))
        let folders = (try? fm.contentsOfDirectory(atPath: Self.pendingDirectory.path)) ?? []
        for name in folders where !known.contains(name) {
            let folder = Self.pendingDirectory.appending(path: name, directoryHint: .isDirectory)
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
            if let id = UUID(uuidString: name),
               let audio = files.first(where: { ["aac", "m4a"].contains($0.pathExtension) && Self.hasAudio($0) }) {
                let date = (try? audio.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let created = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
                var rec = WatchRecording(id: id, created: created, title: audio.deletingPathExtension().lastPathComponent,
                                         duration: Self.audioDuration(audio) ?? 0, markers: [])
                // The title gives the file name back; if it doesn't match, the folder's own name is used.
                if rec.url.lastPathComponent != audio.lastPathComponent { rec.title = Self.defaultTitle(for: created) }
                if rec.url.lastPathComponent == audio.lastPathComponent || (try? fm.moveItem(at: audio, to: rec.url)) != nil {
                    pending.append(rec)
                    log.notice("Queued a recording no list knew about")
                    continue
                }
            }
            try? fm.removeItem(at: folder)
        }
        pending.sort { $0.created < $1.created }
    }

    // MARK: - Record

    /// The record button, Siri, the Action button: notice first, then limits and the microphone.
    func record() async {
        guard phase != .recording, !starting else { return }
        guard consentGiven else {
            phase = .onboarding
            return
        }
        if let failure = limitFailure() {
            fail(failure)
            return
        }
        starting = true
        defer { starting = false }
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            fail(.micDenied)
            return
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                fail(.micDenied)
                return
            }
        default:
            break
        }
        begin()
    }

    /// "Begrepen" on the notice: then the system's microphone question, then recording.
    func acceptNotice() async {
        consentGiven = true
        phase = .idle
        await record()
    }

    func toggle() async {
        if phase == .recording { stop() } else { await record() }
    }

    private func begin() {
        let now = Date()
        let created = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let rec = WatchRecording(id: UUID(), created: created, title: Self.defaultTitle(for: created),
                                 duration: 0, markers: [])
        do {
            try FileManager.default.createDirectory(at: rec.folder, withIntermediateDirectories: true)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            let r = try AVAudioRecorder(url: rec.url, settings: Self.settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
        } catch {
            log.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: rec.folder)
            try? AVAudioSession.sharedInstance().setActive(false)
            fail(.cannotRecord)
            return
        }
        current = rec
        markers = []
        lastElapsed = 0
        spokenElapsed = 0
        ticks = 0
        warned = false
        showsLimitWarning = false
        markerFlash = nil
        isPaused = false
        pausedByInterruption = false
        timerStart = now
        phase = .recording
        WKInterfaceDevice.current().play(.start)
        startTicker()
        persistProgress()
        publishStatus()
    }

    /// Recorded seconds: the recorder's clock, which stands still during an interruption.
    var elapsed: TimeInterval {
        if let r = recorder, r.isRecording { return clock(r) }
        return lastElapsed
    }

    /// The recorder's clock (in DEBUG plus the screenshot demo's head start).
    private func clock(_ r: AVAudioRecorder) -> TimeInterval {
        #if DEBUG
        return r.currentTime + demoElapsed
        #else
        return r.currentTime
        #endif
    }

    /// Input level 0…1 for the meter (read by the view while it is visible).
    func level() -> Float {
        guard let r = recorder, r.isRecording else { return 0 }
        #if DEBUG
        if let demoLevel { return demoLevel }
        #endif
        r.updateMeters()
        // Speech into the Watch microphone sits around -35…-15 dBFS: map -45…-12 dB onto the full
        // meter, leaning on the peak so syllables show, with a curve that lifts quiet speech.
        let db = 0.6 * r.averagePower(forChannel: 0) + 0.4 * r.peakPower(forChannel: 0)
        let linear = max(0, min(1, (db + 45) / 33))
        return linear.squareRoot()
    }

    func mark() {
        guard phase == .recording else { return }
        let t = (elapsed * 10).rounded() / 10
        // Within 1 s of the previous marker: that one stands, nothing added (BandjeKit Markers).
        if let last = markers.last, abs(t - last) < 1 {} else { markers.append(t) }
        let n = markers.count
        WKInterfaceDevice.current().play(.directionUp)
        markerFlash = n
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.markerFlash = nil
        }
        announce(String(localized: "Marker \(n) set", comment: "VoiceOver after marking"))
        persistProgress()
        publishStatus()
    }

    /// The middle button (as the iPhone's pause): pause, or go on recording into the same file.
    func togglePause() {
        guard phase == .recording, let r = recorder else { return }
        if isPaused {
            guard resume(r) else { return }
            WKInterfaceDevice.current().play(.start)
            announce(String(localized: "Recording resumed", comment: "VoiceOver after resuming"))
        } else {
            lastElapsed = clock(r)
            r.pause()
            isPaused = true
            spokenElapsed = lastElapsed
            WKInterfaceDevice.current().play(.click)
            announce(String(localized: "Recording paused", comment: "VoiceOver after pausing"))
        }
        persistProgress()
        publishStatus()
    }

    /// Records on into the same file after a pause or an interruption.
    private func resume(_ r: AVAudioRecorder) -> Bool {
        try? AVAudioSession.sharedInstance().setActive(true)
        guard r.record() else {
            log.error("Could not resume recording")
            return false
        }
        isPaused = false
        pausedByInterruption = false
        timerStart = Date().addingTimeInterval(-lastElapsed)
        persistProgress()
        publishStatus()
        return true
    }

    /// The system stopped the recorder: shown as paused, the clock stands still.
    private func pauseForInterruption(_ r: AVAudioRecorder) {
        guard !isPaused else { return }
        lastElapsed = max(lastElapsed, clock(r))
        isPaused = true
        pausedByInterruption = true
        spokenElapsed = lastElapsed
        persistProgress()
        publishStatus()
    }

    /// The app is in front again: an interrupted recording goes on.
    func becameActive() {
        guard pausedByInterruption, let r = recorder, !r.isRecording else { return }
        _ = resume(r)
    }

    func stop() { finish(.user) }

    private func finish(_ reason: StopReason) {
        guard let r = recorder, var rec = current else { return }
        let recorded = elapsed
        r.stop()
        recorder = nil
        ticker?.invalidate()
        ticker = nil
        flashTask?.cancel()
        warningTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        current = nil
        timerStart = nil
        isPaused = false
        pausedByInterruption = false
        markerFlash = nil
        showsLimitWarning = false

        rec.duration = Self.audioDuration(rec.url) ?? recorded
        rec.markers = markers.filter { $0 <= rec.duration }
        markers = []
        if rec.duration > 0 || Self.hasAudio(rec.url) {
            pending.append(rec)
            savePending()
            link.send(rec)
        } else {
            try? FileManager.default.removeItem(at: rec.folder)
        }
        // Only after the list is saved: until then, this is what knows about the recording.
        UserDefaults.standard.removeObject(forKey: Keys.inProgress)

        switch reason {
        case .user:
            WKInterfaceDevice.current().play(.stop)
            phase = rec.duration > 0 ? .stopped(rec) : .idle
        case .storage:
            fail(.storage(rec.duration > 0 ? rec : nil))
        case .battery:
            fail(.battery(rec.duration > 0 ? rec : nil))
        }
        publishStatus()
    }

    private func fail(_ failure: Failure) {
        phase = .failed(failure)
        WKInterfaceDevice.current().play(.failure)
    }

    /// Back to Start (Done, OK, or 4 s after Stopped).
    func dismiss() {
        if phase != .recording { phase = .idle }
    }

    // MARK: - Limits (G1–G3)

    private func limitFailure() -> Failure? {
        // (The "important usage" capacity is not available on watchOS.)
        if let free = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           Int64(free) < Self.minFreeBytes {
            return .storage(nil)
        }
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        // -1 when unknown (simulator); charging never counts as low.
        let charging = device.batteryState == .charging || device.batteryState == .full
        if device.batteryLevel >= 0, device.batteryLevel < Self.minBattery, !charging { return .battery(nil) }
        return nil
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { WatchRecorder.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard let r = recorder else { return }
        if !r.isRecording, !isPaused {
            // Stopped by the system without an interruption ending yet: paused, not "recording".
            pauseForInterruption(r)
        }
        if r.isRecording {
            lastElapsed = clock(r)
            // Keep the on-screen timer on the recorder's clock (it stands still in an interruption).
            // Only a real gap moves it: each move shifts when the seconds tick, so small jitter of
            // the recorder's clock (after the screen was dimmed) made the seconds jump (owner,
            // 2026-11-11). An interruption still shows within two seconds.
            let anchor = Date().addingTimeInterval(-lastElapsed)
            if let start = timerStart, abs(start.timeIntervalSince(anchor)) > 1.5 {
                timerStart = anchor
                publishStatus()
            }
        }
        ticks += 1
        if lastElapsed >= Self.maxDuration {
            finish(.user)
            return
        }
        if lastElapsed >= Self.warnAt, !warned {
            warned = true
            showLimitWarning()
        }
        if ticks % 5 == 0 { persistProgress() }
        if ticks % 10 == 0 {
            spokenElapsed = lastElapsed
            switch limitFailure() {
            case .storage: finish(.storage)
            case .battery: finish(.battery)
            default: break
            }
        }
    }

    private func showLimitWarning() {
        WKInterfaceDevice.current().play(.notification)
        showsLimitWarning = true
        announce(String(localized: "5 minutes left. Recordings can be up to 2 hours.", comment: "VoiceOver for the 5 minutes warning"))
        warningTask?.cancel()
        warningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.showsLimitWarning = false
        }
    }

    // MARK: - Interruptions (as the prototype: resume when the interruption ends)

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let ended = raw.flatMap(AVAudioSession.InterruptionType.init) == .ended
            MainActor.assumeIsolated { WatchRecorder.shared.interruption(ended: ended) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            // The recorder is gone with the audio system: keep what was written.
            MainActor.assumeIsolated { WatchRecorder.shared.stop() }
        })
    }

    private func interruption(ended: Bool) {
        guard let r = recorder else { return }
        if ended {
            // A pause by the user stays a pause.
            if !r.isRecording, !isPaused || pausedByInterruption {
                let resumed = resume(r)
                log.notice("Interruption ended, resumed: \(resumed)")
            }
        } else {
            if !r.isRecording { pauseForInterruption(r) }
            log.notice("Interruption began")
        }
    }

    // MARK: - Persistence

    private func persistProgress() {
        guard var rec = current else { return }
        rec.markers = markers
        rec.duration = elapsed
        if let data = try? JSONEncoder().encode(InProgress(recording: rec)) {
            UserDefaults.standard.set(data, forKey: Keys.inProgress)
        }
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Keys.pending)
        }
    }

    /// The complications, Smart Stack and the Control read this.
    private func publishStatus() {
        let status = WatchStatus(recordingSince: phase == .recording ? timerStart : nil,
                                 pausedAt: phase == .recording && isPaused ? lastElapsed : nil,
                                 markers: markers.count, pending: pending.count)
        guard status != WatchStatus.current else { return }
        status.save()
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: WatchStatus.controlKind)
    }

    // MARK: - To the iPhone

    /// Queues every waiting recording the system is not already transferring. Safe to call often:
    /// at activation, when the app comes to the front, after a failed transfer.
    func sendPending() {
        let gone = pending.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !gone.isEmpty {
            pending.removeAll { rec in gone.contains { $0.id == rec.id } }
            savePending()
            publishStatus()
        }
        link.send(pending)
    }

    /// `session(_:didFinish:error:)`: delete only after a delivery without error.
    func transferFinished(path: String, created: String?, title: String?, failed: Bool) {
        guard let rec = pending.first(where: { PhoneLink.matches($0, path: path, created: created, title: title) }) else { return }
        if failed {
            log.error("Transfer to the iPhone failed; stays queued, tried again in a minute")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.sendPending()
            }
            return
        }
        try? FileManager.default.removeItem(at: rec.folder)
        pending.removeAll { $0.id == rec.id }
        savePending()
        publishStatus()
        confirmSent()
    }

    /// The success haptic and "Sent to your iPhone", only with the app running (not when woken in
    /// the background for the transfer) and not during a new recording. No notification.
    private func confirmSent() {
        guard WKApplication.shared().applicationState != .background, phase != .recording else { return }
        WKInterfaceDevice.current().play(.success)
        showsSent = true
    }

    // MARK: - Helpers

    /// As the iPhone's `Storage.defaultTitle(for:)` (Bandje/Library.swift): "Opname 8 nov 10.30".
    static func defaultTitle(for date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let day = f.string(from: date).replacingOccurrences(of: ".", with: "")
        f.dateFormat = "HH.mm"
        let time = f.string(from: date)
        return String(localized: "Recording \(day) \(time)", comment: "Default title of a new recording: day and time")
    }

    /// A file with more than a header in it.
    static func hasAudio(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 4_096
    }

    static func audioDuration(_ url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// WatchConnectivity: Apple's own Watch-to-iPhone link (docs/watch.md 4). No networking code.
final class PhoneLink: NSObject, WCSessionDelegate, Sendable {
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ rec: WatchRecording) { send([rec]) }

    /// Transfers each recording unless the system already has it queued (outstanding transfers
    /// survive relaunches), so nothing goes twice and nothing is lost.
    func send(_ recordings: [WatchRecording]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let outstanding = session.outstandingFileTransfers.map {
            ($0.file.fileURL.standardizedFileURL.path, $0.file.metadata?["created"] as? String, $0.file.metadata?["title"] as? String)
        }
        for rec in recordings where !outstanding.contains(where: { Self.matches(rec, path: $0.0, created: $0.1, title: $0.2) }) {
            session.transferFile(rec.url, metadata: rec.transfer.metadata)
        }
    }

    /// The same recording: the same file, or the same start and title in the metadata.
    static func matches(_ rec: WatchRecording, path: String, created: String?, title: String?) -> Bool {
        if path == rec.url.standardizedFileURL.path { return true }
        guard let created, let title else { return false }
        return title == rec.title && created == (rec.transfer.metadata["created"] as? String)
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in WatchRecorder.shared.sendPending() }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let path = fileTransfer.file.fileURL.standardizedFileURL.path
        let created = fileTransfer.file.metadata?["created"] as? String
        let title = fileTransfer.file.metadata?["title"] as? String
        let failed = error != nil
        Task { @MainActor in
            WatchRecorder.shared.transferFinished(path: path, created: created, title: title, failed: failed)
        }
    }
}
