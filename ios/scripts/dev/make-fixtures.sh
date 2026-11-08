#!/usr/bin/env bash
# Generates test fixtures in build/fixtures (git-ignored; never commit audio).
# TTS speech (NL: Xander/Ellen, EN: Samantha/Daniel) as 48 kHz mono 16-bit WAV with the expected
# text next to each, two-speaker dialogues with a known timeline, an import set in several
# formats, and a corrupt file. Usage: scripts/dev/make-fixtures.sh [--long]  (--long: 10 and 60 min)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/fixtures
mkdir -p "$OUT"
TMP=$(mktemp -d)

make_one() { # name voice text
  local name=$1 voice=$2 text=$3
  if [ -f "$OUT/$name.wav" ]; then return; fi
  say -v "$voice" -o "$TMP/$name.aiff" "$text"
  afconvert -f WAVE -d LEI16@48000 -c 1 "$TMP/$name.aiff" "$OUT/$name.wav"
  printf '%s\n' "$text" > "$OUT/$name.txt"
  echo "$OUT/$name.wav ($voice)"
}

make_one nl_xander_1 Xander "Goedemiddag, met Jan. Ik bel even over de afspraak van volgende week dinsdag. Kunnen we die verplaatsen naar woensdagochtend om tien uur?"
make_one nl_ellen_1  Ellen  "Hallo Jan, ja dat is goed. Woensdag om tien uur past mij prima. Ik zet het meteen in mijn agenda en stuur je straks een bevestiging."
make_one nl_xander_2 Xander "Fijn, dank je wel. Zullen we dan ook meteen de begroting voor het nieuwe jaar doornemen? Ik heb de cijfers van het derde kwartaal net binnen."
make_one nl_ellen_2  Ellen  "Dat lijkt me een goed idee. Neem de cijfers maar mee, dan kijken we samen waar we kunnen besparen. Tot woensdag!"
make_one en_samantha_1 Samantha "Good afternoon, this is Sarah. I am calling about the meeting next Tuesday. Could we move it to Wednesday morning at ten?"
make_one en_daniel_1   Daniel   "Hello Sarah, yes that is fine. Wednesday at ten works for me. I will put it in my calendar and send you a confirmation later today."
make_one en_samantha_2 Samantha "Great, thank you. Shall we also go through the budget for next year? I just received the numbers for the third quarter."
make_one en_daniel_2   Daniel   "That sounds like a good plan. Bring the numbers along and we will look at where we can save together. See you on Wednesday."

python3 scripts/dev/concat_wav.py "$OUT/nl_dialogue.wav" 0.6 A="$OUT/nl_xander_1.wav" B="$OUT/nl_ellen_1.wav" A="$OUT/nl_xander_2.wav" B="$OUT/nl_ellen_2.wav"
python3 scripts/dev/concat_wav.py "$OUT/en_dialogue.wav" 0.6 A="$OUT/en_samantha_1.wav" B="$OUT/en_daniel_1.wav" A="$OUT/en_samantha_2.wav" B="$OUT/en_daniel_2.wav"
# ~60 s source for the fake microphone (M1).
LOOP_TO=60 python3 scripts/dev/concat_wav.py "$OUT/mic_60s.wav" 0.6 A="$OUT/nl_xander_1.wav" B="$OUT/nl_ellen_1.wav" A="$OUT/nl_xander_2.wav" B="$OUT/nl_ellen_2.wav"

# Import set (M4). afconvert cannot write mp3 or mp4: mp4/mov via an AVFoundation script (video
# track + audio), mp3 via lame or ffmpeg when one of them is installed (skipped otherwise).
afconvert -f m4af -d aac -b 64000 "$OUT/nl_dialogue.wav" "$OUT/import_nl.m4a"
afconvert -f AIFF -d BEI16 "$OUT/en_dialogue.wav" "$OUT/import_en.aiff"
afconvert -f caff -d LEI16 "$OUT/nl_dialogue.wav" "$OUT/import_nl.caf"
cp "$OUT/en_dialogue.wav" "$OUT/import_en.wav"
if [ ! -f "$OUT/import_en.mp4" ]; then swift scripts/dev/make-mp4.swift "$OUT/en_dialogue.wav" "$OUT/import_en.mp4"; fi
if [ ! -f "$OUT/import_nl.mov" ]; then swift scripts/dev/make-mp4.swift "$OUT/nl_dialogue.wav" "$OUT/import_nl.mov"; fi
if [ ! -f "$OUT/import_nl.mp3" ]; then
  if command -v lame >/dev/null; then lame --quiet -b 64 "$OUT/nl_dialogue.wav" "$OUT/import_nl.mp3"
  elif command -v ffmpeg >/dev/null; then ffmpeg -loglevel error -y -i "$OUT/nl_dialogue.wav" -b:a 64k "$OUT/import_nl.mp3"
  else echo "no lame or ffmpeg: import_nl.mp3 skipped"; fi
fi
# Not audio at all, with an audio extension: must give a clear message, not a crash.
if [ ! -f "$OUT/corrupt.m4a" ]; then head -c 65536 /dev/urandom > "$OUT/corrupt.m4a"; fi
printf 'This is not audio.\n' > "$OUT/notes.mp3"

if [ "${1:-}" = "--long" ]; then
  LOOP_TO=600  python3 scripts/dev/concat_wav.py "$OUT/nl_10min.wav" 0.6 A="$OUT/nl_xander_1.wav" B="$OUT/nl_ellen_1.wav" A="$OUT/nl_xander_2.wav" B="$OUT/nl_ellen_2.wav"
  LOOP_TO=3600 python3 scripts/dev/concat_wav.py "$OUT/nl_60min.wav" 0.6 A="$OUT/nl_xander_1.wav" B="$OUT/nl_ellen_1.wav" A="$OUT/nl_xander_2.wav" B="$OUT/nl_ellen_2.wav"
fi
rm -rf "$TMP"
ls -la "$OUT"
