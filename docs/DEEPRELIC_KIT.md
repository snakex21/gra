# Deeprelic — część 7: wyposażenie podziemi

28 autorskich rekwizytów do jaskiń i ruin Hollowvault. Edytowalny Blender,
84 pliki GLB (LOD0/1/2), współdzielony atlas Hollowvault 1024 px, osobne proste
kolizje opt-in. Poprzednie środowiska nie są dogęszczane; paczka ma własną
kompozycję wewnątrz zamkniętej komory z części 6.

## Uruchomienie

- Samodzielny runtime: rozpakuj ZIP, zaimportuj project.godot w Godot 4.4+
  i uruchom F5. W repo uruchom F6 scenę art/tests/deeprelic.tscn.
- V przełącza cztery kadry wnętrza i cztery strony katalogu.
- Do istniejącej gry kopiuj art/scripts, art/tests, assets, environment, models,
  materials i textures, zachowując strukturę. Nie zastępuj konfiguracji gry
  samodzielnym project.godot. Runtime zawiera niezbędne zależności Hollowvault.
- Poszczególne rekwizyty: environment/deeprelic/*.tscn.
- Gotowa kompozycja: environment/deeprelic_environment.tscn.

## Zawartość

3 bramy: procesyjny łuk, wąski łuk, złamane nadproże.
3 przeprawy: most z parapetami 10 m, niski most 6 m, przerwany most.
4 formy filarów: wysoka kolumna z rogami głowicy, krótki filar, urwany filar,
rozsypane bębny. 3 schody: procesyjne, użytkowe, ze spocznikiem.
4 miejsca kultu: stół ofiarny, fontanna/misa, pusta wnęka, tablica pamięci.
5 pojemników: skrzynia ekspedycyjna, kasetka, kamienny kufer, stos skrzyń,
zamknięty dzban. 6 elementów obozu: zimne palenisko, posłanie, ława, stół,
rozdarty daszek i zgaszona lampa.

Przedmioty są puste, nie zawierają interakcji, zawartości łupów, ognia ani
animacji. Są to assety wizualne, bez zmian gameplay, IK, postaci lub wspinania.

## Kontrakt i ograniczenia

Metry, Godot Y-up, Blender Z-up. Origin na poziomie gruntu; pivot skrzyń,
fontanny, bram i filarów pośrodku podstawy. Mosty mają pomost 0,7 m ponad
pivotem, schody wznoszą się w +Z. Rozmiary dokładne są w manifeście.
LOD0/1/2: 0–65 / 65–150 / 150–800 m, bez przenikania transparentnego.
LOD upraszcza skosy krawędzi, segmenty łuków, przekroje i detale powierzchni;
wszystkie trzy modele pozostają załadowane. Jedna powierzchnia na asset.

Kolizje włącz przez collidable lub include_collision. Schody używają rampy,
nie stopni kolizji; bramy mają drożne przejścia, uszkodzony most ma prawdziwą
lukę. Materiały tkanin i małe fragmenty paleniska są dekoracyjne. Proxy nie
stanowią kontraktu do wspinania. Oświetlenie wnętrza jest pokazowe, punktowe;
nie ma światła słonecznego prześwitującego przez sklepienie. Osobne światło
katalogu używa innej warstwy renderowania. Fontanna ma zamknięte dno bez wody
symulowanej fizycznie, lampy nie emitują światła same z siebie.

## Edycja i odtworzenie

Otwórz art/source/deeprelic.blend. Każdy asset ma trzy osobne meshe w swojej
kolekcji; edytuj w Edit Mode i zachowaj lokalny pivot. Offsety katalogu nie
są eksportowane. Kolekcja COLLISION_RECIPES_DISABLED zawiera widoczne proxy
źródłowe, ale runtime korzysta z assets/deeprelic_manifest.json; edycja proxy
nie aktualizuje automatycznie JSON.

    blender -b art/source/deeprelic.blend --python-exit-code 1 --python tools/art/export_deeprelic.py -- --asset processional_arch

Generator chroni ręczne edycje; pełne świadome nadpisanie:

    blender -b --python-exit-code 1 --python tools/art/generate_deeprelic.py -- --regenerate

Pipeline korzysta wyłącznie z lokalnych helperów. Nie użyto ImageGen,
pobranych modeli ani cudzych assetów. Geometria i atlas: CC0-1.0, dokument
licencji w assets/LICENSES.md; helpery: tools/art/LICENSE. Zależność pack6:
38ce87c5e68c59894eb6e75926a4c75c9908fc38.

## Kontrola

    godot --headless --editor --path . --import
    blender -b --python-exit-code 1 --python tools/art/test_deeprelic_source.py
    godot --headless --path . --script art/tests/test_deeprelic.gd
    godot --path . --rendering-method gl_compatibility art/tests/deeprelic.tscn -- --capture-deeprelic

Raporty w art/reports/v7, prawdziwe kadry silnika w art/screenshots/v7.
Środowisko testowe OpenGL Compatibility / llvmpipe nie pozwala obiecać FPS
na docelowym GPU. Nie uruchamiano pełnego testu gameplay.

Zweryfikowany wynik: 702 testy runtime i 432 sprawdzenia źródeł; 84 poprawne GLB.
Trójkąty biblioteki: 14 820 / 4 248 / 2 496. Łącznie 139 prostych
receptur kolizji. Osiem PNG z Godota 4.6.3, OpenGL Compatibility / llvmpipe.
