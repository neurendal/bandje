// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MediaPlayer
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Now Playing (lock screen, Control Center, the Mac's menu bar Now Playing) and the remote
/// commands (media keys, AirPods, headphone buttons): play, pause, ±15 s, scrubbing. Follows the
/// player by observation; the elapsed time is set on every change of state, rate or seek, and the
/// system runs the clock from the rate in between.
@MainActor
public final class NowPlayingController {
    private let player: PlayerModel
    private let artist: String
    private var artwork: (file: URL, item: MPMediaItemArtwork)?
    /// The remote command targets, removed again in deinit (MPRemoteCommandCenter is shared).
    /// Only touched in init and deinit.
    nonisolated(unsafe) private var targets: [(command: MPRemoteCommand, target: Any)] = []

    public init(player: PlayerModel, artist: String = "Band·je") {
        self.player = player
        self.artist = artist
        installCommands()
        update()
        observe()
    }

    deinit {
        for (command, target) in targets { command.removeTarget(target) }
    }

    /// The info for the current state; nil without a recording (unit-tested).
    public static func info(for player: PlayerModel, artist: String, artwork: MPMediaItemArtwork? = nil) -> [String: Any]? {
        guard let item = player.current else { return nil }
        // Typed: in an [String: Any] literal a bare 0 would be an Int.
        let playbackRate: Double = player.isPlaying ? Double(player.rate) : 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        return info
    }

    /// Call when the cover of the current recording changed on disk.
    public func artworkChanged() {
        artwork = nil
        update()
    }

    private func observe() {
        withObservationTracking {
            _ = player.current
            _ = player.state
            _ = player.rate
            _ = player.duration
            _ = player.seekCount
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        let commands = MPRemoteCommandCenter.shared()
        let enabled = player.current != nil
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                        commands.skipForwardCommand, commands.skipBackwardCommand,
                        commands.changePlaybackPositionCommand] {
            command.isEnabled = enabled
        }
        guard let item = player.current else {
            artwork = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = Self.info(for: player, artist: artist, artwork: loadArtwork(item.artwork))
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ file: URL?) -> MPMediaItemArtwork? {
        guard let file else {
            artwork = nil
            return nil
        }
        if let artwork, artwork.file == file { return artwork.item }
        guard let item = Self.artwork(contentsOf: file) else { return nil }
        artwork = (file, item)
        return item
    }

    /// The cover for Now Playing. Not on the main actor: Media Player asks for the image on a
    /// background queue, and a main-actor closure traps there (Swift 6 isolation check).
    public nonisolated static func artwork(contentsOf file: URL) -> MPMediaItemArtwork? {
        #if os(macOS)
        guard let image = NSImage(contentsOf: file) else { return nil }
        #else
        guard let image = UIImage(contentsOfFile: file.path) else { return nil }
        #endif
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Handlers come in on the main thread; they hop to the main actor explicitly.
    private func installCommands() {
        let center = MPRemoteCommandCenter.shared()
        let player = player
        func add(_ command: MPRemoteCommand,
                 _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            targets.append((command, command.addTarget(handler: handler)))
        }
        add(center.playCommand) { [weak player] _ in
            Task { @MainActor in
                guard let player, !player.isPlaying else { return }
                player.togglePlayPause()
            }
            return .success
        }
        add(center.pauseCommand) { [weak player] _ in
            Task { @MainActor in player?.pause(reason: .user) }
            return .success
        }
        add(center.togglePlayPauseCommand) { [weak player] _ in
            Task { @MainActor in player?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: PlayerModel.skipInterval)]
        add(center.skipForwardCommand) { [weak player] _ in
            Task { @MainActor in player?.skip(by: PlayerModel.skipInterval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: PlayerModel.skipInterval)]
        add(center.skipBackwardCommand) { [weak player] _ in
            Task { @MainActor in player?.skip(by: -PlayerModel.skipInterval) }
            return .success
        }
        add(center.changePlaybackPositionCommand) { [weak player] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in player?.seek(to: position) }
            return .success
        }
    }
}
