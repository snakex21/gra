# Chwyt cięciwy prawej dłoni

Uwaga: poniższy opis dokumentuje wydanie `9862e07`. Aktualna korekta całego
łańcucha bark–łokieć–dłoń i wspólnego punktu strzały jest opisana w
[archery_draw_alignment.md](archery_draw_alignment.md); zastępuje wcześniejsze
ograniczenie pozostawienia punktu cięciwy po lewej stronie postaci.

Poprawka względem dokładnej bazy `8a44d13096b2c6455f34aede9a87b398ee8150b9`.

## Co poprawiono

Poprzednio prawa dłoń używała zamkniętego chwytu rękojeści, obróconego wzdłuż
strzały. Osobno narzucana orientacja nadgarstka i nisko prowadzony łokieć
potęgowały nienaturalne załamanie. Ten sam kod dotyczył jazdy i stania.

- Nowa, autorska siatka `Traveler_BowDrawHand_1` pokazuje palce zahaczone o
  cięciwę: wskazujący powyżej strzały, środkowy i serdeczny poniżej; kciuk
  pozostaje z boku. Dłoń nie obejmuje drzewca zamkniętą pięścią
- Oddzielny znacznik `BowStringContact_1` wyznacza kontakt cięciwy. Istniejący
  `HandGrip_1`, zamknięta dłoń do miecza/wodzy i lewy chwyt są zachowane
- IK rozwiązuje przedramię i dłoń jako jeden odcinek do punktu cięciwy, dzięki
  czemu oś nadgarstka jest zgodna z przedramieniem. Łokieć prowadzony jest wyżej
  i do tyłu, odpowiednio do kierunku celowania
- Cztery drobne, autorskie korekty paliczków dopasowują palce do rzeczywistej
  górnej i dolnej gałęzi cięciwy, również przy częściowym naciągu. Nie przesuwają
  strzały ani łuku
- Kształt `ReleaseOpen` rozluźnia palce przy wypuszczeniu strzały. Krótkie
  odprowadzenie dłoni i powrót do pozy spoczynkowej są wyłącznie wizualne
- Widoczność chwytów jest odtwarzana po zmianie broni i poziomu LOD. Wodze
  pozostają przy siodle podczas odprowadzenia dłoni po strzale

Punkt cięciwy, początek fizycznego pocisku, kierunek celowania, lot strzały,
lewy chwyt łuku, mocowanie pochwy oraz rozgrywka pozostają bez zmian.
Dotychczasowy punkt strzały leży poprzecznie względem prawego barku, więc
przedramię nie jest sztucznie ustawiane równolegle do strzały kosztem kontaktu
lub długości kończyny. Poprawka prostuje nadgarstek i prowadzi palce ku cięciwie.

## Źródło i eksport

Dłoń jest edytowalna w `art/source/travelers_v3.blend`; ma własny klucz kształtu
`ReleaseOpen`. W źródłowej prezentacji jest ukryta, aby nie nakładać jej na
zamkniętą dłoń. Eksporter włącza ją, a gra wybiera właściwy chwyt.
`tools/art/archery_draw_hand.py` odtwarza oryginalną siatkę; pełny generator
Wędrowca również korzysta z tego modułu. Nie użyto płatnych ani pobranych modeli.

Eksport edytowanego źródła:

```
blender -b -t 1 --python tools/art/generate_travelers_v3.py -- --export-source --traveler-only
python tools/art/refine_character_materials.py --traveler-only
godot --headless --editor --import
```

Drugi krok zachowuje istniejące wykończenie materiałów. Trzy GLB zawierają tę
samą małą siatkę dłoni, aby zachować kontakt palców i topologię animacji kształtu.
Wszystkie 15 wcześniejszych siatek każdego LOD zachowuje identyczne dane
wierzchołków, indeksów i wag skórowania; wcześniejsze materiały i tekstury są
identyczne z bazą.

## Weryfikacja

```
godot --headless res://tests/bow_draw_hand.tscn
godot --headless res://tests/mounted_bow_socket.tscn
godot --headless res://tests/weapon_art.tscn
godot --headless res://tests/weapon_mounts.tscn
godot --headless res://tests/traveler_surface_checkpoint.tscn
```

Dedykowany test kontroluje kontakt znacznika i odległość rzeczywistych
wierzchołków trzech palców od obu odcinków cięciwy, prosty nadgarstek, rzeczywistą
powierzchnię przedramienia, skończone ortonormalne transformacje, kierunki celowania, wszystkie
LOD, stanie/jazdę, pochylenie konia, kierunki celowania, różne poziomy naciągu,
zwolnienie palców i przywrócenie chwytu miecza. Istniejące testy sprawdzają
rzeczywiste wystrzelenie, zgodność grafiki z fizyką, zapis i odtworzenie.

Materiały porównawcze powstają z faktycznych siatek i póz wczytanych przez
Godota, następnie renderowanych tymi samymi kamerami i światłami w Blenderze
Cycles CPU. Nie są pomiarem FPS, testem GPU ani testem uruchomienia na Windows.
Wyniki konkretnego wydania, w tym znane błędy bazowego zestawu 197 testów,
są dołączone do paczki osobno.

## Granice poprawki

Test kontaktu palców i neutralnego nadgarstka obejmuje skręt celowania od
−1,2 do +1,2 radiana i pochylenie od −0,65 do +0,65 radiana, trzy poziomy
naciągu oraz poziomą i pochyloną pozycję konia. Dalszy przegląd pełnego
obrotu i skrajnego pochylenia kamery ujawnił ograniczenia wcześniejszego
umieszczenia punktu strzały względem barków: przy bardzo stromym celowaniu
w dół dłoń może przecinać oś strzały lub palce mogą odstawać od cięciwy.
Korekty palców są ograniczone, aby nie rozciągać dłoni bez kontroli.
Ta paczka nie przebudowuje tułowia, barków ani fizycznego punktu strzały
i nie deklaruje pełnej poprawności anatomicznej skrajnych kierunków.
