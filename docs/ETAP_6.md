# Etap 6 — Quadratus, łuk i strzały

Pytanie etapu: **czy wspólne systemy (locomotion, IK, wspinanie, weak pointy, fairness,
encounter) uniosą drugiego, zupełnie innego bossa bez kodu „pod niego”?**
Odpowiedź: tak. Quadratus jest czworonogiem z inną pętlą walki (łuk → kopyto → klęknięcie
→ wspinaczka), a we wspólnym kodzie nie ma ani jednego `if boss == Quadratus`.

- Bot grający wyłącznie przez `PlayerActions` pokonuje Quadratusa pieszo i z Agro
  w każdym przejściu długiego testu (wyniki niżej). Valus pozostał pełnym testem regresji.
- Obie walki i sam łuk dają identyczny stan symulacji przy renderze 30–240 FPS.
- Wszystkie 95 wcześniejszych wpisów zestawu przechodzi; razem 120/120 (118 testów + A/B
  i sonda balansu), pełny przebieg ~12 min headless.

Nazewnictwo: od tego etapu projekt używa oryginalnych nazw kolosów. Boss z Etapu 5 to
**Valus** (`Valus`, `ValusBrain`, `ValusArena`, `ValusBot`), encounter jest wspólny
(`BossEncounter`).

## Pętla walki z Quadratusem

```
wejście na równinę (DORMANT, głowa nisko) -> NOTICE (1,4 s) -> ENGAGED (1,2 s, ryk) -> COMBAT
  -> Quadratus podchodzi, obraca się łukiem za graczem, atakuje: stomp przednim kopytem,
     uderzenie głową (oba z telegrafem); gracz ucieka między nogami i za zad
  -> za nim: łuk, naciąg; tylne kopyto w kroku unosi się i odwraca podeszwę do tyłu
  -> strzała w podeszwę (tylko od tyłu, tylko gdy kopyto jest w górze)
  -> REACT: kolano puszcza (support 1 -> 0), ryk, brak decyzji
  -> KNEEL (11 s): ciało opada na ten róg, futro uda w zasięgu; bez ataków i shake'ów
  -> skok i chwyt uda -> udo -> zad (futro równo z udem) -> grzbiet
  -> weak point na zadzie: chwyt futra, ładowanie, cios (zachwianie po trafieniu)
  -> RISE: kolos wstaje z graczem na grzbiecie; potem shake_body (z telegrafem, limitem)
  -> po grzbiecie (kamienne siodło = odpoczynek) do karku -> głowa -> weak point na czole
  -> oba weak pointy zniszczone -> DEFEATED: kolos się kładzie, „COLOSSUS DEFEATED”
zrzucony / koniec klęknięcia przed wejściem -> znowu łuk
```

## Architektura

```
observe() -> QuadratusBrain.decide()       proponuje intencję (utility, z seedem)
          -> FairnessRules + _rules_block  blokuje (cooldowny, klęknięcie), przycina czasy
          -> intencja -> ataki (ColossusAttack) / reakcja stopy / ruch
          -> LocomotionController: 4 nogi, kolejność kroków, LegState.support, pochylenie
          -> GreyboxQuadruped: kość body = miednica + pochylenie + shake; IK 4 nóg
          -> segmenty (BodySegment) -> HitVolume, WeakPoint, ArrowTarget na kościach
gracz: PlayerActions -> PlayerBow -> ArrowSystem (stały krok) -> ArrowTarget.hit -> kolos
```

### Czworonóg we wspólnym locomotion (`LocomotionController`)

Nowe, ogólne możliwości (dwunożny Valus używa starych ścieżek bez zmian liczbowych):

- **`gait_sequence` + `cycle_steps`**: kroki w stałej kolejności, jeden na takt
  (stęp: tył‑lewa, przód‑lewa, tył‑prawa, przód‑prawa). Wymachy się nakładają (max 2 nogi
  w powietrzu), zawsze stoją co najmniej 2.
- **`LegState.support`**: jak dobrze noga niesie ciało. Osłabiona noga nie robi kroków,
  nie niesie ciężaru (rozkład obciążenia proporcjonalny do `support`, zawsze sumuje się do 1),
  a jej zasięg maleje do `buckle_reach` — ciało opada na ten róg. Gdy jakaś noga jest
  osłabiona, pozostałe nie robią dobrowolnych kroków (tylko pilne, nigdy dwóch naraz).
