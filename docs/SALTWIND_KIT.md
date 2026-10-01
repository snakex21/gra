# Saltwind Expanse — część 4

32 nowe, autorskie moduły do solnej pustyni i podejścia przez kanion. Zestaw
uzupełnia Ancient Valley i Stonewater, zamiast przemianowywać ich modele.
Kompozycja pozostawia pustą nieckę, czytelną bramę i rzadkie skupiska przy
obrzeżach. To lekko stylizowany prototyp artystyczny, nie gotowa mapa walki
ani finalne rzeźbione skały. Nie zawiera postaci, rigów, dźwięku ani symulacji pogody.

## Uruchomienie i kontrola

```bash
godot --headless --editor --path . --import
godot --path . --rendering-method gl_compatibility art/tests/saltwind.tscn
python3 tools/art/validate_saltwind.py
godot --headless --path . --script art/tests/test_saltwind.gd
godot --headless --path . --script art/tests/test_saltwind_heightfield_control.gd
blender -b --python-exit-code 1 --python tools/art/test_saltwind_source.py
# W terminalu działającego pulpitu, nie z --headless:
tools/art/capture_saltwind.sh
```

V zmienia siedem kadrów, 1/2/3 wybiera trzy nieruchome presety światła,
L pokazuje LODy, H ukrywa podpisy. Dwie ostatnie strony zawierają po 16 modeli.
Katalog skaluje modele do wspólnej komórki, także powiększa drobną roślinność;
nie pokazuje wszystkich obiektów w jednakowej skali rzeczywistej.

Samodzielna scena środowiska: `environment/saltwind_expanse.tscn`.
Prefabrykaty: `environment/saltwind/*.tscn`. Każdy prefab domyślnie ma
`collidable = false`; statyczne proxy włącza się świadomie. Przegląd ma je
włączone wyłącznie we własnej scenie. Nic nie zmienia domyślnej sceny projektu.
Na ograniczonym systemie ustaw zapisywalne XDG_DATA_HOME, XDG_CONFIG_HOME i
XDG_CACHE_HOME; skrypt capture robi to sam. Blender nie jest potrzebny w runtime.

## Inwentarz

- Geologia (10): erodowana iglica, rozwidlona iglica, skalna płetwa, kaptur
  skalny, grzyb skalny, podłużny jardang, podcięty brzeg, ząbkowany grzbiet,
  nieregularna daleka skarpa oraz asymetryczny płaskowyż
- Sól i dno niecki (6): płyty solne, wypiętrzony grzbiet, ostrza mineralne,
  nawis skorupy, rozeta mineralna i dwa brzegi suchego żłobu
- Zasypane ruiny (8): brama, mur oporowy, ażurowa wieża, żebrowany filar,
  stopniowany cokół, zasypane schody, pęknięte nadproże i nacinany drogowskaz
- Sucha roślinność (8): wachlarz trawy, kula suchych gałązek, łuk cierniowy,
  krzew solny, wachlarz sztywnych liści, suche trzcinowe nasiona,
  korzeniowy kikut i martwe płaskie drzewo

`assets/saltwind_manifest.json` zawiera identyfikatory, rzeczywiste wymiary,
obwiednie, 96 ścieżek GLB, trójkąty i oddzielne receptury kolizji.
Jednostka = 1 metr; Godot +Y w górę, -Z przód, origin na podstawie.
Geologia i rośliny nie są siatką modułową; nie obiecujemy, że dowolne krawędzie
połączą się szczelnie. Ruiny również używają swoich rzeczywistych wymiarów,
zamiast sugerować uniwersalny krok siatki. Kotwica `ground` oznacza podstawę.

## Źródła, UV i materiały

`art/source/saltwind.blend` zawiera 32 kolekcje, każde z LOD0/1/2, oraz
wyłączoną kolekcję niezależnych proxy. Atlas modeli jest spakowany w Blenderze.
Cztery mapy podłoża są oddzielnymi PNG; ich edytowalnym źródłem proceduralnym
jest `tools/art/generate_saltwind.py`. Runtime ładuje GLB, nie plik Blender.

```bash
# Pełna regeneracja NADPISUJE ręczne zmiany zestawu:
blender -b --python-exit-code 1 --python tools/art/generate_saltwind.py
# Ręczna edycja: zmień każdy LOD w Edit Mode, zapisz .blend i eksportuj model:
blender -b art/source/saltwind.blend --python-exit-code 1 \
  --python tools/art/export_saltwind.py -- --asset eroded_needle
# Test deterministyczności także NADPISUJE ręczne zmiany:
python3 tools/art/test_saltwind_determinism.py
```

Eksport pojedynczego modelu zachowuje lokalny origin i ignoruje przesunięcie
katalogu. Nie odtwarza innych modeli ani nie zgaduje nowych kolizji.
Po zmianie kształtu sprawdź także ręczną recepturę proxy. Geometryczne i
teksturalne wyniki generatora są deterministyczne dla tego samego Blender/NumPy;
metadane binarnego `.blend` nie muszą być identyczne bajtowo.

