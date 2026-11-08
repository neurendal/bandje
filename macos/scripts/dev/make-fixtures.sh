#!/usr/bin/env bash
# Generates Dutch TTS fixtures (48 kHz mono 16-bit WAV) with the expected text next to them.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=tests/fixtures
mkdir -p "$OUT"
TMP=$(mktemp -d)

make_one() { # name voice text
  local name=$1 voice=$2 text=$3
  if [ -f "$OUT/$name.wav" ]; then echo "$OUT/$name.wav exists"; return; fi
  say -v "$voice" -o "$TMP/$name.aiff" "$text"
  afconvert -f WAVE -d LEI16@48000 -c 1 "$TMP/$name.aiff" "$OUT/$name.wav"
  printf '%s\n' "$text" > "$OUT/$name.txt"
  echo "$OUT/$name.wav ($voice)"
}

make_one nl_xander Xander "Goedemiddag, met Jan. Ik bel even over de afspraak van volgende week dinsdag. Kunnen we die verplaatsen naar woensdagochtend om tien uur?"
make_one nl_ellen  Ellen  "Hallo Jan, ja dat is goed. Woensdag om tien uur past mij prima. Ik zet het meteen in mijn agenda en stuur je straks een bevestiging."
# English check (M5): two voices, a short exchange.
make_one en_samantha Samantha "Good afternoon, this is Sarah. I am calling about the meeting next Tuesday. Could we move it to Wednesday morning at ten?"
make_one en_daniel   Daniel   "Hello Sarah, yes that is fine. Wednesday at ten works for me. I will put it in my calendar and send you a confirmation later today."
# Other UI languages (M7): does Voz recognize them without being told the language?
make_one de_anna     Anna     "Guten Tag, hier ist Jan. Ich rufe wegen des Termins nächste Woche an. Können wir ihn auf Mittwochmorgen um zehn Uhr verschieben?"
make_one fr_thomas   Thomas   "Bonjour, c'est Jean. J'appelle au sujet du rendez-vous de la semaine prochaine. Pouvons-nous le déplacer à mercredi matin à dix heures ?"
make_one es_paulina  Paulina  "Buenas tardes, soy Juan. Llamo por la cita de la próxima semana. ¿Podemos cambiarla al miércoles por la mañana a las diez?"
make_one it_alice    Alice    "Buongiorno, sono Gianni. Chiamo per l'appuntamento della prossima settimana. Possiamo spostarlo a mercoledì mattina alle dieci?"
make_one pt_luciana  Luciana  "Boa tarde, aqui é o João. Estou ligando sobre a reunião da semana que vem. Podemos mudar para quarta-feira de manhã às dez?"
make_one pt_joana    Joana    "Boa tarde, fala o João. Estou a ligar por causa da reunião da próxima semana. Podemos mudá-la para quarta-feira de manhã às dez?"
make_one pl_zosia    Zosia    "Dzień dobry, tu Jan. Dzwonię w sprawie spotkania w przyszłym tygodniu. Czy możemy je przełożyć na środę rano na dziesiątą?"
make_one ru_milena   Milena   "Добрый день, это Иван. Я звоню по поводу встречи на следующей неделе. Можем ли мы перенести её на среду, на десять утра?"
make_one uk_lesya    Lesya    "Добрий день, це Іван. Я телефоную щодо зустрічі наступного тижня. Чи можемо ми перенести її на середу, на десяту ранку?"
rm -rf "$TMP"
