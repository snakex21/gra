# Etap 13 — modele Blender i bezpieczny autozapis

Kampania zawiera 21 grywalnych prototypów starć. Ten etap rozwija ich oprawę oraz
wznawianie podróży. Nie oznacza ukończenia rekonstrukcji 1:1 ani finalnej jakości animacji.

## Postacie

Wędrowiec ma własny model z twarzą, włosami, zdobioną tuniką, peleryną, dłońmi
i butami. Kosmetyczne stawy reagują na chód, jazdę, wspinanie i pływanie. Dotychczasowa
kapsuła gracza, chwyt, miecz i światło pozostają źródłem mechaniki. Mono leży na
rzeczywistym ołtarzu w świątyni; jest elementem sceny, bez systemu zwykłych NPC.

Źródło: `art/source/travelers_v3.blend`. Eksport:
`tools/art/generate_travelers_v3.py`; instrukcja `assets/travelers_v3_integration.md`.
Wędrowiec ma 35 614 / 18 512 / 4 236 trójkątów, Mono 28 576 / 14 858 / 3 414
w trzech kolejnych poziomach szczegółowości. Materiały współdzielą atlasy PBR.

Agro ma koński profil pyska, grzywę, kopyta, siodło i uprząż przypięte do istniejących
kości IK. Dormin zyskuje rogi, ciemną grzywę, pazury i nieregularne kamienne fragmenty.
Ich wspólne źródło to `art/source/agro_dormin_v3.blend`. Agro ma 9 482 / 4 347 / 1 676,
Dormin 17 810 / 8 146 / 3 012 trójkątów. Koń zachowuje położenie siodła,
a Dormin dostęp do obu znaków we wszystkich LOD.

`art/source/colossi_v3.blend` obejmuje pozostałe 20 starć: 21 osobnych sylwetek
z uwzględnieniem obu ciał w starciu Celosia–Cenobia. 187 segmentów daje 561 eksportów
GLB w trzech LOD. Każdy profil ma własne maski, pancerze, futro i ornamenty.
Budżet LOD0 wynosi od 6 596 do 37 252 trójkątów na ciało. Daleki poziom nie znika.
Nowa oprawa działa w kampanii oraz scenach prób. Modele są oryginalnymi,
stylizowanymi interpretacjami dopasowanymi do istniejącej mechaniki.

Przeglądy: `art/screenshots/colossi_v3/`, `data/captures/temple_characters_v3.png`,
`data/captures/agro_v3_full.png`, `data/captures/dormin_v3_front.png`.

## Autozapis

Główna scena zapisuje postęp co 60 sekund czasu symulacji, po zwycięstwach,
przy powrocie do menu oraz przy zwykłym zamknięciu gry. Obok pliku slotu JSON
powstaje plik `.world`, np. `data/save.json.world`, z checkpointem świata.
Wybór „Kontynuuj” odtwarza położenie gracza, Agro i aktualną symulację.

Checkpoint powstaje, gdy gracz żyje i stabilnie stoi na terenie albo siedzi na Agro.
Wspinanie, upadek, pływanie i stanie na kolosie zachowują poprzedni bezpieczny
checkpoint. Postęp kampanii nadal jest zapisywany. Jeśli po ostatnim checkpointcie
pokonano kolosa, starszy plik świata zostaje pominięty, a gra wznawia się w świątyni
z zachowanym zwycięstwem. Nowa gra usuwa checkpoint wybranego slotu.

Pliki powstają atomowo przez lokalny plik tymczasowy i zmianę nazwy. Całość
pozostaje w folderze gry; brak prawa zapisu wyświetla komunikat, bez przejścia
do profilu użytkownika. Nagrania i autozapis korzystają z tego samego kodeka
świata, ale mają osobne pliki. Kosmetyczny LOD postaci nie jest stanem symulacji.

## Wejścia do aren

Ukośne przejścia z doliny dostają łagodne połączenie podłoża na całej szerokości.
Uwzględnia ono próbki natywnej siatki kolizji, żeby Agro nie widział sztucznego
urwiska przy krawędzi mapy. Skały Basarana zostawiają otwarte wejście od +Z.
Bot testowy po przekroczeniu bramy podąża osią korytarza i wraca na jego środek.

