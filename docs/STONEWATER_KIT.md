# Stonewater Crossing — część 3

Autorski zestaw architektoniczny do monumentalnego krajobrazu. Uzupełnia
Ancient Valley o wysoką przeprawę wodną, most, przyczółki i sklepioną cysternę.
Nie jest kopią istniejącej lokacji. Nie zmienia rozgrywki ani domyślnej sceny.

## Uruchomienie

Wymagane są dostarczone wcześniej pliki części 2. Nie trzeba mieć Blendera.

```bash
godot --headless --editor --path . --import
godot --path . --rendering-method gl_compatibility art/tests/stonewater.tscn
# V: kadry; 1/2/3: trzy statyczne pory światła; H: napisy; L: kolory LOD
python3 tools/art/validate_stonewater.py
# Opcjonalny test edytowalnego źródła (Blender):
blender -b --python-exit-code 1 --python tools/art/test_stonewater_source.py
godot --headless --path . --script art/tests/test_stonewater.gd
# Faktyczne screenshoty i liczniki renderera (wymaga wyświetlacza):
xvfb-run -a tools/art/capture_stonewater.sh
```

Scena samodzielna do instancjonowania: `environment/stonewater_crossing.tscn`.
Pojedyncze moduły: `environment/stonewater/*.tscn`. Ich kolizje są opcjonalne;
nie należy włączać ich jako zamienników istniejących kolizji poziomu bez przeglądu
przez osobę odpowiedzialną za gameplay. Scena to studium artystyczne, nie gotowa
mapa z gwarantowanymi trasami wspinaczki, nawigacją lub walką.

## 18 modułów, 54 eksporty LOD

- Akwedukt: pełne przęsło z kanałem, urwane zakończenie, ujście wody
- Przeprawa: grobla, płyta mostu, przyczółek, rampa, prosty parapet i zakończenie
- Cysterna: sklepiony moduł, strop z otwartym okulusem, narożnik basenu, rama śluzy
- Elementy monumentalne: żebrowany filar, portal, przypora łukowa
- Detale użytkowe: kaskada kamiennych stopni i rzeźbiony drogowskaz

Nazwy plików, rzeczywiste wymiary, punkty łączenia, liczby trójkątów i oddzielne
receptury kolizji są w `assets/stonewater_manifest.json`. Jednostka = 1 metr.
Godot używa +Y w górę; moduły wzdłuż osi X, głębokość Z. Wspólna siatka 2 m
nie oznacza identycznego kroku każdego modułu: przęsło o prześwicie 12 m ma
powtórzenie 16 m. Korzystaj z nazwanych punktów łączenia, nie z obwiedni fazowań.

## Źródła i edycja

`art/source/stonewater.blend` jest edytowalnym katalogiem. Zawiera wszystkie
LODy i spakowany współdzielony atlas. Materiał runtime to istniejący
`materials/ancient_valley/atlas.tres`, bez nowych tekstur i osobnych materiałów
na każdy obiekt. GLB nie zawierają kopii tekstur.

```bash
# Pełna regeneracja NADPISUJE ręczne zmiany w całym nowym zestawie:
blender -b --python-exit-code 1 --python tools/art/generate_stonewater.py
# Po ręcznej edycji każdego LOD wybranego modelu w Edit Mode:
blender -b art/source/stonewater.blend --python-exit-code 1 \
  --python tools/art/export_stonewater.py -- --asset aqueduct_span_12m
```

Eksporter pojedynczego modelu czyta osobno edytowane LOD0/1/2, zachowuje ich
lokalne originy i nie przelicza pozostałych modeli. Układ katalogu w Blenderze
nie trafia do pliku runtime. Kolizje są niezależnymi, ręcznie opisanymi bryłami
w manifeście: zmiana kształtu wizualnego wymaga osobnego przeglądu receptury.
Eksporter nie zgaduje kolizji z pełnej geometrii i nie zamyka otworów jednym
convex hullem.

## Koszt i ograniczenia

Każdy wizualny GLB ma jeden mesh i jedną powierzchnię. Trzy jawne LODy mają
twarde przejścia, bez podwójnego rysowania/crossfade. Domyślne odległości
samodzielnego prefabrykatu to 55 / 140 / 520 m; scena może dobrać inne wartości.
UV nowego zestawu zachowuje proporcje powierzchni, bez rozciągania obu osi
niezależnie. Gęstość tekseli różni się między dużą powierzchnią a drobnym detalem;
nie dodano kosztownego materiału triplanarnego. Konstrukcyjne łuki i sklepienia
są zamknięte wzdłuż spoin; otwarte pozostają tylko zaprojektowane prześwity.
Źródłowy `.blend` jest ignorowany przez importer Godota. Runtime nie wymaga
Blendera, połączenia sieciowego ani dodatkowych wtyczek.

Receptury box/convex są uproszczone i odrębne od wizualnych meshów. Otwory łuków,
portalu, śluzy i okulusa pozostają otwarte. Nie obiecujemy precyzji fazowanych
krawędzi ani automatycznej zgodności ze wspinaczką. Elementy drobne i dalekie
w scenie nie muszą rzucać cieni; nie ma cieniowania per-pikselowego włosia,
wolumetrycznej mgły ani kosztownych efektów wody.

`art/reports/v3/export_budgets.json` podaje koszt unikalnej biblioteki;
`render_costs.json` rzeczywiste obciążenie kadrów. Te wartości różnią się:
instancje powtarzają geometrię, cienie dodają przejścia, frustum/LOD część usuwa.
Liczniki pamięci są odczytem silnika, nie gwarancją VRAM docelowej karty.
Testowane środowisko programowe llvmpipe nie jest benchmarkiem FPS gry gracza.

## Kontrakt i integracja

Baza tej części: `99ed94f7f163f6239209f0b1f835c56bd53bab84` (część 2).
Nowy renderer i showcase nie importują skryptów bossów, gracza, kontrolerów,
kamery gry, IK, mózgu ani testów gameplayu. `src/`, `scenes/`, `tests/`,
`project.godot` i wcześniejszy kontrakt kolosa pozostają niezmienione.

Ważne przy równoległej integracji: nowszy gameplay
`615f29c43867510758d12389702a6d713433087d` zachowuje dodatkowe części Valusa
(grzywa/fur-cap/pancerz) jako wskazówki wspinaczki. Starszego ogólnego adaptera
Sentinel-v2 nie należy automatycznie nakładać na tego Valusa: ukrywa on wszystkie
meshe potomne segmentów. Stonewater nie wymaga tego adaptera i niczego w nim
nie zmienia. Połączenie artu bossów pozostaje osobną decyzją integracyjną.

Zgodność nowego zestawu sprawdzono także na późniejszym snapshotcie gameplayu
`f84dd100fcb29442dc66f68a0c2d91d03f994805` (Gaius): import, 618 testów artystycznych
i krótki start sceny przeszły, bez nadpisania plików rozgrywki. Pełne bazowe testy
gry mają istniejący błąd limitu CPU: 116/120 zaliczonych, jeden bezpośredni błąd
0,645 ms przy limicie 0,6 ms oraz trzy zależne agregaty. To jawne ograniczenie
pomiaru wspólnego środowiska, nie deklaracja wydajności GPU użytkownika.

Licencje: nowe artystyczne zasoby CC0-1.0, nowe skrypty MIT.
Zobacz `assets/LICENSES.md`. Nie zmieniamy licencji istniejącej gry.
