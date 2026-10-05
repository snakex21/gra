# Agro: ciągła siatka wizualna

Zakres: połączona skóra tułowia, szyi, głowy i nóg, osadzone oczy i nozdrza,
ciągła grzywa, warstwowy ogon, dopasowane siodło i pełne wodze. To etap
poprawy stylizowanego modelu gry, nie deklaracja fotorealizmu.

## Co pozostało niezmienione

- `Horse`, `HorseController`, `QuadrupedGait`, `TwoBoneIK` i ich wejścia
- 15 kości i ich pozycje spoczynkowe, animowane transformacje oraz punkty kopyt
- `saddle_transform`, mocowanie jeźdźca, kolizje, komendy, jazda i AI
- Oryginalne modele czterech kopyt we wszystkich trzech LOD-ach
- Oryginalne tekstury i ich ustawienia importu

Nowy `AgroArt` przypina jedną siatkę do istniejącego `Skeleton3D`.
Nie dodaje pętli animacji ani fizyki. Wszystkie trzy LOD-y muszą przejść
walidację; brak lub uszkodzenie zestawu przywraca dotychczasowe sztywne modele.

## Dlaczego osobna poza wiązania

Tylne kości IK mają inną orientację osi niż korpus. Skóra wiązana do
kanonicznego, nieupozowanego szkieletu zapadała się na tych przejściach.
`assets/agro_skin_neutral_reference.json` zapisuje stałą, rzeczywistą neutralną
pozę po 360 krokach produkcyjnego `_pose(1/120)`. Siatka jest rzeźbiona w tej
pozie, a odwrotności tych macierzy są jej bindami. Sama animacja i spoczynkowe
transformacje szkieletu gry nie zostały zmienione. Bindy nigdy nie są liczone
z przypadkowej pozy aktualnego konia przy uruchomieniu.

## Budżet

| LOD | Nowy skin | Zachowane kopyta | Razem | Poprzednio |
|---|---:|---:|---:|---:|
| 0 | 8698 | 784 | 9482 | 9482 |
| 1 | 3980 | 360 | 4340 | 4347 |
| 2 | 1518 | 136 | 1654 | 1676 |

Progi odległości pozostają 0 / 18 / 45 / 1800 m. Cienie nadal ma tylko LOD0.
Nie dodano plików tekstur ani własnych shaderów. Materiały są współdzielone
z dotychczasowymi zasobami Agro. Wyjątek to płytka kopia materiału włosów:
roughness 0,86 i specular 0,22, z tymi samymi obiektami tekstur.
To kontrola geometrii/zasobów, nie pomiar FPS ani pamięci GPU.

## Źródło i odtworzenie

Edytowalne źródło: `art/source/agro_skin_v4.blend`. Zawiera trzy warianty
siatki i spakowane obrazy istniejącej palety. GLB przechowują nazwy materiałów,
a adapter gry przypisuje rzeczywiste materiały istniejącego Agro; zmiana
koloru w samym eksportowanym GLB nie zmienia tej palety w grze.

Generator celowo wymaga jawnej zgody na zastąpienie źródła:

```sh
blender --background --python tools/art/generate_agro_skin.py -- --regenerate
python -m unittest discover -s tools/art -p test_agro_skin_source.py -v
godot --headless --editor --import --log-file /ABSOLUTNA/SCIEZKA/import.log
godot --headless --script tools/art/test_agro_skin_adapter.gd --log-file /ABSOLUTNA/SCIEZKA/test.log
```

Przed regeneracją zachowaj własne edycje pliku Blender. Generator jest
oryginalnym modelem proceduralnym. Fotografia pomocnicza do oceny proporcji:
[Novara Park — The Foxes, conformation](https://www.novarapark.co.nz/the-foxes/conformation/).
Zdjęcie nie jest teksturą ani elementem paczki.

## Dowody i ich granice

`export_agro_skin_preview.gd` odczytuje faktycznie załadowane siatki, Skin,
kości, materiały i tekstury. CPU bake zapisuje ich aktualną deformację do GLB.
`--materials` zachowuje materiały, brak tej opcji daje jawną szarą wersję
oceny kształtu. `--allow-rigid-baseline` jest obowiązkowe dla starej wersji,
`--lod=0|1|2` wybiera poziom, `--rider` używa rzeczywistego montowania jeźdźca.

Transport specular w `complete_agro_specular_transport.py` uzupełnia wyłącznie
zmierzoną wartość materiału w JSON glTF. Bufor geometrii i obrazów pozostaje
identyczny; osobny plik dowodu zapisuje hashe.

Podglądy używają tych samych kamer, światła, koloru, ziarna i ustawień
Blendera Cycles CPU. Są to podglądy eksportu rzeczywistych zasobów i
produkcji pozy/gaitu, nie zrzuty renderera GPU Godota ani nagranie sterowania.
Przepisane prędkości i trajektorie służą porównaniu stanów; podłoże podglądu
jest studyjne. Syntetyczna pochyłość ma jawnie zadane wysokości kontaktu.

Pozostają ograniczenia dwuczłonowych nóg, spłaszczania mięśni przy LBS,
niskopoligonowej nieprzezroczystej grzywy/ogona oraz braku ich wtórnej fizyki.
Końcowe sprawdzenie przejść LOD, cieni i ruchu w rendererze GPU gry wymaga
osobnej sesji. Nie deklarujemy, że zostało wykonane.

Końcowa kontrola sylwetki usunęła boczny guzek przy nasadzie tylnej nogi.
Dwa górne pierścienie uda zostały zwężone i schowane w obrysie zadu;
kości, neutralne bindy, reguły wyliczania wag i mechanika nie zostały przestawione.
Test regresji sprawdza obwiednię bocznego połączenia w neutralnej siatce.
