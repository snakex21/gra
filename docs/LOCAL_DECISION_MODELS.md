# Lokalny wybór taktyki — etap 16

Kompan działa samodzielnie dzięki `CompanionPolicy`. Lokalny model jest opcjonalnym, domyślnie wyłączonym eksperymentem. Dodany transport i rzeczywista inferencja CPU działają, ale wykonane sondy nie uzasadniają powierzenia tym modelom taktyki gry bez dalszego dopasowania. Brak serwera, timeout, pauza lub błędna odpowiedź pozostawiają zwykłą politykę aktywną.

## Kontrakt gry

`src/companion/local_decision_client.gd` to `Node` umieszczany poza regionem świata. Właściciel ustawia `enabled` oraz wywołuje `request(observation: Dictionary, allowed: Array, generation: int) -> bool`. Przy poprawnej odpowiedzi otrzymuje `decision_ready(intent: StringName, generation: int)`. `cancel()` unieważnia trwające żądanie, także spóźniony callback. Wywołujący zachowuje własną generację po zmianie regionu, odtworzeniu zapisu i zmianie trybu gry.

Słownik jest zamknięty: `follow`, `hold`, `support`, `evade`, `regroup`. Model zwraca wyłącznie propozycję taktyki. Ruch, unikanie niebezpieczeństw, wsparcie i sprawdzanie dopuszczalności nadal należą do kontrolera. Klient przyjmuje tylko skalary:

| Klucze | Typ i zakres |
| --- | --- |
| `health` | liczba 0–100 |
| `stamina` | liczba 0–1 |
| `leader_distance` | liczba 0–10000, metry |
| `enemy_distance` | liczba -1–10000, -1 oznacza brak obserwowanego przeciwnika |
| `threat`, `enemy_active`, `leader_climbing`, `support_available`, `near_cliff`, `mounted`, `player_downed`, `leader_downed`, `ground_safe`, `navigation_blocked` | `bool` |
| `intent` | aktualna taktyka z powyższego słownika |

Nieznane pola, tekst gracza, obiekty, Node/RID, nieskończoności i liczby zamiast flag są odrzucane. Żądanie wymaga niepustej obserwacji, 1–5 dozwolonych taktyk i generacji 0–2147483647. Odpowiedź JSON zawiera dokładnie `intent` i `generation`, zgodną z żądaniem. Transport nie udostępnia narzędzi ani wykonywania wygenerowanego kodu.

Klient wykonuje asynchroniczny POST wyłącznie na `http://127.0.0.1:8766/decision`, bez przekierowań i konfigurowalnego adresu. Limit odpowiedzi wynosi 2048 B, timeout 2 s, minimalny odstęp 6 s. Błędy zwiększają odstęp do 6/12/24/48/60 s; nie ma automatycznych powtórek. Pauza i usunięcie węzła anulują pracę. Tytuł, replay i wyłączenie kompana obsługuje integracja przez `enabled = false` oraz `cancel()`.

## Faktycznie uruchomione modele

