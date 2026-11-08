# Band·je Help
Band·je neemt gesprekken op je Mac op en maakt er tekst van. Je vindt het in de menubalk: het cassettebandje rechtsboven. Alles gebeurt op je Mac.

## Een gesprek opnemen {#record}
Druk op ⌃⌥⌘R om te beginnen, en nog een keer op ⌃⌥⌘R om te stoppen.

Band·je neemt twee dingen tegelijk op: je microfoon en al het geluid dat je Mac afspeelt. Dat werkt met elke bel-app, zoals FaceTime, Zoom, Teams, Meet of een telefoongesprek via je Mac. Band·je neemt je scherm niet op.

- Tijdens de opname wordt het bandje in de menubalk rood, draaien de spoelen en loopt de tijd ernaast in rood.
- Je Mac gaat niet slapen zolang Band·je opneemt.
- De eerste keer vraagt macOS of Band·je het geluid van je Mac mag opnemen. Sta dat toe, anders hoort Band·je alleen je microfoon.
- Blijft je microfoon zes seconden stil, of is de klep dicht terwijl de ingebouwde microfoon aan staat, dan waarschuwt Band·je en biedt het aan een andere microfoon te kiezen.

Laat de anderen weten dat je opneemt. In sommige landen, en bij zakelijk gebruik, is dat wettelijk verplicht, en soms heb je ook hun toestemming nodig. Je bent zelf verantwoordelijk voor het naleven van de wet die voor jou geldt. Band·je herinnert je daar één keer aan, voor je eerste opname.

