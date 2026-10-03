# Etap 12 — jaskinia, lot, checkpointy, grafika i woda

## Działające zmiany

- Jaskinia wykorzystuje Hollowvault i Deeprelic. Wędrowiec może oświetlać ją mieczem
  na V / lewym spuście. Światło działa bez słońca, ma własny stożek i cienie.
- Roboczy kolos jaskiniowy chowa się po okresie odsłonięcia. Skierowanie światła
  na kolosa przyspiesza wyjście z osłony. Chroniony punkt zamyka się w ukryciu;
  timeout zabezpiecza przed zakleszczeniem walki solo. Wspinanie korzysta z humanoidalnego rigu.
- Blender: własne kamienne detale głowy i torsu, sześć eksportów GLB / trzy LOD-y.
  Edytowalne źródło: `art/source/cave_colossus.blend`. Ciało nadal jest prototypowe.
- Avion planuje krzywą przelotu po zapowiedzi. Cel najniższego punktu pozostaje
  stały podczas pikowania; ruch gracza nie powoduje niekończących się poprawek.
- Nagranie przechowuje binarny checkpoint świata co 600 ticków / 10 s: pozycje,
  prędkości, kości, kotwice wspinania, timery, stan walki i generatory losowania AI.
  Przewijanie wybiera najbliższy wcześniejszy checkpoint. Wycinek usuwa niepotrzebny
  prefiks wejść i zachowuje checkpoint potrzebny do jego odtworzenia. Stare pliki
  bez checkpointów korzystają z odtwarzania od początku.
- Grafika aren ma kolejkę pojedynczych rekwizytów oraz porcje trawy po 128 prób
  rozmieszczenia / jeden fragment MultiMesh. Limit kroku wynosi 2 ms i do czterech
  jednostek; pojedyncze wczytanie zasobu może przekroczyć limit. Teren pozostaje
  osobnym krokiem, więc całkowite usunięcie zacięć wymaga dalszego pomiaru.
- Woda: dwie fale w shaderze, kręgi po wejściu, krople i dźwięk plusku. Fala jest
  wizualna: średnia wysokość używana przez pływanie i wspinanie nie zmienia się.
  Zanurzona kamera dostaje własną mgłę i środowisko, niezależne od drugiego widoku.
- Śmierć jednego uczestnika nie resetuje walki, gdy drugi żyje. Odrodzenie pojedynczego
  uczestnika zachowuje postęp bossa. To podstawa kooperacji; menu co-op, sieć i VR
  nie są jeszcze gotowymi trybami gry.
- Lista prób w menu uruchamia pojedyncze starcia. Esc / Start wraca do tej listy.
  Areny kampanii mają stałe sloty dla 21 pozycji, więc dodanie bossa nie przemieszcza
  wcześniejszych aren. Zapis v2 zachowuje zwycięstwa po nazwie, a stare zapisy v1
  zachowują wcześniejsze sześć zwycięstw i prowadzą do nowych brakujących starć.
- Oryginalne rekwizyty: osłona Barby, pierścień gejzeru Basarana, fragment galerii
  Kuromori, porowata skała Dirge'a, lampa i znak jaskiniowy, zwieńczenie ruin Pelagii.
  Źródło `art/source/encounter_props.blend`, 21 eksportów GLB / trzy LOD na model,
  wspólny atlas. Włączone do kolejki grafiki; nie dodają kolizji.
- Devil i Phoenix mają własne sztywne części z Blendera:
  `art/source/cut_winged_guardians.blend`, 18 GLB / trzy LOD na segment.

## Przenośność

Zapis kampanii, sloty, ustawienia, nagrania i zgłoszenia trafiają do lokalnego `data/`.
`PortablePaths` mapuje dawne ścieżki `user://` na ten folder. Nie migruje automatycznie
wcześniejszych danych z profilu Windows. Launcher `tools/run_local.py` kieruje dane
wewnętrzne Godota, Blendera i pliki tymczasowe do `tools/runtime/`; `_sc_` włącza
przenośny edytor. Wyeksportowany plik gry wymaga zachowania takiego launchera dla
cache silnika; eksportu Windows jeszcze nie weryfikowano.

## Weryfikacja

- Osiem scenariuszy `tests/stage12.tscn`: zapis lokalny, światło i zwabienie w jaskini,
  ukończenie wspinanej walki, izolacja śmierci kompana, planowany przelot, plusk,
  binarny checkpoint, przewijanie i wycinek, małe porcje grafiki.
- Wybrane testy regresji wcześniejszych etapów: odtwarzanie walki, przewijanie
  w przód i tył, zapisy, menu, F9, znaczniki i klipy, układ świata, zgodność aren,
  śmierć i reset, pełne walki z Hydrusem oraz Avionem i lot z jeźdźcem.
- `tests/campaign_expansion.tscn` kończy nowe walki w rzeczywistych, obróconych
  i przesuniętych arenach kampanii przez `PlayerActions`, a następnie sprawdza zapis
  zwycięstwa. Osobne testy bossów sprawdzają blokady mechanik i reset.
- `tests/checkpoint_climb.tscn` sprawdza zachowanie chwytu oraz wznowienie ruchomej
  rampy Argusa. Po dwóch sekundach dalszej wspinaczki zmierzono różnicę 2,7 cm;
  odtworzona przestrzeń fizyki może opóźnić pierwsze przesunięcie chwytu o jeden tick.
  Nie zakładamy identyczności bitowej checkpointów we wszystkich sytuacjach kontaktu.
