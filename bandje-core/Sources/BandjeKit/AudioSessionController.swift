// SPDX-License-Identifier: GPL-3.0-only
#if os(iOS)
import AVFoundation
import Foundation

/// iOS audio session for playback: category `.playback` / `.spokenAudio` (background audio needs
/// UIBackgroundModes audio), interruptions (P11) and route changes (P10) passed to the player.
/// Takes `player.willStartPlayback`; the app keeps `shouldStartPlayback` for its own rules.
@MainActor
public final class AudioSessionController {
    private let player: PlayerModel
    private let center: NotificationCenter
    /// Removed again in deinit. Only touched in init and deinit.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init(player: PlayerModel, center: NotificationCenter = .default) {
        self.player = player
        self.center = center
        player.willStartPlayback = { [weak self] in self?.activate() }
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let event = Self.interruption(note.userInfo)
            MainActor.assumeIsolated { self?.handle(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let removed = Self.outputRemoved(note.userInfo)
            MainActor.assumeIsolated { if removed { self?.player.outputDeviceRemoved() } }
        })
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// Before playback: the session plays in the background and with the silent switch on.
    public func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    /// When nothing plays and nothing records any more: other apps' audio may continue.
    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public enum Interruption: Equatable, Sendable {
        case began
        case ended(shouldResume: Bool)
    }

    /// Reads an interruption notification (pure, unit-tested).
    public nonisolated static func interruption(_ userInfo: [AnyHashable: Any]?) -> Interruption? {
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .began
        case .ended:
            let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            return .ended(shouldResume: options?.contains(.shouldResume) ?? false)
        @unknown default:
            return nil
        }
    }

    /// True when the route change means the old output went away (headphones unplugged, P10).
    public nonisolated static func outputRemoved(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let raw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return false }
        return AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    }

    private func handle(_ event: Interruption?) {
        switch event {
        case .began: player.interruptionBegan()
        case .ended(let resume): player.interruptionEnded(shouldResume: resume)
        case nil: break
        }
    }
}
#endif
