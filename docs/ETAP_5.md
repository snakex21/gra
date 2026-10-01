# Etap 5 — pierwszy kompletny boss: Sentinel

Pytanie etapu: **czy wszystkie dotychczasowe systemy składają się w dobrą walkę z kolosem?**
Odpowiedź: tak. Wspinanie, stamina, balans, upadki, kamera, Agro, procedural locomotion
z IK i utility AI razem dają pełną, przechodnią walkę.

- Bot testowy, który zna drogę i gra wyłącznie przez `PlayerActions`, pokonuje Sentinela
  w każdym z 50 przejść długiego testu (wyniki niżej).
- Cała walka przy renderze 30–240 FPS daje identyczny stan symulacji.
- Wszystkie 70 wcześniejszych testów przechodzi; razem 95/95.

## Pętla walki

```
wejście na arenę (DORMANT, uśpiony, głowa spuszczona)
  -> gracz bliżej niż 42 m: NOTICE (1,2 s, głowa i tułów do gracza) -> ENGAGED (1 s, ryk)
  -> COMBAT: stomp / sweep / obserwacja / podejście; gracz unika telegrafowanych ataków
  -> łydka od tyłu (futro) -> udo -> biodra -> plecy -> wciągnięcie na barki
  -> REST na barkach (stoisz bez chwytu, stamina wraca)
  -> grzywa na karku -> tył głowy -> futro na wierzchu głowy
  -> chwyt futra pod stopami, ładowanie miecza, cios w weak point
  -> reakcja: zachwianie (trzeba się utrzymać), potem shake albo zamknięcie weak pointu
  -> między shake'ami można stanąć na głowie i odpocząć
  -> 3 pełne ciosy (albo więcej słabszych) -> DEFEATED: klęknięcie, „COLOSSUS DEFEATED”
```

## Architektura

```
observe() -> SentinelBrain.decide()      proponuje intencję (utility)
          -> FairnessRules              osobna warstwa: blokuje, przycina czasy
          -> intencja -> ColossusAttack (TELEGRAPH -> ACTIVE -> RECOVERY)
          -> ruch -> LocomotionController (masa, kroki, IK) -> kości -> segmenty
          -> HitVolume (kapsuły na kościach kończyn) testowane po synchronizacji kości
gracz: PlayerActions -> PlayerSword (READY / CHARGE / STRIKE / RECOVERY) -> WeakPoint.try_hit
SentinelEncounter: śmierć -> pauza 2,5 s -> reset (gracz, HP, stamina, boss, weak point, Agro)
```

- **`Sentinel`** (`src/colossus/sentinel/`) dziedziczy po `GreyboxHumanoid`, z którego bierze
  rig, locomotion, IK i shake. Ma własną tablicę części:
  - grzywa z futra na karku (droga do głowy);
  - futro na wierzchu głowy (weak point);
  - pancerz z przodu ud;
  - plateau barków oznaczone jako `rest`.
  
  Kolos z Etapów 1–4 nie zmienił zachowania. Doszły tylko haki domyślnie nic nierobiące:
  `_parts`, `_adjust_movement`, `_pose_overrides`, `extra_pelvis_drop`, tagi powierzchni
  i noga sterowana skryptem w `LocomotionController`.
- **Intencje**: `observe_player`, `approach`, `reposition`, `stomp`, `arm_sweep`,
  `shake_player`, `protect_weakpoint`, `recover`, `search_player`.

  | Gdzie jest gracz | Co wybiera mózg |
  |---|---|
  | na ziemi przy stopie | stomp |
  | na ziemi przed bossem | sweep |
  | daleko | podejście |
  | za plecami | szukanie (obrót) |
  | stopa / łydka | ruch nogi (kroki) |
  | udo / biodra / plecy / ramię | umiarkowany shake po kilku spokojnych sekundach |
  | barki | słaby shake, bez pośpiechu |
  | kark | shake |
  | głowa | najmocniejszy shake albo zamknięcie weak pointu |
