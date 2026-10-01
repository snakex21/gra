# Gra — remake w duchu Shadow of the Colossus

Open-source'owa reimplementacja/remake gry w duchu *Shadow of the Colossus*, która rozwija
elementy ograniczone w oryginale sprzętem PS2, czasem produkcji albo wycięte z gry.
Silnik: **Godot 4.4+** (GDScript, a Zig dopiero tam, gdzie profiler pokaże realną potrzebę).
Gra ma działać w pełni offline. Repozytorium nie zawiera żadnych chronionych assetów oryginału.

## Stan: Etap 5 — pierwszy kompletny boss (Valus)

- Milestone 1 (wspinanie po poruszającym się kolosie): [docs/MILESTONE_1.md](docs/MILESTONE_1.md)
- Etap 2 (równowaga na kolosie, upadki, kamera, przejścia): [docs/ETAP_2.md](docs/ETAP_2.md)
- Etap 3 (locomotion, planer kroków, IK, miednica, A/B z animacją, niezależność od FPS): [docs/ETAP_3.md](docs/ETAP_3.md)
- Etap 4 (Agro: chody, promień skrętu, kopyta bez poślizgu, wsiadanie, omijanie, AI, kamera): [docs/ETAP_4.md](docs/ETAP_4.md)
- Etap 5 (Valus: encounter, ataki z telegrafem, weak point, miecz, fairness, reset, bot, 50 walk): [docs/ETAP_5.md](docs/ETAP_5.md)
- Architektura: [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md)

Pełna walka z bossem: `scenes/valus_arena.tscn` (Valus, arena, Agro; F5 resetuje walkę).

Co działa w sandboxie (`scenes/sandbox.tscn`):

- greyboxowy humanoid ~17 m ze szkieletem (`Skeleton3D`) i colliderami przypiętymi do kości,
  z locomotion opartym na krokach: stopy stoją w miejscu (bez ślizgania), dwukościowe IK nóg,
  teren testowy (rampa, nierówności, stopień), przenoszenie ciężaru, masa przy starcie, hamowaniu
  i skręcie oraz próby zrzucania gracza (wstrząs);
- futro (brązowe) można chwytać, kamień i pancerz (szare) blokują wspinanie, a po płaskim kamieniu
  (barki) można chodzić i regenerować staminę;
- chwyt, stamina, wspinanie z przechodzeniem między segmentami ciała, obchodzenie kończyn dookoła,
  podchodzenie pod nawisy, wciąganie się na krawędź, poślizg przy niskiej staminie, skok ze ściany,
  łapanie się w locie, utrata chwytu (puszczenie lub wyczerpanie) z dziedziczeniem prędkości ciała;
- stanie i chodzenie po idącym kolosie (kotwica lokalna względem kości), ciągła równowaga
  STABLE → UNSTABLE → STUMBLE → FALLEN, poślizg z tarciem Coulomba, ratunek chwytem;
- upadki z progami (bezpieczny / twarde lądowanie / ciężki / śmiertelny) i proste zdrowie;
- kamera trzeciej osoby, która nie walczy z graczem: dystans zależny od sytuacji, wyprzedzanie
  trasy przy wspinaniu, nigdy nie wchodzi w ciało kolosa, kadrowanie gracza i kolosa;
- architektura `ColossusBrain → Intent → controller`, reguły fairness niezależne od AI, `players[]`,
  abstrakcyjne `PlayerActions` (flat/VR/AI/testy);
- Agro (też w `scenes/agro_test.tscn` z rampą, skałami, wąskim przejściem, kłodą, ścianą i urwiskiem):
  stęp / kłus / galop z bezwładnością, promień skrętu rosnący z prędkością, cztery kopyta stojące
  w miejscu na każdym terenie, kołysanie i przechył tułowia, wsiadanie i zsiadanie bez teleportów,
  omijanie skał, przekraczanie kłody, zatrzymanie przed ścianą i urwiskiem, przywołanie
  i podążanie za graczem, kamera niezależna od kierunku jazdy.

## Uruchomienie

```bash
godot --path . # albo otwórz project.godot w edytorze Godot 4.4+
```

