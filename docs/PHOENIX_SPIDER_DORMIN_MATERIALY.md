# Phoenix, Spider i Dormin: podłoża i istniejący kamień

Baza: `fb21a1a7c9033ea6ea8699171f6901f48cdd622d`. Kontynuacja materiałów
kampanii układu 5, przez istniejącą kolejkę zasobów i oprawy aren.

## Zakres

- Phoenix: całe podłoże dziedzińca oraz osiem oryginalnych bloków kaskad.
  Ciepły, wypłukany wapień z osadem mineralnym; obie tafle wody i wodospady
  zachowują swoje materiały i przezroczystość
- Spider: całe podłoże i sześć oryginalnych słupów na obrzeżu. Przygaszony,
  omszały kamień; trzy podstawy kotwic pozostają bez zmian
- Dormin: całe podłoże, osiem słupów oraz ściana i gzyms sanktuarium.
  Jasny srebrzysty kamień porządkuje finałowy dziedziniec

Łącznie 27 widocznych powierzchni zmienia tylko `material_override`: 9/7/11.
Sześć nowych materiałów, 18 autorskich map albedo/normal/roughness po 512×512.
Oryginalne generatory NumPy/Pillow, bez zewnętrznych obrazów i ImageGen.
Lokalny triplanar, mipmapy, wspólne zasoby i asynchroniczne ładowanie.
Relief jest wyłącznie cieniowaniem; nie wprowadza pozornych schodów ani kolizji.

Nie dodano geometrii, przeszkód, światła ani shaderów. Oryginalna oprawa
pozostaje identyczna. Układy 1–4, samodzielne próby, stan zapisu/replay,
walka, AI i kooperacja nie są zmieniane. Dokładne selektory sprawdzają
położenie, rozmiar i orientację; kotwice, woda i obiekty bossów są wykluczone.

## Weryfikacja i ograniczenia

Testy obejmują zachowanie starszych zasobów bajt po bajcie, kontrakt materiałów,
geometrię i kolizje, wyłączenie oprawy, układy historyczne, ładowanie oraz
wyładowanie kolejki, a także istniejące testy walk i zapisów.
Dokładny wynik pełnego zestawu 197 testów i znane błędy bazowe znajdują się
w raporcie paczki. Nie poluzowano historycznych progów CPU.

Sześć par wejście/obrzeże przedstawia pełne rzeczywiste sceny eksportowane
przez Godot i renderowane w Blender Cycles CPU: 960×540, 24 próbki, Balanced.
Kamera, światło, normalne, UV, geometria i rozmieszczenie scen są identyczne
przed/po. Podglądy nie zawierają postaci, mgły ani aktywnej walki.
To nie są zrzuty Godota, pomiar FPS ani pomiar pamięci GPU.

## Dalsza bezpieczna praca

Worm wymaga osobnego wykluczenia rezonujących płyt i znaczników stacji.
Saru wymaga zachowania przepaści, mostu i przynęt. Cave/Devil mają już
Hollowvault/Deeprelic, w tym widoczne posadzki należące do gotowych modeli.
Nie należy nakładać kolejnego podłoża ani jednolitego materiału na całe
połączone modele. Najpierw należy sprawdzić ich atlas, UV i wszystkie LOD.
