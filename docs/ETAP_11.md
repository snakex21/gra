# Etap 11 — Avion (latający kolos), nurkowanie, znaczniki w powtórkach, areny budowane po starcie

Zakres (propozycja z Etapu 10, przyjęta w całości; bez ponownych soaków starych walk,
tylko testy regresji):

1. **Latający kolos**: **Avion**, wielki ptak nad jeziorem z kamiennymi wieżami. Pikuje
   na gracza na wieży, a ten łapie go za skrzydło.
2. **Areny budowane po starcie**: świat rusza szybciej, areny dobudowują się w kolejnych
   tickach.
3. **Nurkowanie gracza**: zanurzanie na przycisk, oddech, widok pod wodą.
4. **Znaczniki w powtórkach**: śmierć, trafienie, upadek, obszar, pokonanie, zgłoszenie;
   skok do znacznika, wycinek (klip) do zgłoszenia.
5. **Wsparcie playtestu**: `--seek=` przy odtwarzaniu, lista do sprawdzenia niżej.

## 1. Avion (`src/colossus/avion/`, `src/world/avion_arena.gd`)

### Ciało i lot

- **Ciało**: sztywny tułów, szyja, głowa, ogon-wachlarz i dwuczęściowe skrzydła
  (rozpiętość ~30 m), które biją w barkach i łokciach. Futro na grzbiecie, ogonie
  i wierzchu skrzydeł; tułów i głowa z kamienia.
- **Lot po gładkiej ścieżce**: ograniczony skręt (0,55 rad/s), ograniczone wznoszenie
  i opadanie, przyspieszanie i hamowanie, przechył w zakręcie. Ptak nigdy nie schodzi
  niżej niż 3 m nad wodę poza nurkowaniem.
- **Koszt**: ~80 µs/tick (bez nóg i IK, jak Hydrus).

### Pętla walki

1. Avion krąży wysoko (32 m) nad jeziorem. Gracz płynie do jednej z pięciu wież
   i wspina się po pnączach na płaski szczyt.
2. **Zapowiedź**: krzyk i przechył w stronę gracza, 1,6 s.
3. **Nurkowanie**: zakręca ostrzej (skrzydła złożone), ustawia się w linii przelotu
   i zwalnia do 4,5 m/s w najniższym punkcie. Wewnętrzne skrzydło przechodzi wtedy
   ~0,9 m nad głową gracza na wieży (test).
4. **Chwyt**: trzymając chwyt, gracz podskakuje w futro skrzydła, obchodzi przednią
   krawędź na wierzch i idzie po grzbiecie.
5. **Trzy punkty**: na obu wewnętrznych skrzydłach i na ogonie.
6. **Z jeźdźcem** Avion leci jak szybowiec: płasko (pochylenie do 0,18 rad, przechył do
   0,3 rad), w kręgu 24 m wokół środka jeziora. Upadek kończy się w wodzie, bo wieże
   stoją dalej (45–51 m).
7. **Kołysanie** (`SHAKE_BODY`) według wspólnych zasad potrząsania: najwcześniej 3 s po
   wejściu, nie w ciągu 4 s po trafieniu i tylko nad wodą.
8. Po pokonaniu Avion szybuje w dół i siada na wodzie.

### Fairness

- Nie pikuje na nikogo, kto na nim siedzi. Zapowiedź przerywa, jeśli ktoś wejdzie na
  niego wcześniej. Między nurkowaniami jest 7 s przerwy.
- Nurkowanie, które nie trafi w linię przelotu w 7 s (cel się ruszył, zakręt za
  ciasny), kończy się wzlotem i nową próbą później.
- Nie pikuje na pływaka, tylko na kogoś na wieży albo na brzegu.

### Arena

- Jezioro o promieniu 98 m w niecce (8 m głębokości), brzeg dookoła i pięć wież
  (szczyt 9 m nad dnem, ~10 m nad wodą). Każda wieża ma pnącza z czterech stron, od
  wody do krawędzi szczytu.
- Pnącza kończą się 0,3 m pod krawędzią, więc wspinaczka kończy się podciągnięciem na
  szczyt. Wcześniej gracz „wchodził” na płaski koniec pnącza i wisiał tam, aż zabrakło
  mu staminy.
- Leży za szóstą bramą na południowym zachodzie doliny, najdalej ze wszystkich (373 m,
  korytarz ~200 m).
- Scena: `scenes/avion_arena.tscn`.

### Bot (`AvionBot`)

`ENTER → SWIM → TOWER → WAIT → HANG → ON_BACK → STRIKE`:

- płynie do najbliższego pnącza (zmęczony czeka w wodzie, aż złapie oddech);
- wspina się na wieżę i czeka na środku szczytu, patrząc na ptaka;
- przy przelocie trzyma chwyt i podskakuje, gdy spód skrzydła jest nad głową;
- z dołu skrzydła idzie do przedniej krawędzi, przez nią na wierzch, potem do tułowia;
- puszcza chwyt i staje tylko wtedy, gdy ptak leci płasko; przy kołysaniu się trzyma;
- podchodzi do punktu i uderza.

