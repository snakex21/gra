# Etap 7 — Gaius, assety w grze, pętla Quadratusa, szlif łuku

Zakres (z propozycji na końcu Etapu 6, zaakceptowany):

1. **Assety** z gałęzi `assets` w arenach i na Valusie (warstwa tylko wizualna).
2. **Gaius**, trzeci kolos: miecz jako kość w dłoni, wbity miecz jako droga na rękę,
   hełm jako pancerz do rozbicia.
3. **Quadratus**: pętla „repeat” (drugi weak point dopiero przy kolejnym klęknięciu)
   i gwałtowny krok, czyli zryw z graczem na grzbiecie.
4. **Łuk**: widok zza ramienia przy naciągu, strzały odbijają się od kamienia.
5. Soaki trzech bossów po 100 walk.

Przy okazji: wspólna baza `HumanoidBoss` (Valus i Gaius) i dwa realne błędy
w fairness, opisane niżej.

## 1. Assety (gałąź `assets`)

Gałąź `assets` (commit `a838b5b`) zawiera paczkę „Saltward” (CC0, pipeline MIT). Są w niej:
- modele `.glb` z 3 LOD-ami: części Valusa (dawny Sentinel) dla każdego segmentu, skały,
  ruiny, klify, drzewa, trawy;
- tekstury, materiały, shader terenu, prefaby i skrypty pipeline'u.

**Uwaga:** ta gałąź zawiera też starsze kopie 22 wspólnych plików gry (`project.godot`,
`test_runner.gd` −2460 linii, `greybox_humanoid.gd` −630, brak warstwy fizyki konia…).
Wzięliśmy **wyłącznie ścieżki z assetami** (`models/`, `textures/`, `materials/`,
`environment/`, `art/`, `assets/`, `tools/art/`, `docs/ART_PIPELINE.md`), bez nadpisywania
kodu gry.

`ArenaArt` (`src/world/arena_art.gd`) to warstwa **tylko wizualna**:
- **teren**: shader terenu na podłożu, tarasach i rampach;
- **zamiana greyboxu**: kolumny greyboxu stają się kolumnami ruin, małe bloki skałami
  (kolizja greyboxu zostaje), ich siatki są ukryte;
- **otoczenie poza walką**: głazy, drzewa, krzewy, trawa w chunkowanych MultiMeshach
  (2 LOD-y), klify na dalekim pierścieniu z przerwą przy wejściu;
- **światło**: preset dzienny z paczki;
- **Valus**: sztywna część z paczki na każdym segmencie (3 LOD-y). Jego własne dodatkowe
  części (grzywa, czapa futra, pancerz) zostają widoczne jako czytelne miejsca do
  chwytania, z teksturami z paczki;
- **Quadratus i Gaius**: modeli w paczce nie ma, więc dostają teksturowane materiały
  (kamień / futro / pancerz) według rodzaju części, przez metadane `kind` na siatkach
  greyboxu.

Sceny włączają ją domyślnie (`NO_ART=1` pokazuje czysty greybox). Testy budują areny bez
niej, a `test_art_layer_does_not_change_gameplay` dowodzi, że niczego nie zmienia:
8 s chodu Valusa z assetami i bez, w osobnych procesach, daje różnicę stanu 0, a kolizje
i powierzchnie wspinaczki są identyczne.

## 2. Gaius (`src/colossus/gaius/`)

```
HumanoidBoss (wspólne: encounter, stomp, trafienia, weak point, pokonanie, debug)
  ├─ Valus  (sweep ramieniem, ochrona weak pointa)
  └─ Gaius  (miecz, wbicie, hełm)
```

- **Miecz** to kość `sword` w prawej dłoni (hak `GreyboxHumanoid._bones()`) z własnym
  segmentem: kamienne ostrze 10 m o płaskich ścianach i jelec. Prawa ręka jest ustawiana
  dwukościowym IK z celów w układzie ciała (spoczynek / zamach nad barkiem / wbicie),
  więc czubek ostrza ląduje dokładnie w punkcie ciosu (błąd 0,000 m), płaską stroną
  do góry (0,91), pod kątem ~24°.
