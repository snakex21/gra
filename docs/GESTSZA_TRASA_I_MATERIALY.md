# Gęstsza trasa od świątyni do Phaedry

Kontynuacja poprzedniej oprawy, punkt wyjścia: `fdc8fbce155b40e4d001f110476072e453737f92`.
Nie zmieniono geometrii układu 5 ani naprawionej drogi. Nie zmieniono kooperacji, AI,
kolizji ani zasad gry. Nie publikowano zmian w zdalnym repozytorium.

## Co widać

- Połączone, nieregularne pasma łąki i prześwity zamiast kilku wysp roślinności
- Trawy zielone i suche, niższe krzewy oraz drobne kamienie na trasie
- Nowe kępy cienkich, zgiętych źdźbeł z trzema osobno ułożonymi LOD-ami;
  niższy profil i przygaszona słoma zastępują ostre trójkątne kształty starej trawy
- Nowe autorskie, proceduralne tekstury trawy, ziemi, skały i zużytej kamiennej drogi
- Mieszanie podłoża w kilku skalach; skały zależne od nachylenia i wysokości,
  drobny relief z map normalnych, ciągłość tekstur między fragmentami terenu
- Jaśniejsze kopie używanych atlasów roślin i Nature Craft, bez zmiany ich UV;
  oryginalne źródła i modele pozostają zachowane

Roślinność nie wchodzi na drogę, do centralnej doliny ani do prześwitów aren.
Nowy rozkład jest deterministyczny i dotyczy wyłącznie pasa trasy w układzie 5.
Starsze układy zachowują swój sampler; materiały wizualne są współdzielone.

## Jakość i koszt

MultiMesh grupuje rośliny według modelu i komórki 64 m. Każda grupa ma trzy LOD-y,
jedną powierzchnię materiału i wspólne granice widoczności. Ustawienia niskie,
zrównoważone i wysokie zachowują odpowiednio 35%, 65% i 100% obsady. Kolejność
jest deterministycznie przemieszana, więc obniżanie jakości nie tworzy pustych pasów.
Generowanie i przesyłanie łąki podzielono na małe, wznawialne kroki, zamiast
wykonywać cały gęsty fragment w jednym wywołaniu.
Trawy wzdłuż trasy pozostają widoczne dalej przy użyciu najtańszego LOD-u.
Na niskiej jakości materiał podłoża pomija normalne i drugi poziom tekstur:
4 próbki tekstur na piksel zamiast 11 na zrównoważonej/wysokiej.

Wyniki końcowej kontroli:

- 11 541 elementów proceduralnej łąki na sprawdzanym pasie trasy; wcześniej
  529 elementów w porównywalnym wywołaniu samplera. To liczby obsady całego pasa,
  a nie liczba obiektów widocznych jednocześnie
- Na profilu zrównoważonym, w dwóch punktach kontroli: 492 / 519 wybranych
  odległością elementów tej warstwy, 27 / 32 partie rysowania i 8607 / 9648
  trójkątów. Nie jest to koszt całej sceny; rzeczywiste przycinanie poza kadrem
  może tę warstwę dodatkowo ograniczyć
- Kępy mają 72 / 32 / 12 trójkątów w trzech LOD-ach; najdalszy nadal ma trzy
  zgięte źdźbła, zamiast jednego dużego trójkąta
- Mediana budowy świata z oprawą w trzech uruchomieniach headless: 2,404 s
  wobec 1,884 s poprzednio. Najdłuższy krok kolejki: 5,307 ms wobec 6,393 ms
  w poprzedniej wersji; łąkę generuje się stopniowo
- Osobny test strumieniowania: maksimum 4,620 ms, p95 3,438 ms; identyczne
  wyniki wersji synchronicznej i dzielonej na kroki, również po zmianie jakości
- Porównanie 356 siatek terenu/drogi oraz 864 dotychczasowych transformacji
  potwierdza niezmienioną geometrię. Zgodne są hashe 4096 próbek wysokości,
  dróg i regionów każdego z układów 1–5
