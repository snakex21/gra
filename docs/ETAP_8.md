# Etap 8 — dolina, promień miecza, cała gra od świątyni do końca

Zakres (wybrany po Etapie 7):

1. **Dolina** zamiast osobnych scen: świątynia na start, trzy bramy do aren, jazda na Agro.
2. **Promień miecza**: jedyny przewodnik po świecie, bez znacznika na mapie, jak w oryginale.
3. **Pętla gry**: kolejność kolosów, powrót do świątyni po wygranej, zapis, wyjście z areny.
4. **Bot całej gry** i soak całych rozgrywek.
5. **Sentinel v2** (nowy model od agenta graficznego) na Valusie.
6. Ograniczenia Etapu 7: skok ciała przy owijaniu krawędzi, czytelność odbić strzał
   i pęknięć hełmu.

Przy okazji domknięcia Etapu 7 soaki znalazły trzy prawdziwe błędy (opisane
w [ETAP_7.md](ETAP_7.md)): Gaius mógł potrząsać głową prawie bez przerwy, gracz mógł
wsiąść na Agro leżąc (łuk był potem zablokowany do końca walki), a bot Quadratusa
krążył w kółko na koniu.

## 1. Dolina (`src/world/valley.gd`)

Teren to paczka **Ancient Valley** od agenta graficznego (CC0): 360 × 360 m, świątynia,
jezioro, kanion, łuk skalny. W arenach grafika jest tylko skórką, a tu jej mapa wysokości
i kolizje low-poly **są** podłożem rozgrywki. Dolina dokłada to, czego potrzebuje gra:

| Brama | Gdzie | Droga ze świątyni |
|---|---|---|
| Valus | południe (0, −160) | przez otwartą równinę, ~190 m |
| Quadratus | północ (20, 160) | obok jeziora, ~150 m |
| Gaius | zachód, kanion (−96, 150) | w dół do kanionu, pod łukiem skalnym, ~150 m |

- **Otwarta jest tylko brama do następnego kolosa**, pozostałe zamyka ściana mgły
  z kolizją.
- **Krawędź świata**: niewidzialne ściany przy ±172 m. Dalej siatka horyzontu z paczki
  pokazuje teren, ale nie ma już kolizji.
- **Start w świątyni** przed ołtarzem, twarzą do wyjścia; Agro czeka pod schodami.

## 2. Promień miecza (`src/combat/sword_beam.gd`)

- **Sterowanie**: trzymaj **V / lewy spust** z mieczem w ręku, na stojąco albo z siodła.
  Miecz podnosi się w 0,35 s.
- **Kierunek**: liczy się tylko kierunek patrzenia (`PlayerActions.view_basis`), więc
  kamera, gogle VR i bot działają tak samo.
- **Zbieranie się promienia**: w stożku ±46° promień zbiera się w stronę celu, a poniżej 4°
  staje się jedną jasną linią (`locked`).
- **Potrzebuje słońca**: co 6 ticków jeden promień od ostrza do słońca. W cieniu (pod
  dachem, pod kolosem) ostrze tylko błyska. Test sprawdza to dachem postawionym nad graczem.
- **Ruch z uniesionym mieczem**: wolny chód (0,35 prędkości), postać obraca się tam, gdzie
  patrzy.
- **Na koniu** podnoszenie miecza i rozglądanie się nie skręca Agro.
- **Cel** ustawia region: w dolinie to brama następnego kolosa, w arenie **następny słaby
  punkt** kolosa (Quadratus: najpierw zad, potem czoło). Słaby punkt, na którym spoczywa
  promień, rozjaśnia się, również gdy jest jeszcze zamknięty (pod hełmem, pod klapą).
- **Wygląd**: ostrze w uniesionej ręce, rozbłysk na czubku, promień, którego długość
  i jasność rosną ze skupieniem.

## 3. Pętla gry (`src/game/`)

```
GameWorld (scenes/game.tscn, scena główna)
  start: wczytaj zapis (lub NEW_GAME=1 / -- --new-game) -> DOLINA (świątynia)
  DOLINA: przejście przez otwartą bramę -> wygaszenie -> ARENA (następny kolos)
  ARENA: pokonany -> 12 s upadku kolosa -> DOLINA (świątynia), zapis
         z powrotem przez wejście areny -> DOLINA, przy tej bramie
  trzy pokonane -> DOLINA, wszystkie bramy zamknięte, koniec
```

