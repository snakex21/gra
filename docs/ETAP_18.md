# Etap 18 — bliski chwyt Valusa w PCVR

Pierwsza rzeczywista próba na Quest 2, na stojąco, potwierdziła wejście do VR
i subiektywnie dobre działanie. Użytkownik zgłosił za niski lub dziwny punkt
widzenia, krótkie ręce, pusty start i brak interakcji poza chodzeniem.
Etap 18 rozwija tę samą osobną scenę PCVR: poprawia kalibrację wysokości,
przenosi start przy chwytalną łydkę Valusa oraz dodaje chwyt rękami, dłonie,
przedramiona i miecz, który można podnieść oraz upuścić. To prototyp wspinania na zamrożonym kolosie;
pełna walka, jazda Agro, łuk i kampania VR wymagają dalszej pracy.

## Wysokość i gotowość

Domyślny punkt oczu jest kalibrowany na 1,70 m przy celowym potwierdzeniu A
lub wycentrowaniu Y. Zmiana dotyczy przesunięcia początku układu XR. Nie skaluje
świata ani nie nadpisuje surowej pozycji gogli i kontrolerów: prawdziwe
pochylenie lub przysiad pozostają ruchem użytkownika.

W pauzie X pionowe wychylenie prawego drążka reguluje wysokość oczu
w zakresie 1,40–2,10 m, w tempie 0,25 m/s. Wycentrowanie ustawia także
kierunek względem dojścia do tylnej nogi. Ten etap zakłada grę na stojąco.
Wymaga śledzenia względem podłogi w trybie STAGE lub roomscale;
sam tryb LOCAL bez podłogi nie pozwala rozpocząć ruchu i pokazuje komunikat.
Gra nie zmienia konfiguracji zewnętrznego runtime użytkownika.

Gotowość nadal wymaga fokusu OpenXR, ważnej pozycji głowy i świeżego
naciśnięcia A po puszczeniu przycisku. Utrata sesji lub śledzenia głowy
zwalnia uchwyty i zatrzymuje sterowanie. Odzyskanie śledzenia nie wznawia
samoczynnie ruchu ani wcześniej trzymanego chwytu.

## Stanowisko przy tylnej łydce

Start znajduje się około pięciu metrów od tylnego futra lewej łydki,
w lokalnym punkcie areny `(-1.3, 0.95, -6)`. Valus patrzy w stronę wejścia;
nowe dojście pokazuje chwytalne futro zamiast przedniego pancerza.
Trzy istniejące kamienne rekwizyty po bokach tworzą małe stanowisko
bez zasłaniania drogi do nogi. Valus zachowuje prawdziwy model, szkielet
i dotychczasowe kształty `ClimbPatch`, ale jego ruch oraz ataki są zamrożone.

Pierwszy chwyt można ćwiczyć z ziemi na tylnym futrze łydki, na wysokości
dłoni. Potem można próbować podciągania i zmiany ręki. Kamień i pancerz
pozostają niechwytalne. Nie dodano automatycznej wspinaczki na szczyt,
teleportu do słabego punktu ani całej sekwencji pokonania kolosa.

## Chwyt, wytrzymałość i oprawa rąk

Lewy i prawy boczny przycisk chwytu kontrolera Touch działają niezależnie.
Ściśnięcie przekraczające 0,65 rozpoczyna próbę, a zejście poniżej 0,35
zwalnia rękę. Chwyt szuka rzeczywistego `ClimbPatch` w promieniu 0,18 m
od dłoni; nie wydłuża sztucznie zasięgu ramienia. Kotwica na powierzchni
oraz ruch trzymanej ręki przesuwają ciało i początek układu XR z uwzględnieniem
kolizji. Podciąganie wymaga ruchu rękami, a nie samego trzymania drążka.

Uchwyty zużywają wytrzymałość. Puszczenie obu rąk lub wyczerpanie powoduje
spadek pod wpływem grawitacji. Utracony lub ponownie wykryty kontroler
wymaga puszczenia chwytu i świeżego ściśnięcia; zapamiętany przycisk
nie przykleja ręki po odzyskaniu trackingu.

Własne modele dłoni, mankietów i przedramion zastępują kapsułowe znaczniki.
Ich oprawa podąża za kontrolerami. To nie pełna postać z IK całych ramion
ani optyczne śledzenie palców.

Miecz jest osobnym przedmiotem fizycznym z istniejącym modelem w LOD 1.
Obie ręce mogą złapać jego rękojeść bocznym przyciskiem chwytu i puścić,
aby uruchomić fizykę upadku. Upuszczony miecz wraca po 2 s, po oddaleniu
ponad 3 m albo po spadnięciu 1 m pod stopy. Pojawia się obok pasa, ostrzem
w dół; ponowne podniesienie wymaga świeżego chwytu. Nie przykleja się sam
do dłoni. Pauza, wycentrowanie lub
utrata śledzenia odkładają broń i wymagają puszczenia przycisku przed nowym
chwytem. Miecz nadal nie zadaje obrażeń i nie otwiera słabych punktów.
Łuk nie jest częścią tej próby.

