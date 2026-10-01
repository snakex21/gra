# Saltwind Expanse — rzeczywista walidacja, 2026-10-01

## Zaliczone dla końcowych źródeł

- Godot 4.6.3: headless import bez błędów skryptów/importu
- 953 sprawdzenia eksportów: 32 assety, 96 GLB, po jednym meshu/powierzchni,
  normalne i UV, brak zerowych trójkątów, monotoniczne LODy, niezależne proxy,
  wymiary pięciu PNG i ścisła granica art-only
- 1141 sprawdzeń edytowalnego źródła Blender: wszystkie 96 LODów, proporcje UV,
  wizualne prześwity bramy/wieży/żłobu na każdym LOD, spakowany atlas
- 890 sprawdzeń runtime/kolizji: importowane meshe, wspólne materiały,
  odległości LOD, idempotencja, opcjonalne proxy, prześwity, deterministyczny
  scatter, zamknięte krawędzie terenu i połączenie z dalekim terenem
- 102 wyniki generatora odtworzone identycznie bajtowo: 96 GLB + 5 PNG + manifest
- Eksporter pojedynczego modelu sprawdzony w izolowanej kopii: trzy LODy iglicy
  zachowały liczby trójkątów i obwiednię; inne 93 GLB i 31 rekordów nietknięte
- 9 rzeczywistych PNG 1280×720 z viewportu Godota; trzy presety, blisko/daleko,
  geologia, sól i dwa czytelne katalogi. Bez retuszu i bez imagegen
- Osobny snapshot gry `23ec961224956a095d5b7be7f0e11deae07ec228`:
  import, 890 sprawdzeń Saltwind i 90 klatek uruchomienia przeszły;
  177 plików gameplayu porównanych bajtowo ze snapshotem, zero zmian

Wszystkie surowe wyniki są w tym katalogu. `capture_provenance.json` wiąże
końcowe źródła z dziewięcioma screenshotami przez SHA-256.

## Koszt

Unikalne modele: 23 840 / 7 658 / 2 240 trójkątów, 104 proxy.
GLB razem 2,66 MB, Blender 2,14 MB, pięć PNG 15,66 MB.
Scena: 33 moduły krajobrazu i 199 roślin, plus ukryte strony katalogu.
Teren: 18 432 trójkąty blisko i 10 368 daleko.

Końcowe odczyty viewportu: 30–103 draw calls, 17 250–40 568 prymitywów
w zależności od kadru. Zgłoszona pamięć tekstur 71,85 MB, buforów 10,68 MB;
liczniki obejmują silnik/przegląd/UI/render targets, nie są rozmiarem samych PNG.
Atlas i mapy normalne nie są samplowane wszystkie naraz na każdym obiekcie.

Renderer Compatibility/OpenGL, Mesa llvmpipe (LLVM 19.1.7, 256 bits).
To pomiary struktury obciążenia w rendererze programowym, nie benchmark FPS
na GPU gracza. Nie testowano Godot 4.4.1, mobilnego GPU, konsol ani Forward+.

## Jawny niezaliczony przypadek promieni

23/49 pionowych punktowych promieni dokładnie na granicach heightfieldu nie
trafiło w scenie Saltwind. Oddzielny płaski heightfield 97×97, bez generatora
Saltwind, odtworzył 24/49 pudła. W obu testach 49/49 promieni przesuniętych o
0,017/0,023 m oraz 49/49 kontaktów sfery 0,15 m trafiło. Nie ukryto tego przez
zastąpienie oryginalnych wyników: dokładne współrzędne są w raporcie kontrolnym.

To odtworzone ograniczenie zapytania Godot/backendu, nie deklaracja
bezbłędności zapytań pod stopami gracza. Integrujący gameplay powinien rozważyć
zapytanie kształtem lub niewielkie dodatkowe próbki z tolerancją. Nie zmienialiśmy
kodów fizyki, wspinania ani zapytań gracza. Kontakty kształtu i spójność siatki
terenu są osobnymi zaliczonymi testami, nie zastępują testu całej rozgrywki.

## Jakość i integracja

To autorski proceduralny prototyp artystyczny: facety i przejścia LOD nadal są
widoczne; brak finalnych rzeźbień hero, nawigacji, walki i gwarancji wspinaczki.
Kolizje są prostymi, niezależnymi przybliżeniami, bez zamykania prześwitów.
Nie używa i nie zmienia starego adaptera Sentinela ani wskazówek futro/pancerz
nowszego Valusa. Brak push, merge i zmian domyślnej sceny.

## Pełne bazowe testy gry: NIE pełny PASS

Na snapshocie `23ec961224956a095d5b7be7f0e11deae07ec228` zakończyło się 139 testów:
134 PASS i 5 FAIL, exit code 1. Jedyny bezpośredni błąd:
`test_performance_budget`, 0,702 ms przy limicie 0,6 ms w scenariuszu M1.
Cztery kolejne błędy są zależnymi agregatami poprzednich etapów.
Porównanie ze starymi zamrożonymi baseline oznaczyło także 11 metryk;
pełne wartości są w `compat_gameplay_baseline.log`. Nie przedstawiamy tego
jako zaliczonej wydajności. Scenariusze i 177 plików gameplayu są niezmienione;
nowy Saltwind nie jest dodawany do tych scenariuszy. Nie naprawiano ani
nie podwyższano limitów rozgrywki w tej paczce.
