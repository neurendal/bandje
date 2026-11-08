// SPDX-License-Identifier: GPL-3.0-only
import ActivityKit
import Foundation
import Testing
@testable import Bandje

/// M7: Live Activity and Control state follow the recorder; intents respect the one-time notice.
@Suite(.serialized)
struct IntentsTests {
    @Test func timerStartCountsBackFromUpdate() {
        let now = Date()
        let state = RecordingAttributes.ContentState(elapsed: 75, isPaused: false, updatedAt: now)
        #expect(state.timerStart == now.addingTimeInterval(-75))
    }

    @Test func parsesIntentsFlag() {
        #expect(SelftestOptions(arguments: ["--intents"]).intents == "run")
        #expect(SelftestOptions(arguments: ["--intents", "hold"]).intents == "hold")
    }

    @MainActor @Test func startIntentNeedsTheNoticeFirst() async {
        let saved = RecordingCommands.consentShown
        defer { RecordingCommands.consentShown = saved }
        RecordingCommands.consentShown = false
        await #expect(throws: RecorderError.self) { _ = try await StartRecordingIntent().perform() }
        #expect(!Recorder.shared.isActive)
    }

    @MainActor @Test func liveActivityFollowsRecorder() async throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "intents-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: source) }
        try Selftest.writeSpeechLike(to: source, seconds: 10)

        func active() -> [[String: Any]] {
            LiveRecording.currentActivities().filter { ($0["state"] as? String) == "active" }
        }
        let recorder = Recorder()
        try await recorder.start(source: FakeMicSource(url: source))
        let folder = try #require(recorder.folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(RecordingControl.isRecording)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { await recorder.stop(); return }
        #expect(active().count == 1)
        #expect(active().first?["title"] as? String == folder.lastPathComponent)

        recorder.pause()
        try await Task.sleep(for: .milliseconds(600))
        #expect(active().first?["isPaused"] as? Bool == true)
        #expect((active().first?["elapsed"] as? Double ?? 0) > 0.3)

        recorder.resume()
        try await Task.sleep(for: .milliseconds(600))
        #expect(active().first?["isPaused"] as? Bool == false)

        await recorder.stop()
        try await Task.sleep(for: .milliseconds(600))
        #expect(active().isEmpty)
        #expect(!RecordingControl.isRecording)
    }
}
