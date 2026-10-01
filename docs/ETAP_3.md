# Etap 3 — naturalny ruch kolosa: foot planting, IK, balans ciała

Pytanie etapu: **czy kolos może poruszać się jak ciężkie, żywe stworzenie, nie psując wspinania?**
Odpowiedź z testów: tak. Stopy w fazie STANCE nie ślizgają się (≤0,0004 m/s), teren jest
obsługiwany, a wszystkie 31 testów z Milestone 1 i Etapu 2 nadal przechodzą.

## Architektura

```
Brain -> Intent -> desired movement (desired_velocity, desired_turn_rate)
      -> LocomotionController   body mass: speed with limited jerk, turn rate with limited acceleration
         -> step planner        STANCE/SWING per leg, steps when needed, 1 ground probe per step
         -> pelvis / COM        continuous weight transfer, reach-limited height, lean
      -> rig (GreyboxHumanoid)  two-bone IK onto planned feet, upper body, shake, head
      -> skeleton -> BodySegment (colliders the player climbs)
```

- **`LocomotionController`** (`src/locomotion/`) nie zna kości ani intencji i działa dla
  N nóg (`max_swinging`), więc nada się też dla Spidera czy innego czworonoga.
  Z wartości ciągłych sam wyprowadza kadencję, długość kroku, timing, cele stóp, pochylenie
  i miednicę.
- **Brain nie steruje nogami.** Kolos zamienia intencję na pożądaną prędkość i tempo skrętu
  (tryb debug `manual` podaje je bezpośrednio).
- **`TwoBoneIK`** to analityczne IK dla dwóch kości z biegunem kolana. Nie dochodzi do pełnego
  wyprostu (99,5%).
- **`LocomotionDebugDraw`** (F3) pokazuje:
  - stopę w STANCE (zielona) i w SWING (żółta),
  - cel kroku (cyjan),
  - normalną podłoża,
  - linię podparcia,
  - środek masy i jego rzut.

### Kroki
- **STANCE:** punkt kontaktu jest zamrożony w świecie, IK trzyma stopę, a ciało przesuwa się nad nią.
- **SWING:** łuk jest gładki aż do przyspieszenia (C²): poziomo smootherstep, w pionie
  64t³(1−t)³. Prędkość i przyspieszenie wynoszą 0 przy oderwaniu i postawieniu, więc gracz
  na nodze nie dostaje szarpnięcia.
  Szczytowe przyspieszenie stopy jest ograniczone do 16 m/s²: długi krok trwa dłużej.
- **Cel kroku** uwzględnia:
  - przewidywaną pozycję i kurs ciała w chwili postawienia (prędkość, tempo skrętu),
  - nominalną pozycję stopy pod biodrem,
  - wyprzedzenie o połowę drogi ciała w czasie podparcia,
  - wysokość i normalną terenu (1 promień na krok, ewentualnie 1 w połowie lotu, gdy plan się zmienił).

  Druga noga wynika z naprzemienności, a środek ciężkości z obciążeń (poniżej).
- **Timing według potrzeby:** w ruchu noga stawia krok, gdy minie czas podwójnego podparcia.
  Gdy kolos stoi, stopy są tylko korygowane, jeśli odjechały o więcej niż 0,35 m.
  Gdy zaparty jest do wstrząsu, nie przestawia stóp.
  Noga bliska pełnego wyprostu dostaje krok natychmiast.
- **Skręt:** stopy obracają się z planowanym kursem. Wewnętrzna i zewnętrzna noga robią różne
  kroki, bo cele obracają się wokół ciała. Tułów i głowa wyprzedzają skręt bioder.

### Miednica i balans
- **Obciążenie nóg** (`load`) zmienia się w sposób ciągły. W podwójnym podparciu ciężar
  przechodzi na nogę, która zostaje; noga odrywa się przy obciążeniu 0,00. Środek podparcia
  jest średnią ważoną obciążeniem, więc nigdy nie skacze.
- **Pozycja pozioma:** miednica przesuwa się o 35% nad nogę podporową, z wyprzedzeniem
  proporcjonalnym do prędkości.
- **Wysokość:** to ograniczenie zasięgu każdej nogi, przy czym cel nogi w locie wchodzi
  w pierwszych 60% lotu. Ograniczenia łączy „miękkie minimum” (bez załamań). Falowanie wynika
  z geometrii, nie jest dodane osobno.
- **Sprężyny krytycznie tłumione:** w pionie są miększe niż w poziomie, a ruch ciała jest
  podawany z wyprzedzeniem (feed-forward), więc miednica nie zostaje za stopami.
- **Pochylenie i wyprzedzenie skrętu:** ciało pochyla się w stronę przyspieszenia (start, hamowanie,
  dośrodkowe w skręcie). Pochylenie, wyprzedzenie skrętu i przechył miednicy przechodzą przez
  filtry drugiego rzędu.

