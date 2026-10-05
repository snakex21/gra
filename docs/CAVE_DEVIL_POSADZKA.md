# Cave i Devil: mineralne detale istniejącej posadzki

Baza: `d5d654cfb80b8027b5ec4b05fc48ad9348a9d6d4`.
Zmiana dotyczy tylko oprawy kampanii układu 5.

## Sposób integracji

Podłoga jest częścią połączonych modeli Hollowvault: jedna wielka komora
oraz dwanaście odcinków tunelu. Wszystkie trzy jawne LODy mają własne,
sprawdzone UV. Nie dodano drugiej podłogi, nie rozdzielono siatek i nie
nałożono jednolitego materiału ziemi na sklepienia.

Nowy materiał jest lokalnie przypisany do tych 39 instancji LOD w każdej
arenie. Reużywa jeden atlas i zachowuje ustawienia oryginału. Wariant zmienia
wyłącznie region soil, zachowując inne kafle oraz oryginalny atlas bibliotek.
Deeprelic, nacieki, dekoracje, kolizje, światło i geometria pozostają bez zmian.

Ładowanie atlasu jest asynchroniczne. Wybór modeli odbywa się dopiero po
wykonaniu wcześniejszych zadań oprawy; słaby uchwyt zabezpiecza wyładowanie
areny w czasie oczekiwania. Cave i Devil reużywają ten sam materiał i teksturę.
Układy 1–4 oraz samodzielne próby nie wywołują nowej warstwy materiałowej.

Teksturę opracowano proceduralnie własnym kodem. Bez ImageGen, zewnętrznych
obrazów i modeli. Nie zmieniono AI, kooperacji, wody, wspinania ani zapisu/replay.

## Podglądy i granice sprawdzenia

Pary przed/po pochodzą z rzeczywistych scen budowanych przez Godot,
renderowanych w Blender Cycles CPU z tą samą kamerą, profilem Balanced,
geometrią, UV i LOD. Oświetlenie podziemne jest tłumaczeniem parametrów gry;
bez dodanego słońca przechodzącego przez sklepienie. Podgląd nie obejmuje
postaci, aktywnej latarni, mgły, walki ani działania kamery kolizyjnej.
To nie są zrzuty z Godota i nie dowodzą kosztu GPU ani liczby FPS.

Dokładne wyniki audytu UV/atlasu, testów funkcjonalnych i pełnego zestawu
regresji znajdują się w raportach dołączonych do paczki.

## Usunięcie istniejącego zasłaniania posadzki

Audyt sceny wykazał, że dotychczasowy dysk podpierający arenę zasłaniał
posadzkę komory i nakładał się na posadzki tunelu. Sam atlas nie wystarczał.
Dlatego tylko materiał górnej powierzchni tego dysku odrzuca piksele pod
sprawdzoną, istniejącą podłogą: elipsa 22×28 m promieni oraz tunel o połowie
szerokości 5,5 m od z=29,55 do 167,95 m. Obwód, przerwa przed tunelem oraz
zewnętrzne podłoże zachowują oryginalny wygląd. To maska materiału, bez
wycinania siatki i bez zmiany kolizji.

Maska włącza się dopiero po sprawdzeniu wszystkich 39 prawidłowych instancji
LOD. Poza 740 m pozostaje pełne podparcie wizualne, zanim jawne LODy podłogi
znikną przy 800 m. Nie zmieniono żadnego wierzchołka ani światła.

Wariant atlasu zachowuje dokładnie także poziomy mip4–10 i skompresowane
bloki poza soil na mip0–3. Dzięki temu szczegóły posadzki nie przeciekają
na sklepienie w oddali. Zachowano makrokolor ziemi; zmieniają się lokalne
ziarna mineralne, osad i delikatne ciemniejsze żyłki.

Blender czyta źródłowe PNG i używa własnego filtrowania tekstur. Nie odtwarza
piksel w piksel kompresji S3TC ani wyboru mipmap Godota. Oddzielny test
porównuje rzeczywiste zaimportowane dane S3TC. Testu sprzętowego GPU nie wykonano.

Przy niemal poziomym spojrzeniu (cosinus względem normalnej ≤0,001) podparcie
pozostaje pełne. Ten margines uwzględnia 0,233 mm różnicy wysokości po imporcie
siatki, aby także swobodna kamera nie ujawniła szczeliny przy skrajnie płaskim
kącie patrzenia. Zwykłe kamery gracza nie zmieniają w tym miejscu zachowania.