- **Brain nie może ominąć reguł** (`src/combat/fairness_rules.gd`, osobny obiekt):
  - minimalny telegraf 0,6 s;
  - recovery po ciężkim ataku ≥ 1,2 s;
  - cooldown 6 s na każdy atak;
  - przerwa ≥ 1,5 s między atakami;
  - maks. 2 te same ataki z rzędu w oknie 20 s;
  - brak ataku na gracza przewróconego lub spadającego (i przez 1,2 s po wstaniu);
  - shake: maks. 3 s (z 0,6 s telegrafu), cooldown ≥ 5 s, nie od razu po ciężkim ataku;
  - ochrona weak pointu: maks. 2,5 s, cooldown 6 s, budżet 5 s na 20 s, więc weak point jest
    otwarty przez większość czasu;
  - przestawianie się: maks. 8 s, potem cooldown, więc droga nie jest odcięta na stałe.
  
  Test ze „spamującym” mózgiem (zawsze stomp, zawsze shake) dowodzi, że reguły wygrywają.

### Ataki (TELEGRAPH → ACTIVE → RECOVERY)

| Atak | Telegraf | Aktywny | Recovery | Hitbox | Skutek |
|---|---|---|---|---|---|
| STOMP | 0,9 s: ciężar przechodzi na drugą nogę, stopa idzie 3,2 m w górę i przez pierwsze 60% telegrafu dryfuje za graczem (maks. 2 m/s), potem miejsce jest zablokowane | 0,3 s: zejście 0,18 s, potem fala uderzeniowa | 1,6 s | kapsuła na kości stopy (pod stopą); pierścień 6 m po uderzeniu | 60 HP, przewrócenie 2,2 s, odrzut; fala: 9–22 HP, odrzut, przewrócenie z bliska |
| ARM SWEEP | 1,1 s: zamach ręką do tyłu i w bok, skręt tułowia, przysiad (miednica −3,2 m, ukłon) | 0,6 s: ręka zamiata nisko łukiem przed bossem (zasięg ~7,5 m) | 1,2 s | kapsuły na przedramieniu i dłoni | 35 HP, odrzut w bok, przewrócenie |
| REPOSITION | — | chodzenie 8 m w bok (zmienia dostęp do nogi) | — | — | brak obrażeń |

- Stopa nigdy się nie teleportuje: noga w stompie jest „skryptowa”, planer kroków jej nie
  rusza i dostaje ją z powrotem postawioną dokładnie w miejscu uderzenia.
- Kolos nie rani gracza, który na nim wisi lub stoi. Klimber trzyma się przez wstrząsy.
- Po pokonaniu atak w toku dokończy ruch, ale bez obrażeń, a nowe nie startują.

### Weak point, miecz, reakcja

- **`WeakPoint`** jest dzieckiem segmentu głowy. Pozycję gameplayową bierze z transformacji
  kości z bieżącego ticku. Ma stan OPEN / PROTECTED / DESTROYED i 100 punktów życia.
- Przyjmuje tylko cios mieczem w fazie STRIKE w promieniu 1,1 m. Odrzuca z powodem:
  - `not_a_sword`;
  - `out_of_range`;
  - `protected`;
  - `destroyed`.
- **`PlayerSword`**: trzymanie przycisku ładuje cios do 1,2 s, puszczenie uderza (raz,
  w pierwszym ticku STRIKE). Obrażenia: dźgnięcie 12, pełny ładunek 40.
  - Działa stojąc lub w chwycie (cios przy dłoniach).
  - Podczas ładowania nie da się pełzać i chodzi się wolniej.
- **Reakcja** na trafienie: wyraźny błysk, dźwięk, iskry i zachwianie ciała przez 1,3 s.
  Obwiednia sin² i drganie startujące od zera, więc trzymający się gracz czuje ruch,
  ale nie ma skoku pozy. Zaraz potem mózg zwykle wybiera shake albo zamknięcie weak pointu
  (`player_near_weakpoint`), w granicach reguł.

### Stamina i REST_SURFACE

