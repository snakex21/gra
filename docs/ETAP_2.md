# Etap 2 — kontakt gracza z poruszającym się kolosem

Cel: gracz zachowuje się naturalnie zarówno trzymając się kolosa, jak i stojąc lub chodząc
po jego powierzchni.

## Co zostało zrobione

### 1. Stanie na kolosie: kotwica lokalna i równowaga
- **Niesienie przez ciało** działa jak chwyt: stojący gracz ma kotwicę w przestrzeni lokalnej
  segmentu (`_apply_carry`). Wbudowane w Godota przenoszenie przez platformę jest wyłączone,
  bo dryfowało przy obracających się segmentach. Wynik: dryf 1 mm na nieruchomym kolosie,
  0 mm na obracającym się.
- **`Balance`** (`src/player/balance.gd`) to czysta klasa danych z przebiegiem
  STABLE → UNSTABLE → STUMBLE → FALLEN. Wartość 0..1 zmienia się w sposób ciągły w zależności
  od „zakłócenia” (m/s²) liczonego z:
  przyspieszenia stycznego powierzchni, przyspieszenia wzdłuż normalnej (z mniejszą wagą),
  prędkości kątowej segmentu, nachylenia ponad 15° oraz mnożnika za prędkość gracza względem
  powierzchni. Zakłócenie powyżej pojemności (6 m/s²) drenuje równowagę, poniżej niej
  równowaga się odnawia.
  Stan określa kontrolę ruchu (1 → 0,55 → 0,2 → 0) i współczynnik tarcia stóp lub ciała.
- **Poślizg względem powierzchni** wynika z tarcia Coulomba: ciało przesuwa się dopiero, gdy
  (grawitacja w dół zbocza − przyspieszenie powierzchni) przekroczy μ·nacisk. Powierzchnia
  przyspieszająca w dół odciąża stopy. Model jest deterministyczny i nie ma w nim żadnego
  losowego `fall=true`.
- **Ratunek chwytem:** w stanie STUMBLE/FALLEN albo podczas spadania (vy < −3 m/s) chwyt
  szuka powierzchni w zasięgu całego ciała, także wtedy, gdy przycisk jest trzymany od czasu
  wciągnięcia się na krawędź.

### 2. Upadki (`FallImpact`)
Liczy się prędkość uderzenia wzdłuż normalnej, względem powierzchni.

| Upadek | Prędkość | Skutek |
|---|---|---|
| do ~2,3 m | < 10 m/s | brak |
| ~2,3–5,5 m | < 15,5 m/s | zachwianie (−0,6 równowagi) i obrażenia |
| większy | ≥ 15,5 m/s | przewrócenie na 1,6 s i duże obrażenia; śmierć powyżej ~16,5 m (27 m/s), respawn po 3 s |

Zdrowie to jedna liczba z powolną regeneracją, bez dodatkowych systemów.

### 3. Kamera (`PlayerCamera`)
- Dystans zależy od sytuacji: ziemia 5 m, blisko kolosa 6,5 m, na kolosie 7 m,
  wspinanie 7 m, fokus +4 m.
- Przy wspinaniu pivot wyprzedza gracza wzdłuż kierunku wspinaczki i jest odsunięty od
  powierzchni, więc widać dalszą drogę i fragment kolosa, na którym jest gracz.
- Kamera nie wchodzi w kolosa:
  - pivot jest zawsze w wolnej przestrzeni (cast od rąk lub ciała);
  - boom jest castowany z tego pewnego punktu (`cast_motion` w Godot ignoruje kolizje na starcie);
  - pozycja po wygładzeniu jest dodatkowo sprawdzana twardo.
- Zasłonięcie przez kolosa przybliża kamerę dopiero po 0,35 s i miękko, więc przelatujące ramię
  nie powoduje pompowania dystansu.