| Akcja | Klawiatura / mysz | Pad |
|---|---|---|
| Ruch | WASD | lewy drążek |
| Kamera | mysz | prawy drążek |
| Chwyt (trzymaj) | PPM / Shift | R1 / R2 |
| Skok (na ścianie: odbicie / skok wzdłuż powierzchni) | Spacja | A |
| Kadruj kolosa | Q / środkowy przycisk | L1 |
| Respawn | Backspace | Back |
| Tryb kolosa: AI / zamrożony / chód / obrót / wstrząs | F2 | — |
| Nogi A/B: proceduralne + IK / animacja + IK / stary FK | F4 | — |
| Debug + nakładka kroków / pomoc | F3 / F1 | — |
| Wsiądź / zsiądź z Agro | E | Y |
| Jazda: kopnięcie (szybszy chód) / wodze (trzymaj) | Spacja / PPM | A / R1 |
| Zawołaj Agro | C | D-pad dół |
| Sterowanie jazdą: względem kamery / względem konia | F6 | D-pad góra |
| Miecz: trzymaj = ładowanie, puść = cios | LPM / F | X |
| Reset walki z bossem | F5 | — |

## Testy

```bash
tools/run_tests.sh                 # 93 testy + A/B + porównanie z zamrożonymi wzorcami, headless, ~3,5 min
tools/run_tests.sh --save-baseline # zamraża nowy wzorzec regresji Etapu 2/3 (tylko świadomie)
tools/run_tests.sh --save-horse-baseline  # zamraża wzorzec metryk Agro (tylko świadomie)
tools/run_tests.sh --only=horse    # wybrane testy
tools/capture_screenshots.sh       # prawdziwa scena + autopilot -> tests/output/*.png
tools/capture_screenshots.sh agro  # scena Agro + skryptowany jeździec -> tests/output/agro_*.png
tools/capture_screenshots.sh boss  # walka z Valusem grana przez bota -> tests/output/boss_*.png
tools/run_boss_soak.sh 50          # długi test: 50 pełnych walk bota (różne seedy), ~12 min
```

Testy sterują graczem wyłącznie przez `PlayerActions`, tak jak robi to człowiek albo AI kompan.
Sprawdzają zachowanie, a nie szczegóły implementacji: czy chwyt na idącej nodze nie dryfuje,
czy da się wejść z łydki na barki idącego kolosa, czy wstrząs destabilizuje stojącego gracza
i czy można się uratować chwytem, czy upadki mają konsekwencje, czy kamera nigdy nie wchodzi
w ciało kolosa, czy kopyta Agro nie ślizgają się, czy koń nie skręca w miejscu w galopie
i czy staje przed urwiskiem. Testy wydajności mierzą koszt logiki na tick i liczbę zapytań
fizyki (benchmark regresji).

## Struktura

```
src/core/       warstwy fizyki, liczniki wydajności (Perf)
src/input/      PlayerActions (abstrakcyjne akcje), FlatInputSource, domyślne bindy
src/player/     PlayerCharacter (lokomocja + wspinanie + stanie na kolosie), PlayerRiding, Stamina, Balance, FallImpact, PlayerVisual
src/climb/      ClimbPatch (chwytalny kształt), SurfaceAnchor (punkt na ruchomym ciele), ClimbQuery
src/colossus/   Colossus (baza), BodySegment (collider na kości), brain/ (Brain, Intent, Observation, UtilityBrain)
src/colossus/greybox/  GreyboxHumanoid — rig sterowany danymi, mapowanie locomotion na kości (IK)
src/locomotion/ LocomotionController (masa, planer kroków, miednica), LegState, TwoBoneIK, StepMath, debug draw
src/horse/      Horse, HorseController, QuadrupedGait, HorseInputIntent, ScriptedHorseDriver, debug draw
src/colossus/valus/  Valus (pierwszy boss), ValusBrain
src/combat/     ColossusAttack, HitVolume, WeakPoint, FairnessRules, PlayerSword, BossEncounter, ValusBot, debug draw
src/fx/         Sfx (syntezowane dźwięki zastępcze), Fx (lekki kurz / błysk)
src/world/      TerrainKit, AgroArena, ValusArena — teren testowy
src/camera/     PlayerCamera
src/ui/         PlayerHud
scenes/         sandbox, agro_test, valus_arena
tests/          testy headless + wizualny smoke test
docs/           dokumentacja projektu
```

## Licencja

Kod i własne assety: do ustalenia przez właściciela repozytorium (sugerowana MIT dla kodu).
