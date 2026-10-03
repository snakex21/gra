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

Etap 16 udostępnia opcjonalnego kompana pieszego w kampanii. Domyślna pozostaje
samotna podróż. Kompan podąża, sprawdza przeszkody i przepaści, unika ostrzeganych
ataków i rzadko pomaga łukiem. Nie przejmuje Agro ani głównej drogi wspinania.
Zmienność jego zachowania wynika z utrwalonego ziarna polityki decyzji. Model
uczenia maszynowego nie jest potrzebny do działania tej funkcji. Eksperymentalny
lokalny backend nadal wymaga oceny jakości i kosztu na docelowym sprzęcie.

VR rozwija bezpośrednie odczuwanie skali, wspinaczki i obecności stworzenia.
Dobór interfejsu, komunikacji partnerów i rozwiązań komfortu ma zachować ciszę
oraz tajemniczy charakter krainy.

Etap 17 rozpoczyna od osobnej sceny PCVR z terenem doliny i zamrożonym Valusem,
śledzeniem głowy oraz kontrolerów, ruchem po podłożu i skokowym obrotem.
Start w arenie Valusa pozwala od razu oceniać skalę. Wykorzystuje wbudowany
OpenXR; kampania nadal działa w dotychczasowym rendererze Compatibility.
Ten pierwszy zakres nie zawierał chwytu rękami. Walka, Agro i połączenie VR
z zapisami kampanii wymagają kolejnych prototypów.
Testy mapy akcji, ruchu i sceny oraz natywny podgląd na monitorze przechodzą;
nie zastępują walidacji urządzenia i obrazu stereoskopowego.
[Zakres i wymagania PCVR](ETAP_17.md).

Pierwsza próba na Quest 2, na stojąco, potwierdziła wejście do VR i jakościowo
dobrą wydajność, lecz wykazała problem wysokości i brak bliskich interakcji.
Etap 18 kalibruje punkt oczu, przesuwa start przy tylne futro łydki Valusa
i dodaje chwyt oraz podciąganie obiema rękami z wytrzymałością. Dłonie,
przedramiona i miecz do podnoszenia oraz upuszczania rozwijają obecność gracza.
Kolos nadal jest zamrożony; pełna walka i komfort wspinania wymagają dalszej weryfikacji.
Ścisłe testy chwytu, miecza i oprawy przechodzą headless oraz w natywnym
Compatibility bez błędów i zgłoszeń wycieków. Nowe interakcje nadal wymagają
ponownej próby w Quest 2; testy na monitorze nie potwierdzają komfortu w goglach.
[Zakres Etapu 18](ETAP_18.md).

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
W bieżącej sesji zintegrowano także płynne przejścia biomów, regionalną gęstość
lasów i kolonie istniejącej trawy oraz krzewów. Oprawa omija drogi i areny,
korzysta z LOD-ów i profili jakości oraz nie zmienia terenu ani kolizji.
[Zakres i koszt roślinności](ENVIRONMENT_DRESSING.md).
Etap 16 dodaje wybór kompana, bezpieczne dołączanie i odejście, niezależne odrodzenie
uczestnika oraz zapis jego trybu, RNG i timerów w checkpointach świata. Powtórki
odtwarzają dwa strumienie akcji, zmiany trybu i przegrupowania bez wywoływania modelu.
Etap 17 dodaje osobny prototyp PCVR do oceny skali i podstaw ruchu. Jego launcher
wybiera Mobile/Vulkan, a jawna symulacja klawiaturą/myszą działa w Compatibility.
Nie zmienia normalnej gry ani systemowego runtime OpenXR.
Etap 18 dodaje kalibrację wysokości, małe stanowisko przy chwytalnej łydce
Valusa, ręczny chwyt i podciąganie, własną oprawę dłoni oraz fizyczne podnoszenie
i upuszczanie miecza. Broń nie zadaje jeszcze obrażeń.

Ekosystem, eksploracyjne znajdźki i zagadki oraz bardziej rozbudowane reakcje
regionów i świątyni na śmierć kolosów pozostają do wdrożenia. Pogoda jest obecnie
kosmetyczna i nie zmienia fizyki walk. Sieciowa kooperacja, sterowanie drugim
graczem i pełna kampania VR wymagają dalszej pracy. Kompan obecnie porusza się pieszo i stosuje
lokalne omijanie; labirynty i głębokie przerwy w terenie wymagają rozbudowy nawigacji.
Nie wybrano modelu decyzji do dystrybucji. Modele postaci i reżyseria obecnych
starć mają oprawę prototypową. [Aktualny etap](ETAP_18.md),
[stan badań lokalnych modeli](LOCAL_DECISION_MODELS.md).
