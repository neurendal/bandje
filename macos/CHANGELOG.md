# Changelog

## Unreleased

- Fix: starting dictation could freeze Band·je for up to a minute when macOS audio was slow to answer (for example while OBS was recording audio). The microphone now starts and stops in the background; the menu bar and windows keep responding.
- Fix: without permission for automatic pasting, the first dictation opened the macOS prompt or System Settings right away, in the middle of your work. Band·je no longer asks after dictating: the text is on the clipboard and a short sound says to paste it yourself (⌘V). Band·je asks at launch, or when you choose **Turn On Automatic Pasting…** in the menu or Settings.
- Every recording gets a cover: its cassette with the title and length on band.je navy, put into the .m4a right after recording, as on the iPhone. A new title or colour makes a new cover. Finder, Music and every app the audio is shared to show it; the share sheet shows it too. Older recordings get theirs in the background when the window opens.
- While a recording plays, it shows in Now Playing (Control Centre and the menu bar) with its cover and title; play, pause, ±15 s and scrubbing work from there.
- Help: Band·je comes with four example templates (the generic summary was missing from the list).
- The example summary templates (Meeting, Job interview, Customer interview, Generic summary) now come in all ten app languages, from the same data as the iPhone app, so both put the same examples in the shared Templates folder. The summary file word ("samenvatting", "summary"…) comes from that data too.
- The cassette in light mode is a shade darker with a fine edge, so it stands out on the white window.
- Fix: when the window opened, the search field had the focus (with its ring), so the space bar typed into it instead of playing.
- Fix: sharing audio or the transcript (.md) left out the text in Mail. The file was shared straight from the recordings folder (iCloud Drive), which macOS offers as an iCloud file; Band·je now shares a copy (instant on APFS), as it already did for the PDF and the web page.
- Settings › **Sound**: **Microphone** and **Sound Output**, as in the menu bar menu.
- Fix: buttons and links in Settings (such as **Open Settings…** under Access) were navy and hard to read in dark mode; only the switches are navy now.
- **Print…** (⌘P, File menu, or in Share) prints the open recording's transcript, the same pages as the PDF. The sandbox gets the print entitlement.
- Right-click a recording in the list for **Delete…**, or select it and press ⌫; Band·je asks first (Move to Trash).
- Settings: the window is titled after the tab (was "Untitled"); the selected tab, buttons and links are Band·je red, the switches navy.
- Sharing a recording, transcript or web page adds a short text (which recording and its date) and a small closing note "Recorded with Band·je", with Band·je linked to band.je; Mail gets the title as its subject.
- The App Store version asks for a review once per version, with Apple's own sheet: only from the third transcript, not in the first week, and never while Band·je is busy.
- Faster start of the window: the list appears as soon as the recordings folder is read (the first words of each transcript follow a moment later), and with iCloud on it no longer waits for iCloud's full file listing. Until then the list says **Loading Recordings…**, and **No Recordings** when there are none.
- Fix: the window could hang for a while (a spinner on the open recording) because the summary templates were read again on every redraw, waiting for iCloud each time. They are now read in the background.
- **Band●je** at the top left of the list, above the search field, as on the iPhone; no "Band·je" text in the toolbar. The app menu says **Band·je**.
- New in the window's menu bar: **Summarize** with **New Template** (a template with two headings, opened for you to change), **Open Templates Folder** and **Template Help**; and a **Help** menu with **Band·je Help** (⌘?).
- About: "Powered by Desert Ant Labs · desert-ant-core" now sits under the speech models; the bottom is only for Neurendal.
- Closing the window: **Band·je keeps running**, a shorter text with the menu bar icon, **Don't show again**, and a **Quit Band·je** button.
- Fix: the window could open while Band·je stayed a menu bar app (no Dock icon, no app menu, no ⌘Q): the Dock icon now follows the window once it is on screen, and a minimized window keeps it.
- Quitting while recording asks first (**Stop Recording and Quit** or Cancel); Band·je saves the recording, then quits. A recording being saved is waited for.
- Fix: opening a recording no longer draws the cassette large and then shrinks it.
- **The menu bar menu, reordered**: actions first, then the current recording ("Latest Recording · 6 Nov, 21:35", or its own name) with what you can do with it and **Recent Recordings**, then the devices (**Microphone**, **Sound Output**), and at the bottom **Open Band·je** ⌘O, **Settings…** ⌘, (was More Settings…), Help, About and Quit. **Name Speakers… (1 unnamed)** counts the speakers without a name. **Open Recordings Folder** moved to the File menu of the window. "I need somebody" under Help shows until you open Help once.
- **More Settings in tabs**, as in macOS Settings: General (startup, language), Shortcuts, Transcription, Storage (iCloud, folder) and Access. Rows have the label left and the control right, in a card per section. Shortcut fields are narrower. The folder choice is hidden while iCloud syncs. Access uses the welcome's words and updates by itself when Band·je becomes active again (no Check Permissions button).
- New in Transcription: **Transcribe automatically** (was only a hidden setting) and **Recognise speakers** (off: only Me and the other side, or the text without speakers).
- New example template **Generic summary** / **Algemene samenvatting** (as on the iPhone). An existing Templates folder gets it once; delete it and it stays gone.
- The welcome's **Access** also offers **iCloud** (Turn On…, with the same questions as in More Settings; a check mark when it syncs, "Not available" without iCloud Drive).
- With several summaries the newest is the first tab after Transcript (was: by template name), as on the iPhone.
- Fix: after a recording without speech, the window could keep showing a spinner instead of "No speech recognized" (a late reload cleared the transcript it had just read).
- The welcome, after a design review: the cassette with **Welcome to Bandje**; the shortcuts as keycaps with what they do; **Access** with **Allow…** per permission (Sound from your Mac: "At first recording" until macOS has asked); privacy in one line; **Start** as the default button in a darker red, with "You can allow this later." while the microphone isn't allowed; a word from the makers with a link to Neurendal. One left-aligned column in a window the size of its content.
- The record button from the iPhone and iPad at the bottom of the list: the red record mark, and while recording a red disc with the waveform. When a recording starts (from the window, the menu or the shortcut) the window shows the record screen: the tape running with the VU meter and the name on the sticker, the time, and Stop. The button or the recording's row at the top of the list brings it back.
- **The window at launch**: the first time the window opens (also at login), with a welcome in the window: what Band·je does, then **Microphone**, **Automatic Pasting** and **Sound from your Mac**, each with its own button and a check mark once allowed, **Open Band·je at login** (off), and **Start**. After an update the welcome only comes back (when the window opens) if a permission is missing. The welcome alerts are gone.
- More Settings › Startup: **Show the Band·je window at launch** (on). Off: only the cassette in the menu bar, also after an update. Closing the window says once that Band·je keeps running in the menu bar (with "Do not show this message again").
- **Open Band·je** (⌘O) is the first item in the menu.
- Older Mac recordings named like "2026-11-05_14-30" get the iPhone's name for that moment ("Opname 5 nov 14.30", in your Mac's language and region) once, at launch, so the iPhone and the Mac show the same titles. The recording time is kept.
- The menu's current recording follows the recording selected in the window, and choosing one under **Kies opname** selects it in the window.
- The window, after the design review: **Start Recording** sits at the bottom of the list (a new recording has nothing to do with the open one); while recording, the new recording is at the top with a red dot, and when it stops the window shows it. ⌘F opens the search bar right above the transcript ("3 of 7"); the magnifying glass at the top is gone. **Transcript | Summary** are tabs; **Summarize** (with the template menu, **Open Templates Folder** and **How Do I Make a Template?**) is in the Summary tab. Double-click the title to change the name and colour. No "Band·je" title bar text.
- The selected recording and tab are band.je navy instead of the system accent. Progress bars are Band·je red again; the sentence that plays is easier to see in dark mode.
- New recordings get exactly the iPhone's name (the app's language with your region: "Recording 6 Nov 14.32", not "Nov 6").
- Loading the speech model shows a % (an estimate from the last load on this Mac).
- **Cassette colour per recording** (red, orange, yellow, green, blue, purple, navy), chosen in the new **Name and Colour…** sheet (also by clicking the title on the cassette); stored in `.bandje.json` and shared with the iPhone. The Mac now keeps keys in `.bandje.json` it doesn't know, so nothing a newer iPhone writes gets lost.
- The flags set while recording on the iPhone show as small red flags above the position bar.
- Playback speeds 0.5× and 0.75× added.
- The library shows the full date in smaller type and the length in words ("5 Nov 2026, 10:30 · 54 sec", "2 min", "1 hr, 2 min"), so it no longer reads as a time span, the same as on the iPhone.
- The play button and every progress bar (position, transcribing, summarizing, the % in the list) use band.je's button colour: navy in light, near-white in dark, the same on iPhone, iPad and Mac.
- Share › **Transcript as PDF** (A4: the Band●je wordmark, the cassette and a red rule; title, header lines, then time · speaker and the text per turn; a footer with band.je and page numbers). The web page is now called **Web Page with Audio**.
- The window opens when you start Band·je yourself (Finder, Launchpad, Spotlight); at login it stays in the menu bar. A click on the Dock icon opens it too.
- The summary tab is called **Summary** (with several summaries: "Summary · template"), the same as on the iPhone. Summaries no longer embed a logo.
- Sharing shows the app icon and the title; the shared page has a favicon, one centred column and a footer with what Band·je does.
- **The Band·je window** (from the iPhone app): your recordings per day with mini cassettes, the recording with cassette, player and the transcript that follows the audio, a tab per summary, search, rename, delete, name speakers. **Open Band·je** (⌘O) in the menu; the Dock icon shows while the window is open (setting: Always in the Dock).
- **Sync with iCloud** (opt-in, default off): recordings, transcripts, summaries and templates in iCloud Drive › Band·je, shared with the iPhone app. Recording stays local and moves to iCloud when it stops; changes from other devices show up live. No CloudKit, no server.
- **Share as Web Page**: one self-contained HTML file with the player, transcript, summaries and the audio (or a compact version for email), with Band·je branding and a link to band.je. The HTML page next to every recording and the `bandje://` links are gone.
- The same recording names, `.bandje.json` and Markdown layout as the iPhone app ("Opname 6 nov 14.32"); unknown keys from the iPhone are kept in transcripts.
- The app is called **Band·je** in all texts.
- License: the source code is now GPL-3.0-only (was MIT), with an additional permission (GPL section 7) to combine it with the Desert Ant Labs SDKs and models. See LICENSE and NOTICE.
- Help in all 10 app languages (was English and Dutch; the others fell back to English). Every menu and button name in the help is the app's own text in that language; macOS names (Privacy & Security, Screen & System Audio Recording, Login Items & Extensions, the "Do not show this message again" checkbox) are Apple's own wording, taken from macOS itself. The app texts now use those exact macOS names too.
- More Settings fits on smaller screens (a 13" MacBook at 1440 × 900): when the window is taller than the screen, it gets the height that fits and scrolls.
- **Open Bandje at login**: a checkbox in the welcome window (off unless you tick it) and a switch in More Settings that follows System Settings > Login Items.
- After you turn on automatic pasting in System Settings, macOS only tells Bandje after a restart. The menu then offers **Restart Bandje for Automatic Pasting**, and More Settings shows a **Restart Bandje** button next to the permission.
- Fix: the free-space check before a recording was skipped (it asked about the new recording's folder, which doesn't exist yet), so a recording could start on a full disk. It now asks the nearest existing folder, and uses the quick free-space figure first, so starting never waits for macOS to work out purgeable space.
- Several people around one Mac (a meeting at a table) are told apart too: the microphone channel gets **Speaker 1**, **Speaker 2** instead of one **Me**. One voice on the microphone stays **Me**; speaker numbers on the other side count on after them.
- When a transcript or summary is done, a small green check mark appears on the cassette in the menu bar (instead of replacing it for five seconds) and stays until you open the menu.
- Before the first recording, a one-time notice: you may have to tell the other participants (and sometimes get consent); you are responsible for following the law.

## 1.0.0

First App Store version: recording (microphone + system audio), on-device transcription with
speaker labels in 25 languages, speaker naming, dictation, interactive recording page, summaries
with Apple Intelligence (macOS 26), help in English and Dutch, app in 10 languages.
