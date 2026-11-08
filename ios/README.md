# Bandje for iPhone and iPad

The iPhone and iPad app: record a meeting or a memo, import audio from Files or the share sheet, and
transcribe it on the device with speaker labels. Summaries in your own templates through Apple
Intelligence, on the device. Optional sync with the Mac through your own iCloud Drive.

Want it without building? [Get Bandje on the App Store](https://apps.apple.com/app/id6831353548).

## Requirements

- Xcode 27 (the app runs on iOS 26 and later, but uses iOS 27 APIs where available), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen`)
- An iOS 26 simulator (the Makefile picks the first "iPhone 17 Pro"), or a device
- About 400 MB for the speech models

## Build

The speech models are not in this repository. Fetch them once with the Mac app's script (it checks
every file against `models.lock.json`, which is the same for both apps):

```sh
../macos/scripts/fetch-models.sh   # Voz and Who into ~/Music/Bandje/.models
make build                         # generates Bandje.xcodeproj, builds for the simulator
make run                           # installs and launches it in the simulator
make test                          # unit and UI tests
./scripts/check-no-network.sh      # after make build
```

A build step copies the models from `~/Music/Bandje/.models` into the app, after checking them
against `models.lock.json`. The app never downloads anything itself.

To run on your own device, change `DEVELOPMENT_TEAM` and the bundle identifiers
(`com.neurendal.bandje…`) and the iCloud container in `project.yml` to your own, then `make device`.
Please give a build you distribute a different name and icon, see [TRADEMARKS.md](../TRADEMARKS.md).

## Network

Bandje's own code never uses the network: no URLSession, sockets or WebKit, no CloudKit. iCloud sync
is iOS moving files in iCloud Drive. `scripts/check-no-network.sh` checks the source, the
dependencies, the entitlements and the binary.

The speech engine by Desert Ant Labs checks its license, at most once a month per speech model. It
sends a random install ID, the model and engine version and the app ID; never audio, never text. The
Desert Ant Labs license does not allow disabling this check.

## Layout

| Path | What |
|---|---|
| `Bandje/` | The app: recording, import, player, transcription (Voz, Who), summaries, iCloud, web export |
| `Shared/` | Code shared with the extensions (App Intents) |
| `ShareExtension/` | Import audio from the share sheet |
| `Widgets/` | The recording's Live Activity (lock screen, Dynamic Island) and a Control Center control |
| `BandjeTests/`, `BandjeUITests/` | Tests |
| `scripts/` | Model check, network check, App Store archive, test fixtures |

## License

GPL-3.0-only with an additional permission for the Desert Ant Labs SDKs and models, see
[LICENSE](LICENSE) and [NOTICE](NOTICE). The name and the cassette logo are trademarks of Neurendal
B.V., see [TRADEMARKS.md](../TRADEMARKS.md).
