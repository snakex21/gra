# Gra — remake w duchu Shadow of the Colossus

Open-source'owa reimplementacja/remake gry w duchu *Shadow of the Colossus*, która rozwija
elementy ograniczone w oryginale sprzętem PS2, czasem produkcji albo wycięte z gry.
Silnik: **Godot 4.4+** (GDScript, a Zig dopiero tam, gdzie profiler pokaże realną potrzebę).
Gra ma działać w pełni offline. Repozytorium nie zawiera żadnych chronionych assetów oryginału.

Nadrzędny kierunek: samotność, ogrom i tajemnicza Zakazana Kraina. Docelowo świat
zyskuje cykl dnia i nocy, pogodę, ekosystem oraz ukryte miejsca i zagadki; reaguje
na śmierć kolosów i odzyskiwanie mocy przez Dormina. Kooperacja, kompan AI i VR
mają zachować ten charakter. [Wizja i stan realizacji](docs/WIZJA_GRY.md).

## Stan: Etap 14 — broń, geografia i profile grafiki

- Milestone 1 (wspinanie po poruszającym się kolosie): [docs/MILESTONE_1.md](docs/MILESTONE_1.md)
- Etap 2 (równowaga na kolosie, upadki, kamera, przejścia): [docs/ETAP_2.md](docs/ETAP_2.md)
- Etap 3 (locomotion, planer kroków, IK, miednica, A/B z animacją, niezależność od FPS): [docs/ETAP_3.md](docs/ETAP_3.md)
- Etap 4 (Agro: chody, promień skrętu, kopyta bez poślizgu, wsiadanie, omijanie, AI, kamera): [docs/ETAP_4.md](docs/ETAP_4.md)
- Etap 5 (Valus: encounter, ataki z telegrafem, weak point, miecz, fairness, reset, bot, 50 walk): [docs/ETAP_5.md](docs/ETAP_5.md)
- Etap 6 (Quadratus: czworonóg, łuk i strzały, trafienie w kopyto, klęknięcie, dwa weak pointy, łuk z Agro, bezpieczne zejście z Valusa): [docs/ETAP_6.md](docs/ETAP_6.md)
- Etap 7 (Gaius: miecz jako droga, hełm do rozbicia; assety Saltward; pętla i zryw Quadratusa; widok łuku zza ramienia, odbicia strzał; soaki 3×100): [docs/ETAP_7.md](docs/ETAP_7.md)
- Etap 8 (dolina Ancient Valley ze świątynią i trzema bramami, promień miecza, pętla gry z zapisem, bot całej gry, Sentinel v2): [docs/ETAP_8.md](docs/ETAP_8.md)
- Etap 9 (Phaedra: płochliwy kolos z długą szyją, zwabienie do tunelu; menu i ustawienia; nagrywanie i deterministyczne powtórki; tańszy Agro w dolinie; tekstury Agro i Wędrowca): [docs/ETAP_9.md](docs/ETAP_9.md)
- Etap 10 (ciągły świat bez wygaszeń, wspólna baza czworonogów, piąty kolos Hydrus w jeziorze i pływanie, przewijanie powtórek, F9, sloty zapisu, zmiana klawiszy, głośność): [docs/ETAP_10.md](docs/ETAP_10.md)
- Etap 11 (szósty kolos Avion: ptak nad jeziorem z wieżami, chwyt skrzydła przy pikowaniu; areny budowane po starcie; nurkowanie i oddech; znaczniki, skoki i wycinki w powtórkach): [docs/ETAP_11.md](docs/ETAP_11.md)
- Etap 12 (jaskinia Hollowvault / Deeprelic i latarka miecza, planowany przelot Aviona, checkpointy świata, mniejsze kroki grafiki, fale i mgła pod wodą): [docs/ETAP_12.md](docs/ETAP_12.md)
- Etap 13 (Wędrowiec, Mono, Agro, Dormin i wszystkie pozostałe kolosy z Blendera, bezpieczny autozapis i wejścia do aren): [docs/ETAP_13.md](docs/ETAP_13.md)
- Etap 14 (modele broni, dłonie i naciąg łuku, poprawiony Wędrowiec, wspólne drogi Krainy, renderer Compatibility i profile kosztu grafiki): [docs/ETAP_14.md](docs/ETAP_14.md)
- Architektura: [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md)
- Stan po sesji 3 października 2026 i dalsze zadania: [docs/STAN_SESJI_2026-10-03.md](docs/STAN_SESJI_2026-10-03.md)

