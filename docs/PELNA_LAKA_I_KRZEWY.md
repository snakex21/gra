# Pełniejsza łąka i niskie krzewy

Kontynuacja `d50b91281b4b46062f80f3d083083509a696df44`, przygotowana lokalnie w chmurze. Bez publikacji, merge ani zmian AI/kooperacji.

## Co naprawiono

Poprzednia duża liczba obiektów nie przekładała się na obraz: najdalsza trawa miała zaledwie trzy źdźbła, a profil zrównoważony usuwał ją około 127 m od środka partii. Szeroka łąka wyglądała jak puste podłoże.

- Każdy nowy model trawy zawiera dziewięć nieregularnie rozłożonych kęp. Wszystkie trzy LOD-y zachowują ich położenia i pionowy zarys
- Trawa ma 288 / 144 / 54 trójkąty. Niskie krzewy mają 240 / 120 / 80 trójkątów, nierówne korony i drobne końcówki liści
- Większe zielone i przygaszone słomiane płaty przeplatają się z szerokimi niskimi krzewami, małymi kamieniami i prześwitami. Pierwszy roboczy wariant z dużymi płaskimi liśćmi został odrzucony
- Daleki LOD jest pełnoprawną sylwetką kępy. Na profilu zrównoważonym trawa sięga do 280,5 m, krzewy do 306 m, według wspólnego środka granic partii
- Zachowano istniejące, poprawione wcześniej tekstury i materiały. Nie użyto generowania obrazów ani pobranych grafik

## Przejścia i zgodność

Nie zmieniono siatek terenu ani drogi, kolizji, nawigacji, wejść aren, zapisów, powtórek lub reguł gry. Historyczne układy 1–4 i ich kolejność losowania pozostają bez zmian. Nowa łąka obejmuje tylko pas trasy w układzie 5.

Poprzedni kwadrat 210 m był buforem dekoracji, nie obszarem mechaniki gry. Rzeczywista granica dawnej doliny wynosi 172–180 m, a świątynia jest znacznie bliżej środka. Pełne obrysy nowych roślin pozostają poza kwadratem 180 m. Tylko krótka trawa i małe kamienie łagodnie wchodzą na zewnętrzne pobocze: gęstość narasta w zakresie 187–207 m, wysokość do 230 m. Krzewy zaczynają się od 217 m. Sama świątynia, punkty startowe, przejazdy i widoki z centrum pozostają otwarte.

Odległość korzeni od drogi uwzględnia jej rzeczywistą szerokość i dodatkowy zapas 6 m na obrys trawy. Duże krzewy zachowują minimum 28 m od osi. Nadal obowiązują wyłączenia przy arenach, wodzie i stromych stokach. Nowe kępy dopasowują nachylenie do siatki terenu.

## Wydajność i dowody

MultiMesh grupuje obiekty w komórkach 64 m. Profile niska/zrównoważona/wysoka zachowują 35% / 65% / 100% instancji. Kolejność jest deterministycznie przemieszana. Własne LOD-y nie są dodatkowo agresywnie upraszczane przez automatyczny LOD siatki.

Próbkowanie jest wznawiane co cztery kandydatury; przemieszanie działa partiami; granice i kolory są obliczane raz; każdy upload jednego LOD-u jest osobną jednostką. Miękki limit wywołania wynosi 1,25 ms, lecz pojedyncza jednostka i planista systemu mogą go przekroczyć. Pompa układu 5 przetwarza do 16 tanich jednostek w jednym wywołaniu: starsze, większe zadania łączy w budżecie 1 ms, a wznawialną łąkę w budżecie 3 ms. Nie czeka całej klatki po każdej drobnej operacji. Testy mierzą tę rzeczywistą pompę, maksymalny krok oraz pełny koszt budowy, nie tylko zadania pierwotnie obecne w kolejce.

Wyniki końcowe oraz budżety są w dołączonym raporcie weryfikacji. Liczby trójkątów i powierzchni są górnym oszacowaniem przed przycinaniem poza kadrem, z rzeczywistych zaimportowanych modeli, profili i progów odległości. Nie są pomiarem GPU ani FPS.

