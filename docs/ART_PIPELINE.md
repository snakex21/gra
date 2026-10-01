# Saltward — działający prototyp artystyczny

Autorski, lekko stylizowany zestaw do pustego, monumentalnego krajobrazu: spękany
kamień, ziemia, skromna roślinność i **Saltward Sentinel**, jeden testowy kolos.
Nie jest rekonstrukcją lokacji ani postaci z komercyjnej gry. Wszystkie nowe
modele i tekstury powstały lokalnie, proceduralnie; nie pobierają nic z sieci.

## Szybki start

Gotowe GLB i tekstury są w repo. **Blender nie jest potrzebny do uruchomienia.**

```bash
godot --headless --path . --editor --import
tools/art/run_showcase.sh
# Oddzielny, opcjonalny sandbox z dotychczasowym gameplayem:
godot --path . --rendering-method gl_compatibility art/tests/sandbox_art.tscn
# Testy tylko nowej warstwy artystycznej:
tools/art/run_art_tests.sh
```

W edytorze: otwórz `art/tests/environment_showcase.tscn` i uruchom **F6**.
`project.godot` oraz domyślna scena pozostają niezmienione.

- **1 / 2 / 3:** neutralny dzień, niskie słońce, noc z czytelnym światłem księżyca
- **V:** cztery stałe kadry przeglądowe: basen, kolos, ruiny, ziemia/roślinność
- **L:** kolory LOD dla modeli: zielony LOD0, żółty LOD1, czerwony LOD2
- **H:** ukrywanie napisów
- Nie ma cyklu dobowego, pogody, audio ani efektów cząsteczkowych

Scena przeglądowa używa własnych stałych kamer wyłącznie do oceny grafiki.
Sandbox artystyczny używa oryginalnego sterowania i kamery gracza.

## A. Zweryfikowany kontrakt repozytorium

| Element | Stan sprawdzony przed pracą |
|---|---|
| Repo | `snakex21/gra` |
| Baza | `b6155855fa4153ab5610ec02e591b9d622e1fbf3`, `claude/sharp-cray-x761iy` |
| Projekt | Godot 4.4+, GDScript; istniejący CI używa 4.4.1 |
| Sprawdzone narzędzia | Godot 4.6.3 stable, Blender 4.3.2 |
| Jednostka / osie | 1 jednostka = 1 m, Godot +Y w górę, -Z przód, +X lewa strona kolosa |
| Szkielet | 17 kości i 17 istniejących `BodySegment`, około 17 m wysokości |
| Mechanika | `FUR` = istniejący `ClimbPatch`; kamień i pancerz = istniejące kolizje |
| Pliki repo instrukcji | Brak `AGENTS.md` i lokalnych art skills w sprawdzonym checkoutcie |

`assets/colossus_visual_contract.json` przechowuje nazwy, rodziców, offsety
spoczynkowe, części i SHA-256 odczytanego kontrolera. Validator zgłosi zmianę
kontraktu. Zmiana gameplayu wymaga ponownego sprawdzenia adaptera, nie edytowania
rozgrywki przez pipeline artystyczny.

Nie zmieniono `src/`, `scenes/`, `tests/`, `project.godot`, istniejących skryptów
testowych ani CI. Nowe testy znajdują się tylko w `art/tests/`.

## B. Zawartość zestawu

**19 assetów środowiska + 17 części jednego kolosa = 36 pozycji.**
Każda ma GLB LOD0, LOD1 i LOD2, łącznie 108 plików wizualnych.

| Zestaw | Modele |
|---|---|
| Skały | `rock_01`–`rock_05`: pięć proporcji, od kamienia do głazu |
| Klif | `cliff_buttress`: warstwowa, nieregularna ściana skalna |
| Ruiny | `ruin_column`, `ruin_wall`, `ruin_arch`, `ruin_stairs`, `ruin_rubble` |
| Droga | `road_slab`, plus przejście ścieżki w shaderze ziemi |
| Roślinność | `grass_tuft`, `grass_dry`, `grass_low`, `shrub_salt`, `plant_spear` |
| Drzewa | `tree_windward`, `tree_juniper` |
| Kolos | `sentinel_<nazwa_kości>`, oryginalny ślepy kamienny wizjer, żebra/inlay, futro i pancerz |

Gotowe moduły do przeciągnięcia do sceny: `environment/prefabs/*.tscn`.
Cała kompozycja: `environment/saltward_environment.tscn`.

### Materiały i tekstury

