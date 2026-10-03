# Stan projektu po sesji — 3 października 2026

Sesja obejmuje Etapy 13–17: modele Blendera i przenośny autozapis, broń,
geografię i wydajność, czas i pogodę, opcjonalnego kompana z zapisem
sesji i powtórkami, osobny prototyp PCVR i kolejną oprawę roślinności.
Zakres opisują `ETAP_13.md`–`ETAP_17.md` oraz `ENVIRONMENT_DRESSING.md`.
Gra uruchamia się przez `Uruchom-gre.bat`.
Po świeżym klonowaniu należy najpierw wykonać
`python tools/run_local.py install-godot`.

## Co jest gotowe

- Menu prób i kampania obejmują wszystkie 21 zaplanowanych starć. Celosia oraz
  Cenobia walczą równocześnie, a finał z Dorminem pozostawia Wędrowca przy życiu.
- Wędrowiec, Mono na ołtarzu, Agro, Dormin i pozostałe kolosy mają własne modele
  Blender, eksporty GLB i trzy poziomy szczegółowości. Źródła `.blend` pozostają
  edytowalne w `art/source/`; renderowanie wykorzystuje dotychczasowe rigi i kolizje.
- Zapis postępu, checkpoint świata, ustawienia, nagrania i dane narzędzi zostają
  w folderze projektu. Minutowy autozapis i zwykłe wyjście zachowują ostatnie
  bezpieczne położenie. Starszy checkpoint nie cofa późniejszego zwycięstwa.
- Jaskinia ma światło miecza, Avion planuje przelot, grafika aren powstaje małymi
  krokami, a woda ma fale, efekty pod wodą i plusk. Powtórki korzystają z checkpointów.
- Łagodne wejścia do wszystkich aren i otwarte wejście Basarana usuwają wykryte
  sztuczne progi. Para strażników daje się pokonać także po rzeczywistym dojeździe.
- Cykl dobowy i regionalna pogoda działają w kampanii. Zegar, fronty oraz anomalia
  Dormina przetrwają zapis i przewijanie. Krajobraz ma nowe modele drzew,
  skał i ruin, wspólny atlas, MultiMesh i trzy LOD-y. Profile grafiki ograniczają koszt.
- Zintegrowano oprawę roślinności z płynnymi granicami biomów i gęstością lasów
  oraz koloniami istniejącej trawy i krzewów. Wspólne assety i LOD-y ograniczają
  koszt widocznej grafiki; drogi, areny, kolizje i wysokości terenu pozostają
  niezmienione. Profile jakości nie redukują przydzielonych wcześniej węzłów
  i buforów. [Zakres oraz budżety](ENVIRONMENT_DRESSING.md).
- Kompan AI jest opcjonalny, domyślnie wyłączony i pieszy. Podąża, omija ściany
  i przepaści, unika ataków oraz rzadko pomaga łukiem. Ziarno polityki daje
  różne, odtwarzalne decyzje bez modelu uczenia maszynowego.
- Tryb sesji, aktor, RNG i timery są w checkpointach. Nagrania zawierają dwa
  strumienie akcji, zmiany trybu i przegrupowania. Odtwarzanie nie uruchamia modelu;
  stare checkpointy i nagrania pozostają solo. Śmierć lub odejście jednego
  uczestnika zachowuje walkę, gdy drugi pozostaje żywy.
- Prototyp PCVR ma osobną scenę terenu doliny z zamrożonym Valusem i launcher `Uruchom-VR.bat`.
  Wbudowany OpenXR obsługuje śledzenie głowy/kontrolerów oraz podstawy ruchu.
  Startuje w arenie Valusa; bramka A, chód 1,5 m/s, obrót o 30°, wycentrowanie,
  pauza, blokada przy utracie śledzenia i winieta tworzą prototyp komfortu.
  Renderer VR to Mobile/Vulkan; zwykła gra pozostaje w Compatibility.
  Nie potwierdzono działania ani wydajności w rzeczywistych goglach.
  [Dokładny zakres i stan sprawdzeń](ETAP_17.md).

## Lokalny model — stan badawczy

Opcja modelu ma działający asynchroniczny klient, ograniczone dane, timeout
i fallback zwykłego kompana. Ręcznie uruchamiany adapter ONNX bada rzeczywiste
głowice decyzji na CPU, ale ocenione modele zbyt słabo adaptują stan gry,
aby zalecać je w produkcji. Nie wybrano modelu docelowego ani nie wykazano
przewagi jakości nad zwykłą polityką. Bekko nie przypisuje jeszcze licencji wag;
pobrane wagi i runtime pozostają lokalnym materiałem badawczym w pomijanym
`data/ai/`. [Wyniki i polecenia](LOCAL_DECISION_MODELS.md).

## Potwierdzone sprawdzenia

W pierwszej części sesji pełny zestaw 197 testów regresji: 0 niepowodzeń. Testy etapu 12, autozapisu,
postaci i checkpointów przechodzą lokalnie. Sprawdzono 20 pełnych walk
z nowymi modelami w obróconych arenach oraz osobną pełną walkę Dormina.
Test integracji sprawdził 21 kampanii, 21 scen prób i dwa checkpointy — 0 błędów.
Rzeczywisty dojazd do Celosii i Cenobii zakończył się zwycięstwem bez śmierci.
Szczegółowe zakresy i liczby: `ETAP_12.md`, `ETAP_13.md`.