- Wspinanie kosztuje 8/s (wisi 3 + ruch 5), shake do +24/s. Pełny pasek wystarcza na łydkę
  → barki bez większych wstrząsów, ale nie na całą drogę do głowy.
- **REST_SURFACE** to płaskie plateau barków (kamień, tag `rest` widoczny w nakładce F3).
  Stoisz bez chwytu i stamina wraca 35/s (15 → 90 w 2,5 s). Futro na wierzchu głowy też jest
  chodliwe, więc między shake'ami można stanąć i złapać oddech.
- To wymusza planowanie. Bot rusza z barków na grzywę zaraz po shake'u, kiedy działa jego
  cooldown, a na głowie odpoczywa na stojąco, kiedy jest spokojnie.

### Agro na arenie

- Nogi kolosa są dla sond konia zwykłą przeszkodą (warstwa COLOSSUS). 3 przejazdy po 6 m/s
  prosto na chodzącego Sentinela: 0 kontaktów z ciałem.
- **Reakcja na zagrożenie**: kolos publikuje strefy (`get_danger_zones`) od decyzji o stompie
  i podczas sweepa.
  - Koń w strefie płoszy się: szybszy zryw i zwrot, ucieka.
  - Jeździec kierujący go w strefę dostaje odmowę: koń zatrzymuje się przed jej krawędzią.

### Kamera, śmierć, pokonanie

- Kamera z Etapu 2 bez zmian. W pełnej walce granej przez bota ani razu nie weszła w ciało
  kolosa. Q nadal kadruje bossa z graczem. Brak kamery filmowej.
- **Śmierć**: „YOU DIED”, 2,5 s pauzy, potem reset całej walki. Gracz wraca na start z pełnym
  HP i staminą, boss jest uśpiony, weak point pełny, Agro na swoim miejscu. F5 to szybki
  reset do testów.
- **Pokonanie**: boss przestaje wybierać agresywne intencje i zadawać obrażenia, po czym
  przez 6 s klęka (miednica −3 m, ukłon). Pojawia się „COLOSSUS DEFEATED”.
  - Gracz trzymający głowę jest kontrolowanie niesiony w dół (6 m, maks. 0,08 m/tick,
    kotwica bez dryfu) i po zakończeniu ruchu może zejść.
  - Puszczenie się z głowy wciąż oznacza upadek z ~12 m. Lepszy finał to temat na Etap 6.

### Audio i VFX (zastępcze, wyłączalne)

- **`Sfx`**: dźwięki syntetyzowane w kodzie, bez plików i bez cudzych nagrań. Krok, stomp,
  zamach, uderzenie, trafienie weak pointu, utrata chwytu, pokonanie.
- **`Fx`**: kilkanaście cząstek CPU, bez cieni, zwalniane po zakończeniu. Kurz pod krokami,
  większy pod stompem, iskry przy trafieniu.
- `Sfx.enabled` / `Fx.enabled` wyłączają je do benchmarków i testów.

### Debug (F3)

- **HUD**:
  - SENTINEL: stan encountera, intencja, atak i faza, czasy telegrafu / aktywnej fazy /
    recovery, postęp i stan weak pointu, cooldown shake'a, region gracza, cel, zablokowane
    intencje, wyniki mózgu;
  - PLAYER: HP, stamina, stan, balans, segment chwytu, powierzchnia, miecz;
  - AGRO: chód, prędkość, omijanie, reakcja na zagrożenie;
  - PERFORMANCE: koszt ticku per system, zapytania na tick.
- **Nakładka**:
  - hitboxy (czerwone = aktywne, pomarańczowe = telegraf);
  - zasięg ataku (pierścień fali, strefy zagrożenia);
  - weak point;
  - powierzchnie chwytu (brązowe) i odpoczynku (zielone);
  - droga wspinaczki (żółta).

## Wyniki testów (`tools/run_tests.sh`: 95/95 PASS, ~4 min)

