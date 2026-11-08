# Band·je-Hilfe
Band·je nimmt Gespräche auf deinem Mac auf und macht Text daraus. Du findest es in der Menüleiste: die kleine Kassette oben rechts. Alles passiert auf deinem Mac.

## Ein Gespräch aufnehmen {#record}
Drücke ⌃⌥⌘R zum Starten und noch einmal ⌃⌥⌘R zum Stoppen.

Band·je nimmt zwei Dinge gleichzeitig auf: dein Mikrofon und allen Ton, den dein Mac abspielt. Das klappt mit jeder Telefonie-App, etwa FaceTime, Zoom, Teams, Meet oder einem Telefonat über deinen Mac. Band·je nimmt deinen Bildschirm nicht auf.

- Während der Aufnahme wird die Kassette in der Menüleiste rot, ihre Spulen drehen sich und daneben läuft die Zeit in Rot.
- Dein Mac geht nicht in den Ruhezustand, solange Band·je aufnimmt.
- Beim ersten Mal fragt macOS, ob der Ton deines Mac aufgenommen werden darf. Erlaube es, sonst hört Band·je nur dein Mikrofon.
- Bleibt dein Mikrofon sechs Sekunden lang stumm oder wird der Deckel geschlossen, während das eingebaute Mikrofon verwendet wird, warnt Band·je dich und bietet an, zu einem anderen Mikrofon zu wechseln.

Sag den anderen, dass du aufnimmst. In manchen Ländern und bei geschäftlicher Nutzung schreibt das Gesetz es vor, und manchmal brauchst du auch ihre Zustimmung. Du bist selbst dafür verantwortlich, das für dich geltende Recht einzuhalten. Band·je erinnert dich einmal daran, vor deiner ersten Aufnahme.

