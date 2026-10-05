# Worm i Saru — materiały oryginalnego podłoża

Etap dla kampanii z układem świata 5. Bez zmiany geometrii, colliderów, logiki walk, modeli postaci ani dotychczasowego wystroju. Układy 1–4 i sceny prób bez oprawy zachowują wcześniejszy wygląd.

## Zakres

- Worm: jeden istniejący Ground; zwarta ziemia z mineralną skorupą, pyłem i drobnym kruszywem. Trzy rezonujące płyty i sześć znaczników pozostają nietknięte.
- Saru: dwa istniejące brzegi Ground; ochrowy granit z jasnymi porostami. Oddzielny materiał chłodnej skały i osadu na ChasmFloor. Przepaść pozostaje otwarta na szerokości 70 m; dno pozostaje 22 m poniżej brzegów.
- Rampy, galerie, cały SaruBridge, złote przeciwwagi, sygnały i przynęty nie są celem tego etapu.

Dziewięć oryginalnych map 512×512 (albedo, normal, roughness), opracowanych deterministycznie przez NumPy/Pillow. Bez zewnętrznych zdjęć i bez generowania obrazów przez AI. Trzy zestawy zajmują łącznie 1 640 893 bajty plików PNG. Wymiary powtórzeń: Worm 14 m, brzegi Saru 16 m, dno 18 m. Lokalna projekcja triplanarna obsługuje pozbawione UV siatki Saru, pozostając związana z areną po obrocie/przesunięciu w kampanii. Normalne dotyczą wyłącznie oświetlenia; brak displacement i parallax.

## Izolacja

ArenaGroundMaterials przypisuje nowe material_override istniejącym, ściśle wybranym siatkom. Nie zmienia istniejącego wspólnego kamienia Saru, używanego również przez rampę i galerie. Wybór Worm sprawdza wymiary i transformację oryginalnego pudełka/dysku. Wybór Saru dodatkowo sprawdza pełne skróty tablic siatek, nazwę, warstwę kolizji, transformację i widoczność. Zmieniona w przyszłości geometria nie zostanie automatycznie pokryta materiałem: pozostanie wcześniejszy materiał do czasu świadomego audytu i aktualizacji odcisków.

Materiały są współdzielone i ładowane przez istniejącą kolejkę. Zadania przypisania używają WeakRef, aby bezpiecznie obsłużyć rozładowanie areny przed zakończeniem kolejki. Dwukrotne wykonanie nie dodaje węzłów.

## Powtarzalna weryfikacja

- python tools/art/generate_worm_saru_materials.py --check
- python tools/art/generate_arena_ground_materials.py --check
- godot --headless --path . --script res://tests/arena_worm_saru_materials.gd
- tools/run_tests.sh
- python tools/art/capture_worm_saru_arena_previews.py OUTPUT --baseline-root BASELINE

Podglądy to rzeczywisty eksport scen Godot do Blender Cycles na CPU, z tą samą kamerą i światłem przed/po. Pokazują pełną istniejącą scenę oraz detal podłoża. Nie stanowią pomiaru FPS ani weryfikacji obrazu renderera Godot na GPU. Wyniki uruchomień, znane ograniczenia i skróty plików znajdują się w raporcie dostawy.
