# Etap 17 — osobny prototyp PCVR

Prototyp sprawdza skalę Zakazanej Krainy z perspektywy gogli: teren doliny
i Valusa. Korzysta z wbudowanego OpenXR w Godot 4.6.3. Jest osobną sceną
`scenes/pc_vr.tscn`, uruchamianą przez `Uruchom-VR.bat` lub `tools/run_vr.py`.
Pełna kampania VR, wspinanie rękami, jazda Agro, walka i sieciowa kooperacja
pozostają kolejnymi zadaniami. Zwykła gra nadal startuje w Compatibility.

## Zakres prototypu

- Scena buduje układ świata 3 i oprawę areny Valusa małymi porcjami. Start
  znajduje się w arenie Valusa, około 80 m od kolosa, a nie przy świątyni.
  Prawdziwy model i szkielet Valusa zachowują skalę; jego fizyka jest zamrożona.
- Bramka gotowości wymaga aktywnego fokusu OpenXR, ważnego śledzenia głowy
  oraz celowego naciśnięcia A po puszczeniu przycisku na śledzonym kontrolerze.
  Kalibracja przyjmuje wysokość głowy nad podłogą 0,6–2,4 m i skalę świata 1:1.
- `XROrigin3D`, `XRCamera3D` i dwa `XRController3D` obsługują położenie głowy
  oraz kontrolerów. OpenXR dostarcza rzeczywisty tracking; podgląd na monitorze
  nie jest potwierdzeniem poprawnego obrazu stereoskopowego.
- Ruch po podłożu, skokowy obrót, ponowne wycentrowanie i pauza tworzą podstawę
  do sprawdzania komfortu. Kontrolery mają jedynie lekkie znaczniki kapsułowe;
  nie są pełnymi modelami dłoni ani IK palców.
- Scena nie wczytuje ani nie zapisuje kampanii, nie nagrywa powtórki i nie
  uruchamia kompana ani lokalnego modelu decyzji. Nie potrzebuje wag AI.
- Nie dodano npm, Godot XR Tools, vendor pluginów ani osobnego Android APK.

## Sterowanie i zachowanie ruchu

| Akcja | Kontrolery Touch | Symulacja na monitorze |
|---|---|---|
| Gotowość / wznowienie po utracie trackingu | A, po puszczeniu przycisku | Spacja |
| Chód, do 1,5 m/s | Lewy drążek | WASD |
| Obrót skokowy o 30° | Prawy drążek; wróć do środka przed następnym skokiem | Q / E |
| Rozglądanie | Rzeczywisty obrót głowy | Mysz |
| Wycentrowanie położenia nad ciałem | Y | Y |
| Pauza / wznowienie zwykłej pauzy | X | X |
| Wyjście | B | Esc |

Chód jest kierowany względem poziomego kierunku patrzenia. Kolizja kapsuły
ogranicza wirtualny ruch; brak bezpiecznej podłogi, stroma krawędź i głęboka
woda zatrzymują krok. Fizyczny ruch w pokoju przesuwa ciało kolizyjne pod głową,
ale nie przepisuje rzeczywistego położenia śledzonej głowy. Gdy głowa przesunie
się przez ścianę, widok ciemnieje. Podczas chodu działa łagodna winieta.

Utrata lewej ręki wyłącza chód, prawej — obrót. Odzyskany drążek musi wrócić
do środka, zanim ponownie wywoła ruch. Utrata śledzenia głowy lub fokusu,
przerwanie sesji i zmiana środka śledzenia zatrzymują sterowanie. Powrót wymaga
celowego A; trzymany wcześniej przycisk nie wznawia automatycznie ruchu.
Podczas ruchu dodatkowa kontrola odrzuca położenie głowy poza wysokością
0,3–2,6 m; celowa kalibracja pozostaje w węższym zakresie 0,6–2,4 m.
To obsługa kontrolerów, a nie optyczne śledzenie samych dłoni.
Minimalny profil prostego kontrolera nie ma osi do chodzenia i obrotu.

## PCVR i obsługa Questów

