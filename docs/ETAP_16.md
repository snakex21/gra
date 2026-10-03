# Etap 16 — opcjonalny kompan i jego powtórki

Kampania pozwala wybrać samotną podróż albo dyskretnego kompana AI. Domyślnie
kompan pozostaje wyłączony. Jego podstawowy kontroler działa offline bez modelu
uczenia maszynowego i zachowuje możliwość rozwiązania każdej walki solo.
Sieciowy co-op, sterowanie drugim graczem i VR pozostają do wdrożenia.

## Zachowanie i koszt

`CompanionController` steruje drugim `PlayerCharacter` przez te same
`PlayerActions`, których używa gracz. Podąża pieszo kilka metrów za hostem,
sprawdza podłoże i przepaści, omija przeszkody i wycofuje się z ostrzeganych
ataków aktywnego kolosa. Krótkie zapamiętanie strony obejścia ogranicza oscylację
przed ścianą. Nie przejmuje Agro, wspinaczki ani głównych słabych punktów.

W bezpiecznej pozycji może pomóc rzeczywistym naładowanym strzałem z łuku
w stronę kolosa. Między strzałami mija 7,5–10 sekund. Bliskość hosta jest oceniana
poziomo, więc wsparcie działa także podczas wysokiej wspinaczki. Niebezpieczne
naciągnięcie jest anulowane zwykłą akcją schowania łuku.

Mała `CompanionPolicy` wybiera `follow`, `hold`, `support`, `evade` lub `regroup`
co 4–6 sekund. Utrwalone ziarno daje zmienność, a zapis RNG zapewnia identyczną
kontynuację checkpointu. Bezpieczeństwo ma pierwszeństwo przed wyborem taktyki.

Nawigacja działa najwyżej 10 razy na sekundę, bez serii nadrabianych zapytań po
wolnej klatce. Zwykłe podążanie wymaga siedmiu promieni; ograniczony wachlarz
obejścia i linia strzału mogą wymagać najwyżej 38 na aktualizację. Zagrożenia
pochodzą bezpośrednio od aktywnego bossa, z limitem 16 stref. Kontroler nie
przeszukuje całego drzewa scen w każdej klatce.

To lokalne omijanie: głębokie przerwy i labirynty mogą zatrzymać kompana.
Nie zmieniono prędkości biegu ani fizyki ruchu. Po dalekiej podróży Agro
`GameWorld` może wykonać rzadkie przegrupowanie w dolinie, poza kadrem i walką,
na suchym podłożu. Sprawdza wolne miejsce dla całej kapsuły, aby nie umieścić
postaci wewnątrz ściany. To przegrupowanie jest zdarzeniem powtórki.
Kontrakt: [CompanionController API](../assets/companion_controller_api.md).

## Wybór, walka i przejścia

Ustawienia oferują „Samotną podróż”, „Kompana AI” oraz „Kompana AI z lokalnym
modelem”. Zmiana działa bez dodatkowego zatwierdzania. Stare ustawienia
i niepoprawne wartości wybierają solo; wersja formatu pozostaje zgodna.

Dołączenie i odejście zachowują hosta, Agro, zdrowie słabych punktów i postęp
walki. Odejście usuwa uczestnika z encountera oraz odłącza właściciela jego
strzał w locie. Jeśli jeden uczestnik umrze, żywy partner zachowuje walkę,
a zmarły odradza się według `BossEncounter`. Śmierć wszystkich powoduje reset.

Budzenie bossa, powrót i przebudowa świata utrzymują tryb sesji. Jaskinia nadaje
obu postaciom odpowiednią warstwę światła i tryb latarki miecza; wyjście je
wyłącza. Przejście po zwycięstwie anuluje naciągnięty łuk, czyści akcje i zamraża
fizykę kompana na czas wygaszenia, po czym ją wznawia. Pauza, śmierć, zmiana
regionu, przebudowa i tytuł unieważniają oczekujące odpowiedzi backendu.

## Zapis i odtwarzanie

