# bandje-core

Swift package with the library **BandjeKit**: code shared by Bandje for macOS and for iOS.
macOS 15 and iOS 26, Swift 6, no dependencies, no networking code.

    swift build
    swift test                       # Swift Testing
    scripts/check-no-network.sh      # also run by both apps' check-no-network.sh

What is in it: the continuous player (`specs/player.md` in the umbrella folder, rules P1 to P16).

| File | What |
|---|---|
| `Player.swift` | `PlayerModel` (the one player, @Observable), `PlayableItem`, `RecordingID` |
| `AudioEngine.swift` | `AudioEngine` protocol, `AVAudioPlayerEngine` (real), `FakeAudioEngine` (tests, selftests) |
| `PlaybackPositionStore.swift` | Position per recording, global speed, last played (UserDefaults) |
| `NowPlayingController.swift` | Now Playing and remote commands (media keys, lock screen, AirPods) |
| `AudioSessionController.swift` | iOS only: audio session, interruptions (P11), route changes (P10) |
| `CoverPolicy.swift` | When a device writes a recording's cover into its audio (`specs/icloud-sync.md`): only for its own changes or a recording without one, never over a newer file in iCloud |

Tests: `swift test` (macOS) and `xcodebuild -scheme bandje-core -destination <iOS simulator> test`.

The apps use it by path, so the folders sit side by side:

    bandje-core/    this package
    bandje-mac/     Package.swift and mas/project.yml: ../bandje-core
    bandje-ios/     project.yml: ../bandje-core

License: GPL-3.0-only (LICENSE), as the apps.
