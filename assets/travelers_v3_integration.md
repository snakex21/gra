# Wędrowiec i Mono — autorskie modele v3

Modele, proporcje, włosy, tkaniny i motywy ornamentów zostały zbudowane w tym projekcie. Nie zawierają modeli ani tekstur wyeksportowanych z innej gry. Edytowalne źródło to `art/source/travelers_v3.blend`; materiały i wszystkie trzy mapy atlasu są spakowane w pliku Blender.

## Podłączenie Wędrowca

Po utworzeniu wszystkich dotychczasowych elementów `PlayerVisual` na końcu jego `_ready()`:

```gdscript
TravelerArt.attach(self, get_parent() as PlayerCharacter)
```

Można też dołączyć adapter po gotowości gracza, z poziomu świata:

```gdscript
TravelerArt.attach(player.visual, player)
```

`attach()` jest idempotentne. Adapter chowa stare siatki postaci, pozostawiając istniejące obiekty ramion, miecz, poświatę, wiązkę i latarkę. Importowane ramiona są przypięte do istniejących pivotów `(-0.3, 0.4, 0)` i `(0.3, 0.4, 0)`. Początek modelu odpowiada środkowi kapsuły gracza. Skala wynosi 1 metr; wysokość modelu to około 1.83 m. Pozy chodu, jazdy, wspinaczki, pływania i skoku poruszają wyłącznie widocznymi częściami. Kolizje, `PlayerActions`, stan gracza i mocowanie broni pozostają pod kontrolą dotychczasowego kodu.

Model używa hierarchii sztywnych części, zgodnej z obecnym proceduralnym rigiem. To adapter do istniejących animacji, nie pełny rig skórzany z animacjami klatkowymi. Miękkie wstawki barkowe, zaokrąglone główki rękawów oraz kontaktowe powierzchnie łokci i nadgarstków zakrywają połączenia w pozycjach wspinaczki i jazdy.

Wersja po dopracowaniu ma ciągły profil nosa, policzków i podbródka, osadzone oczy, powieki i usta przylegające do powierzchni, matowe włosy oraz fałdy tuniki i peleryny. Haft podąża za tkaniną. Dłonie mają przeciwstawny kciuk i cztery częściowo zagięte palce obejmujące uchwyt; nie są otwartą płetwą.

Kontrakt dla kosmetycznego IK i broni jest taki sam we wszystkich LOD:

| Węzeł | Rodzic | Pozycja lokalna (metry) |
| --- | --- | --- |
| `Arm_0/1` | korzeń postaci | `(±0.300, 0.400, 0)` |
| `Forearm_0/1` | `Arm_i` | `(0, −0.285, 0)` |
| `Wrist_0/1` | `Forearm_i` | `(0, −0.276, 0)` |
| `Traveler_Hand_0/1` | `Wrist_i` | `(0, 0, 0)` |
| `HandGrip_0/1` | `Wrist_i` | `(0, −0.050, −0.037)` |

Wszystkie obroty tych węzłów w eksporcie są identity. Oś uchwytu to lokalne **−Y**. `HandGrip_i` względem `Forearm_i` jest dokładnie `(0, −0.326, −0.037)`. Bark→łokieć: 0.285 m; łokieć→nadgarstek: 0.276 m; łokieć→środek uchwytu: 0.328093 m. Nadgarstek i dłoń są osobnymi węzłami, więc można obrócić zamknięte palce wraz z bronią bez obracania całego przedramienia.

Domyślna odległość przełączenia LOD to 12 m i 35 m, liczona względem aktywnej kamery. Do ujęć kontrolowanych można ustawić `art.auto_lod = false` i `art.set_lod(0)`. `pose_preview(&"climb")` lub `pose_preview(&"ride")` służy do inspekcji grafiki i nie przestawia stanu gameplayu.

## Mono na ołtarzu

```gdscript
var mono := TravelerArt.create_mono(valley_root, altar_top_local, altar_yaw, 0)
```

Argument pozycji jest lokalny względem `valley_root` i wskazuje górną powierzchnię ołtarza, nie środek jego bryły. Mono leży twarzą w kierunku **+Y**, głowa jest w **+Z**, stopy w **−Z**. Początek modelu to środek długości ciała rzutowany na płaszczyznę podpory. Najniższa geometria LOD0 jest na wysokości Y=0.014 m; włosy spoczywają nad powierzchnią. Wymiary LOD0: około 0.616 m szerokości, 1.916 m długości i 0.358 m wysokości. `yaw = PI` zamienia kierunek głowy i stóp. Wektory są lokalne, więc scena poprawnie dziedziczy pozycję i obrót rodzica.

