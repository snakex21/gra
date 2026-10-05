# Teren i zapisane rozmieszczenie roślin — układ 4

Lokalna kontynuacja kosmetycznej paczki `0fa42e8`, bez publikacji, push ani merge.

## Co zmieniono

- Nowa gra używa układu 4. Układy 1–3 pozostają dostępne w tych samych współrzędnych dla zapisów i powtórek.
- Sześć miejsc otrzymało więcej przestrzeni: Phaedra, Kuromori, Phalanx, Pelagia, Argus i Saru. Świątynia, 21 lokacji, promień aren 175 m, wysokości aren i rozmiary postaci pozostają bez zmian. Granice nadal wynoszą 4096 × 4096 m. To lokalna korekta, nie skalowanie świata.
- Indywidualne podejścia są łagodnie przesunięte razem z końcowymi bramami i orientacją aren. Wspólne odcinki tras zostają na miejscu.
- Otwarte odcinki dróg rozszerzają się płynnie z 28 do 36 m. Bramy, most i centralna dolina zachowują stare szerokości. Rzeczywista siatka drogi i jej kolizja używają tej samej szerokości.
- Szerokie lokalne wzniesienia i obniżenia rozbijają płaski teren między lokacjami. Renderowana powierzchnia, kolizja i wysokość roślin korzystają z tej samej siatki. Podłoże pod drogami nadal pozostaje poniżej ich przejezdnej wstęgi.
- 720 instancji istniejących krzaków, paproci i traw zapisano w edytowalnym JSON. Każdy rekord ma stabilne ID, model_id, position, rotation i scale. Mesh nie jest kopiowany per roślina. Starszy proceduralny podkład krajobrazu pozostaje oddzielną warstwą.

## Co pokazał pomiar

Wcześniejsze ciasne pary miały środki co 440 m i tylko 90 m między krawędziami aren. Postać ma 1,8 m wysokości kolizji, a maksymalna prędkość piesza to 5,5 m/s. Koń: 1,7 / 4,2 / 9,5 m/s. Podgląd ortograficzny obejmuje 4200 m w 1440 px, co dodatkowo spłaszcza przestrzeń.

| Para | Przed | Po |
|---|---:|---:|
| Phaedra / Kuromori | 90,00 m | 204,44 m |
| Barba / Phalanx | 90,00 m | 161,08 m |
| Pelagia / Argus | 272,25 m | 328,82 m |
| Saru / Pelagia | 272,25 m | 421,04 m |
| Gaius / Saru | 272,25 m | 418,44 m |

Globalne minimum nadal wynosi 90 m w dwóch nietkniętych parach (Avion/Phoenix, Quadratus/Dormin). Najkrótsza trasa zostaje 334,29 m; najdłuższa wzrasta z 2416,42 do 2480,44 m. Te czasy są ilorazem długości trasy i prędkości, nie pomiarem rzeczywistej jazdy:

| Zmieniona trasa | Długość przed → po | Pieszo przed → po | Galop przed → po |
|---|---:|---:|---:|
| Phaedra | 681,37 → 788,11 m | 123,9 → 143,3 s | 71,7 → 83,0 s |
| Kuromori | 1293,10 → 1501,87 m | 235,1 → 273,1 s | 136,1 → 158,1 s |
| Phalanx | 929,59 → 1136,26 m | 169,0 → 206,6 s | 97,9 → 119,6 s |
| Pelagia | 1476,40 → 1609,12 m | 268,4 → 292,6 s | 155,4 → 169,4 s |
| Argus | 2313,54 → 2480,44 m | 420,6 → 451,0 s | 243,5 → 261,1 s |
| Saru | 1671,05 → 1797,19 m | 303,8 → 326,8 s | 175,9 → 189,2 s |

## Edycja roślin

`data/environment/authored_nature_layout4.json` jest źródłem prawdy dla 720 nowych roślin. Pozycja XYZ jest w metrach; obrót XYZ w radianach, kolejność Eulera Godot YXZ; skala XYZ jest lokalna i dodatnia. Katalog modeli to `data/environment/nature_catalog.json`. Zapisz JSON i uruchom grę ponownie. Runtime nie losuje tych pozycji od nowa.

