# Stan projektu po sesji — 3 października 2026

Zamknięty zakres: grywalne prototypy 21 starć, integracja nowych modeli Blender
oraz przenośny autozapis świata. Gra uruchamia się przez `Uruchom-gre.bat`.
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

## Potwierdzone sprawdzenia

Pełny zestaw 197 testów regresji: 0 niepowodzeń. Testy etapu 12, autozapisu,
postaci i checkpointów przechodzą lokalnie. Sprawdzono 20 pełnych walk
z nowymi modelami w obróconych arenach oraz osobną pełną walkę Dormina.
Test integracji sprawdził 21 kampanii, 21 scen prób i dwa checkpointy — 0 błędów.
Rzeczywisty dojazd do Celosii i Cenobii zakończył się zwycięstwem bez śmierci.
Szczegółowe zakresy i liczby: `ETAP_12.md`, `ETAP_13.md`.

Kadry nowych modeli: `art/screenshots/colossi_v3/` i `data/captures/*_v3*.png`.
Surowe logi, wyniki prób, zapisy gracza, cache i silnik są lokalne, poza Git.
Workflow GitHub uruchamia regresję i nowe testy; wynik CI należy odczytać po
zakończeniu jego wykonania. Lokalne wyniki Windows nie potwierdzają wyniku Linux CI.

## Otwarte zadania i kolejność

1. Sprawdzić pełne przejścia całej kampanii z różnymi startami. Losowy kierunek
   Agro potrafił zatrzymać bota podróży w dolinie; nie jest to jeszcze zamknięty
   wielokrotny soak od pierwszego kolosa do Dormina. Boty testowe nie są gotowym
   kompanem AI dla gracza. Przy zakończeniu dużego testu 197 przypadków Godot
   zgłasza zasoby pozostawione przez fixture — trzeba dopracować ich sprzątanie.
2. Dopracować sylwetki, materiały, animacje oraz czytelność dróg wspinania.
   To stylizowane, własne modele prototypowe; odtworzenie gry 1:1 nie jest ukończone.
3. Rozwinąć jeden fragment krainy: pora dnia, pogoda, roślinność, fauna,
   ukryte miejsce i reakcja regionu na pokonanie kolosa. Zachować samotność
   i eksplorację bez mapy pełnej znaczników.
4. Zbudować dyskretnego kompana AI, następnie wejście i wyjście drugiego gracza
   oraz synchronizację sieciową. Istniejący fundament wielu uczestników pozwala
   kontynuować walkę, gdy żywy partner pozostaje; nie stanowi pełnego trybu co-op.
5. VR rozwijać osobno po ustabilizowaniu interakcji, kamery i komfortu ruchu.

Nie rozpoczynano dziś pełnej pogody, ekosystemu, sieciowego co-op ani trybu VR.
Nadrzędny kierunek pozostaje zapisany w `WIZJA_GRY.md`.
