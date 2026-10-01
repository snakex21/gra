# Etap 4 — Agro: koń, który nie jest samochodem

Pytanie etapu: **czy jazda na Agro daje poczucie zwierzęcia z masą, a nie pojazdu?**
Odpowiedź z testów: koń ma bezwładność, promień skrętu rośnie z prędkością, a cztery kopyta
stoją w miejscu (≤0,002 m/s) także na rampie, nierównościach, stopniu i kłodzie. Koń sam omija
skały, przechodzi przez wąskie przejście, przekracza niskie przeszkody, staje przed ścianą
i urwiskiem. Kamera jest niezależna od kierunku jazdy. Wszystkie 48 testów z Milestone 1
i Etapów 2–3 nadal przechodzą (razem 70/70).

## Architektura

```
rider (gracz / AI kompan / test)  ->  build_ride_intent(HorseInputIntent)   bez klawiszy i kamer
AI konia (follow / come / stop)   ->  ten sam HorseInputIntent
   -> HorseController   "umysł i masa": poziom chodu (kopnięcie / wodze / pchnięcie drążka),
                        prędkość z limitem przyspieszenia i jerk, tempo skrętu ograniczone
                        promieniem R(v), lokalne omijanie, hamowanie przed ścianą i krawędzią
   -> QuadrupedGait     zegar chodu (IDLE/WALK/TROT/GALLOP), fazy nóg, kroki zdarzeniowe,
                        1 sonda gruntu na krok
   -> Horse (_pose)     wysokość tułowia ograniczona zasięgiem nóg, bob, pochylenie z terenu
                        i przyspieszenia, przechył w zakręcie, szyja i głowa, IK czterech nóg
   -> Skeleton3D        siodło = kość "body"  ->  PlayerRiding (jeździec zakotwiczony do kości)
```

- **Koń jest `CharacterBody3D`** i porusza się przez `move_and_slide` (tylko w poziomie).
  Nawet gdy sondy niczego nie wykryją, ściana zatrzymuje ciało, a kontroler traci prędkość
  (`report_actual_speed`). Nie da się przebić przez przeszkodę w galopie.
- **Wspólne elementy z locomotion kolosa** są tylko tam, gdzie ma to sens. Trafiły do
  `src/locomotion/step_math.gd`: łuk swingu (C², smootherstep + 64t³(1−t)³), dociąganie celu
  kroku, postawienie stopy, sonda gruntu. `LegState` i `TwoBoneIK` są wspólne. Zegar chodu
  czworonoga (`QuadrupedGait`) jest osobny, bo kolos stawia kroki „według potrzeby”, a koń
  ma rytm. `LocomotionController` kolosa przepięto na `StepMath` bez zmiany zachowania:
  testy Etapu 3 przechodzą z tymi samymi wynikami co w ETAP_3.md (poślizg stóp 0,0003 m/s,
  A/B procedural 0,0002 m/s, niezależność od FPS 0).
- **`current_rider` można podmienić.** Jeźdźcem jest dowolny węzeł z `build_ride_intent()`:
  gracz (`PlayerCharacter` → `PlayerRiding`), `ScriptedHorseDriver` w testach, a później AI
  kompan. Nic nie zakłada `player_0`. `HorseInputIntent` nie zależy od urządzenia
  (pole `direction` dla płaskiego sterowania i VR, `turn` dla sterowania względem konia).
- **Polecenia AI** (`command_follow`, `command_come`, `command_stop`) to wspólne API dla gracza
  (klawisz „zawołaj”), AI kompana i testów.

### Chody i masa

| Chód | Prędkość | Maks. tempo skrętu | Zmierzony promień skrętu | Duty factor | Fazy (FL, FR, RL, RR) |
|---|---|---|---|---|---|
| WALK | 1,7 m/s | 0,76 rad/s | 2,2 m | 0,65 | 0,25 / 0,75 / 0 / 0,5 (czterotakt) |
| TROT | 4,2 m/s | 0,76 rad/s | 5,5 m | 0,40 | 0 / 0,5 / 0,5 / 0 (przekątne) |
| GALLOP | 9,5 m/s | 0,44 rad/s | 21,7 m | 0,25 | 0,5 / 0,6 / 0 / 0,12 (czterotakt) |