- **Jeden region naraz**: symuluje się tylko jeden kolos, a areny są dokładnie tymi
  samymi walkami co w Etapach 5–7.
- **Wjazd na koniu**: kto przejechał przez bramę na Agro, wjeżdża do areny w siodle
  (`PlayerRiding.mount_now`).
- **Zapis** (`GameState`): pokonani w ustalonej kolejności, czas gry i liczba śmierci,
  JSON w `user://save.json`.
  - Zapis atomowy: najpierw plik tymczasowy, potem zmiana nazwy.
  - Uszkodzony albo obcy plik daje nową grę.
  - Plik z lukami (np. „quadratus” bez „valus”) nie pozwala ominąć kolosa.
- **Wszystko w tickach fizyki**, łącznie z wygaszeniem ekranu, więc boty, testy
  i sprawdzenie niezależności od FPS działają też dla przejść między regionami.

## 4. Bot całej gry (`src/combat/game_bot.gd`)

- **Drogę znajduje tylko promieniem**, nigdy nie czyta pozycji bramy:
  - obraca widok, szybko przy rozproszonym promieniu, wolno gdy zaczyna się zbierać,
    i zawraca, gdy słabnie;
  - po złapaniu kierunku dosiada Agro i jedzie galopem;
  - co 7 s sprawdza promień z siodła, sterując wtedy względem konia (F6).
- **Utknięcie**: zakręca na 2,5 s, na zmianę w lewo i w prawo.
- **W arenie**:
  - Valusa i Gaiusa walczy pieszo, więc najpierw zsiada;
  - z Quadratusem walczy z siodła;
  - walkę przekazuje botom bossów z poprzednich etapów.
- Soak: `tools/run_game_soak.sh [runs]`. Każda gra ma inne seedy mózgów kolosów i inny
  pierwszy kierunek szukania.

## 5. Sentinel v2 i czytelność

- **Valus w Sentinel v2**: zaokrąglony model z 17 sztywnych części i 3 LOD-ów. Wariant
  przedłużonych stóp pasuje do naszych stóp 3,6 m.
  - Adapter z paczki ukrywa wszystkie siatki segmentu, więc go nie używamy.
  - `ArenaArt.dress_valus` ukrywa tylko części bazowe. Grzywa, czapa futra i pancerz
    Valusa zostają widoczne, bo pokazują, gdzie da się złapać.
- **Odbicie strzały od kamienia**: iskry i syntezowany dźwięk rykoszetu.
- **Hełm Gaiusa**:
  - z każdym ciosem przybywa ciemnych linii pęknięć (tekstura generowana w kodzie,
    bez plików);
  - przy pęknięciu kurz i dźwięk trzasku;
  - przy rozbiciu większa chmura i uderzenie.
- **Owijanie krawędzi przy wspinaniu**: przy przejściu przez wypukłą krawędź kapsuła
  gracza przeskakuje o ~0,5 m w jednym ticku. Rozgrywka zostaje bez zmian, a `PlayerVisual`
  wygładza tylko **rysowane** ciało: największy krok rysowanego ciała w walce z Gaiusem
  spadł z 0,54 m do 0,2 m na tick.

## 6. Ważne ustalenie: szum silnika fizyki i niezależność od FPS

Pierwsza wersja wygładzała skok w samej rozgrywce. Pełny przebieg testów wykazał wtedy,
że walka z Quadratusem przy 90+ FPS kończy się inaczej niż przy 60. Szukanie przyczyny:

- **Ślad bitowy** (`TRACE_TICKS` / `TRACE_BITS` w `fps_scenario`): w ticku 1390, przy
  skoku na nogę, wszystkie dane wejściowe są bitowo identyczne (gracz, każdy segment:
  transformacja docelowa, węzła i serwera fizyki). Mimo to `move_and_slide` zwraca pozycję
  różną o ~0,000004 m. To szum wewnątrz silnika, który był obecny już wcześniej.
