# Linia bark–łokieć–dłoń przy naciąganiu łuku

Poprawka kodu względem dokładnego wydania `9862e0729614832f0558a383430975765a34c34d`.

Poprzedni fizyczny punkt cięciwy leżał po lewej stronie postaci. Prawa dłoń
próbowała go dosięgnąć przez tył szyi. Samo poprawienie palców i nadgarstka
nie usuwało tej sprzeczności.

## Poprawiona poza

- Głowa i punkt cięciwy korzystają ze wspólnego układu naciągu, opartego na
  kierunku celowania oraz pochyleniu siedzenia
- Tułów ustawia się bokiem do linii strzału, a barki obracają się razem z nim
- Naciągająca dłoń pozostaje po prawej stronie żuchwy. Fizyczny punkt strzały
  jest teraz w tej samej pozycji, co widoczna nasadka strzały i palce
- Łokieć wynika z rozwiązania całego łańcucha o stałych długościach; nie jest
  przesuwany osobno. Nadgarstek pozostaje w osi przedramienia
- Pochylenie górnej części ciała podąża za celowaniem, zamiast rozciągać palce
  do źle ustawionej cięciwy. Kołczan podąża za barkami
- Lewa ręka ma zasięg ograniczony rzeczywistymi długościami odcinków. Wartość
  naciągu sterująca siłą strzału, czas ładowania i prędkość pocisku nie zmieniają się
- Po zwolnieniu cięciwy tułów wraca razem z odprowadzeniem dłoni. Zmiana broni,
  LOD i let-down przywracają zwykłe mocowania

To świadoma zmiana wspólnego punktu fizycznego i wizualnego, nie wyłącznie
przesunięcie grafiki strzały. Kierunek pocisku nadal jest obliczany od tego
rzeczywistego punktu do celu wskazanego promieniem widoku. Nie zmieniono
kolizji pocisku, grawitacji, obrażeń, dziedziczenia prędkości konia, zapisu,
protokołu współpracy ani położenia pochwy przy biodrze.

Miednica, biodra, nogi i podstawa postaci nie są obracane przez tę pozę.
Wszystkie modele GLB, źródła Blender, materiały, tekstury i siatka dłoni
pozostają identyczne z wydaniem bazowym.

## Weryfikacja

- `tests/archery_draw_alignment.tscn`: rzeczywiste położenie głowy, przedramienia,
  dłoni, kołczanu i strzały; stałe długości kończyny; osadzenie miednicy i pochwy;
  powrót pozy; fizyczne trafienie w bliską ścianę przy trzech pochyleniach
- `tests/bow_draw_hand.tscn`: wszystkie LOD, stanie i jazda, pochylenie konia,
  skręt celowania ±1,2 radiana i pochylenie ±0,65 radiana, różne poziomy naciągu,
  kontakt palców z faktyczną cięciwą, prosty nadgarstek oraz zwolnienie palców
- `tests/mounted_bow_socket.tscn`: zgodność fizycznej strzały z nasadką, niezależność
  od FPS/LOD, przejścia wsiadania, prędkość konia i przechwycenie przez niski mur
- dotychczasowe testy broni, pochwy, siedzenia i powierzchni postaci oraz pełny
  zestaw 197 testów rozgrywki

Podglądy są renderami faktycznych siatek i końcowych póz wczytanych przez
Godota, oświetlonych identycznie w Blenderze Cycles CPU. Nie są testem GPU,
FPS ani uruchomienia na Windows. Raport wydania podaje rzeczywiste wyniki,
w tym istniejące błędy zestawu bazowego. Zakres sprawdzeń nie jest deklaracją
pełnej biomechanicznej poprawności dowolnego obrotu kamery ani każdej sytuacji
kolizyjnej w całej grze.

## Zimny start testu niezależności od FPS

Pełna regresja na pierwszym kandydacie `3f98068` ujawniła różnicę pięciu ticków
w pieszym scenariuszu Quadratusa. Diagnostyka wykazała problem inicjalizacji
samego scenariusza testowego: tworzył on tymczasową podłogę, następnie odkładał
jej usunięcie do końca klatki i od razu budował właściwą podłogę areny. Przy
różnych FPS niepotrzebny obiekt mógł pozostawać w fizyce przez inny czas.

`_setup_quadratus()` usuwa teraz tymczasowe węzły synchronicznie, przed dodaniem
areny, tak jak pozostałe nowsze scenariusze testowe w tym samym pliku. Test
`fps_scenario_setup.tscn` sprawdza oba warianty przed pierwszym tickiem: brak
kolejkowanego kolidera, obecność i niezmienione wymiary właściwej podłogi oraz
brak pominiętych kroków. Kontrola negatywna na poprzednim kodzie wykrywa błąd.

Nie zmieniono algorytmu kolizji, kapsuł ani marginesów gracza/kolosa. Lista
sześciu limitów FPS, sterowanie botem, porównywane stany i próg testu pozostają
bez zmian. Jest to naprawa cyklu życia obiektów testowych, nie złagodzenie
kryterium deterministyczności.
