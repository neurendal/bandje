// SPDX-License-Identifier: GPL-3.0-only
import ActivityKit
import AppIntents
import Foundation
import WidgetKit

/// What the intents (Siri, Shortcuts, Action button, Control, Live Activity buttons) and the
/// record screen do. Runs in the app.
@MainActor
enum RecordingCommands {
    /// UserDefaults key: the one-time notice before the first recording was shown (SPEC 9).
    static let consentKey = "consentShown"

    static var consentShown: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }

    /// Starts a recording unless one is running. The first recording must start in the app,
    /// after the notice about informing participants.
    static func start() async throws {
        let recorder = Recorder.shared
        guard !recorder.isActive else { return }
        guard consentShown else {
            throw RecorderError(message: String(localized: "Open Bandje to make your first recording."))
        }
        Player.shared.unload()
        #if DEBUG
        try await recorder.start(source: Selftest.uiFakeMic())
        #else
        try await recorder.start()
        #endif
    }

    /// Stops and saves the recording, then transcribes it if that setting is on.
    static func stop() async {
        let recorder = Recorder.shared
        guard recorder.isActive, let folder = await recorder.stop() else { return }
        let library = Library.shared
        await library.refresh()
        library.justRecorded = folder
        Transcriptions.shared.startIfAutomatic(library.recordings.filter { $0.folder == folder })
    }

    static func togglePause() {
        let recorder = Recorder.shared
        recorder.state == .paused ? recorder.resume() : recorder.pause()
    }
}

/// Keeps the Live Activity and the Control in step with the recorder.
@MainActor
final class LiveRecording {
    static let shared = LiveRecording()

    /// Only the id is kept: `Activity` is not Sendable, so each update finds it again off the
    /// main actor.
    private var activityID: String?
    #if DEBUG
    /// What happened, for the selftests.
    private(set) var events: [String] = []
    #endif

    /// Call after every recorder state change.
    func sync(_ recorder: Recorder) {
        let state = RecordingAttributes.ContentState(elapsed: recorder.elapsed, isPaused: recorder.state == .paused,
                                                     updatedAt: Date())
        if RecordingControl.isRecording != recorder.isActive {
            RecordingControl.isRecording = recorder.isActive
            ControlCenter.shared.reloadControls(ofKind: RecordingControl.kind)
        }
        if recorder.isActive {
            if let id = activityID {
                Task.detached {
                    for activity in Activity<RecordingAttributes>.activities where activity.id == id {
                        await activity.update(ActivityContent(state: state, staleDate: nil))
                    }
                }
                log(state.isPaused ? "update-paused" : "update-recording")
            } else {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { log("disabled"); return }
                do {
                    activityID = try Activity.request(attributes: RecordingAttributes(title: recorder.title),
                                                      content: ActivityContent(state: state, staleDate: nil)).id
                    log("requested")
                } catch {
                    log("request-failed: \(error.localizedDescription)")
                }
            }
        } else if let id = activityID {
            activityID = nil
            Self.end(where: { $0 == id }, state: state)
            log("ended")
        }
    }

    /// Ends activities left over from a previous run (crash, forced quit) and resets the Control.
    func cleanUpAfterLaunch() {
        guard !Recorder.shared.isActive else { return }
        let current = activityID
        Self.end(where: { $0 != current }, state: nil)
        if RecordingControl.isRecording {
            RecordingControl.isRecording = false
            ControlCenter.shared.reloadControls(ofKind: RecordingControl.kind)
        }
    }

    private nonisolated static func end(where matches: @escaping @Sendable (String) -> Bool,
                                        state: RecordingAttributes.ContentState?) {
        Task.detached {
            for activity in Activity<RecordingAttributes>.activities where matches(activity.id) {
                await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: .immediate)
            }
        }
    }

    #if DEBUG
    /// The app's activities as the system reports them (selftest).
    nonisolated static func currentActivities() -> [[String: Any]] {
        Activity<RecordingAttributes>.activities.map {
            ["id": $0.id, "title": $0.attributes.title, "state": "\($0.activityState)",
             "isPaused": $0.content.state.isPaused, "elapsed": $0.content.state.elapsed]
        }
    }
    #endif

    private func log(_ event: String) {
        #if DEBUG
        events.append(event)
        #endif
    }
}

struct BandjeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Start a recording in \(.applicationName)", "Record with \(.applicationName)"],
                    shortTitle: "Start Recording", systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Stop the recording in \(.applicationName)", "Stop \(.applicationName)"],
                    shortTitle: "Stop Recording", systemImageName: "stop.circle")
    }
}