### Zasada odkryta w tym etapie: każdy człon pozy musi być gładki (C²)
Bark jest 6–10 m od stawów. Samo *załamanie* kąta (skok prędkości kątowej) daje tam pik
przyspieszenia rzędu 100+ m/s², który zrzuca stojącego gracza albo drenuje staminę
wspinającemu się.

| Znalezione źródło szarpnięcia | Pik przed | Rozwiązanie |
|---|---|---|
| `sin(πt)` w przechyle miednicy i w unoszeniu stopy | 158 m/s² | `sin²`, a potem krzywa C² 64t³(1−t)³ |
| pochylenie ∝ przyspieszenie, wyprzedzenie ∝ tempo skrętu (oba z załamaniami na limitach) | ~100 m/s² | filtry drugiego rzędu |
| `clamp` przeciwskrętu tułowia przy długim kroku | 14 m/s² | `tanh` |
| skok środka podparcia przy oderwaniu stopy | 20–50 m/s² | ciągłe obciążenia nóg |
| ograniczenie wysokości znikające przy oderwaniu stopy | 13 m/s² | efektywna stopa + miękkie minimum |
| wykładnicze dojście celu po ponownym planie | 107 m/s² (stopa) | sprężyna (ciągła prędkość) |

## Wyniki testów

`tools/run_tests.sh`: **48 PASS, 0 błędów**: 31 testów z M1 i Etapu 2, 15 nowych testów
Etapu 3, porównanie A/B i sonda kalibracyjna.

| Test | Wynik |
|---|---|
| planted_foot_does_not_slide | poślizg w STANCE maks. 0,0003 m/s, błąd IK 0,000 m |
| walking_on_slope_places_feet_correctly | teren: rampa 10°, nierówności, stopień 0,8 m; błąd wysokości stopy 0,000 m, normalne zgodne, poślizg 0,0002 m/s, bark ≤4,3 m/s² |
| turning_uses_stable_steps | obrót w miejscu o 2,5 rad w 5 krokach, nigdy dwie stopy w powietrzu, poślizg 0,0001 m/s |
| start_and_stop_are_smooth | idle → walk → szybciej → skręt → walk → stop: \|a\| ≤ 1,25 m/s², zryw ≤ 1,5 m/s³, bark ≤ 4,9 m/s², 0 kroków po zatrzymaniu |
| walk_shake_walk_transition | 1,34 → 0,01 → 1,40 m/s, płynnie; stopy zaparte |
| pelvis_tracks_support_area | miednica przesuwa się 0,35 m nad nogę podporową; noga odrywa się przy obciążeniu 0,00 |
| grip_does_not_drift_during_procedural_step | dryf chwytu 0,00000 m przez kolejne kroki |
| standing_player_remains_attached_during_step | gracz na stopie przejeżdża cały krok, równowaga 0,99 |
| standing_on_shoulder_during_start_stop | dryf 8 mm, równowaga 1,00 |
| player_on_leg_survives_step_transition | 4 przejścia oderwanie/postawienie, bez teleportu (2. różnica 7 mm) |
| grip_on_hips_during_turn | dryf 0, poziom wstrząsu 0,00 |
| grip_on_back_during_sudden_direction_change | dryf 0, maks. 5,05 m/s² |
| shake_behavior_unchanged_after_locomotion | koszt staminy przy chwycie 53,9 (wzorzec 54,2); utrata równowagi 0,95 s (wzorzec 1,28) |
| locomotion_is_independent_of_render_fps | 30/60/144/240 FPS renderowania, ten sam stan symulacji co do bitu (różnica 0) |
| locomotion_cost_stays_within_reasonable_budget | kolos ~130 µs/tick (IK ~20 µs), 0,01 promienia/tick |

Wzorzec z Etapu 2 (`tests/baseline/etap2_baseline.json`) jest porównywany przy każdym
uruchomieniu. Flagowane są tylko koszty CPU (opis niżej) oraz 0,18 promienia na tick przy
staniu podczas wstrząsu: to promień, który potwierdza podparcie, gdy zatrzaśnięcie do podłoża
nie zgłasza kolizji (naprawił migotanie obserwacji „gracz na ciele”).

## A/B: proceduralny + IK vs animacja + IK (F4)

Ten sam skryptowany przebieg (25 s po torze z rampą, nierównościami i stopniem), ten sam ruch
ciała, ta sama górna część ciała:

| Tryb | Poślizg stóp śr. / maks. | Błąd stopa–podłoże | Pik barku | Logika kolosa (w tym IK) | Promienie/tick | Poślizg w skręcie | Wspinanie na idącym kolosie |
|---|---|---|---|---|---|---|---|
| **proceduralny + IK** | **0,0000 / 0,0002 m/s** | **0,000 m** | 4,3 m/s² | ~130 µs (IK 20) | 0,01 | 0,0002 m/s | ok |
| animacja + IK | 0,67 / 1,51 m/s | 0,14 m | **1,15 m/s²** | ~140 µs (IK 40) | 3,0 | 1,42 m/s | ok |
| stary FK (bez IK) | 0,68 / 1,50 m/s | 3,46 m | 0,95 m/s² | ~80 µs | 0 | 1,42 m/s | ok |

