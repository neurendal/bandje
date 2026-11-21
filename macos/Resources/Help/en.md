# Band·je Help
Band·je records conversations on your Mac and turns them into text. It lives in the menu bar: the little cassette tape at the top right. Everything happens on your Mac.

## Recording a conversation {#record}
Press ⌃⌥⌘R to start, and ⌃⌥⌘R again to stop.

Band·je records two things at once: your microphone and all sound your Mac plays. It works with any call app, such as FaceTime, Zoom, Teams, Meet or a phone call through your Mac. Band·je does not record your screen.

- While recording, the cassette in the menu bar turns red, its reels turn and the time runs next to it in red.
- Your Mac does not go to sleep while Band·je records.
- Heard something important? Press ⌃⌥⌘M to mark that moment, see [Markers](#player).
- macOS asks for permission to record your Mac's audio when you click **Allow…** in the welcome or under Settings › Access, or else at the first recording. Allow it, or Band·je can only hear your microphone. At the start of every recording Band·je checks it, silently, and warns you right away when it is off.
- If your microphone stays silent for six seconds, or the lid is closed while the built-in microphone is in use, Band·je warns you and offers to switch to another microphone.

Let the other people know you are recording. In some countries, and for business use, the law requires it, and sometimes you need their consent too. You are responsible for following the law that applies to you. Band·je reminds you once, before your first recording.

### Where your recordings go
Every recording gets its own folder in `~/Music/Bandje` (or the folder you chose in [Settings](#settings), or iCloud Drive › Band·je when you [sync with iCloud](#settings)), named after the day and time, such as `Recording Nov 6 14.32`. Your iPhone names its recordings the same way. In the folder:

- the audio (`.m4a`): you on the left channel, the others on the right
- the transcript (`.md`), readable in any text or Markdown app
- the raw data (`.json`) with the time of every word
- summaries, as `.md` files

Open a recording in the [Band·je window](#player). Choose **Open Recordings Folder** in the menu to see the files. If Band·je or your Mac stops unexpectedly during a recording, Band·je offers to save it the next time it starts.

## Transcripts {#transcripts}
After you stop recording, Band·je writes down what was said, with who said it.

The menu shows the progress. You can start a new recording while Band·je transcribes. When the transcript is ready, a small green check mark appears on the cassette in the menu bar, and the menu says **Transcript ready**: click it to open the recording in the Band·je window. The check mark goes away once you have opened the menu.

- What you say is labelled **Me**. What the others say is labelled **Other side**.
- When several people speak on the other side, Band·je tells them apart: **Speaker 1**, **Speaker 2** and so on. Give them names with [Name Speakers](#speakers).
- The same goes for several people around your Mac, for a meeting at one table: instead of **Me** they become **Speaker 1**, **Speaker 2** and so on.
- Band·je understands 25 languages, including English, Dutch, German, French, Spanish, Italian, Portuguese, Polish, Russian and Ukrainian. You don't need to choose the language.

For the best result, wear headphones during a call. Without them, your microphone also picks up the other side from your speakers. Band·je filters most of that out, but not all.

### Transcribing another file
Choose **Transcribe File…** to transcribe any audio or video file, such as a voice memo from your iPhone or a video call you saved. Band·je copies it to its own folder in your recordings folder and puts the transcript next to it; of a video it keeps only the sound. The original stays where it was. You can add [markers](#player) to it as to your own recordings.

## Naming speakers {#speakers}
Give the speakers in a transcript their real names.

Open the recording in the [Band·je window](#player) and choose **Name Speakers…** under **More**, or choose **Name Speakers…** in the menu: it opens the current recording. To work on an older recording from the menu, choose **Recent Recordings** first.

For every speaker you see their longest quote. Click the play button to hear that part, type a name and click **Save**. Band·je updates the transcript and any later summary. Leave a field empty to keep the label.

On a phone line with a menu or hold music, Band·je sometimes hears more speakers than there were. Give two labels the same name, or leave the extra one as it is.

## The Band·je window {#player}
All your recordings in one window: listen, read along, search, name speakers, summarize and share.

Choose **Open Band·je** in the menu (⌘O). The window also opens when you start Band·je yourself, for example from Launchpad or Spotlight. **Open in Band·je** opens the current recording. While the window is open, Band·je is in the Dock and in ⌘Tab; close it and Band·je is back in the menu bar only. Turn on **Always in the Dock** in [Settings](#settings) to keep the icon. The first time, the window always opens with a welcome in two steps: first the shortcuts, then **Next** to the permissions, each with its own button. Close the window and Band·je stays in the menu bar; quit Band·je from that menu.

- On the left: your recordings per day, with the time, the length and the first words of the transcript. Search finds titles and words in transcripts. At the bottom is **Start Recording**; while you record, the new recording is at the top with a red dot, and when you stop, the window opens it.
- On the right: the recording with the cassette, the position bar and the play button (Space). Click a sentence to listen from there; while playing, the sentence you hear lights up and the transcript follows. ⌘← and ⌘→ skip 15 seconds back and forward. **Search Transcript** (⌘F) finds words.
- Every recording remembers where you left off, also after a restart; the speed applies to all recordings. Only the recording you see plays: open another recording or close the window and playback stops. Starting a recording or dictation pauses it. When you stop a recording, the window opens with it; choose **Transcribe File…** or a template under **Summarize** in the menu and the window opens with that recording, showing the progress.
- Next to **Transcript** is the **Summary** tab. Without a summary yet, it holds **Summarize**: choose a template, see [Summaries](#summaries). Every summary gets its own tab; **Another Summary** makes one more.
- No transcript yet (a recording from your iPhone, for example)? Click **Transcribe**.
- **Share**: **Audio…** and **Audio Page…** share the recording. **Share As…**, **Copy As…** and **Save As…** first ask **PDF**, **Text** or **Markdown** and are one document: the summaries first, then the transcript. With summaries you also check there what goes in (everything is checked). **Save As…** saves it where you want, **Copy As…** puts it on the clipboard. **Audio Page…** is one file with the player, the transcript, the summaries and the audio, which works in any browser, also offline. **Audio Page, Compact (for Email)…** makes the audio smaller. The page has a link to band.je and nothing else.
- On paper: **Print…** (⌘P, or in **Share**) prints the same document as the PDF.
- Copying: **Copy** next to a summary puts its text on the clipboard. You can also select text and press ⌘C.
- **More**: **Name and Colour…** (or click the title on the cassette): the name and the cassette's colour, **Name Speakers…**, **Show in Finder**, **Delete…** (to the Trash).
- You can also delete a recording from the list: right-click it and choose **Delete…**, or select it and press ⌫. Band·je asks first.

### Markers
A marker is a small flag at a moment in the recording, so you can find it again.

- While recording: press ⌃⌥⌘M, choose **Mark This Moment** in the menu, or click the flag next to the stop button in the window. A short sound confirms it.
- While listening: click the flag to the right of the play button, or press ⌘D or ⌃⌥⌘M. The marker goes where you are in the recording.
- The flags show on the position bar and in the transcript, before the sentence the marker falls in. Under the paragraph is the marker's time: click it to listen from there. Without a transcript yet, the markers are listed under **Transcribe**.
- A note: click **Add a note…** under the marker, type one line and click **Save**. While playing, the note shows above the position bar for a moment when you reach the marker. Clear the field to remove the note; the marker stays.
- Removing: right-click the marker and choose **Remove Marker**. Made a mistake? Click **Undo** in the message that stays for a few seconds.
- Markers and notes are also in the transcript (`.md`), the PDF, the printout and the web page, as a line `🚩 12:34 note` under the paragraph the marker falls in. When you sync with iCloud, markers set on your iPhone show on your Mac, and the other way round.

## Dictation {#dictation}
Press ⌃⌥⌘D, speak, and your text is on the clipboard. Paste it with ⌘V where your cursor is: in a chat, an email, an editor or Terminal.

There are two ways to use the shortcut:

- **Tap** ⌃⌥⌘D: Band·je listens until you press Return, or ⌃⌥⌘D again. The Return itself is not sent to the app.
- **Hold** ⌃⌥⌘D: Band·je listens while you hold the keys and puts the text on the clipboard when you let go.

Press Esc to cancel. The menu bar icon turns orange while Band·je listens, with the time next to it. One dictation can last up to five minutes; in the last 30 seconds the time blinks.

### Pasting
After dictating, the text is on the clipboard and ⌘V shows next to the cassette for a moment. Press ⌘V to paste it where your cursor is. The text stays on the clipboard until you copy something else, so you can also paste it later or in more places.

Nothing you dictate is saved.

## Summaries {#summaries}
Band·je can summarize a conversation in a form you choose, with Apple Intelligence on your Mac.

Summaries need macOS 26 or later with Apple Intelligence turned on. Without it, the **Summarize** menu doesn't appear and Band·je works as usual.

1. Choose **Summarize** in the menu.
2. Under **Pick a Template**, choose one. Band·je summarizes the current recording. To summarize another one, first pick it under **Recent Recordings**.
3. While Band·je works, purple sparkles show in the menu bar. Point at them to see the progress.
4. When it's done, a small green check mark appears on the cassette and the menu says **Summary ready**. If the Band·je window is open, it shows the recording.

You can also start in the [Band·je window](#player): choose **Summarize** next to the tabs and pick a template.

The summary is saved next to the transcript as `<name> summary <template>.md`. A summary takes from a few seconds to about a minute. Long conversations are summarized in parts.

The summary is written in the language of the conversation. Apple Intelligence summarizes in English, Dutch, German, French, Spanish, Italian, Portuguese and a few other languages, but not yet in Polish, Russian or Ukrainian.

The model on your Mac is small. It sticks to what was said, but it can miss details. Check important facts in the transcript.

Band·je comes with four templates: a meeting, a job interview, a customer interview and a generic summary. To make your own, see [Making a template](#templates).

## Making a template {#templates}
Make your own template for summaries: a text file with the headings you want.

A template is a plain text file (`.md` or `.txt`) in `~/Music/Bandje/Templates`. The file name becomes the name in the **Summarize** menu.

Quickest start: with the Band·je window open, choose **Summarize** > **New Template** in the menu bar. Band·je makes a new template with two headings and opens it; change it, save it and give it a name of its own in the Finder.

### Start from a copy
The easiest way is to copy an example and change it:

1. Choose **Summarize** > **Open Templates Folder**.
2. Select the example that is closest to what you want, such as `Meeting.md`.
3. Choose File > Duplicate (⌘D) in Finder, and rename the copy, for example `Weekly standup.md`.
4. Open the copy in TextEdit or another text app, change the headings and save.

The new template is in the **Summarize** menu right away. Change the examples themselves too, or delete them: Band·je only puts them back if you delete the whole Templates folder.

### What goes in a template
A list of headings, each with a line about what goes under it:

- `## Decisions` with the line "Each decision as a bullet. Say who decided."
- `## Action items` with the line "Who, what and when."

Tips:

- Be specific. "Salary expectation with the exact amounts" works better than "Salary".
- Keep it to about five headings. The model on your Mac is small: fewer headings give better answers.
- Write "if that was said" when something may not come up, so Band·je doesn't make it up.
- The headings stay as you write them. The text follows the language of the conversation.

## Microphone and sound {#devices}
Choose which microphone you use and where your Mac's sound goes, straight from the menu.

### Microphone
The **Microphone** menu lists every microphone. The one in use has a check mark and its name is shown under the menu item. Choosing one changes the microphone for your whole Mac, so your call app uses the same one. With the lid closed, the built-in microphone is off; Band·je marks it.

### Sound Output
The **Sound Output** menu lists every device that can play sound and sets your Mac's sound output. Band·je never changes it by itself.

Some USB microphones have a headphone jack and count as speakers too. When your AirPods disconnect, macOS may send the sound there. Choose your speakers in Sound Output to fix it.

## More settings {#settings}
Shortcuts, the recordings folder, permissions, opening at login and the language of Band·je.

Choose **Settings…** in the menu.

### General
Turn on **Open Band·je at login** and Band·je appears in the menu bar by itself after you log in. **Always in the Dock** keeps Band·je in the Dock, also without the window. You can also choose this in the welcome window the first time you open Band·je. It is off until you turn it on. When you switch it off under System Settings > General > Login Items & Extensions, Band·je shows that here. Turn **Show the Band·je window at launch** off and Band·je stays in the menu bar when it starts.

Band·je follows the language of macOS. To use another language for Band·je only, choose it here and click **Restart Band·je**. Menus, windows, new transcripts and Help switch. **Same as macOS** goes back.

### Keyboard Shortcuts
Click a field and press the new combination. It must include ⌘, ⌃ or ⌥, or be a function key. Esc cancels, **Restore Defaults** brings back ⌃⌥⌘R, ⌃⌥⌘D and ⌃⌥⌘M. ⌃⌥⌘M (**Mark This Moment**) works everywhere while recording, and otherwise in the Band·je window. When not recording, another app can use the same combination.

If another app already uses the combination, Band·je tells you and keeps the old one.

### Sound
Choose the **Microphone** and the **Sound Output**, as in Band·je's menu. It applies to all apps, also for calls.

### Transcription
**Transcribe automatically** transcribes every recording as soon as you stop. **Recognise speakers** tells several voices apart (Speaker 1, Speaker 2…); turn it off and you only get Me and Other side. Band·je recognises the language by itself.

### Storage
Turn on **Sync with iCloud** and your recordings, transcripts, summaries and templates are in iCloud Drive › Band·je, on your iPhone and your other Macs with the same Apple Account. A recording is made on your Mac first and moves to iCloud when you stop. Band·je asks whether to move your existing recordings along. Turn it off and your own folder is the recordings folder again; nothing is deleted from iCloud, and Band·je offers to copy the recordings back. Apple encrypts iCloud Drive end-to-end when Advanced Data Protection is on.

Click **Change…** and choose a folder, anywhere on your Mac or on an external drive. New recordings and transcribed files go there. Existing recordings stay where they are, and so do your templates and the speech models. **Use ~/Music/Bandje** goes back to the standard folder.

If the folder is in iCloud Drive, Dropbox or another cloud service (also Desktop and Documents when they are in iCloud), Band·je warns you: your recordings then leave your Mac through that service.

### Access
Whether Band·je may use the microphone and record the sound of your Mac, each with its own button (**Allow…** or **Open Settings…**). A green check mark means allowed; the state updates by itself when you come back from System Settings. See [Troubleshooting](#troubleshooting).

## Band·je Unlimited {#purchases}
What is free, what the two purchases unlock, and how to restore them (Band·je from the App Store).

Band·je is free. Recording is always free and never limited.

- **Transcribing** is free for your first 5 recordings. A recording counts once, when its first transcription finishes; transcribing it again is free.
- **Dictation** is free for 15 minutes of dictated audio in total. A dictation that is running when the minutes run out finishes normally. After 10 minutes Band·je says once how many free minutes are left; the menu bar menu shows it too.
- What you already have stays yours: transcripts, summaries, sharing and exports are never locked. Summaries are free on every transcript.

Two purchases, each paid once, no subscription:

- **Band·je Unlimited**: transcribing and dictation without limit.
- **Band·je Dictation**: dictation without limit.

Buy them in **Settings… › Purchases**, or choose **Buy Band·je Unlimited…** in the Band·je menu while the window is open. Once the free transcriptions are used, **Transcribe** shows Band·je Unlimited first; an automatic transcription doesn't start, and the recording says so.

If you bought Band·je before it was free, everything is unlocked without doing anything. A purchase works on every Mac, iPhone and iPad with the same Apple Account, and with Family Sharing. On another Mac, choose **Restore Purchases**. The free part counts per device. The welcome window says what is free, with **Already bought it? Restore Purchases**.

## Privacy and network {#privacy}
Your audio, transcripts and summaries never leave your Mac.

- No account, no analytics, no tracking. No server of ours.
- iCloud only if you turn on [Sync with iCloud](#settings): then your recordings are in your own iCloud Drive, as your other files are. Band·je never sees them.
- Everything is stored in your recordings folder: `~/Music/Bandje`, unless you chose another one. Delete a folder and it's gone. If you choose a folder in iCloud Drive or another cloud service, your recordings go to that service; Band·je warns you first.
- Transcription, speaker recognition and dictation run on your Mac.
- Summaries use only the Apple Intelligence model on your Mac, never Apple's Private Cloud Compute.

The speech engine by Desert Ant Labs checks its license over the network: at most once a month per speech model. It sends a random install ID, the model and engine version and the app ID. Never audio, never text. **About Band·je** shows this too.

## Memory and storage {#resources}
Band·je is light: about 60 to 70 MB of memory while it runs.

The speech models come with Band·je: about 400 MB of the app's size. Band·je never downloads anything itself.

A few seconds after starting, Band·je loads the speech model in the background, so dictation is ready right away. The very first time on a Mac this takes about 20 seconds, because macOS optimizes the model for your chip. After that it's quick.

An hour of audio takes about 55 MB. Transcribing it needs some extra memory while it runs.

## Troubleshooting {#troubleshooting}
Solutions for things that can go wrong.

### Check the permissions first
Many problems come from a missing permission. Choose **Settings…** and look under **Access**:

- **Microphone**: needed to record your voice and to dictate.
- **Sound from your Mac**: needed to record the other side. macOS doesn't let apps read this permission, so Band·je checks it itself: it plays an inaudible signal for half a second that never reaches your speakers or AirPods, and looks whether it comes in. **Allow…** makes macOS ask; after **Open Settings…** the check mark appears once you switched Band·je on.

A green check mark means allowed. Otherwise click **Open Settings…**, turn Band·je on and come back; Band·je notices by itself.

Each time Band·je starts, it checks the microphone, and the sound of your Mac if that was off, and tells you if one is missing. Don't want the message? Tick **Do not show this message again**, or turn off **Warn at launch when something is missing** under Access.

### The other side is missing from the recording
macOS didn't allow Band·je to record your Mac's audio. Band·je warns you about this at the start of a recording. Go to System Settings > Privacy & Security > Screen & System Audio Recording and turn on Band·je under System Audio Recording Only. Still not working right after? Restart Band·je.

### My own voice is missing
Check the **Microphone** menu. With the lid closed, the built-in microphone is off: choose another one. If Band·je may not use the microphone at all, turn it on in System Settings > Privacy & Security > Microphone.

### I hear nothing after taking out my AirPods
macOS sent the sound to another device, such as a USB microphone with a headphone jack. Choose your speakers in **Sound Output**.

### The transcript is gibberish
The conversation is probably in a language Band·je doesn't know. Band·je can't tell, so it writes what it thinks it heard.

### There are more speakers than there were
Phone menus, hold music and poor lines can confuse the speaker recognition. Give the labels the right names in [Name Speakers](#speakers).

### Summarize isn't in the menu
Summaries need macOS 26 or later with Apple Intelligence turned on in System Settings > Apple Intelligence & Siri. Your Mac's language and Siri's language must match.

### The shortcut doesn't work
Another app may use the same combination. Choose a different one in [Settings](#settings).

## About Band·je {#about}
Band·je is made by Neurendal B.V. in the Netherlands.

Speech and speaker recognition: Voz and Who by Desert Ant Labs, based on NVIDIA Parakeet TDT 0.6B v3 and pyannote community-1 (CC BY 4.0). Summaries: Apple Intelligence.

Choose **About Band·je** in the menu for the versions and links.
