# Agro, dosiad i mocowania wyposażenia

Baza tej poprawki: `c7e9fc66d1bab5552cddce11bfb38320464500ce`.

## Zakres

- Miednica Wędrowca jest osadzona przy siodle, a kosmetyczne nogi celują do dopasowanych strzemion. Stały offset `PlayerRiding.SEATED_VISUAL_OFFSET` wynosi −0,28 m; jego waga płynnie zmienia się podczas istniejących przejść wsiadania/zsiadania.
- Dalsza noga przenosi się nad siodłem. Stopy wracają do neutralnej orientacji po zejściu. Nie zmieniono kapsuły gracza ani jego mechanicznej trajektorii wsiadania.
- Agro ma mniej wypukłe nasady przednich nóg, węższe uda i delikatnie skorygowaną klatkę. Ciągłość wcześniej zaakceptowanego Wędrowca pozostaje bez zmiany jego plików GLB.
- Wodze są niewielką, osobną geometrią kosmetyczną. Podążają za wolną dłonią albo spoczywają przy siodle. Nie sterują koniem i nie tworzą kolizji.
- Łuk, kołczan z widocznymi strzałami, miecz i pochwa mają poprawione ramy mocowania. Podczas jazdy schowane wyposażenie jest dopasowane osobno, aby nie wchodziło pod grzbiet.
- Gra nadal pokazuje wybraną broń w dłoni: na ziemi zwykłe noszenie, w siodle miecz wzniesiony poza ciało konia. Miecz jest schowany przy wybranym łuku lub podczas odpowiedniego stanu wspinaczki. Nie dodano nowej mechaniki chowania/dobywania broni.

## Jawne zmiany mechaniczne

To nie jest wyłącznie wymiana materiałów lub modeli:

1. Poza stojącego Agro podnosi nominalną wysokość tułowia o 0,12 m i zmienia miękki limit wyprostu nóg z 0,97 na 0,992. Działa to przez istniejącą, wygładzoną wagę idle; cele kopyt i twardy limit 0,995 pozostają. Wysokość kotwicy siodła zmienia się razem z tułowiem. Kości, ich długości, kontroler chodu i zapisane macierze bind nie są przebudowane.
2. `PlayerBow.bow_point` używa tego samego offsetu i wagi dosiadu co render postaci. Kierunek przesunięcia jest osią Y produkcyjnej macierzy tułowia konia. Widoczna cięciwa, celowanie i fizyczny pocisk mają jeden punkt wylotu, także podczas przejść i na pochyłości. Strzały na ziemi zachowują wcześniejszy origin. Nie ma opóźnionego przesuwania samego modelu lecącej strzały.

## Źródła edytowalne

- `art/source/agro_skin_v4.blend` zawiera trzy LOD-y ciągłej skóry i stały szkielet/bindy. Ponowny eksport otwartego zapisanego pliku został porównany z plikami GLB: geometria, UV, normalne, tangenty, wagi, indeksy i macierze bind są zgodne.
- Geometria wodzy znajduje się w `src/horse/agro_reins.gd`; jej 32 trójkąty są liczone osobno od skóry i zachowanych kopyt. Manifest Agro zawiera również pełny koszt runtime z wodzami.
- Dopasowanie do strzemion i faza nogi są w `src/player/traveler_art.gd`, wyposażenie w `src/player/weapon_art.gd`.

## Weryfikacja i ograniczenia

Oddzielne próby obejmują dosiad we wszystkich LOD-ach, pochylenia, przejścia, kopyta, hamowanie, mocowania wyposażenia, strzały przy niskiej ścianie, punkt wylotu, dziedziczenie prędkości, odtworzenie zapisu i różne częstotliwości renderu. Obrazy porównawcze to rzeczywista geometria/poza załadowana w Godocie i wyrenderowana w Blenderze CPU, ze zgodnymi kamerami i oświetleniem. Nie są pomiarem GPU/FPS.

Koń nadal korzysta z uproszczonego, dwusegmentowego szkieletu kończyn. Grzywa i ogon są stylizowane, bez wtórnej symulacji włosia. Wcześniejszy gwałtowniejszy fragment hamowania po kłusie/galopie został odtworzony identycznie w wersji bazowej i pozostaje; nie przedstawiamy tej poprawki jako pełnej naprawy animacji ani pełnego realizmu anatomicznego. Przejście wsiadania pozostaje proceduralnym łukiem, nie animacją motion capture.

Końcowy raport testów, dokładny commit i podpisane hashami porównania są przekazywane oddzielnie z paczką. Wyniku pełnego zestawu nie należy utożsamiać z oceną wyglądu.
