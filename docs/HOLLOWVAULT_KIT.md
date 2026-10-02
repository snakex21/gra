# Hollowvault — część 6: zamknięte jaskinie

28 autorskich modułów, 84 GLB (trzy jawne LODy), edytowalne źródło Blender.
Dwie komory mają ciągłe, pełne sklepienie z zamkniętym wierzchołkiem,
zewnętrzną powłoką i podłogą. Otwory są tylko przy ziemi, z przodu i z tyłu.
To wnętrza jaskiń, nie otwarte misy. Materiał używa backface culling;
widoczność sklepienia nie jest maskowana materiałem dwustronnym.

## Instalacja

1. Rozpakuj `Hollowvault-v6-runtime.zip` do nowego folderu i zaimportuj jego
   `project.godot` w Godocie 4.4+ (sprawdzono w 4.6.3). Uruchom F6 scenę
   `art/tests/hollowvault.tscn`; samodzielny projekt uruchamia ją także przez F5.
2. Do istniejącej gry skopiuj foldery art, assets, environment, materials,
   models i textures. Nie kopiuj samodzielnego project.godot na konfigurację gry.
   Wszystkie nowe zasoby mają nazwy hollowvault i nie podmieniają poprzednich paczek.
3. Przeciągnij `environment/hollowvault_environment.tscn` do swojej sceny.
   Pojedyncze moduły są w `environment/hollowvault/`.
4. `Hollowvault-v6-source.zip` zawiera .blend, generator, lokalne helpery,
   eksporter pojedynczego modelu oraz testy. Rozpakuj obok runtime.
5. `Hollowvault-v6-preview-tests.zip` zawiera osiem rzeczywistych kadrów Godota
   i raporty. Plik bundle jest opcjonalnym przyrostem Git względem pack5.

V przełącza cztery kamery wnętrza i cztery strony katalogu. Kamera startowa
jest wewnątrz wielkiej komory. Podgląd nie ładuje gracza ani kolosa.
Demo ma punktowe lampy, subtelne światło otoczenia, bez GI/SSAO/SSIL/volumetrics.
Nie ma słońca oświetlającego jaskinię przez dach. Słońce katalogu ma osobną warstwę.

## Zawartość

- 2 kopuły: wielka komora ok. 44 × 56 m, sklepienie do 26 m; boczna ok. 24 × 30 m,
  sklepienie do 17 m. Wymiary dotyczą powierzchni wewnętrznej, skała ma 1,4 m grubości
- 3 przejścia o długości 12 m: proste, łagodnie skręcające i wznoszące się;
  maksymalny prześwit łuku ok. 6 m, szerokość podstawy 11,2 m
- 10 form mineralnych: po dwa stalagmity i stalaktyty, dwa skupiska,
  zrośnięta kolumna, kurtyna kalcytu, półki naciekowe, basen trawertynowy
- 5 kamiennych form: duży/mały głaz, płyta, iglica i rumowisko
- 8 reliktów: ołtarz, schody, brama, mostek, podstawa lampy, znacznik, mur i filar

Źródła i geometria są oryginalne, CC0-1.0. Bez ImageGen, pobranych modeli,
kopiowania komercyjnej gry lub płatnych generatorów. Reużyto lokalny pipeline
prymitywów/UV wcześniejszych paczek, nie ich gotowe modele.

## Kontrakt artystyczny

Metry; Godot +Y w górę, Blender +Z w górę. Eksport GLB robi konwersję osi.
Pivot komór/podłóg przy ziemi; stalaktyt ma grot przy Y=0, podstawę przy Y=wysokość.
Aby zawiesić stalaktyt, ustaw pivot na `wysokość_sufitu - wysokość_assetu`.
Otwory komór leżą na ±Z. Tunele mają końce Z=±6. Moduły łącz z niewielką
zakładką zewnętrznych powłok; kształt przejścia komory różni się od profilu tunelu.
Łagodny skręt przesuwa drugi koniec o 3 m w X. Rampa podnosi drugi koniec o 2 m;
jej podłoga to uproszczone, płytkie stopnie, nie dokładna ciągła pochylnia.

Wspólny atlas 1024 px, jedna powierzchnia renderowana na asset. Dodatkowe mapy
w folderze textures są źródłowymi próbkami materiału. Jawne zakresy LOD:
0–65 / 65–150 / 150–800 m, bez transparentnego crossfade. Wszystkie trzy LODy
pozostają załadowane; culling nie zmniejsza automatycznie zajętości plików/RAM.
Cała biblioteka: 25 096 / 8 304 / 3 708 trójkątów na LOD0/1/2.

Kolizje są opt-in: `collidable` na module lub `include_collision` na środowisku.
Demo ma je włączone. To boxy i małe wypukłe fragmenty powłoki, nie jeden hull
zamykający wnętrze. Łącznie 1 602 prostych receptur w bibliotece (głównie sklepienia).
Stalaktyty, wiszące ozdoby, rumowisko i płytki basen są dekoracyjne bez kolizji.
Proxy są użytkowe, uproszczone; nie stanowią kontraktu do wspinania. Nie zmieniono
skryptów gameplay, IK, fizyki postaci, kamery gry ani wspinania.

## Edycja

Otwórz `art/source/hollowvault.blend`. Każdy asset ma kolekcję z trzema meshami
`<id>_LOD0..2`; offsety katalogowe nie są częścią eksportowanych lokalnych pozycji.
Edytuj meshe w Edit Mode i zachowaj pivot/skale. Proxy są w wyłączonej kolekcji
COLLISION_RECIPES_DISABLED; runtime czyta osobne receptury z JSON, więc zmiana
proxy w Blenderze sama nie zmieni kolizji Godota.

Eksport jednego edytowanego assetu bez regeneracji całego źródła:

    blender -b art/source/hollowvault.blend --python-exit-code 1 --python tools/art/export_hollowvault.py -- --asset great_closed_dome

Pełna regeneracja wymaga świadomego `-- --regenerate`, ponieważ nadpisuje edycje:

    blender -b --python-exit-code 1 --python tools/art/generate_hollowvault.py -- --regenerate

## Weryfikacja

    godot --headless --editor --path . --import
    blender -b --python-exit-code 1 --python tools/art/test_hollowvault_source.py
    godot --headless --path . --script art/tests/test_hollowvault.gd
    godot --path . --rendering-method gl_compatibility art/tests/hollowvault.tscn -- --capture-hollowvault

- Import wszystkich nowych GLB bez błędów
- 2 161 sprawdzeń runtime: importy, wspólny materiał, cache, zakresy LOD,
  idempotencja budowy, kolizje opt-in i drożność przejść
- 459 sprawdzeń źródła plus 1 470 promieni w sufit na wszystkich LODach:
  zamknięte/manifold powłoki kopuł, brak dziur w sklepieniu, poprawne normalne
  skierowane do wnętrza, otwarte portale i tunel
- Osiem rzeczywistych PNG z Godota 4.6.3, OpenGL Compatibility / llvmpipe
- Raport zawiera draw calls i trójkąty, nie obietnicę FPS na docelowym GPU
- Brak pełnego testu gameplay; ta paczka nie ingeruje w gameplay

Baza: pack5 `08d9b7eaa04551b917340e6c14ee0ce4668cd734`.
