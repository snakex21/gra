# Etap 10 — ciągły świat, Hydrus, wspólna baza czworonogów, narzędzia powtórek

Zakres (propozycja z Etapu 9, przyjęta w całości):

1. **Ciągły świat**: areny wewnątrz świata doliny, wjazd do areny bez wygaszenia.
2. **`QuadrupedBoss`**: wspólna baza czworonogów; Quadratus i Phaedra jako rodzeństwo.
3. **Piąty kolos**: wybrałem pływającego – **Hydrus**, wąż w jeziorze. Przy okazji
   doszło **pływanie gracza**.
4. **Powtórki do playtestu**: przewijanie, prędkość, swobodna kamera, zgłoszenie błędu
   jednym klawiszem (F9).
5. **Menu**: sloty zapisu, zmiana klawiszy, głośność.
6. Soaki: zróżnicowane całe gry (pięć kolosów) i walki z każdym kolosem.

## 1. Ciągły świat (`src/world/world_map.gd`, `src/game/game_world.gd`)

```
            Gaius            Quadratus
               \\              /
 Hydrus ── [ dolina 360 × 360 m ] ── Phaedra
                     |
                   Valus
```

- **Bramy stoją w krawędzi doliny** i są jedynymi otworami w niej. Za każdą prosty
  korytarz prowadzi do obręczy areny.
- **Areny mają w świecie swoje miejsce**: dyski o promieniu 175 m, 193–280 m za bramą,
  które nie nachodzą na dolinę ani na siebie (test).
  - Wysokość areny to wysokość terenu doliny tam, gdzie korytarz z niej wychodzi.
    Valus leży na 0 m, Phaedra na ~20 m, Hydrus na ~19 m.
  - Arena zachowuje swój lokalny układ (kolos w środku, wejście od +Z). Budowniczy aren
    działają w obróconym korzeniu, a w kodzie walk nic nie zakładało środka świata.
    Znalazł się jeden wyjątek: bot Phaedry porównywał wysokość z zerem.
- **Obręcz areny**: niewidzialny pierścień z jednym otworem, tam gdzie wchodzi korytarz.
  Ściany korytarza mają 7 m: na tyle nisko, żeby słońce sięgało podłogi, bo bez niego
  promień miecza w korytarzu by nie działał.
- **Horyzont**: własna siatka bez kolizji zamiast tej z paczki doliny. Pod arenami
  i korytarzami opada, a między nimi wznosi się w grzbiety, więc areny leżą w nieckach.
- **Jeden gracz, jeden Agro, jedna kamera** przez całą grę. Świat buduje się raz
  (~1,2 s z grafiką).
  - Przejście przez otwartą bramę **budzi kolosa**, czyli tworzy go w jego arenie.
  - Powrót przez bramę do doliny **usypia go**: kolos znika, a walka zaczyna się od nowa.
  - Naraz istnieje najwyżej jeden kolos.
- **Wygaszenie zostało tylko po zwycięstwie**: powrót do świątyni, jak w oryginale.
- **Bot całej gry** po przebudzeniu kolosa jedzie dalej korytarzem za promieniem (ten
  wskazuje już kolosa) i oddaje walkę botowi kolosa dopiero w arenie.

## 2. `QuadrupedBoss` (`src/colossus/greybox/quadruped_boss.gd`)

- Całe zachowanie czworonoga w walce przeszło z Quadratusa do bazy: przebieg spotkania,
  ataki, potrząsanie, uginanie trafionej nogi, weak pointy, fairness i poza.
- **Quadratus** ma teraz 116 linii (wcześniej 1053): anatomię, mózg, weak pointy i trasę
  wspinaczki.
- **Phaedra** dziedziczy bezpośrednio po bazie.
- Soaki z tymi samymi seedami dają przed podziałem i po nim **identyczne wyniki** (czasy,
  upadki, wszystko).

## 3. Hydrus i pływanie

### Pływanie (`PlayerCharacter.State.SWIM`, `src/world/water_body.gd`)

- **WaterBody**: dysk wody bez kolizji. Woda jest tam, gdzie teren w dysku leży niżej niż
  tafla. Działa w każdej scenie, także w jeziorze w dolinie, gdzie dotąd chodziło się
  po dnie.
- **Pływanie zaczyna się** od 1,35 m wody nad stopami. Ciało unosi się z głową nad
  powierzchnią, a gracz płynie powoli (2,2 m/s) tam, gdzie patrzy.
- **Skok do wody** nie zadaje obrażeń przy upadku.
- **Na płyciźnie** gracz wychodzi z wody i znowu idzie.
- Z wody da się **chwycić** (bok płynącego kolosa).
- **Trzymanie się pod wodą** zużywa 1,6× więcej staminy (wstrzymany oddech).
- Miecz, łuk i promień nie działają w wodzie.
- **Agro nie pływa**: głęboką wodę (ponad 1 m) traktuje jak urwisko i staje na brzegu.