- R(v) = 1,6 m + v² / 4,5 m/s². W miejscu koń obraca się powoli, krokami (0,6 rad/s).
  Przy prędkości nigdy nie obraca się jak wieżyczka.
- Przyspieszenie do 2,4 m/s², hamowanie do 4,0 m/s², wodze do 5,5 m/s². Jerk ograniczony do
  7 m/s³, a przyspieszenie kątowe do 1,8 rad/s².
- Ostre żądanie skrętu przy prędkości zwalnia konia: powyżej 0,6 rad do kłusa, powyżej 1,2 rad
  do stępa. Koń wchodzi w zakręt łukiem.
- Zmiany chodu mają histerezę, a wagi chodu (bob, kołysanie) przechodzą płynnie.
- **Sterowanie:**
  - drążek wskazuje „mniej więcej tam” (względem kamery albo, po F6, względem konia);
  - Spacja/A to kopnięcie, czyli chód wyżej;
  - PPM/R1 to wodze: koń zwalnia, a po puszczeniu trzyma chód odpowiadający prędkości;
  - po puszczeniu drążka koń **trzyma zadany kurs** i chód. Po ominięciu przeszkody wraca na
    kurs, a nie idzie tam, gdzie akurat patrzy jego nos.

### Częściowa autonomia (lokalnie, bez szukania ścieżki)

Około 8 zapytań fizyki na tick:

- **Omijanie:** sfery o szerokości konia rzucane w kierunku żądania oraz pod kątami ±0,25,
  ±0,5 i ±0,85 rad. Wygrywa pierwszy wolny kierunek, najbliższy temu, czego chce jeździec,
  więc w otwartym terenie wystarcza jeden cast. Stronę obejścia wybiera punkt trafienia
  (z dala od przeszkody), a koń trzyma się tej strony, aż droga będzie wolna. Bez dreptania
  w miejscu.
- **Hamowanie:** cast wzdłuż kierunku, w który koń faktycznie skręca, na długość drogi
  hamowania, plus krótki „zderzak” prosto przed ciałem. Koń hamuje opóźnieniem, które
  zatrzymuje go dokładnie przed przeszkodą (do 5,5 m/s²), zamiast gonić limit prędkości
  z opóźnieniem.
- **Ściana szersza niż wachlarz:** koń zwalnia i staje. Wybór innej drogi należy do
  jeźdźca, nie do konia.
- **Niska przeszkoda** (do 0,55 m, wykrywana promieniem na 0,18 m): koń przekracza ją
  najwyżej kłusem i nie omija.
- **Krawędź:** próbki gruntu co ok. 3 m wzdłuż kursu. Spadek głębszy niż 1,5 m to krawędź,
  a jej położenie doprecyzowuje bisekcja (3 promienie, tylko gdy krawędź istnieje).
  Koń staje 1,9 m przed nią.
- **Pochyłości po których da się iść** (normalna y ≥ 0,65) nigdy nie są przeszkodą.
  Rampa nie hamuje galopu.

### Stopy i tułów

- **Kopyta w STANCE są zamrożone w świecie.** Oderwanie następuje według fazy chodu, gdy noga
  jest za bardzo rozciągnięta albo przy korekcie w bezruchu. Jeden replan w połowie swingu.
- **Wysokość tułowia** to min(nominalna + bob, zasięg nóg):
  - liczona do kostki (podeszwa + normalna × wysokość kopyta), z rzeczywistym pochyleniem
    i przechyłem tułowia (pochylony tułów podnosi tylne biodra);
  - z chwilowym wyprzedzeniem dla nóg w podporze;
  - z płynnie rosnącym wpływem miejsca lądowania nóg w swingu, żeby tułów obniżał się przed
    zejściem ze stopnia, a nie po nim.
  
  Wynik jest wygładzany sprężyną krytycznie tłumioną. Na koniec działa twarda gwarancja:
  kopyto w podporze zawsze jest w zasięgu, więc IK nigdy go nie ciągnie. W slalomie w galopie
  zadziałała 1 raz na 780 ticków.