- **`body_tilt`**: biodra leżą na płaszczyźnie dopasowanej (najmniejsze kwadraty) do
  wysokości, na jaką pozwala każda noga. Pochylenie i przechył idą przez sprężynę i limit
  `max_body_tilt`, wysokość środka obniżana miękkim maksimum przekroczeń. Na rampie 10°
  ciało pochyla się o 0,18 rad, po trafieniu w tylną lewą nogę: pitch 0,22, roll 0,40 rad.
- `hip_world()` liczy pochylone biodra (sprawdzenie zasięgu w planerze).

`GreyboxQuadruped` to wspólny rig czworonoga: anatomia z `_rig()` / `_parts()`, IK czterech
nóg (kolana przednich do przodu, tylnych do tyłu), kopyto w wymachu odwraca podeszwę
do tyłu (`swing_hoof_flip`), shake = przechył i „bryknięcie” tułowia z rzutem głową,
statystyki stóp, nakładka debug (fazy stóp, podpory, COM, obciążenie każdej nogi,
wysokość dopuszczana przez każdą nogę). Haki: `_adjust_movement`, `_pose_overrides`,
`_draw_debug_extra`.

### Quadratus (`src/colossus/quadratus/`)

- **Anatomia** (to nie Valus na czterech nogach): długi tułów ~13 m nad ziemią, biodra 7,2 m,
  nogi 4,0 + 3,6 m. Futro: tułów (chodliwy wierzch), zady równo z udami (droga z uda na
  grzbiet bez okapu pod brzuchem), kark, czapa na głowie. Kamień: golenie, kopyta, siodło
  na grzbiecie (`rest`), pancerz na bokach barków. Futro na udach tylko w górnej części:
  gdy nogi stoją, najniższe futro jest na ~4,8 m (poza zasięgiem skoku), po klęknięciu ~2,4 m.
- **Stany ruchu** (`move_state()`): IDLE, WALK, TURN, REPOSITION, ATTACK, STAGGER,
  KNEEL (lowered body), RECOVER. Obrót za graczem to wolny marsz po łuku (0,35 prędkości),
  nigdy obrót w miejscu jak obiekt. Chód 1,3 m/s, krok (stride) ~4,5 m, 4 takty.
- **Intencje** (`QuadratusBrain`): `observe`, `approach`, `turn`, `reposition`, `stomp`,
  `head_attack`, `react_to_foot_hit`, `lower_body`, `recover`, `shake_body`.
- **Ataki** (TELEGRAPH → ACTIVE → RECOVERY, po przycięciu przez `FairnessRules`):
  - stomp przednim kopytem: telegraf 1,0 s (kopyto 3,6 m w górę, śledzi cel przez 60%
    telegrafu z prędkością 2 m/s), uderzenie 0,3 s, fala 7 m, recovery 1,8 s;
    wspólny `LimbStomp` (ten sam ruch co stomp Valusa);
  - uderzenie głową: telegraf 1,1 s (szyja w górę), 0,45 s zamachu w dół, recovery 1,5 s,
    kapsuła trafienia na kości głowy.
  Strefy zagrożenia trafiają do Agro (`danger_sources`).
- **Trafienie w kopyto**: `ArrowTarget` na podeszwie obu tylnych kopyt. Liczy się tylko,
  gdy kopyto jest w wymachu, podeszwa > 0,25 m nad ziemią i strzała leci pod prąd normalnej
  podeszwy (od tyłu). Kamień kopyta, golenie i strzały z przodu / z boku nie robią nic.
  Reakcja: REACT 1,4 s (ryk, rzut głową) → KNEEL 11 s → RISE 2,6 s → cooldown 4 s.
- **Reakcje na gracza na ciele**: `shake_body` z telegrafem 0,7 s (napięcie, przysiad),
  przechył i bryknięcie tułowia, rzut głową / barkami; limit 3 s i cooldown 5 s ze wspólnych
  reguł (`_shake_kinds()`); zablokowany w czasie klęknięcia. Po trafieniu w weak point:
  zachwianie z obwiednią sin² (bez skoku pozy).
