# Etap 14 — broń, Wędrowiec, geografia i koszt grafiki

Wędrowiec nosi własne modele miecza, łuku, strzały, pochwy i kołczanu z Blendera.
Broń ma trzy poziomy szczegółowości; łuk odkształca ramiona przy naciąganiu,
cięciwa biegnie przez właściwy zaczep, a dłonie trafiają w uchwyty przez kosmetyczne IK.
Przełączenie broni odkłada nieużywany model. Ten sam model strzały działa w dłoni
i w locie, również po wznowieniu checkpointu. Naciąg częściowy i pełny nie powoduje
przeskoku strzały przy wypuszczeniu. Światło miecza wychodzi z końcówki klingi.

Źródło: `art/source/weapons_v4.blend`; generator: `tools/art/generate_weapons_v4.py`.
Wędrowiec dostał poprawioną twarz, włosy, fałdy ubrania i osobne nadgarstki/palce.
Mono pozostaje na dotychczasowym etapie. Są to własne stylizowane modele do dalszego
dopracowania, nie ukończona oprawa wszystkich postaci i kolosów.

## Budżety modeli

| Model | LOD0 | LOD1 | LOD2 |
|---|---:|---:|---:|
| Miecz | 5 998 | 2 758 | 1 067 |
| Łuk | 7 820 | 3 596 | 1 406 |
| Strzała | 1 224 | 562 | 199 |
| Pochwa | 3 260 | 1 498 | 569 |
| Kołczan | 5 972 | 2 746 | 1 074 |
| Wędrowiec | 34 360 | 17 859 | 4 080 |

Liczby oznaczają trójkąty pojedynczego modelu, a nie cały koszt klatki. Broń ma
tekstury 512×512. Modele z daleka przechodzą na tańsze LOD-y; najwyższy poziom jest
przeznaczony na widok blisko gracza. Pełny audyt GLB uruchamia
`python tools/art/audit_asset_budgets.py` i zapisuje `assets/asset_budgets.json`.
Raport opisuje geometrię i obrazy w plikach; nie zastępuje pomiaru VRAM ani FPS.
Opcja `--check-budgets` przerywa CI przy brakującym modelu lub przekroczonym limicie.

Kontrola kolejnych eksportów ma limity dla Wędrowca 40 000 / 22 000 / 5 000
trójkątów i dla pojedynczego modelu broni 10 000 / 5 000 / 1 800.
Maksymalna tekstura broni ma 512×512, postaci 2048×2048. Limity pozostawiają zapas
na dopracowanie sylwetek i wychwytują przypadkowe rozmnożenie geometrii.

## Starsze karty i ustawienia