| Test | Wynik |
|---|---|
| boss_enters_combat_when_player_enters_arena | uśpiony przy wejściu; po przekroczeniu 42 m NOTICE → ENGAGED → COMBAT w 2,2 s; zero ataków przed COMBAT |
| boss_attack_has_telegraph | stomp 0,9 s, sweep 1,1 s; reguły przycinają 0,05 s → 0,6 s i recovery 0,1 → 1,2 s |
| boss_attack_active_window_is_correct | okna 0,30 / 0,60 s co do ticku; 105 ticków aktywnych hitboxów, 0 poza oknem; 5 trafień, 0 poza oknem |
| boss_attack_has_recovery | recovery 1,6 / 1,2 s; następny zamach po ≥ 1,6 s |
| boss_attack_can_damage_player | stomp −60 HP i przewrócenie, sweep −35 HP |
| boss_cannot_spam_heavy_attack | mózg „tylko stomp”, gracz zawsze przy stopie, 60 s: 6 stompów, min. odstęp 8,9 s, maks. 2 w 20 s |
| boss_cannot_spam_shake | mózg „tylko shake”, 40 s: najdłuższy 3,02 s, najkrótsza przerwa 5,07 s, shake przez 38% czasu |
| climb_route_is_reachable | łydka → udo → miednica → plecy → barki → głowa, weak point w zasięgu po 35,6 s |
| weakpoint_moves_with_bone | boss przeszedł 10 m: błąd względem kości głowy 0,000000 m |
| weakpoint_rejects_invalid_hits | not_a_sword, out_of_range, protected, cios z ziemi: nothing_in_reach; HP bez zmian |
| weakpoint_accepts_valid_sword_hit | chwyt futra pod stopami na głowie, pełny cios: 40 obrażeń |
| weakpoint_damage_advances_progress | 0 → 0,12 (dźgnięcie) → 0,52 → 0,92 → 1,0; DESTROYED i DEFEATED |
| rest_surface_restores_stamina | barki (tag `rest`), bez chwytu: 15 → 90 w 2,5 s |
| boss_reacts_to_player_on_body | łydka: ruch nogi; plecy: shake; głowa: shake i zamknięcie weak pointu |
| player_can_fall_and_reenter_climb_route | wyczerpany spada z biodra, odpoczywa, łapie łydkę ponownie i wraca na 8 m |
| agro_avoids_colossus_legs | 3 przejazdy po 6 m/s prosto na chodzącego bossa: 0 kontaktów |
| agro_reacts_to_stomp_danger | koń bez jeźdźca ucieka (3,9 → 5,4 m w ~1 s); jeździec w strefę: odmowa, zatrzymanie 4,2 m przed krawędzią |
| player_death_resets_encounter | YOU DIED, pauza, reset: HP 100, stamina 100, spawn, boss DORMANT, weak point 100, Agro na miejscu |
| boss_can_be_defeated | 3 pełne ciosy: DEFEATED, „COLOSSUS DEFEATED” |
| boss_stops_attacking_after_defeat | pokonany w trakcie telegrafu stompa: 0 nowych ataków, 0 trafień, tylko IDLE, klęknięcie |
| grip_survives_defeat_sequence | 9 s klękania z chwytem na głowie: w dół 6 m, maks. 0,08 m/tick, kotwica 0,000003 m |
| scripted_driver_can_complete_boss | WIN w ~58 s; kamera 0 klatek w ciele kolosa |
| boss_simulation_independent_of_render_fps | cała walka przy 30/60/90/120/144/240 FPS: różnica stanu 0,00000000 |
| boss_cost_stays_within_budget | patrz niżej |
| all_existing_tests_still_pass | 70 wcześniejszych wpisów (Milestone 1, Etapy 2–4): 0 błędów |

## Długi test regresji (`tools/run_boss_soak.sh 50`)

50 kompletnych walk (różne seedy mózgu, start przesunięty losowo o ±6 m / ±3 m). Każda
grana przez bota od wejścia na arenę do „COLOSSUS DEFEATED”, bez powtórek i bez ukrywania
błędów:

| Wynik | Wartość |
|---|---|
| zwycięstwa | **50 / 50** |
| deadlocki (brak wyniku w 360 s) | **0** |
| nieosiągalny weak point (> 120 s walki bez trafienia) | 0 |
| zgubione chwyty (ruch > 0,5 m/tick podczas chwytu) | 0 |
| błędne resety (stan po resecie inny niż na starcie) | 0 |
| zakleszczenia AI (ta sama intencja > 25 s bez ataku) | 0 |
| zatrzymania bota (timeout fazy) | 0 |
| czas do zwycięstwa | min. 56,7 s, mediana 58,0 s, p75 105 s, maks. 232 s |
| przejścia bez śmierci | 36 / 50 |
| śmierci | 20 w 14 przejściach, wszystkie od upadku, głównie z głowy (~17 m) |
| upadki z trasy (zrzucony / wyczerpany) | śr. 1,9 na walkę |
| uniki telegrafowanych ataków | śr. 3,4 na walkę; trafienia bota przez bossa: 0 |

Przejścia z jedną lub dwiema śmierciami trwają ~105–155 s (reset i ponowne podejście).

Czego test długi nauczył (i co naprawiono po pierwszym przebiegu 46/50):
- 4 deadlocki: bot zaczynał tuż za stojącym koniem i biegł prosto w niego. Dostał
  obejście bokiem przy braku postępu.
- Obsługa timeoutu fazy w bocie przestała się zerować po zmianie w `_enter`.

Po poprawkach te same seedy wygrywają, a pełny przebieg daje 50/50.

## Koszt CPU (headless; bot wspina się, 25 s walki)

| System | µs / tick |
|---|---|
| Sentinel razem | ~270–280 |
| – mózg (obserwacja + decyzja, co 0,25 s) | ~10 |
| – system ataków + walka (encounter, reguły, stopa w stompie) | ~35 |
| – hit detection (kapsuły vs gracz) + kurz kroków | ~15 |
| – pozy ataków | ~7 |
| – locomotion | ~115–120 |
| – IK | ~28–30 |
| weak point | < 1 (sprawdzany tylko przy ciosie) |
| gracz (z wspinaniem i mieczem) | ~100 |
| Agro (stoi, sondy pomijane) | ~170 |
| kamera (na klatkę) | ~80 |
| VFX | ~1,5 (14 efektów w 25 s) |
| cały tick fizyki (monitor silnika, z serwerem fizyki) | 3,0–3,9 ms średnio; pojedyncze piki do 13 ms na tej współdzielonej maszynie (headless, w tym narzut testów) |

Zapytania fizyki na tick:

| Źródło | Zapytania / tick |
|---|---|
| wspinanie | ~1,1 |
| kamera | ~7,1 |
| koń stojący | 0 |
| trafienia bossa | analitycznie, 0 zapytań |
| miecz | 0 zapytań, ale wywołanie przy ciosie |

Nic nie trafiło do Ziga. Jedyna optymalizacja z profilu: stojący bez celu koń kosztował tyle
co boss, więc pomija teraz sondy.

## Znalezione i naprawione problemy

1. **Teleport po puszczeniu chwytu** (błąd z wcześniejszych etapów). `is_on_floor()`
   zachowywało starą wartość podczas wspinania, a stara kotwica „stania na segmencie”
   przenosiła gracza tam, gdzie ostatnio stał. Tu: z głowy z powrotem na barki.
2. **Skoki ciała przy przejściach przez krawędzie segmentów**: 1–2 m w jednym ticku przy
   obrocie normalnej. Dłonie zostają zakotwiczone dokładnie, a offset ciała dochodzi
   płynnie w układzie segmentu (~0,1 s). Test długi: 0 „glitchy”.
3. **Ręka sweepa szła do tyłu.** Kierunek ramienia liczony w układzie pochylonej klatki;
   teraz w układzie ciała. Bazowy kod nadpisywał też `pelvis_drop`, więc przysiad nie
   działał.