Pięć nowych współdzielonych map: atlas 1024×1024, sól albedo/normal
2048×2048, osad albedo/normal 1024×1024. Wszystkie powstały lokalnie,
bez zdjęć, pobieranych bibliotek, AI imagegen czy płatnych narzędzi.
Sól wykorzystuje okresowe komórki Voronoi, a normal mapy liczą różnice z
zawijaniem na brzegach. UV atlasu zachowuje wspólną skalę obu osi powierzchni;
nie rozciąga niezależnie długich i krótkich boków. Gęstość tekseli nadal różni
się między wielką skałą a drobnym detalem. Dalekie facety i twarde przejścia LOD
pozostają widocznym kompromisem prototypu.

Każdy GLB ma jeden mesh i jedną powierzchnię; tekstury nie są w nim osadzone.
Modele używają jednego atlasu. Duży teren używa dwóch próbek albedo w shaderze,
bez parallaxu i kosztownych efektów. Osobne materiały `salt_crust.tres` i
`wind_sediment.tres` oferują mapy normalne do bliższych powierzchni; domyślny
teren nie ładuje ich normal map. Pięć map nie oznacza pięciu samplowanych
tekstur na każdym obiekcie. Rośliny są nieprzezroczystą geometrią, bez alpha blend.

## Koszt i przestrzeń

Unikalna biblioteka: 23 840 / 7 658 / 2 240 trójkątów dla LOD0/1/2,
czyli około 68% i 91% mniej względem LOD0. Nie są to liczby trójkątów kadru.
Trzy zasoby LOD pozostają załadowane; odległość ogranicza rysowanie, nie
magicznie całą pamięć. Zwykłe zakresy to 0–55 / 55–145 / 145–800 m.
Twarde przejścia nie rysują obu LODów w crossfade.

Dziewięć fragmentów terenu zajmuje 480×480 m i 18 432 trójkąty; dalej jest
niekolizyjna kontynuacja (10 368 trójkątów) aż do 1200×1200 m. Krawędzie obu części używają
identycznych próbek. Test rzeczywistych krawędzi mesha sprawdza brak dziur,
podwójnych trójkątów i pęknięć przy połączeniu. Heightfield 97×97 jest osobny.
Rzadka roślinność korzysta z 24 komórek/typów MultiMesh i trzech zakresów
0–38 / 38–78 / 78–140 m; nie rzuca cieni. 199 roślin ma deterministyczne pozycje; trzy kopie LOD nie oznaczają 597 osobnych roślin.

104 proste receptury proxy w bibliotece. Duże podcięcia używają kilku
sześciobocznych hullów; brama i wieża osobnych boxów. Całe prześwity nie są
zamykane jednym hull-em. Małe rośliny i mineralne dekoracje nie mają kolizji;
kikut i drzewo mają tylko grube proxy pnia. Proxy są przybliżeniem, nie
wiernym odwzorowaniem powierzchni ani deklaracją miejsc wspinaczki.

Pomiary konkretnego renderu znajdują się w `art/reports/v4/render_costs.json`.
Liczniki obejmują cienie, UI i zasoby przeglądu, nie tylko unikalne modele.
Przetestowano Compatibility/OpenGL w Godot 4.6.3 na Mesa llvmpipe.
Nie jest to pomiar FPS użytkownika ani gwarancja wydajności GPU/VRAM.
Nie sprawdzono docelowej karty, urządzeń mobilnych, konsol ani Forward+.
Jedno światło kierunkowe, brak GI/SSAO/SSR, wolumetrycznej mgły,
przezroczystej wody, aktualizowanej pogody i cyklu dnia.

## Ograniczenie zapytań do heightfieldu

W tym Godot/backendzie część pionowych promieni dokładnie na granicach
komórek/triangle edge pudłuje. W scenie Saltwind było to 23/49 próbek.
Osobny minimalny test płaskiego heightfieldu, bez generatora i bez grafiki
Saltwind, odtworzył problem: 24/49. Oba zestawy miały 49/49 trafień promieni
przesuniętych o 0,017/0,023 m i 49/49 kontaktów sfery o promieniu 0,15 m.
To jawny problem zapytania punktowego, a nie zaliczenie tych promieni.

`heightfield_control.json` zachowuje dokładne współrzędne. Przy integracji
konsument oparty na pojedynczym downward ray powinien mieć odporną strategię
(np. zapytanie kształtem albo małe dodatkowe próbki i tolerancję). Zestaw nie
zmienia zapytań gracza ani fizyki gry. Kontakt sfery nie zastępuje pełnego
testu ruchu gracza, schodów, chwytania czy wspinaczki.

## Integracja i zgodność

Baza paczki: Stonewater `2887ed88ed391a19c51e642f6dfc4264ef209772`.
Dodane pliki są w obszarze art/materials/textures/models/environment/tools/art/docs.
Nie zmieniono `src/`, `scenes/`, `tests/`, `project.godot` ani kontraktu kolosa.
Aktualny snapshot gry do osobnego testu zgodności:
`23ec961224956a095d5b7be7f0e11deae07ec228`. Wyniki są w raporcie walidacji.

Zestaw nie potrzebuje adaptera Sentinela. Nowsze warstwy grzywy, futra i pancerza
Valusa są wskazówkami wspinaczki; starszego ogólnego adaptera nie należy
nakładać na nie automatycznie. Integracja kolosów pozostaje poza tą paczką.
Istniejący limit CPU rozgrywki 0,6 ms i jego agregaty nie stają się zaliczone
przez udany import lub render nowego artu.

Nowe assety CC0-1.0, nowy kod MIT. Szczegóły: `assets/LICENSES.md`.