- Test Aviona: trzy ukończone przeloty w 75 s, bez zmiany celu i bez przerwania;
  pełna walka botem: 99,2 s, cztery przeloty, zero przerwanych, zero śmierci.
- Test Hydrusa: wygrana botem w 67,3 s bez śmierci.
- Końcowy test grafiki dla 21 aren po otwarciu wejścia Basarana: 995 małych kroków. Wcześniejszy pomiar kolejki
  wykazał tick z terenem do 53 ms oraz start 1,23 s wobec 1,62 s przy budowie naraz
  (headless, ta maszyna, przed pełną rozbudową listy). Nie jest to pomiar płynności
  końcowej oprawy w rendererze.
- Render jaskini i podwodnej mgły sprawdzany w Forward+ oraz Compatibility.
  Dodatkowa asercja porównuje obraz z latarką i bez niej, żeby wykryć samo widoczne
  źródło światła, które nie oświetla otoczenia.
- Końcowe powtórzenie pełnego zestawu 197 testów po integracji modeli etapu 13:
  0 niepowodzeń. Test podróży zachował jednego gracza, brak wygaszenia i jednego
  aktywnego kolosa; dotarcie do walki zajęło 171,8 s symulacji. Szczegóły
  sprawdzenia checkpointów i nowych modeli znajdują się w `ETAP_13.md`.

## Ustalony kierunek kampanii

Lista użytkownika (kolejność; dostępność określa `BossRoster.PLAYABLE`):

1. Valus
2. Quadratus
3. Gaius
4. Phaedra
5. Avion
6. Barba — redesign
7. Hydrus
8. Kuromori — pomysły inspirowane Yamori A
9. Basaran
10. Dirge
11. Celosia + Cenobia — jedno starcie, dwóch przeciwników przeciw jednemu lub dwóm graczom
12. Pelagia
13. Phalanx
14. Argus
15. Malus
16. Devil
17. Phoenix
18. Spider
19. Worm
20. Saru
21. Dormin — finał zamiast śmierci Wędrowca

### Rdzenie nowych grywalnych prototypów

| Starcie | Droga do odsłonięcia i wspinaczki |
| --- | --- |
| Barba | Osłona pod łukiem prowokuje pochylenie; broda daje wejście na ciało. Kamienne nogi blokują skrót z Valusa. |
| Kuromori | Dwa trafienia grzbietowych znaków na ścianie strącają strażnika; odsłonięty brzuch jest ograniczonym oknem ataku. Trucizna wymusza zmianę miejsca. |
| Basaran | Zwabienie nad dwa gejzery, odsłonięta stopa, strzał i przewrócenie; potem wspinaczka na zad. |
| Dirge | Jazda na Agro, strzał w oko i zderzenie strażnika ze ścianą otwierają dostęp do grzbietu. |
| Celosia + Cenobia | Dwa aktywne zagrożenia naraz: światło przy palenisku otwiera drogę do pancerza Celosii, a szarża w kolumnę do pancerza Cenobii. Oba sigile wymagane. |
| Pelagia | Wejście od tyłu i uderzanie kamiennych zębów kieruje strażnika do trzech ruin; kolejne zderzenia odsłaniają sigil. |
| Phalanx | Trzy worki przebijane łukiem obniżają lot; chwyt i skok z Agro prowadzą na skrzydło i trzy sigile. |
| Argus | Stomp podnosi fizyczną rampę przeciwwagi; galeria pozwala przeskoczyć na plecy. |
| Malus | Osłony przed ostrzałem, znak za plecami, droga po dłoni i strzał w nadgarstek prowadzą do korony. |
| Devil | Zapowiedziana zasadzka z sufitu; skierowane światło miecza zmusza strażnika do lądowania i otwiera wspinaczkę. |
| Phoenix | Aktywna osłona cieplna i zapowiadane płomienie; zwabienie pod wodospad chłodzi ciało na czas wspinaczki. |
| Spider | Trzy węzły sieci przy ziemi do przecięcia lub przestrzelenia; opuszczone ciało daje wejście po nogach. Ataki siecią pozostają zagrożeniem. |
| Worm | Rytm lądowań na trzech płytach prowokuje wyjście z ziemi; mineralne kołnierze trzeba rozbić przed kolejnymi wspinaczkami. |
| Saru | Ustawienie przeciwwag na linii zapowiedzianych rzutów tworzy most z zawieszonych bloków nad prawdziwą przepaścią. |
| Dormin | Trzy więzy wymagają kolejno światła, mocnego ciosu po oświetleniu oraz szybkiego trafienia w poruszającą się pieczęć. Uwolniony strażnik daje wejście na grzbiet i koronę; po wygranej Wędrowiec wraca żywy. |

Wszystkie 21 starć można uruchomić z menu **Próby kolosów**, obok dodatkowej próby
jaskiniowej. Są to kompletne pętle walki na
prototypowej geometrii; modele, animacje, tempo i reżyseria wymagają dalszej pracy.

Nowe i przeprojektowane starcia mają własny rdzeń mechaniczny oraz powód konfliktu.
Nie opieramy ich na zabijaniu biernego zwierzęcia, które wyłącznie ucieka. Wycięte
kolosy dostaną własne projekty; bez źródła nie traktujemy wymyślonej mechaniki jako
historycznej rekonstrukcji. Odtworzenie wszystkich oryginalnych zachowań, kompletna
oprawa, co-op z botem / człowiekiem i VR pozostają szerszym celem projektu.