W tej ścieżce świat renderuje komputer; gogle odbierają obraz przez działające
połączenie PCVR. To nie jest samodzielna gra uruchamiana na procesorze Questa.
Aktualna dokumentacja Meta Link wymienia Quest 2, Quest Pro, Quest 3 i Quest 3S,
a Link dla PC wymaga Windows. Samo wymienienie urządzenia przez Meta nie
potwierdza jeszcze zgodności naszej sceny. [Meta: użycie Link](https://developers.meta.com/vr/documentation/unity/unity-link/).

Quest 1 nie znajduje się na tej aktualnej liście. Meta zapowiedziała koniec
krytycznych poprawek i aktualizacji bezpieczeństwa w sierpniu 2024 oraz
możliwości aktualizowania aplikacji Quest 1 w maju 2025. Można badać działający
starszy zestaw Quest 1/Link/OpenXR, ale nie deklarujemy jego bieżącego wsparcia
ani powodzenia połączenia. Daty te opisują wsparcie urządzenia i aplikacji Questa;
nie są wynikiem testu naszego PCVR. [Meta: zmiany dla Quest 1](https://developers.meta.com/vr/blog/changes-coming-quest-1-2023-meta/).

Komputer musi spełniać również wymagania sterownika Link, łącza i kodowania
obrazu. Meta publikuje osobną listę zgodnych GPU oraz wymagania Windows i RAM.
To wymagania połączenia, a nie zmierzone wymagania naszej gry. Wiek karty
ani działanie desktopowego OpenGL 3.3 nie gwarantują PCVR.
[Meta: wymagania PC dla Link](https://www.meta.com/help/quest/140991407990979/).

## Uruchamianie i renderer

```text
Uruchom-VR.bat
python tools/run_vr.py
python tools/run_vr.py --simulate
```

Godot zaleca Mobile dla desktop VR. Osobny launcher VR wybiera
`--rendering-method mobile --rendering-driver vulkan --xr-mode on`, aby
OpenXR był aktywny od startu silnika. Standardowy launcher gry nadal używa
Compatibility. Compatibility także ma zastosowania XR; wybór Mobile/Vulkan
dotyczy tego prototypu PCVR, a nie zakazu innych ścieżek.
[Godot 4.6: konfiguracja XR](https://docs.godotengine.org/en/4.6/tutorials/xr/setting_up_xr.html),
[Godot: zalecenie Vulkan na Windows](https://godotengine.org/article/godot-xr-update-mar-2026/).

Godot przyjmuje `--xr-mode on`, `off` i `default`. Flaga `on` nie tworzy
sterownika ani połączenia z goglami; inicjalizacja może się nie udać.
Diagnostyka sceny bez HMD powinna korzystać z `--xr-mode off`.
[Godot 4.6: opcje wiersza poleceń](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html).

`--simulate` wybiera Compatibility, `--xr-mode off` i argument sceny
`--vr-sim`. Klawiatura i mysz zastępują dane urządzenia tylko w tej jawnie
oznaczonej symulacji. Nie potwierdza ona gotowości realnego OpenXR ani gogli.
Gdy uruchomiony silnik nie zainicjalizuje OpenXR, scena pokazuje komunikat
na monitorze i przycisk zamknięcia; nie przechodzi automatycznie do symulacji.

Launcher pozwala też jawnie wybrać `--renderer gl_compatibility` do badania
zgodności innego backendu z już działającym runtime. Domyślną ścieżką testową
PCVR pozostaje Mobile/Vulkan; alternatywnego renderera nie sprawdzono w HMD.

## Runtime użytkownika i przenośne dane

Potrzebny jest już działający zewnętrzny runtime OpenXR oraz połączenie
gogli z komputerem. Dla Meta jest to środowisko Link skonfigurowane przez
użytkownika. Oficjalna dokumentacja opisuje wybór aktywnego runtime w
ustawieniach Meta Link; nasz launcher go nie zmienia.
[Meta: aktywny runtime OpenXR](https://developers.meta.com/vr/documentation/unity/unity-link/).

Projekt nie instaluje oprogramowania Meta/SteamVR, nie zmienia rejestru ani
systemowego aktywnego runtime. Sterownik gogli pozostaje zewnętrzną zależnością.
Własne logi, cache, silnik i dane narzędzi zostają w folderze projektu, zgodnie
z `tools/run_local.py`. Launcher nie przełącza zapisu do profilu użytkownika
przy braku prawa zapisu. To reguła naszej aplikacji; nie deklarujemy przenośności
zewnętrznego sterownika Meta ani jego własnych danych.

## Koszt renderowania i komfort

Testowa scena korzysta z profilu grafiki `low` i istniejących modeli.
Nie dodaje volumetric fog, GI ani efektów wymagających ciężkiego przetwarzania
całego obrazu. W VR trzeba ocenić także zgodność shaderów i obu oczu;
Godot ostrzega, że część efektów postprocessingu nie obsługuje stereoskopii.
[Godot 4.6: konfiguracja XR](https://docs.godotengine.org/en/4.6/tutorials/xr/setting_up_xr.html).

Realny tryb XR wyłącza VSync monitora i ustawia fizykę na 90 Hz; symulacja
na monitorze używa 60 Hz. Poprzednie ustawienia są przywracane przy wyjściu
ze sceny. Nie jest to wymuszenie 90 Hz w samych goglach ani wynik pomiaru FPS.

Płynności nie wyznaczamy z podglądu na monitorze. Trzeba zmierzyć CPU/GPU
frame time, zgubione klatki, odświeżanie, rozdzielczość oczu i obciążenie
połączenia Link na docelowych goglach. Ruch, skokowy obrót, powrót z pauzy
i ponowne wycentrowanie wymagają osobnej oceny użytkownika. Desktopowe profile
grafiki i wynik testu headless nie stanowią gwarancji komfortu VR.

## Weryfikacja i dalsze prace

| Sprawdzenie | Stan |
|---|---|
| Mapa akcji OpenXR | Headless: 147/147 kontroli, 0 niepowodzeń |
| Logika rigów i bramki bez HMD | Headless: 6 grup rigów i 2 grupy sceny, PASS |
| Natywny start Mobile/Vulkan bez HMD | Kod 0, runtime wykryty, komunikat braku HMD; bez błędów skryptów |
| Rig i scena przy natywnym renderowaniu Compatibility | PASS, bez błędów i zgłoszeń wycieków |
| Kadry gotowości i rozpoczętej symulacji na monitorze | Czytelne kadry 1600×900 |
| Inicjalizacja rzeczywistego OpenXR i obraz obu oczu | Niesprawdzone w goglach |
| Quest 2 przez Link, tracking, przyciski i recenter | Niesprawdzone w goglach |
| Quest 1 ze starszym działającym runtime | Niesprawdzone; bez deklaracji wsparcia |
| Wydajność i komfort przy docelowym odświeżaniu | Niesprawdzone w goglach |

```bash
python tools/run_vr_tests.py
python tools/run_vr_tests.py --native
```

Runner uruchamia sceny z limitem czasu i `--xr-mode off`, sprawdza kod wyjścia,
znaczniki zakończenia oraz błędy i wycieki, nawet gdy proces zwróci kod 0.
Testy rigów korzystają z symulowanych pozycji i rzeczywistych kolizji: badają
gotowość, recenter, ruch pokoju, obrót, przeszkody, wodę, urwiska i utratę
śledzenia. Test sceny sprawdza także niezmienione pliki kampanii i brak
nagrywania. Kadry są w `tests/output/pc_vr_sim_ready.png` oraz
`tests/output/pc_vr_sim_started.png`; pozostają lokalnymi wynikami poza Git.

Próba natywnego startu użyła Godota 4.6.3, Mobile/Vulkan na AMD Radeon
RX 7900 XTX i istniejącego runtime Oculus 1.208.0. OpenXR zwrócił
`XR_ERROR_FORM_FACTOR_UNAVAILABLE`, ponieważ nie dostarczono HMD. Silnik
zgłosił oczekiwane ostrzeżenie nieudanej inicjalizacji XR, a scena pokazała
komunikat braku gogli. `--quit-after 5` zakończyło próbę kodem 0; nie było
błędów skryptów. To sprawdzenie wykrycia runtime i ścieżki odmowy startu,
bez sesji VR, danych trackingu i pomiaru wydajności urządzenia.

Brak HMD podczas testów automatycznych jest ograniczeniem pomiaru, nie
potwierdzeniem ani zaprzeczeniem zgodności konkretnego Questa. Dopiero udany
test na urządzeniu pozwoli wpisać jego model, runtime, GPU, odświeżanie,
rozdzielczość oraz wyniki czasu klatki. Po tym etapie kolejne prototypy mają
zbadać chwyt rękami, bezpieczne przenoszenie przez ruch kolosa, walkę, Agro
i powiązanie z kampanią. [Wizja gry](WIZJA_GRY.md).

## Roślinność zintegrowana w tej sesji

Do bieżącego świata włączono także oprawę roślinną: płynne przejścia kolorów
biomów i gęstości lasu oraz deterministyczne kolonie istniejących kęp trawy,
suchej trawy i krzewów. Rozmieszczenie omija drogi, świątynię, areny, strome
zbocza i zanurzone podłoże. To wyłącznie grafika, bez zmiany wysokości terenu,
kolizji, nawigacji, walki ani RNG rozgrywki.

Wspólne siatki, atlas, materiał i trzy LOD-y obsługują profile low/balanced/high.
Profile zmniejszają liczbę widocznych instancji i dystanse; nie usuwają
wcześniej przydzielonych węzłów ani buforów transformacji. Większa roślinność
ma dodatkowy koszt CPU/RAM i wymaga pomiarów wydajności na docelowym sprzęcie. Wyników
chmurowych nie traktujemy jako pomiarów FPS lokalnej integracji.
[Zakres, budżety i wcześniejsze sprawdzenia oprawy](ENVIRONMENT_DRESSING.md).

Lokalne testy `environment_dressing` i `landscape_v5` przechodzą zarówno
headless, jak i z natywnym Compatibility. Test koloru instancji uwzględnia
udokumentowaną precyzję 16 bit/half-float: tolerancję 1/1024 i identyczność
koloru między LOD-ami. Odświeżono trzy kadry krajobrazu oraz dodano bliski
`art/screenshots/landscape_v5/understory_close.png`, na którym widać rzeczywiste kępy.

Zintegrowany świat ma 7 531 rozmieszczeń pokrywy roślinnej w 2 454 batchach;
cały krajobraz ma 3 663 węzły MultiMesh, 36 współdzielonych siatek i 266 zadań
budowy. Pule widocznych rozmieszczeń dla low/balanced/high to odpowiednio
2 982 / 5 362 / 7 531. Są to sumy dla całego świata, a nie jednoczesne draw calle
ani pomiar FPS. Regresje `main_layout`, `climate_persistence` i `graphics_quality`
przechodzą; test profili zachował identyczny checkpoint 29 060 bajtów. Test
geometrii 21 tras sprawdził 4 269 próbek bez brakującej podłogi. Nie zastępuje
to pełnego przejścia kampanii przez sterowanego aktora.
