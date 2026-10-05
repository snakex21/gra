# Wędrowiec: ciągła siatka barku i ubrania

## Zakres

Ten etap naprawia wadę poprzedniej wersji: oddzielny, sztywny rękaw odsuwał się od tułowia podczas pozowania. Samo zachowanie prawidłowych punktów chwytu nie sprawdzało tej wady. Nowa tunika i oba rękawy są jedną połączoną powierzchnią z rzeczywistym przejściem przez pachę. Skóra ramion jest ciągła przez łokcie.

Usunięto również wykryte przenikanie górnych części spodni przez dolną tunikę. Zmieniono przekroje klatki i talii, proporcje widocznego barku, połączenie szyi z kołnierzem, dopasowanie zdobień, górę spodni, przyczep peleryny oraz bryłę buta z podbiciem, niskim noskiem i płaską podeszwą. To nadal postać stylizowana. Nie jest to deklaracja jakości fotorealistycznego modelu z referencji.

## Dwa niezależne układy

Istniejące węzły Arm, Forearm, Wrist, HandGrip, Leg, Knee i Ankle nadal obsługują te same punkty chwytu, broń, jazdę oraz logikę ruchu. Ich nazwy i pozycje wiązania pozostają zachowane. Kontroler gracza i jego collider nie zostały zastąpione.

Osobny szkielet kosmetyczny ma 19 kości: korpus, po trzy podstawowe na stronę (ramię, przedramię, nadgarstek), dwie kości dolnej części tkaniny podążające za istniejącymi biodrami oraz dziesięć lokalnych kości korygujących pachę i przedni/tylny fałd rękawa. Każda korekta powtarza obrót swojej kości bazowej i dodaje ograniczone przesunięcie zależne od uniesienia ramienia. Przedni i tylny fałd dostają wyłącznie korektę głębokości przy uniesieniu; w neutralnej pozycji ta korekta jest zerowa. Korekty nie zmieniają punktów logicznych ani siatki przy mankiecie. Jest sterowany po końcowym IK ekwipunku. Kierunek zginania kosmetycznego łokcia jest odczytywany z istniejącego łokcia, z ustalonym kierunkiem awaryjnym przy współliniowości. Sam dokładny punkt dłoni nie dowodzi prawidłowej płaszczyzny łokcia.

Węższy widoczny bark nie przesuwa dłoni: kosmetyczne IK odczytuje końcowy, istniejący punkt nadgarstka. W skrajnych pozach wymaga to ograniczonego wydłużenia wyłącznie widocznej kończyny. Maksimum dopuszczone przez sterownik wynosi 20%; rzeczywiście zmierzone wartości należy odczytać z raportu danej wersji.

Pozycje kości i współczynniki lokalnych korekt są jawnie zapisane w `assets/travelers_v3_manifest.json`, w `surface_rig_contract`. Sterownik sprawdza zgodność z importowanym szkieletem. Kości kosmetyczne są rodzeństwem pod SurfaceBody, aby skala podłużna nie tworzyła ścinania przez skalowanego rodzica. Nadgarstek kopiuje również orientację starego punktu, a nie tylko jego położenie.

Poza wiązania nowej siatki ma ramiona rozłożone w T. Oddzielono ją od niezmienionej pozy wiązania starego logicznego riggu. Nie wymaga to obracania powierzchni pachy o pełne 171° od opuszczonych rąk. Pozycja wiązania i wagi nie zastępują kontroli obrazów: połączona topologia może nadal mieć złą objętość, szczypanie lub przecięcia.

Dolna część tuniki i górne części spodni korzystają ze wspólnego, płynnego pola wag. Talia spodni pozostaje z korpusem, a ich dolne końce dokładnie podążają za starymi nogami przy kolanach. Same siatki ud przeniesiono pod szkielet kosmetyczny; węzły Leg/Knee/Ankle zachowały rodziców i pozycje. Dolna część tuniki poniżej pasa płynnie podąża za istniejącymi kośćmi nóg, zamiast pozostawać sztywną rurą przecinaną przez uda. Jej dwie kości kosmetyczne odczytują końcowe transformacje oryginalnych Leg_0/Leg_1; nie sterują nogami ani colliderami. Przednie zdobienie porusza się z tkaniną, a osobna peleryna pozostaje sterowana korpusem. To skinning ubrania, nie symulacja tkaniny.