- Wspólny atlas **1024×1024**, 16 pól z marginesem UV; jedna powierzchnia / materiał
  na eksportowany mesh. Nie ma materiału tworzonego osobno dla każdego kamienia
- Sześć materiałów **grass / soil / rock / sand / path / ruin_stone**: każdy ma
  własne oryginalne albedo i normal **512×512** oraz współdzielony `.tres`
- Shader ziemi miesza trawę, ziemię, piasek, skałę na stokach i wydeptaną drogę
  w przestrzeni świata. Łącznie pięć próbek albedo, bez kosztownego parallaxu
- Normal mapy służą pojedynczym materiałom triplanarnym. Duża ziemia ma tańszy
  shader bez normal map; atlas używa tylko albedo i stałej szorstkości
- Rośliny to nieprzezroczysta geometria, bez alpha blending, shell fur, groomu,
  kołysania wiatrem i cieni od traw
- Cała nowa paczka ma 13 PNG. Żadna tekstura nie przekracza 1024 px

UV używa wnętrza pól atlasu; LODy zachowują UV. Na bardzo odległych mipach może
pojawić się minimalne mieszanie sąsiednich pól, więc małe rośliny są wcześniej
wyłączane. To świadomy kompromis prototypu, bez dodatkowych samplerów na obiekt.

## C. Scena przeglądowa

`art/tests/environment_showcase.tscn` tworzy deterministyczny basen 200×200 m,
klif, modułowe ruiny, kamienie, drogę, trawy, oba drzewa i nieruchomego kolosa.
Trzy presety mają jedno światło kierunkowe, prosty sky i niewolumetryczną mgłę.
Nie wymaga GI, SSAO, SSR, volumetrics, compute ani Forward+.

Kompozycja jest próbką artystyczną, nie gotową pełną mapą gry. Nie zawiera wody,
ponieważ była opcjonalna. Rozstawienie proceduralne ma stałe ziarno **7013**.

## D. Kolos: tylko warstwa wizualna

`art/scripts/colossus_visual_adapter.gd` dołącza GLB do istniejących
`Seg_<bone_name>` w przestrzeni lokalnej. Ukrywa wyłącznie ich pierwotne meshe.
Usunięcie adaptera przywraca je. Brakujące segmenty przerywają podmianę w całości.

- Brak nowego skinned riga, animacji, IK, kości, controllerów lub grip logic
- Adapter nie ma `_process` ani `_physics_process`; podążanie wynika z rodzica
- Nie zmienia `CollisionShape3D`, `ClimbPatch`, ich identyfikatorów ani transformów
- Futro pokrywa istniejące regiony FUR. Krótkie, płytkie pasma mają sugerować chwyt;
  nie dodają nowych miejsc chwytania. Kamienny tors, dłonie, stopy i pancerz
  zachowują kształty oraz role dotychczasowych powierzchni
- Bazowy collider pozostaje autorytatywny. Ozdobna warstwa futra wystaje do około
  8 cm; fazy kamienia są płytkie. Nie należy traktować tej różnicy jako nowej fizyki
- To jeden oryginalny test wizualny, nie końcowy boss ani rekonstrukcja Valusa

## E. LOD, kolizje i koszt

- Modele środowiska: LOD0 do 35 m, LOD1 35–90 m, LOD2 90–260 m
- Klify: 50 / 110 / 380 m; kolos: 48 / 100 / 300 m
- Przejścia są twarde, bez przezroczystego crossfade. Klucz **L** pokazuje poziomy
- Wysoki `lod_bias` zapobiega agresywnemu drugiemu uproszczeniu automatycznych LOD
  importera. Podstawowy wybór należy do trzech dostarczonych GLB
- Trawa: `MultiMesh` w komórkach 16 m, dokładna wersja do 27 m, uproszczona
  27–68 m, dalej wyłączona. 1 713 instancji po odrzuceniu drogi i pustych obszarów
- Osobne collision GLB: dziewięć wypukłych proxy, **48 trójkątów każdy**
- Łuk ma osobne boxy filarów i klinów, dzięki czemu nie zamyka otworu hull-em
- Schody mają pojedynczy klin/rampę, drzewa tani pień, trawy/krzewy brak kolizji
- Teren: render 81×81 wierzchołków logicznych / 12 800 trójkątów, osobny
  heightfield 21×21. Nie jest to dokładna kolizja każdego kamyka powierzchni

Liczby assetów: `art/reports/asset_budgets.json`.
Rzeczywiste odczyty renderera: `art/reports/render_costs.json`.
Nie podajemy FPS gracza z pomiaru programowego llvmpipe.

