# Architektura (stan po Etapie 8)

Dokument opisuje decyzje, które mają przetrwać dalszy rozwój. Kod jest komentowany po angielsku
(open source), a dokumentacja projektowa jest po polsku.

## 1. Wspinanie: kotwica w przestrzeni lokalnej segmentu

**Problem:** gracz ma trzymać się ciała, które się porusza, obraca, trzęsie i jest animowane.

**Rozwiązanie:** podczas chwytu jedynym stanem gracza jest `SurfaceAnchor`:
`(body, shape, local_point, local_normal)` w przestrzeni lokalnej collidera. W każdym ticku
pozycja gracza jest *wyliczana* z aktualnej transformacji ciała:

```
pozycja = body.global_transform * local_point + normal * hang_distance - climb_up * hand_reach
```

Skutki:
- zero dryfu i zero opóźnienia względem ciała, niezależnie od sposobu animacji
  (proceduralna, AnimationPlayer, IK);
- do sieci replikujemy `(id segmentu, local_point, local_normal)`, czyli dokładnie to, czego
  wymaga plan online (pozycje względem kości);
- VR: każda ręka dostanie własną kotwicę, bo model jest ten sam.

### Powierzchnia wspinania
- Collidery to proste kształty (box/capsule) na `BodySegment` (`AnimatableBody3D`), które
  podążają za kością `Skeleton3D`. Nigdy nie kolidujemy ze skinned meshem.
- Chwytalność jest cechą **kształtu**, nie ciała. `ClimbPatch` (futro, pnącza, spękania) to
  chwytalny `CollisionShape3D` z parametrami (`grip_cost`, `slip_speed`). Zwykły
  `CollisionShape3D` (kamień, pancerz) blokuje wspinanie, ale można po nim chodzić.
  Jeden segment może więc łączyć futro z pancerzem.
- Ten sam system działa na statycznej geometrii (ruiny w sandboxie), co przyda się w eksploracji.

### Ruch po powierzchni (`ClimbQuery.crawl`)
Kilka krótkich raycastów na tick:
1. ściana/stopień przed rękami (blisko i dalej od powierzchni), czyli róg wklęsły lub przejście
   na inny segment;
2. kontynuacja bieżącej powierzchni (płaskiej lub zakrzywionej);
3. zawinięcie wokół krawędzi wypukłej (obchodzenie kończyny, wejście z nawisu na ścianę).

Trafienie w kształt niechwytalny oznacza blokadę. Przejścia między kośćmi nie wymagają żadnej
specjalnej logiki, bo to po prostu trafienie w inny segment.

### Orientacja „góry” (`climb_up`)
Kierunek „do góry” jest przenoszony równolegle (parallel transport) przy każdej zmianie normalnej,
a na pionowych ścianach przyciągany do pionu świata. Dzięki temu wejście pod nawis i wyjście
na jego zewnętrzną ścianę zachowuje sens sterowania. Na górnych powierzchniach sterowanie
jest względne do kamery.

### Szczegół Godota: `sync_to_physics`
`AnimatableBody3D` z `sync_to_physics` cofa ustawioną transformację węzła i przyjmuje ją dopiero
po kroku fizyki. Węzeł, serwer fizyki i render są więc spójne, ale o jeden tick za kością.
Konsekwencje w kodzie:
- zapytania fizyczne startują z `SurfaceAnchor.query_point()` (transformacja serwera);
- prędkości punktów liczymy z `BodySegment.target_transform/previous_target`;
- dzięki `sync_to_physics` gracz stojący na barkach jest poprawnie niesiony (platform velocity).

## 1b. Stanie na kolosie (Etap 2)

- **Niesienie:** ta sama zasada co przy chwycie. Po każdym `move_and_slide` zapisujemy pozycję
  gracza w przestrzeni lokalnej segmentu pod stopami, a na początku następnego ticka
  odtwarzamy ją z aktualnej transformacji segmentu. Platforma Godota jest wyłączona
  (`platform_floor_layers = 0`). Przy zejściu z ciała gracz dostaje prędkość punktu
  materialnego, na którym stał.