## Zgodność zapisu gry

W `src/game/world_snapshot.gd` dodano jawne pomijanie całego poddrzewa TravelerArt podczas zapisu pochodnego stanu wizualnego. Wcześniej pomijany był sam adapter, ale nowy szkielet i sterownik pod nim trafiały do zapisu z nazwą zależną od LOD. Po odtworzeniu innego LOD te ścieżki nie istniały. Oryginalny PlayerVisual, ramiona/chwyty poza tym poddrzewem i stan symulacji pozostają w dotychczasowym systemie zapisu. Nie dodano ogólnego ignorowania brakujących ścieżek.

## Edytowalne źródło

- `art/source/travelers_v3.blend`: oryginalna scena Blender z kosmetycznym szkieletem i grupami wag
- `tools/art/generate_travelers_v3.py`: główny generator
- `tools/art/traveler_body_surface.py`: autorska ciągła powierzchnia, wagi i bryła obuwia
- `src/player/traveler_surface_pose.gd`: wizualny sterownik skina
- `art/scripts/traveler_visual_import.gd`: jawne ustawienia połysku skóry i włosów po imporcie Godota

Regeneracja Wędrowca bez eksportowania modeli Mono:

```sh
blender --background --python-exit-code 1 --python tools/art/generate_travelers_v3.py -- --traveler-only
python tools/art/refine_character_materials.py --traveler-only
godot --headless --path . --editor --import
```

Ponowny eksport ręcznie edytowanego źródła, bez jego nadpisania:

```sh
blender --background --python-exit-code 1 --python tools/art/generate_travelers_v3.py -- --export-source --traveler-only
python tools/art/refine_character_materials.py --traveler-only
```

Scena Blender pokazuje dłonie i owijki w pozie T przez jawnie oznaczone kopie `Studio_T_*`. Dzielą dane siatki z oryginalnymi dłońmi/owijkami, więc edycja wierzchołków pozostaje wspólna. Ich transformacje służą tylko widokowi autorskiemu; obie ścieżki eksportu je pomijają. Oryginalne części nadal mają niezmienionych rodziców Wrist/Forearm i są przywracane do eksportu. Niezgodny ręcznie zmieniony kontrakt jest zgłaszany jako błąd i wyłącza sterowanie kosmetycznym skinem; nie ma ukrytego przełączenia na stary model. W takim przypadku może pozostać widoczna surowa poza wiązania i trzeba poprawić źródło/manifest przed użyciem.

Sam surowy GLB zawiera dwa układy wiązania; prawidłową kompletną pozę gry pokazuje adapter Godota, a nie przypadkowy podgląd GLB bez sterownika.

Zmiana pozycji wiązania kości wymaga świadomego zaktualizowania kontraktu w manifeście i ponownej weryfikacji. Sam eksport siatki nie zatwierdza nowego kontraktu. Zewnętrzny etap wykończenia materiałów należy wykonać ponownie po eksporcie.

## Poziomy szczegółowości

Dolny brzeg tuniki pozostaje otwarty, z cienkim zawinięciem, zamiast pełnej płaskiej zaślepki. Zawinięcie ma oddzielone normalne od zewnętrznej tkaniny oraz płaskie normalne swoich małych ścian, dzięki czemu jego skierowane w dół normalne nie psują oświetlenia zewnętrznego brzegu podczas jazdy. Uproszczenie siatki zachowuje granice skóry ramienia oraz wspólnie odkształcane pasy rękawa przy mankiecie. Kontrola eksportu porównuje pozycje i nazwane wagi tych chronionych wierzchołków. Tunika zachowuje co najmniej 52% bazowych trójkątów, ponieważ agresywne uproszczenie reszty korpusu może zniszczyć sylwetkę mimo zachowanych mankietów. Pozostałe niechronione części Wędrowca są w najniższym LOD redukowane do 7%, zamiast 12%, aby zmieścić cały model w istniejącym limicie 5000 trójkątów. Obie niewielkie siatki ud (po 388 trójkątów) pozostają identyczne we wszystkich LOD. Zachowuje to próbkowanie wspólnej deformacji przy talii, obu brzegach podwinięcia i kolanach. Pozostałe drobne części mają zmienioną triangulację dalekiego LOD; nie oznacza to zmiany ich oryginalnych punktów chwytu ani formy modelu LOD0. Ostateczny budżet trzeba sprawdzić po eksporcie; sam współczynnik redukcji nie gwarantuje liczby trójkątów.