### Hydrus (`src/colossus/hydrus/`, `src/world/hydrus_arena.gd`)

- **Ciało**: wąż ~45 m z głowy i 9 segmentów.
  - Segmenty leżą na śladzie, który zostawia głowa (punkt co 0,5 m, jedno przejście na
    tick), z falą wzdłuż ciała rosnącą ku ogonowi.
  - Nie ma nóg ani IK, więc koszt wynosi tylko ~130 µs/tick.
- **Futro**: na całym grzbiecie (da się po nim chodzić) i w kępach na bokach co drugiego
  segmentu. Kępy sięgają od wody do grzbietu i tworzą jedną ciągłą drogę z wody na górę.
- **Pętla walki**:
  1. Hydrus krąży po jeziorze między filarami i omija je trzema czujkami na szerokość
     ciała.
  2. Gracz czeka w wodzie albo na filarze. Na filary wchodzi się po pnączach.
  3. Gdy Hydrus przepływa, gracz chwyta kępę i wspina się na grzbiet.
  4. Na grzbiecie są trzy świecące punkty do zniszczenia.
- **Taran**: pływaka w pobliżu Hydrus taranuje.
  - Najpierw unosi głowę (zapowiedź ~1,6 s), potem rusza z prędkością 7 m/s.
  - Kto w czasie zapowiedzi odpłynie w bok, nie zostanie trafiony (test).
- **Nurkowanie**: najpierw ~1,5 s uniesionej głowy z rykiem, potem całe ciało schodzi
  pod wodę.
  - Zanurzenie biegnie wzdłuż ciała, a nurkowanie kończy się dopiero, gdy wypłynie ogon.
  - Pod wodą trzeba się trzymać, na jednym segmencie ~5 s.
- **Fairness**:
  - nurkowanie dopiero po 6 s na grzbiecie, gdy wspinacz ma co najmniej 60% staminy,
    nie w ciągu 5 s po trafieniu, i 12 s przerwy między nurkowaniami;
  - nie taranuje nikogo, kto jest na nim;
  - kołysanie (±0,25 rad) podlega wspólnym limitom potrząsania.
- **Arena**: jezioro w niecce (płycizna, stromy brzeg, 9 m głębokości w środku) i sześć
  filarów. Leży za piątą bramą na zachodniej krawędzi doliny.
- **Bot** (`HydrusBot`):
  - czeka w wodzie i odpływa w bok przed taranem;
  - płynie do najbliższej kępy, gdy Hydrus jest wolny, i wspina się na grzbiet;
  - podchodzi do punktu i uderza;
  - trzyma się dopiero wtedy, gdy zanurzenie dochodzi do jego segmentu, a nie przez
    całe nurkowanie (tak robiłby człowiek).
- **Przy okazji**: gracz wciśnięty przez ciało Hydrusa w filar utykał w jego kolizji.
  Teraz każdy gracz uwięziony w statycznej geometrii dłużej niż pół sekundy zostaje
  wypchnięty w górę, na wolne miejsce.
- **Scena**: `scenes/hydrus_arena.tscn`.

## 4. Powtórki (`src/game/replay_viewer.gd`)

- **Uruchomienie**: `godot --path . -- --replay=user://replays/last.replay`.
- **Sterowanie**:
  - K: pauza;
  - J / L: 10 s wstecz / naprzód;
  - [ / ]: prędkość ×0,25 … ×4;
  - F7: swobodna kamera (WASD, Q/E, strzałki, Shift szybciej).
- **Przewijanie wstecz** buduje świat od początku nagrania i biegnie do celu
  przyspieszony ×16.
- **Determinizm**: w Godocie 4 `Engine.time_scale` wydłuża krok fizyki, co zepsułoby
  determinizm. Dlatego przeglądarka zmienia razem `time_scale` i
  `physics_ticks_per_second` o potęgę dwójki. Krok zostaje wtedy **bitowo** równy 1/60 s,
  a nagranie odtwarza się identycznie także przy przewijaniu (test: stany w 15 i 30 s
  równe nagraniu, po skoku w przód, w tył i znowu w przód).
- **F9 w grze**: zapisuje dotychczasowe nagranie i krótkie podsumowanie JSON (region,
  postęp, pozycja i stan gracza) do `user://replays/report_<data>.*`.

## 5. Menu