4. **Skok pozy głowy przy trafieniu**: drganie zaczynało się od losowej fazy z pełną
   amplitudą. Teraz obwiednia od zera.
5. **Bez szans na uniknięcie**: przewrócony po upadku gracz dostawał stomp. Nowa reguła:
   brak ataku na leżącego lub spadającego.
6. **Wyczerpanie na trasie**: shake na plecach i głowie od razu z pełną siłą. Strojenie:
   najpierw kilka spokojnych sekund, słabszy shake w dolnych regionach, oddzielny region
   karku.
7. **Kucnięcie na futrze na wierzchu**: chwyt na poziomej powierzchni stawiał ciało
   0,9 m obok dłoni, a po puszczeniu gracz spadał z małej głowy. Teraz kuca nad dłońmi,
   także wizualnie.
8. **Liczniki Perf kradzione przez HUD** (fałszywie niskie wyniki testów kosztu). Teraz
   każdy czytelnik ma własną migawkę.
9. **Deadlocki bota w teście długim**: bot biegł prosto w stojącego konia. Dostał obejście
   bokiem, a obsługa stalla zerowała się źle. Wszystkie 4 seedy wygrywają po poprawce.

## Znane ograniczenia

- Atak sweep sięga ~7,5 m, a gracz dalej przed bossem jest bezpieczny. To decyzja projektowa,
  zgodna z długością ramion.
- Koń stojący ~4 m od miejsca stompa nie zdąży wyjść z 6 m fali w ~1 s: ucieka i zyskuje
  ~1,5 m. Sam koń nie ma zdrowia. Jeździec dostaje falę tak samo jak pieszy i spada z konia.
- Bot ma jedną trasę (zna drogę) i nie używa Agro w walce.
- Po pokonaniu trzymający się gracz ląduje na klęczącym bossie około 12 m nad ziemią. Musi
  zejść sam, a puszczenie się z głowy to upadek SEVERE.
- Szkielet kolosa, proporcje i kolory to nadal greybox. Agent graficzny przygotowuje
  własnego Sentinela, a mapowanie na ten szkielet jest po jego stronie.

## Do ludzkiego playtestu

1. Czy telegrafy (0,9 s stomp, 1,1 s sweep, 0,6 s przed shake'iem) są czytelne bez nakładki?
2. Czy droga łydka → barki → grzywa → głowa jest zrozumiała bez nakładki (kolory futra
   i pancerza)?
3. Czy stamina „pasuje”: na barkach trzeba odpocząć, a na głowie trzeba czekać na spokojny
   moment?
4. Czy shake na głowie (do 3 s, potem ≥ 5 s spokoju) jest wymagający, ale uczciwy?
5. Czy przewrócenie po stompie (2,2 s) i fala są zbyt karzące?
6. Czy reakcja na trafienie (zachwianie) daje dobry feedback, a nie tylko utratę staminy?
7. Czy kamera na barkach i na głowie pokazuje dość (Q kadruje bossa)?
8. Agro: czy płoszenie się przy stompie jest czytelne i nie irytuje, gdy jeździec chce
   przejechać obok?
9. Śmierć → reset po 2,5 s: czy to dobry rytm testowania?

## Propozycja Etapu 6

1. **Drugi kolos o innej sylwetce** (czworonóg albo latający), na tej samej architekturze
   Brain → Intent → Rules → Attack, żeby sprawdzić, co jest naprawdę wspólne.
2. **Łuk z ziemi i z konia** (aiming bez przejmowania kamery, przygotowane w Etapie 4)
   i pierwsza zagadka „sprowokuj kolosa”, na przykład strzał w podeszwę, żeby uklęknął.
3. **Lepsze zakończenie walki**: kontrolowane zsunięcie z klęczącego kolosa i bezpieczne
   zejście.
4. **Integracja assetów agenta graficznego**: mapowanie Sentinela na szkielet gameplayowy
   z zachowaniem tagów fur/stone/armor/rest.
5. **Bot z kilkoma trasami i z Agro** w długim teście, do szukania deadlocków.
