# Etap 9 — Phaedra, menu, powtórki, tańszy Agro, tekstury postaci

Zakres (wybrany po Etapie 8):

1. **Phaedra**, czwarty kolos: płochliwy czworonóg z długą szyją. Trzeba go zwabić do
   tunelu i wejść mu na kark, gdy wsadza tam głowę. Arena w bagnach Mirewood Fen, czwarta
   brama w dolinie.
2. **Menu**: Kontynuuj, Nowa gra, Pauza, Ustawienia.
3. **Koszt Agro w dolinie**: z ~400 do ~200 µs/tick.
4. **Nagrywanie i deterministyczne odtwarzanie** rozgrywki.
5. Testy, soak 100 walk z Phaedrą, soak całej gry z czterema kolosami, zrzuty.

Przy okazji: **tekstury Agro i Wędrowca** generowane w kodzie.
Ciągły świat (bez wygaszeń między doliną i arenami) przechodzi do Etapu 10.

## 1. Phaedra (`src/colossus/phaedra/`, `src/world/phaedra_arena.gd`)

Czworonóg o wysokości ~11 m: kamienne ciało, długa szyja z trzech kości i głowa. Futro
jest tylko na wierzchu: czapa na głowie, grzywa wzdłuż szyi, kłąb i grzbiet.

**Charakter**: płochliwy i ciekawski.

- Na otwartym terenie trzyma dystans i cofa się przed każdym, kto podejdzie bliżej niż
  ~16 m. Z daleka podchodzi powoli, ale nie bliżej niż ~22 m.
- Przyparty do muru (kopyto blisko gracza) tupie.
- Nie potrafi się powstrzymać, kiedy ktoś się schowa. Gdy gracz jest w tunelu, Phaedra
  podchodzi do wylotu, opuszcza szyję i wsadza głowę do środka.

**Pętla walki**:

```
gracz w tunelu -> PEEK: APPROACH (podejście do wylotu, obrót) -> LOWER (1,6 s)
               -> HOLD (do 9 s, głowa w tunelu) -> RAISE (1,8 s) -> przerwa 5 s
chwyt czapy futra na głowie -> spłoszona podnosi głowę -> szyja staje się zboczem do grzbietu
wspinaczka po grzywie -> weak point w połowie szyi -> weak point na kłębie -> pokonana
```

- **Szyja**: łańcuch trzech kości i głowy. Opuszczanie głowy do wylotu to małe IK
  w płaszczyźnie ciała (CCD na trzech stawach) plus obrót szyi w bok. Wszystko jest
  mieszane wagą zaglądania. Głowa celuje 1,3 m w głąb tunelu, 1,35 m nad ziemią, więc
  czapa futra jest na wysokości ~2,4 m, w zasięgu skoku.
- **Fairness**: nie zagląda, gdy ktoś jest na niej. Podczas zaglądania nie atakuje
  i nie potrząsa. Po chwycie głowy daje 6 s spokoju, zanim zacznie potrząsać szyją,
  a potrząsanie jest słabsze niż u Quadratusa (0,5).
- **Kod**: `Phaedra extends Quadratus` i zmienia tylko hooki (`_make_brain`,
  `_weak_point_specs`, `_target_legs`, `_attack_cooldowns`, `_boss_label`,
  `_adjust_movement`, `_pose_overrides`, `_rules_block`). Do Quadratusa dodałem te hooki
  zamiast kopiować kod.
- **Arena**: zatopiona niecka w bagnach. Ma trzy zrujnowane tunele (5 m szerokości,
  3,2 m wysokości, 14 m długości), w których gracz się mieści, a Phaedra nie.
  Warstwę wizualną daje paczka Mirewood (`ArenaArt.dress_fen`): mury z mchem,
  zwisający mech, rośliny, drzewa, kłody, kapliczka. Kolizje i AI są greyboxowe; test
  sprawdza, że grafika nie zmienia żadnej kolizji w promieniu 75 m.
- **Dolina**: czwarta brama na wschodzie (128, −100), pod górę zbocza. Promień miecza
  prowadzi do niej po pokonaniu Gaiusa.
- **Bot** (`PhaedraBot`): chowa się w najbliższym tunelu, czeka 1,7 m od wylotu, chwyta
  czapę, gdy głowa jest opuszczona, wspina się po grzywie i uderza. Puszcza się tylko
  wtedy, gdy stoi na grzbiecie z gruntem pod stopami. Spada, gdy straci chwyt.
