# Materiały Valusa, Gaiusa i Pelagii

Etap bazuje na `d0569c3aee1af97c9b19d868c840201a158bfedd` (materiały Wędrowca i Agro).

## Co trafia do gry

Adapter `ColossusArtV3` wybiera nowy, odizolowany materiał wyłącznie dla identyfikatorów
`valus`, `gaius`, `pelagia`. Ten sam wybór obejmuje wszystkie trzy istniejące LOD-y
oraz istniejącą warstwę odblokowywanej wełny. Inne profile nadal używają oryginalnego
atlasu. Nie zmienia się żaden GLB, siatka, szkielet, UV, skinning, animacja, kolizja,
chwyt, punkt wspinaczki, AI, kooperacja ani mechanika.

- Valus: zróżnicowane warstwy zwietrzałego kamienia, drobne ubytki i grubiej
  rozdzielone pasma wełny
- Gaius: ślady obróbki i mineralne spękania kamienia, włókna oraz stonowane
  starzenie brązowych okuć
- Pelagia: erozja wodna, nierównomierny osad na kamieniu, rozdzielone ciemne włókna
  i utlenione ornamenty

To etap materiałów, nie pełna przebudowa postaci: nie usuwa uproszczeń sylwetek,
twarzy ani zaokrąglonych brył. Same tekstury nie gwarantują realistycznego wyglądu.

Zmiany są w kolorze, normalnych i przestrzennej szorstkości powierzchni. Średnie
kolory zachowują dotychczasową tożsamość. Tylko kafle okuć 11 i 13 otrzymują
niewielką, nierównomierną metaliczność. Nie dodano emisji ani nowych shaderów.

## Izolacja i ważne wyjątki

Oryginalne `materials/colossi_v3/atlas.tres`, oba obrazy `textures/colossi_v3/` oraz
wszystkie modele pozostają bez zmian. Nie modyfikuje się zasobów współdzielonych
przez `Asset.mesh_for` ani materiałów powierzchni siatek. Nowe zasoby są w
`materials/colossi_material_finish/` i `textures/colossi_material_finish/`.

Kafle 9 i 15 (oczy) oraz 10 (ozdoby Valusa i czytelne zęby sterujące Pelagii)
zachowują dokładne piksele koloru i normalnych. Nie zmieniono istniejących sigili,
podświetleń, obrażeń, zębów sterujących ani ostrzeżeń. Kwantyzacja nowej mapy
szorstkości daje na niezmienianych kaflach 217/255 zamiast wcześniejszej stałej 0,85;
metaliczność tych kafli wynosi zero. Siła normalnych 0,6, filtrowanie, odległości
LOD, warstwy i flagi cieni pozostają takie jak wcześniej. Devil nie używa nowego
materiału; jego chronione cienie skrzydeł nie są przedmiotem tego etapu.

Istniejące siatki LOD1/2 mają miejscami dryf UV na sąsiednie kafle. Zachowujemy te
siatki, zamiast zmieniać geometrię w etapie materiałowym. Stan pancerza Gaiusa ma
wcześniejszą niespójność wizualną: operuje na pierwotnej bryle, zasłoniętej przez
rzeźbę V3, a reset może przywrócić jej widoczność. Ten etap nie naprawia tego
zachowania; test porównuje je z bazą i nie deklaruje nowej poprawności pancerza.

## Odtworzenie

`python tools/art/refine_colossus_materials.py` tworzy deterministycznie trzy PNG
z oryginalnego atlasu. Wymaga numpy i Pillow. `--check` sprawdza dokładne bajty.
`python -m unittest discover -s tools/art -p 'test_colossus_material_finish.py' -v`
sprawdza izolację kafli, normalne, rozmiary, rzeczywiste zmiany struktury,
metaliczność i deterministyczny wynik. Geometrii nie trzeba eksportować ponownie.

## Granice dowodów

Podglądy to rzeczywiste modele, materiały i transformacje wyeksportowane z Godota,
a następnie renderowane w Blenderze na CPU przy identycznej kamerze i świetle.
Nie są obrazami wygenerowanymi AI ani zrzutami renderera GPU Godota. Przechodzenie
między LOD-ami w ruchu, końcowa kompresja i liczba FPS wymagają kontroli GPU.
Trzy dodatkowe tekstury 2048² są współdzielone przez trzy wybrane profile. To
świadomy koszt pamięci GPU, którego ten test CPU nie mierzy; nie dodano draw calli
ani geometrii. Import zachowuje mipmapy i kompresję VRAM.