- **Pochylenie** wynika z różnicy przód/tył kopyt i z przyspieszenia, a w galopie dochodzi
  kołysanie. **Przechył** to połowa nachylenia terenu w poprzek plus przechył do środka zakrętu.
  Wszystko idzie przez sprężyny (C²). **Szyja** opada z prędkością i kiwa się w rytm chodu,
  a **głowa** patrzy w kierunku skrętu.
- Lewa strona konia to −X: koń patrzy w −Z. Naprawiony błąd z pierwszej wersji, w której
  przechył od terenu miał odwrotny znak.

### Wsiadanie, jazda, zsiadanie

`ON_FOOT → APPROACH HORSE (koń w zasięgu 2,8 m) → MOUNT (0,6 s) → RIDE → DISMOUNT (0,65 s) → ON_FOOT`

- Łuki wsiadania i zsiadania są liczone w układach konia w każdym ticku, więc podążają za
  poruszającym się koniem. Bez teleportów: maks. 0,10 m na tick.
- Przy jeździe pozycja gracza pochodzi z kości `body` (`saddle_transform()`). Dryf w siodle
  wynosi 0,000000 m przez 15 s galopu, zakrętów i hamowania.
- Miejsce zsiadania: lewo, prawo, tył, przód. Musi tam być grunt (różnica wysokości ≤ 1,2 m,
  normalna y ≥ 0,7) i wolna kapsuła. Gdy żadne miejsce nie jest bezpieczne, zsiadanie jest
  odmawiane z powodem („no safe place to get off”).
- Kolizje gracza są wyłączone tylko na czas jazdy. Kamera wyklucza konia, na którym siedzi
  gracz (inne konie są dla niej przeszkodą).

### Kamera a kierunek jazdy

Kamera należy do gracza. Przy jeździe jest dalej (5,5 m + 0,15·v), ale nigdy sama się nie
obraca. Bez drążka koń trzyma kurs, a kamera może patrzeć w bok albo do tyłu. Po F6 drążek
steruje względem konia (`steer_relative`): gracz może patrzeć gdzie indziej niż jedzie.
To przygotowanie pod RIDING + AIMING + SHOOTING, a samego łuku jeszcze nie ma.

## Wyniki testów (`tools/run_tests.sh`, 70/70 PASS)

