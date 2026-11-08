# Pomoc Band·je
Band·je nagrywa rozmowy na Twoim Macu i zamienia je w tekst. Mieszka na pasku menu: to mała kaseta w prawym górnym rogu. Wszystko dzieje się na Twoim Macu.

## Nagrywanie rozmowy {#record}
Naciśnij ⌃⌥⌘R, aby zacząć, i jeszcze raz ⌃⌥⌘R, aby zakończyć.

Band·je nagrywa jednocześnie dwie rzeczy: Twój mikrofon i cały dźwięk odtwarzany przez Maca. Działa z każdą aplikacją do rozmów, np. FaceTime, Zoom, Teams, Meet albo z rozmową telefoniczną przez Maca. Band·je nie nagrywa ekranu.

- Podczas nagrywania kaseta na pasku menu robi się czerwona, jej szpule się obracają, a obok czerwonym kolorem biegnie czas.
- Gdy Band·je nagrywa, Mac nie przechodzi w stan uśpienia.
- Za pierwszym razem macOS poprosi o pozwolenie na nagrywanie dźwięku z Maca. Zezwól, inaczej Band·je usłyszy tylko Twój mikrofon.
- Jeśli mikrofon milczy przez sześć sekund albo pokrywa zostanie zamknięta, gdy używany jest wbudowany mikrofon, Band·je Cię ostrzeże i zaproponuje przełączenie na inny mikrofon.

Uprzedź pozostałe osoby, że nagrywasz. W niektórych krajach, a także w zastosowaniach służbowych, wymaga tego prawo, a czasem potrzebna jest też ich zgoda. Odpowiadasz za przestrzeganie prawa, które Cię dotyczy. Band·je przypomni Ci o tym raz, przed pierwszym nagraniem.

