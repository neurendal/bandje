# Band·je

Band·je records your calls and meetings on your Mac and turns them into text. Everything happens on your Mac: no account, no analytics, no server of ours. Your recordings follow you to your iPhone only if you turn on iCloud sync, through your own iCloud Drive.

It lives in the menu bar as a small cassette tape, with a window for all your recordings.

- **Record** with ⌃⌥⌘R: your microphone (left channel) and your Mac's sound (right channel) in one stereo file. Works with any call app (FaceTime, Zoom, Teams, Meet, phone calls through your Mac). System audio comes from a Core Audio process tap; Band·je never records the screen.
- **Transcribe** on your Mac, in 25 languages, with speaker labels. Name the speakers after listening to a short clip of each.
- **Dictate anywhere** with ⌃⌥⌘D: speak, and the text is pasted where your cursor is. Tap to start and stop, or hold to talk.
- **The Band·je window**: your recordings per day, the cassette and player, the transcript that follows the audio (click a sentence to hear it), a tab per summary, naming speakers, search.
- **Share as web page**: one self-contained HTML file with the player, transcript, summaries and the audio, for anyone, in any browser.
- **Sync with iCloud** (optional, off by default): recordings, transcripts, summaries and templates in iCloud Drive › Band·je, shared with the iPhone app.
- **Summaries** with Apple Intelligence on your Mac (macOS 26), from templates you write yourself as plain text files.
- The app and its built-in help in 10 languages.

Website: [band.je](https://band.je). Source: [github.com/neurendal/bandje](https://github.com/neurendal/bandje). Made by [Neurendal B.V.](https://neurendal.com)

## Requirements

- Apple silicon Mac, macOS 15 or later (summaries need macOS 26 with Apple Intelligence on)
- Xcode command line tools (Swift 6)
- About 400 MB for the speech models

## Build

```sh
# A stable signing identity keeps macOS permissions across rebuilds (free "Apple Development"
# certificate from Xcode > Settings > Accounts, or a self-signed code signing certificate).
security find-identity -v -p codesigning
export BANDJE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"

./scripts/fetch-models.sh     # downloads Voz and Who to ~/Music/Bandje/.models (once), checked against models.lock.json
make app                      # build/Bandje.app (debug build with test modes); the models go inside the app
make install                  # release build in ~/Applications
```

Without `BANDJE_SIGN_IDENTITY` the app is signed ad-hoc, and macOS may ask for the microphone and system-audio permissions again after every build. The bundle ID is `com.neurendal.bandje`; change it in `Resources/Info.plist` if you distribute your own build.

The app never downloads anything itself. `make app` copies the models into the app (`Contents/Resources/Models`, about 400 MB); with `BUNDLE_MODELS=0` it leaves them out and the app loads them from `~/Music/Bandje/.models`.

`models.lock.json` pins each model to an exact Hugging Face commit and lists the size and SHA-256 of every file; `fetch-models.sh` refuses anything else. To move to a newer `desert-ant-core`: raise the version in `Package.swift`, set the model revisions its `Catalog.swift` declares in `scripts/dev/fetch_models.py`, run `python3 -I scripts/dev/fetch_models.py ~/Music/Bandje/.models --update-lock`, then the full selftest. `scripts/dev/check-sdk-update.sh` tells you when a newer `desert-ant-core` exists.

## Network

Band·je's own code never uses the network: no URLSession, sockets or WebKit, no CloudKit. The only URLs are three links in the About window that open your browser, and the band.je link in a shared web page. iCloud sync is macOS moving files in iCloud Drive. `scripts/check-no-network.sh` checks the source, the dependencies, the entitlements and the binary.

The app has the `network.client` entitlement for one reason: the speech engine by Desert Ant Labs checks its license, at most once a month per speech model. It sends a random install ID, the model and engine version and the app ID; never audio, never text. The Desert Ant Labs license does not allow disabling this check, so there is no build without it.

## Tests

```sh
make test                     # unit tests, translations, help sources
./scripts/check-no-network.sh
make selftest-quick           # live checks with the real app, no audio played (~1 min)
make selftest                 # full run: plays and records test audio (~10 min)
```

The selftests make their test audio with macOS voices (`scripts/dev/make-fixtures.sh`) the first time.

## Layout

| Path | What |
|---|---|
| `Sources/Bandje/` | The app: recording (`Recorder.swift`, `FileWriter.swift`), transcription (`Transcriber.swift`, `TranscriptWriter.swift`), dictation, summaries, window (`MainWindow.swift`, `RecordingView.swift`, `Library.swift`), iCloud (`ICloud.swift`), web export (`WebExport.swift`), menu (`BandjeApp.swift`) |
| `Resources/Localization/` | Translations; the Dutch source texts are in the code as `tr("key", "text")`, see `scripts/strings.py` |
| `Resources/Help/` | Help book sources, one file per language (`en.md` is the source); `TRANSLATE.md` is the prompt for translating |
| `scripts/` | Model download, help and translation tools, network check, selftests |

## License

Bandje's source code is licensed under the GNU General Public License version 3 (GPL-3.0-only), see [LICENSE](LICENSE), with an additional permission (GPL section 7) to combine it with the Desert Ant Labs SDKs and models, see [NOTICE](NOTICE). Neurendal B.V. also distributes a compiled version through the Mac App Store under a separate license agreement.

Speech recognition (Voz) and speaker recognition (Who) by Desert Ant Labs (https://desertant.com), under the Desert Ant Labs Source-Available License 1.0. They are based on NVIDIA Parakeet TDT 0.6B v3 and pyannote community-1 (CC BY 4.0). The GPL does not cover these models and SDKs; see [NOTICE](NOTICE). `desert-ant-core` also brings in `apple/swift-numerics` (Apache 2.0).
