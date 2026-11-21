// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import SwiftUI

@main
struct BandjeApp: App {
    @State private var library = Library.shared
    @State private var recorder = Recorder.shared
    @State private var player = Playback.player
    @State private var transcriptions = Transcriptions.shared
    @State private var summaries = SummaryJobs.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        Selftest.startIfRequested()
        // Automated runs never play out loud on the Mac running the simulator.
        if !Selftest.options.isEmpty { Playback.engine.volume = 0 }
        #endif
        // Files made for sharing in earlier runs (PDF, text, the audio page): their share sheets are gone.
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "Share", directoryHint: .isDirectory))
        // Purchases (specs/purchase.md): listens for transactions from launch, then looks up what
        // is owned. Never shows anything at launch.
        Purchases.shared.start(override: Self.purchaseOverride)
        // The audio session, Now Playing and the lock screen commands (specs/player.md).
        Playback.start()
        // Recordings from the Watch (docs/watch.md): also when iOS starts Band·je in the background for one.
        WatchReceiver.shared.start()
        // The selected tab (Transcript / Summary) in band.je navy, as on the Mac (owner, 6 Nov).
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.selection)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        if Self.prepareModelsAtLaunch {
            Task.detached(priority: .background) { await Transcriber.shared.prepareModels() }
        }
    }

    /// DEBUG only: `-purchaseState free|used|unlimited|dictation|existing` (screenshots, manual
    /// tests). Selftests that transcribe run unlocked unless they ask otherwise, so the device's free
    /// count never fails them. Release builds never read it.
    private static var purchaseOverride: Purchases.Override? {
        #if DEBUG
        if let state = UserDefaults.standard.string(forKey: "purchaseState") { return Purchases.Override(rawValue: state) }
        if !Selftest.options.isEmpty { return .unlimited }
        #endif
        return nil
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
            if phase == .background { Playback.player.saveNow() }  // P15
            if phase == .active {
                // A purchase on another device, a refund, or the existing-customer check that could
                // not be read at launch (offline).
                Task { await Purchases.shared.refresh() }
                Task {
                    await library.pickUpInbox()
                    await library.importFromWatch()
                    await library.refresh(except: recorder.folder)
                    // Watch recordings imported in the background: transcribing needs the app in front.
                    library.transcribeWaitingWatchImports()
                }
            }
        }
    }
}