Eksport Wędrowca dopuszcza do ośmiu wpływów kości na wierzchołek. Bazowy skin może mieć pięć wpływów w lokalnym przejściu fałdu, a upraszczanie siatki może łączyć różne zestawy. Zachowanie ośmiu wpływów zapobiega odrzucaniu istotnych wag na niższych LOD. Zwiększa to koszt skinningu części powierzchni; nie jest to obietnica wzrostu FPS. Przed eksportem sprawdzana jest suma wag i limit ośmiu. Import JOINTS_1/WEIGHTS_1 oraz wypieczenie wszystkich ośmiu wpływów sprawdzono na Godot 4.6.3. Wynik uwzględnia kwantyzację wag przez importer.

## Jak powstają obrazy kontrolne

Eksporter pobiera rzeczywiste instancje załadowane przez Godota i końcowe pozy po IK. `skin_snapshot_baker.gd` zapisuje odkształcone pozycje, normalne i styczne zgodnie z liniowym skinningiem renderera Godot 4.6. Nie wystarczy skopiować ArrayMesh: taka kopia pokazałaby błędnie pozę wiązania.

Raport zapisuje oryginalne i wypieczone tablice, macierze wiązania, bieżące pozy kości, materiały i sumy kontrolne. Nieobsługiwane blend shapes lub modyfikatory są odrzucane zamiast pomijane. Materiały są prywatnymi kopiami na potrzeby eksportu; instancje gry i współdzielone zasoby pozostają bez zmian.

Obrazy Blender Cycles CPU są diagnostycznym podglądem danych gry. Nie są zrzutami działającego renderera GPU ani pomiarem FPS, VRAM czy wszystkich możliwych przecięć. Prócz testów kodu należy obejrzeć neutralny przód/bok/tył, pełne uniesienie ramion, ujęcia asymetryczne, ugięte łokcie, nadgarstki, broń, wspinanie i jazdę. Porównanie tej poprawki powinno używać ostatnio dostarczonej wersji `4cea8a4`, tej samej pozy, kamery i światła.

## Podstawa konstrukcji

Siatka została napisana od nowa w repozytorium. Nie pobrano modeli, tekstur ani elementów gry z referencji i nie użyto generowania obrazów. Materiał referencyjny użytkownika służył do oceny kierunku oraz proporcji, nie do deklarowania identycznej jakości.

Publiczne materiały anatomiczne użyte do sprawdzania konstrukcji:
- [Proko: kości obręczy barkowej](https://www.proko.com/course-lesson/anatomy-of-the-shoulder-bones)
- [Proko: naramienny, budowa i forma](https://www.proko.com/course-lesson/how-to-draw-deltoids-anatomy-for-artists/)
- [Proko: mięśnie piersiowe i forma](https://www.proko.com/course-lesson/how-to-draw-pecs-anatomy-and-form/)
- [Proko: przeciętne proporcje postaci](https://www.proko.com/course-lesson/human-proportions-average-figure)
- [SELF: fotografia koszulki przy uniesionych rękach, użyta wyłącznie do obserwacji układu tkaniny](https://www.self.com/story/how-to-remove-armpit-stains-on-white-shirts)

Proporcje podręcznikowe są pomocą porównawczą, a nie obowiązkowym kształtem każdej osoby. Przywiązanie do liczby „głów” nie zastępuje oceny całej sylwetki.