- **Scena**: `scenes/phaedra_arena.tscn` (jak areny pozostałych kolosów; F5 reset).

## 2. Menu i ustawienia (`src/ui/game_menu.gd`, `src/game/settings.gd`)

- **Ekran tytułowy**: Kontynuuj (tylko gdy jest zapis), Nowa gra, Ustawienia, Wyjście.
- **Pauza** (Esc / P / Start): Wznów, Ustawienia, Wyjdź do menu. Pauza to
  `SceneTree.paused`, więc symulacja stoi, a menu działa (`PROCESS_MODE_ALWAYS`).
  Klawiatura, mysz i pad (fokus przez wbudowane `ui_*`).
- **Ustawienia** w `user://settings.json`, osobno od zapisu gry:
  - czułość myszy,
  - odwrócenie osi Y,
  - sterowanie Agro względem konia (zamiast kamery),
  - podpowiedzi sterowania,
  - tekst diagnostyczny.

  Złe wartości z pliku są przycinane. Ustawienia trafiają do źródła wejścia, jeźdźca
  i HUD-u; rozgrywka nigdy ich nie czyta.
- HUD (podpowiedzi, baner) chowa się pod otwartym menu.
- Bez menu: `-- --new-game` / `NEW_GAME=1` albo `-- --continue`.
- Zrzuty: `tools/capture_screenshots.sh menu` → `tests/output/menu_*.png`.

## 3. Agro w dolinie (`src/horse/`)

Sondy przeszkód Agro (wachlarz castów przed klatką piersiową) trafiały w mapę wysokości
doliny na każdym zboczu, więc koń rzucał więcej i dłuższych castów niż na płaskim.

- **Zmiana**: mapa wysokości jest w grupie `walkable_terrain`. Koń co 30 ticków
  odświeża listę jej RID-ów, a casty przeszkód je pomijają. Mapa to otwarty teren:
  skały, świątynia i ściany mają własne kolizje, które sondy dalej widzą.
- **Bez zmian**: spadki i urwiska wykrywa osobna sonda w dół, która nadal widzi mapę
  wysokości. Zbocza, po których da się jechać, nigdy nie były przeszkodą.
- **Wynik**: Agro w dolinie **398 → 234 µs/tick** (sondy 197 → 71 µs), czyli prawie tyle
  co na płaskim torze (216 µs). Cały tick doliny 0,62 ms. Jazda doliny przy 30–240 FPS
  nadal bitowo identyczna.

## 4. Nagrywanie i powtórki (`src/input/action_replay.gd`)

- **Co jest nagrywane**: tylko `PlayerActions` (ruch, kierunek patrzenia, chwyt, fokus,
  atak, promień, celowanie, skok, interakcja, przywołanie, zmiana broni) oraz tryb
  sterowania Agro. Reszta wynika z determinizmu symulacji.
- **Kiedy**: dokładnie w chwili, gdy gracz czyta akcje. `PlayerCharacter.action_hook`
  jest wywoływany na początku jego ticku, już po źródle wejścia albo bocie.
- **Klucz**: `[który gracz z kolei, tick tego gracza]`. GameWorld buduje nowego gracza
  w każdym regionie, a klucz zgadza się bez względu na to, jak wystartował świat dookoła.
- **Zapis**: tylko ticki, w których coś się zmieniło, plus jednotickowe wciśnięcia.
  Plik binarny (dokładne floaty), kompresja zstd. Nagłówek opisuje start (postęp gry,
  seedy).
- **W grze**: każda gra jest nagrywana do `user://replays/last.replay`, zapis co 60 s
  i przy wyjściu. Odtworzenie: `-- --replay=<plik>`. Gra startuje wtedy z postępu
  z nagłówka, bez zapisu i bez wejścia.
- **Pułapka znaleziona przy teście**: dwa światy zbudowane w różnych fazach klatki
  fizyki (w sygnale `physics_frame` i poza nim) różnią się o jeden tick próbkowania.
  Symulacja była identyczna, różnił się tylko moment odczytu. Test buduje więc oba
  światy w tej samej fazie, tak samo jak robi to gra.

## 5. Tekstury Agro i Wędrowca (`src/fx/proc_textures.gd`)