Checkpoint świata przechowuje tryb sesji, drugą postać, kontroler, RNG, timery
i zaakceptowaną decyzję. Przy wczytaniu używa tego trybu również wtedy, gdy
ustawienia wskazują inny; menu synchronizuje wybór z odtworzoną sesją.
Stare checkpointy bez pola kompana pozostają solo. Ustawienia wybierają nowe
sesje; sam JSON postępu kampanii nie zastępuje checkpointu świata.

`ActionReplay` zapisuje drugi strumień akcji, zmiany trybu i przegrupowania.
Odtwarzanie ustawia `external_drive`: kontroler nie czyści akcji, nie przesuwa
timerów i nie zużywa RNG. Nie wywołuje lokalnego modelu. Ruch wynika z zapisanych
akcji oraz zapisanych przegrupowań.

Zmiany trybu są stosowane przed aktorami. `CompanionFirstTick` uzupełnia pierwszą
klatkę nowo dołączonej postaci, jeśli SceneTree odroczył jej przetwarzanie;
licznik zapobiega podwójnemu wykonaniu. Przegrupowanie odtwarza się po tej samej
ukończonej klatce fizyki. Checkpoint ma osobne kursory akcji, zmian trybu
i przegrupowań. Wycinek przelicza je względem zachowanego prefiksu. Stare
nagrania bez dodatkowych pól nadal działają solo.

Zapisy i ustawienia pozostają w `data/`, runtime w `tools/runtime/`, a testowe
pliki i logi w lokalnych folderach testów. Eksperymentalne wagi, zależności
i raporty są w pomijanym przez Git `data/ai/`. Nie zapisujemy ich do profilu
użytkownika.

## Eksperymentalny lokalny backend decyzji

Asynchroniczny klient wysyła ograniczone pola stanu i pięć intencji do lokalnego
endpointu. Zapytania są nie częściej niż co 6 sekund, jedno aktywne naraz,
z timeoutem 2 sekund. Decyzja ma ograniczoną ważność i nie przejmuje fizyki.
Brak serwera, timeout lub niepoprawna odpowiedź pozostawiają zwykłą politykę.
Runtime uruchamia się ręcznie; domyślnie jest wyłączony.

Adapter badawczy uruchamia rzeczywistą głowicę Bekko przez ONNX Runtime na CPU
z dwoma wątkami i ograniczonym wejściem. Przykłady tematyczne autora potwierdziły
działanie głowicy, ale modele słabo adaptowały stan gry. Końcowa próba 17M miała
medianę około 24 ms, zbiór roboczy około 117 MiB i pamięć prywatną około 575 MiB.
Mały plik wag ani sam czas inferencji nie potwierdzają jakości decyzji lub
małego kosztu procesu. To lokalny pomiar, nie wymagania sprzętowe gry.

Nie wybrano modelu produkcyjnego. Potrzebne są reprezentatywne stany gry,
ocena poprawnych decyzji i testy kontrastowe bezpieczeństwa. Poprawne parsowanie
pięciu nazw nie dowodzi rozumienia obserwacji. Pełne wyniki, piny i polecenia:
[LOCAL_DECISION_MODELS](LOCAL_DECISION_MODELS.md).

