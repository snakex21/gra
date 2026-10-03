# Etap 15 — czas, pogoda i dalsza oprawa Krainy

Główna kampania ma teraz pełny cykl dnia i nocy, zmienną pogodę oraz atmosferę
reagującą na kolejne zwycięstwa. Do krajobrazu dochodzą własne modele drzew,
skał i ruin z Blendera. Ten etap rozwija wygląd świata i trwałość jego stanu;
mechaniki walk pozostają takie same.

## Czas i pogoda

Nowa gra zaczyna o **08:00**, a pełna doba trwa **1800 sekund symulacji**, czyli
30 minut gry. Zegar przesuwa się razem z krokiem fizyki. Pauza i ekran tytułowy
go zatrzymują. Wejście do areny, powrót do doliny i przebudowa świątyni nie
rozpoczynają dnia od nowa; podczas przejścia z wygaszeniem obrazu czas płynie dalej.

`WorldClimate` wyznacza fronty z utrwalonego seeda i czasu świata. Pogodnie,
zachmurzenie, deszcz, mgła i silniejszy wiatr przechodzą między sobą przez płynną
interpolację w okresach 240 sekund. Odczyt modelu nie zużywa losowości walk
i nie zmienia zapisanego stanu. Godzina, intensywności i kierunek wiatru są
odtwarzalne po wczytaniu lub przewinięciu powtórki. Nazwa dominującego frontu
jest tylko etykietą; wygląd wynika z ciągłych intensywności.

Regiony mają różne profile. Pustynie Phalanxa i Worma zamieniają mokry front
w pył, jeziora wzmacniają mgłę, lasy osłabiają wiatr, wyżyny go wzmacniają,
a gejzery i krater mają własne zamglenie. Główna mapa wybiera profil również
podczas dojazdu, na podstawie położenia gracza. Otwarte dziedzińce Barby
i niecka Dirge'a zachowują otwarte niebo. Dojazd do Devila staje się jaskinią
dopiero pod rzeczywistym zamkniętym sklepieniem.

Po pokonaniu kolejnych kolosów rosną zachmurzenie, mgła, atmosferyczny wiatr
i powolne pulsowanie anomalii Dormina. Po finale ten wpływ ustaje; naturalny
cykl czasu i pogody działa dalej. Pogoda nie dodaje sił działających na gracza,
nie zmienia sterowania Agro ani trudności wspinaczki.

Model i pełny kontrakt danych opisuje [WorldClimate API](../assets/world_climate_api.md).

## Niebo, światło i deszcz

`WorldClimateView` pokazuje ruch słońca, świt, zmierzch, tarczę księżyca,
zmiany chmur, mgłę, pustynny pył oraz subtelną anomalię. Noc zachowuje światło
otoczenia, dzięki czemu teren pozostaje czytelny. To samo światło kierunkowe
obsługuje słońce i księżyc; noc nie tworzy drugiego atlasu cieni. Przesunięcie
chmur wynika z zegara modelu, zamiast z niezależnego czasu shadera.

Deszcz to jeden mały emiter w pobliżu kamery. Fizyczny test dachu ukrywa go
pod sklepieniem lub zwykłym zadaszeniem. Dach nad otwartą drogą osłania od
opadu, zachowując normalne niebo i światło. Pod zamkniętym sklepieniem działa
lokalna atmosfera jaskini. Zanurzenie kamery także ukrywa krople.

Pogoda aktualizuje suchą bazę środowiska kamery, zachowując osobną mgłę
podwodną. Wynurzenie przywraca aktualną atmosferę zewnętrzną. Dzięki temu
zmiana frontu nad jeziorem nie usuwa podwodnego ograniczenia widoczności.

Warstwa graficzna działa poza drzewem regionu i checkpointu. Wczytanie wymusza
odświeżenie jej parametrów; wyjście do tytułu wyłącza emiter. Wiek pojedynczych
kropel pozostaje kosmetyczny i po przewinięciu może się różnić. Zachowany jest
stan czasu, frontu i intensywności pogody.