Po Etapie 16 ponowny pełny zestaw 197 testów zakończył się kodem 0 i bez
niepowodzeń ani błędów skryptów. Stare testy powtórek i ustawień przechodzą.
Zamknięcie historycznego runnera nadal zgłasza `ObjectDB`, pięć zasobów w użyciu
i komunikat `ERROR` z `PagedAllocator`; raport oznaczył siedem różnic starszych metryk Etapu 2/4.
Te wyniki nie dowodzą braku wycieków każdej starszej fixture ani płynności modeli.

Nowy kontroler ma 25 sprawdzeń i 0 błędów; polityka, ustawienia, świat
i ścisła regresja lifecycle przechodzą. Test powtórek ma 37 sprawdzeń;
dodatkowo sprawdzono replay od tick 0 przez odejście, ponowne dołączenie
i przegrupowanie. Harness HTTP ma 40 sprawdzeń Godota, protokół Python — 8 testów.
Nowe natywne sceny kompana zamykają Compatibility bez wycieków tekstur po
barierze renderowania fixture. Ścisły zestaw uruchamia
`python tools/run_companion_tests.py` i odrzuca błędy skryptów przy kodzie 0.
Weryfikację klimatu i krajobrazu opisuje `ETAP_15.md`.

Natywny start Etapu 17 w Mobile/Vulkan na RX 7900 XTX wykrył istniejący runtime
Oculus 1.208.0. Brak HMD zwrócił `XR_ERROR_FORM_FACTOR_UNAVAILABLE`; scena
pokazała komunikat braku gogli, bez błędów skryptów, a próba zakończyła się kodem 0.
Mapa akcji ma 147/147 poprawnych kontroli. Headless przechodzą 6 grup testów
rigów oraz 2 grupy sceny; rig i scena przechodzą też z natywnym Compatibility
bez błędów i zgłoszeń wycieków. Kadry gotowości i rozpoczętej symulacji 1600×900
są czytelne. Zestaw uruchamia `python tools/run_vr_tests.py` oraz `--native`.
Tracking, obraz obu oczu, Quest 2/Link, zgodność starszego Quest 1 oraz wydajność
i komfort pozostają niesprawdzone w goglach. [Weryfikacja PCVR](ETAP_17.md).

Lokalne testy roślinności `environment_dressing` i `landscape_v5` przechodzą
headless oraz w natywnym Compatibility. Test GPU uwzględnia precyzję koloru
half-float, tolerancję 1/1024 i identyczność LOD. Trzy kadry odświeżono;
`art/screenshots/landscape_v5/understory_close.png` pokazuje rzeczywiste kępy.
Świat ma 7 531 rozmieszczeń w 2 454 batchach pokrywy roślinnej, 3 663 węzły
MultiMesh całego krajobrazu, 36 wspólnych siatek i 266 zadań budowy.
Low/balanced/high udostępniają 2 982 / 5 362 / 7 531 widocznych rozmieszczeń
w skali całego świata; to nie pomiar FPS ani jednoczesnych draw calli.
Regresje `main_layout`, `climate_persistence` i `graphics_quality` przechodzą;
checkpoint profili pozostaje identyczny (29 060 bajtów). Geometria 21 tras:
4 269 próbek, 0 brakujących podłóg. Test geometrii nie jest przejściem kampanii.
[Lokalne i historyczne wyniki oprawy](ENVIRONMENT_DRESSING.md).

Kadry nowych modeli: `art/screenshots/colossi_v3/` i `data/captures/*_v3*.png`.
Surowe logi, wyniki prób, zapisy gracza, cache i silnik są lokalne, poza Git.
Workflow GitHub uruchamia regresję i nowe testy; wynik CI należy odczytać po
zakończeniu jego wykonania. Lokalne wyniki Windows nie potwierdzają wyniku Linux CI.

## Otwarte zadania i kolejność

1. Sprawdzić pełne przejścia całej kampanii z różnymi startami. Losowy kierunek
   Agro potrafił zatrzymać bota podróży w dolinie; nie jest to jeszcze zamknięty
   wielokrotny soak od pierwszego kolosa do Dormina. Kompan ma osobny kontroler;
   boty testowe całych walk nadal służą weryfikacji. Przy zakończeniu 197 testów Godot
   zgłasza zasoby pozostawione przez fixture — trzeba dopracować ich sprzątanie.
2. Dopracować sylwetki, materiały, animacje oraz czytelność dróg wspinania.
   To stylizowane, własne modele prototypowe; odtworzenie gry 1:1 nie jest ukończone.
3. Rozwinąć faunę, ukryte miejsca, zagadki i konkretne reakcje regionów na
   pokonanie kolosa. Czas i pogoda już działają; pogoda pozostaje kosmetyczna.
   Zachować samotność i eksplorację bez mapy pełnej znaczników.
4. Rozwinąć nawigację kompana, sterowanie drugim graczem i synchronizację sieciową.
   Obecny kompan pieszy nie stanowi pełnego co-op. Badania modelu kontynuować na
   reprezentatywnych stanach z oceną jakości, kosztu i warunków dystrybucji.
5. Zweryfikować prototyp PCVR na goglach i docelowym PC: runtime, oba oczy,
   tracking, recenter, pauzę, komfort oraz czas klatki. Potem rozwinąć interakcje
   rękami, ruch kolosa, walkę i Agro. Quest 1 nie ma deklarowanego bieżącego wsparcia.

Ekosystem, sieciowy co-op i pełna kampania VR pozostają do wdrożenia. Wymagania sprzętowe
trzeba zmierzyć na rzeczywistym starszym sprzęcie; OpenGL 3.3 samo nie gwarantuje FPS.
Nadrzędny kierunek pozostaje zapisany w `WIZJA_GRY.md`.