- **SWORD_SLAM**:
  - telegraf 1,5 s; przez pierwszą połowę punkt ciosu śledzi cel z prędkością
    ≤ 2,5 m/s, potem jest zablokowany;
  - zamach 0,4 s, kapsuła trafienia na ostrzu, fala przy czubku;
  - **ostrze zostaje wbite 8 s jako rampa**: Gaius przykuca i nic innego nie robi
    (bez shake'a), potem przez 1,6 s wyciąga miecz;
  - cooldown 9 s, strefy zagrożenia dla Agro (punkt ciosu i pas ostrza).
- **Droga**: wbiec na ostrze od czubka (podskok, bo czubek sterczy 0,5 m) → owinięta
  pięść (futro) → przedramię → ramię → futrzany naramiennik → barki (`rest`) → grzywa →
  tył głowy → hełm.
- **Hełm** to `ArmorPlate` (nowa, wspólna klasa): kawałek pancerza na segmencie, który
  kruszą naładowane ciosy miecza:
  - 3 ciosy go rozbijają; słabe ciosy, strzały i ciosy poza zasięgiem się odbijają;
  - po rozbiciu wyłącza się kolizja, znika siatka, a weak point pod spodem się otwiera
    (wcześniej był zamknięty);
  - `PlayerSword` traktuje weak pointy i pancerze tym samym API; wygrywa najbliższy cel,
    który przyjmie cios.
- **Pokonanie**: wspólne z Valusem (klęknięcie i skłon), czubek głowy ~3,3 m nad ziemią.
- `GaiusBrain`: `sword_slam`, `stomp`, `search_player`, `approach`, `observe_player`,
  na ciele `shake_player` (na ręce dopiero po 7 s, żeby dało się wejść).
- `GaiusBot` dziedziczy po `ValusBot` (uogólnionym na `HumanoidBoss`) i podmienia początek
  trasy (sprowokować cios, zejść z linii, wbiec na ostrze, chwycić pięść, ręka, naramiennik)
  oraz głowę (najpierw hełm).

## 3. Quadratus: pętla i gwałtowny krok

- **Czoło zamknięte kamienną klapą**, dopóki zad nie jest zniszczony **i** kolos nie klęczy.
  Zniszczenie zadu sprawia, że od razu wstaje. Trzeba zejść (bot schodzi po zadzie i udzie),
  znowu trafić kopyto i wejść drugi raz; drugie i kolejne klęknięcia trwają 20 s, bo głowa
  jest daleko.
- Geometria pod tę drogę:
  - wierzchy przedniej i tylnej bryły tułowia oraz zadów są wyrównane (był stopień 0,3 m);
  - kamienne siodło nie jest już stopniem 0,5 m;
  - futro z tyłu głowy sięga do czoła.
- **LURCH**: przeciw graczowi **stojącemu** na grzbiecie. Telegraf 0,8 s (napięcie),
  potem zryw do 3,9 m/s i twarde zatrzymanie; przód tułowia nurkuje i podbija.
  `LocomotionController.speed_gain` pozwala na chwilę zdjąć limity masy. Zryw liczy się
  jako shake we wspólnych regułach (maksymalna długość, cooldown), jeden na decyzję,
  nigdy w klęknięciu. Stojący gracz spada do UNSTABLE (balans ~0,5), ale nie zostaje
  zrzucony; chwyt ratuje.

## 4. Łuk

- **Widok przy naciągu**: kamera wchodzi zza prawego ramienia (3 m zamiast 5, fov 52
  zamiast 70) i wraca po strzale. Celownik pozostaje środkiem widoku, a promień celowania
  dalej idzie z kamery (`aim_origin`).
- **Odbicia**: strzała trafiająca w kamień lub pancerz kolosa odbija się (najwyżej 2 razy,
  z 30% prędkości, plus ruch powierzchni). W futro i w ziemię się wbija.

## 5. Naprawione błędy (znalezione w tym etapie)

- **Cooldown ataku się nie liczył.** Atak, który doszedł do DONE, nie był zgłaszany do
  `FairnessRules` (warunek `is_done()` w `_end_attack`), więc jego cooldown nie startował.
  Dotyczyło Quadratusa z Etapu 6 i Valusa po refaktorze. Nowy test
  `test_attacks_respect_cooldowns_all_bosses` pilnuje tego dla wszystkich bossów.
- **Brak przysiadu przed shake'iem** (Valus, Quadratus): kod czytał intencję ruchu, która
  w czasie telegrafu jest IDLE, więc przysiad nigdy się nie pokazywał. Teraz czyta
  prawdziwą intencję.

Znalezione przez soaki (zakleszczenia, poprawione przed końcowym soakiem):
- **Shake'i bez przerwy po trafieniu.** Trafienie w weak point przerywało shake, więc
  cooldown był krótki (1,5 s). Po 1,3 s wzdrygnięcia kolos znowu potrząsał, a gracz nie
  miał kiedy wstać i odzyskać staminy. Gaius po otwarciu głowy zrzucał tak bota do
  skutku. Nowa reguła fairness `Colossus.shake_after_flinch`: wzdrygnięcie liczy się jak
  shake, a następny shake może przyjść dopiero 2 s po nim. Dotyczy wszystkich kolosów.
- **Wsiadanie na Agro na leżąco.** Powalony gracz mógł wsiąść, a w siodle równowaga się
  nie odnawiała, więc łuk był zablokowany do końca walki. Teraz powalony nie wsiada,
  a w siodle się podnosi.
- **Bot Quadratusa** po przekroczeniu czasu jazdy chciał zsiąść, ale `_dismount` od razu
  odsyłał go z powrotem do jazdy. Poprawione.

## Wyniki

### Testy

Pełny przebieg `tools/run_tests.sh` (razem z testami Etapu 8): **153/153 PASS** (120 do Etapu 6, 19 Etapu 7, 14 Etapu 8). Nowe testy Etapu 7:

| Test | Wynik |
|---|---|
| `gaius_sword_follows_the_arm` | rękojeść vs dłoń 0,000001 m; wbity: czubek vs punkt ciosu 0,000 m, płaska strona do góry 0,91, nachylenie 24,1° |
| `gaius_slam_has_telegraph_and_stuck_window` | TELEGRAPH 1,5 s → ACTIVE 0,4 s → RECOVERY 9,6 s (wbity 8,0 s, nic innego), strefa zagrożenia 26 ticków w zamachu |
| `gaius_slam_point_locks_for_a_late_dodge` | punkt ciosu po 55% zamachu: 0,000 m ruchu; późny unik: HP 100 → 100 |
| `gaius_blade_is_a_walkable_ramp` | 300 ticków na ostrzu, +2,4 m, do pięści 1,59 m, stan STAND |
| `gaius_climb_route_blade_to_shoulders` | bot: pięść po 16,7 s, barki po 24,1 s (1 cios miecza) |
| `gaius_grip_on_sword_arm_has_no_drift` | chwyt ręki przez wyciąganie miecza (12 s, 7,3 m): kotwica vs powierzchnia 0,000002 m |
| `gaius_helmet_breaks_after_charged_strikes` | słaby cios odbity, 3 naładowane → hełm rozbity, kolizja wyłączona, weak point OPEN |
| `armor_plate_rejects_invalid_hits` | strzała / poza zasięgiem / słaby: odrzucone, naładowany: pęknięcie |
| `gaius_can_be_defeated` | DEFEATED, czubek głowy po klęknięciu 3,3 m |
| `gaius_scripted_driver_can_complete_fight` | wygrana (ostrze 2×, hełm, 3 ciosy) |
| `gaius_simulation_independent_of_render_fps` | cała walka przy 30–240 FPS: różnica stanu 0,00000000 |
| `gaius_cost_stays_within_budget` | kolos 305 µs/tick (lokomocja 143, IK 28, poza ręki z mieczem 22) |
| `attacks_respect_cooldowns_all_bosses` | najkrótsza przerwa między tymi samymi atakami: stomp 9,4 s, sword_slam 20,6 s |
| `art_layer_does_not_change_gameplay` | 8 s chodu, assety wył./wł. w osobnych procesach: różnica 0,00000000, kolizje identyczne |
| `quadratus_lurch_unsettles_standing_player_fairly` | 7 zrywów w 40 s: telegraf 0,87 s, szczyt 3,9 m/s, balans min 0,47–0,57, nikt nie spadł |
| `quadratus_crown_needs_second_kneel` | czoło zamknięte przy 1. klęknięciu i po zniszczeniu zadu, otwarte przy 2., zamyka się po 19,4 s |
| `bow_aim_zooms_camera_over_shoulder` | 5,0 m / fov 70 → 3,0 m / fov 52, 0,75 m w prawo → po strzale wraca |
| `arrow_glances_off_stone` | kamienna łydka: odbicie; futro: wbita |

### Soak (100 walk każdego bossa, po poprawkach z sekcji 5)

| | Valus | Quadratus (52 pieszo / 48 z Agro) | Gaius |
|---|---|---|---|
| wygrane | **100/100** | **100/100** | **100/100** |
| czas min / mediana / max | 44,1 / 47,2 / 63,8 s | 59,9 / 87,6 / 234,2 s | 46,6 / 54,7 / 198,0 s |
| śmierci | 0 | 2 (upadki) | 3 (upadki z głowy) |
| złe resety | 0 | 0 | 0 |
| zatrzymania bota | 0 | 3 (2× RIDE, 1× DESCEND) | 4 (APPROACH_LEG) |
| strzały | — | 638, w podeszwę 219, z konia 226 | — |
| reakcje kopyt | — | 219, wszystkie pełne REACT→KNEEL→RISE | — |

Uwagi do soaku:
- Pierwszy soak (przed poprawkami) miał **3 zakleszczenia na 300 walk**. Dwa u Gaiusa:
  ciągłe shake'i po otwarciu głowy, bot ginął ze zmęczenia. Jedno u Quadratusa: gracz
  wsiadł na Agro leżąc i łuk był zablokowany. Oba błędy były w grze, nie w bocie.
- `ai_stuck` u Quadratusa (31) to obracanie się w miejscu za jeźdźcem, który krąży za
  zadem dłużej niż 25 s. Nie blokuje walki.

### Wydajność

- Gaius ~305 µs/tick logiki, z czego IK ręki z mieczem ~22 µs.
- Warstwa assetów jest tylko wizualna (0 kolizji, różnica stanu 0).

## Ograniczenia

- Ciało gracza przeskakuje o ~0,5 m przy owijaniu chwytu przez krawędź u Gaiusa (górna
  krawędź głowy pod hełmem). Kotwica się nie przesuwa, przeskakuje ustawienie ciała.
  W Etapie 8 rysowane ciało jest już wygładzane (patrz ETAP_8.md).
- Quadratus i Gaius nie mają jeszcze modeli z paczki (tylko tekstury na greyboxie).
- Kamienne kopyto Quadratusa odbija strzałę, ale nie ma żadnego efektu dźwiękowego
  ani wizualnego odbicia.
- Zryw Quadratusa to zryw do przodu; krok w bok wymagałby bocznego ruchu ciała
  w locomotion.

## Lista do playtestu

- Czy wbity miecz Gaiusa jest czytelny jako droga (8 s okna, skok na czubek)?
- Hełm: 3 naładowane ciosy na stojąco; czy widać pęknięcia?
- Drugie wejście na Quadratusa: czy „zamknięte czoło” jest zrozumiałe bez tekstu?
- Zryw Quadratusa: czy daje szansę zareagować (telegraf 0,8 s)?
- Widok zza ramienia przy łuku na koniu.
- Wygląd aren z paczką Saltward: skala klifów, gęstość trawy, światło.

## Propozycja Etapu 8

Zrealizowana jako [Etap 8](ETAP_8.md): dolina ze świątynią i bramami, promień miecza,
pętla gry z zapisem, bot całej gry, Sentinel v2.
