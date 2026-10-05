# Kamienne fasady trzech aren

Kontynuacja paczki `979e528fced764e72b021795befbad3d31b9ae6d`. Zmiana obejmuje kampanię z układem terenu 5 i włączoną oprawą graficzną. Nie jest to pełna gra.

## Wybrane miejsca

Przegląd poprzednich rzeczywistych podglądów i konstruktorów aren wskazał trzy szczególnie surowe zespoły architektoniczne:

- **Barba:** trzy ściany dziedzińca i sześć filarów. Ciepły piaskowiec z dużymi ciosami, zużytymi spoinami i detalem fasadowym
- **Kuromori:** pięć ścian obwodowych, piętnaście płyt galerii i 48 już istniejących wizualnych stopni. Chłodniejszy kamień z osadem mineralnym i śladami deszczu
- **Argus:** sześć filarów zewnętrznych, cztery podpory, dwa stałe podesty i tylna ściana. Suchy, zwietrzały monumentalny mur

Łącznie 90 istniejących powierzchni otrzymuje trzy współdzielone materiały. Dobór odbywa się przez zamkniętą listę oryginalnych położeń i rozmiarów brył, a nie ogólne przemalowanie wszystkich skał i budowli. Ta iteracja skupia się na architekturze; nie zmienia klifów innych aren.

## Zachowanie gry

Nie dodano ani nie usunięto geometrii, colliderów, węzłów, schodów, osłon ani punktów wspinaczki. Materiały nie mają displacementu ani paralaksy; spoiny i relief są wyłącznie cieniowaniem. Mapowanie lokalne pozostaje stabilne po obrocie i przesunięciu areny.

U Barby pozostają nietknięte dach i podpory schronienia oraz importowany model osłony. U Kuromoriego nie zmieniają się niewidoczna rampa kolizyjna, jej nachylenie, istniejące stopnie, prześwit północnej galerii ani drogi bossa. U Argusa pozostają oryginalne materiały ruchomej rampy, płyty-przeciwwagi, mostu i punktu skoku; emitujące sygnały aktywacji nie są przemalowane. Materiały Pelagii i ich reakcje na uszkodzenie/reset nie wchodzą do zakresu.

Układy 1–4, tryb bez oprawy i samodzielne próby zachowują poprzedni wygląd. Nie modyfikowano zapisów, kontrolerów, współpracy AI ani zachowania przeciwników.

## Źródła i budżet

Dziewięć map PNG 512 × 512: kolor, normalne i szorstkość dla każdej areny. Powstają deterministycznie w lokalnym generatorze NumPy/Pillow. Nie użyto ilustracji AI ani pobranych fotografii. Skala powtórzenia wynosi 8 m u Barby i Kuromoriego oraz 10 m u Argusa. Tekstury korzystają z mipmap i filtrowania anizotropowego.

Zasoby są dekodowane w tle przez ResourceLoader, a przypięcie każdego materiału jest osobną pracą istniejącego planera. Kolejka używa słabych referencji, więc wyładowanie areny podczas przygotowania nie dotyka usuniętych obiektów. Brak nowych modeli oznacza zerowy przyrost trójkątów i instancji. Triplanar trzech map wymaga do dziewięciu próbek tekstury na fragment. Testy CPU nie określają kosztu GPU ani FPS.

## Podglądy i weryfikacja

Podglądy są renderami Blender Cycles CPU z wyeksportowanej kompletnej geometrii aren, rzeczywistych materiałów i istniejących rozmieszczeń. Obie strony porównania zachowują tę samą kamerę, oświetlenie i profil Balanced. Widok „entry” odpowiada wejściu gracza, a „rim” pokazuje istniejącą architekturę z bliska. Nie są to zrzuty działającego Godota ani pomiar wydajności. Brakuje postaci, aktywnej rozgrywki, otoczenia całej krainy i mgły; światło oraz tonemapping mogą się różnić od docelowego renderera.

Wyniki uruchomionych testów, znane porażki bazowe, dokładny commit i sumy kontrolne znajdują się w dołączonym raporcie. Progi testów wydajności nie zostały obniżone. Nie wykonano push, merge ani zmian na komputerze użytkownika.