**Cała gra: `scenes/game.tscn`** (scena główna): menu (Kontynuuj / Nowa gra / Wczytaj / Próby kolosów / Ustawienia,
trzy sloty zapisu), start w świątyni, promień miecza (V / lewy spust) wskazuje drogę. Jeden ciągły
świat: wspólne drogi i rozgałęzienia prowadzą do regionów kolejnych kolosów, bez
ekranu ładowania; po wygranej powrót do świątyni i zapis. Esc / P / Start = pauza.
Bez menu: `-- --new-game` (albo `NEW_GAME=1`) lub `-- --continue`.

Autozapis co minutę, przy wyjściu i po zwycięstwach pozostaje w `data/`.
„Kontynuuj” wznawia ostatni bezpieczny checkpoint świata, także na Agro.
Podczas wspinaczki zachowany jest wcześniejszy bezpieczny punkt; późniejsze
zwycięstwo ma pierwszeństwo nad starszym checkpointem. Szczegóły w [Etapie 13](docs/ETAP_13.md).

Każda gra jest nagrywana (`data/replays/last.replay`, akcje gracza tick po ticku i checkpoint co 10 s), F9 zapisuje
zgłoszenie błędu (nagranie + podsumowanie). Odtworzenie tick w tick z przewijaniem:
`python tools/run_local.py godot -- --replay=res://data/replays/last.replay [--seek=<s>]` (K pauza, J/L ±10 s, [ ] prędkość,
`,` / `.` poprzedni / następny znacznik — śmierć, trafienie, upadek, pokonanie, zgłoszenie —, C wycinek
do zgłoszenia, F7 kamera).

**Próby kolosów** w menu uruchamiają gotowe prototypy bez przechodzenia całej kampanii.
Grywalna lista ma 21 starć, z równoczesną parą Celosia + Cenobia i finałem z Dorminem,
po którym Wędrowiec pozostaje żywy. Mechaniki nowych prób opisuje [Etap 12](docs/ETAP_12.md).
Kolejność i dostępność określa `src/game/boss_roster.gd`; każda próba ma scenę
`scenes/<nazwa>_arena.tscn`. Celosia i Cenobia tworzą jedno równoczesne starcie.
Jaskinia z testowym humanoidem pozostaje osobną próbą `scenes/cave_arena.tscn`;
Devil jest odrębnym strażnikiem jaskini w kampanii. Esc / Start wraca do listy prób,
F5 resetuje walkę, Tab przełącza miecz / łuk. Stare zwycięstwa zachowują się przy
migracji zapisu; starsze nagrania korzystają ze swojego wcześniejszego układu świata.
Areny mają warstwę assetów (paczka Saltward, CC0); `NO_ART=1` wyłącza ich oprawę.

Nowe mechaniki i modele są prototypami. To nie jest ukończone odtworzenie 1:1.
Wycięte kolosy mają własne interpretacje projektu. Fundament wielu uczestników
zachowuje walkę po śmierci lub odejściu kompana; pełny wybór co-op / sieć / VR jest
jeszcze do wdrożenia.

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