Po rzeczywistym dojeździe do Celosii i Cenobii strażnicy mogą znajdować się pod
innym kątem niż na początku osobnej próby. Płomień nabyty przy palenisku pozostaje
na opuszczonym mieczu, więc gracz może ustawić Celosię przed murem. Odpychanie
nadal wymaga podniesienia miecza i celowania; zmiana broni, śmierć lub reset gasi płomień.
Bot testowy sprawdza linię cofania w mur i unika zapowiedzianych szarż przez PlayerActions.

## Sprawdzenie

- `tests/auto_save.tscn`: rzeczywiste wsiadanie i zsiadanie, zapis i wczytanie na Agro,
  dalsza fizyka, zachowanie poprzedniego checkpointu podczas rzeczywistej wspinaczki,
  ochrona późniejszego zwycięstwa, minutowy zapis i „Kontynuuj” w głównej scenie — 0 błędów.
- `tests/travelers_v3.tscn`: importy, materiały, stawy, chód przez PlayerActions,
  pozycje jazdy i wspinaczki; headless i Forward+ — 0 błędów.
- `tests/temple_characters_v3.tscn`: prawdziwy ołtarz i orientacja Mono; checkpoint
  przy LOD0 i LOD2 ma identyczne 28 700 B, 29 rekordów węzłów i 15 obiektów.
  Odtworzenie oraz dalszy ruch działają, modele i tekstury nie trafiają do pliku — 0 błędów.
- `tests/colossi_v3.tscn`: 561 GLB, kontrakty kości/kolizji/znaków i 20 pełnych walk
  z nowymi modelami w obróconych arenach kampanii — 20/20 wygranych bez śmierci/resetów.
- `tests/capture_agro_dormin_v3.tscn -- --validate`: 96 GLB, rig i jazda Agro,
  trzy pieczęcie Dormina, wspinaczka i oba znaki; import oraz render OpenGL — 0 błędów.
- `test_world_layout_keeps_arenas_apart_and_connected`: 21 aren, drogi i zamknięte obrzeża;
  63 pasy wejściowe mają maksymalną zmianę wysokości 0,301 m na pół metra — 0 błędów.
- `tests/corridor_arrival.tscn`: rzeczywista droga ze świątyni do walki;
  przejazdy do Quadratusa i Basarana po poprawkach — 0 błędów.
- `tests/paired_arrival.tscn`: rzeczywista podróż do pary, dwa rozbicia pancerza,
  cztery trafienia i zwycięstwo w 51,17 s od rozpoczęcia walki; ponowna walka
  po pełnym resecie w 42,90 s — 0 błędów, bez śmierci i resetów podczas podejścia.
- `tests/art_integration_v3.tscn`: 21 kampanii z `with_art=true`, 21 natywnych scen
  prób oraz dwa binarne checkpointy — 0 błędów. Odtworzenie zachowuje otwarte
  futro Celosii, zamknięty pancerz Cenobii i blokady Dormina. Wartość odtworzona
  przez WorldSnapshot ma pierwszeństwo przed odroczonym resetem nowych colliderów.
- `tests/test_runner.tscn`: pełny zestaw 197 testów regresji — 0 niepowodzeń.
  Przy zamykaniu tego dużego procesu Godot zgłasza pozostawione zasoby testowe;
  nie jest to wynik czystego zamknięcia wszystkich fixture.

Nie ukończono jeszcze wielokrotnych przejść całej kampanii od świątyni do finału
z losową pozycją Agro i kierunkiem startu. Indywidualne starcia oraz powyższe
konkretne przejazdy nie zastępują takiego sprawdzenia.

## Kolejność dalszego rozwoju

Najpierw dopracowanie oprawy i czytelności dróg wspinania, następnie mały fragment
świata z pogodą, porą dnia i reakcją na pokonanie kolosa. Po ustabilizowaniu tych
systemów: dyskretny kompan AI i wejście/wyjście drugiego gracza. VR wymaga osobnej
pracy nad dłońmi, kamerą, ruchem i komfortem; nie jest jeszcze działającym trybem.
Pełny kierunek opisuje `WIZJA_GRY.md`.
