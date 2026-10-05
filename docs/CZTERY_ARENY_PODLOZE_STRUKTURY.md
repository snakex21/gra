# Cztery kolejne areny: podłoże i istniejące struktury

Baza: `8559e70947a6a1a9c7739ea81f903f085dff3710`. Zmiana jest częścią kampanii
układu5, przez istniejące wywołania ArenaGroundMaterials/ArenaArchitectureMaterials.
Nie wpływa na układy1–4, oprawę wyłączoną ani samodzielne próby walk.

## Zakres

- Gaius: srebrny spękany granit na całym podłożu i czterech istniejących
  podwyższeniach; istniejące nadproże i trzy niskie słupy otrzymują granitowe lico
- Dirge: ciepły piasek na pustyni, fundamencie i pięciu grzbietach; pięć ścian
  z czytelnym warstwowym kamieniem, otwarta trasa pościgu pozostaje bez zmian
- Celosia/Cenobia: jedna rzeczywista wspólna arena, wypalane kamienne płyty
  i kamienny dach/podpory schronienia. Kolumny, mur ognia, palenisko i płomień
  zachowują oryginalne materiały i wszystkie mechaniki resetu
- Malus: chłodne łupkowe podłoże; wszystkie istniejące zadaszenia, ściany
  osłon i galeria pośrednia zachowują geometrię, otrzymując spójny kamień

Łącznie47 widocznych powierzchni w prawdziwej scenie:9/12/4/22.
Gaius w surowym builderze ma15 potencjalnych bloków architektury, ale wcześniejsza
oprawa ukrywa11 z nich i zastępuje teksturowanymi ruinami/kamieniami. Zachowujemy
te gotowe modele i nie nakładamy nowego materiału na ukryte prostopadłościany.

Osiem nowych materiałów,24 autorskie mapy512×512 (albedo/normal/roughness).
Brak displacement, parallax, przezroczystości, świateł i nowych shaderów.
Lokalny triplanar z mipmapami, ładowanie kolejką i współdzielone zasoby materiałów.
Istniejące drzewa, trawy, skały, klify i dekoracje pozostają identyczne.
Nie dokładamy drobnych przeszkód do pościgu ani do obszaru małych strażników.

## Bezpieczeństwo i weryfikacja

Selektory dopasowują autorską pozycję, rozmiar i orientację oryginalnych obiektów.
Zmiana dotyczy wyłącznie material_override; nie tworzy geometrii, kolizji,
anchorów, schodów ani ukrytych barier. Aktywne elementy nie są przemalowywane.
Dane geometrii/UV/normalnych/transformacji wszystkich eksportowanych powierzchni
są porównane przed/po; renderowane sceny obejmują cały istniejący wystrój.

Osiem par przed/po: wejście oraz obrzeże/struktury,960×540,24 próbki,Balanced.
Blender Cycles CPU na rzeczywistych danych gry, nie zrzuty Godota ani pomiar FPS.
Dokładne wyniki testów znajdują się w raporcie dostarczonej paczki.

## Pozostałe miejsca i bezpieczna kontynuacja

Standardowe powierzchnie ziemi ukończono dla15 aren, obejmujących16 tradycyjnych
bossów (Celosia i Cenobia dzielą arenę). Nadal bez tej warstwy są obecne w kodzie
Phoenix, Spider, Worm, Saru, Dormin oraz Cave/Devil.

Następna spójna grupa: Phoenix, Spider, Dormin. Mają duże płaskie podłoża
oraz widoczne istniejące ściany/kolumny. Można poprawić pełne powierzchnie i
bezpieczne statyczne struktury z zachowaniem wodospadów, wody i punktów kotwic.
Worm: osobno, z wyłączeniem rezonujących płyt i znaczników stacji.
Saru: osobno, ścisłe zachowanie otwartej przepaści, mostu i przynęt.
Cave/Devil mają już zestawy Hollowvault/Deeprelic: wymagają oględzin widocznego
podłoża przy warstwach kamery i światła, nie ponownego dekorowania ukrytej powłoki.