- **Weak pointy**: zad (kość body) i czoło (kość head), po 80 HP, ten sam `WeakPoint` co
  u Valusa. Oba zniszczone → DEFEATED: wszystkie nogi tracą podparcie przez 5 s,
  kolos się kładzie (grzbiet ~6,5 m, futro boków do ~1 m nad ziemią — da się zejść).

### Łuk i strzały

- **`PlayerBow`**: IDLE → DRAW → AIM → RELEASE → RECOVERY na akcji `attack`; pełny naciąg
  w 0,9 s; prędkość strzały 22–58 m/s zależnie od naciągu; puszczenie przed 20% naciągu
  nie strzela. Zmiana broni: `switch_weapon` (Tab / R / D‑pad prawo). Bez specjalnych
  strzał, craftingu i ekwipunku.
- **Celowanie**: kierunek z `PlayerActions.view_basis`, początek promienia z `aim_origin`
  (kamera albo w przyszłości kontroler VR). Strzała leci z łuku w punkt pod celownikiem
  (1 raycast celowania na tick w czasie naciągu). Grawitację kompensuje gracz.
  `PlayerBow.launch_direction()` to rozwiązanie balistyczne dla botów / AI kompana.
- **`ArrowSystem`**: strzały jako prawdziwe pociski w stałym kroku: krok balistyczny
  (g = 9,8, bez oporu), potem analityczny test kuli `ArrowTarget` w jego ruchomym układzie
  (szybka stopa nie przeskoczy strzały) i 1 raycast na strzałę i tick (świat + kolosy).
  Strzała w kolosie przykleja się do kości (porusza się z nim), w ziemi zostaje, znika
  po 12 s. Trajektoria jest dokładnie parabolą (odchyłka 0,000000 m).
- **Z konia**: łuk działa w stanie RIDE. Strzała dziedziczy prędkość konia. Podczas
  naciągu drążek steruje względem konia (skręt / napęd), bez drążka koń trzyma kurs,
  gdziekolwiek patrzy kamera: kierunek Agro jest niezależny od celowania.
- **Debug (F3)**: przewidywana trajektoria dla bieżącego naciągu (biała, żółta przy
  pełnym), wektor celowania, punkt pod celownikiem, przeleciane tory strzał, punkt
  trafienia (czerwony = cel, szary = powierzchnia). HUD: celownik, łuk naciągu, stan łuku,
  prędkość strzały.

### Valus: wspólny stomp i bezpieczne zejście

- Stomp Valusa używa teraz wspólnego `LimbStomp` (ta sama matematyka; testy ataków Valusa
  przechodzą bez zmian).
- Zakończenie: pokonany Valus przez 9 s osuwa się na kolana (miednica −5,6 m) i pochyla
  (−1,6 rad). Gracz trzymający się głowy zjeżdża z ~18 m na ~2 m nad ziemią, kotwica
  zostaje na powierzchni (błąd 0,000003 m), puszczenie = bezpieczne lądowanie (0 obrażeń).
  Bez teleportu.

## Wyniki testów

Pełny przebieg `tools/run_tests.sh`: **120/120 PASS** (95 wcześniejszych + 25 nowych).

