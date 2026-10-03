# WorldClimate — etap 15

Czysty model `RefCounted` w `src/world/world_climate.gd`. Nie tworzy węzłów ani zasobów renderowania, nie używa zegara systemowego i nie konsumuje globalnego RNG. Warstwa graficzna oraz zapis świata należą do integracji w `GameWorld`.

- `WorldClimate.new(world_seed: int = 146021)` — nowy świat zaczyna o 08:00. Seed w zakresie 1–2147483646 wybiera dalszą sekwencję pogody; pierwszy front jest pogodny.
- `advance(delta: float)` — wyłącznie sekundy symulacji z kroku fizyki. Pauza oznacza brak wywołania albo `delta = 0`. Doba trwa 1800 sekund. Ujemne i niefinitywne wartości są ignorowane; zegar ma bezpieczny limit 100 lat symulacji.
- `sample(region_kind: StringName = &"valley", defeated_count: int = 0, completed: bool = false) -> Dictionary` — czysty odczyt; nie zmienia stanu. Parametr regionu przyjmuje nazwę starcia lub regionalny profil `ForbiddenLands.REGIONS`.
- `to_dict() -> Dictionary` — wyłącznie `version: 1`, `seed: int`, `elapsed: float` i `compensation: float`. Mała poprawka sumowania czasu zapewnia kontynuację po checkpointach bez narastającego błędu dodawania. Wynik można przechowywać w JSON albo binarnym snapshotcie.
- `from_dict(data: Dictionary, legacy_elapsed: float = 0.0) -> bool` — przed odczytem resetuje model. Brak/nieznana wersja lub uszkodzony zegar odtwarzają czas ze starego `play_time` i zwracają `false`. Poprawny zegar wersji 1 zwraca `true`; brak/uszkodzenie opcjonalnego seeda lub poprawki używa ich wartości domyślnych. Liczby z JSON są akceptowane, tekstowe liczby nie.

| Klucz `sample()` | Typ / zakres | Znaczenie |
|---|---|---|
| `hour` | float, [0, 24) | Godzina lokalna świata |
| `day_index` | int, ≥ 0 | Liczba przekroczonych północy; nowa gra: 0 |
| `sun_height` | float, [-1, 1] | Astronomiczna wysokość słońca; szczyt o 12:00 |
| `daylight` | float, [0, 1] | Światło dzienne z miękkim świtem i zmierzchem |
| `rain`, `cloud`, `fog` | float, [0, 1] | Siła deszczu, zachmurzenia i mgły; mgła nie jest bezpośrednią gęstością shadera |
| `haze` | float, [0, 1] | Pył w suchych regionach |
| `wind_strength` | float, [0, 1] | Atmosferyczny wiatr; nie siła działająca na gracza |
| `wind_direction` | Vector3, jednostkowy XZ | Poziomy kierunek wiatru; nie jest kątem |
| `exposure` | float, [0, 1] | Otwarta przestrzeń: 1, jaskinie: 0, świątynia/finał: 0,30 |
| `anomaly` | float, [0, 1] | Nasilenie odzyskiwanej mocy Dormina |
| `weather_id` | String | `clear`, `overcast`, `rain`, `mist`, `windy` lub pustynne `haze` |

Fronty są wyznaczane z utrwalonego seeda i indeksu czasu, z miękką interpolacją przez 240 sekund. Kierunek wiatru korzysta z interpolacji kątowej, więc nie zanika podczas zmiany kierunku. Nazwa frontu wskazuje dominującą stronę przejścia; jest etykietą do prezentacji, natomiast wszystkie intensywności pozostają ciągłe.

Pustynie Phalanxa i Worma zamieniają deszcz w pył. Jaskinie Dirge'a, Devila, Barby i Hollowvault/Deeprelic mają lokalną mgłę bez opadu i wiatru. Jeziora, lasy, wyżyny, gejzery oraz krater mają odrębne profile. Nieznane nazwy przyjmują profil doliny. Kolejne zwycięstwa podnoszą zachmurzenie, mgłę i powolne pulsowanie anomalii; `completed = true` usuwa ten wpływ, a naturalna pogoda działa dalej. Model nie zmienia sterowania ani fizyki walk.

Weryfikacja: `python tools/run_local.py godot --headless --path . tests/world_climate.tscn --quit-after 10000`. Test ma własny watchdog i obejmuje dobę, zgodność 30/60/120 Hz, deterministyczność, ciągłość frontów, brak mutacji podczas odczytu, binarny/JSON zapis i kontynuację, migrację starych zapisów, uszkodzone pola, regiony i finał.