Mono zawiera samą geometrię renderu, bez colliderów. Ma zamknięte oczy, dłonie spoczywające na sukni oraz modelowane długie włosy, palce i ornamenty.

## Budżety

| Model | LOD0 | LOD1 | LOD2 |
| --- | ---: | ---: | ---: |
| Wędrowiec | 34 360 | 17 859 | 4 080 |
| Mono | 28 576 | 14 858 | 3 414 |

Wartości oznaczają trójkąty po eksporcie. Poprzedni Wędrowiec miał 35 614 trójkątów LOD0; nowy ma o 1 254 mniej (3.5%). Wędrowiec ma 14 części siatki, Mono jedną. Oba modele używają atlasu PBR 1024×1024: albedo, normal oraz ORM. Wędrowiec ma dodatkowy wariant materiału włosów z większą chropowatością i słabszą mapą normalną, korzystający z tego samego atlasu. Tekstury są osadzone w GLB; zewnętrzne PNG pozostają źródłami do edycji. Szczegółowe metryki, pochodzenie i granice wszystkich LOD zapisano w `assets/travelers_v3_manifest.json`.

## Edycja w Blenderze i eksport

Zachowaj nazwy korzeni `Traveler_v3` i `Mono_v3_Sleep` oraz pivoty `Arm_*`, `Forearm_*`, `Wrist_*`, `HandGrip_*`, `Leg_*`, `Knee_*`, `Ankle_*`. Układ źródła jest Blender Z-up, eksport do Godot jest Y-up. Po ręcznej edycji i zapisaniu pliku źródłowego:

```bat
python tools\run_local.py blender --python tools/art/generate_travelers_v3.py -- --export-source
python tools\run_local.py godot --headless --editor --import --quit
python tools\run_local.py godot --headless --fixed-fps 60 --quit-after 1000 tests/travelers_v3.tscn
```

`--export-source` buduje GLB i LOD z zapisanego `.blend`, usuwa offsety prezentacji studia tylko w kopiach eksportowych i sprawdza SHA-256 źródła, aby potwierdzić brak nadpisania ręcznych zmian. Domyślne uruchomienie generatora odtwarza własny pakiet v3 z kodu; używaj go tylko do zamierzonej regeneracji tego nowego pakietu. Opcja `--render` zapisuje ujęcie Blender do lokalnego `data/captures`.

Podgląd importu i wymagających pozycji:

```bat
python tools\run_local.py godot --rendering-method forward_plus --resolution 1600x1050 --fixed-fps 60 --quit-after 1000 tests/travelers_v3.tscn
```

Test sprawdza import sześciu GLB, zgodność liczby trójkątów, materiały, brak nowych colliderów, pivoty i sockety dłoni wszystkich LOD, mocowanie ramion, zachowanie broni i akcji, rzeczywisty chód przez `PlayerActions` oraz kosmetyczne pozycje jazdy i wspinania. Capture zapisuje wspólne ujęcie, twarz, profil, uchwyt dłoni, wspinaczkę i jazdę do `data/captures/*v3*.png`. W izolowanych pozach podglądu kosmetyczny proces `WeaponArt` i widoczność wyposażenia są wyłączone; testy broni sprawdzają rzeczywiste stany animacji z IK.

Wszystkie komendy używają lokalnego launchera, który kieruje dane Blender/Godot i cache do folderu gry.

## Kontrola w rzeczywistej świątyni

Po podłączeniu obu hooków i wykluczeniu `TravelerArt` z pól symulacyjnych `WorldSnapshot`:

```bat
python tools\run_local.py godot --headless --fixed-fps 60 --quit-after 3000 tests/temple_characters_v3.tscn
python tools\run_local.py godot --rendering-method forward_plus --resolution 1600x1050 --fixed-fps 60 --quit-after 3000 tests/temple_characters_v3.tscn
```

Test używa `GameWorld.with_art = true`, rzeczywistego ołtarza świątyni i automatycznych hooków. Sprawdza lokalne położenie Mono Y=1.64 m i yaw=PI/2, czyli głowę wzdłuż osi X ołtarza. Sprawdza też binarny checkpoint z Wędrowcem na LOD2: jego rozmiar jest równy zapisowi LOD0 (28 700 bajtów w tym fixture, 29 węzłów i 15 obiektów symulacyjnych), nie zawiera adaptera, Mono ani zasobów renderowania. Odtworzony świat odbudowuje grafikę na LOD0 i kontynuuje ruch przez `PlayerActions`. Oba przebiegi kończą się wynikiem 0 błędów. Wspólne ujęcie zapisuje się w `data/captures/temple_characters_v3.png`.