| Koszt oprawy | Niska | Zrównoważona | Wysoka |
|---|---:|---:|---:|
| Maksymalna liczba kropel | 96 | 176 | 256 |
| Oktawy szumu chmur | 1 | 2 | 3 |
| Aktualizacja cząstek | 30 Hz | 30 Hz | 30 Hz |

Krople współdzielą prostą siatkę i materiał oraz nie rzucają cieni. Niebo używa
małej kostki 32 px, a światło otoczenia jest sterowane kolorem. Ten system
nie wymaga mgły wolumetrycznej, SSR, SSAO, SSIL ani SDFGI. Zwykłe odświeżanie
pogody odbywa się najwyżej 10 razy na sekundę; zmiana regionu, ustawień
lub odtworzenie checkpointu może wymusić dodatkowe odświeżenie.

W stałym kadrze północnego mostu na **RX 7900 XTX / Godot 4.6.3 Compatibility**
test zgłosił 58 draw calli i 15 116 primitives bez deszczu oraz 59 draw calli
i 17 932 primitives z deszczem w profilu zrównoważonym. Dodatkowy emiter
kosztował w tym kadrze **jeden draw call i 2816 primitives**. Są to liczniki
renderera statycznej próby, a nie pomiar FPS walki ani potwierdzenie płynności
na kartach sprzed kilkunastu lat. Wymagania minimalne nadal trzeba sprawdzić
na rzeczywistym starszym sprzęcie.

Sześć kadrów znajduje się w `art/screenshots/climate/`: dzień, zmierzch, noc,
deszcz, anomalia i księżyc. Szczegóły warstwy oraz pomiaru zawiera
[WorldClimateView API](../assets/climate_view_api.md).

## Modele krajobrazu

Pakiet `landscape_v5` zawiera **dziewięć modeli, każdy w trzech LOD-ach**:
dąb, drzewo wygięte wiatrem, sosnę, martwe drzewo, dwa rodzaje skał oraz łuk,
podporę i parapet ruin. Źródło to `art/source/landscape_v5.blend`, generator
to `tools/art/generate_landscape_v5.py`, a manifest znajduje się w
`assets/landscape_v5_manifest.json`.

Modele używają jednego wspólnego nieprzezroczystego materiału i atlasu 1024×1024
z mapami albedo, normalnych i roughness. Korony drzew mają geometrię zamiast
przezroczystych kart liści. GLB przechowują geometrię bez osadzonych obrazów,
więc warianty LOD nie powielają własnych kopii atlasu. Każdy model ma jedną
powierzchnię. Limity eksportu to **3000 / 1000 / 200 trójkątów** dla LOD0/1/2.

Oprawa zastępuje proste dekoracje w regionach lasu, skał i mostu. Kilka ruin
stanowi punkty orientacyjne przy leśnej drodze, zachowując puste przestrzenie
pozostałych regionów. Drzewa i skały omijają drogi oraz najbliższe otoczenie
aren. To dekoracje: istniejące podłoże, kształty kolizji i przejezdność mostu
pozostają bez zmian.

Powtarzalne elementy są grupowane w `MultiMesh`, współdzielą siatki i materiał,
mają trzy zakresy widoczności oraz wyłączone rzucanie cieni. Budowa detali jest
rozłożona na małe zadania przestrzenne. Most korzysta z mniejszych grup, aby
element stojący blisko kamery nie wybierał LOD-u według odległego środka całej
konstrukcji. Początkowa budowa fizycznego terenu nadal wymaga osobnej pracy
nad streamingiem.

## Zapis i powtórki

Stan klimatu jest opcjonalnym polem `climate` w dotychczasowym zapisie kampanii;
wersja `GameState` pozostaje zgodna ze starszymi plikami. Zapisuje seed, czas
i małą poprawkę sumowania, zapewniającą zgodność zegara przy 30/60/120 Hz.
Stare zapisy i checkpointy bez tego pola odtwarzają godzinę oraz pozycję frontu
z dotychczasowego `play_time`. Niepoprawne opcjonalne dane są zastępowane
bezpiecznymi wartościami domyślnymi.