| Test | Wynik |
|---|---|
| horse_acceleration_is_smooth | 0 → 9,5 m/s, chody IDLE→WALK→TROT→GALLOP po kolei, galop po 2,73 s; maks. 2,40 m/s², jerk 7,0 m/s³ |
| horse_braking_is_smooth | wodze z 9,5 m/s: stop po 3,48 s / 12,2 m, chody w dół po kolei, maks. 5,5 m/s² |
| horse_cannot_instant_turn_at_speed | żądanie 90° w galopie: 3,4° po 0,25 s, skręt gotowy po 2,7 s, zwolnił do 4,6 m/s |
| horse_turn_radius_increases_with_speed | 2,2 / 5,5 / 21,7 m przy 1,7 / 4,2 / 9,5 m/s |
| horse_feet_do_not_slide | stęp, kłus, galop, zakręty, stop: poślizg maks. 0,0020 m/s, błąd IK 0,000 m, 154 kroki |
| horse_feet_follow_uneven_terrain | rampa 10°, nierówności, stopień 0,8 m: kopyto–grunt maks. 0,037 m, poślizg 0,0007 m/s |
| horse_body_lean_is_continuous | slalom w galopie + wodze: brak skoków pozy (d² przechyłu 9,8, wysokości 14,6), przechył do środka zakrętu |
| mounted_player_has_no_saddle_drift | 15 s jazdy: jeździec–siodło 0,000000 m |
| mount_and_dismount_are_stable | APPROACH HORSE → MOUNT → RIDE → DISMOUNT → na ziemi; maks. 0,10 m/tick; drugie wsiadanie działa |
| dismount_refused_without_space | otoczony skałami: zostaje w siodle, powód podany |
| horse_avoids_small_obstacle | pole skał w kłusie: 0 kontaktów, przeszedł całe pole |
| horse_keeps_heading_after_avoiding | sterowanie względem konia: po obejściu skał wraca na kurs 0,0° |
| horse_threads_narrow_passage | przejście 3 m w kłusie: 0 kontaktów ze ścianami |
| horse_steps_over_low_obstacle | kłoda 0,3 m: rozpoznana jako „step”, przejście prosto, poślizg 0 |
| horse_stops_before_large_obstacle | galop na ścianę 5 m, jeździec dalej pcha: ≤3,4 m/s w ostatnich 3 m, staje, 0 kontaktów |
| horse_stops_at_cliff_edge | galop na krawędź 4 m: staje 1,86 m przed nią, nie spada |
| horse_simulation_independent_of_render_fps | wsiadanie, jazda, zakręt, wodze, zsiadanie przy 30/60/90/120/144/240 FPS: różnica stanu 0,00000000 |
| horse_camera_can_look_away_from_travel_direction | kamera 90° w bok: kurs konia bez zmian (0,0°) bez drążka i ze sterowaniem względem konia |
| horse_comes_when_called | zawołany z 56 m przez pole skał: staje 2,0 m od gracza, 0 kontaktów |
| horse_follows_player | podąża za biegnącym graczem (5,5 m/s): 4,3–15,1 m, po zatrzymaniu staje 4 m od niego |
| horse_cost_stays_within_budget | patrz niżej |
| existing_colossus_tests_still_pass | 48 wcześniejszych testów w tym samym przebiegu: 0 błędów |

Metryki konia (`horse_*`) są zamrożone w osobnym wzorcu `tests/baseline/etap4_horse_baseline.json`
(`--save-horse-baseline`). Wzorzec Etapu 2/3 jest nietknięty. Flagowane są tylko te same koszty
CPU kolosa co w Etapie 3 (szum pomiaru na tej maszynie, opis w ETAP_3.md). Koszt locomotion
kolosa jest bez zmian (~125 µs/tick).

## Koszt CPU (headless, jazda po torze z rampą)

| Część | µs / tick |
|---|---|
| Agro razem | ~180–230 |
| – HorseController (w tym sondy przeszkód ~70–80) | ~75–95 |
| – planer kroków (QuadrupedGait) | ~23–29 |
| – IK + poza tułowia | ~55–75 |
| wsiadanie / jazda (PlayerRiding) | ~6–8 |
| kamera (na klatkę) | ~45–57 |
| zapytania fizyki konia | ~8,4 / tick |

Sondy przeszkód są największą częścią kosztu kontrolera, ale całość mieści się z dużym
zapasem w budżecie testu (400 µs). Bez profilu wskazującego problem niczego nie optymalizowano
i nic nie przeniesiono do Ziga. Pod llvmpipe (zrzuty ekranu) liczby są 2–3× wyższe, bo
renderowanie programowe zajmuje ten sam procesor.

## Scena testowa i zrzuty

`scenes/agro_test.tscn` (`src/world/agro_arena.gd`) zawiera:

- równinę;
- tor z rampą 10°, nierównościami i stopniem 0,8 m;
- pole skał;
- wąskie przejście 3 m z lejkiem;
- kłodę 0,3 m;
- ścianę 5 × 50 m;
- płaskowyż 4 m z rampą i urwiskiem.

Gracz startuje obok Agro.

`tools/capture_screenshots.sh agro` uruchamia prawdziwą scenę (renderer, kamera, HUD, nakładka
F3) ze skryptowanym jeźdźcem. Zapisuje `tests/output/agro_*.png`:

