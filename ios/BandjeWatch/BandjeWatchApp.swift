// SPDX-License-Identifier: GPL-3.0-only
import AppIntents
import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct BandjeWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    init() {
        WatchRecorder.shared.launch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(WatchRecorder.shared)
                #if DEBUG
                // Screenshots of the dimmed (Always On) state: `-demoDimmed YES`, DEBUG only.
                .transformEnvironment(\.isLuminanceReduced) { if UserDefaults.standard.bool(forKey: "demoDimmed") { $0 = true } }
                #endif
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchRecorder.shared.launch()
    }

    /// Woken for WatchConnectivity (a transfer finished while the app was not running): stay
    /// awake until the session has delivered its callbacks.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            WatchRecorder.shared.launch()
            Task { @MainActor in
                for _ in 0..<40 {
                    let session = WCSession.default
                    if session.activationState == .activated, !session.hasContentPending { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                connectivity.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

/// Siri ("Neem op met Band·je") and Shortcuts; the Action button through the Control or a shortcut.
struct BandjeWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Start a recording in \(.applicationName)", "Record with \(.applicationName)"],
                    shortTitle: "Start Recording", systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Stop the recording in \(.applicationName)", "Stop \(.applicationName)"],
                    shortTitle: "Stop Recording", systemImageName: "stop.circle")
        AppShortcut(intent: ToggleRecordingIntent(),
                    phrases: ["Start or stop a recording in \(.applicationName)"],
                    shortTitle: "Start/Stop Recording", systemImageName: "record.circle")
    }
}
