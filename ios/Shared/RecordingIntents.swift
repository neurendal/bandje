// SPDX-License-Identifier: GPL-3.0-only
import ActivityKit
import AppIntents
import Foundation

// Compiled into both the app and the widget extension (WIDGET_EXTENSION). The intents below are
// system intents (AudioRecordingIntent, LiveActivityIntent): the system runs them in the app's
// process, so their work lives in the app (`RecordingCommands`); in the extension they do nothing.

/// The Live Activity while recording (SPEC 4): title, time, lamp, pause and stop.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Recorded time at `updatedAt`, pauses excluded.
        var elapsed: TimeInterval
        var isPaused: Bool
        var updatedAt: Date

        /// The start of a timer that shows `elapsed` at `updatedAt` and keeps counting: the
        /// widget uses `Text(timerInterval:)`, so no per-second updates are needed.
        var timerStart: Date { updatedAt.addingTimeInterval(-elapsed) }
    }

    var title: String
}

/// Recording state shared with the Control (Control Centre, Action button) via the App Group.
enum RecordingControl {
    static let kind = "com.neurendal.bandje.record"
    static let appGroup = "group.com.neurendal.bandje"
    private static let key = "isRecording"

    static var isRecording: Bool {
        get { UserDefaults(suiteName: appGroup)?.bool(forKey: key) ?? false }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: key) }
    }
}

struct StartRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Starts a new recording in Bandje.")
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try await RecordingCommands.start()
        #endif
        return .result()
    }
}

struct StopRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the recording in Bandje and saves it.")
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RecordingCommands.stop()
        #endif
        return .result()
    }
}

/// The pause/resume button in the Live Activity.
struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Recording"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RecordingCommands.togglePause()
        #endif
        return .result()
    }
}

/// The Control: on starts a recording, off stops it.
struct RecordingToggleIntent: SetValueIntent, AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Recording")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if value {
            try await RecordingCommands.start()
        } else {
            await RecordingCommands.stop()
        }
        #endif
        return .result()
    }
}
