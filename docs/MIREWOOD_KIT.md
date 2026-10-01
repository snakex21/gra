# Mirewood Fen — część 5

31 nowych, autorskich assetów mokradeł: korzenne wyspy, otwarte pnie, drewniane
pomosty, zapadnięte ruiny i roślinność. Przygaszona, lekko stylizowana oprawa
monumentalnego, opuszczonego świata. To oryginalne geometrie i tekstury,
nie modele ani rekonstrukcje z komercyjnej gry. Nie użyto pobranych modeli,
ImageGen, płatnych usług ani zamkniętych generatorów.

## Uruchomienie

Gotowe GLB są w repo, Blender nie jest wymagany do używania paczki.

```bash
godot --headless --editor --path . --import
godot --path . --rendering-method gl_compatibility art/tests/mirewood.tscn
```

W Godocie otwórz `art/tests/mirewood.tscn`, potem F6. Sterowanie:
1/2/3 — dzień / późne słońce / niebieska godzina, V — dziewięć widoków,
L — kolory jawnych LODów, H — napisy. Cztery strony katalogu mają maksymalnie
osiem podpisanych modeli, dopasowanych do pola; skala katalogowa nie oznacza
skali świata. Jest 11 zapisanych PNG, ponieważ szeroki kadr ma trzy oświetlenia.

Samodzielny zestaw środowiska: `environment/mirewood_environment.tscn`.
Poszczególne prefaby: `environment/mirewood/*.tscn`; `collidable` jest domyślnie
wyłączone. W scenie demonstracyjnej kolizje są włączone. Zestaw nie przestawia
sceny startowej projektu i nie ładuje gracza ani kolosa.

## Inwentarz

| Grupa | Identyfikatory / zastosowanie |
|---|---|
| Brzeg i wyspy | `root_island`, `crescent_island`, `root_bank_16m`, `root_bank_corner`, `peat_hummock` |
| Duże korzenie | `woven_root_bridge`, `buttress_root` |
| Drzewa i pnie | `hollow_elder_trunk`, `hollow_fallen_log`, `crown_stump`, `fen_elder_tree`, `fallen_root_tree` |
| Drewniana przeprawa | `boardwalk_8m`, `boardwalk_broken`, `boardwalk_railed`, `boardwalk_turn`, `mooring_landing`, `old_mooring_piles` |
| Omszałe ruiny | `rootbound_gate`, `buried_moss_passage`, `drowned_shrine`, `moss_retaining_wall`, `drowned_stairs`, `rootwell_ring`, `fen_waystone` |
| Drobna roślinność | `cypress_knees`, `broad_sedge`, `cattail_rush`, `marsh_fern`, `lily_pad_raft`, `hanging_moss` |

Pnie mają rzeczywisty pusty środek, a kolizje składają się z odcinków pierścienia.
Złamany pomost zachowuje dziurę także w proxy. Korzenne wyspy i łagodnie gięte
wiązki korzeni uzupełniają wcześniejszą dolinę, kamienny akwedukt i solną pustynię;
nie są samym przemalowaniem tamtych modeli.

## Kontrakt i budowa

- Metry, Godot +Y w górę, -Z przód; pivot przy podstawie. Blender Z-up, eksporter
  dokonuje przekształcenia, bez dodatkowego obrotu 90° w Godocie
- Drewniane pomosty mają długość 8 m, szerokość 2,8 m i wysokość pokładu ok. 1,3 m;
  origin pozostaje przy gruncie. Ustawienie na siatce 4 m / 8 m
- Każdy model ma trzy osobne, ręcznie określone proceduralne LODy, jeden mesh i
  jedną powierzchnię. Uproszczenie jest semantyczne: mniej przekrojów korzeni,
  boków, listew, pinnae i szczegółów; otwory konstrukcyjne pozostają otwarte
- Wspólny atlas 1024 px. Cztery dodatkowe mapy torfu/mchu po 1024 px: albedo
  i normal. Materiały `peat.tres` i `moss.tres` są gotowe do triplanarnego użycia
  na innych bryłach; teren przeglądu używa tańszego shadera tylko z dwoma albedo
- UV architektury używa wspólnej metrycznej skali obu osi na danej powierzchni,
  nie rozciąga osobno długiego i krótkiego boku do kwadratu. Atlas ma marginesy
- Źródło `.blend` zawiera wszystkie 93 edytowalne meshe LOD oraz wyłączoną kolekcję
  pomocniczych proxy. Atlas modeli jest spakowany w źródle
- Reużywane są sprawdzone lokalne prymitywy i algorytm UV ze starszego pipeline'u,
  nie wcześniejsze kształty gotowych assetów. Bez nowych zależności narzędziowych

## Tania scena przeglądowa

480 × 480 m bliskiego gruntu w dziewięciu chunkach i dopasowana kontynuacja do
1200 × 1200 m. 18 432 trójkąty bliskiego gruntu plus 10 368 odległego.
Otwarty środek bagna pozostaje spokojny; duże kształty skupiają się przy brzegach.
69 instancji dużych assetów oraz 992 logiczne instancje roślin, grupowane w
24-metrowe komórki MultiMesh. Każda komórka ma trzy niezależne zasoby LOD;
2976 instancji w załadowanych buforach nie oznacza 2976 widocznych naraz.