## F. Izolowana integracja

`art/tests/sandbox_art.tscn` instancjonuje oryginalne `scenes/sandbox.tscn`.
Zmienia jego materiał podłoża i dodaje wizualnego Sentinela. Kilka nowych ruin,
skał i drzew stoi na obrzeżach; ich proste statyczne kolizje należą do wrappera.
W centrum pozostają wszystkie pierwotne kolizje i obiekty greyboxowe.
Domyślna scena nie jest przekierowana do tego wrappera.

## Edytowalne źródła i regeneracja

`art/source/saltward_kit.blend` zawiera dwie sceny:

1. `01_Environment_Catalogue`: modele rozłożone w katalogu, LOD0 widoczne
2. `02_Sentinel_Rest_Reference`: wizualne części w pozycji spoczynkowej,
   hierarchia pustych obiektów odpowiada istniejącym stawom; nie jest nowym rigiem

Tekstury są spakowane w `.blend`. GLB nie zawiera kopii tekstur; Godot przypisuje
wspólne materiały. `.gdignore` przy źródłach zapobiega automatycznemu importowi
Blendera. Runtime korzysta wyłącznie z gotowych GLB.

```bash
# Pełne odtworzenie oryginalnego zestawu; NADPISUJE ręczne edycje źródeł!
tools/art/build_art.sh

# Jedna ręcznie edytowana bryła: edytuj LOD0 w Edit Mode, zapisz .blend,
# zachowaj jednostki, origin i UV. Eksport odświeży tylko wybrany model/LOD/proxy.
blender -b art/source/saltward_kit.blend --python-exit-code 1 \
  --python tools/art/export_from_blend.py -- --asset rock_01
godot --headless --path . --editor --import
python3 tools/art/validate_exports.py
tools/art/run_art_tests.sh
```

Nazwy: małe litery, snake_case, `_lod0.glb` / `_lod1.glb` / `_lod2.glb`, osobny
`_collision.glb`. Origin kamieni i modułów znajduje się na poziomie podstawy;
origin części kolosa jest początkiem istniejącej kości. Blender używa Z-up,
eksporter przekształca do Godot Y-up. Nie stosuj dodatkowego obrotu ani skali 100×.

Pełna regeneracja jest deterministyczna geometrycznie i teksturowo przy tej samej
wersji Blender/NumPy. Binarne `.blend` może zawierać zmienne metadane narzędzia;
nie obiecujemy jego identyczności bajtowej między wersjami aplikacji.

## Walidacja i ograniczenia

`art/reports/validation.md` zawiera wynik konkretnego uruchomienia oraz oddziela
zaliczone testy artystyczne od istniejącego limitu CPU gameplayu. `art/screenshots/`
zawiera rzeczywiste PNG z viewportu Godota, bez retuszu i bez renderów Blender.

```bash
tools/art/capture_art.sh
# Ewentualnie na maszynie bez pulpitu, jeśli Xvfb jest zainstalowany:
xvfb-run -a tools/art/capture_art.sh
```

`--headless` wystarcza do importu i testów, ale nie do tych zrzutów. Skrypt kończy
się błędem zamiast udawać render, jeżeli brakuje działającego wyświetlacza.

Sprawdzono Compatibility / OpenGL na Mesa llvmpipe. Nie sprawdzono docelowej
karty użytkownika, mobilnego GPU, VR, konsol ani osiągów Forward+. Godot 4.4.1
pozostaje wersją istniejącego CI; lokalny test wykonano w 4.6.3. Presety i render
nie są benchmarkiem gotowej gry. LOD pop, szwy modułów i uproszczone proxy to
jawne kompromisy tego prototypu; nie zastępują testu na sprzęcie docelowym.

Pochodzenie/licencje: [assets/LICENSES.md](../assets/LICENSES.md).
Nowe assety CC0-1.0, nowy kod pipeline MIT; istniejąca gra nie została relicencjonowana.

## Część 3 — Stonewater Crossing

Nowy komplementarny zestaw akweduktu, przeprawy i sklepionej cysterny:
[opis, edycja i integracja](STONEWATER_KIT.md). Oddzielny przegląd:
`art/tests/stonewater.tscn`. Nie wymaga adaptera kolosa ani żadnego skryptu
rozgrywki. Reużywa atlasu Ancient Valley; nowe moduły mają własne LODy i jawne
receptury prostych kolizji w `assets/stonewater_manifest.json`.