Animacja + IK dostała uczciwe warunki: kontakt wynika z faz cyklu (jak oznaczenia „foot plant”
w klipie), a korekta miednicy jest wygładzona.

**Wnioski:**
- Proceduralny tryb eliminuje poślizg stóp i poprawnie stawia stopy na terenie przy podobnym
  koszcie CPU (proceduralny jest nawet trochę tańszy, bo robi 1 promień na krok zamiast 3 na
  tick).
- **Animacja + IK daje spokojniejszy bark** (1,15 vs 4,3 m/s²), bo jej ciało nie przenosi ciężaru
  z nogi na nogę. Proceduralne kołysanie to cena za czytelny ciężar. Dla stojącego gracza 4,3 m/s²
  mieści się w pojemności równowagi (6 m/s²) i wszystkie testy stania przechodzą. Siłę kołysania
  stroi parametr `sway`.
- Animacja ślizga stopami, bo pętla nie zna prędkości ciała, kierunku skrętu ani terenu. Da się
  to poprawić siatką klipów i dopasowaniem prędkości, ale to dokładnie to, co planer kroków
  daje za darmo.
- **Rekomendacja:** **hybryda**, która już jest w kodzie: planowane stopy, IK i miednica
  proceduralnie, a ręce, tułów i oddech jako autorskie krzywe sterowane fazą kroku. Gdy powstaną
  prawdziwe modele, autorskie animacje mogą zastąpić górną część ciała i styl (np. animowany
  łuk stopy), a planer zostanie źródłem miejsc postawienia stóp.

## Fizyka vs FPS renderowania

- Symulacja (kolos, locomotion, gracz, balans, stamina) działa wyłącznie w stałym kroku 60 Hz.
  Test uruchamia ten sam scenariusz jako osobne procesy przy 30/60/144/240 FPS renderowania:
  stan końcowy jest identyczny co do bitu.
- Interpolacja fizyki (Godot 4.4) interpoluje kości, segmenty kolosa i gracza między tickami.
  Kamera działa w `_process` na interpolowanej pozycji gracza. Wejście kamery (mysz, drążek)
  nie jest ograniczone do ticku.
- Fizyka nie została podniesiona do 120/240 Hz. Jeśli kiedyś będzie potrzebna lokalna większa
  częstotliwość, planer i IK można podzielić na podkroki niezależnie od świata.

## Koszt CPU (headless, minimum z 4 powtórzeń, scenariusz benchmarku M1)

| | Etap 2 | Etap 3 |
|---|---|---|
| logika kolosa | 60 µs/tick | 122 µs/tick |
| logika gracza | ~70 µs | ~60 µs |
| klatka | 0,31 ms | 0,34 ms |

+60 µs na tick na kolosa (planer ~10–20, miednica i poza ~30, IK ~20) to ~0,4% budżetu klatki
przy 60 Hz. Brak alokacji przyrastających na klatkę (przyrost obiektów −1 przez 300 ticków).
Nie ma powodu do optymalizacji ani przenoszenia do Ziga bez profilu w realnej scenie.

## Inne zmiany wymuszone przez regresję
- Głowa nie śledzi gracza stojącego na ciele kolosa (zamiatała bark i spychała gracza).
- Obserwacja „gracz na ciele” toleruje 0,5 s utraty kontaktu, a gracz potwierdza podparcie
  promieniem, gdy zatrzaśnięcie ukrywa kolizję.
- Wciąganie się na krawędź szuka miejsca wzdłuż krawędzi, a skok wzdłuż przewieszenia trzyma
  się powierzchni.
- Chwyt szuka też futra przed klatką piersiową (pochylone kończyny).
- Stopa greyboxa jest dłuższa (3,6 m), więc da się na niej stać.

## Do playtestu przez człowieka
- Czy kołysanie miednicy (35%) i falowanie w pionie czytają się jako ciężar, a nie jako chybotanie?
  Porównaj F4 na żywo.
- Wspinanie po nodze w trakcie kroku: łydka w locie daje poziom wstrząsu do ~0,9 (koszt staminy).
  Czy to dobre wyzwanie, czy przesada?
- Tempo startu, hamowania i skrętu (masa): przyspieszenie 0,5 m/s², hamowanie 1,25 m/s², skręt 0,25 rad/s².
- Kolos przy maks. 2,2 m/s: czy kroki nie są za długie?

## Znane ograniczenia
- Stopy nie omijają przeszkód w locie: łuk ma tylko zapas wysokości dla stopnia, bez wykrywania
  krawędzi.
- Brak dynamiki potknięcia samego kolosa (np. stopa na krawędzi). Planer zawsze znajduje
  podłoże albo zostaje na wysokości ciała.
- Kolano celuje w kierunek stopy z lekkim odchyleniem na zewnątrz. Przy bardzo ostrych skrętach
  w miejscu kolano może wyglądać sztywno.
