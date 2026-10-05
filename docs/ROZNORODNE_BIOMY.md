# Różnorodne, pełniejsze skupiska roślinności

Kontynuacja zatwierdzonej pełniejszej łąki z
`c363b1ad6be10c1818aff9a75dd0c5a392449eff`.
Zmiana dotyczy wyłącznie wizualnej dekoracji układu świata 5. Nie przenosi dróg,
aren, wejść, skał kolizyjnych ani świątyni. Nie zmienia walk, AI, kooperacji,
mechaniki zapisów ani powtórek. Historyczne układy 1–4 zachowują dawny sampler.

## Różne miejsca, różne mieszanki

- Otwarte łąki: pełne kępy traw z kłosami, drobne kremowe kwiaty i niski podszyt
- Zachodni las: warstwowe, wygięte liście paproci i zaokrąglone niskie krzewy
- Wyżyny: zwarte wrzosowe kępy, złotawe trawy, skały i odsłonięty żwir
- Suche regiony: niska sucha roślinność oraz mieszane kamyki, bez zielonego dywanu
- Wschodnie niziny: wyższe sitowie przeplatane trawą; wyżej krzewy i kwiaty
- Obrzeża wybrzeża: sitowie w najniższych miejscach oraz krzewy i żwir wyżej
- Teren wulkaniczny: oszczędniejsze suche rośliny i kamieniste plamy

To mieszanki zależne od istniejących wag biomów, wysokości i położenia wybrzeża,
a nie nowe regiony albo przebudowana geografia. Istniejące drzewa, skały i ruiny
pozostają na swoich miejscach. Dwa rodzaje roślin na mały obszar mieszają się
w nieregularne skupiska z lukami i przechodzą probabilistycznie między biomami.

### Pełniejsze miejsca zamiast jednolitego dywanu

24 większe lokalne skupiska mają nieregularne, łagodnie zanikające brzegi.
Ich promienie wynoszą około 70–92 m. Każde ma 463–970 zaakceptowanych modeli
przed redukcją profilu jakości. Centra są na rzeczywistym terenie, a filtr
nadal odsuwa rośliny
od dróg, świątyni, aren, stromych zboczy i morza.

W skupiskach kandydatury leżą co około 4 m. Poza nimi gęstość wraca do
oszczędniejszego tła: drobniejsza siatka nie mnoży automatycznie roślin całego
fragmentu mapy. Dalekie widoki i otwarte strefy zostają. To lokalne, bogatsze
miejsca rozłożone po biomach, a nie jednakowo gęsta cała mapa.

Zatwierdzony korytarz zachowuje wszystkie 23 328 pozycji, skal i orientacji.
Pełne dotychczasowe krzewy zostają; część miękkiej trawy dostaje równie szeroką
kępkę z kłosami. Nie rozciągamy kosztownej gęstości korytarza na całą mapę.

## Modele i koszt

Siedem nowych rodzin ma trzy prawdziwe siatki LOD. Każdy poziom zachowuje
wszystkie dziewięć grup korzeni; odległość nie zamienia kępy w kilka patyków.
Paprocie mają fałdowane, warstwowe liście, krzewy nakładające się korony,
trawy liście u podstawy oraz kłosy, kwiaty rozetki, żwir 18 różnych kamieni.

21 plików GLB zajmuje około 379 KB. LOD-y mają 216–279 / 108–144 / 54–81
trójkątów na model. Wszystkie są nieprzezroczyste, mają jeden wspólny materiał
i istniejący atlas, bez cieni, kolizji oraz skryptu na każdej roślinie.

Ekologiczne plamy mają rozmiar 64 m. Poza korytarzem są łączone w partie
MultiMesh wielkości 128 m. Ogranicza to liczbę węzłów kosztem mniej dokładnego
odrzucania przestrzennego. Progi LOD wynoszą 90/155/240 m przed zastosowaniem
profilu; większy pierwszy próg chroni rośliny blisko kamery przed zbyt wczesnym
uproszczeniem z powodu odległego środka partii. Korytarz zachowuje własne
64-metrowe partie i dalsze progi.

Profil niski zostawia 35%, zrównoważony 65%, wysoki 100% instancji. Kolejność
jest mieszana deterministycznie, aby redukcja nie wycinała równych pasów.

Końcowy sampler ma 60 848 instancji proceduralnych zamiast 29 886 w poprzedniej
zatwierdzonej wersji: 23 328 w korytarzu i 37 520 poza nim. To realny dodatkowy
koszt, około dwukrotnie większa populacja całego świata. Ich trzy LOD-y mają
6 882 partie; wspólne tekstury i siatki nie są kopiowane na każdą roślinę.

Budowa pracuje w istniejącej kolejce: cztery kandydatury albo jeden upload LOD
na mały krok, miękki limit 1,25 ms. Najpierw kończy gęsty korytarz, potem dalsze
skupiska. Odczytuje aktualny profil jakości, zwalnia tablice po zakończeniu,
a usunięcie rodzica bezpiecznie anuluje pracę. Pełna dekoracja pojawia się
stopniowo po starcie. Limity czasowe są miękkie, nie gwarantują stałego FPS.

## Weryfikacja

`tests/biome_groundcover.gd` sprawdza wszystkie 256 fragmentów, identyczność
samplera synchronicznego i porcjowanego, historyczne układy, pozycje korytarza,
różnorodność i rzeczywistą obsadę wszystkich 24 skupisk, limity, prześwity
całych modeli, kontakt z powierzchnią, obwiednie LOD, zmianę profilu w trakcie
uploadu, priorytet kolejki, późne dodanie zadania i anulowanie po usunięciu rodzica.

`tests/route_density_cost.gd` liczy rzeczywiste zaimportowane trójkąty oraz
produkcyjne ustawienia LOD dla korytarza, lasu, wyżyn, pustyni, wschodu i terenu
wulkanicznego. To koszt przed frustum/occlusion culling, a nie pomiar FPS GPU.
W paczce są szczegółowe końcowe raporty i przebiegi testów.

Podglądy przed/po to CPU Blendera: rzeczywiste siatki, pozycje, kolory i tekstury
gry, identyczne kamery i oświetlenie, profil zrównoważony z rzeczywistą selekcją
instancji i LOD. Nie są zrzutami z Godota; oświetlenie, filtracja i końcowa
płynność wymagają sprawdzenia na GPU w grze.

Nie trzeba kasować zapisów. Zapisany układ 4 celowo zachowuje dawną roślinność;
nowa dekoracja jest dla układu 5. Paczka kontynuacyjna nie zawiera całej gry/EXE.

### Końcowe pomiary CPU i geometrii

Trzy pełne przebiegi z dekoracją: 8 592 partie całego świata, 1 061–1 107
wywołań kolejki. To około 17,7–18,5 s przy 60 wywołaniach/s. Najdłuższy
zmierzony krok wyniósł 6,50 ms; miękki limit nie jest twardą gwarancją opóźnienia.

Profil zrównoważony wybierał przed odrzuceniem obiektów poza kadrem:
141 741 trójkątów w lesie, 99 504 na wyżynie, 106 380 w suchym regionie,
175 923 na wschodzie oraz 510 940 w punkcie gry na gęstej trasie
(wcześniej 500 176). Te liczby dotyczą warstwy proceduralnej, nie całej gry.
Większy wizualny efekt jest zatem rzeczywiście renderowany, a nie uzyskany
samymi nazwami modeli lub podkręconym podglądem.