- **Równowaga (`Balance`):** jedna wartość 0..1 zmieniana w sposób ciągły przez „zakłócenie”
  (m/s²). Stan wyznacza kontrolę i tarcie. Bez ragdolla i bez losowości.
- **Poślizg:** prędkość własna gracza i poślizg są rozdzielone (`velocity = own + slide`).
  Poślizg wynika z tarcia Coulomba w układzie powierzchni.
- **Upadki (`FallImpact`):** progi prędkości uderzenia względem powierzchni.
- Wszystkie trzy klasy to czyste dane (`RefCounted`), łatwe do testowania i replikacji.

## 2. Kolos: CO (mózg) oddzielone od JAK (kontroler)

```
Colossus.observe() -> ColossusObservation
      -> ColossusBrain.decide()  (co think_interval, domyślnie 0,25 s)
      -> reguły encountera (fairness, ręcznie projektowane)
      -> _execute_intent()  ciągły kontroler: prędkość, kurs, amplituda wstrząsu, spojrzenie
      -> _pose_bones()      pozy kości (później IK / AnimationTree)
      -> BodySegment.follow_bone()
```

- `ColossusBrain` to stabilny interfejs: obserwacja na wejściu, `ColossusIntent` na wyjściu.
  Mózg nie rusza kości i nie widzi drzewa sceny. `UtilityBrain` to pierwsza implementacja
  (deterministyczna dla danego seeda). Mały model decyzyjny podmieni tylko tę klasę, co
  umożliwia test A/B.
- `ColossusIntent.kind` to `StringName`, więc kolejne kolosy dodają własne intencje bez
  modyfikowania wspólnego kodu.
- **Reguły są poza AI.** Przykład z M1: wstrząs trwa maksymalnie `shake_max_duration`, a po nim
  następuje `shake_cooldown`. Żaden mózg nie może tego obejść (sprawdza to test). Tu trafią
  gwarancje w rodzaju „słaby punkt jest regularnie wystawiany”.
- Kontroler zmienia parametry ciągle i powoli, więc kolos nie przeskakuje między stanami.
  Prędkość ma ograniczony zryw (jerk), kurs ograniczone przyspieszenie kątowe, wstrząs rampę,
  a spojrzenie jest wygładzone. Decyzje mózgu co 0,25 s nie mogą przez to powodować szarpnięć
  (pilnuje tego sonda `probe_balance_disturbance` i test chodu).
- Ta sama intencja może mieć różne wykonanie zależnie od sytuacji. `shake_player` trzęsie
  graczem, który się trzyma, a stojącego przechyla w jego stronę. Brain o tym nie wie.
- Nowy kolos to podklasa `Colossus`, która dostarcza rig (`_build_body`), kontroler i własne
  reguły. `GreyboxHumanoid` definiuje rig tabelami `BONES`/`PARTS`.

## 2b. Locomotion (Etap 3)

```
Intent -> desired movement -> LocomotionController (masa, planer kroków, miednica)
       -> rig: IK nóg + górna część ciała -> Skeleton3D -> BodySegment
```
Szczegóły i pomiary: [ETAP_3.md](ETAP_3.md). Zasady:
- Brain nigdy nie steruje nogami.
- Kontroler nie zna kości, więc kolejny kolos dostarcza tylko mapowanie na swój szkielet.
- Każdy człon pozy musi być gładki (C²), inaczej daleki od stawu bark dostaje szarpnięcia.
- Symulacja działa tylko w stałym kroku. Render, kamera i wejście nie wpływają na stan gry.
  Pilnuje tego test uruchamiany przy 30/60/144/240 FPS.

## 2c. Agro (Etap 4)