- **Sloty zapisu**: trzy. Slot 1 to dawny plik zapisu, więc stare zapisy dalej działają.
  - Tytuł: Kontynuuj (ostatni slot), Nowa gra (wybór slotu), Wczytaj, Ustawienia,
    Wyjście.
  - Slot pokazuje stan gry, np. „Slot 2 — 3/5 kolosów, 42 min”.
- **Głośność** (główna szyna dźwięku).
- **Sterowanie**: każda akcja z listy pokazuje swoje klawisze. Kliknięcie, a potem
  wciśnięcie klawisza lub przycisku myszy zmienia przypisanie (Esc anuluje). Pad zachowuje
  swoje przyciski. Można wrócić do domyślnych.
- Wszystko trafia do `user://settings.json`.

## Wyniki

### Testy

Pełny przebieg `tools/run_tests.sh`: **184/184 PASS** (166 wcześniejszych + 18 nowych).

| Test | Wynik |
|---|---|
| `world_layout_keeps_arenas_apart_and_connected` | 5 aren; najbliższa para 6 m od siebie poza dyskami; podłogi korytarzy z dokładnością do 0,03 m, największy stopień 0,06 m na 2 m; obręcze zamknięte (po 36 promieni), wejścia otwarte |
| `world_ride_from_valley_into_fight_without_fade` | ze świątyni do walki w 44,8 s gry: bez wygaszenia, jeden gracz, najwyżej jeden kolos |
| `world_leaving_puts_the_colossus_to_sleep` | za bramą: 1 kolos; z powrotem w dolinie: 0; ponownie za bramą: nowy, cały |
| `world_ride_independent_of_render_fps` | świątynia → brama → korytarz → 20 s walki z Valusem przy 30/60/144/240 FPS: różnica 0,00000000, wygaszenie 0 |
| `quadruped_bosses_share_one_base` | QuadrupedBoss → Quadratus (116 linii), Phaedra; walki bez zmian |
| `player_swims_in_the_valley_lake` | skok z 6 m: pływanie, bez obrażeń; głowa 0,24 m nad wodą; 2,2 m/s; wyjście na brzeg; Agro staje w 0,52 m wody |
| `hydrus_swims_round_the_lake_past_the_pillars` | 204 m w 60 s, ciało nie bliżej niż 4,6 m od filara, stała głębokość |
| `hydrus_ram_is_telegraphed_and_can_be_dodged` | zapowiedź 1,65 s; nieruchomy pływak trafiony (-30), odpływający w bok nie |
| `hydrus_dive_is_telegraphed_and_survivable` | nurkowanie 6 s po wejściu na grzbiet, 4,9 s pod wodą, trzymanie się wystarcza (stamina ≥ 27) |
| `hydrus_can_be_defeated` | bot wygrywa w 70,7 s |
| `hydrus_simulation_independent_of_render_fps` | walka botem przy 30/60/90/144/240 FPS: różnica 0,00000000 |
| `hydrus_cost_stays_within_budget` | kolos 136 µs/tick, gracz 93 µs |
| `five_colossi_in_order_with_west_gate` | zapis z Etapu 9 (cztery kolosy) prowadzi przez zachodnią bramę do Hydrusa |
| `replay_viewer_seeks_back_and_forth_exactly` | 40 s nagrania; do 30 s w 1,4 s (×16), do 15 s, znów do 30 s: wszystko bitowo jak w nagraniu |
| `menu_slots_volume_and_rebinding` | głośność 0,3 → -10,5 dB; skok przestawiony na K (pad zostaje); domyślne wracają; opisy slotów |
| `bug_report_saves_the_recording` | F9 zapisuje nagranie i podsumowanie JSON |
| `temple_way_out_is_walkable` | prosto przez łuk w trzech miejscach: wyjście bez zacięcia |
| `all_etap9_and_earlier_tests_still_pass` | 166 wcześniejszych, 0 porażek |

Porównanie z zamrożonymi wzorcami nadal flaguje 7 metryk czasu z sandboxa Etapu 2 (to
samo co w Etapie 9: stary wzorzec, nie zmiana z tego etapu).

### Soak

- **Cała gra z pięcioma kolosami, zróżnicowana** (`tests/game_soak.gd`, 3 × 34):
  **102/102 gier ukończonych**, 0 zatrzymań bota.
  - Agro stoi za każdym razem gdzie indziej, a pierwszy odcinek jazdy idzie w losową
    stronę doliny.
  - Od świątyni do końca: min 666 / mediana 766 / max 1024 s.
  - 26 śmierci na 102 gry, wszystkie w walkach. Mediany walk: Valus 47 s, Quadratus 78 s,
    Gaius 54 s, Phaedra 85 s, Hydrus 59 s.
  - Zróżnicowanie od razu znalazło trzy prawdziwe błędy (niżej) i dwa błędy bota.
    Wcześniejsze przebiegi na kodzie przed poprawkami: 100/102, a pierwszy 0/4, bo wszyscy
    utknęli w wyjściu ze świątyni.