Własne tekstury generowane w kodzie: szum (FastNoiseLite) ze stałymi seedami i normal
mapa liczona z jasności. Bez plików graficznych i bez niczego z oryginału. Mapowanie
triplanarne, bo części greyboxu nie mają UV.

| Materiał | Gdzie |
|---|---|
| sierść (ciemny gniady, pasma wzdłuż ciała) | ciało Agro |
| grzywa (prawie czarne pasma) | grzywa, ogon, dolne części nóg |
| róg kopyta (słoje) | kopyta |
| skóra z przetarciami i szwem | siodło, pas |
| tkana derka w pasy | derka pod siodłem |
| len (splot płócienny) | tunika Wędrowca |
| filc wełniany z przetarciami | peleryna |
| skóra, włosy | twarz, dłonie, włosy |

W trybie headless (testy, soaki) zostają zwykłe kolory. Test sprawdza, że tekstury są
deterministyczne. Przy okazji poprawiona peleryna: przebijała ją kapsuła ciała (jasna
plama na plecach), teraz jest odsunięta.

## Wyniki

### Testy

Pełny przebieg `tools/run_tests.sh`: **166/166 PASS** (153 wcześniejszych + 13 nowych).

| Test | Wynik |
|---|---|
| `phaedra_peeks_into_the_tunnel` | gracz w tunelu → podejście, głowa w wylocie (błąd celu 0,00 m), czapa futra na 2,42 m |
| `phaedra_grabbed_head_lifts_the_climber` | chwyt czapy → głowa w górę, gracz 0,9 → 11,9 m, 0 potrząśnięć przez 6 s |
| `phaedra_keeps_away_in_the_open` | 4 wycofania przed graczem na otwartym terenie |
| `phaedra_no_peek_with_someone_on_it` | z graczem na ciele nie zagląda |
| `phaedra_can_be_defeated` | bot wygrywa w 112,5 s (2 zajrzenia, 2 chwyty głowy, 1 upadek); weak pointy w kolejności szyja → kłąb |
| `phaedra_simulation_independent_of_render_fps` | walka botem przy 30/60/90/144/240 FPS: wygrana w ticku 3493, różnica 0,00000000 |
| `phaedra_cost_stays_within_budget` | kolos 309 µs/tick (mózg 8, walka 32, poza z IK szyi 20, locomotion 136, IK 38); gracz 92 |
| `four_colossi_in_order_with_fourth_gate` | Phaedra czwarta w kolejności; zapis z trzema kolosami (także sprzed Etapu 9) prowadzi do niej; otwarta tylko wschodnia brama, promień do niej prowadzi |
| `fen_art_does_not_change_phaedra_arena_collision` | 44/44 kształty kolizji bez zmian, 78 rekwizytów |
| `procedural_textures_are_deterministic` | dwa wygenerowania identyczne |
| `replay_reproduces_a_fight` | 45 s walki z Valusem (bot): 1491 zmienionych ticków z 2700, plik 27,8 kB; powtórka bez bota bitowo identyczna |
| `settings_and_pause` | zapis/odczyt ustawień, przycinanie złych wartości; pauza 0,3 s: gracz przesunął się o 0,0000 m |
| `all_etap8_and_earlier_tests_still_pass` | 153 wcześniejszych, 0 porażek |

### Soak

- **Phaedra** (`tools/run_boss_soak.sh 100 1 phaedra`, w dwóch procesach po 50):
  **100/100 wygranych**, 0 zakleszczeń, 0 widocznych skoków ciała, 0 złych resetów.
  - Czas do wygranej: min 57,7 / mediana 72,5 / p90 162,9 / max 252,8 s.
  - 81 walk bez śmierci. 19 śmierci, wszystkie to upadki z uniesionej szyi (~30 m/s,
    czyli bot puścił się wysoko na szyi). 39 upadków ogółem.
  - Jedno chwilowe zatrzymanie bota przy wspinaczce (run 94), walka i tak wygrana.
- **Cała gra z czterema kolosami** (`tools/run_game_soak.sh`, 2 × 10): **20/20 gier
  ukończonych**, 0 śmierci, 0 zatrzymań.
  - Od świątyni do końca: min 429,3 / mediana 433,6 / max 525,2 s.
  - W tym dolina 130 s (jazda 93 s), 13 namierzeń promieniem na grę, 0 objazdów.
  - Walki: Valus 47 s, Quadratus 85–89 s, Gaius 49–141 s, Phaedra 58 s.
  - Gry różnią się mało: seed przesuwa tylko pierwszy kierunek szukania drogi i mózgi
    kolosów, a bot gra je bardzo podobnie. Różnorodność walk sprawdzają soaki bossów.