- Patrzenie w górę obraca widok, ale boom nie schodzi pod gracza w ziemię.
- Fokus (Q/L1) celuje między graczem a kolosem, więc w kadrze są oba.
- Kamera nigdy nie obraca się sama, z wyjątkiem trzymanego fokusu.

### 4. Przejścia i przypadki graniczne
Sprawdzone testami: chwyt podczas zsuwania, chwyt tuż przed uderzeniem w ziemię (−10,6 m/s),
przejścia noga → biodro → kręgosłup → klatka na obracającym się kolosie, puszczenie podczas
wstrząsu (dziedziczenie 7,4 m/s), skok wzdłuż powierzchni (+1,37 m), wciągnięcie się na krawędź
bez natychmiastowego ponownego chwytu.

### 5. Kolos
- Intencja `shake_player` jest wykonywana w stylu zależnym od tego, **jak** cel jest
  przyczepiony:
  - trzymającym się kolos trzęsie (koszt staminy);
  - stojącego przechyla w jego stronę o 26°, drgając z amplitudą 0,7.

  Brain i reguły się nie zmieniły (wstrząs ≤ 3 s, potem cooldown).
- **Znaleziony i naprawiony błąd ciągłości ruchu:** przy każdej decyzji mózgu (co 0,25 s)
  prędkość i kurs zmieniały się skokowo, co dawało szarpnięcia ~8 m/s² na barkach.
  Wprowadzone zostały prędkość kątowa z ograniczonym przyspieszeniem i ograniczony zryw
  (jerk) prędkości. Zakłócenie podczas chodu spadło z 8,7 do 1,7 m/s².
- **Znaleziony i naprawiony błąd prędkości kątowej:** `acos(w)` kwaternionu w float32
  zaokrąglał obroty z jednego ticka do zera; teraz używany jest `asin(|xyz|)`.
- Doszedł tryb debug `turn` (obrót w miejscu, F2).

### 6. Debug HUD
Stan gracza (GROUND / STAND / AIR / GRIP / CLIMB / SLIP / FALLEN / DEAD), równowaga i stan
równowagi, zakłócenie / pojemność, |a| oraz |ω| powierzchni, prędkość powierzchni, prędkość
spadania i ostatnie uderzenie z kategorią, segment (kość) chwytu lub podłoża, poziom wstrząsu,
stamina, zdrowie, stan kamery i przyczyna jej przybliżenia, a także koszt logiki na tick
i liczba zapytań fizyki na tick.

## Wyniki testów

`tools/run_tests.sh`: **31 testów + sonda kalibracyjna, 0 błędów** (14 z Milestone 1 bez zmian).

Nowe testy: standing_on_still_colossus_is_stable, standing_on_walking_colossus_remains_controllable,
standing_on_turning_colossus_is_carried, shake_destabilizes_standing_player,
player_can_grab_during_slip, severe_shake_can_throw_ungripped_player,
brain_shake_throws_idle_standing_player, gripping_player_resists_shake_using_stamina,
small_fall_is_safe, medium_fall_has_consequence, large_fall_triggers_fall_consequence,
lethal_fall_respawns, late_grab_catches_falling_player, grip_transfer_while_colossus_turns,
camera_does_not_clip_into_colossus, camera_focus_frames_player_and_colossus,
bone_local_grip_still_has_no_drift.

Wybrane wyniki:
- chwyt na idącym kolosie przy wstrząsie: dryf 0,00000 m przy prędkości powierzchni 7,8 m/s;
- stanie na nieruchomym kolosie: dryf 1 mm, równowaga 1,00; na obracającym się: dryf 0 mm;
- na idącym kolosie (1,4 m/s): równowaga 1,00, a gracz przechodzi 1,65 m w 0,3 s;
- półwstrząs: STABLE → UNSTABLE → STUMBLE, bez przewrócenia;
- pełny wstrząs: utrata równowagi po ~1,3 s, ratunek chwytem w 1 tick, zrzucenie po ~2,1 s;
- z prawdziwym mózgiem gracz, który nic nie robi, spada przy drugim wstrząsie (10,9 s);
- kamera: 0 klatek w ciele kolosa na 840 (obracanie kamerą przez ciało, wspinanie, wstrząs);
- upadki: 1,5 m → nic; 5 m → 14,7 m/s, HARD, 27 obrażeń; 12 m → 23 m/s, SEVERE, 77 obrażeń
  i przewrócenie; 18 m → śmierć i respawn.

