# Architektura (stan po Milestone 1)

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
- Kontroler zmienia parametry ciągle i powoli (przyspieszenie, rampa wstrząsu, wygładzone
  spojrzenie), więc kolos nie przeskakuje między stanami.
- Nowy kolos to podklasa `Colossus`, która dostarcza rig (`_build_body`), kontroler i własne
  reguły. `GreyboxHumanoid` definiuje rig tabelami `BONES`/`PARTS`.

## 3. Gracze i wejście

- Nie ma singletona gracza. Każdy `PlayerCharacter` jest w grupie `players`, a sandbox trzyma
  `players[]` i przekazuje referencje (kamera, HUD, źródło wejścia).
- Rozgrywka czyta wyłącznie `PlayerActions` (move, look, view_basis, grab, jump, focus).
  Źródła wejścia to `FlatInputSource` (klawiatura/mysz/pad), a w przyszłości VR, AI kompan
  i testy. Sieć będzie synchronizować akcje/intencje, nie przyciski.
- Kolejność w ticku: wejście (`process_priority -100`) → kolos (`process_physics_priority -10`)
  → gracz → kamera (`_process`, interpolowana pozycja gracza).
- Włączona jest interpolacja fizyki (Godot 4.4), więc symulacja idzie w 60 Hz, a obraz jest płynny
  przy dowolnym FPS.

## 4. Kamera

Zasada: kamera nie walczy z graczem.
- yaw/pitch należą do gracza, bez automatycznego centrowania;
- przeszkody świata przyciągają kamerę szybko, a oddalanie jest wolne;
- kończyny kolosa przyciągają kamerę tylko wtedy, gdy znalazłaby się *wewnątrz* nich, więc
  przelatujące ramię nie powoduje pompowania dystansu;
- przy wstrząsie pivot jest wygładzany (sztywność zależna od `shake_level`), żeby obraz nie drgał;
- asysta tylko na żądanie: przytrzymanie „focus” kadruje kolosa.

## 5. Wydajność

Pomiar w teście `test_performance_budget`: kolos + wspinający się gracz + fizyka to ok. 0,25 ms
na klatkę (headless). Wspinanie kosztuje kilka raycastów na tick. Budżet jest więc bardzo
daleko od problemu i na razie nie ma potrzeby przenosić czegokolwiek do Zig.
