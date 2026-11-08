// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main
struct BandjeApp: App {
    @State private var library = Library.shared
    @State private var recorder = Recorder.shared
    @State private var player = Player.shared
    @State private var transcriptions = Transcriptions.shared
    @State private var summaries = SummaryJobs.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        Selftest.startIfRequested()
        // Automated runs never play out loud on the Mac running the simulator.
        if !Selftest.options.isEmpty { Player.shared.volume = 0 }
        #endif
        // The selected tab (Transcript / Summary) in band.je navy, as on the Mac (owner, 6 Nov).
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.selection)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        if Self.prepareModelsAtLaunch {
            Task.detached(priority: .background) { await Transcriber.shared.prepareModels() }
        }
    }

    /// Not in tests and selftests: they measure the models' first run themselves.
    private static var prepareModelsAtLaunch: Bool {
        #if DEBUG
        guard Selftest.options.isEmpty else { return false }
        #endif
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(recorder)
                .environment(player)
                .environment(transcriptions)
                .environment(summaries)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await library.pickUpInbox()
                    await library.refresh(except: recorder.folder)
                }
            }
        }
    }
}