### Gdzie trafiają nagrania
Każde nagranie dostaje własny folder w `~/Music/Bandje` (lub w folderze wybranym w [Ustawienia](#settings) albo w iCloud Drive › Band·je, gdy [synchronizujesz przez iCloud](#settings)), nazwany dniem i godziną, np. `Nagranie 6 lis 14.32`. iPhone nazywa swoje nagrania tak samo. W folderze znajdziesz:

- dźwięk (`.m4a`): Ty na lewym kanale, pozostali na prawym
- transkrypcję (`.md`), którą otworzysz w każdej aplikacji do tekstu lub Markdown
- surowe dane (`.json`) z czasem każdego słowa
- podsumowania jako pliki `.md`

Otwórz nagranie w [oknie Band·je](#player). Wybierz **Otwórz folder nagrań** w menu, aby zobaczyć pliki. Jeśli Band·je lub Mac niespodziewanie przestanie działać podczas nagrywania, Band·je zaproponuje zapisanie nagrania przy następnym uruchomieniu.

## Transkrypcje {#transcripts}
Po zakończeniu nagrywania Band·je zapisuje, co zostało powiedziane i kto to powiedział.

Menu pokazuje postęp. Możesz zacząć nowe nagranie, gdy Band·je transkrybuje. Gdy transkrypcja jest gotowa, na kasecie na pasku menu pojawia się mały zielony znaczek, a w menu widać **Transkrypcja gotowa**: kliknij, aby otworzyć nagranie w oknie Band·je. Znaczek znika, gdy otworzysz menu.

- To, co mówisz Ty, jest oznaczone jako **Ja**. To, co mówią pozostali, jako **Druga strona**.
- Gdy po drugiej stronie mówi kilka osób, Band·je je rozróżnia: **Mówca 1**, **Mówca 2** itd. Nadaj im imiona w [Nazwij mówców](#speakers).
- To samo dotyczy kilku osób przy Twoim Macu, np. na spotkaniu przy jednym stole: zamiast **Ja** stają się **Mówca 1**, **Mówca 2** itd.
- Band·je rozumie 25 języków, m.in. angielski, niderlandzki, niemiecki, francuski, hiszpański, włoski, portugalski, polski, rosyjski i ukraiński. Nie musisz wybierać języka.

Dla najlepszego wyniku używaj słuchawek podczas rozmowy. Bez nich mikrofon wychwytuje też drugą stronę z głośników. Band·je odfiltrowuje większość tego dźwięku, ale nie wszystko.

### Transkrypcja innego pliku
Wybierz **Transkrybuj plik…**, aby przetranskrybować dowolny plik audio, np. notatkę głosową z iPhone'a. Band·je kopiuje dźwięk do osobnego folderu w Twoim folderze nagrań i umieszcza obok transkrypcję. Oryginał zostaje na miejscu.

## Nazywanie mówców {#speakers}
Nadaj mówcom w transkrypcji ich prawdziwe imiona.

Otwórz nagranie w [oknie Band·je](#player) i wybierz **Nazwij mówców…** w **Więcej** albo wybierz **Nazwij mówców…** w menu: otworzy się bieżące nagranie. Aby z menu pracować na starszym nagraniu, najpierw wybierz **Ostatnie nagrania**.

Przy każdym mówcy widzisz jego najdłuższą wypowiedź. Kliknij przycisk odtwarzania, aby odsłuchać ten fragment, wpisz imię i kliknij **Zachowaj**. Band·je aktualizuje transkrypcję i każde późniejsze podsumowanie. Zostaw pole puste, aby zachować etykietę.

Przy linii telefonicznej z menu lub muzyką w oczekiwaniu Band·je czasem słyszy więcej mówców, niż było. Nadaj dwóm etykietom to samo imię albo zostaw dodatkową bez zmian.

## Okno Band·je {#player}
Wszystkie nagrania w jednym oknie: słuchaj, czytaj na bieżąco, szukaj, nazywaj mówców, podsumowuj i udostępniaj.

Wybierz **Otwórz Band·je** w menu (⌘O). Okno otwiera się też, gdy sam uruchomisz Band·je, na przykład z Launchpada lub Spotlight. **Otwórz w Band·je** otwiera bieżące nagranie. Gdy okno jest otwarte, Band·je jest w Docku i w ⌘Tab; zamknij je, a Band·je znów będzie tylko na pasku menu. Włącz **Zawsze w Docku** w [Ustawienia](#settings), aby ikona została. Za pierwszym razem okno otwiera się zawsze, z uprawnieniami, każde z własnym przyciskiem. Po zamknięciu okna Band·je zostaje na pasku menu; zakończ Band·je w tym menu.

- Po lewej: nagrania według dni, z godziną, długością i pierwszymi słowami transkrypcji. Wyszukiwanie znajduje tytuły i słowa w transkrypcjach. Na dole jest **Rozpocznij nagrywanie**; podczas nagrywania nowe nagranie jest na górze z czerwoną kropką, a po zatrzymaniu okno je otwiera.
- Po prawej: nagranie z kasetą, paskiem pozycji i przyciskiem odtwarzania (Spacja). Kliknij zdanie, aby słuchać od tego miejsca; podczas odtwarzania słyszane zdanie jest podświetlone, a transkrypcja przewija się za nim. **Szukaj w transkrypcji** (⌘F) znajduje słowa.
- Obok **Transkrypcja** jest karta **Podsumowanie**. Gdy nie ma jeszcze podsumowania, jest tam **Podsumuj**: wybierz szablon, zobacz [Podsumowania](#summaries). Każde podsumowanie ma własną kartę; **Kolejne podsumowanie** tworzy kolejne.
- Nie ma jeszcze transkrypcji (np. przy nagraniu z iPhone'a)? Kliknij **Transkrybuj**.
- **Udostępnij**: **Dźwięk…**, **Transkrypcja (.md)…**, **Transkrypcja jako PDF…** lub **Strona z dźwiękiem…**: jeden plik z odtwarzaczem, transkrypcją, podsumowaniami i dźwiękiem, który działa w każdej przeglądarce, także offline. **Strona z dźwiękiem, kompaktowa (do e-maila)…** zmniejsza dźwięk. Strona ma link do band.je i nic więcej.
- Na papierze: **Drukuj…** (⌘P lub w **Udostępnij**) drukuje transkrypcję, tak jak PDF.
- **Więcej**: **Nazwa i kolor…** (albo kliknij tytuł na kasecie): nazwa i kolor kasety, **Nazwij mówców…**, **Pokaż w Finderze**, **Usuń…** (do Kosza).
- Nagranie możesz też usunąć z listy: kliknij je prawym przyciskiem i wybierz **Usuń…** albo zaznacz je i naciśnij ⌫. Band·je najpierw zapyta.

## Dyktowanie {#dictation}
Naciśnij ⌃⌥⌘D, mów, a tekst pojawi się tam, gdzie jest kursor: w czacie, e-mailu, edytorze lub Terminalu.

Skrótu można używać na dwa sposoby:

- **Naciśnij krótko** ⌃⌥⌘D: Band·je słucha, aż naciśniesz Return albo ponownie ⌃⌥⌘D. Sam Return nie jest wysyłany do aplikacji.
- **Przytrzymaj** ⌃⌥⌘D: Band·je słucha, dopóki trzymasz klawisze, i wkleja tekst, gdy je puścisz.

Naciśnij Esc, aby anulować. Gdy Band·je słucha, ikona na pasku menu robi się pomarańczowa, a obok widać czas. Jedno dyktowanie może trwać do pięciu minut; w ostatnich 30 sekundach czas miga.

### Wklejanie
Tekst zawsze trafia do schowka. Aby wkleić go za Ciebie, Band·je potrzebuje pozwolenia na wysłanie naciśnięcia klawisza (⌘V): wybierz **Włącz automatyczne wklejanie…** w menu albo przejdź do Ustawienia systemowe > Prywatność i ochrona > Dostępność i włącz Band·je. Bez tego wklejasz samodzielnie przez ⌘V.

macOS informuje działające Band·je o tym pozwoleniu dopiero po ponownym uruchomieniu. Dopiero je włączono? Wybierz **Uruchom Band·je ponownie, by wklejać automatycznie** w menu albo **Uruchom Band·je ponownie** w [Ustawienia](#settings).

Jeśli zamiast wklejenia słyszysz krótki dźwięk, pole hasła lub inna aplikacja włączyła bezpieczne wprowadzanie (Bezpieczne wprowadzanie z klawiatury w Terminalu, menedżer haseł). macOS blokuje wtedy wklejanie; tekst jest w schowku, więc naciśnij ⌘V samodzielnie.

Nic, co dyktujesz, nie jest zapisywane.

## Podsumowania {#summaries}
Band·je może podsumować rozmowę w wybranej przez Ciebie formie, z Apple Intelligence na Twoim Macu.

Podsumowania wymagają macOS 26 lub nowszego z włączonym Apple Intelligence. Bez tego menu **Podsumuj** się nie pojawia, a Band·je działa jak zwykle.

1. Wybierz **Podsumuj** w menu.
2. W sekcji **Wybierz szablon** wybierz jeden. Band·je podsumuje bieżące nagranie. Aby podsumować inne, najpierw wybierz je w **Ostatnie nagrania**.
3. Gdy Band·je pracuje, na pasku menu widać fioletowe iskierki. Wskaż je, aby zobaczyć postęp.
4. Po zakończeniu na kasecie pojawia się mały zielony znaczek, a menu pokazuje **Streszczenie gotowe**. Jeśli okno Band·je jest otwarte, pokazuje nagranie.

Możesz też zacząć w [oknie Band·je](#player): wybierz **Podsumuj** obok kart i wybierz szablon.

Podsumowanie jest zapisywane obok transkrypcji jako `<nazwa> podsumowanie <szablon>.md`. Podsumowanie trwa od kilku sekund do około minuty. Długie rozmowy są podsumowywane w częściach.

Podsumowanie jest pisane w języku rozmowy. Apple Intelligence podsumowuje po angielsku, niderlandzku, niemiecku, francusku, hiszpańsku, włosku, portugalsku i w kilku innych językach, ale jeszcze nie po polsku, rosyjsku ani ukraińsku.

Model na Twoim Macu jest mały. Trzyma się tego, co zostało powiedziane, ale może pominąć szczegóły. Ważne fakty sprawdzaj w transkrypcji.

Band·je ma cztery szablony: spotkanie, rozmowę o pracę, wywiad z klientem i ogólne podsumowanie. Aby utworzyć własny, zobacz [Tworzenie szablonu](#templates).

## Tworzenie szablonu {#templates}
Utwórz własny szablon podsumowań: plik tekstowy z nagłówkami, które chcesz.

Szablon to zwykły plik tekstowy (`.md` lub `.txt`) w `~/Music/Bandje/Templates`. Nazwa pliku staje się nazwą w menu **Podsumuj**.

Najszybciej: gdy okno Band·je jest otwarte, wybierz na pasku menu **Podsumuj** > **Nowy szablon**. Band·je tworzy nowy szablon z dwoma nagłówkami i go otwiera; zmień go, zachowaj i nadaj mu własną nazwę w Finderze.

### Zacznij od kopii
Najprościej skopiować przykład i go zmienić:

1. Wybierz **Podsumuj** > **Otwórz folder szablonów**.
2. Zaznacz przykład najbliższy temu, czego chcesz, np. `Meeting.md`.
3. Wybierz Plik > Duplikuj (⌘D) w Finderze i zmień nazwę kopii, np. na `Cotygodniowy standup.md`.
4. Otwórz kopię w TextEdit lub innej aplikacji do tekstu, zmień nagłówki i zachowaj.

Nowy szablon od razu jest w menu **Podsumuj**. Możesz też zmienić same przykłady lub je usunąć: Band·je przywróci je tylko wtedy, gdy usuniesz cały folder Templates.

### Co zawiera szablon
Listę nagłówków, każdy z linijką o tym, co ma się pod nim znaleźć:

- `## Decyzje` z linijką „Każda decyzja jako punkt. Podaj, kto zdecydował.”
- `## Zadania` z linijką „Kto, co i do kiedy.”

Wskazówki:

- Pisz konkretnie. „Oczekiwania płacowe z dokładnymi kwotami” działa lepiej niż „Wynagrodzenie”.
- Ogranicz się do około pięciu nagłówków. Model na Twoim Macu jest mały: mniej nagłówków daje lepsze odpowiedzi.
- Dopisz „jeśli o tym mówiono”, gdy coś może się nie pojawić, aby Band·je tego nie zmyślił.
- Nagłówki zostają takie, jak je napiszesz. Tekst jest w języku rozmowy.

## Mikrofon i dźwięk {#devices}
Wybierz mikrofon i miejsce, do którego trafia dźwięk z Maca, prosto z menu.

### Mikrofon
Menu **Mikrofon** zawiera wszystkie mikrofony. Używany jest zaznaczony, a jego nazwa widnieje pod pozycją menu. Wybór mikrofonu zmienia go dla całego Maca, więc aplikacja do rozmów używa tego samego. Przy zamkniętej pokrywie wbudowany mikrofon jest wyłączony; Band·je to oznacza.

### Wyjście dźwięku
Menu **Wyjście dźwięku** zawiera wszystkie urządzenia, które mogą odtwarzać dźwięk, i ustawia wyjście dźwięku Maca. Band·je nigdy nie zmienia go samo.

Niektóre mikrofony USB mają gniazdo słuchawkowe i też liczą się jako głośniki. Gdy AirPods się rozłączą, macOS może wysłać dźwięk właśnie tam. Wybierz swoje głośniki w Wyjście dźwięku, aby to naprawić.

## Ustawienia {#settings}
Skróty, folder nagrań, uprawnienia, otwieranie po zalogowaniu i język Band·je.

Wybierz **Ustawienia…** w menu.

### Ogólne
Włącz **Otwieraj Band·je po zalogowaniu**, a Band·je sam pojawi się na pasku menu po zalogowaniu. **Zawsze w Docku** trzyma Band·je w Docku, także bez okna. Możesz to też wybrać w oknie powitalnym przy pierwszym otwarciu Band·je. Opcja jest wyłączona, dopóki jej nie włączysz. Gdy wyłączysz ją w Ustawienia systemowe > Ogólne > Rzeczy i rozszerzenia otwierane podczas logowania, Band·je pokaże to tutaj. Wyłącz **Pokazuj okno Band·je przy uruchomieniu**, a Band·je przy uruchomieniu zostanie na pasku menu.

Band·je używa języka macOS. Aby używać innego języka tylko w Band·je, wybierz go tutaj i kliknij **Uruchom Band·je ponownie**. Zmienią się menu, okna, nowe transkrypcje i Pomoc. **Jak w macOS** przywraca język systemu.

### Skróty klawiszowe
Kliknij pole i naciśnij nową kombinację. Musi zawierać ⌘, ⌃ lub ⌥ albo być klawiszem funkcyjnym. Esc anuluje, **Przywróć domyślne** przywraca ⌃⌥⌘R i ⌃⌥⌘D.

Jeśli inna aplikacja już używa tej kombinacji, Band·je Cię o tym poinformuje i zachowa poprzednią.

### Dźwięk
Wybierz **Mikrofon** i **Wyjście dźwięku**, tak jak w menu Band·je. Dotyczy to wszystkich aplikacji, także rozmów.

### Transkrypcja
**Transkrybuj automatycznie** transkrybuje każde nagranie, gdy tylko je zatrzymasz. **Rozpoznawaj mówców** rozróżnia kilka głosów (Mówca 1, Mówca 2…); po wyłączeniu dostajesz tylko Ja i Druga strona. Język Band·je rozpoznaje sam.

### Przechowywanie
Włącz **Synchronizuj przez iCloud**, a nagrania, transkrypcje, podsumowania i szablony będą w iCloud Drive › Band·je, na iPhonie i innych Macach z tym samym Kontem Apple. Nagranie powstaje najpierw na Macu i trafia do iCloud po zakończeniu. Band·je zapyta, czy przenieść też istniejące nagrania. Po wyłączeniu folderem nagrań znów jest Twój własny folder; nic nie jest usuwane z iCloud, a Band·je zaproponuje skopiowanie nagrań z powrotem. Apple szyfruje iCloud Drive end-to-end, gdy włączona jest Zaawansowana ochrona danych.

Kliknij **Zmień…** i wybierz folder w dowolnym miejscu na Macu lub na dysku zewnętrznym. Trafiają tam nowe nagrania i transkrybowane pliki. Istniejące nagrania zostają na miejscu, podobnie jak szablony i modele mowy. **Użyj ~/Music/Bandje** wraca do standardowego folderu.

Jeśli folder jest w iCloud Drive, Dropbox lub innej usłudze chmurowej (także Biurko i Dokumenty, gdy są w iCloud), Band·je Cię ostrzeże: nagrania opuszczają wtedy Maca przez tę usługę.

### Dostęp
Czy Band·je może używać mikrofonu, wklejać za ciebie i nagrywać dźwięk z Maca, każde z własnym przyciskiem (**Zezwól…** lub **Otwórz ustawienia…**). Zielony znacznik oznacza zgodę; stan odświeża się sam, gdy wracasz z Ustawień systemowych. Zobacz [Rozwiązywanie problemów](#troubleshooting).

## Prywatność i sieć {#privacy}
Twój dźwięk, transkrypcje i podsumowania nigdy nie opuszczają Maca.

- Bez konta, bez analityki, bez śledzenia. Bez naszego serwera.
- iCloud tylko wtedy, gdy włączysz [Synchronizuj przez iCloud](#settings): nagrania są wtedy w Twoim własnym iCloud Drive, tak jak inne pliki. Band·je nigdy ich nie widzi.
- Wszystko jest przechowywane w folderze nagrań: `~/Music/Bandje`, chyba że wybierzesz inny. Usuń folder i już go nie ma. Jeśli wybierzesz folder w iCloud Drive lub innej usłudze chmurowej, nagrania trafią do tej usługi; Band·je najpierw Cię ostrzeże.
- Transkrypcja, rozpoznawanie mówców i dyktowanie działają na Twoim Macu.
- Podsumowania korzystają tylko z modelu Apple Intelligence na Twoim Macu, nigdy z Private Cloud Compute Apple.

Silnik mowy od Desert Ant Labs sprawdza licencję przez sieć: najwyżej raz w miesiącu dla każdego modelu mowy. Wysyła losowy identyfikator instalacji, wersję modelu i silnika oraz identyfikator aplikacji. Nigdy dźwięku, nigdy tekstu. Pokazuje to też **Band·je – informacje**.

## Pamięć i miejsce na dysku {#resources}
Band·je jest lekki: zajmuje około 60–70 MB pamięci podczas działania.

Modele mowy są dołączone do Band·je: to około 400 MB rozmiaru aplikacji. Band·je sam niczego nie pobiera.

Kilka sekund po uruchomieniu Band·je ładuje model mowy w tle, aby dyktowanie było od razu gotowe. Za pierwszym razem na danym Macu trwa to około 20 sekund, bo macOS optymalizuje model pod Twój procesor. Potem idzie szybko.

Godzina dźwięku zajmuje około 55 MB. Transkrypcja wymaga podczas działania trochę dodatkowej pamięci.

## Rozwiązywanie problemów {#troubleshooting}
Rozwiązania problemów, które mogą się pojawić.

### Najpierw sprawdź uprawnienia
Wiele problemów wynika z brakującego uprawnienia. Wybierz **Ustawienia…** i zajrzyj do sekcji **Dostęp**:

- **Mikrofon**: potrzebny do nagrywania Twojego głosu i do dyktowania.
- **Dźwięk z Maca**: potrzebny do nagrywania drugiej strony. macOS nie pozwala aplikacjom odczytać tego uprawnienia, więc Band·je pokazuje, co działo się podczas ostatniego nagrania: dźwięk docierał albo była cisza. Cisza jest normalna, jeśli nic nie grało.
- **Automatyczne wklejanie**: potrzebne do wklejania podyktowanego tekstu za Ciebie.

Zielony znacznik oznacza zgodę. W przeciwnym razie kliknij **Otwórz ustawienia…**, włącz Band·je i wróć; Band·je zauważy to sam.

Przy każdym uruchomieniu Band·je sprawdza mikrofon i automatyczne wklejanie i informuje, jeśli czegoś brakuje. Nie potrzebujesz automatycznego wklejania? Zaznacz **Nie pokazuj ponownie tego komunikatu** albo wyłącz **Ostrzegaj przy uruchomieniu, gdy czegoś brakuje** w sekcji Dostęp.

### W nagraniu brakuje drugiej strony
macOS nie pozwolił Band·je nagrywać dźwięku z Maca. Przejdź do Ustawienia systemowe > Prywatność i ochrona > Nagrywanie ekranu i dźwięku systemowego i włącz Band·je w sekcji Tylko nagrywanie dźwięku systemowego.

### Brakuje mojego głosu
Sprawdź menu **Mikrofon**. Przy zamkniętej pokrywie wbudowany mikrofon jest wyłączony: wybierz inny. Jeśli Band·je w ogóle nie ma dostępu do mikrofonu, włącz go w Ustawienia systemowe > Prywatność i ochrona > Mikrofon.

### Po wyjęciu AirPods nic nie słyszę
macOS wysłał dźwięk do innego urządzenia, np. mikrofonu USB z gniazdem słuchawkowym. Wybierz swoje głośniki w **Wyjście dźwięku**.

### Transkrypcja to bełkot
Rozmowa jest prawdopodobnie w języku, którego Band·je nie zna. Band·je tego nie rozpozna, więc zapisuje to, co według niego usłyszał.

### Mówców jest więcej, niż było
Menu telefoniczne, muzyka w oczekiwaniu i słabe połączenia mogą zmylić rozpoznawanie mówców. Nadaj etykietom właściwe imiona w [Nazwij mówców](#speakers).

### W menu nie ma Podsumuj
Podsumowania wymagają macOS 26 lub nowszego z Apple Intelligence włączonym w Ustawienia systemowe > Apple Intelligence i Siri. Język Maca i język Siri muszą być takie same.

### Skrót nie działa
Inna aplikacja może używać tej samej kombinacji. Wybierz inną w [Ustawienia](#settings).

## Band·je – informacje {#about}
Band·je tworzy Neurendal B.V. w Holandii.

Rozpoznawanie mowy i mówców: Voz i Who od Desert Ant Labs, na podstawie NVIDIA Parakeet TDT 0.6B v3 i pyannote community-1 (CC BY 4.0). Podsumowania: Apple Intelligence.

Wybierz **Band·je – informacje** w menu, aby zobaczyć wersje i linki.