## 2. Areny budowane po starcie (`GameWorld.lazy_arenas`)

- Na starcie powstaje dolina, korytarze, obręcze aren i horyzont. Zawartość aren (teren
  i układ, a potem grafika) dobudowuje się **po jednym kroku na tick**, najpierw arena
  następnego kolosa.
- Kolos, który budzi się przed ukończeniem swojej areny, dostaje ją od razu w całości
  (`ensure_arena`).
- Start trwa krócej: ~0,8 s zamiast ~1,1–1,4 s z grafiką. Areny są gotowe po
  12 tickach, a najdłuższy krok to ~50–110 ms.
- Areny zbudowane po kolei są identyczne z tymi zbudowanymi naraz (test porównuje
  liczbę kształtów kolizji i siatek).
- Determinizm zostaje: budowa idzie w tickach fizyki, więc powtórka buduje w tych
  samych tickach.

## 3. Nurkowanie i oddech (`PlayerCharacter`)

- **Nurkuj**: Ctrl / Z / B na padzie (do zmiany w menu). Trzymany w wodzie: gracz
  schodzi w dół 2,2 m/s i płynie wolniej (1,9 m/s). Puszczony: wypływa.
- **Oddech**: 14 s pod wodą, wraca 5 s na sekundę nad wodą. Pokazuje go niebieski
  pierścień wewnątrz pierścienia staminy (tylko gdy coś ubyło).
- Bez powietrza woda zadaje 12 obrażeń na sekundę, a nurek sam wypływa.
- Oddech liczy się też przy trzymaniu się kolosa pod wodą (Hydrus: najdłużej ~9 s,
  więc bez zmian w walce).
- **Unik**: zanurkowanie, gdy Hydrus unosi głowę do taranu, przepuszcza go górą (test).
- **Pod wodą** obraz robi się zielononiebieski i ciemnieje z głębokością.
- Przy dodawaniu klawisza wyszło, że C już woła Agro. Nowy test pilnuje, żeby żadne dwie
  akcje nie miały domyślnie tego samego klawisza.

## 4. Znaczniki w powtórkach (`ActionReplay`, `ReplayViewer`)

- **Nagranie zapisuje znaczniki** z tickiem: śmierć gracza, trafienie (z przyczyną,
  bliskie trafienia jako jeden), bolesny upadek (prędkość, obrażenia), wejście do
  obszaru, pokonanie kolosa, zgłoszenie F9.
- **Pasek czasu** na dole przeglądarki: całe nagranie, bieżące miejsce i kolorowe
  znaczniki. Nad paskiem: następny znacznik i za ile sekund.
- **`,` / `.`**: skok do poprzedniego / następnego znacznika, 3 s przed nim (żeby
  zobaczyć, co do niego doprowadziło).
- **C**: wycinek: 15 s przed bieżącym miejscem i 5 s po nim, do `user://replays/clip_*.replay`.
  - Wycinek to to samo nagranie z oknem, bo świat da się odtworzyć tylko od początku.
  - Otwarty, sam przewija do początku okna, gra je i staje na końcu.
- **`--seek=<s>`** przy `--replay=`: od razu do danej chwili (np. czasu ze zgłoszenia).
- Stare nagrania (bez nurkowania i znaczników) dalej się odtwarzają.

## Wyniki

### Testy

Pełny przebieg `tools/run_tests.sh`: **197/197 PASS** (184 wcześniejsze + 13 nowych).

| Test | Wynik |
|---|---|
| `avion_circles_high_over_the_lake` | 40 s sam: 560 m lotu, nigdy niżej niż 32,8 m nad wodą, najdalej 70 m od środka, skręt ≤ 0,55 rad/s |
| `avion_swoop_is_telegraphed_and_wing_reaches_the_tower` | 1,6 s krzyku i przechyłu, spód skrzydła 0,87 m od głowy na wieży, w przelocie ≤ 4,5 m/s |
| `avion_glides_over_the_water_with_a_rider` | 35 s na ptaku, pierwsze kołysanie 6,5 s po wejściu, pochylenie ≤ 0,17 rad, ≤ 61 m od środka, bez pikowania z jeźdźcem |
| `avion_can_be_defeated` | bot wygrywa w 243 s, bez śmierci |
| `avion_simulation_independent_of_render_fps` | walka botem przy 30/60/90/144/240 FPS: różnica 0,00000000 |
| `avion_cost_stays_within_budget` | kolos 87 µs/tick (mózg 6,6), gracz 116 µs |
| `six_colossi_in_order_with_south_west_gate` | zapis z Etapu 10 (pięć kolosów) prowadzi przez bramę SW do Aviona; jezioro i 5 wież na miejscu |
| `player_dives_and_holds_breath` | 6,7 m w dół w 4 s, z powrotem w 3,4 s; bez powietrza nurek sam wypływa (zdrowie 100 → 59) |
| `diving_under_the_hydrus_ram` | zanurkowanie przy uniesionej głowie: taran przechodzi górą |
| `replay_markers_jump_and_clip` | znaczniki śmierci i upadku; skok ląduje 3 s przed znacznikiem; wycinek gra swoje okno i staje |
| `arenas_are_built_after_the_start` | start 0,77 s (naraz 1,1 s), 12 ticków dobudowy, najdłuższy 66 ms; areny identyczne |
| `default_keys_do_not_clash` | 13 akcji, 30 klawiszy / przycisków, bez powtórzeń |
| `all_etap10_and_earlier_tests_still_pass` | 184 wcześniejsze, 0 porażek |