Zakresy dużych modeli: 0–55 / 55–145 / 145–800 m; roślin: 0–38 / 38–78 / 78–140 m.
Nie ma przezroczystego crossfade. W katalogu wymuszony jest LOD0 do 900 m.
Wszystkie zasoby LOD są załadowane, więc culling zmniejsza renderowanie, nie
rozmiar plików na dysku ani automatycznie całą pamięć.

Woda jest nieruchomą, nieprzezroczystą płaszczyzną ze skromną analityczną normalą.
Nie ma SSR, odbić renderowanych do tekstury, refrakcji, symulacji fal, pływania,
pogody, cyklu dobowego, audio ani cząsteczek. Jedno światło kierunkowe z cieniami,
bez GI, SSAO, SSIL i volumetrics. Rośliny nie rzucają cieni.

## Kolizje i ograniczenia użycia

438 jawnych prostych kształtów w bibliotece: boxy i małe wypukłe fragmenty.
To liczba unikatowych receptur, nie liczba colliderów całego świata.
Przejścia i studnia nie są zamknięte jednym convex hullem. Korzenie używają
prostych odcinków proxy; ich zakrzywiony render może lokalnie odstawać od hull-a.
Mała roślinność, lilie i wiszący mech nie mają kolizji. Schody mają tanią rampę.

Złamany pomost naprawdę jest przerwany. Nie jest to gotowa, ciągła ścieżka dla
nawigacji; nie dodano mostka kolizyjnego ponad dziurą. Korzenny most także nie
jest pełną płaską kładką. Woda nie zapewnia podparcia ani pływania. Poziom torfu
pod wodą to osobny heightfield. Testowane są otwory, nie możliwości gracza.

Znane zachowanie Godota 4.6.3: 24 z 49 pionowych promieni dokładnie na granicach
komórek heightfield nie trafia. Wszystkie 49 lekko przesuniętych promieni i 49
kontaktów sfery przechodzą. Nie ukryto tego jako PASS, nie zmieniono zapytań ani
fizyki gameplayu. Dołączenie do gry i próby docelowego gracza należą do integracji.

## Edycja i odtwarzanie

```bash
# Pełna regeneracja, świadomie nadpisująca ręczne edycje źródła:
blender -b --threads 2 --python-exit-code 1 \
  --python tools/art/generate_mirewood.py -- --regenerate

# Eksport tylko wybranego ręcznie poprawionego modelu, bez regeneracji:
blender -b art/source/mirewood.blend --python-exit-code 1 \
  --python tools/art/export_mirewood.py -- --asset boardwalk_8m
```

Regenerator odmawia nadpisania istniejącego źródła bez `--regenerate`.
Edytuj każdy LOD w Edit Mode, zachowując nazwy `id_LOD0/1/2`, UV i skalę 1.
Przesunięcie obiektu w katalogu to tylko układ źródłowej sceny, nie przesunięcie
modelu w eksporcie. Eksporter wybranego assetu zapisuje trzy GLB i aktualizuje
jego metryki w manifeście; innych modeli nie przebudowuje.

Autorytatywne kolizje są w `assets/mirewood_manifest.json`, nie w render GLB.
Wyłączona kolekcja proxy w Blenderze wizualizuje receptury; przesunięcie jej
obiektów samo nie zmienia manifestu. Po korekcie colliderów zmień receptury i
próby przejścia w JSON, potem uruchom testy. Nie ma automatycznego hull-a, który
mógłby przypadkiem zamknąć otwór.

```bash
python3 tools/art/validate_mirewood.py
blender -b --python-exit-code 1 --python tools/art/test_mirewood_source.py
godot --headless --path . --script art/tests/test_mirewood.gd
python3 tools/art/test_mirewood_editing.py
python3 tools/art/test_mirewood_determinism.py
bash tools/art/capture_mirewood.sh  # rzeczywisty działający display
```

Test deterministyczny generuje nową kopię w katalogu tymczasowym i porównuje
99 plików: 93 GLB, pięć PNG i manifest. Nie nadpisuje edytowanego źródła.
`.blend` nie ma gwarancji identyczności bajtowej metadanych zapisu, a inna wersja
Blendera może zmienić eksport. Test eksportu ręcznej korekty również działa
w oddzielnym katalogu, bez niszczenia oryginału.

## Zweryfikowany zakres

Baza art: `f48162425002ec23562a271c11b4abd8b6c593cf` (finalne Saltwind).
Zmiany ograniczono do grafiki, materiałów, modeli, prefabs, dokumentacji i testów
artystycznych. `src/`, `scenes/`, istniejące `tests/` i `project.godot` są bez zmian.
Nie użyto adaptera Sentinel do aktualnego Valusa. Nie zmieniono gracza, kamery,
climb cues, IK, fizyki, AI ani balansu. Raporty: `art/reports/v5/`.

Zrzuty pochodzą z Godota 4.6.3, Compatibility / Mesa llvmpipe, 1280×720.
Liczniki renderera są dowodem pracy renderera, nie FPS docelowego GPU.
Źródłowa paleta jest celowo ciemna i przygaszona; nocna wersja zachowuje kontury,
ale nie zastępuje testu czytelności interakcji. Bryły są widocznie low-poly,
LOD-y mają twarde przejścia, dalekie liście tracą szczegóły. Ten modularny prototyp
nie udaje ręcznie wyrzeźbionej produkcyjnej lokacji ani ukończonego gameplayu.

Modele i tekstury: CC0-1.0. Nowy pipeline: MIT. Dotychczasowa gra bez zmiany licencji.