| Test | Wynik |
|---|---|
| `quadratus_four_leg_locomotion_is_stable` | 36 s chód / skręt / stop: kolejność RL‑FL‑RR‑FR 100%, max 2 nogi w powietrzu, zawsze ≥ 2 stoją, przechył ≤ 0,11 rad (w skręcie), wysokość bioder 7,00–7,20 m, po zatrzymaniu 0 kroków |
| `quadratus_feet_do_not_slide` | poślizg stojącej stopy max 0,0004 m/s (5125 stopo‑ticków) |
| `quadratus_handles_uneven_ground` | rampa 10°, garby, stopień 0,8 m: pitch 0,184 rad (rampa 0,175), podeszwa vs grunt 0,000 m, błąd zasięgu IK 0,000 m |
| `quadratus_weight_shifts_between_legs` | każda noga 0,00 ↔ 0,50 ciężaru, noga w wymachu 0,000, suma = 1 (±0,000), środek podparcia ±2,84 m na boki |
| `quadratus_foot_target_can_be_hit_with_arrow` | stojące kopyto: 0 ticków jako cel; w wymachu: trafienie (lot 0,27 s) |
| `quadratus_reacts_to_correct_foot_hit` | kamień kopyta → brak reakcji; podeszwa → REACT → KNEEL, intencje `react_to_foot_hit`, `lower_body`, support 0, 0 ataków |
| `quadratus_body_lowers_after_foot_hit` | biodro tego rogu 7,20 → 3,26 m, środek 7,20 → 5,51 m, pitch 0,22 / roll 0,40 rad, futro uda 4,82 → 2,39 m, obciążenia 0,33/0,33/0,00/0,33, max 0,047 m/tick, 0 kroków w czasie opadania; potem wstaje (support 1, 7,20 m) |
| `quadratus_climb_route_becomes_reachable` | chwyt uda przed trafieniem: nie; po: tak; od uda do weak pointu na zadzie 3,1 s |
| `quadratus_grip_has_no_drift` | chwyt uda przez klęknięcie, wstanie i marsz (8,6 m): kotwica vs powierzchnia 0,000001 m, dryf 0 |
| `quadratus_weakpoint_moves_with_body` | weak point przesunął się 9,1 m z ciałem, błąd vs kość 0 |
| `quadratus_body_reaction_is_fair` | 60 s na grzbiecie: 6 shake'ów, telegraf ≥ 0,73 s, najdłuższy 3,02 s, przerwa ≥ 5,07 s, 0 shake'ów w klęknięciu |
| `quadratus_can_be_defeated` | 6 pełnych ciosów (3 + 3; drugi i trzeci słabszy, bo kolos się zatacza), DEFEATED, leży (zad 6,5 m), zejście bez obrażeń |
| `quadratus_scripted_driver_can_complete_fight` | pieszo: wygrana 57,4 s; z Agro: 87,3 s (2 strzały z siodła) |
| `quadratus_simulation_independent_of_render_fps` | cała walka pieszo i z Agro przy 30/60/90/120/144/240 FPS: różnica stanu 0,00000000 |
| `quadratus_cost_stays_within_budget` | patrz „Wydajność” |
| `valus_defeat_leaves_a_safe_way_down` | z głowy 18,0 m → 2,0 m (czubek głowy 3,0 m), puszczenie: lądowanie bez obrażeń |
| `bow_draw_strength_changes_arrow_velocity` | 0,1 s: brak strzału; 0,3 s: 33 m/s / 33 m; 0,6 s: 45 m/s / 53 m; pełny: 58 m/s / 81 m |
| `bow_trajectory_is_repeatable` | dwa identyczne strzały: różnica 0,00000000 m, odchyłka od paraboli 0,000000 m |
| `arrow_hits_expected_target` | 15 / 30 / 60 m: trafienie, czas lotu = przewidywany (±1 tick) |
| `arrow_misses_when_aim_is_wrong` | 1,5° w bok, bez poprawki na opad, słaby naciąg, od tyłu celu: pudło |
| `bow_is_independent_of_render_fps` | 3 strzały pieszo + 1 z galopującego Agro przy 30–240 FPS: różnica 0,00000000 |
| `player_can_aim_from_agro` | jazda 5,2 m/s: naciąg na koniu, strzał, trafienie celu z boku |
| `horse_heading_is_not_changed_by_aim` | celowanie 360° przez 3 s: kurs konia zmienił się o 0,0000 rad; drążek w prawo przy patrzeniu w lewo: koń skręca w prawo |
| `arrow_hit_can_trigger_colossus_reaction` | strzała → `foot_hit`, REACT, `react_to_foot_hit` |
| `all_valus_and_earlier_tests_still_pass` | 95 wcześniejszych, 0 porażek |

## Długie testy (soak)

`tools/run_boss_soak.sh` — każda walka od początku do końca, bez powtórek, inne ziarno mózgu
i inny start (Quadratus: na zmianę pieszo / z Agro, dystans strzału 10–17 m).