Bekko ma [oficjalny eksport ONNX i implementację CPU](https://github.com/hotchpotch/bekko-system-one/blob/0fccbb8568b67d47745d820319fe9a4a04e7fa95/browser/README.md),
ale [karta wag nie przypisuje jeszcze licencji](https://huggingface.co/hotchpotch/bekko-system-one-v0-17m#license).
Wagi są lokalnym materiałem badawczym poza Git i dystrybucją gry; licencja kodu
referencyjnego nie zastępuje licencji wag. [K2-Type](https://huggingface.co/IFM/K2-Type-0.9B)
ma rzeczywistą głowicę wskazującą opcje, lecz oficjalna ścieżka CUDA nie zapewnia
projektowi gotowego backendu ONNX CPU. [Lumma 154M](https://huggingface.co/FrontiersMind/Lumma-fev-0.1b)
również ma głowicę decyzji; sprawdzony oficjalny pakiet nie dostarczył gotowego
eksportu ONNX. Żaden nie został tu wdrożony jako zalecany sterownik kompana.

## Potwierdzone sprawdzenia

| Test | Wynik lokalny | Zakres |
|---|---|---|
| `test_companion_policy` | 0 błędów | Ziarna, limity, bezpieczeństwo, rzeczywisty binarny codec RNG |
| `test_companion_controller` | 25 sprawdzeń, 0 błędów; headless i natywny Compatibility | Ruch, ściana, przepaść, atak, łuk, wspinający się host, replay/fade, checkpoint i dalszy ruch |
| `companion_settings` | 0 błędów | Trzy tryby, legacy, przenośny JSON, zmiana i odwrócenie, klawiatura/pad, 720p/900p |
| `companion_world` | 0 błędów; headless i czysty natywny Compatibility | Dołączenie/odejście, odrodzenie, światło jaskini, freeze, checkpoint, autozapis i rzeczywisty powrót poza kamerą po 5 s; odmowa w walce, wodzie i przy zajętym lub niebezpiecznym podłożu |
| `companion_replay` | 37 sprawdzeń, 0 błędów | Dwa strumienie, późna decyzja, zmiany trybu, przegrupowanie, seek i wycinek |
| `test_companion_controller_review` | 0 błędów; headless i czysty natywny Compatibility | Wolna kapsuła, replay od tick 0 przez odejście i powrót, regroup po fizyce |
| Harness lokalnej decyzji | 40 sprawdzeń Godota + 8 testów Python, 0 błędów | Rzeczywiste HTTP, whitelist, generacja, timeout i niepoprawne dane |
| Pełny historyczny runner | 197 testów, 0 niepowodzeń, kod 0 | Mechaniki, ruch, Agro, stare powtórki i ustawienia; ograniczenia poniżej |

Nowe sceny kompana zamykają natywny renderer bez wycieków tekstur. Krótkie
fixture czekają na pierwsze ukończone renderowanie przed zwolnieniem GameWorld,
aby uniknąć znanego problemu lifetime świeżego Sky w Compatibility.

Pełny historyczny runner ponownie zgłosił ostrzeżenia `ObjectDB`, pięć zasobów
w użyciu oraz komunikat `ERROR` z `PagedAllocator` przy zamykaniu, mimo 197 PASS i kodu 0. Nie było
błędów skryptów. Raport oznaczył siedem różnic starszych metryk Etapu 2/4;
nie są pomiarem FPS modeli. Wynik mechanik nie dowodzi braku wycieków
w każdej starszej próbie i nie usuwa zadania sprzątania tego runnera.

```text
python tools/run_companion_tests.py
python tests/test_local_decision.py
python tests/test_local_decision_http.py
python tools/run_local.py godot --rendering-method gl_compatibility tests/companion_world.tscn
python tools/run_local.py godot --rendering-method gl_compatibility tests/test_companion_controller_review.tscn
```

Ścisły runner uruchamia dziewięć scen z limitem czasu i odrzuca także błędy
skryptów przy kodzie 0. Pozwala zawęzić zestaw przez `--scene companion_replay`,
a wskazać silnik przez `--godot`. HTTP uruchamia się przez harness Python,
który sam tworzy i zamyka serwer. [CI](../.github/workflows/tests.yml) zawiera
osobny krok tych testów. Wynik Windows nie potwierdza ukończonego CI na Linuxie.

## Pozostały zakres

Kompan działa w kampanii. Samodzielne próby kolosów zachowują wcześniejszą
konfigurację. Do dalszej pracy pozostają pełna nawigacja, woda i osobny
wierzchowiec kompana, drugi gracz i sieć, komfort VR oraz model o potwierdzonej
jakości i jasnych warunkach dystrybucji. Wymagania sprzętowe nadal wymagają
pomiarów na rzeczywistym starszym sprzęcie.