```
rider / AI / test -> HorseInputIntent -> HorseController (chód, masa, R(v), omijanie, hamowanie)
                  -> QuadrupedGait (zegar chodu, fazy nóg) -> Horse (tułów, szyja, IK nóg)
                  -> Skeleton3D -> siodło (kość body) -> PlayerRiding
```
Szczegóły i pomiary: [ETAP_4.md](ETAP_4.md). Zasady:
- Jeździec nigdy nie ustawia prędkości ani kursu. Wyraża zamiar (kierunek, kopnięcie, wodze),
  a koń przekłada go na ruch w granicach swojej masy i promienia skrętu.
- Jeźdźcem jest dowolny węzeł z `build_ride_intent()` (`current_rider` się zmienia).
  `HorseInputIntent` nie zna urządzeń. Polecenia AI (`follow/come/stop`) to wspólne API
  dla gracza, AI kompana i testów.
- Autonomia jest lokalna: korekta kursu, zwolnienie, zatrzymanie. Koń nie szuka ścieżki
  i nie wybiera nowej drogi za jeźdźca.
- Wspólna z kolosem jest tylko matematyka kroku (`StepMath`, `LegState`, `TwoBoneIK`).
  Rytm czworonoga to osobny `QuadrupedGait`.
- Jeździec jest zakotwiczony do kości jak chwyt: zero dryfu. Wsiadanie i zsiadanie to łuki
  w układzie konia, bez teleportów. Zsiadanie wymaga bezpiecznego miejsca.
- Kolejność w ticku: kolos (−10) → koń (−9) → gracz (0), więc jeździec czyta siodło
  z bieżącego ticku.

## 2d. Walka z bossem (Etap 5)

```
observe -> Brain.decide (proponuje) -> FairnessRules (blokuje, przycina czasy) -> intencja
       -> ColossusAttack: TELEGRAPH -> ACTIVE -> RECOVERY (pozy kończyn, HitVolume na kościach)
       -> ruch -> locomotion / IK -> segmenty -> trafienia testowane po synchronizacji kości
gracz: PlayerActions -> PlayerSword (READY/CHARGE/STRIKE/RECOVERY) -> WeakPoint.try_hit
BossEncounter: śmierć -> pauza -> reset; pokonanie -> DEFEATED
```
Szczegóły: [ETAP_5.md](ETAP_5.md). Zasady:
- Mózg niczego nie wymusza. Reguły fairness to osobny obiekt, silniejszy od każdego mózgu.
  Test ze „spamującym” mózgiem (zawsze stomp / zawsze shake) to sprawdza.
- Żaden atak nie zadaje obrażeń w ticku decyzji. Hitboxy to kapsuły na prawdziwych kościach
  kończyn, aktywne tylko w fazie ACTIVE.
- Weak point żyje na segmencie (kości) i bierze pozycję z bieżącego ticku. Walkę wygrywa się
  przez weak point, nie przez pasek HP.
- Jedna gra dla wszystkich: bot testowy gra wyłącznie przez `PlayerActions`, jak człowiek.
- Wszystko w stałym kroku: cała walka przy 30–240 FPS daje identyczny stan.

## 2e. Czworonożny kolos, łuk i strzały (Etap 6)

```
QuadratusBrain -> FairnessRules + reguły kolosa -> intencja -> ataki / reakcje / ruch
  -> LocomotionController (4 nogi: kolejność kroków, LegState.support, pochylany tułów)
  -> GreyboxQuadruped (kość body z miednicy + pochylenie + shake, IK czterech nóg)
gracz: PlayerActions -> PlayerBow (IDLE/DRAW/AIM/RELEASE/RECOVERY) -> ArrowSystem
  -> ArrowTarget (podeszwa kopyta) -> reakcja kolosa (noga traci podparcie)
```
Szczegóły: [ETAP_6.md](ETAP_6.md). Zasady:
- Nie ma `if boss == Quadratus` we wspólnym kodzie. Wspólne mechanizmy (planer kroków,
  podparcie nogi, pochylenie ciała, `LimbStomp`, `ArrowTarget`, `WeakPoint`, `FairnessRules`,
  `BossEncounter`) są konfigurowane przez anatomię i parametry konkretnego kolosa.