- `--resnap` zachowuje ręcznie poprawione XZ, obrót, skalę i ID, zmieniając tylko Y do powierzchni terenu
- `--regenerate` zastępuje ręczne zmiany deterministyczną kompozycją referencyjną; najpierw zachowaj kopię/commit pliku
- Po ręcznych edycjach testuj z `--edited`, aby sprawdzić poprawność i prześwity bez wymuszania identyczności z pierwotnym generatorem

```sh
godot --headless --path . --script tools/art/bake_nature_placements.gd -- --resnap
godot --headless --path . --script tests/authored_nature.gd -- --edited
```

Rośliny są wyłącznie wizualne: bez nowych kolizji, nawigacji czy stanu AI. Zachowują odsunięcie od dróg, aren i świątyni. Siatki są współdzielone, mają 3 LOD-y, wspólne granice cullingu i atlas; profile jakości zmieniają liczbę widocznych instancji i odległości. Dla nowej warstwy: 264 batchy, 36 wspólnych meshów, maks. 24 rośliny na komórkę 64 m. Widoczne pule low/balanced/high: 309/499/720. Cały świat, gdyby wymusić jeden poziom na wszystkich roślinach: LOD0/1/2 = 1 824 760 / 905 666 / 475 356 trójkątów; to nie liczba trójkątów w pojedynczej klatce. Trawy/paprocie znikają do 85 m, krzewy do 140 m na wysokiej jakości, wcześniej na niższych.

Cały zbudowany układ 4 ma 3981 batchy (wcześniej 3663), 72 wspólne meshe i 302 zadania dekoracji: 256 chunków oraz osobne rozgrzewanie pojedynczych zasobów. W trzech końcowych przebiegach headless budowa/dekoracja trwała 1,740 / 1,699 / 1,675 s; najdłuższy job 5,870 / 4,698 / 3,933 ms. Nominalny budżet kolejki 1,8 ms jest kontrolowany między zadaniami i może zostać przekroczony przez pojedynczy job; to nie gwarancja czasu klatki. Pierwszy odczyt atlasu (~20 ms) został wydzielony do synchronicznej konstrukcji świata **przed** spawnem aktorów i sterowaniem, więc nie wpada w pierwszy job kępy podczas gry. Nie ma ponownego losowania/zapisu pliku w pętli gry. Atlas importowany jest zgodnie z repo: kompresja VRAM mode=2 oraz mipmapy; `configure_texture_imports.py --check` przechodzi (556 plików, 0 zmian).

Runtime wykorzystuje 60 geometrycznych plików GLB, zmniejszonych łącznie z 78 193 796 do 7 177 424 bajtów przez usunięcie powielonych atlasów. Wierzchołki/indeksy/normale/UV, transformacje i wszystkie LOD-y pozostają identyczne z gotowym pakietem. Manifest zawiera obydwa hashe i podpis geometrii. Nowych modeli ani tekstur nie tworzono.

## Zapis i granica integracji

Nie zmieniono formatu checkpointów ani plików użytkownika. Istniejące pole `world_layout` rozstrzyga geografię; brak pola nadal oznacza historyczny układ 1. Nowa gra zapisuje 4. Continue i replay przywracają własny numer, zamiast przenosić stare absolutne współrzędne. Cache tras, siatki i dekoracji jest kluczowany numerem układu, więc interleaving 3/4 nie zmienia starych wyników.

Małe punkty integracyjne to `scenes/game.gd` (nowa gra), `world_map.gd`/`valley.gd` (dispatch), `game_world.gd` (wskazanie miecza i wybór regionu klimatu) oraz dwie linie w `game_bot.gd` przekazujące wersję trasy. Nie zmieniono decyzji AI, walk, kolosów, współpracy ani kompana. Pliki snapshot/replay nie wymagają produkcyjnych zmian. Podczas integracji zachowaj nowszą zawartość tych punktów po stronie drugiego agenta.

