# Pochwa przy lewym biodrze

Poprawka po wydaniu `9ee3d29b0283cde64053943a9d6d33ab2b0fd81d` dotyczy rzeczywistego mocowania w grze. `WeaponArt._scabbard_carry_frame()` wyznacza wspólną transformację pochwy i schowanego miecza. Dwa skórzane paski nadal łączą istniejący pas z rzeczywistymi mosiężnymi pierścieniami w zaimportowanym modelu.

## Ułożenie

- Płaska powierzchnia pochwy biegnie wzdłuż boku postaci. Jelec jest skierowany w przód i w tył, zamiast wchodzić poprzecznie w tunikę
- Wylot jest przy pasie, a pochylenie na pieszo jest mniejsze niż w poprzednim wydaniu
- Schowany miecz i pochwa zawsze używają tej samej skali i transformacji. Nie przesunięto ostrza względem otworu pochwy
- Podczas prawego lub przedniego wsiadania/zsiadania pochwa wykonuje krótki ruch kosmetyczny, aby ominąć siodło, uniesioną nogę, szyję i wodze. Ruch wraca dokładnie do zwykłego ułożenia na końcach przejścia
- Przy przednim wejściu/wyjściu dodatkowe załamanie lewej wodzy płynnie zmienia ugięcie; punkty przy wędzidle i dłoni/siodle oraz pierwotny środkowy punkt i dotychczasowe wygładzanie końców pozostają bez zmian. Dodano osiem trójkątów wyłącznie do tej skórzanej taśmy. Dotyczy to także prawdziwego zsiadania, gdy koń zwalnia już odniesienie do jeźdźca
- Zwykłe wejście/wyjście z lewej i od tyłu zachowuje podstawowe mocowanie

Nie zmieniono modeli, tekstur ani długości miecza. Plik źródłowy `art/source/weapons_v4.blend` oraz pliki GLB pozostają identyczne z bazą. Pozycję ekwipunku w czasie gry ustala adapter Godota; zapisany w Blenderze układ prezentacyjny nie zastępuje tego adaptera.

## Granica kosmetyki

Bez zmian pozostają ścieżki ruchu i kolizje gracza oraz Agro, punkty rozgrywki, logika walki, fizyczny punkt wystrzału łuku, kierunek i prędkość strzały, zapis gry oraz format powtórki. Poprawka nie dodaje hitboxa ekwipunku.

Podglądy powstają z załadowanych przez Godota siatek i aktualnych transformacji, ze skórą i morfami wypieczonymi z bieżącej pozy. Blender dodaje zgodne kamery, światła i podłogę. Nie przesuwa pochwy na potrzeby obrazka. Są to podglądy Blender Cycles, nie zrzuty renderera GPU Godota ani pomiar FPS.

## Kontrole

Test `weapon_mounts` obejmuje LOD0/1/2/0, połączenia pasków i pierścieni, widoczność pustej pochwy, wspólną transformację schowanego miecza, cztery kierunki wsiadania i zsiadania, ciągłość mocowania, końce i ugięcie wodzy oraz szybką zmianę broni. `mounted_bow_socket` sprawdza m.in. zgodność widocznej strzały z rzeczywistym punktem wystrzału i trafienie w niską przeszkodę.

```sh
godot --headless --path . --log-file /tmp/weapon_mounts.log res://tests/weapon_mounts.tscn
godot --headless --path . --log-file /tmp/mounted_bow_socket.log res://tests/mounted_bow_socket.tscn
godot --headless --path . --log-file /tmp/weapon_art.log res://tests/weapon_art.tscn
godot --headless --path . --log-file /tmp/rider_seating_fit.log res://tests/rider_seating_fit.tscn
godot --headless --path . --log-file /tmp/traveler_checkpoint.log res://tests/traveler_surface_checkpoint.tscn
godot --headless --fixed-fps 60 --path . --log-file /tmp/full_suite.log res://tests/test_runner.tscn
```

Ścieżkę logu należy dostosować do systemu. Pełny runner i raporty mogą zapisywać dane testowe; uruchamiaj je w osobnej kopii projektu.

Raport wydania podaje wyniki faktycznie wykonanych kontroli i dokładny zakres pomiarów trójkątów. Próbki czasowe i wybrane pozy nie stanowią matematycznego dowodu dla każdej możliwej historii animacji, każdego terenu ani dowolnego FPS. Szczegółowe pomiary geometrii dotyczą LOD0; pozostałe LOD-y objęto kontrolami mocowania i funkcji ekwipunku.

Osobny, istniejący już w bazie kontakt rękojeści z ramieniem przy leżącej martwej/powalonej postaci nie jest naprawą pozy w tym wydaniu. Nie należy opisywać tej paczki jako pozbawionej wszystkich możliwych kolizji wizualnych. Wyniki zbiorczego runnera są porównywane z dokładną bazą; stare niepowodzenia należy raportować osobno od nowych regresji.