- **Dlaczego wcześniej nie było go widać**: dotychczasowe wspinanie go wygaszało. Każde
  wygładzanie pozycji w rozgrywce go zachowywało, a decyzje bota w walce wzmacniały go
  do innego przebiegu. Najgorzej działał próg (`skok > 2×krok`), który zamieniał szum
  w inną decyzję.
- **Rozwiązanie**: wygładzenie przeniesione do warstwy wizualnej, która nie wpływa na
  symulację. Po zmianie stan przy 60 i 90 FPS jest znów bitowo identyczny.
- **Zasada na przyszłość**: w rozgrywce nie wprowadzamy pamięci, która przenosi
  mikroróżnice z silnika, ani progów na wielkościach ciągłych tam, gdzie wystarczy
  wizualizacja.

## Wyniki

__RESULTS__

## Ograniczenia

- **Doczytywanie regionów**: dolina i areny to osobne regiony z krótkim wygaszeniem, nie
  jeden ciągły świat. Areny mają stałe współrzędne i własną ziemię 500 × 500 m. Ciągły
  świat wymaga przesunięcia aren do własnego układu (osobny etap).
- **Koszt Agro w dolinie**: ~400 µs/tick, czyli 2× więcej niż na płaskiej arenie. Głównie
  sondy kroków na mapie wysokości (~200 µs). Cały tick doliny mieści się jednak w ~2 ms.
- **Krawędź świata** to niewidzialna ściana, bez klifów z kolizją.
- **Jezioro**: nie ma pływania, można przejść po dnie.
- **Brak menu**: jest tylko zapis i wczytanie przy starcie; nowa gra przez
  `NEW_GAME=1` albo `-- --new-game`.
- **Promień w arenie** pokazuje tylko następny słaby punkt; nie ma jeszcze „pieczęci” na
  ciele kolosa ani dźwięku odkrycia.
- **Valus po nowej regule fairness** (spokój po wzdrygnięciu) jest dla bota wyraźnie
  łatwiejszy: 0 upadków w 100 walkach. Do sprawdzenia w playteście z człowiekiem.

## Lista do playtestu

- Czy promień miecza da się „wyczuć” (szerokość stożka 46°, zbieranie się do linii)?
- Droga do Gaiusa przez kanion: czy łuk skalny i ściany są czytelne, czy cień nie
  przeszkadza promieniowi?
- Czy powrót do świątyni po 12 s upadku kolosa nie jest za długi lub za krótki?
- Wyjście z areny przez wejście: czy powrót do doliny przy bramie jest oczywisty?
- Sentinel v2: czy grzywa i czapa futra są nadal czytelne jako miejsca chwytu?
- Pęknięcia hełmu i iskry strzał: czy widać, że cios „wszedł”?

## Propozycja Etapu 9

1. **Phaedra, czwarty kolos**: czworonóg z długą, giętką szyją, w arenie z ruinami
   i tunelami.
   - Mechanika z oryginału: kolos jest płochliwy i sam nie podchodzi. Gracz musi
     zwabić go do tunelu i wejść mu na kark, gdy wsadza tam głowę.
   - Wymaga szyi jako łańcucha segmentów z IK (do patrzenia i sięgania) i mózgu, który
     szuka gracza wzrokiem.
   - Korzysta z lokomocji czworonoga z Etapu 6.
2. **Ciągły świat** zamiast wygaszeń: areny we własnych układach współrzędnych wewnątrz
   doliny, doczytywanie regionów w tle.
   - Wjazd do areny bez przerwy.
   - Na początek obok siebie budzi się tylko jeden kolos.
   - Test: przejazd z doliny do areny bez skoku czasu ticku.
3. **Menu i ustawienia**: nowa gra, kontynuuj, pauza, czułość, odwrócenie osi, tryb
   sterowania koniem, sloty zapisu. Wszystko przez `PlayerActions` i `GameState`.
4. **Agro na mapie wysokości**: sondy kroków mają kosztować w dolinie tyle co na płaskim
   (cache wysokości, 400 → ~200 µs/tick).
5. **Paczka do playtestu z człowiekiem**: nagrywanie wejść (`PlayerActions`)
   i odtwarzanie przebiegu (deterministyczny replay), żeby każdy zgłoszony problem dało
   się odtworzyć tick w tick.
6. Soak: 100 całych gier (cztery kolosy) i 100 walk z Phaedrą.
