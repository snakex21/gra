# Wędrowiec: przebudowa bryły i spokojniejszy materiał

To oryginalna, stylizowana postać do gry. Ten etap poprawia konkretne kształty,
ale nie należy przedstawiać go jako fotorealizmu ani jako dowodu osiągnięcia
pełnego realizmu. Ostateczny charakter nadal jest uproszczony, zwłaszcza dłonie,
uszy, stawy sztywnych segmentów i krój ubrania.

## Zmienione elementy

- Ciągła powierzchnia twarzy: nos, policzki, broda, przejście ust oraz powieki
- Mniejsza proporcja głowy, szersza nasada szyi i mniej wystająca dolna powieka
- Włosy dopasowane do rzeczywistego przekroju czaszki, z płytkimi nierównymi grupami
- Fałdy i kompresja tuniki przy pasie; odsunięcie tkaniny od powierzchni pasa
- Usunięte stałe kuliste/poduszkowe wstawki barków, spłaszczona główka rękawa
- Węższy, mniej bulwiasty profil butów
- Niższy odbłysk skóry i włosów, sprawdzany na załadowanych materiałach Godot

Nie zmieniono nazw ani transformacji węzłów, punktów chwytu broni, długości
segmentów rig-u, colliderów, ruchu, wspinania, konia ani logiki AI/kooperacji.
Rig jest hierarchią sztywnych części; nie ma tu wag skórkowania do przebudowy.
Zmiana wizualnej wysokości głowy nie zmienia kapsuły rozgrywki.

## Źródło i odtwarzanie

Edytowalny plik: `art/source/travelers_v3.blend`. Generator:
`tools/art/generate_travelers_v3.py`. W pliku źródłowym pozostaje również Mono;
flaga poniżej pozostawia jej istniejące pliki wykonawcze bez zapisu.

    blender --background --python-exit-code 1 --python tools/art/generate_travelers_v3.py -- --traveler-only
    python tools/art/refine_character_materials.py --traveler-only
    godot --headless --path . --editor --import

Po ręcznej edycji źródła można wyeksportować sam model Wędrowca, nie regenerując
ani nie zapisując ponownie `.blend`:

    blender --background --python-exit-code 1 --python tools/art/generate_travelers_v3.py -- --export-source --traveler-only
    python tools/art/refine_character_materials.py --traveler-only

Nie użyto pobranych modeli, tekstur postaci z innych gier ani AI do tworzenia
obrazów. Źródło wygenerowano w Blenderze 4.3.2. Dawny `.blend` pochodził z nowszej
wersji; dlatego źródło odtworzono generatorem, a nie zapisano z ostrzeżeniem o
utracie danych po otwarciu starszym Blenderem. Wynik i rig sprawdzano osobno.

Konstrukcyjne odniesienie dydaktyczne, bez użycia cudzych modeli ani obrazów
w grze: [Proko — anatomia i konstrukcja oka](https://www.proko.com/course-lesson/how-to-draw-eyes-anatomy-and-structure).

## Ważny szczegół importu

Godot 4.6.3 nie zachował w tym projekcie `KHR_materials_specular` z GLB.
`art/scripts/traveler_visual_import.gd` ustawia jednorazowo podczas importu
wyłącznie `metallic_specular`: skóra 0,24, włosy 0,16. Trzy `.glb.import` mają
wskazany ten skrypt. Nie jest to mutacja materiałów w każdej klatce ani zmiana
logiki gry. Bez prawidłowego podpięcia importera sam parametr w Blenderze nie
jest dowodem efektu w Godot.

Instalator paczki zachowuje istniejący UID i pozostałe ustawienia importu.
Zmienia tylko pustą wartość `import_script/path`; przy innym własnym importerze
zatrzymuje się i wymaga ręcznego scalenia. Zamknij Godot przed instalacją.

## Koszt i granice dowodów

Limity siatki pozostają 40 000 / 22 000 / 5 000 trójkątów dla LOD0/1/2.
Dokładne liczby i rozmiary są w `assets/travelers_v3_manifest.json`.
Oddzielenie skóry zwiększa liczbę powierzchni z 15 do 21 na postać i LOD,
z dwóch do trzech materiałów. To sześć potencjalnych dodatkowych wywołań
rysowania, nie zmierzona liczba FPS. Piksele i rozdzielczości atlasów nie rosną.

Porównania eksportują rzeczywiście załadowane adaptery Godot, ich widoczną broń,
aktualne materiały i globalne transformacje. Cycles CPU liczy te modele przy
stałych kamerach/światłach. Są to zamrożone próbki póz, nie zrzuty klatki z GPU
Godot. Osobno wykonuje się testy rig-u, chwytów, broni, wspinania, konia/jeźdźca,
przełączeń LOD i skończonych transformacji w próbkach całych cykli póz.

Natywny eksport Godot również pomija parametr odbłysku. Narzędzie
`complete_character_specular_transport.py` przenosi go wyłącznie z zapisanej
wartości faktycznego materiału Godot do standardowego pola GLB. Nie modyfikuje
binarnego bloku geometrii/obrazów i zapisuje dowód z sumami kontrolnymi.
Renderer nie domalowuje materiałów ani nie rekonstruuje postaci.

Testy CPU i kontrola przykładowych widoków nie dowodzą braku wszelkich przenikań
w każdej klatce ani wydajności GPU. Podgląd nie zastępuje sprawdzenia gry na
komputerze docelowym. Wyniki pełnego zestawu i znane błędy bazowe są dołączane
jako osobny raport końcowej paczki; nie wolno opisywać częściowych testów jako
pełnego zielonego wyniku.