Porównania pokazują ten sam dawny i nowy punkt widzenia oraz to samo światło. Podgląd CPU Blendera odtwarza rzeczywiste siatki, transformacje, LOD-y i gęstość profilu zrównoważonego. Nie jest zrzutem z uruchomionego Godota: oświetlenie, filtracja i szczegóły shaderów mogą wyglądać inaczej. Nie zastosowano autorskiego pełnego LOD0 do przedstawienia profilu zrównoważonego.

Dodatkowy test rzuca promienie na rzeczywiste trójkąty widocznej trawy i krzewów. Odróżnia pokrycie przez rośliny od pustego podłoża, nie liczy samych obrysów AABB. Osobno pokazuje trawę i krzewy oraz pierwszy, środkowy i daleki plan. Drogi, niebo i kamienie są wyłączone z tej miary, natomiast celowe polany pozostają w mianowniku.

### Wyniki końcowe (Godot 4.6.3, testy headless)

- Pas trasy: 23 328 elementów, w tym 15 366 kęp trawy, 7415 krzewów i 547 drobnych kamieni. Cały świat: 30 531 proceduralnych elementów; 5463 przydzielone partie wszystkich LOD-ów
- Profil zrównoważony, warstwa proceduralnej roślinności/kamieni: 414 408 trójkątów / 146 wybranych partii w dawnym bliskim ujęciu; 500 176 / 187 w ujęciu z poziomu drogi. To znacznie więcej niż poprzednie 8607 / 27 i 9648 / 32
- W ujęciu z poziomu drogi koszt geometrii wzrósł około 51,8 razy. 75,7% przypada na najdalszy LOD, 23,7% na środkowy, tylko 0,6% na najbliższy. Nie ma przypadkowo zdublowanych ani odwróconych kopii trójkątów w nowych modelach. Większy koszt wynika z faktycznie utrzymanego dalekiego pokrycia, nie z błędnego dublowania LOD-ów
- Niska jakość w tym samym punkcie: 192 758 trójkątów, około 61% mniej niż zrównoważona. Wysoka: 934 866. Niska jakość ogranicza rysowanie, ale nie usuwa kosztu przygotowania całej deterministycznej obsady
- Test pojedynczych kontynuacji strumieniowania: maksimum 4.655 ms, 95. percentyl 1.744 ms. Trzy pełne budowy układu 5 z końcowym, adaptacyjnym opróżnianiem kolejki: maksymalne kroki 6,385 / 6,438 / 7,189 ms; łączny czas CPU 3,183 / 3,136 / 3,504 s
- Końcowa kolejka dekoracji potrzebowała 551 / 544 / 585 wywołań klatkowych zamiast wcześniejszych 1245–1278. Przy 60 wywołaniach na sekundę to około 9,1–9,8 sekundy stopniowego pojawiania się całej dekoracji świata, zamiast około 21 sekund. Rzeczywisty wynik zależy od komputera i częstotliwości klatek. Czas CPU powyżej nie jest obietnicą 3-sekundowego ładowania w grze
- Rzeczywiste piksele roślin w dawnym bliskim ujęciu: pierwszy plan 44,30%, środkowy 44,16%, daleki 57,59%, wobec około 3,90% / 2,21% / 0% wcześniej. Celowe prześwity i przestrzeń między źdźbłami pozostają liczone jako puste podłoże; nie twierdzimy, że każdy fragment kadru jest w ponad połowie zakryty
- Osobny udział trawy: 34,93% / 28,46% / 24,50%; krzewów: 9,38% / 15,70% / 33,09%
- Wszystkie 356 eksportowanych siatek terenu/drogi i 864 ręczne transformacje istniejących dekoracji są identyczne z bazą

Przeszły testy: deterministyczna obsada i obrysy wyłączeń, czterokandydatowe wznowienia oraz stan RNG, zmiana jakości pomiędzy uploadami LOD, anulowanie, budżety geometrii, dekoracje środowiska, układy 4/5, historyczna powtórka układu 4, zapis/odczyt, powtórki walk, układ świata, ustawienia grafiki i trzy pełne budowy sceny. Układy 1–4 zachowują stary sampler. Żaden test headless nie stanowi pomiaru FPS na karcie graficznej.
