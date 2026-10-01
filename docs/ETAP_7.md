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

## Wyniki

__RESULTS__

## Ograniczenia

- Ciało gracza przeskakuje o ~0,5 m (próg wykrywacza glitchy) przy przejściu chwytu
  między stykającymi się bryłami u Gaiusa (pięść/przedramię, tył głowy/hełm). Kotwica się
  nie przesuwa (0 m/tick), przesuwa się ustawienie ciała. Zdarza się rzadko (liczby
  w soaku).
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

__ETAP8__
