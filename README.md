# Use the Source, Luke.

<p align="center">
  <img src=".github/readme/logo.png" width="128" height="128" alt="Bandje">
</p>

<h3 align="center">Bandje records your conversations and turns them into text.<br>On your Mac, iPhone, iPad and Apple Watch. All on device.</h3>

<p align="center">
  <a href="https://apps.apple.com/app/id6831353548"><img src="https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download Bandje on the App Store"></a>
</p>

<p align="center">
  <b>Free to try. Pay once for Mac, iPhone and iPad.</b> No subscription. No tokens. No account.<br>
  <a href="https://band.je">band.je</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/readme/mac-04-window-dark.webp">
    <img src=".github/readme/mac-04-window-light.webp" width="820" alt="The Bandje window on the Mac: recordings per day, the player and the transcript with speaker names">
  </picture>
</p>

## What Bandje does

**⚡ Hyperfast prompt dictation on your Mac.** Press ⌃⌥⌘D, speak, and paste the text with ⌘V: in your editor, your mail, your AI prompt. Tap to start and stop, or hold to talk. Built from this source, or downloaded from [band.je](https://band.je/mac/), Bandje pastes it for you (see [Build it yourself](#build-it-yourself)).

**🎙️ Record and transcribe.** Calls in any app (FaceTime, Zoom, Teams, Meet, phone calls through your Mac), meetings, lectures and memos. Bandje records both sides of a call, and no bot joins your meeting. Already have recordings? Import your voice memos, earlier calls and other audio files and transcribe those too.

**🗣️ Who said what.** Speaker diarization labels every voice. Listen to a short clip of each speaker and give them a name.

**📝 Summaries in your own templates.** Write a template as a plain text file (meeting notes, action items, a sales call, a lecture) and Bandje fills it in with Apple Intelligence, on your device.

**⌚ Apple Watch.** Start a recording on your wrist, mark a moment, and pick it up on your iPhone.

**☁️ iCloud, if you want it.** Record on your iPhone, read on your Mac. Recordings, transcripts and summaries sync through your own iCloud Drive, not through us. Off by default.

**🌍 25 languages.** Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish and Ukrainian.

**🔗 A page that plays.** Share a transcript as one web page with the recording built in, for any browser. Or as PDF or text.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/readme/ios-02-transcript-dark.webp">
    <img src=".github/readme/ios-02-transcript-light.webp" width="200" alt="Transcript on the iPhone">
  </picture>
  &nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/readme/ios-05-speakers-dark.webp">
    <img src=".github/readme/ios-05-speakers-light.webp" width="200" alt="Naming speakers on the iPhone">
  </picture>
  &nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/readme/ios-06-summary-dark.webp">
    <img src=".github/readme/ios-06-summary-light.webp" width="200" alt="A summary from your own template on the iPhone">
  </picture>
</p>

## All on device

Speech recognition, speaker labels and summaries run on your own Mac, iPhone or iPad. Your audio, transcripts and summaries stay on your devices (and in your own iCloud Drive, if you turn sync on). No account, no analytics, no tracking.

Don't take our word for it. That's what this repository is for: the code of the App Store apps is here, and [`check-no-network.sh`](macos/scripts/check-no-network.sh) checks that it contains no networking code, on every push.

Two honest footnotes. The speech engine by [Desert Ant Labs](https://desertant.com) checks its license at most once a month per speech model. It sends a random install ID and version numbers, not tied to you. Never audio, never text. And the Mac download from [band.je](https://band.je/mac/) adds a small private layer that is not in this repository: a license check with Polar, update checks, and a one-time download of the speech models. See the [privacy page](https://band.je/privacy/).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/readme/mac-05-summary-dark.webp">
    <img src=".github/readme/mac-05-summary-light.webp" width="820" alt="A summary on the Mac">
  </picture>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6831353548"><img src="https://img.shields.io/badge/Get_Bandje_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Get Bandje on the App Store"></a>
</p>

| | Requires |
|---|---|
| **Mac** | macOS 15 or later, Apple silicon. Summaries need macOS 26 with Apple Intelligence. |
| **iPhone** | iOS 26 or later |
| **iPad** | iPadOS 26 or later |
| **Apple Watch** | watchOS 26 or later, with the iPhone app |

---

## Build it yourself

Bandje is free software under the GPL. Buying it on the App Store (or on [band.je](https://band.je/mac/)) is the easy way, and it keeps this project going. If you'd rather build it yourself, here's how.

| Folder | What | Build instructions |
|---|---|---|
| [`macos/`](macos) | The Mac app: menu bar, window, call recording, dictation (Swift Package, `make`) | [macos/README.md](macos/README.md) |
| [`ios/`](ios) | The iPhone, iPad and Apple Watch app (XcodeGen, Xcode 27) | [ios/README.md](ios/README.md) |
| [`bandje-core/`](bandje-core) | BandjeKit, the code both apps share: player, markers, purchases (Swift Package). The apps find it next to them as `../bandje-core`. | [bandje-core/README.md](bandje-core/README.md) |

In short, on an Apple silicon Mac with Xcode 27:

```sh
cd macos
./scripts/fetch-models.sh   # Voz and Who speech models (~400 MB) into ~/Music/Bandje/.models, checked against models.lock.json
make app                    # build/Bandje.app
make test

cd ../ios
make build                  # needs xcodegen; uses the same models
```

**The `APPSTORE` flag.** The Mac App Store build is compiled with `APPSTORE` (set in [`macos/mas/project.yml`](macos/mas/project.yml)). That build has the in-app purchases and, because of App Review guideline 2.4.5, no automatic pasting: dictated text goes to the clipboard. `make app` builds without the flag: everything is unlocked, there is no store, and dictation pastes for you after you allow Bandje under Privacy & Security › Accessibility. The iOS app has no such flag; it uses StoreKit, and [`ios/StoreKit/Bandje.storekit`](ios/StoreKit/Bandje.storekit) lets you test the purchases locally in Xcode.

Speech recognition (Voz) and speaker recognition (Who) by [Desert Ant Labs](https://desertant.com), under the Desert Ant Labs Source-Available License 1.0. They are fetched separately and are not covered by the GPL.

Each tag in this repository is the exact source of an App Store release: `macos-v1.0.0`, `ios-v1.0.0`, and so on. The code is developed elsewhere and published here per release, so this repository has one commit per release, not the day-to-day history.

## Contributing

Issues are welcome. Pull requests too: sign the [Contributor License Agreement](CLA.md) by ticking the box in the pull request template. See [CONTRIBUTING.md](CONTRIBUTING.md) for how a pull request makes its way into a release.

## License

Bandje's source code is licensed under the [GNU General Public License version 3](LICENSE) (GPL-3.0-only), with an additional permission (GPL section 7) to combine it with the Desert Ant Labs SDKs and models, see [NOTICE](NOTICE). Neurendal B.V. also distributes a compiled version through the App Store under its own [End-User License Agreement](https://band.je/terms/).

"Bandje" and the cassette logo are trademarks of Neurendal B.V. and are not covered by the GPL, see [TRADEMARKS.md](TRADEMARKS.md). Fork away, but give your build its own name and icon.

Apple, Mac, iPhone, iPad, iCloud and App Store are trademarks of Apple Inc. Bandje is not affiliated with or endorsed by Apple Inc.

Made by [Neurendal B.V.](https://neurendal.com)
