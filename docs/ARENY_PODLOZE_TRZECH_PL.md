# Quadratus, Phaedra i Avion — podłoże zintegrowane z kampanią

Kontynuacja dokładnej wersji `33851a305eeaed6a3371bff74df8feafd8a25ea9`.
To materiały rzeczywistych aren, nie osobny zestaw pokazowych modeli.

- **Quadratus:** jasny nadmorski piasek, drobny żwir i płynne skupiska osadu. Ta sama powierzchnia pokrywa istniejący podjazd i dwie niskie wyniosłości, aby nie wyglądały jak osobne brunatne bloki.
- **Phaedra:** zielona darń, mech, suche źdźbła i przerzedzenia. Odcień wiąże duże podłoże z dodaną wcześniej roślinnością.
- **Avion:** chłodny, zwietrzały kamień ze spękaniami i osadem przy jeziorze. Zachowano prawdziwe nachylenie misy oraz istniejącą wodę.

Każda arena otrzymuje własne okresowe mapy albedo, normalnych i szorstkości 512 × 512. Materiały korzystają z dotychczasowego potoku StandardMaterial3D, triplanaru, mipmap i współdzielonej pamięci podręcznej. Ładowanie w kampanii pozostaje asynchroniczne. Szczegóły normalnych to wyłącznie cieniowanie, bez przemieszczenia wierzchołków.

## Co pozostaje zgodne

Geometria, wysokości, kształty kolizji i punkty rozgrywki nie są zmieniane. Nie zmienia się AI, kooperacja, jazda konna ani wspinaczka. Tunele Phaedry, woda Aviona, pnącza, filary i cele walki nie otrzymują nowej powłoki. Wszystkie 635 wcześniej dostarczonych obiektów Nature Variety, modele, rozmieszczenie i LOD-y są zachowane.

Punkt integracji nadal działa tylko dla kampanii układu 5, z włączoną oprawą. Układy 1–4 oraz samodzielne próby zachowują dotychczasowy wygląd. Cztery wcześniejsze komplety materiałów (Valus, Hydrus, Basaran, Phalanx) nie zostały zregenerowane inaczej ani zastąpione.

## Rzetelne podglądy

`tools/art/capture_surface_arena_previews.py` eksportuje kompletne sceny z dwóch oddzielnych katalogów: dokładnej poprzedniej wersji oraz tej kontynuacji. Każda wersja zawiera istniejące modele i roślinność. Eksporter pobiera rzeczywiste siatki, materiały i produkcyjne rekordy instancji z Godota w trybie headless.

Blender Cycles CPU renderuje identyczną kamerę, światło oraz profil Balanced. Dla każdej areny są dwa porównania: rzeczywisty start gracza i osobny kadr skraju. Kontrola przed renderowaniem wymaga zgodności wszystkich tablic geometrii, transformacji i instancji między PRZED i PO.

To podglądy danych sceny, **nie zrzuty działającej gry**. Nie ma postaci ani mgły, a woda jest zatrzymana w czasie zero. Oświetlenie, tonemapping, import tekstur i przezroczysta woda Blendera nie są identyczne z Godotem. Brak pomiaru GPU i FPS. Triplanar z trzema mapami może wymagać do dziewięciu odczytów tekstur na fragment; nie należy mylić kosztu CPU headless z wydajnością renderowania.

## Odtworzenie

Po imporcie obu kopii Godota:

    python tools/art/capture_surface_arena_previews.py KATALOG_WYNIKOW --baseline-root KOPIA_33851a3
    python tools/art/assemble_surface_arena_previews.py KATALOG_WYNIKOW

Eksport nie wymaga ekranu ani GPU. Generator map i testy są w `tools/art/`; test scen w `tests/arena_ground_materials.gd`. Wyniki wykonanych testów, niezależny przegląd, manifesty podglądów i instrukcja instalacji są w paczce kontynuacji.
