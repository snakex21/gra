# Kolosy V3

Oryginalna oprawa prototypowych kolosów z Blendera: 20 starć, 21 osobnych profili ciała, 181 bazowych segmentów oraz 6 wizualnych nakładek futra. Każdy segment ma trzy eksporty GLB. Źródło zachowuje edytowalne pierścienie brył, kępki futra, pióra, maski i ornamenty w osobnych kolekcjach rodzin. Wszystkie eksporty używają metrów i lokalnego układu obecnego BodySegment.

```gdscript
# Wywołaj po dotychczasowym dress_valus / GuardianVisuals / skin_colossus.
var attached := ColossusArtV3.dress(colossus, &"valus")
```

`dress(c: Colossus, kind: StringName) -> int` przyjmuje nazwy kampanii. Dla `celosia_cenobia` rekurencyjnie wybiera osobne profile Celosii i Cenobii. Zwraca liczbę podłączonych segmentów; ponowne wywołanie zwraca 0. Brak pasującego profilu lub zmiana kontraktu kości zachowuje poprzednią oprawę. Dodatkowa jaskinia używa swojej obecnej oprawy.

Adapter ukrywa zastępowane bryły i stare wizualne zestawy, zachowując fizyczne segmenty, ClimbPatch, ArrowTarget, WeakPoint i szkielet. Nie tworzy kolizji ani nie zapisuje pozycji kości. Nakładki futra na pancerzach pary, grzbiecie Spidera i skrzydlatych strażnikach odczytują istniejące `ClimbPatch.disabled`; odsłaniają się po otwarciu rzeczywistej drogi wspinaczki. Sigile pozostają osobnymi obiektami gry.

Humanoidy mają osobne maski wołu, wizjera, brodatego strażnika, cyklopa, wieży i małpiego strażnika. Czworonogi rozróżniają rogi Quadratusa, smukły profil Phaedry, skorupę Basarana, zęby sterujące Pelagii oraz lwią i dziczą sylwetkę pary. Wodne i pustynne formy mają osobne profile głowy i ornamentów. Pióra ptaków, błony Devila, karapaks Spidera i pierścień gębowy Worma są geometrią źródłową, a nie naklejonym znakiem.

LOD zmienia się w odległości 55 i 125 m, osobno dla każdego segmentu. Najwyższy poziom ma od 6 596 do 37 252 trójkątów na ciało. Dalsze poziomy mają około 42% i 15% geometrii. Jedna wspólna para tekstur albedo/normal 2048×2048 ogranicza liczbę materiałów. Dokładne budżety są w `geometry.json` i `assets/colossi_v3_manifest.json`.

Źródło: `art/source/colossi_v3.blend`. Generator: `tools/art/generate_colossi_v3.py`. Kontrakt można ponownie zebrać przez `tests/dump_colossi_v3.tscn`. Kolejność regeneracji:

```text
python tools\run_local.py godot --headless --quit-after 120 tests/dump_colossi_v3.tscn
python tools\run_local.py blender --python tools/art/generate_colossi_v3.py
python tools\run_local.py godot --headless --editor --import --quit
```

`tests/colossi_v3.tscn` sprawdza wszystkie eksporty, liczbę trójkątów, malejące LOD, osie i granice GLB, idempotencję oraz identyczny stan kości, kolizji i sigili. Następnie rozgrywa 20 pełnych walk botami przez PlayerActions w obróconych arenach kampanii, z oprawą V3 i bez oprawy otoczenia. Argument `--contracts-only` pomija walki; podanie nazw kolosów ogranicza serię walk.

`tests/capture_colossi_v3.tscn` renderuje siedem arkuszy przeglądu rodzin do `art/screenshots/colossi_v3/`. Są to rzeczywiste eksporty GLB w zebranych pozach odniesienia. Źródła, logi, raporty, importy i obrazy pozostają w folderze gry.