Baza poprzedniej paczki: `42cffe9`; poprzednia ukończona paczka: `0fa42e8`. Lokalnie dostępny późniejszy upstream: `e3aabb68`. Odczyt aktualnego remote HEAD został anulowany przez kontrolę uprawnień; nie ponawiano ani nie obchodzono ograniczenia. Przed zastosowaniem konieczny jest ponowny `git apply --check` na rzeczywiście aktualnym checkoutcie. Ta paczka jest kontynuacją po wcześniejszej paczce środowiska, nie zamiennikiem jej historii.

## Testy

Godot 4.6.3 headless, z zapisywalnymi HOME/XDG oraz bezwzględną ścieżką logu:

```sh
mkdir -p tools/runtime/{cache,config,data} tests/output
export HOME="$PWD/tools/runtime" XDG_CACHE_HOME="$PWD/tools/runtime/cache"
export XDG_CONFIG_HOME="$PWD/tools/runtime/config" XDG_DATA_HOME="$PWD/tools/runtime/data"
godot --headless --path . --editor --import --quit --log-file "$PWD/tests/output/import.log"
godot --headless --path . --fixed-fps 60 tests/terrain_layout.tscn --log-file "$PWD/tests/output/terrain_layout.log"
godot --headless --path . --fixed-fps 60 tests/main_layout.tscn --log-file "$PWD/tests/output/main_layout.log"
godot --headless --path . --fixed-fps 60 tests/forbidden_lands.tscn --log-file "$PWD/tests/output/rides4.log" -- --layout4 phaedra kuromori phalanx saru pelagia argus
godot --headless --path . --script tests/authored_nature.gd --log-file "$PWD/tests/output/nature.log"
godot --headless --path . --script tests/terrain_art_integration.gd --log-file "$PWD/tests/output/art4.log"
python tools/art/test_nature_placements.py
```

Sprawdzone: wszystkie 21 tras, 5282 próbki fizycznego podłoża (902 na poszerzonych pasach ±16 m), 42 spawny, bramy i triggery, wszystkie 210 par aren, końce tras, 783 próbki starego terenu identyczne bajtowo po przeplatanych zapytaniach 3/4, stare 21 długości i środków, 10 historycznych wysokości. Wszystkie 21 rzeczywistych przejazdów przez PlayerActions/Agro dotarło do swoich aren bez śmierci; dodatkowo zapis/odtworzenie w drodze do Hydrus i wyjazd/powrót do Valus przeszły bez błędów. Test głównego menu obejmuje New Game, Continue, checkpoint bez world_layout, checkpointy 1/2/3/4, nagłówki replay i ich restart. Dodatkowo stare environment_dressing i landscape_v5 nadal przechodzą bez zmiany starej fizyki i siatki. Trzy testy replay (walka, seek przód/tył, markery/klip), world_climate (1758 asercji) i climate_persistence (44 sprawdzenia) przechodzą. Rzeczywiste czasy sześciu jazd, z przyspieszaniem i zakrętami: Phaedra124,48s, Kuromori176,12s, Pelagia187,12s, Phalanx137,90s, Argus277,60s, Saru206,22s; każdy przejazd bez śmierci.

Na dozwolonym komputerze z ekranem porównaj te same kamery:

```sh
godot --path . tests/forbidden_lands_capture.tscn
godot --path . tests/forbidden_lands_capture.tscn -- --layout4
```

Wyniki trafiają do osobnych katalogów `art/screenshots/forbidden_lands_layout3` i `...layout4`. Kamera normalnej rozgrywki nie została zmieniona.

## Ograniczenia

Brak renderu Godota, pomiarów GPU/FPS i wizualnej akceptacji na działającym ekranie: tworzenie gniazda ekranu jest zabronione w tym środowisku i nie próbowano obchodzić blokady. Dołączony plan jest oznaczonym diagramem rzeczywistych danych, a nie screenshotem gry. Testy headless nie zastępują oceny wyglądu i wydajności na komputerze z GPU. Nie wykonano całego wielogodzinnego soaku wszystkich walk ani testów nieobecnej najnowszej wersji co-op.