- **Hydrus** (`tools/run_boss_soak.sh 100 1 hydrus`): **100/100 wygranych**, 0 śmierci,
  0 zakleszczeń, 0 skoków obrazu.
  - Czas: min 61,6 / mediana 72,3 / max 169,3 s.
  - 131 nurkowań, najdłużej pod wodą 9,3 s. 186 uników przed taranem, 0 trafień taranem.
  - Pierwszy przebieg wyłapał start za plecami Agro: bot przez całą walkę pchał konia.
    Poprawione.
- Quadratus i Phaedra: po wydzieleniu `QuadrupedBoss` te same seedy dają te same wyniki
  co przed zmianą. Soaki z Etapu 9 (Phaedra 100/100) i Etapu 7 nadal obowiązują.

**Błędy znalezione przez soaki i poprawione:**

- **Wyjście ze świątyni.** Kolizja schodów w paczce doliny wznosi się od świątyni
  i kończy uskokiem 2,6 m, więc środkiem wyjścia nie dało się przejść. Teren pod
  schodami już jest łagodnym zejściem, więc kolizję schodów wyłączyłem (test). **Do
  zgłoszenia agentowi graficznemu.**
- **Ukośna brama** (Quadratus) budziła kolosa, gdy gracz stał jeszcze w dolinie obok
  korytarza. Do tego między krawędzią a ścianą korytarza była szczelina poza świat.
  - Otwór bramy jest teraz tam, gdzie ściany korytarza przecinają krawędź; tam stoją
    filary, nadproże i mgła.
  - Za bramą jest się dopiero po przekroczeniu krawędzi w świetle bramy.
- **Gracz wciśnięty w filar** przez ciało Hydrusa utykał w kolizji. Teraz zostaje
  wypchnięty w górę.
- **Boty**: utknięcie liczy się teraz po faktycznym przesunięciu, nie po prędkości
  (ślizg przy ścianie daje prędkość bez ruchu). Wtedy bot obchodzi przeszkodę, woła Agro
  albo wsiada, gdy koń jest w zasięgu.

### Wydajność

- Hydrus: ~130 µs/tick. Pierwsza wersja kosztowała 1274 µs, bo ślad głowy miał punkt
  w każdym ticku.
- Świat z grafiką (dolina, 5 aren, korytarze, horyzont) buduje się raz w ~1,2 s, bez
  grafiki w ~0,5 s.
- Przewijanie powtórki: 30 s gry w ~1 s (×16).

## Ograniczenia

- **Areny są zawsze zbudowane**: geometria i grafika wszystkich pięciu, choć kolos
  istnieje tylko jeden. Przy większym świecie trzeba będzie doczytywać areny w tle.
- **Korytarze są proste** i wąskie: spójne z kierunkiem promienia, ale mało
  krajobrazowe.
- **Hydrus**:
  - kształty to greybox, bez modelu od agenta graficznego;
  - woda to płaski przezroczysty dysk, bez fal i bez efektów pod wodą;
  - gracz nie nurkuje sam, tylko pływa po powierzchni.
- **Odtwarzanie** wymaga tej samej wersji gry. Nie ma jeszcze paska czasu ani
  znaczników.
- **Zmiana klawiszy** dotyczy klawiatury i myszy; pad ma stałe przypisania.

## Propozycja Etapu 11

1. **Latający kolos**: ptak, który krąży nad ruinami i nurkuje na gracza na wysokiej
   wieży. Chwyta się go za skrzydło, gdy przelatuje nisko, a spadek kończy się w wodzie.
   Wymaga lotu po krzywych, wspinaczki na bardzo szybkim ciele i kamery w powietrzu.
2. **Doczytywanie aren w tle** (geometria i grafika), żeby świat mógł rosnąć.
3. **Nurkowanie gracza**: zanurzanie się na przycisk, oddech, światło pod wodą.
4. **Pasek czasu w powtórkach**: znaczniki zdarzeń (śmierć, trafienie, upadek), skok
   do zdarzenia, eksport krótkiego klipu do zgłoszenia.
5. **Playtest z człowiekiem** na nagraniach F9: lista do sprawdzenia poniżej.

## Lista do playtestu

- Czy przejazd z doliny przez korytarz do areny jest czytelny (ściany, światło, kolos
  w oddali)?
- Hydrus: czy da się samemu wpaść na kępy na boku? Czy zapowiedź taranu i nurkowania
  wystarcza?
- Pływanie: tempo 2,2 m/s, wyjście na brzeg, filary z pnączami.
- Menu: zmiana klawiszy i sloty na padzie i z klawiatury.