| | Valus (100 walk) | Quadratus (50 walk: 25 pieszo, 25 z Agro) |
|---|---|---|
| wygrane | **100/100** | **50/50** (25 pieszo, 25 z Agro) |
| czas walki min / mediana / max | 56,7 / 58,0 / 232,3 s | 56,8 / 68,2 / 193,4 s |
| śmierci | 32 (wszystkie: upadek, głównie z głowy) | 2 (upadek po zrzuceniu z grzbietu) |
| deadlocki | 0 | 0 |
| nieosiągalny weak point | 0 | 0 |
| zgubiony chwyt / skok chwytu > 0,5 m/tick | 0 | 0 |
| zły reset | 0 | 0 |
| zakleszczenia AI (ta sama intencja > 25 s) | 0 | 0 |
| zepsuta reakcja stopy (nie REACT→KNEEL→RISE→NONE albo support ≠ 1) | — | 0 z 71 |
| strzały | — | 155: 71 w podeszwę (46%), 83 w ciało / ziemię, 1 w zamknięty cel, 0 z niewłaściwej strony; 28 z konia |
| niewykorzystane klęknięcia | — | 1 z 71 |
| trafienia gracza przez bossa | 0 | 20 |

Pudła bota to głównie strzały, gdy kopyto zmieniało kierunek albo zasłaniała je druga noga
(bot strzela z wyprzedzeniem, ale nie zna przyszłej trajektorii wymachu).

## Wydajność

Zmierzone (`test_quadratus_cost_stays_within_budget`: bot z Agro, potem wspinaczka, 30 s;
pełny przebieg testów na obciążonej maszynie — 4 rdzenie, równolegle 2 soaki i render zrzutów).

| System | µs / tick |
|---|---|
| Quadratus razem | 268 (bez obciążenia: 296 w innym przebiegu; zakres 270–300) |
| — mózg (`QuadratusBrain`, co 0,25 s) | 9 |
| — walka (encounter, ataki, reakcja stopy) | 34 |
| — trafienia (HitVolume) | 10 |
| — poza (głowa, reakcje) | 6 |
| — locomotion czterech nóg | 113 |
| —— w tym balans / przenoszenie ciężaru (`loco_balance`) | 41 |
| — IK czterech nóg | 38 |
| łuk (`bow`, w tym raycast celowania) | 0,5 (średnio; w czasie naciągu ~1 promień/tick) |
| symulacja strzał (`arrows`, 1–2 w locie) | 7 |
| gracz razem | 78 (w tym wspinanie 28) |
| Agro | 164 |
| kamera | 64 / klatkę |
| pełny tick fizyki (monitor silnika, z serwerem fizyki) | śr. 2,86 ms / max 4,46 ms (bez obciążenia); 5,15 / 7,54 ms przy 3 procesach na 4 rdzeniach |

Zapytania fizyki na tick: strzały 0,02 promienia (1 na strzałę w locie), testy celów 0,04
(analityczne, bez fizyki), promień celowania łuku 0,01 (tylko przy naciągu), wspinanie 0,58,
Agro 0,19–5, kamera 7,05; sonda gruntu kolosa: 1 na krok. Valus w tym samym przebiegu:
274 µs/tick (bez zmian względem Etapu 5).

Nic nie wymaga optymalizacji ani Ziga: najdroższy jest Agro z sondami przeszkód, potem
locomotion czterech nóg.

## Naprawione problemy w trakcie etapu

- Czworonóg chodził inochodem (lewa przednia i lewa tylna razem): bramka kroku liczy
  takty od startu poprzedniego kroku, nie od lądowania.
- Na rampie kolos dreptał w miejscu bez końca: sprawdzenie zasięgu nogi ignorowało
  pochylenie bioder (`hip_world()`).
- Suma obciążeń nóg chwilowo odbiegała od 1 o 15%: normalizacja dla > 2 nóg.
- Wspinaczka z uda kończyła się pod brzuchem (okap): futrzane zady równo z udami.
- Bot puszczał chwyt na samej krawędzi grzbietu (futro przechodzi przez krawędź) i spadał:
  czołga się po futrze do weak pointu; na pochylonym (klęczącym) grzbiecie czeka w chwycie.
