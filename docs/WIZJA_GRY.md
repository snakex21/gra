# Kierunek gry

Nasza wersja zachowuje samotność, ogrom i atmosferę *Shadow of the Colossus*,
a rozwija Zakazaną Krainę tam, gdzie oryginalny projekt ograniczał sprzęt PS2.
Kolosy, krajobraz, światło i cisza pozostają centrum doświadczenia.

## Żyjąca Zakazana Kraina

Pełny cykl dnia i nocy oraz pogoda zmieniają odbiór miejsc i warunki podróży.
Bogatsza roślinność i fauna nadają regionom własne zachowanie. Świat nadal jest
pusty i tajemniczy: nie wypełniamy go zwykłymi NPC ani mapą znaczników.

Jaskinie, podziemia, ruiny, świątynie i grobowce oferują ukryte znajdźki oraz zagadki.
Eksploracja wynika z obserwacji krajobrazu, światła, dźwięków i śladów w otoczeniu.
Odkrycia mają wzmacniać ciekawość oraz poczucie dawnej historii krainy.

## Konsekwencje śmierci kolosów

Świat reaguje na kolejne zwycięstwa. Zmianom mogą podlegać pogoda, zachowanie
zwierząt, konkretne regiony oraz świątynia. Pojawiają się anomalie związane
z odzyskiwaniem mocy przez Dormina. Ich nasilanie nadaje podróży konsekwencje
i przygotowuje finałową walkę, po której Wędrowiec może przeżyć.

Postęp reakcji wynika z pokonanych kolosów i musi przetrwać zapis oraz odtworzenie
nagrania. Samo wczytanie regionu nie powinno ponownie losować stanu świata.

## Żywe kolosy i odrębne walki

Proceduralny ruch, IK i dynamiczne reakcje mają tworzyć wrażenie masy oraz żywego
stworzenia. Każde starcie ma własną zagadkę dostępu, zagrożenie i drogę wspinaczki.
Nowe interpretacje wyciętych kolosów nie powielają wcześniejszych walk i nie
opierają konfliktu wyłącznie na ściganiu biernej, uciekającej istoty.

Kampania obejmuje 21 starć w kolejności z `src/game/boss_roster.gd`.
Celosia i Cenobia walczą równocześnie w jednym starciu; Dormin jest finałem.

## Kooperacja, kompan AI i VR

Docelowo dostępne są samotna gra, gra z kompanem AI oraz współpraca z drugim
graczem. Obecność partnera ma być dyskretna. Jego śmierć lub odejście nie odbiera
żywemu graczowi postępu walki. Zagadki muszą pozostawać możliwe do rozwiązania solo.

VR rozwija bezpośrednie odczuwanie skali, wspinaczki i obecności stworzenia.
Dobór interfejsu, komunikacji partnerów i rozwiązań komfortu ma zachować ciszę
oraz tajemniczy charakter krainy.

## Dostępność sprzętowa

Oprawa ma być skalowalna również dla starszych kart. Budżety siatek i tekstur,
LOD-y, ograniczony koszt cieni oraz małe porcje budowy otoczenia są częścią projektu.
Domyślny renderer Compatibility i trzy profile grafiki pozwalają ograniczyć koszt
bez zmiany fizyki ani zagadek. Wymagania minimalne ustalimy na podstawie pomiarów
na rzeczywistym starszym sprzęcie, a nie wieku karty ani wyników na mocnym komputerze.

## Stan realizacji

Grywalne są prototypy 21 starć oraz dodatkowa próba jaskiniowa. Działają podstawy
proceduralnego ruchu, IK, wspinaczki, podróży przez ciągły świat, checkpointów
powtórek i zachowania walki po utracie partnera. Etap 12 dodaje latarkę miecza,
planowanie lotu Aviona, mniejsze porcje budowy grafiki oraz efekty wody.
Etap 13 dodaje własne modele Wędrowca, Mono, Agro i wszystkich kolosów z Blendera oraz przenośny autozapis
bezpiecznego stanu świata. Mono leży na ołtarzu w świątyni; nie wprowadza tłumu NPC.
Etap 14 dodaje modele broni z naciągiem łuku i dopasowaniem dłoni, poprawia Wędrowca,
rozwija geografię Krainy i dodaje profile kosztu renderowania.
Etap 15 wprowadza pełny cykl dnia i nocy, płynną pogodę regionów oraz atmosferyczny
wpływ kolejnych zwycięstw i Dormina. Zegar i warunki są częścią zapisów oraz powtórek.
Krajobraz zyskuje modele drzew, skał i ruin ze wspólnym atlasem i trzema LOD-ami.

Ekosystem, eksploracyjne znajdźki i zagadki oraz bardziej rozbudowane reakcje
regionów i świątyni na śmierć kolosów pozostają do wdrożenia. Pogoda jest obecnie
kosmetyczna i nie zmienia fizyki walk. Pełne tryby
kooperacji, kompan AI i VR również wymagają dalszej pracy. Modele i reżyseria
obecnych starć mają oprawę prototypową.