- Klęknięcie nie jest animacją: trafiona noga traci `support`, planer przestaje jej używać,
  reszta nóg przejmuje ciężar, a płaszczyzna bioder opada na ten róg.
- Strzała to pocisk w stałym kroku (balistyka bez oporu, jeden raycast na strzałę i tick
  plus analityczny test kuli w ruchomym układzie celu). Identyczna trajektoria przy 30–240 FPS.
- Celowanie pochodzi z `PlayerActions.view_basis` / `aim_origin`, więc VR może podać pozę
  kontrolera. Na koniu podczas celowania drążek steruje względem konia: celowanie nigdy
  nie skręca Agro.

## 2f. Wspólna baza humanoidów, pancerz, assety (Etap 7)

```
HumanoidBoss (encounter, stomp, trafienia, weak point, pokonanie, debug; hooki)
  ├─ Valus  (_attack_kinds: stomp, arm_sweep, protect)
  └─ Gaius  (_attack_kinds: stomp, sword_slam; kość `sword`, ArmorPlate na hełmie)
ArenaArt.dress_arena / skin_colossus / dress_valus  -> tylko węzły wizualne
```
Szczegóły: [ETAP_7.md](ETAP_7.md). Zasady:
- Podklasa bossa zmienia tylko hooki (`_make_brain`, `_make_attack`, `_attack_tick`,
  `_holds_still`, `_extra_rules`…). Cykl ataku, zamknięcie ataku i zgłoszenie do
  `FairnessRules` są w bazie i zamykają się dokładnie raz (meta `closed`).
- Broń kolosa to kość z własnym segmentem. Wbity miecz to zwykła powierzchnia kolizji
  i wspinania, a „okno” to atak w fazie RECOVERY, który trzyma pozę.
- `ArmorPlate` i `WeakPoint` mają to samo API trafienia; `PlayerSword` wybiera najbliższy
  cel, który przyjmie cios. Weak point pod pancerzem jest zamknięty, dopóki pancerz stoi.
- Warstwa assetów nie dotyka kolizji ani logiki: ukrywa siatki greyboxu i dokłada własne.
  Testy budują areny bez niej, a jeden test dowodzi w osobnych procesach, że stan
  symulacji z nią i bez niej jest identyczny.

## 2g. Cała gra: regiony, promień, zapis (Etap 8)

```
GameWorld ── GameState (kolejność kolosów, zapis JSON)
   ├─ region DOLINA: Valley.build (Ancient Valley = podłoże), gracz, Agro, kamera, HUD
   └─ region ARENA:  XxxArena.build_encounter (te same walki co w Etapach 5-7)
przejście: brama / wygrana / wyjście z areny -> wygaszenie (ticki) -> nowy region
gracz: PlayerActions.beam_held -> SwordBeam (raise, focus, lit) -> cel z regionu
       (brama następnego kolosa / Colossus.beam_weak_point)
```
Szczegóły: [ETAP_8.md](ETAP_8.md). Zasady:
- Jeden region naraz: symuluje się tylko jeden kolos. Region buduje własnego gracza, konia,
  kamerę i HUD. Między regionami przechodzi tylko `GameState` i to, czy gracz jechał konno.
- Promień nie jest znacznikiem: wynika wyłącznie z kierunku patrzenia, światła słońca
  (jeden promień co 6 ticków) i celu regionu. Bot całej gry szuka drogi tak samo.
- Zapis nigdy nie pozwala ominąć kolosa: liczy się tylko ciągły prefiks ustalonej kolejności.
- Wszystko w tickach fizyki, łącznie z wygaszeniem i przejściami, więc rozgrywka jest
  niezależna od FPS także między regionami.