Obie dłonie z przedramionami mają razem 3 304 trójkąty, a miecz LOD 1 — 2 758.
Siatki i materiały korzystają z cache. Miecz ma trzy proste kolidery pudełkowe
i jeden `RigidBody3D`; dłonie i miecz nie rzucają cieni. Nie dodano nowych
pakietów zależności. Te liczby opisują geometrię i fizykę, a nie FPS ani
gwarantowane wymagania sprzętowe.

## Uruchamianie i sterowanie

```text
Uruchom-VR.bat
python tools/run_vr.py
python tools/run_vr.py --simulate
```

| Akcja | Quest 2 / Touch | Podgląd bez gogli |
|---|---|---|
| Gotowość / wznowienie po utracie śledzenia | A po puszczeniu przycisku | Spacja |
| Chód | Lewy drążek | WASD |
| Obrót skokowy | Prawy drążek w bok | Q / E |
| Chwyt lewą / prawą ręką | Lewy / prawy boczny przycisk chwytu | F / G |
| Podniesienie / puszczenie miecza przy rękojeści | Boczny przycisk chwytu | F / G, schematyczne położenie dłoni |
| Wycentrowanie pozycji, wysokości i kierunku | Y | Y |
| Pauza | X | X |
| Regulacja wysokości w pauzie | Prawy drążek góra / dół | Page Up / Page Down |
| Wyjście | B | Esc |

Podgląd klawiaturą/myszą jest jawnie oznaczoną symulacją. F/G symulują stan
przycisków, a nie rzeczywisty ruch rąk. Ocena naturalnego podciągania wymaga
gogli. Domyślny launcher nadal wybiera Mobile/Vulkan i wbudowany OpenXR
Godota 4.6.3; podgląd używa Compatibility i `--xr-mode off`.

## Weryfikacja i ograniczenia

| Sprawdzenie | Stan |
|---|---|
| Pierwsza próba użytkownika na Quest 2, stojąc | Wejście do VR potwierdzone; jakościowe uwagi o wysokości, dłoniach i interakcjach |
| Subiektywna wydajność pierwszej wersji | Oceniona jako dobra; brak zmierzonych czasów klatki i FPS |
| Import projektu w edytorze | PASS |
| Mapa 9 akcji OpenXR, odczyt `--verify-only` | 165/165 kontroli — PASS |
| Rig i osobna scena PCVR | Ścisłe testy headless i natywne Compatibility — PASS |
| Wspinanie na rzeczywistej łydce Valusa | 40 kontroli, 0 błędów, w obu trybach |
| Dłonie i przedramiona | 34 kontrole headless / 36 natywnych, 0 błędów |
| Fizyczny miecz | 40 kontroli, 0 błędów, w obu trybach |
| Zwykła gra, `main_layout` | Nowa Gra, przenośne Kontynuuj i starszy checkpoint — PASS |
| Kadry natywnej symulacji | Obejrzane dwa kadry sceny i dwa dłoni |
| Ponowna próba nowych interakcji w Quest 2 | Pozostaje do wykonania |
| Pełna walka, ruch kolosa, Agro i kampania VR | Poza zakresem tego etapu |

Generacja mapy z zapisem i ponownym odczytem miała wcześniej 166 poprawnych
kontroli; końcowe sprawdzenie istniejącego pliku nie zapisuje go i ma 165.
Test wspinania obejmuje chwyt obiema rękami, współpracę z mieczem, grawitację
po puszczeniu oraz brak zawisu i dryfu przy ścianie. Test broni używa
rzeczywistego `RigidBody3D`, podłogi i ściany; sprawdza też prędkość rzutu
po dodatkowej synchronizacji śledzenia.

```text
python tools/run_vr_tests.py
python tools/run_vr_tests.py --native
```

Runner obejmuje mapę akcji oraz rig, scenę, wspinanie, dłonie i miecz.
Wariant natywny używa Compatibility bez HMD. Końcowe sprawdzenia przeszły
bez `SCRIPT ERROR`, `ERROR` i zgłoszeń wycieków; runner wymaga także
poprawnego znacznika zakończenia i ogranicza czas każdej sceny do 120 s.
Lokalne kadry to `pc_vr_sim_ready.png`, `pc_vr_sim_started.png`,
`pc_vr_hands_first_person.png` i `pc_vr_hands_detail.png` w `tests/output/`.

Pierwsza próba nie potwierdza jeszcze działania nowych poprawek ani komfortu
wspinania. Nie daje też minimalnych wymagań sprzętowych: brak pomiarów
CPU/GPU frame time, rozdzielczości oczu, odświeżania i zgubionych klatek.
Quest 1 pozostaje niegwarantowaną próbą zgodności ze starszym środowiskiem;
informacje o aktualnym wsparciu Meta Link i oficjalne źródła są w [Etapie 17](ETAP_17.md).

PCVR nadal jest osobną sceną bez zapisów kampanii, nagrywania powtórek,
kompana AI i sieciowej kooperacji. Własne dane narzędzi i silnika zostają
w folderze projektu; launcher nie instaluje ani nie przełącza systemowego
runtime OpenXR. Zwykła kampania zachowuje Compatibility i dotychczasowe
mechaniki wspinania. [Wizja gry](WIZJA_GRY.md).