Checkpoint świata przechowuje klimat razem z postępem kampanii. Przewijanie
i wycinki powtórek wznawiają go z najbliższego checkpointu, po czym wykonują
pozostałe kroki nagrania. Gdy nowszy JSON zawiera więcej czasu gry, ale gracz
był w niebezpiecznym stanie, autosave zachowuje klimat ostatniego bezpiecznego
świata oraz nowszy licznik łącznego czasu gry. Dzięki temu wczytanie nie miesza
pogody z innego momentu z pozycją starego checkpointu.

Dane pozostają przenośne: zapisy w `data/` obok aplikacji, testowe pliki w
`data/tests/`, raporty w `tests/output/`, kadry w `art/screenshots/`. Klimat
nie tworzy osobnego pliku w profilu Windows. Helper uruchamiania trzyma cache,
logi i dane runtime w folderach projektu.

## Weryfikacja

| Test | Potwierdzony wynik | Zakres |
|---|---|---|
| `world_climate` | 1758 sprawdzeń, 0 błędów | Doba, 30/60/120 Hz, płynne i deterministyczne fronty, seed, zapis i kontynuacja, legacy, uszkodzone pola, regiony, finał |
| `climate_persistence` | 44 sprawdzenia, 0 błędów | Rzeczywisty GameWorld, checkpoint, pauza i tytuł, arena/przebudowa/fade, priorytet bezpiecznego autosave, seek i skompresowany wycinek |
| `climate_shelter` | 0 błędów | Fizyczny dach, otwarty dojazd do jaskini, zamknięte sklepienie, kamera pod wodą i wynurzenie |
| `climate_view` | Headless i rzeczywisty OpenGL Compatibility: 0 błędów | Niebo, noc, deszcz, trzy profile, środowisko kamery, sześć kadrów i liczniki rysowania |
| `landscape_v5` | Headless i rzeczywisty OpenGL Compatibility: 0 błędów | 27 modeli, wspólny atlas, geometria, LOD-y, batching, identyczne kolizje |
| `world_climate_capture` | Rzeczywisty OpenGL Compatibility: 0 błędów, czyste zamknięcie renderera | Zintegrowana kampania, las dzień/noc, most/deszcz/anomalia |
| Dotychczasowy `test_runner` | Pełny zestaw 197 testów: 0 nieudanych | Wspinanie, proceduralny ruch, Agro, walki, fizyka wody, zapis, powtórki i niezależność od render FPS |
| `stage12`, `auto_save`, `main_layout` | 0 nieudanych | Jaskinia, woda, checkpointy, bezpieczny autozapis, prawdziwe uruchamianie kampanii |

```text
python tools/run_local.py godot --headless --path . tests/world_climate.tscn --quit-after 10000
python tools/run_local.py godot --headless --path . --fixed-fps 60 tests/climate_persistence.tscn --quit-after 10000
python tools/run_local.py godot --headless --path . --fixed-fps 60 tests/climate_shelter.tscn --quit-after 10000
python tools/run_local.py godot --headless --path . --fixed-fps 60 tests/climate_view.tscn --quit-after 20000
python tools/run_local.py godot --path . --resolution 1280x720 tests/climate_view.tscn --quit-after 20000
python tools/run_local.py godot --headless --path . tests/landscape_v5.tscn --quit-after 20000
python tools/run_local.py godot --path . --resolution 1280x720 tests/landscape_v5.tscn --quit-after 20000
python tools/art/audit_asset_budgets.py --check-budgets
```

