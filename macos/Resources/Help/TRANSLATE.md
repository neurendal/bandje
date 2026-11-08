Prompt for translating Bandje Help (paste this, then the full text of en.md)

You translate the help pages of Bandje, a small macOS menu bar app that records calls, transcribes
them on the Mac, dictates, and summarizes with Apple Intelligence. Translate the Markdown file
below from English into <LANGUAGE>. Return only the translated file, nothing else.

Keep the format exactly:
- The first line stays `# ` + the book title ("Bandje Help" in <LANGUAGE>, as macOS would name it).
- Every `## Title {#anchor}` line: translate the title, keep `{#anchor}` exactly as it is.
- The line right after each `##` heading is the one-line summary; keep it one line.
- Keep `### ` subheadings, `- ` bullets, `1. ` lists, **bold**, `code`, and links like `[text](#anchor)`
  (translate the text, keep `(#anchor)`).
- Do not add URLs, emoji, headings or extra sections.
- Keep shortcuts (⌃⌥⌘R, ⌃⌥⌘D, ⌘V, Esc, Return) and paths (`~/Music/Bandje`, `.md`, `.m4a`) as they are.

Use the exact names from the app and from macOS in <LANGUAGE>:
- Bandje menu items: use the translations in the list below (from the app's Localizable.strings).
- macOS: the official <LANGUAGE> names of System Settings, Privacy & Security, Accessibility,
  Microphone, Screen & System Audio Recording, "System Audio Recording Only", Apple Intelligence & Siri.
- Speaker labels in transcripts: use the app's labels for "Me", "Other side", "Speaker 1".
- The summary file name word ("summary" in `<name> summary <template>.md`): use the app's word.

Style: short sentences, plain and concrete, no marketing tone. Address the reader the way the app
already does in that language (see the strings below): "du" in German, "vous" in French, "tú" in
Spanish, "tu" in Italian, "você" in Portuguese, "ty" in Polish, "вы" in Russian, "ви" in Ukrainian.

Menu items and labels in <LANGUAGE> (fill in from Resources/Localization/<lang>.lproj/Localizable.strings):
<PASTE THE RELEVANT LINES: menu.*, shortcuts.reset, transcript.me, transcript.otherSide,
transcript.speaker, summary.fileWord, button.save>

---
Save the result as Resources/Help/<lang>.md (de, fr, es, it, pt, pl, ru, uk), then run
`python3 -I scripts/make-help.py check` and `make app`.