- Przeszły testy starych powtórek, zapisu/odczytu, prześwitów dróg i aren,
  ustawień jakości, oprawy i uruchomienia sceny gry

Zachowano celowo otwarty krajobraz. Najsilniejsza poprawa dalekiego planu to
tekstury i przejścia podłoża; roślinność podlega rzeczywistym odległościom LOD.
Szczegółowe wyniki są w dołączonym raporcie weryfikacji.
Czasy pracy CPU w trybie headless nie są pomiarem FPS. Brak dostępu do GPU oznacza,
że końcowego kosztu shaderów i zachowania sterownika nie można tutaj potwierdzić.

## O obrazach porównawczych

Obrazy pochodzą z renderowania CPU w Blenderze rzeczywistych siatek, UV, tekstur,
kolorów i transformacji wyeksportowanych z obu wersji gry. W obu wersjach użyto
identycznych kamer i światła. Nie są to zrzuty z Godota ani makiety.

Szeroki i bliski widok autorski pokazują pełną obsadę LOD0. Dodatkowy widok
zrównoważony stosuje rzeczywiste progi odległości, LOD-y i redukcję obsady
roślinności. Nie symuluje przycinania poza kadrem, okluzji, dynamicznych cieni,
LOD-ów krajobrazu ani obiektów rozgrywki. Shader podłoża odtworzono w węzłach;
różnice silników oświetlenia, filtracji tekstur i rasteryzacji pozostają.

Weryfikacja porównuje rzeczywistą poprzednią wersję układu 5 z nową oprawą.
Naprawa drogi jest obecna po obu stronach, więc nie służy do zawyżania poprawy.

## Zastosowanie kontynuacji

1. Zrób kopię swojego projektu i zapisów gry
2. W repozytorium z poprzednią dostarczoną wersją sprawdź:
   `git apply --check gestsza-trasa-kontynuacja.patch`
3. Jeżeli kontrola przejdzie, zastosuj:
   `git apply gestsza-trasa-kontynuacja.patch`
4. Otwórz projekt w Godot 4.4+ (testowano headless Godot 4.6.3), zaczekaj na import
   tekstur i uruchom `scenes/game.tscn`
5. Porównaj trasę świątynia–Phaedra w nowej grze układu 5. Ustawienia → Jakość
   grafiki pozwalają zmieniać obsadę, odległości i koszt materiału bez zmiany świata

Jeżeli projekt ma własne nowsze zmiany, nie nadpisuj go bez kontroli konfliktów.
ZIP zawiera te same zmienione pliki w katalogu `pliki/` oraz instrukcję i dowody.
Patch jest dostarczony osobno. Bez Gita można, po wykonaniu kopii i potwierdzeniu
właściwej wersji bazowej, skopiować zawartość `pliki/` do katalogu projektu,
zachowując strukturę folderów. Nie kopiuj całego katalogu `pliki` jako podfolderu.

## Odtwarzanie zasobów i testów

- `python tools/art/generate_ground_materials.py --check`
- `python tools/art/regrade_foliage_atlases.py`
- `blender --background --python tools/art/generate_meadow_grass.py`
- `python tools/art/test_ground_materials.py`
- `godot --headless --editor --import`
- `godot --headless --script tests/route_meadow.gd`
- `godot --headless --script tests/route_density_cost.gd`
- `godot --headless --script tests/route_meadow_streaming.gd`
- `godot --headless --script tests/terrain_art_integration.gd`
- `godot --headless tests/environment_dressing.tscn`
- `godot --headless tests/graphics_quality.tscn`
- `godot --headless tests/terrain_layout.tscn -- --layout5`
- `godot --headless --script tests/layout4_cross_version_replay.gd`

Szczegóły eksportowania sceny i ograniczeń odwzorowania: `tools/art/ROUTE_PREVIEW.md`.