Windows: **`Uruchom-gre.bat`**, a do bezpośredniej próby jaskini **`Uruchom-jaskinie.bat`**.
Lokalny Godot jest w `tools/runtime`; Python jest potrzebny tylko do tego launchera.
Domyślny renderer to OpenGL Compatibility. Ustawienia → Jakość grafiki oferują
profil niski dla starszych kart, zrównoważony i wysoki. Minimalne wymagania sprzętowe
czekają na pomiary na starszym sprzęcie; sama obsługa OpenGL 3.3 nie gwarantuje FPS.
Po świeżym klonowaniu uruchom `python tools/run_local.py install-godot`, żeby pobrać
Godota do lokalnego folderu narzędzi. Cache, runtime i zapisy gracza są pomijane przez Git.
Zapisy, ustawienia i powtórki są w `data/`, cache projektu w `.godot/`, dane narzędzi
w `tools/runtime/`. Launcher kieruje również wewnętrzne dane silnika do tego folderu.
Przeniesienie całego folderu przenosi te dane. Brak prawa zapisu nie powoduje przejścia
do profilu użytkownika. Uruchamiaj przez launcher, żeby zachować również przenośne cache silnika.

```bash
python tools/run_local.py godot
python tools/run_local.py godot --editor
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
| Łuk: trzymaj = naciąganie (celownik na środku), puść = strzał | LPM / F | X |
| Zmiana broni: miecz / łuk | Tab / R | D-pad prawo |
| Unieś miecz do słońca (promień prowadzi do kolosa / słabego punktu) | V | lewy spust |
| Reset walki z bossem | F5 | — |
| Pauza / menu | Esc / P | Start |
| Zgłoszenie błędu (nagranie + opis) | F9 | — |
| Pływanie | jak chód (w głębokiej wodzie) | — |
| Nurkowanie (trzymaj w wodzie; oddech 14 s) | Ctrl / Z | B |

## Testy

Etap 14 (broń, profile grafiki, importy tekstur i nowy układ świata):

```bash
python tools/run_local.py godot --fixed-fps 60 tests/weapon_art.tscn
python tools/run_local.py godot --fixed-fps 60 tests/graphics_quality.tscn
python tools/run_local.py godot --fixed-fps 60 tests/texture_budgets.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/main_layout.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/forbidden_lands.tscn
```

Etap 13 na Windows (sprawdzony lokalnie w Godot 4.6.3):

```bash
python tools/run_local.py godot --headless --fixed-fps 60 tests/auto_save.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/art_integration_v3.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/colossi_v3.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/temple_characters_v3.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/paired_arrival.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/test_runner.tscn
```

Etap 12 na Windows:

```bash
python tools/run_local.py godot --headless --fixed-fps 60 tests/stage12.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/campaign_expansion.tscn
python tools/run_local.py godot --headless --fixed-fps 60 tests/checkpoint_climb.tscn
python tools/run_local.py godot --rendering-method forward_plus --resolution 1280x720 --fixed-fps 60 tests/capture_stage12.tscn
```

```bash
tools/run_tests.sh                 # 197 testów + A/B + porównanie z zamrożonymi wzorcami, headless, ~15 min
tools/run_tests.sh --save-baseline # zamraża nowy wzorzec regresji Etapu 2/3 (tylko świadomie)
tools/run_tests.sh --save-horse-baseline  # zamraża wzorzec metryk Agro (tylko świadomie)
tools/run_tests.sh --only=horse    # wybrane testy
tools/capture_screenshots.sh       # prawdziwa scena + autopilot -> tests/output/*.png
tools/capture_screenshots.sh agro  # scena Agro + skryptowany jeździec -> tests/output/agro_*.png
tools/capture_screenshots.sh boss  # walka z Valusem grana przez bota -> tests/output/boss_*.png
tools/capture_screenshots.sh quadratus  # walka z Quadratusem (bot z Agro) -> tests/output/quadratus_*.png
tools/run_boss_soak.sh 50                # długi test: 50 pełnych walk z Valusem (różne seedy)
tools/run_boss_soak.sh 50 1 quadratus    # 50 walk z Quadratusem (na zmianę pieszo / z Agro)
tools/run_boss_soak.sh 50 1 gaius        # 50 walk z Gaiusem
tools/run_boss_soak.sh 50 1 phaedra      # 50 walk z Phaedrą
tools/run_boss_soak.sh 50 1 hydrus       # 50 walk z Hydrusem
tools/run_game_soak.sh 20                # 20 całych kampanii: świątynia -> promień -> jazda -> wszystkie starcia
tools/capture_screenshots.sh gaius  # walka z Gaiusem grana przez bota -> tests/output/gaius_*.png
tools/capture_screenshots.sh art    # statyczne widoki aren z assetami -> tests/output/art_*.png
tools/capture_screenshots.sh game   # dolina, promień, jazda, brama -> tests/output/game_*.png
tools/capture_screenshots.sh phaedra     # walka z Phaedrą (bot w tunelu) -> tests/output/phaedra_*.png
tools/capture_screenshots.sh characters  # Agro i Wędrowiec z teksturami -> tests/output/characters_*.png
tools/capture_screenshots.sh menu        # menu tytułowe, pauza, ustawienia -> tests/output/menu_*.png
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
src/game/       GameWorld (ciągły świat, budzenie kolosów), GameState (postęp, sloty), Settings, ReplayViewer
src/input/      PlayerActions (abstrakcyjne akcje), FlatInputSource, ActionReplay (nagrywanie / powtórki), domyślne bindy
src/player/     PlayerCharacter (lokomocja + wspinanie + stanie na kolosie), PlayerRiding, Stamina, Balance, FallImpact, PlayerVisual
src/climb/      ClimbPatch (chwytalny kształt), SurfaceAnchor (punkt na ruchomym ciele), ClimbQuery
src/colossus/   Colossus (baza), BodySegment (collider na kości), brain/ (Brain, Intent, Observation, UtilityBrain)
src/colossus/greybox/  GreyboxHumanoid, GreyboxQuadruped — rigi sterowane danymi, mapowanie locomotion na kości (IK)
src/locomotion/ LocomotionController (masa, planer kroków, miednica), LegState, TwoBoneIK, StepMath, debug draw
src/horse/      Horse, HorseController, QuadrupedGait, HorseInputIntent, ScriptedHorseDriver, debug draw
src/colossus/valus/  Valus (pierwszy boss), ValusBrain
src/colossus/quadratus/  Quadratus (drugi boss, czworonóg), QuadratusBrain
src/colossus/gaius/  Gaius (trzeci boss, miecz), GaiusBrain; wspólna baza HumanoidBoss w greybox/
src/colossus/phaedra/  Phaedra (czwarty boss, długa szyja, zaglądanie do tunelu), PhaedraBrain; wspólna baza QuadrupedBoss w greybox/
src/colossus/hydrus/   Hydrus (piąty boss, wąż w jeziorze: ślad głowy, taran, nurkowanie), HydrusBrain
src/combat/     ColossusAttack, HitVolume, WeakPoint, FairnessRules, LimbStomp, PlayerSword, PlayerBow,
                ArrowSystem, ArrowTarget, ArmorPlate, SwordBeam, BossEncounter, ValusBot, QuadratusBot, GaiusBot, PhaedraBot, HydrusBot, GameBot, debug draw
src/fx/         Sfx (syntezowane dźwięki zastępcze), Fx (lekki kurz / błysk), ProcTextures (tekstury Agro i Wędrowca generowane w kodzie)
src/world/      TerrainKit, AgroArena, ValusArena, QuadratusArena, GaiusArena, PhaedraArena, HydrusArena — teren; WorldMap (układ świata,
                korytarze, horyzont), WaterBody (woda); Valley (dolina);
                ArenaArt — warstwa wizualna z assetów (bez wpływu na gameplay)
src/camera/     PlayerCamera
src/ui/         PlayerHud, GameMenu (tytuł, pauza, ustawienia)
scenes/         game (cała gra), sandbox, agro_test, valus_arena, quadratus_arena, gaius_arena, phaedra_arena, hydrus_arena
models/ textures/ materials/ environment/ art/  assety (CC0) od agenta graficznego: Saltward, Ancient Valley, Sentinel v2, Stonewater, Saltwind, Mirewood
tests/          testy headless + wizualny smoke test
docs/           dokumentacja projektu
```

## Licencja

Kod i własne assety: do ustalenia przez właściciela repozytorium (sugerowana MIT dla kodu).