[Bekko System One 17M](https://huggingface.co/hotchpotch/bekko-system-one-v0-17m) jest modelem decyzyjnym: shared-prefix encoder i głowica Choice oceniają opisane kandydatury równolegle, bez generowania tekstu. To pasuje do zamkniętych taktyk. Adapter używa oficjalnego ONNX oraz tokenizera; segmenty prefiksu koduje osobno, przekazuje maski bool i indeksy właścicieli int64 oraz odczytuje kolumnę Choice. Sposób wejścia opisuje [kod autora przypięty do konkretnej rewizji](https://github.com/hotchpotch/bekko-system-one/blob/0fccbb8568b67d47745d820319fe9a4a04e7fa95/browser/README.md).

Uruchomiono 17M i 68M z ONNX Runtime 1.30.0, dwoma wątkami CPU, wyłączonym aktywnym oczekiwaniem i bez Torch, CUDA czy zdalnego kodu. Prefiks jest ograniczony do 448 tokenów, gałąź do 64; przepełnienie odrzuca propozycję. Stan jest renderowany jako stałe angielskie zdania faktów, z zachowaniem liczb i jednostek, następnie pakowany w JSON. Renderer nie oblicza wybranej taktyki, nie dodaje etykiety odpowiedzi i nie przechowuje wyników.

Ważne ograniczenie dystrybucji: autor [nie przypisał jeszcze licencji wydanym wagom Bekko](https://huggingface.co/hotchpotch/bekko-system-one-v0-17m#license). Licencja MIT publicznego kodu nie obejmuje automatycznie wag. Wagi są wyłącznie lokalnymi plikami badawczymi w ignorowanym `data/ai`; przed dystrybucją potrzebne jest wyjaśnienie licencji. Wielkość ONNX 29 MB nie oznacza 29 MB RAM ani całej instalacji.

Porównano również [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B), kwantyzację Q4_0 wydaną przez [zespół ggml-org](https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF), [LiquidAI LFM2.5-1.2B-Instruct Q4_K_M](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF) i starszy [Qwen2.5-0.5B-Instruct Q4_K_M](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) jako punkt odniesienia. Qwen ma Apache-2.0. LFM ma [własną licencję Open License 1.0](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/blob/8ed288026e23958ad9dfa92d53ed773a8eee7125/LICENSE), zawierającą próg rocznego przychodu 10 mln USD; nie opisujemy jej jako Apache.

Runtime llama.cpp jest przypięty do [b11010](https://github.com/ggml-org/llama.cpp/releases/tag/b11010), wyłącznie CPU: 2 wątki, 512 tokenów kontekstu, 12 tokenów wyjścia, jedna kolejka, `--offline`, bez narzędzi i interfejsu WWW. Native server działa na 127.0.0.1:8767 z losowym kluczem procesu. Adapter pobiera właściwy szablon checkpointu przez `/apply-template`, wyłącza thinking i stosuje gramatykę dozwolonych nazw. Gotowość jest notyfikacją stdout procesu, bez pollowania `/health`. Mechanizm szablonów i ograniczeń opisuje [oficjalna dokumentacja runtime](https://github.com/ggml-org/llama.cpp/blob/b11010/tools/server/README.md).

## Wyniki lokalnych sond

Maszyna: Windows 10, procesor zgłoszony jako `AMD64 Family 25 Model 33 Stepping 2, AuthenticAMD`. Pomiar CPU nie korzysta z GPU. Dla modeli generujących tekst użyto 10 małych stanów oraz pełnego promptu mieszczącego się w 512 tokenach. Są to sondy zgodności z instrukcją tego adaptera; nie są ogólnym rankingiem modeli, porównaniem benchmarków autorów ani pomiarem FPS gry. W spokojnym stanie obok lidera `hold` również może być akceptowalnym stylem, mimo celu `follow` w pierwszej sondzie.

| Model i adapter | Mediana / maksimum | Peak working set | Private committed | Zgodność ścisła z 10 celami |
| --- | --- | --- | --- | --- |
| Bekko17, fakty opisane po angielsku | 24 / 26 ms | 117 MiB | 575 MiB | 1/10 |
| Bekko68, ten sam renderer | 180 / 190 ms | 438 MiB | 756 MiB | 2/10 |
| Qwen3.5 Q4_0, szablon checkpointu, scalarny JSON | 1116 / 1217 ms | 991 MiB | 647 MiB | 1/10; 10 poprawnych nazw |
| LFM2.5 Q4_K_M, szablon checkpointu, scalarny JSON | 1572 / 1757 ms dla ukończonych | 1241 MiB | 552 MiB | 1/10; 4 odpowiedzi, 6 timeoutów |
| Qwen2.5 Q4_K_M, ten sam tryb szablonu i JSON | 476 / 1012 ms | 483 MiB | 146 MiB | 1/10; 10 poprawnych nazw |

Bekko17 zwykle wybierał `support`, a 68M `regroup`. Cztery dodatkowe pary różniące się jednym faktem — atakiem, klifem, gruntem lub zdrowiem — nie zmieniły ich decyzji na `evade` w wariancie zagrożenia (0/4). Te pary były dodatkowym sprawdzianem po ustaleniu renderera. Jednocześnie oba modele poprawnie zmieniały wybór `sports`/`business` dla dwóch artykułów z przykładu autora, z różnymi logitami. Potwierdza to działanie głowicy, nie dobrą adaptację do naszej gry.

Początkowe sondy surowego JSON i ręcznego ChatML dały Qwen2.5 2/10, Qwen3.5 3/10 i LFM 1/10. Zmieniono następnie rendering szablonu, a nie ukryto tych wyników. Wniosek dla projektu jest ograniczony: obecny adapter nie wykazał przewagi nad zaprogramowaną polityką. Wybór modelu wymaga testów z rzeczywistymi stanami gry oraz par sytuacji, rozsądnych zbiorów akceptowanych taktyk i ewentualnego lekkiego dopasowania do zadania. Nie wybieramy modelu tylko na podstawie daty, liczby parametrów czy małego pliku.

## K2-Type, Lumma i dalsze kandydatury

Użytkownik wskazał właściwy model: [IFM/K2-Type-0.9B](https://huggingface.co/IFM/K2-Type-0.9B), nie K2-Horizon. K2-Type jest modelem decyzyjnym z głowicą pointer; oficjalny kod `jev` koduje stan i kandydatów znacznikami specjalnymi, używa osobnych gałęzi attention i resetowanych pozycji. Standardowe generowanie z GGUF pomijałoby tę semantykę. Rewizja badana: `0648c43e30d20d85b621e3604c397f8af4d5b1de`, Apache-2.0. Opublikowany serwer wymaga CUDA/Torch; w repo nie znaleziono gotowego eksportu ONNX tej głowicy. Nie uruchomiono go tutaj i nie przypisujemy mu pomiarów CPU innych modeli.

[Kolekcja Lumma Decision Models](https://huggingface.co/collections/FrontiersMind/lumma-decision-models) zawiera m.in. [Lumma-fev-0.1b](https://huggingface.co/FrontiersMind/Lumma-fev-0.1b), około 154M parametrów, również z głowicą pointer. Wagi i kod mają Apache-2.0, badana rewizja `4eb5d5ceec18cc42d3a0e7227b090b90dcd20ab8`. Nie znaleziono gotowego ONNX w tym repo. To sensowny kandydat do osobnego eksportu CPU i weryfikacji zgodności głowicy, zamiast zastępowania jej generowaniem odpowiedzi. Nie przeprowadzono ciężkiego treningu GPU.

Zbadano również [SmolLM2-360M-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct) i [Qwen3-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF), oba Apache-2.0. Nie są modelami pointer/Choice i nie były tu benchmarkowane. K2-Horizon jest osobnym modelem generującym tekst; jego wyniki nie rozstrzygają przydatności K2-Type.

## Instalacja, uruchomienie i sprawdzenie

Wszystkie modele, koła Python, binaria, pliki tymczasowe, licencje i wyniki trafiają do `data/ai`. Katalog jest ignorowany przez Git. Instalatory sprawdzają dokładny rozmiar i SHA256 przypiętych artefaktów. Nie aktualizują systemowego Python, nie używają profilu ani modelowego cache Hugging Face. Bekko wheels są przypięte dla Windows x64/Python 3.13; inne platformy wymagają osobnych zweryfikowanych pinów. Nie ma automatycznego pobierania modelu podczas uruchamiania gry.

```text
python tools/ai/install_bekko.py
python tools/ai/benchmark_bekko.py
python tools/ai/run.py --backend bekko-research

python tools/ai/install_bekko.py 68
python tools/ai/benchmark_bekko.py 68
python tools/ai/run.py --backend bekko68-research

python tools/ai/install.py pins_qwen35.json
python tools/ai/benchmark.py pins_qwen35.json
python tools/ai/run.py --backend qwen35

python tools/ai/install.py pins_lfm.json
python tools/ai/benchmark.py pins_lfm.json
python tools/ai/run.py --backend lfm

python tools/ai/install.py pins_qwen25.json
python tools/ai/benchmark.py pins_qwen25.json
python tools/ai/run.py --backend qwen25
```

`run.py` wymaga jawnego wyboru backendu. `pins.json` jest aliasem nowego Qwen3.5 do lokalnego researchu; nie ustawia modelu domyślnego w grze. Proces można zamknąć Ctrl+C; runtime llama.cpp jest wtedy również zamykany. Wyniki benchmarków są zapisane jako `data/ai/benchmark_*.json`.

```text
python tests/test_local_decision.py
python tests/test_local_decision_http.py
python tests/test_local_decision_http.py --godot /absolute/path/to/godot

# opcjonalnie, po instalacji lokalnego modelu
python tests/test_local_decision_live.py
python tests/test_local_decision_model_smoke.py
python tests/test_local_decision_model_smoke.py 68
```

Weryfikacja: 8 testów Python — PASS; prawdziwy klient Godot i kontrolowany serwer HTTP — 40 sprawdzeń, 0 błędów, czyste wyjście. Obejmuje niedozwolone dane, ścisły słownik, błędną generację, stary callback po `cancel()`, pauzę, limit równoległości, cooldown i rzeczywisty timeout około 2 s. Harness obsługuje `GODOT`/`--godot`, lokalne katalogi danych oraz traktuje błędy skryptu jako niepowodzenie nawet przy exit 0. Sceny `test_local_decision.tscn` nie należy uruchamiać bez harnessu, bo wymaga jego mock serwera. Dodatkowy live smoke potwierdził poprawną, ograniczoną odpowiedź z rzeczywistej głowicy Bekko przez lokalny HTTP.
