# Gra — remake w duchu Shadow of the Colossus

Open-source'owa reimplementacja/remake gry w duchu *Shadow of the Colossus*, która rozwija
elementy ograniczone w oryginale sprzętem PS2, czasem produkcji albo wycięte z gry.
Silnik: **Godot 4.4+** (GDScript, a Zig dopiero tam, gdzie profiler pokaże realną potrzebę).
Gra ma działać w pełni offline. Repozytorium nie zawiera żadnych chronionych assetów oryginału.

## Stan: Etap 2 — kontakt gracza z poruszającym się kolosem

- Milestone 1 (wspinanie po poruszającym się kolosie): [docs/MILESTONE_1.md](docs/MILESTONE_1.md)
- Etap 2 (równowaga na kolosie, upadki, kamera, przejścia): [docs/ETAP_2.md](docs/ETAP_2.md)
- Architektura: [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md)

Co działa w sandboxie (`scenes/sandbox.tscn`):

- greyboxowy humanoid ~17 m ze szkieletem (`Skeleton3D`) i colliderami przypiętymi do kości,
  ciągłym ruchem (chód, skręt, oddech, śledzenie gracza głową) i próbami zrzucania (wstrząs);
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
  abstrakcyjne `PlayerActions` (flat/VR/AI/testy).

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
| Debug / pomoc | F3 / F1 | — |

## Testy

```bash
tools/run_tests.sh                 # 31 testów rozgrywki, headless, ~4 s
tools/run_tests.sh --only=climb    # wybrane testy
tools/capture_screenshots.sh       # prawdziwa scena + autopilot -> tests/output/*.png
```

Testy sterują graczem wyłącznie przez `PlayerActions`, tak jak robi to człowiek albo AI kompan.
Sprawdzają zachowanie, a nie szczegóły implementacji: czy chwyt na idącej nodze nie dryfuje,
czy da się wejść z łydki na barki idącego kolosa, czy wstrząs destabilizuje stojącego gracza
i czy można się uratować chwytem, czy upadki mają konsekwencje, czy kamera nigdy nie wchodzi
w ciało kolosa. Test wydajności mierzy koszt logiki na tick i liczbę zapytań fizyki
(benchmark regresji).

## Struktura

```
src/core/       warstwy fizyki, liczniki wydajności (Perf)
src/input/      PlayerActions (abstrakcyjne akcje), FlatInputSource, domyślne bindy
src/player/     PlayerCharacter (lokomocja + wspinanie + stanie na kolosie), Stamina, Balance, FallImpact, PlayerVisual
src/climb/      ClimbPatch (chwytalny kształt), SurfaceAnchor (punkt na ruchomym ciele), ClimbQuery
src/colossus/   Colossus (baza), BodySegment (collider na kości), brain/ (Brain, Intent, Observation, UtilityBrain)
src/colossus/greybox/  GreyboxHumanoid — rig i kontroler sterowane danymi
src/camera/     PlayerCamera
src/ui/         PlayerHud
scenes/         sandbox
tests/          testy headless + wizualny smoke test
docs/           dokumentacja projektu
```

## Licencja

Kod i własne assety: do ustalenia przez właściciela repozytorium (sugerowana MIT dla kodu).