Porównanie z zamrożonymi wzorcami flaguje 7 metryk czasu z sandboxa Etapu 2 (koszt
kolosa w sandboxie ~130–150 µs wobec ~45–80 µs we wzorcu). To samo daje commit sprzed
Etapu 9 uruchomiony zaraz obok, więc to nie zmiana z tego etapu, tylko stary wzorzec
mierzony na innej maszynie. Do odświeżenia świadomie (`--save-baseline`) po sprawdzeniu
na docelowym sprzęcie.

### Wydajność

- **Phaedra**: ~310 µs/tick, tyle co Quadratus. IK szyi to ~20 µs w pozie.
- **Agro w dolinie**: 234 µs/tick (było 398).
- **Powtórki**: ~28 kB na 45 s walki, czyli ~2,2 MB na godzinę. Koszt nagrywania jest
  pomijalny (jedno porównanie tablicy na tick).
- **Testy**: runner przy czekaniu na procesy FPS kręcił klatkę za klatką i przy kilku
  testach FPS z rzędu wyczerpywał `--quit-after`. Kończył się wtedy po cichu, bez raportu.
  Teraz między sprawdzeniami czeka 20 ms.

## Ograniczenia

- **Phaedra jako podklasa Quadratusa**: działa przez hooki, ale nazwa bazy jest myląca.
  Do wydzielenia `QuadrupedBoss`, tak jak `HumanoidBoss` w Etapie 7.
- **Tunele**: gracz chowa się w nich bez żadnej mechaniki ukrycia. Phaedra „wie”, że gracz
  jest w tunelu (geometria), a nie że go zgubiła z oczu.
- **Trawa i rośliny z paczki Mirewood** mogą wystawać w tunelach (tylko wizualnie).
- **Ciągły świat**: dalej regiony z wygaszeniem → Etap 10.
- **Powtórki** zależą od tej samej wersji gry (każda zmiana rozgrywki unieważnia stare
  pliki). Nie ma jeszcze przewijania ani podglądu z kamery swobodnej.
- **Menu** bez slotów zapisu i bez przemapowania klawiszy.
- **Soak całej gry** prawie się nie różnicuje między seedami (patrz wyniki); do
  rozważenia losowanie startowej pozycji Agro i dłuższe błądzenie bota.

## Lista do playtestu

- Czy da się samemu wpaść na pomysł z tunelem? Czy Phaedra wystarczająco „szuka” gracza
  wzrokiem, zanim podejdzie do wylotu?
- Czy chwyt czapy z ziemi jest czytelny (wysokość ~2,4 m, skok)?
- Wspinaczka po szyi, gdy Phaedra ją unosi: czy grzywa jest dość szeroka?
- Menu na padzie: fokus i powrót.
- Tekstury Agro i Wędrowca z bliska i w ruchu (pasma sierści, peleryna).

## Propozycja Etapu 10

1. **Ciągły świat**: areny we własnych układach współrzędnych wewnątrz doliny,
   doczytywanie w tle, wjazd do areny bez wygaszenia.
   - Symuluje się tylko kolos najbliższy graczowi.
   - Test: przejazd z doliny do areny bez skoku czasu ticku i z tym samym stanem przy
     30–240 FPS.
2. **`QuadrupedBoss`**: wydzielenie wspólnej bazy z Quadratusa (jak `HumanoidBoss`),
   Phaedra i Quadratus jako równorzędne podklasy.
3. **Piąty kolos** do ustalenia: latający albo pływający, bo oba wymagają nowego typu
   lokomocji i nowej mechaniki wejścia na kolosa.
4. **Powtórki dla playtestu**: przewijanie, kamera swobodna, zapis powtórki przy
   śmierci i przy zgłoszeniu błędu (jeden klawisz).
5. **Menu**: sloty zapisu, przemapowanie klawiszy i padów, głośność.
6. Soaki: 100 całych gier z większym zróżnicowaniem (pozycja startowa Agro, błądzenie
   bota) i 100 walk z każdym kolosem po zmianie bazy czworonogów.