## Koszty CPU/fizyki (headless, benchmark regresji)

| Scenariusz | Klatka | Kolos | Gracz | Kamera | Zapytania/tick |
|---|---|---|---|---|---|
| wspinanie (jak benchmark M1) | 0,23–0,30 ms | ~45 µs | ~55 µs | — | 3 raycasty |
| wspinanie + kamera | ~0,26–0,32 ms | ~45 µs | ~55 µs | ~35 µs | 2,5 raycasta + 7 zapytań kamery |
| stanie + pełny wstrząs | ~0,30 ms | ~45 µs | ~65 µs | ~50 µs | 7–8 zapytań kamery |
| spadanie z trzymanym chwytem | ~0,12 ms | ~35 µs | ~25 µs | ~20 µs | 2 zapytania sferą + 7 kamery |

Benchmark M1 wynosił 0,22–0,29 ms, więc brak wyraźnej regresji. Przyrost liczby obiektów
przez 300 ticków to −1 (brak wycieków). Raycasty i zapytania korzystają ze współdzielonych
obiektów parametrów (bez alokacji na zapytanie).
`find_grip` liczy najbliższy punkt analitycznie i robi 1 zapytanie sferą plus 1–3 promienie
zamiast wachlarza promieni.

## Znalezione problemy

1. Szarpnięcia ruchu kolosa przy każdej decyzji mózgu: naprawione (patrz wyżej).
2. Zerowa prędkość kątowa (precyzja float32): naprawione.
3. Platforma Godota dryfowała przy obrotach: zastąpiona kotwicą lokalną.
4. `cast_motion` ignoruje kolizje na starcie, przez co kamera przechodziła przez ciało: naprawione.
5. Fokus pod kolosem wbijał kamerę za plecy gracza: naprawione (osobny kąt boomu, kadrowanie obu).
6. Przy liniowym tłumieniu poślizg tylko oscylował; tarcie Coulomba i przechył kolosa
   dają realne zrzucanie.
7. Głowa kolosa, śledząc gracza, fizycznie spycha kogoś, kto stoi tuż przy niej.
   To poprawne zachowanie, ale warto o nim wiedzieć przy projektowaniu tras.

## Znane ograniczenia

- Ciało gracza podczas wspinania nadal nie koliduje z innymi segmentami (kotwica rąk jest
  poprawna). Kamera jest na to odporna.
- Poślizg liczony jest w płaszczyźnie poziomej (wystarcza dla platform ≤ 46°).
- Brak animacji przewrotu i wstawania; jest tylko wizualne przechylenie i leżenie.
- Gracz przewrócony na kolosie nie może sam „przytrzymać się” stopami; ratuje go tylko chwyt.

## Do playtestu przez człowieka

- Czy próg 6 m/s² i tempo utraty równowagi (~1,3 s przy pełnym wstrząsie) dają czas na reakcję?
- Czy przechył kolosa przy stojącym graczu jest czytelny jako ostrzeżenie?
- Czy kara za upadki (5 m = 27% zdrowia, 12 m = 77%) nie jest zbyt surowa? W SotC upadki
  z kolosa bolą, ale rzadko zabijają.
- Kamera: wyprzedzanie przy wspinaniu (1,2 m), dystanse sytuacyjne, wolne oddalanie po zasłonięciu.
- Czy chwyt ratunkowy nie jest za „magnetyczny” (zasięg ~1,15 m od ciała podczas upadku)?