Test krajobrazu kontroluje importy, UV, atlas i mipmapy, rzeczywiste trójkąty,
malejące LOD-y, współdzielenie materiału, ograniczone grupy widoczności
oraz niezmienione kształty fizyczne i wysokość podłoża. Pomiar renderowania
wymaga uruchomienia na rzeczywistym GPU; wyniki headless go nie zastępują.

Test krajobrazu potwierdził identyczne **2 807 352 bajty danych kształtów kolizji**
oraz **2 806 080 bajtów wierzchołków podłoża i dróg** przed i po dodaniu oprawy.
Skompresowany payload trzech obrazów atlasu wynosi **2 796 256 bajtów** (2,67 MiB).
266 zadań zbudowało 1002 węzły batchy trzech LOD-ów dla 911 instancji dekoracji.
Najdłuższy zmierzony krok trwał 1,066 ms przy wcześniej sprawdzonych zasobach;
to pomiar tej próby, bez gwarancji czasu zimnego wczytania na innym sprzęcie.
Największy dąb ma 2622 / 974 / 162 trójkąty; sosna 1856 / 742 / 168.

Kadry modeli są w `art/screenshots/landscape_v5/`. Zintegrowana kampania ma
dodatkowe kadry lasu za dnia i w nocy oraz mostu z deszczem i anomalią w
`art/screenshots/world_climate/`. Uruchamia je:

```text
python tools/run_local.py godot --resolution 1280x800 --fixed-fps 60 tests/world_climate_capture.tscn --quit-after 10000
```

System nieba zachowuje istniejący obiekt `Sky`. Podmiana świeżego zasobu przed
pierwszym renderowaniem powodowała w Compatibility wyciek natywnych tekstur przy
wyjściu. Test tożsamości zasobu oraz ponowne testy `graphics_quality`,
`climate_view` i zintegrowanej kampanii potwierdziły usunięcie tego wycieku.
Weryfikacja importów obejmuje też 555 obrazów z kompresją VRAM i mipmapami;
audyt rzeczywistych GLB nie zgłosił przekroczenia nowych budżetów krajobrazu.

Osobna kopia przygotowanego drzewa Git, bez katalogu `.godot` i bez lokalnych
danych gracza, przeszła od zera import oraz siedem scen: `texture_budgets`,
`main_layout`, `world_climate`, `climate_view`, `climate_persistence`,
`climate_shelter` i `landscape_v5`. Wszystkie zakończyły się kodem 0 bez błędów
w logach. Kopia, cache i logi tej weryfikacji zostały w `tests/output/`.

Pełny historyczny runner zgłosił przy zamykaniu ostrzeżenia `ObjectDB`, pięć
zasobów nadal w użyciu oraz `PagedAllocator`, mimo wyniku 197 PASS i kodu 0.
Pojedynczy test tego runnera uruchomiony z `--verbose` oraz nowe sceny klimatu
zamykają się czysto. Nie ustalono źródła ostrzeżeń pełnego przebiegu; wymagają
osobnej diagnozy sprzątania konkretnej próby. Raport historycznych metryk oznaczył
też osiem różnic względem wzorców Etapu 2/4. Cały przebieg potwierdza zachowanie
mechanik, ale nie jest dowodem braku wycieków we wszystkich starszych testach
ani pomiarem wpływu nowej oprawy na FPS.

## Dalszy zakres

Pogoda jest obecnie kosmetyczna. Deszcz nie ma fizycznej kolizji, osobnego
systemu kałuż, mokrych materiałów ani dodatkowych plusków. System klimatu
działa w głównej kampanii `GameWorld`; osobne sceny „Próby kolosów” zachowują
swoją wcześniejszą oprawę i nie mają pełnego cyklu czasu z tego etapu.

Nie wdrożono tutaj gry sieciowej, kompana AI ani VR. Fauna, zagadki,
eksploracyjne znajdźki oraz bardziej rozbudowane reakcje konkretnych regionów
pozostają kolejnymi zadaniami. Krajobraz nadal wymaga dopracowania kompozycji,
terenów wokół aren i dalszego profilowania na starszych kartach.
