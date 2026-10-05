# Skały, ruiny i roślinność w trzech arenach

Kontynuacja oprawy mapy po paczce „Materiały i sylwetki czterech aren”. Nowe modele są rzeczywiście wywoływane przez `GameWorld._dress_arena` w kampanii układu 5. To nie jest osobna wystawa modeli.

## Charakter miejsc
- Quadratus: przerwane grzbiety i skalne okapy, fragmenty ścian oraz żłobione kolumny; niskie rozety i płożące krzewy przy podstawach
- Phaedra: pochylone warstwy skalne, łuki i suche fontanny na obrzeżach łąki; kwieciste poduszki i płożące krzewy. Tunele i ich podejścia pozostają wolne
- Avion: otoczaki i warstwowe skały, fragmenty nadbrzeżnej architektury, trzciny i niskie kwiaty na płaskim brzegu. Woda, wieże, tor lotu oraz wejście pozostają bez zmian

Rozmieszczenie jest zapisane w czytelnym `CONFIG` skryptu `src/world/arena_variety_dressing.gd`. Sześć asymetrycznie rozmieszczonych skupisk w każdej arenie ma większe sylwetki i niższy roślinny fartuch. Parametry są deterministyczne; nie ma losowania co klatkę.

Łącznie: 635 nowych instancji, w tym 72 większe skały i fragmenty ruin. Quadratus i Phaedra mają po 216, Avion 203. Nie dodano kolejnego osobnego katalogu do zwiedzania.

## Granice i koszt
Cały prostokątny obrys każdego obiektu (suma obrysów wszystkich trzech LOD) jest sprawdzany, nie tylko jego środek. Dodatki pozostają poza strefą walki o promieniu 96 m / 88 m / 119 m i poza ciągłym pasem wejściowym o szerokości 48 m. Maksymalny zasięg skupisk to 167 m / 164 m / 167 m. Nie dodano kolizji ani zmiany wysokości terenu. Dodatkowa kontrola pełnych obrysów zostawia 25 cm odstępu od istniejących klifów, drzew i wysokich przeszkód. Dane `data/environment/arena_variety_clearance.json` pochodzą z rzeczywistych kolizji aren. Po świadomej zmianie bazowej scenografii należy je ponownie wyeksportować i uruchomić niezależny test; brak lub błędny plik blokuje nową warstwę zamiast ignorować prześwity.

Materiały: jedna oryginalna paleta 64×64, współdzielona przez cały nowy zestaw. Geometria jest importowana raz i współdzielona przez MultiMesh. Istnieją trzy autorskie LOD-y z tym samym środkiem obrysu, oddzielnymi przedziałami widoczności i zerową histerezą. Skały/ruiny zachowują liczebność we wszystkich profilach; roślinność stosuje istniejące progi 35% / 65% / 100%. Profil zmienia widoczność, nie pozycje. Budowa jest rozłożona na małe zadania kolejki; po usunięciu areny nie kontynuuje tworzenia węzłów.

Nie zmieniono zapisu, replay, AI, kompana, fizyki, nawigacji, wejść, zachowania bossów ani samodzielnych prób. Układy 1–4 nie dostają nowej warstwy. To dekoracja skraju, a nie nowe wspinaczkowe lub interaktywne obiekty.

## Weryfikacja
Wyniki końcowe i budżety zawiera raport dołączony do paczki. Testy headless mierzą deterministyczność, fizykę i obrysy, wybór LOD oraz koszt geometrii, nie FPS ani czas GPU. Porównania PRZED/PO pochodzą z rzeczywistych scen Godota eksportowanych do Blendera i renderowanych na CPU. Zachowują tę samą kamerę, oświetlenie i profil Balanced. Nie są zrzutami uruchomionej gry; nie pokazują postaci, mgły ani aktywnej walki.

## Testy lokalne

    godot --headless --editor --path . --import
    python tools/art/test_nature_variety_assets.py
    godot --headless --path . --script tests/arena_variety_dressing.gd

Nazwy poleceń i plików wynikowych należy sprawdzić w końcowej instrukcji paczki.

## Ponowny zapis prześwitów po świadomej edycji starej scenografii

Zachowaj kopię `arena_variety_clearance.json`, potem uruchom:

    godot --headless --path . --script tools/art/bake_arena_variety_clearance.gd -- --regenerate

Bez `--regenerate` narzędzie nic nie zapisuje. Zbiera obrysy rzeczywistej starej scenografii, z wyłączoną wyłącznie nową warstwą. Po zapisie obowiązkowo uruchom test całej integracji i obejrzyj rozmieszczenie; nowy klif może usunąć dekoracje z danej grupy.