Projekt domyślnie używa OpenGL Compatibility. Nie wymaga Vulkan / DirectX 12.
Tryb ten wymaga na desktopie obsługi OpenGL 3.3 i odpowiedniego sterownika.
Wiek karty sam w sobie nie ustala kompatybilności ani osiąganej płynności.
[Wymagania silnika](https://docs.godotengine.org/en/stable/about/system_requirements.html),
[renderery Godota](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).

Menu ustawień ma trzy profile, stosowane także w osobnych próbach kolosów.

| Parametr | Niska | Zrównoważona (domyślna) | Wysoka |
|---|---:|---:|---:|
| MSAA | wyłączone | 2× | 4× |
| Atlas cienia słońca | 1024 | 2048 | 4096 |
| Kaskady cienia słońca | 1 | 2 | 4 |
| Zasięg cienia słońca | 45 m | 100 m | 180 m |
| Atlas cieni świateł lokalnych | 512 | 1024 | 2048 |
| Próg automatycznego LOD siatki | 3 px | 1,5 px | 1 px |

Profile nie zmieniają kolizji, fizyki 60 Hz, akcji gracza, mocy latarki ani stanu
walki. Nie wymagają restartu. Ustawienie zapisuje się w lokalnym `data/settings.json`;
starsze pliki zachowują profil zrównoważony. Koszt małych plusków jest ograniczony
przez wspólną prostą siatkę i materiał kropli oraz wyłączone rzucanie cieni.

Importy tekstur 3D w `textures/` i obrazów modeli w `models/` są wersjonowane.
Kompresja VRAM i mipmapy nie mogą zniknąć przy świeżym klonowaniu repozytorium.
Narzędzie `tools/art/configure_texture_imports.py` odtwarza ustawienia importu;
cache `.godot/` nadal pozostaje lokalny i nie trafia do Git.

Rzeczywisty test Compatibility potwierdził 552 skompresowane obrazy z mipmapami:
243 mapy normalnych RGTC oraz 309 obrazów DXT1. Kontrola kanałów normalnych,
ORM i roughness przeszła; kadr zawiera 86 materiałów używanych przez modele i areny.
Suma wczytanych danych obrazów wynosi 115 572 424 B, wobec 675 981 264 B porównania
RGBA8 z pełnymi mipmapami. Te liczby opisują payload zasobów testu, a nie szczyt
alokacji VRAM całej kampanii. W wybranych GLB wykryto 34 grupy identycznych danych
z różnymi RID tekstur, dodatkowo 25 342 480 B payloadu; współdzielenie tych obrazów
pozostaje osobnym zadaniem. Raport i kontrola importów nie mylą identycznego pliku
z automatycznym współdzieleniem zasobu przez silnik.

Przed ustaleniem wymagań minimalnych potrzebny jest pomiar na rzeczywistej starszej
karcie. Test na RX 7900 XTX potwierdza poprawność renderera i przełączania profili,
nie wydajność kart z 2013 roku. Nadal warto profilować materiały, draw calle,
duplikowanie obrazów osadzonych w GLB i tworzenie całego świata.

Porównanie renderowania na własnym sprzęcie:

```text
python tools/run_local.py godot --resolution 1280x720 tests/render_budget.tscn
```

Uruchamiać bez `--fixed-fps`. Narzędzie wyłącza VSync, kończy budowę oprawy,
zamraża symulację i porównuje trzy profile w trzech identycznych kadrach.
`tests/output/render_budget.json` zapisuje czas budowy świata, odstępy między
klatkami oraz liczniki rysowania i pamięci zgłaszane przez Godota.
Primitives z monitora mogą uwzględniać wielokrotne przebiegi renderowania;
nie oznaczają unikalnych trójkątów całej sceny. To porównanie statycznej oprawy,
nie pomiar FPS walki. [Opis liczników silnika](https://docs.godotengine.org/en/4.6/classes/class_performance.html).

Pomiar 2026-10-03, Godot 4.6.3 / Compatibility, RX 7900 XTX, 1280×720:

| Profil, kadr świątyni | Draw calle zgłoszone przez silnik | Pamięć wideo zgłoszona |
|---|---:|---:|
| Niska | 415 | 103,9 MB |
| Zrównoważona | 519 | 118,6 MB |
| Wysoka | 668 | 133,4 MB |

Te liczniki obejmują tylko wczytany świat i zasoby tego statycznego testu.
Mediany odstępów klatek w kadrze świątyni wyniosły 1,005 / 1,132 / 1,224 ms;
nie przeliczamy ich na obietnicę FPS rozgrywki. Start świata trwał 2,33 s,
a wymuszone ukończenie pozostałej oprawy 1,04 s. Normalna gra rozkłada tę oprawę
na klatki; początkowa budowa fizycznego terenu nadal jest blokująca i wymaga dalszej
pracy przy docelowym streamingu. Test zakończył się bez błędów i wycieków.

## Nowy układ świata

Układ 3 zastępuje promieniste korytarze wspólnymi drogami, rozgałęzieniami,
mostem nad kanionem i regionami rozmieszczonymi względem świątyni.
Orientacja i podział bazują na mapach oraz zrzutach oryginału; szczegóły i źródła
opisuje [Mapa Krainy](MAPA_KRAINY.md). Regiony dodatkowych kolosów są naszym projektem.
To pierwszy grywalny etap geografii, z prostym terenem i roślinnością do dalszego
modelowania. Krajobraz wymaga jeszcze rzeźbienia i bogatszych modeli ruin.

Zapisy i nagrania przechowują numer układu świata, więc stare checkpointy odtwarzają
wcześniejszy układ. Kosmetyczna broń, dłonie i LOD-y nie powiększają grafu zapisanej
symulacji. Fizyka dróg powstaje przed wjazdem gracza, a detale renderowania są
budowane małymi porcjami.

## Weryfikacja

```text
python tools/run_local.py godot --headless --fixed-fps 60 tests/weapon_art.tscn
python tools/run_local.py godot --fixed-fps 60 tests/weapon_art.tscn
python tools/run_local.py godot --fixed-fps 60 tests/graphics_quality.tscn
python tools/run_local.py godot --fixed-fps 60 tests/texture_budgets.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/main_layout.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/forbidden_lands.tscn
python tools/art/configure_texture_imports.py --check
python tools/art/audit_asset_budgets.py --check-budgets
```

Test broni sprawdza 15 importów, właściwe akcje gracza, końcówkę miecza, latarkę,
pełny i częściowy naciąg, fizyczny lot strzały, Agro, cios we wspinaczce, wszystkie
LOD-y i wznowienia binarne. Test grafiki zmienia rzeczywiste atlasy, MSAA i kaskady;
checkpoint przed i po zmianie pozostaje identyczny. W tej sesji przechodzą też
regresje łuku, strzał, promienia miecza, ustawień/menu, autozapisu, checkpointów
wspinaczki oraz Etapu 12. Szczegóły przejazdów mapy znajdują się w jej dokumencie.
Pełna próba mapy ukończyła 21/21 przejazdów Agro bez śmierci i stallów oraz 4269
próbek fizycznej podłogi. Zapis gałęzi Hydrusa i wyjście/powrót do Valusa przeszły.
Kopia samych plików przygotowanych do Git, bez cache `.godot/`, przeszła świeży
import silnika, kontrolę 552 ustawień tekstur oraz testy `texture_budgets` i
`main_layout`. Import nie zgłosił błędów, a helper konfiguracji nie wymagał zmian.