- Klęczący Quadratus robił kroki dwiema nogami naraz (widać na zrzucie): przy osłabionej
  nodze planer nie robi dobrowolnych kroków.
- Quadratus obracał się w miejscu za graczem stojącym na jego grzbiecie: gracza na sobie
  czuje, a nie obserwuje.
- Strzała raportowała punkt trafienia na brzegu sfery celu: teraz najbliższy punkt toru.
- Pokonany Valus zostawiał gracza trzymającego się głowy ~12 m nad ziemią: głębsze
  klęknięcie i skłon (głowa ~3 m), rozłożone na 9 s, żeby chwyt nie skakał.

## Ograniczenia

- Jedna celna strzała otwiera oba weak pointy: przy 11 s klęknięcia bot zdąży wejść na
  zad, a po wstaniu przejść grzbietem do głowy. Walka jest krótka (~1–1,5 min).
- Kopyto w wymachu to jedyny cel strzał; brak innych reakcji na strzały (np. w oko).
- Brak oporu powietrza i wiatru; strzały nie odbijają się od kamienia (przyklejają się).
- Shake czworonoga to przechył / bryknięcie / rzut głową bez „gwałtownego kroku”
  w bok (kroki wymagałyby planowania z graczem na grzbiecie).
- Grafika to nadal greybox (assety z gałęzi `dot/art-ancient-frontier` jeszcze nie istnieją).

## Lista do playtestu

- Czy podeszwa jest czytelna jako cel (kolor, moment odsłonięcia, ~1 s okna)?
- Czy 11 s klęknięcia to dobre okno (za długie = jedna strzała na całą walkę)?
- Czas pełnego naciągu 0,9 s i prędkości 22–58 m/s: czy łuk „czuje się” dobrze z konia?
- Sterowanie Agro względem konia podczas celowania: intuicyjne czy myli?
- Czy uderzenie głową i stomp są dobrze telegrafowane z perspektywy gracza na koniu?
- Shake na grzbiecie: siła, częstość, czy kamienne siodło jest dobrym miejscem odpoczynku?
- Zejście z leżącego Quadratusa i klęczącego Valusa: czy jest oczywiste?
- Kamera przy celowaniu (brak zbliżenia przez ramię — do decyzji).

## Zrzuty

`tools/capture_screenshots.sh quadratus` (prawdziwa scena, bot z Agro) zapisuje do
`tests/output/quadratus_*.png`: wejście, celowanie z konia z trajektorią, trafienie
w podeszwę (nakładka), klęknięcie, nakładka klęknięcia (podpory, obciążenia, COM),
wspinaczka po udzie, zad, ładowanie ciosu, shake, droga do głowy, czoło, stomp i
uderzenie głową (telegraf i trafienie), pokonany kolos.

## Propozycja Etapu 7

**Etap 7 — trzeci kolos (Gaius) i domknięcie pętli Quadratusa.**

1. **Gaius** (humanoid z kamiennym mieczem): pierwszy kolos z bronią jako osobnym,
   kinematycznym obiektem (kość dłoni + segmenty miecza). Uderzenie mieczem wbitym
   w ziemię jako droga na ramię (wspinanie po broni), pancerz kruszony ciosem
   (nowa mechanika: niszczalny pancerz na `BodySegment`), na wspólnym `GreyboxHumanoid`.
2. **Quadratus — pętla „repeat”**: drugi weak point dostępny dopiero po drugim
   klęknięciu (np. głowa wysoko, dopóki obie tylne nogi nie zostaną trafione po kolei),
   krótsze klęknięcie po pierwszym zniszczonym weak poincie.
3. **Łuk**: zbliżenie kamery przy naciągu (przez ramię), drżenie przy długim trzymaniu
   pełnego naciągu, odbijanie strzał od kamienia.
4. **Reakcje czworonoga na gracza**: gwałtowny krok w bok z graczem na grzbiecie
   (planowany jak atak: telegraf, limit, cooldown).
5. **Assety**: podpięcie modeli z `dot/art-ancient-frontier`, jeśli gałąź będzie gotowa
   (szkielety muszą zachować nazwy kości z greyboxów albo dostać mapę kości).
6. Soak obu bossów po 100 walk przy każdym etapie (czas pozwala).