### Wo deine Aufnahmen landen
Jede Aufnahme bekommt einen eigenen Ordner in `~/Music/Bandje` (oder in dem Ordner, den du in den [weiteren Einstellungen](#settings) gewählt hast, oder in iCloud Drive › Band·je, wenn du [über iCloud synchronisierst](#settings)), benannt nach Tag und Uhrzeit, etwa `Aufnahme 6 Nov 14.32`. Dein iPhone benennt seine Aufnahmen genauso. Im Ordner liegen:

- der Ton (`.m4a`): du auf dem linken Kanal, die anderen auf dem rechten
- das Transkript (`.md`), lesbar in jeder Text- oder Markdown-App
- die Rohdaten (`.json`) mit der Zeit jedes Worts
- Zusammenfassungen als `.md`-Dateien

Öffne eine Aufnahme im [Band·je-Fenster](#player). Wähle im Menü **Aufnahmeordner öffnen**, um die Dateien zu sehen. Wird Band·je oder dein Mac während einer Aufnahme unerwartet beendet, bietet Band·je beim nächsten Start an, sie zu sichern.

## Transkripte {#transcripts}
Nach der Aufnahme schreibt Band·je auf, was gesagt wurde und wer es gesagt hat.

Das Menü zeigt den Fortschritt. Während Band·je transkribiert, kannst du schon eine neue Aufnahme starten. Ist das Transkript fertig, erscheint ein kleines grünes Häkchen auf der Kassette in der Menüleiste, und im Menü steht **Transkript fertig**: Klicke darauf, um die Aufnahme im Band·je-Fenster zu öffnen. Das Häkchen verschwindet, sobald du das Menü geöffnet hast.

- Was du sagst, ist mit **Ich** beschriftet. Was die anderen sagen, mit **Gegenseite**.
- Sprechen mehrere Personen auf der Gegenseite, unterscheidet Band·je sie: **Sprecher 1**, **Sprecher 2** und so weiter. Gib ihnen Namen mit [Sprecher benennen](#speakers).
- Dasselbe gilt für mehrere Personen an deinem Mac, etwa bei einem Meeting an einem Tisch: Statt **Ich** heißen sie dann **Sprecher 1**, **Sprecher 2** und so weiter.
- Band·je versteht 25 Sprachen, darunter Englisch, Niederländisch, Deutsch, Französisch, Spanisch, Italienisch, Portugiesisch, Polnisch, Russisch und Ukrainisch. Du musst die Sprache nicht auswählen.

Das beste Ergebnis bekommst du mit Kopfhörern. Ohne sie nimmt dein Mikrofon auch die Gegenseite aus deinen Lautsprechern auf. Band·je filtert das meiste davon heraus, aber nicht alles.

### Eine andere Datei transkribieren
Wähle **Datei transkribieren …**, um eine beliebige Audiodatei zu transkribieren, etwa eine Sprachmemo von deinem iPhone. Band·je kopiert den Ton in einen eigenen Ordner in deinem Aufnahmeordner und legt das Transkript daneben. Das Original bleibt, wo es war.

## Sprecher benennen {#speakers}
Gib den Sprechern in einem Transkript ihre echten Namen.

Öffne die Aufnahme im [Band·je-Fenster](#player) und wähle unter **Mehr** **Sprecher benennen …**, oder wähle im Menü **Sprecher benennen …**: Es öffnet die aktuelle Aufnahme. Für eine ältere Aufnahme im Menü wählst du zuerst **Letzte Aufnahmen**.

Zu jedem Sprecher siehst du sein längstes Zitat. Klicke auf die Wiedergabetaste, um diese Stelle zu hören, gib einen Namen ein und klicke auf **Sichern**. Band·je aktualisiert das Transkript und jede spätere Zusammenfassung. Lass ein Feld leer, um die Beschriftung zu behalten.

Bei einer Telefonleitung mit Sprachmenü oder Warteschleifenmusik hört Band·je manchmal mehr Sprecher, als es gab. Gib zwei Beschriftungen denselben Namen oder lass die überzählige, wie sie ist.

## Das Band·je-Fenster {#player}
Alle deine Aufnahmen in einem Fenster: anhören, mitlesen, suchen, Sprecher benennen, zusammenfassen und teilen.

Wähle im Menü **Band·je öffnen** (⌘O). Das Fenster öffnet sich auch, wenn du Band·je selbst startest, etwa über Launchpad oder Spotlight. **In Band·je öffnen** öffnet die aktuelle Aufnahme. Solange das Fenster offen ist, ist Band·je im Dock und in ⌘Tab; schließt du es, ist Band·je wieder nur in der Menüleiste. Schalte **Immer im Dock** in den [weiteren Einstellungen](#settings) ein, um das Symbol zu behalten. Beim ersten Mal öffnet sich das Fenster immer, mit den Berechtigungen, jede mit eigener Taste. Schließt du das Fenster, bleibt Band·je in der Menüleiste; beende Band·je über dieses Menü.

- Links: deine Aufnahmen nach Tag, mit Uhrzeit, Dauer und den ersten Wörtern des Transkripts. Die Suche findet Titel und Wörter in Transkripten. Unten ist **Aufnahme starten**; während der Aufnahme steht die neue Aufnahme oben mit einem roten Punkt, und nach dem Stoppen öffnet das Fenster sie.
- Rechts: die Aufnahme mit der Kassette, der Positionsleiste und der Wiedergabetaste (Leertaste). Klicke auf einen Satz, um ab dort zuzuhören; während der Wiedergabe wird der Satz hervorgehoben, den du gerade hörst, und das Transkript läuft mit. **Im Transkript suchen** (⌘F) findet Wörter.
- Neben **Transkript** ist der Tab **Zusammenfassung**. Gibt es noch keine Zusammenfassung, steht dort **Zusammenfassen**: Wähle eine Vorlage, siehe [Zusammenfassungen](#summaries). Jede Zusammenfassung bekommt einen eigenen Tab; **Weitere Zusammenfassung** erstellt eine weitere.
- Noch kein Transkript (etwa bei einer Aufnahme von deinem iPhone)? Klicke auf **Transkribieren**.
- **Teilen**: **Audio …**, **Transkript (.md) …**, **Transkript als PDF …** oder **Webseite mit Audio …**: eine Datei mit Player, Transkript, Zusammenfassungen und Ton, die in jedem Browser funktioniert, auch offline. **Webseite mit Audio, kompakt (für E-Mail) …** macht den Ton kleiner. Die Seite hat einen Link zu band.je und sonst nichts.
- Auf Papier: **Drucken …** (⌘P oder unter **Teilen**) druckt das Transkript, genau wie das PDF.
- **Mehr**: **Name und Farbe …** (oder klicke auf den Titel auf der Kassette): Name und Farbe der Kassette, **Sprecher benennen …**, **Im Finder zeigen**, **Löschen …** (in den Papierkorb).
- Eine Aufnahme kannst du auch in der Liste löschen: klicke sie mit der rechten Maustaste an und wähle **Löschen …**, oder wähle sie aus und drücke ⌫. Band·je fragt vorher nach.

## Diktat {#dictation}
Drücke ⌃⌥⌘D, sprich, und der Text erscheint dort, wo dein Cursor steht: in einem Chat, einer E-Mail, einem Editor oder im Terminal.

Du kannst den Kurzbefehl auf zwei Arten nutzen:

- **Tippen** auf ⌃⌥⌘D: Band·je hört zu, bis du Return oder noch einmal ⌃⌥⌘D drückst. Das Return selbst geht nicht an die App.
- **Halten** von ⌃⌥⌘D: Band·je hört zu, solange du die Tasten hältst, und fügt ein, wenn du loslässt.

Mit Esc brichst du ab. Das Symbol in der Menüleiste wird orange, solange Band·je zuhört, mit der Zeit daneben. Ein Diktat kann bis zu fünf Minuten dauern; in den letzten 30 Sekunden blinkt die Zeit.

### Einfügen
Der Text liegt immer in der Zwischenablage. Damit Band·je ihn für dich einfügen kann, braucht es die Erlaubnis, einen Tastendruck (⌘V) zu senden: Wähle im Menü **Automatisch einfügen …** oder geh zu Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen und aktiviere Band·je. Ohne diese Erlaubnis fügst du selbst mit ⌘V ein.

macOS teilt einem laufenden Band·je diese Erlaubnis erst nach einem Neustart mit. Gerade aktiviert? Wähle im Menü **Band·je neu starten für automatisches Einfügen** oder **Band·je neu starten** in den [weiteren Einstellungen](#settings).

Hörst du statt des Einfügens einen kurzen Ton, hat ein Passwortfeld oder eine andere App die sichere Eingabe eingeschaltet (die sichere Tastatureingabe im Terminal, ein Passwortmanager). macOS blockiert dann das Einfügen; der Text liegt in der Zwischenablage, drücke also selbst ⌘V.

Nichts, was du diktierst, wird gespeichert.

## Zusammenfassungen {#summaries}
Band·je kann ein Gespräch in einer Form deiner Wahl zusammenfassen, mit Apple Intelligence auf deinem Mac.

Zusammenfassungen brauchen macOS 26 oder neuer mit eingeschaltetem Apple Intelligence. Ohne das erscheint das Menü **Zusammenfassen** nicht, und Band·je funktioniert wie gewohnt.

1. Wähle im Menü **Zusammenfassen**.
2. Wähle unter **Vorlage wählen** eine Vorlage. Band·je fasst die aktuelle Aufnahme zusammen. Für eine andere wählst du sie zuerst unter **Letzte Aufnahmen**.
3. Während Band·je arbeitet, funkeln lila Sterne in der Menüleiste. Zeig darauf, um den Fortschritt zu sehen.
4. Ist es fertig, erscheint ein kleines grünes Häkchen auf der Kassette, und das Menü zeigt **Zusammenfassung fertig**. Ist das Band·je-Fenster offen, zeigt es die Aufnahme.

Du kannst auch im [Band·je-Fenster](#player) beginnen: Wähle neben den Tabs **Zusammenfassen** und dann eine Vorlage.

Die Zusammenfassung wird neben dem Transkript als `<Name> Zusammenfassung <Vorlage>.md` gesichert. Eine Zusammenfassung dauert ein paar Sekunden bis etwa eine Minute. Lange Gespräche werden in Teilen zusammengefasst.

Die Zusammenfassung wird in der Sprache des Gesprächs geschrieben. Apple Intelligence fasst auf Englisch, Niederländisch, Deutsch, Französisch, Spanisch, Italienisch, Portugiesisch und in einigen anderen Sprachen zusammen, aber noch nicht auf Polnisch, Russisch oder Ukrainisch.

Das Modell auf deinem Mac ist klein. Es hält sich an das Gesagte, kann aber Details übersehen. Prüfe wichtige Fakten im Transkript.

Band·je bringt vier Vorlagen mit: ein Meeting, ein Vorstellungsgespräch, ein Kundeninterview und eine allgemeine Zusammenfassung. Eigene Vorlagen erstellen: siehe [Eine Vorlage erstellen](#templates).

## Eine Vorlage erstellen {#templates}
Erstelle deine eigene Vorlage für Zusammenfassungen: eine Textdatei mit den Überschriften, die du möchtest.

Eine Vorlage ist eine einfache Textdatei (`.md` oder `.txt`) in `~/Music/Bandje/Templates`. Der Dateiname wird zum Namen im Menü **Zusammenfassen**.

Am schnellsten: Ist das Band·je-Fenster geöffnet, wähle in der Menüleiste **Zusammenfassen** > **Neue Vorlage**. Band·je erstellt eine neue Vorlage mit zwei Überschriften und öffnet sie; passe sie an, sichere sie und gib ihr im Finder einen eigenen Namen.

### Mit einer Kopie beginnen
Am einfachsten kopierst du ein Beispiel und änderst es:

1. Wähle **Zusammenfassen** > **Vorlagenordner öffnen**.
2. Wähle das Beispiel aus, das deinem Wunsch am nächsten kommt, etwa `Meeting.md`.
3. Wähle im Finder Ablage > Duplizieren (⌘D) und benenne die Kopie um, zum Beispiel in `Wochenrunde.md`.
4. Öffne die Kopie in TextEdit oder einer anderen Text-App, ändere die Überschriften und sichere.

Die neue Vorlage steht sofort im Menü **Zusammenfassen**. Du kannst auch die Beispiele selbst ändern oder löschen: Band·je stellt sie nur wieder her, wenn du den ganzen Ordner Templates löschst.

### Was in eine Vorlage gehört
Eine Liste von Überschriften, jede mit einer Zeile dazu, was darunter gehört:

- `## Entscheidungen` mit der Zeile „Jede Entscheidung als Aufzählungspunkt. Nenne, wer entschieden hat.“
- `## Aufgaben` mit der Zeile „Wer, was und bis wann.“

Tipps:

- Sei konkret. „Gehaltsvorstellung mit den genauen Beträgen“ funktioniert besser als „Gehalt“.
- Bleib bei etwa fünf Überschriften. Das Modell auf deinem Mac ist klein: Weniger Überschriften ergeben bessere Antworten.
- Schreib „falls das gesagt wurde“, wenn etwas vielleicht nicht vorkommt, damit Band·je es nicht erfindet.
- Die Überschriften bleiben so, wie du sie schreibst. Der Text folgt der Sprache des Gesprächs.

## Mikrofon und Ton {#devices}
Wähle direkt im Menü, welches Mikrofon du verwendest und wohin der Ton deines Mac geht.

### Mikrofon
Das Menü **Mikrofon** listet alle Mikrofone. Das verwendete hat ein Häkchen, und sein Name steht unter dem Menüpunkt. Wählst du eines, ändert sich das Mikrofon für deinen ganzen Mac, sodass deine Telefonie-App dasselbe verwendet. Bei geschlossenem Deckel ist das eingebaute Mikrofon aus; Band·je markiert das.

### Tonausgabe
Das Menü **Tonausgabe** listet alle Geräte, die Ton abspielen können, und legt die Tonausgabe deines Mac fest. Band·je ändert sie nie von selbst.

Manche USB-Mikrofone haben eine Kopfhörerbuchse und zählen auch als Lautsprecher. Wenn deine AirPods die Verbindung trennen, schickt macOS den Ton vielleicht dorthin. Wähle dann unter Tonausgabe deine Lautsprecher.

## Einstellungen {#settings}
Tastenkürzel, der Aufnahmeordner, Berechtigungen, Öffnen bei der Anmeldung und die Sprache von Band·je.

Wähle im Menü **Einstellungen …**.

### Allgemein
Schalte **Band·je bei der Anmeldung öffnen** ein, und Band·je erscheint nach der Anmeldung von selbst in der Menüleiste. **Immer im Dock** hält Band·je im Dock, auch ohne Fenster. Du kannst das auch im Willkommensfenster wählen, wenn du Band·je zum ersten Mal öffnest. Es ist aus, bis du es einschaltest. Schaltest du es unter Systemeinstellungen > Allgemein > Anmeldeobjekte & Erweiterungen aus, zeigt Band·je das hier an. Ist **Band·je-Fenster beim Start zeigen** aus, bleibt Band·je beim Start in der Menüleiste.

Band·je folgt der Sprache von macOS. Um nur für Band·je eine andere Sprache zu verwenden, wähle sie hier und klicke auf **Band·je neu starten**. Menüs, Fenster, neue Transkripte und die Hilfe wechseln. **Wie macOS** stellt es zurück.

### Tastenkürzel
Klicke auf ein Feld und drücke die neue Kombination. Sie muss ⌘, ⌃ oder ⌥ enthalten oder eine Funktionstaste sein. Esc bricht ab, **Standardwerte** stellt ⌃⌥⌘R und ⌃⌥⌘D wieder her.

Verwendet eine andere App die Kombination schon, sagt Band·je dir das und behält die alte.

### Ton
Wähle **Mikrofon** und **Tonausgabe**, wie im Menü von Band·je. Das gilt für alle Apps, auch zum Telefonieren.

### Transkription
**Automatisch transkribieren** transkribiert jede Aufnahme, sobald du stoppst. **Sprecher erkennen** unterscheidet mehrere Stimmen (Sprecher 1, Sprecher 2…); ist es aus, bekommst du nur Ich und Gegenseite. Die Sprache erkennt Band·je selbst.

### Speicher
Schalte **Über iCloud synchronisieren** ein, und deine Aufnahmen, Transkripte, Zusammenfassungen und Vorlagen liegen in iCloud Drive › Band·je, auf deinem iPhone und deinen anderen Macs mit demselben Apple Account. Eine Aufnahme entsteht zuerst auf deinem Mac und wandert in iCloud, wenn du stoppst. Band·je fragt, ob deine vorhandenen Aufnahmen mitwandern sollen. Schaltest du es aus, ist dein eigener Ordner wieder der Aufnahmeordner; in iCloud wird nichts gelöscht, und Band·je bietet an, die Aufnahmen zurückzukopieren. Apple verschlüsselt iCloud Drive Ende-zu-Ende, wenn der erweiterte Datenschutz aktiviert ist.

Klicke auf **Ändern …** und wähle einen Ordner, irgendwo auf deinem Mac oder auf einem externen Laufwerk. Neue Aufnahmen und transkribierte Dateien landen dort. Bestehende Aufnahmen bleiben, wo sie sind, ebenso deine Vorlagen und die Sprachmodelle. **~/Music/Bandje verwenden** kehrt zum Standardordner zurück.

Liegt der Ordner in iCloud Drive, Dropbox oder einem anderen Clouddienst (auch Schreibtisch und Dokumente, wenn sie in iCloud liegen), warnt Band·je dich: Deine Aufnahmen verlassen deinen Mac dann über diesen Dienst.

### Zugriff
Ob Band·je das Mikrofon nutzen, für dich einfügen und den Ton deines Mac aufnehmen darf, mit je einer Taste (**Erlauben …** oder **Einstellungen öffnen …**). Ein grünes Häkchen heißt erlaubt; der Stand aktualisiert sich von selbst, wenn du aus den Systemeinstellungen zurückkommst. Siehe [Problemlösung](#troubleshooting).

## Datenschutz und Netzwerk {#privacy}
Deine Aufnahmen, Transkripte und Zusammenfassungen verlassen deinen Mac nie.

- Kein Konto, keine Analysen, kein Tracking. Kein Server von uns.
- iCloud nur, wenn du [Über iCloud synchronisieren](#settings) einschaltest: Dann liegen deine Aufnahmen in deinem eigenen iCloud Drive, wie deine anderen Dateien. Band·je sieht sie nie.
- Alles wird in deinem Aufnahmeordner gespeichert: `~/Music/Bandje`, außer du hast einen anderen gewählt. Löschst du einen Ordner, ist er weg. Wählst du einen Ordner in iCloud Drive oder einem anderen Clouddienst, gehen deine Aufnahmen an diesen Dienst; Band·je warnt dich vorher.
- Transkription, Sprechererkennung und Diktat laufen auf deinem Mac.
- Zusammenfassungen nutzen nur das Apple Intelligence-Modell auf deinem Mac, nie Apples Private Cloud Compute.

Die Sprach-Engine von Desert Ant Labs prüft ihre Lizenz über das Netzwerk: höchstens einmal im Monat pro Sprachmodell. Sie sendet eine zufällige Installations-ID, die Modell- und Engine-Version und die App-ID. Nie Ton, nie Text. **Über Band·je** zeigt das auch.

## Arbeitsspeicher und Speicherplatz {#resources}
Band·je ist sparsam: etwa 60 bis 70 MB Arbeitsspeicher, solange es läuft.

Die Sprachmodelle sind in Band·je enthalten: etwa 400 MB der App-Größe. Band·je lädt selbst nie etwas herunter.

Ein paar Sekunden nach dem Start lädt Band·je das Sprachmodell im Hintergrund, damit das Diktat sofort bereit ist. Beim allerersten Mal auf einem Mac dauert das etwa 20 Sekunden, weil macOS das Modell für deinen Chip optimiert. Danach geht es schnell.

Eine Stunde Ton belegt etwa 55 MB. Das Transkribieren braucht währenddessen etwas zusätzlichen Arbeitsspeicher.

## Problemlösung {#troubleshooting}
Lösungen für Dinge, die schiefgehen können.

### Prüfe zuerst die Berechtigungen
Viele Probleme kommen von einer fehlenden Berechtigung. Wähle **Einstellungen …** und sieh unter **Zugriff** nach:

- **Mikrofon**: nötig, um deine Stimme aufzunehmen und zu diktieren.
- **Ton von deinem Mac**: nötig, um die Gegenseite aufzunehmen. macOS lässt Apps diese Berechtigung nicht auslesen, deshalb zeigt Band·je, was bei der letzten Aufnahme passiert ist: Ton kam an, oder es war still. Still ist normal, wenn nichts abgespielt wurde.
- **Automatisches Einfügen**: nötig, um diktierten Text für dich einzufügen.

Ein grünes Häkchen heißt erlaubt. Sonst: Klicke auf **Einstellungen öffnen …**, schalte Band·je ein und komm zurück; Band·je merkt es von selbst.

Bei jedem Start prüft Band·je das Mikrofon und das automatische Einfügen und sagt dir, wenn etwas fehlt. Brauchst du das automatische Einfügen nicht? Markiere **Diese Meldung nicht mehr anzeigen** oder schalte unter Zugriff **Beim Start warnen, wenn etwas fehlt** aus.

### Die Gegenseite fehlt in der Aufnahme
macOS hat Band·je nicht erlaubt, den Ton deines Mac aufzunehmen. Geh zu Systemeinstellungen > Datenschutz & Sicherheit > Aufnahme von Bildschirm & Systemaudio und aktiviere Band·je unter „Nur Aufnahme von Systemaudio“.

### Meine eigene Stimme fehlt
Sieh im Menü **Mikrofon** nach. Bei geschlossenem Deckel ist das eingebaute Mikrofon aus: Wähle ein anderes. Darf Band·je das Mikrofon gar nicht verwenden, aktiviere es unter Systemeinstellungen > Datenschutz & Sicherheit > Mikrofon.

### Ich höre nichts, seit ich meine AirPods herausgenommen habe
macOS hat den Ton an ein anderes Gerät geschickt, etwa ein USB-Mikrofon mit Kopfhörerbuchse. Wähle deine Lautsprecher unter **Tonausgabe**.

### Das Transkript ist Kauderwelsch
Das Gespräch ist wahrscheinlich in einer Sprache, die Band·je nicht kennt. Band·je kann das nicht erkennen und schreibt deshalb auf, was es zu hören glaubt.

### Es gibt mehr Sprecher, als es gab
Sprachmenüs, Warteschleifenmusik und schlechte Verbindungen können die Sprechererkennung durcheinanderbringen. Gib den Beschriftungen unter [Sprecher benennen](#speakers) die richtigen Namen.

### Zusammenfassen fehlt im Menü
Zusammenfassungen brauchen macOS 26 oder neuer mit eingeschaltetem Apple Intelligence unter Systemeinstellungen > Apple Intelligence & Siri. Die Sprache deines Mac und die Sprache von Siri müssen übereinstimmen.

### Der Kurzbefehl funktioniert nicht
Vielleicht verwendet eine andere App dieselbe Kombination. Wähle in den [weiteren Einstellungen](#settings) eine andere.

## Über Band·je {#about}
Band·je wird von Neurendal B.V. in den Niederlanden entwickelt.

Sprach- und Sprechererkennung: Voz und Who von Desert Ant Labs, basierend auf NVIDIA Parakeet TDT 0.6B v3 und pyannote community-1 (CC BY 4.0). Zusammenfassungen: Apple Intelligence.

Wähle im Menü **Über Band·je** für die Versionen und Links.
