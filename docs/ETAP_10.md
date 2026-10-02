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

WYNIK_TESTOW

### Soak

WYNIKI_SOAK

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
