# Aiuto di Band·je
Band·je registra le conversazioni sul tuo Mac e le trasforma in testo. Si trova nella barra dei menu: la piccola musicassetta in alto a destra. Tutto avviene sul tuo Mac.

## Registrare una conversazione {#record}
Premi ⌃⌥⌘R per iniziare e di nuovo ⌃⌥⌘R per fermare.

Band·je registra due cose insieme: il tuo microfono e tutto l’audio riprodotto dal Mac. Funziona con qualsiasi app di chiamata, come FaceTime, Zoom, Teams, Meet o una telefonata tramite il Mac. Band·je non registra lo schermo.

- Durante la registrazione la musicassetta nella barra dei menu diventa rossa, le bobine girano e accanto scorre il tempo in rosso.
- Il Mac non va in stop mentre Band·je registra.
- La prima volta macOS chiede il permesso di registrare l’audio del Mac. Consentilo, altrimenti Band·je sente solo il tuo microfono.
- Se il microfono resta muto per sei secondi, o se chiudi il coperchio mentre usi il microfono integrato, Band·je ti avvisa e propone di passare a un altro microfono.

Avvisa gli altri che stai registrando. In alcuni paesi, e per uso lavorativo, è obbligatorio per legge, e a volte serve anche il loro consenso. Sei responsabile del rispetto della legge che ti riguarda. Band·je te lo ricorda una volta, prima della prima registrazione.