Adaptacje starych asercji (bez usuwania testów): opis slotu liczy teraz kolosy z listy
(„1/6 kolosów”), test układu świata najpierw dobudowuje areny, test pięciu kolosów
akceptuje dłuższą listę.

Porównanie z zamrożonymi wzorcami flaguje 8 metryk sandboxa Etapu 2: 7 czasów (jak
w Etapach 9 i 10) i liczbę promieni wspinaczki przy wstrząsie (0,18 wobec 0). Ta ostatnia
jest zaflagowana także na kodzie Etapu 10 uruchomionym osobno (0,42), więc to nie zmiana
z tego etapu.

### Soak

- **Avion** (`tools/run_boss_soak.sh 100 1 avion`, 4 × 25): **100/100 wygranych**,
  0 zakleszczeń, 0 skoków obrazu, 0 złych resetów.
  - Czas: min 105 / mediana 228 / max 571 s.
  - 998 nurkowań (307 przerwanych), 329 chwytów skrzydła, 245 upadków do jeziora.
  - 3 śmierci na 100 walk: upadek z dużej wysokości na szczyt wieży albo brzeg.
- **Cała gra z sześcioma kolosami, zróżnicowana** (`tests/game_soak.gd`, 4 × 6):
  **24/24 gier ukończonych**, 0 zatrzymań bota.
  - Od świątyni do końca: min 948 / mediana 1064 / max 1473 s.
  - Walka z Avionem w grze: min 120 / mediana 172 / max 467 s.
  - 9 śmierci na 24 gry, wszystkie w walkach.
  - Pierwsze przejazdy znalazły błąd: kierunki pnączy wież były podawane botowi
    w układzie areny, a arena Aviona jest w świecie obrócona, więc bot płynął do ściany
    bez pnączy. Teraz są w układzie świata.
- Starych walk nie soakowałem ponownie (zgodnie z ustaleniem); pilnują ich testy
  regresji, a cała gra przechodzi przez wszystkie.

### Wydajność

- Avion: ~80 µs/tick (mózg ~6 µs), gracz ~100 µs.
- Start gry z grafiką: ~0,8 s (wcześniej ~1,1–1,4 s), potem 12 ticków dobudowy aren.

## Ograniczenia

- **Avion**:
  - kształty to greybox, bez modelu od agenta graficznego;
  - ~30% nurkowań kończy się przerwaniem (ptak nie trafi w linię przelotu), więc walka
    trwa dłużej, niż musi (mediana ~4 min z botem);
  - bot czasem spada z ptaka na szczyt wieży albo na brzeg z dużej wysokości
    (3 śmierci na 100 walk). Z jeźdźcem ptak trzyma się środka jeziora, ale upadek
    zaraz po chwycie (przy wieży) nadal może skończyć się na kamieniu.
- **Dobudowa aren**: najdłuższy krok (grafika areny) trwa do ~110 ms, czyli jest
  widoczny jako jedno zacięcie w pierwszych tickach gry. Grafikę można by dzielić
  drobniej.
- **Woda**: nadal płaski dysk; widok pod wodą to tylko kolor nakładki, bez mgły
  i załamania światła.
- **Wycinek** zawiera całe nagranie od początku, bo stanu świata nie da się zapisać
  w połowie. Krótkie okno nie zmniejsza więc pliku.

## Propozycja Etapu 12

1. **Kolos w jaskini**: walka w półmroku (paczki Hollowvault / Deeprelic), światło
   miecza jako latarka, kolos, który chowa się w szczelinach.
2. **Lepszy lot Aviona**: planowanie przelotu z wyprzedzeniem zamiast poprawek w locie,
   mniej przerwanych nurkowań.
3. **Zapis stanu świata** (snapshot), żeby wycinki i przewijanie nie musiały startować
   od początku nagrania.
4. **Dzielona dobudowa grafiki** aren (po kawałku na tick), żeby nie było zacięć.
5. **Woda**: fale, mgła pod wodą, plusk i krople.

## Lista do playtestu

- Avion: czy zapowiedź pikowania (krzyk, przechył) wystarcza, żeby zdążyć się
  przygotować? Czy chwyt skrzydła z wieży jest czytelny (kiedy skoczyć)?
- Avion: czy przejście spod skrzydła na wierzch jest zrozumiałe bez podpowiedzi?
- Nurkowanie: czy 14 s oddechu i pierścień oddechu są dobrze wyważone?
- Powtórki: czy znaczniki i wycinki pomagają znaleźć problem ze zgłoszenia F9?
- Długi korytarz do Aviona (~200 m): czy jazda nie nuży?