1. podejście do konia;
2. wsiadanie;
3. kłus wśród skał (2 ujęcia);
4. galop;
5. przechył w zakręcie;
6. kamera patrząca w bok;
7. galop na ścianę i postój przy ścianie;
8. postój nad urwiskiem;
9. rampa;
10. nierówności i stopień;
11. zsiadanie;
12. zawołany koń w drodze;
13. koń przy graczu.

## Manualne scenariusze (do ludzkiego playtestu)

1. Podejdź do Agro (HUD: APPROACH HORSE), wsiądź E/Y i zsiądź na płaskim terenie, przy ścianie
   i między skałami. Czy łuki wyglądają naturalnie? Czy odmowa zsiadania jest zrozumiała?
2. Ruszanie i hamowanie: pchnięcie drążka (stęp), Spacja ×2 (kłus, galop), PPM (wodze). Czy czuć
   masę? Czy galop nie przychodzi za wolno albo za szybko (teraz 2,7 s)?
3. Zakręty: w stępie ciasno, w galopie szeroko. Czy ostre szarpnięcie drążkiem w galopie, które
   wymusza zwolnienie do kłusa, jest czytelne, czy frustrujące?
4. Kamera: w galopie obróć kamerę w bok i do tyłu bez drążka, potem F6 (sterowanie względem
   konia) i jedź, patrząc w bok. Czy kamera nigdy nie „wyrywa” sterowania?
5. Skały, przejście 3 m, kłoda: czy autonomia konia pomaga, czy przeszkadza (koń „wie lepiej”)?
6. Ściana i urwisko w galopie z wciśniętym drążkiem: czy zatrzymanie jest wiarygodne? Przy
   ścianie koń może lekko odbić w bok, zanim stanie.
7. Teren: rampa, nierówności, stopień, z nakładką F3 (kopyta, cele, normalne, sondy). Czy nogi
   wyglądają wiarygodnie? W kłusie bywa faza lotu, a przy schodzeniu ze stopnia noga w swingu
   bywa chwilę za krótka (nie dotyka ziemi, więc nie ma poślizgu).
8. Zawołaj Agro (C / D-pad dół) z daleka i z drugiej strony skał. Czy podejście i zatrzymanie
   się ~2–3 m od gracza jest naturalne?
9. Różne FPS (np. limit 30 i 144 w ustawieniach sterownika): czy jazda wygląda tak samo?

## Znane ograniczenia (świadomie na później)

- Koń nie koliduje z graczem pieszym (maska: świat i kolos). AI zatrzymuje się 3–5 m od gracza,
  ale gracz wchodzący pod konia przejdzie przez niego.
- Omijanie jest lokalne (bez szukania ścieżki). Ślepy zaułek albo labirynt to zadanie jeźdźca.
- Model, animacje, łuk, miecz, koop i VR to późniejsze etapy. Rig konia jest greyboxem
  z prostopadłościanów.
- Wartości chodów, promieni i rytmu to pierwsze strojenie z testów, nie z playtestu.

## Pliki

```
src/horse/horse.gd                 Horse: rig, symulacja, poza, IK, siodło, polecenia AI
src/horse/horse_controller.gd      HorseController: chód, masa, skręt, omijanie, hamowanie
src/horse/quadruped_gait.gd        QuadrupedGait: zegar chodu, fazy nóg, kroki
src/horse/horse_input_intent.gd    HorseInputIntent: niezależny od urządzenia zamiar jazdy
src/horse/scripted_horse_driver.gd ScriptedHorseDriver: jeździec-dane dla testów i narzędzi
src/horse/horse_debug_draw.gd      nakładka F3
src/locomotion/step_math.gd        wspólna matematyka kroku (kolos + koń)
src/player/player_riding.gd        PlayerRiding: wsiadanie, jazda, zsiadanie, intent z akcji gracza
src/world/agro_arena.gd            scena testowa Agro
scenes/agro_test.tscn              scena testowa
tests/capture_agro.gd              zrzuty ekranu Agro
tests/fps_scenario.gd              --scenario=horse: test niezależności od FPS
```