### Waar je opnames staan
Elke opname krijgt een eigen map in `~/Music/Bandje` (of de map die je koos bij [Instellingen](#settings), of iCloud Drive › Band·je als je [synchroniseert via iCloud](#settings)), met de dag en tijd als naam, zoals `Opname 6 nov 14.32`. Je iPhone noemt zijn opnames op dezelfde manier. In de map staan:

- de audio (`.m4a`): jij op het linkerkanaal, de anderen op het rechter
- het transcript (`.md`), leesbaar in elke tekst- of Markdown-app
- de ruwe gegevens (`.json`) met de tijd van elk woord
- samenvattingen, als `.md`-bestanden

Open een opname in het [Band·je-venster](#player). Kies **Open opnamemap** in het menu om de bestanden te zien. Stopt Band·je of je Mac onverwacht tijdens een opname, dan biedt Band·je bij de volgende start aan om de opname te bewaren.

## Transcripten {#transcripts}
Als je stopt met opnemen, schrijft Band·je op wat er gezegd is, en door wie.

In het menu zie je de voortgang. Tijdens het transcriberen kun je gewoon een nieuwe opname starten. Is het transcript klaar, dan staat er een klein groen vinkje op het cassettebandje in de menubalk, en zegt het menu **Transcript klaar**: klik erop om de opname in het Band·je-venster te openen. Het vinkje verdwijnt zodra je het menu hebt geopend.

- Wat jij zegt, krijgt het label **Ik**. Wat de anderen zeggen, krijgt het label **Andere kant**.
- Praten er meerdere mensen aan de andere kant, dan houdt Band·je ze uit elkaar: **Spreker 1**, **Spreker 2** enzovoort. Geef ze een naam met [Sprekers benoemen](#speakers).
- Dat geldt ook voor meerdere mensen rond je Mac, bij een overleg aan één tafel: in plaats van **Ik** worden dat **Spreker 1**, **Spreker 2** enzovoort.
- Band·je verstaat 25 talen, waaronder Nederlands, Engels, Duits, Frans, Spaans, Italiaans, Portugees, Pools, Russisch en Oekraïens. Je hoeft de taal niet te kiezen.

Draag tijdens een gesprek bij voorkeur een koptelefoon. Zonder koptelefoon vangt je microfoon ook de andere kant uit je speakers op. Band·je filtert het meeste daarvan weg, maar niet alles.

### Een ander bestand transcriberen
Kies **Transcribeer bestand…** om elk audiobestand te transcriberen, zoals een memo van je iPhone. Band·je kopieert de audio naar een eigen map in je opnamemap en zet het transcript ernaast. Het origineel blijft waar het stond.

## Sprekers benoemen {#speakers}
Geef de sprekers in een transcript hun echte naam.

Open de opname in het [Band·je-venster](#player) en kies **Benoem sprekers…** onder **Meer**, of kies **Benoem sprekers…** in het menu: dat opent de huidige opname. Wil je vanuit het menu met een oudere opname aan de slag, kies die dan eerst bij **Recente opnames**.

Per spreker zie je het langste citaat. Klik op de afspeelknop om dat stuk te horen, typ een naam en klik op **Bewaar**. Band·je werkt het transcript en latere samenvattingen bij. Laat een veld leeg om het label te houden.

Op een telefoonlijn met een keuzemenu of wachtmuziek hoort Band·je soms meer sprekers dan er waren. Geef twee labels dan dezelfde naam, of laat het extra label staan.

## Het Band·je-venster {#player}
Al je opnames in één venster: luisteren, meelezen, zoeken, sprekers benoemen, samenvatten en delen.

Kies **Open Band·je** in het menu (⌘O). Het venster opent ook als je Band·je zelf start, bijvoorbeeld vanuit Launchpad of Spotlight. **Open in Band·je** opent de huidige opname. Zolang het venster open is, staat Band·je in het Dock en in ⌘Tab; sluit je het, dan staat Band·je weer alleen in de menubalk. Zet **Altijd in het Dock** aan bij [Instellingen](#settings) om het icoon te houden. De eerste keer opent het venster altijd, met de toestemmingen, elk met een eigen knop. Sluit je het venster, dan blijft Band·je in de menubalk; stop Band·je via dat menu.

- Links: je opnames per dag, met de tijd, de lengte en de eerste woorden van het transcript. Zoeken vindt titels en woorden in transcripten. Onderaan staat **Start opname**; tijdens het opnemen staat de nieuwe opname bovenaan met een rode stip, en na het stoppen opent het venster hem.
- Rechts: de opname met het cassettebandje, de positiebalk en de afspeelknop (spatiebalk). Klik op een zin om vanaf daar te luisteren; tijdens het afspelen licht de zin op die je hoort en loopt het transcript mee. **Zoek in transcript** (⌘F) vindt woorden.
- Naast **Transcript** staat het tabblad **Samenvatting**. Is er nog geen samenvatting, dan staat daar **Vat samen**; kies een template, zie [Samenvatten](#summaries). Elke samenvatting krijgt een eigen tabblad; **Nog een samenvatting** maakt er nog een.
- Nog geen transcript (bijvoorbeeld een opname van je iPhone)? Klik op **Transcribeer**.
- **Deel**: **Audio…**, **Transcript (.md)…**, **Transcript als pdf…** of **Webpagina met audio…**: één bestand met de speler, het transcript, de samenvattingen en de audio, dat in elke browser werkt, ook offline. **Webpagina met audio, compact (voor mail)…** maakt de audio kleiner. De pagina heeft een link naar band.je en verder niets.
- Op papier: **Druk af…** (⌘P, of in **Deel**) drukt het transcript af, net als de pdf.
- **Meer**: **Naam en kleur…** (of klik op de titel op het cassettebandje): de naam en de kleur van het bandje, **Benoem sprekers…**, **Toon in Finder**, **Verwijder…** (naar de prullenmand).
- Een opname weggooien kan ook in de lijst: klik met de rechtermuisknop op de opname en kies **Verwijder…**, of selecteer hem en druk op ⌫. Band·je vraagt het eerst.

## Dicteren {#dictation}
Druk op ⌃⌥⌘D, praat, en de tekst komt waar je cursor staat: in een chat, een mail, een editor of Terminal.

De sneltoets werkt op twee manieren:

- **Tik** op ⌃⌥⌘D: Band·je luistert tot je op Return drukt, of nog een keer op ⌃⌥⌘D. De Return zelf gaat niet naar de app.
- **Houd** ⌃⌥⌘D vast: Band·je luistert zolang je de toetsen vasthoudt en plakt als je loslaat.

Esc breekt af. Het icoon in de menubalk is oranje zolang Band·je luistert, met de tijd ernaast. Eén keer dicteren duurt maximaal vijf minuten; in de laatste 30 seconden knippert de tijd.

### Plakken
De tekst staat altijd op het klembord. Om hem voor je te plakken, moet Band·je een toetsaanslag (⌘V) mogen sturen: kies **Zet automatisch plakken aan…** in het menu, of ga naar Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid en zet Band·je aan. Zonder die toestemming plak je zelf met ⌘V.

macOS vertelt een draaiende Band·je pas na een herstart dat je deze toestemming hebt gegeven. Net aangezet? Kies **Herstart Band·je voor automatisch plakken** in het menu, of **Herstart Band·je** in [Instellingen](#settings).

Hoor je een kort geluid in plaats van dat de tekst verschijnt, dan heeft een wachtwoordveld of een andere app secure input aangezet (Veilige toetsenbordinvoer in Terminal, een wachtwoordmanager). macOS houdt het plakken dan tegen; de tekst staat op het klembord, dus druk zelf op ⌘V.

Wat je dicteert, wordt nergens bewaard.

## Samenvatten {#summaries}
Band·je kan een gesprek samenvatten in een vorm die je zelf kiest, met Apple Intelligence op je Mac.

Samenvatten werkt vanaf macOS 26, met Apple Intelligence aan. Zonder dat verschijnt **Samenvatten** niet in het menu en werkt Band·je gewoon zoals altijd.

1. Kies **Samenvatten** in het menu.
2. Kies onder **Kies een template** een template. Band·je vat de huidige opname samen. Wil je een andere samenvatten, kies die dan eerst bij **Recente opnames**.
3. Terwijl Band·je bezig is, staan er paarse sterretjes in de menubalk. Wijs ze aan om de voortgang te zien.
4. Als het klaar is, staat er een klein groen vinkje op het cassettebandje en zegt het menu **Samenvatting klaar**. Is het Band·je-venster open, dan toont het de opname.

Je kunt ook beginnen in het [Band·je-venster](#player): kies **Vat samen** naast de tabbladen en kies een template.

De samenvatting komt naast het transcript als `<naam> samenvatting <template>.md`. Samenvatten duurt een paar seconden tot ongeveer een minuut. Lange gesprekken worden in delen samengevat.

De samenvatting komt in de taal van het gesprek. Apple Intelligence vat samen in onder meer het Nederlands, Engels, Duits, Frans, Spaans, Italiaans en Portugees, maar nog niet in het Pools, Russisch of Oekraïens.

Het model op je Mac is klein. Het houdt zich aan wat er gezegd is, maar kan details missen. Controleer belangrijke feiten in het transcript.

Band·je heeft vier templates: een vergadering, een sollicitatiegesprek, een klantinterview en een algemene samenvatting. Zelf een maken: zie [Een template maken](#templates).

## Een template maken {#templates}
Maak je eigen template voor samenvattingen: een tekstbestand met de kopjes die je wilt.

Een template is een gewoon tekstbestand (`.md` of `.txt`) in `~/Music/Bandje/Templates`. De bestandsnaam wordt de naam in het menu **Samenvatten**.

Snelste begin: is het Band·je-venster open, kies dan in de menubalk **Samenvatten** > **Nieuw template**. Band·je maakt een nieuw template met twee kopjes en opent het; pas het aan, bewaar het en geef het in de Finder een eigen naam.

### Begin met een kopie
Het makkelijkst is een voorbeeld kopiëren en aanpassen:

1. Kies **Samenvatten** > **Open templatemap**.
2. Selecteer het voorbeeld dat het meest lijkt op wat je wilt, zoals `Vergadering.md`.
3. Kies in de Finder Archief > Dupliceer (⌘D) en geef de kopie een nieuwe naam, bijvoorbeeld `Weekstart.md`.
4. Open de kopie in Teksteditor of een andere tekstapp, pas de kopjes aan en bewaar.

De nieuwe template staat meteen in het menu **Samenvatten**. Je kunt de voorbeelden zelf ook aanpassen of weggooien: Band·je zet ze alleen terug als je de hele map Templates weggooit.

### Wat er in een template staat
Een lijst kopjes, elk met een regel over wat eronder moet:

- `## Besluiten` met de regel "Elk besluit als opsommingsteken. Noem wie het besloot."
- `## Actiepunten` met de regel "Wie, wat en wanneer."

Tips:

- Wees concreet. "Salariswens met de exacte bedragen" werkt beter dan "Salaris".
- Houd het bij een stuk of vijf kopjes. Het model op je Mac is klein: minder kopjes geven betere antwoorden.
- Schrijf "als dat gezegd is" bij iets wat misschien niet ter sprake komt, zodat Band·je het niet verzint.
- De kopjes blijven zoals jij ze schrijft. De tekst volgt de taal van het gesprek.

## Microfoon en geluid {#devices}
Kies welke microfoon je gebruikt en waar het geluid van je Mac heen gaat, direct vanuit het menu.

### Microfoon
Het menu **Microfoon** toont alle microfoons. Die in gebruik heeft een vinkje en de naam staat onder het menu-item. Kies je er een, dan geldt die voor je hele Mac, dus ook je bel-app gebruikt dezelfde. Met de klep dicht staat de ingebouwde microfoon uit; Band·je geeft dat aan.

### Geluidsuitvoer
Het menu **Geluidsuitvoer** toont alle apparaten die geluid kunnen afspelen, en zet de geluidsuitvoer van je Mac om. Band·je verandert dat nooit zelf.

Sommige USB-microfoons hebben een koptelefoonaansluiting en tellen ook als speaker. Vallen je AirPods weg, dan kan macOS het geluid daarheen sturen. Kies dan je speakers in Geluidsuitvoer.

## Instellingen {#settings}
Sneltoetsen, de opnamemap, toestemmingen, openen bij inloggen en de taal van Band·je.

Kies **Instellingen…** in het menu.

### Algemeen
Zet **Open Band·je bij inloggen** aan en Band·je staat na het inloggen vanzelf in de menubalk. **Altijd in het Dock** houdt Band·je in het Dock, ook zonder venster. Dat kun je ook kiezen in het welkomstvenster als je Band·je voor het eerst opent. Het staat uit tot je het aanzet. Zet je het uit in Systeeminstellingen > Algemeen > Inlogonderdelen en extensies, dan ziet Band·je dat hier ook. **Toon het Band·je-venster bij het starten** uit: dan blijft Band·je bij het starten in de menubalk.

Band·je volgt de taal van macOS. Wil je alleen voor Band·je een andere taal, kies die dan hier en klik op **Herstart Band·je**. Menu's, vensters, nieuwe transcripten en Help gaan om. **Zoals macOS** zet het terug.

### Sneltoetsen
Klik op een veld en druk de nieuwe combinatie in. Daarin moet ⌘, ⌃ of ⌥ zitten, of het is een functietoets. Esc annuleert, **Herstel standaard** zet ⌃⌥⌘R en ⌃⌥⌘D terug.

Gebruikt een andere app de combinatie al, dan meldt Band·je dat en blijft de oude staan.

### Geluid
Kies de **Microfoon** en de **Geluidsuitvoer**, net als in het menu van Band·je. Het geldt voor alle apps, ook om te bellen.

### Transcriptie
**Transcribeer automatisch** transcribeert elke opname zodra je stopt. **Sprekers herkennen** onderscheidt meerdere stemmen (Spreker 1, Spreker 2…); staat het uit, dan krijg je alleen Ik en Andere kant. De taal herkent Band·je zelf.

### Opslag
Zet **Synchroniseer via iCloud** aan en je opnames, transcripten, samenvattingen en templates staan in iCloud Drive › Band·je, op je iPhone en je andere Macs met dezelfde Apple ID. Een opname wordt eerst op je Mac gemaakt en gaat naar iCloud als je stopt. Band·je vraagt of je bestaande opnames mee moeten. Zet je het uit, dan is je eigen map weer de opnamemap; in iCloud wordt niets verwijderd, en Band·je biedt aan de opnames terug te kopiëren. Apple versleutelt iCloud Drive end-to-end als Geavanceerde gegevensbescherming aan staat.

Klik op **Wijzig…** en kies een map, waar dan ook op je Mac of op een externe schijf. Nieuwe opnames en getranscribeerde bestanden komen daar. Bestaande opnames blijven waar ze staan, net als je templates en de spraakmodellen. **Gebruik ~/Music/Bandje** zet de standaardmap terug.

Staat de map in iCloud Drive, Dropbox of een andere clouddienst (ook Bureaublad en Documenten als die in iCloud staan), dan waarschuwt Band·je je: je opnames verlaten dan via die dienst je Mac.

### Toegang
Of Band·je de microfoon mag gebruiken, voor je mag plakken en het geluid van je Mac mag opnemen, met per onderdeel een knop (**Sta toe…** of **Open instellingen…**). Een groen vinkje betekent toegestaan; de stand ververst vanzelf als je terugkomt uit Systeeminstellingen. Zie [Problemen oplossen](#troubleshooting).

## Privacy en netwerk {#privacy}
Je audio, transcripten en samenvattingen verlaten je Mac nooit.

- Geen account, geen statistieken, geen tracking. Geen server van ons.
- Alleen iCloud als je [Synchroniseer via iCloud](#settings) aanzet: dan staan je opnames in je eigen iCloud Drive, net als je andere bestanden. Band·je ziet ze nooit.
- Alles staat in je opnamemap: `~/Music/Bandje`, tenzij je een andere koos. Gooi je een map weg, dan is hij weg. Kies je een map in iCloud Drive of een andere clouddienst, dan gaan je opnames naar die dienst; Band·je waarschuwt je eerst.
- Transcriberen, sprekerherkenning en dicteren gebeuren op je Mac.
- Samenvatten gebruikt alleen het Apple Intelligence-model op je Mac, nooit Private Cloud Compute van Apple.

De spraakherkenning van Desert Ant Labs controleert zijn licentie via het netwerk: hooguit eens per maand per spraakmodel. Daarbij gaan een willekeurig installatienummer, het model, de versie en de app-ID mee. Nooit audio, nooit tekst. Dat staat ook in **Over Band·je**.

## Geheugen en opslag {#resources}
Band·je is licht: ongeveer 60 tot 70 MB geheugen terwijl het draait.

De spraakmodellen zitten in Band·je zelf: ongeveer 400 MB van de app. Band·je downloadt zelf nooit iets.

Een paar seconden na het starten laadt Band·je het spraakmodel op de achtergrond, zodat dicteren meteen klaar is. De allereerste keer op een Mac duurt dat ongeveer 20 seconden, omdat macOS het model voor jouw chip optimaliseert. Daarna gaat het snel.

Een uur audio neemt ongeveer 55 MB in. Transcriberen gebruikt tijdelijk wat extra geheugen.

## Problemen oplossen {#troubleshooting}
Oplossingen voor dingen die mis kunnen gaan.

### Controleer eerst de toestemmingen
Veel problemen komen door een ontbrekende toestemming. Kies **Instellingen…** en kijk onder **Toegang**:

- **Microfoon**: nodig om je stem op te nemen en om te dicteren.
- **Geluid van je Mac**: nodig om de andere kant op te nemen. macOS laat apps deze toestemming niet uitlezen, dus Band·je laat zien wat er bij de laatste opname gebeurde: er kwam geluid binnen, of het was stil. Stil is normaal als er niets afspeelde.
- **Automatisch plakken**: nodig om gedicteerde tekst voor je te plakken.

Een groen vinkje betekent toegestaan. Anders: klik op **Open instellingen…**, zet Band·je aan en kom terug; Band·je ziet het vanzelf.

Bij elke start controleert Band·je de microfoon en automatisch plakken, en meldt het als er een ontbreekt. Heb je automatisch plakken niet nodig? Vink **Toon deze melding niet opnieuw** aan, of zet **Waarschuw bij het starten als er iets ontbreekt** uit onder Toegang.

### De andere kant ontbreekt in de opname
macOS staat niet toe dat Band·je het geluid van je Mac opneemt. Ga naar Systeeminstellingen > Privacy en beveiliging > Scherm- en systeemaudio-opname en zet Band·je aan bij Alleen systeemaudio-opname.

### Mijn eigen stem ontbreekt
Kijk in het menu **Microfoon**. Met de klep dicht staat de ingebouwde microfoon uit: kies een andere. Mag Band·je de microfoon helemaal niet gebruiken, zet het dan aan in Systeeminstellingen > Privacy en beveiliging > Microfoon.

### Ik hoor niets meer nadat ik mijn AirPods weglegde
macOS stuurt het geluid naar een ander apparaat, zoals een USB-microfoon met koptelefoonaansluiting. Kies je speakers in **Geluidsuitvoer**.

### Het transcript is onzin
Het gesprek is waarschijnlijk in een taal die Band·je niet kent. Band·je merkt dat niet en schrijft op wat het denkt te horen.

### Er zijn meer sprekers dan er waren
Keuzemenu's, wachtmuziek en slechte lijnen kunnen de sprekerherkenning in de war brengen. Geef de labels de juiste naam met [Sprekers benoemen](#speakers).

### Samenvatten staat niet in het menu
Samenvatten werkt vanaf macOS 26, met Apple Intelligence aan in Systeeminstellingen > Apple Intelligence en Siri. De taal van je Mac en die van Siri moeten gelijk zijn.

### De sneltoets werkt niet
Een andere app gebruikt misschien dezelfde combinatie. Kies een andere bij [Instellingen](#settings).

## Over Band·je {#about}
Band·je is gemaakt door Neurendal B.V. in Nederland.

Spraak- en sprekerherkenning: Voz en Who van Desert Ant Labs, gebaseerd op NVIDIA Parakeet TDT 0.6B v3 en pyannote community-1 (CC BY 4.0). Samenvatten: Apple Intelligence.

Kies **Over Band·je** in het menu voor de versies en links.