### Dove finiscono le registrazioni
Ogni registrazione ha una propria cartella in `~/Music/Bandje` (o nella cartella scelta in [Impostazioni](#settings), oppure iCloud Drive › Band·je quando [sincronizzi con iCloud](#settings)), con il giorno e l’ora come nome, ad esempio `Registrazione 6 nov 14.32`. Il tuo iPhone dà lo stesso tipo di nome alle sue registrazioni. Nella cartella:

- l’audio (`.m4a`): tu sul canale sinistro, gli altri sul destro
- la trascrizione (`.md`), leggibile con qualsiasi app di testo o Markdown
- i dati grezzi (`.json`) con l’orario di ogni parola
- i riassunti, come file `.md`

Apri una registrazione nella [finestra di Band·je](#player). Scegli **Apri cartella registrazioni** nel menu per vedere i file. Se Band·je o il Mac si chiude all’improvviso durante una registrazione, Band·je propone di salvarla al successivo avvio.

## Trascrizioni {#transcripts}
Quando fermi la registrazione, Band·je scrive ciò che è stato detto e chi l’ha detto.

Il menu mostra l’avanzamento. Puoi avviare una nuova registrazione mentre Band·je trascrive. Quando la trascrizione è pronta, sulla musicassetta nella barra dei menu compare un piccolo segno di spunta verde e il menu mostra **Trascrizione pronta**: fai clic per aprire la registrazione nella finestra di Band·je. Il segno di spunta scompare dopo che hai aperto il menu.

- Ciò che dici tu è etichettato **Io**. Ciò che dicono gli altri è etichettato **Interlocutore**.
- Quando dall’altra parte parlano più persone, Band·je le distingue: **Parlante 1**, **Parlante 2** e così via. Dai loro un nome con [Nomina parlanti](#speakers).
- Lo stesso vale per più persone intorno al tuo Mac, ad esempio in una riunione allo stesso tavolo: invece di **Io** diventano **Parlante 1**, **Parlante 2** e così via.
- Band·je capisce 25 lingue, tra cui inglese, olandese, tedesco, francese, spagnolo, italiano, portoghese, polacco, russo e ucraino. Non serve scegliere la lingua.

Per il miglior risultato, usa le cuffie durante una chiamata. Senza cuffie il microfono capta anche l’interlocutore dagli altoparlanti. Band·je ne filtra la maggior parte, ma non tutto.

### Trascrivere un altro file
Scegli **Trascrivi file…** per trascrivere qualsiasi file audio, ad esempio un memo vocale dell’iPhone. Band·je copia l’audio in una propria cartella nella cartella delle registrazioni e ci mette accanto la trascrizione. L’originale resta dov’era.

## Nominare i parlanti {#speakers}
Dai ai parlanti di una trascrizione il loro vero nome.

Apri la registrazione nella [finestra di Band·je](#player) e scegli **Nomina parlanti…** in **Altro**, oppure scegli **Nomina parlanti…** nel menu: si apre la registrazione attuale. Per lavorare su una registrazione precedente dal menu, scegli prima **Registrazioni recenti**.

Per ogni parlante vedi la sua frase più lunga. Fai clic sul pulsante di riproduzione per ascoltare quel pezzo, scrivi un nome e fai clic su **Salva**. Band·je aggiorna la trascrizione ed eventuali riassunti successivi. Lascia un campo vuoto per mantenere l’etichetta.

Su una linea telefonica con un menu o una musica d’attesa, a volte Band·je sente più parlanti di quanti ce ne fossero. Dai a due etichette lo stesso nome, oppure lascia com’è quella in più.

## La finestra di Band·je {#player}
Tutte le tue registrazioni in un’unica finestra: ascolta, segui il testo, cerca, nomina i parlanti, riassumi e condividi.

Scegli **Apri Band·je** nel menu (⌘O). La finestra si apre anche quando avvii Band·je tu stesso, ad esempio da Launchpad o Spotlight. **Apri in Band·je** apre la registrazione attuale. Mentre la finestra è aperta, Band·je è nel Dock e in ⌘Tab; chiudila e Band·je torna solo nella barra dei menu. Attiva **Sempre nel Dock** in [Impostazioni](#settings) per tenere l’icona. La prima volta la finestra si apre sempre, con i permessi, ognuno con il suo pulsante. Se chiudi la finestra, Band·je resta nella barra dei menu; esci da Band·je da quel menu.

- A sinistra: le tue registrazioni per giorno, con l’ora, la durata e le prime parole della trascrizione. La ricerca trova titoli e parole nelle trascrizioni. In basso c’è **Avvia registrazione**; durante la registrazione la nuova registrazione è in cima con un punto rosso e, quando ti fermi, la finestra la apre.
- A destra: la registrazione con la musicassetta, la barra di avanzamento e il pulsante di riproduzione (Spazio). Fai clic su una frase per ascoltare da lì; durante la riproduzione la frase che senti si illumina e la trascrizione la segue. **Cerca nella trascrizione** (⌘F) trova le parole.
- Accanto a **Trascrizione** c’è la scheda **Riassunto**. Se non c’è ancora un riassunto, contiene **Riassumi**: scegli un modello, vedi [Riassunti](#summaries). Ogni riassunto ha la sua scheda; **Un altro riassunto** ne crea un altro.
- Non c’è ancora una trascrizione (ad esempio una registrazione dal tuo iPhone)? Fai clic su **Trascrivi**.
- **Condividi**: **Audio…**, **Trascrizione (.md)…**, **Trascrizione in PDF…** o **Pagina web con audio…**: un unico file con il lettore, la trascrizione, i riassunti e l’audio, che funziona in qualsiasi browser, anche offline. **Pagina web con audio, compatta (per email)…** rende l’audio più piccolo. La pagina ha un link a band.je e nient’altro.
- Su carta: **Stampa…** (⌘P, o in **Condividi**) stampa la trascrizione, come il PDF.
- **Altro**: **Nome e colore…** (o fai clic sul titolo sulla musicassetta): il nome e il colore della musicassetta, **Nomina parlanti…**, **Mostra nel Finder**, **Elimina…** (nel Cestino).
- Puoi eliminare una registrazione anche dall’elenco: fai clic destro su di essa e scegli **Elimina…**, oppure selezionala e premi ⌫. Band·je chiede prima conferma.

## Dettatura {#dictation}
Premi ⌃⌥⌘D, parla e il testo appare dove si trova il cursore: in una chat, un’email, un editor o Terminal.

Puoi usare l’abbreviazione in due modi:

- **Premi brevemente** ⌃⌥⌘D: Band·je ascolta finché non premi Return, o di nuovo ⌃⌥⌘D. Il Return non viene inviato all’app.
- **Tieni premuto** ⌃⌥⌘D: Band·je ascolta finché tieni premuti i tasti e incolla quando li rilasci.

Premi Esc per annullare. Mentre Band·je ascolta, l’icona nella barra dei menu diventa arancione, con il tempo accanto. Una dettatura può durare fino a cinque minuti; negli ultimi 30 secondi il tempo lampeggia.

### Incollare
Il testo è sempre negli Appunti. Per incollarlo al posto tuo, Band·je ha bisogno del permesso di inviare una pressione di tasti (⌘V): scegli **Attiva incolla automatico…** nel menu, oppure vai in Impostazioni di Sistema > Privacy e sicurezza > Accessibilità e attiva Band·je. Senza questo permesso incolli tu con ⌘V.

macOS comunica questo permesso a Band·je solo dopo un riavvio. L’hai appena attivato? Scegli **Riavvia Band·je per l'incolla automatico** nel menu, oppure **Riavvia Band·je** in [Impostazioni](#settings).

Se senti un breve suono invece dell’incolla, un campo password o un’altra app ha attivato l’inserimento sicuro (Inserimento sicuro da tastiera di Terminal, un gestore di password). macOS blocca allora l’incolla; il testo è negli Appunti, quindi premi tu ⌘V.

Niente di ciò che detti viene salvato.

## Riassunti {#summaries}
Band·je può riassumere una conversazione nella forma che scegli, con Apple Intelligence sul tuo Mac.

I riassunti richiedono macOS 26 o successivo con Apple Intelligence attivo. Senza, il menu **Riassumi** non compare e Band·je funziona come al solito.

1. Scegli **Riassumi** nel menu.
2. In **Scegli un modello**, scegline uno. Band·je riassume la registrazione attuale. Per riassumerne un’altra, selezionala prima in **Registrazioni recenti**.
3. Mentre Band·je lavora, nella barra dei menu compaiono delle scintille viola. Passaci sopra con il puntatore per vedere l’avanzamento.
4. Al termine, sulla musicassetta compare un piccolo segno di spunta verde e il menu indica **Riassunto pronto**. Se la finestra di Band·je è aperta, mostra la registrazione.

Puoi anche partire dalla [finestra di Band·je](#player): scegli **Riassumi** accanto ai pannelli e seleziona un modello.

Il riassunto viene salvato accanto alla trascrizione come `<nome> riassunto <modello>.md`. Un riassunto richiede da pochi secondi a circa un minuto. Le conversazioni lunghe vengono riassunte a pezzi.

Il riassunto è scritto nella lingua della conversazione. Apple Intelligence riassume in inglese, olandese, tedesco, francese, spagnolo, italiano, portoghese e in poche altre lingue, ma non ancora in polacco, russo o ucraino.

Il modello sul tuo Mac è piccolo. Si attiene a ciò che è stato detto, ma può perdere dei dettagli. Verifica i fatti importanti nella trascrizione.

Band·je include quattro modelli: una riunione, un colloquio di lavoro, un’intervista a un cliente e un riassunto generico. Per crearne uno tuo, vedi [Creare un modello](#templates).

## Creare un modello {#templates}
Crea un tuo modello per i riassunti: un file di testo con le intestazioni che vuoi.

Un modello è un semplice file di testo (`.md` o `.txt`) in `~/Music/Bandje/Templates`. Il nome del file diventa il nome nel menu **Riassumi**.

Il modo più rapido: con la finestra di Band·je aperta, scegli **Riassumi** > **Nuovo modello** nella barra dei menu. Band·je crea un nuovo modello con due titoli e lo apre; modificalo, salvalo e dagli un nome nel Finder.

### Parti da una copia
Il modo più semplice è copiare un esempio e modificarlo:

1. Scegli **Riassumi** > **Apri cartella dei modelli**.
2. Seleziona l’esempio più vicino a ciò che vuoi, ad esempio `Meeting.md`.
3. Nel Finder scegli Archivio > Duplica (⌘D) e rinomina la copia, ad esempio `Weekly standup.md`.
4. Apri la copia in TextEdit o in un’altra app di testo, modifica le intestazioni e salva.

Il nuovo modello compare subito nel menu **Riassumi**. Puoi modificare anche gli esempi stessi, o eliminarli: Band·je li rimette solo se elimini l’intera cartella Templates.

### Cosa mettere in un modello
Un elenco di intestazioni, ognuna con una riga su cosa va sotto:

- `## Decisioni` con la riga "Ogni decisione in un punto elenco. Indica chi ha deciso."
- `## Azioni da fare` con la riga "Chi, cosa e quando."

Suggerimenti:

- Sii preciso. "Aspettative di stipendio con gli importi esatti" funziona meglio di "Stipendio".
- Limitati a circa cinque intestazioni. Il modello sul tuo Mac è piccolo: meno intestazioni danno risposte migliori.
- Scrivi "se è stato detto" quando qualcosa potrebbe non emergere, così Band·je non se lo inventa.
- Le intestazioni restano come le scrivi. Il testo segue la lingua della conversazione.

## Microfono e audio {#devices}
Scegli quale microfono usare e dove va l’audio del Mac, direttamente dal menu.

### Microfono
Il menu **Microfono** elenca tutti i microfoni. Quello in uso ha un segno di spunta e il suo nome appare sotto la voce di menu. Sceglierne uno cambia il microfono per tutto il Mac, così l’app di chiamata usa lo stesso. Con il coperchio chiuso il microfono integrato è spento; Band·je lo indica.

### Uscita audio
Il menu **Uscita audio** elenca tutti i dispositivi che possono riprodurre audio e imposta l’uscita audio del Mac. Band·je non la cambia mai da solo.

Alcuni microfoni USB hanno un’uscita per le cuffie e contano anche come altoparlanti. Quando gli AirPods si scollegano, macOS può mandare l’audio lì. Scegli i tuoi altoparlanti in Uscita audio per risolvere.

## Impostazioni {#settings}
Abbreviazioni, cartella delle registrazioni, autorizzazioni, apertura al login e lingua di Band·je.

Scegli **Impostazioni…** nel menu.

### Generali
Attiva **Apri Band·je al login** e Band·je compare da solo nella barra dei menu dopo il login. **Sempre nel Dock** tiene Band·je nel Dock, anche senza la finestra. Puoi sceglierlo anche nella finestra di benvenuto la prima volta che apri Band·je. È disattivato finché non lo attivi. Se lo disattivi in Impostazioni di Sistema > Generali > Elementi login ed estensioni, Band·je lo mostra qui. Disattiva **Mostra la finestra di Band·je all’avvio** e Band·je resta nella barra dei menu all’avvio.

Band·je segue la lingua di macOS. Per usare un’altra lingua solo per Band·je, sceglila qui e fai clic su **Riavvia Band·je**. Menu, finestre, nuove trascrizioni e Aiuto cambiano lingua. **Come macOS** torna indietro.

### Abbreviazioni da tastiera
Fai clic su un campo e premi la nuova combinazione. Deve contenere ⌘, ⌃ o ⌥, oppure essere un tasto funzione. Esc annulla, **Ripristina predefiniti** riporta ⌃⌥⌘R e ⌃⌥⌘D.

Se un’altra app usa già la combinazione, Band·je te lo dice e mantiene quella vecchia.

### Suono
Scegli il **Microfono** e l’**Uscita audio**, come nel menu di Band·je. Vale per tutte le app, anche per le chiamate.

### Trascrizione
**Trascrivi automaticamente** trascrive ogni registrazione appena ti fermi. **Riconosci i parlanti** distingue più voci (Parlante 1, Parlante 2…); se è disattivato, ottieni solo Io e Interlocutore. Band·je riconosce la lingua da solo.

### Archiviazione
Attiva **Sincronizza con iCloud** e le tue registrazioni, trascrizioni, riassunti e modelli saranno in iCloud Drive › Band·je, sul tuo iPhone e sugli altri Mac con lo stesso Account Apple. Una registrazione viene creata prima sul Mac e passa su iCloud quando la fermi. Band·je chiede se spostare anche le registrazioni esistenti. Se la disattivi, la tua cartella torna a essere la cartella delle registrazioni; da iCloud non viene eliminato nulla e Band·je propone di copiare indietro le registrazioni. Apple cifra iCloud Drive end-to-end se la protezione avanzata dei dati è attiva.

Fai clic su **Modifica…** e scegli una cartella, ovunque sul Mac o su un disco esterno. Le nuove registrazioni e i file trascritti vanno lì. Le registrazioni esistenti restano dove sono, così come i tuoi modelli e i modelli vocali. **Usa ~/Music/Bandje** torna alla cartella standard.

Se la cartella è in iCloud Drive, Dropbox o un altro servizio cloud (anche Scrivania e Documenti quando sono in iCloud), Band·je ti avvisa: le registrazioni lasciano allora il Mac tramite quel servizio.

### Accesso
Se Band·je può usare il microfono, incollare per te e registrare l’audio del tuo Mac, ciascuno con il suo pulsante (**Consenti…** o **Apri impostazioni…**). Un segno di spunta verde significa consentito; lo stato si aggiorna da solo quando torni da Impostazioni di Sistema. Vedi [Risoluzione dei problemi](#troubleshooting).

## Privacy e rete {#privacy}
Audio, trascrizioni e riassunti non lasciano mai il tuo Mac.

- Nessun account, nessuna analisi, nessun tracciamento. Nessun server nostro.
- iCloud solo se attivi [Sincronizza con iCloud](#settings): allora le tue registrazioni sono nel tuo iCloud Drive, come gli altri tuoi file. Band·je non le vede mai.
- Tutto è salvato nella cartella delle registrazioni: `~/Music/Bandje`, a meno che tu non ne abbia scelta un’altra. Elimina una cartella e non c’è più. Se scegli una cartella in iCloud Drive o in un altro servizio cloud, le registrazioni vanno a quel servizio; Band·je ti avvisa prima.
- Trascrizione, riconoscimento dei parlanti e dettatura avvengono sul tuo Mac.
- I riassunti usano solo il modello di Apple Intelligence sul tuo Mac, mai Private Cloud Compute di Apple.

Il motore vocale di Desert Ant Labs verifica la licenza tramite la rete: al massimo una volta al mese per modello vocale. Invia un ID di installazione casuale, la versione del modello e del motore e l’ID dell’app. Mai audio, mai testo. Lo mostra anche **Informazioni su Band·je**.

## Memoria e spazio {#resources}
Band·je è leggero: circa 60-70 MB di memoria mentre è in esecuzione.

I modelli vocali sono inclusi in Band·je: circa 400 MB delle dimensioni dell’app. Band·je non scarica mai nulla da solo.

Pochi secondi dopo l’avvio, Band·je carica il modello vocale in background, così la dettatura è subito pronta. La primissima volta su un Mac ci vogliono circa 20 secondi, perché macOS ottimizza il modello per il tuo chip. Dopo è rapido.

Un’ora di audio occupa circa 55 MB. Trascriverla richiede un po’ di memoria in più durante l’elaborazione.

## Risoluzione dei problemi {#troubleshooting}
Soluzioni per ciò che può andare storto.

### Controlla prima le autorizzazioni
Molti problemi dipendono da un’autorizzazione mancante. Scegli **Impostazioni…** e guarda in **Accesso**:

- **Microfono**: serve per registrare la tua voce e per dettare.
- **Suono del Mac**: serve per registrare l’interlocutore. macOS non permette alle app di leggere questa autorizzazione, quindi Band·je mostra cosa è successo nell’ultima registrazione: è arrivato del suono oppure c’era silenzio. Il silenzio è normale se non suonava nulla.
- **Incolla automatico**: serve per incollare al posto tuo il testo dettato.

Un segno di spunta verde significa consentito. Altrimenti fai clic su **Apri impostazioni…**, attiva Band·je e torna; Band·je se ne accorge da solo.

A ogni avvio Band·je controlla il microfono e l’incolla automatico e ti avvisa se manca qualcosa. Non ti serve l’incolla automatico? Seleziona **Non mostrare più questo messaggio**, oppure disattiva **Avvisa all’avvio se manca qualcosa** in Accesso.

### Nella registrazione manca l’interlocutore
macOS non ha permesso a Band·je di registrare l’audio del Mac. Vai in Impostazioni di Sistema > Privacy e sicurezza > Registrazione schermo e audio di sistema e attiva Band·je in Solo registrazione audio di sistema.

### Manca la mia voce
Controlla il menu **Microfono**. Con il coperchio chiuso il microfono integrato è spento: scegline un altro. Se Band·je non può usare affatto il microfono, attivalo in Impostazioni di Sistema > Privacy e sicurezza > Microfono.

### Non sento nulla dopo aver tolto gli AirPods
macOS ha mandato l’audio a un altro dispositivo, ad esempio un microfono USB con uscita per le cuffie. Scegli i tuoi altoparlanti in **Uscita audio**.

### La trascrizione non ha senso
Probabilmente la conversazione è in una lingua che Band·je non conosce. Band·je non può accorgersene, quindi scrive ciò che crede di aver sentito.

### Ci sono più parlanti di quanti ce ne fossero
Menu telefonici, musica d’attesa e linee disturbate possono confondere il riconoscimento dei parlanti. Dai alle etichette i nomi giusti in [Nomina parlanti](#speakers).

### Riassumi non è nel menu
I riassunti richiedono macOS 26 o successivo con Apple Intelligence attivo in Impostazioni di Sistema > Apple Intelligence e Siri. La lingua del Mac e quella di Siri devono coincidere.

### L’abbreviazione non funziona
Un’altra app potrebbe usare la stessa combinazione. Scegline un’altra in [Impostazioni](#settings).

## Informazioni su Band·je {#about}
Band·je è realizzato da Neurendal B.V. nei Paesi Bassi.

Riconoscimento vocale e dei parlanti: Voz e Who di Desert Ant Labs, basati su NVIDIA Parakeet TDT 0.6B v3 e pyannote community-1 (CC BY 4.0). Riassunti: Apple Intelligence.

Scegli **Informazioni su Band·je** nel menu per le versioni e i link.