## 3. Gracze i wejście

- Nie ma singletona gracza. Każdy `PlayerCharacter` jest w grupie `players`, a sandbox trzyma
  `players[]` i przekazuje referencje (kamera, HUD, źródło wejścia).
- Rozgrywka czyta wyłącznie `PlayerActions` (move, look, view_basis, grab, jump, focus).
  Źródła wejścia to `FlatInputSource` (klawiatura/mysz/pad), a w przyszłości VR, AI kompan
  i testy. Sieć będzie synchronizować akcje/intencje, nie przyciski.
- Kolejność w ticku: wejście (`process_priority -100`) → kolos (`process_physics_priority -10`)
  → koń (`-9`) → gracz → kamera (`_process`, interpolowana pozycja gracza).
- Włączona jest interpolacja fizyki (Godot 4.4), więc symulacja idzie w 60 Hz, a obraz jest płynny
  przy dowolnym FPS.

## 4. Kamera

Zasada: kamera nie walczy z graczem.
- yaw/pitch należą do gracza; kamera sama się nie obraca (wyjątek: trzymany fokus);
- asysta przesuwa tylko pivot i dystans:
  - dystans zależy od sytuacji (ziemia / blisko kolosa / na kolosie / wspinanie / fokus);
  - przy wspinaniu pivot wyprzedza gracza wzdłuż trasy;
- gwarancja „nigdy w kolosie”:
  - pivot wyznaczany jest castem z punktu pewnie wolnego (ręce odsunięte od powierzchni,
    potem ciało);
  - boom castowany jest z tego pivota, bo Godot ignoruje kolizje na starcie castu;
  - pozycja końcowa jest twardo sprawdzana;
- świat przybliża kamerę szybko, a zasłonięcie przez kolosa miękko i dopiero po 0,35 s;
- kąt boomu jest ograniczony osobno od kąta patrzenia, więc patrzenie w górę nie wbija
  kamery w ziemię; fokus celuje między graczem a kolosem.

## 5. Wydajność

- `Perf` (`src/core/perf.gd`) mierzy czas logiki (kolos/gracz/kamera) i liczbę zapytań
  fizyki per kategoria. Dane pokazuje HUD (F3), a `test_performance_budget` używa ich jako
  benchmarku regresji (4 scenariusze, próg wycieku obiektów).
- Stan po Etapie 2: 0,23–0,32 ms na klatkę headless. Wspinanie to 3 raycasty na tick,
  chwyt w powietrzu 2 zapytania sferą, kamera ok. 7 zapytań.
- Zapytania korzystają ze współdzielonych obiektów parametrów, a `find_grip` liczy najbliższy
  punkt analitycznie.
- Etap 4: Agro kosztuje ~180–230 µs na tick (sondy przeszkód ~75, planer kroków ~25, IK i poza
  ~60) i ~8 zapytań fizyki na tick. Osobne etykiety: `horse_controller`, `horse_probes`,
  `horse_steps`, `horse_ik`, `mount`, `camera`.
- Etap 5: Valus w walce ~270–470 µs/tick (mózg ~10, walka/ataki ~35–65, trafienia ~15–30,
  locomotion ~115–190, IK ~30–45; zakres zależy od obciążenia maszyny). Etykiety: `brain`,
  `boss_combat`, `boss_hits`, `boss_pose`, `vfx`.
- Etap 6: Quadratus w walce ~300 µs/tick (mózg ~10, walka ~50, trafienia ~15, locomotion
  czterech nóg ~120 w tym balans/przenoszenie ciężaru, IK czterech nóg ~40); strzały ~6 µs/tick
  przy kilku strzałach w locie (1 raycast na strzałę i tick). Etykiety: `loco_balance`,
  `arrows`, `bow`, `climb`, zapytania `arrow_rays`, `arrow_target_tests`, `bow_aim_rays`.
- Nie ma potrzeby przenosić czegokolwiek do Ziga.
