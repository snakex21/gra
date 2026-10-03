# WorldClimateView

Kosmetyczny węzeł `Node3D` umieszczany bezpośrednio pod `GameWorld`, poza `region` oraz drzewem checkpointu. Nie zapisuje danych, nie zmienia fizyki, kolizji ani stanu kamery. Używa istniejącego kierunkowego światła także dla księżyca.

```gdscript
var view = preload("res://src/world/world_climate_view.gd").new()
add_child(view)
view.setup(self) # albo setup(self, sun, world_environment)
view.refresh(model.sample(region_profile), camera.global_position, String(region_kind), settings.graphics_profile, force)
```

Wywołuj `refresh` najwyżej 10 razy na sekundę oraz z `force = true` po odtworzeniu checkpointu/przewinięciu. `force` odtwarza stałe rozmieszczenie kosmetycznego deszczu; wiek pojedynczych kropel nie jest częścią symulacji. `clear()` od razu chowa deszcz po wyjściu do tytułu.

Kontrakt próbki: `hour` 0–24; `daylight`, `rain`, `cloud`, `fog`, `haze`, `wind_strength`, `anomaly`, `exposure` 0–1; poziomy jednostkowy `wind_direction: Vector3`; `day_index: int`; `weather_id: String`. Adwekcja chmur wynika z zegara próbki, shader nie korzysta z `TIME`. Dodatkowe `sheltered: bool` pochodzi z fizycznego testu dachu przez root; ukrywa wyłącznie deszcz i nie zmienia światła ani widoczności nieba pod zwykłym mostem lub w otwartej świątyni.

`exposure` opisuje faktyczny stopień otwarcia lokalnego otoczenia. W dojeździe do Barby, Dirge czy Devila pozostaje 1; pod zamkniętym sklepieniem 0. Przy wartości poniżej 0.5 deszcz zostaje ukryty natychmiast, włącznie z już żyjącymi kroplami. Samo `region_kind` nie służy do ukrywania deszczu. Root powinien używać położenia kamery w lokalnych współrzędnych areny lub jawnych metadanych zadaszenia. Woda i wejście pod sklepienie mogą więc działać niezależnie.

Warstwa modyfikuje wyłącznie globalne `WorldEnvironment.environment`. Nie dotyka `camera.environment` ani kopii podwodnej w `WaterCameraEffects`. `dry_environment_state()` zwraca niezależny słownik aktualnej suchej bazy (fog, ambient, sky, background). Można synchronizować nim suchą kopię używaną przez efekty kamery. Kopii podwodnej nigdy nie nadpisuj suchym `fog_density`/`fog_light_color`; powrót nad wodę wybiera aktualną suchą bazę. Przy zmianie globalnego `fog_mode` istniejące kopie podwodne powinny pozostać `FOG_MODE_EXPONENTIAL`, aby gęstość 0.12 zachowała działanie.

Limity: jeden emiter CPU, 96/176/256 kropel, aktualizacja cząstek 30 Hz, wspólna siatka i materiał, zero cieni deszczu. Niebo używa 1/2/3 oktaw prostego szumu w low/balanced/high oraz małej kostki 32 px; jej pass pomija chmury. Ambient i refleksy są sterowane kolorem, bez kosztownego IBL. Noc nie zwiększa liczby świateł ani atlasów cieni. Bez volumetric fog, SSR, SSAO, SSIL, SDFGI. Mgła to tani efekt odległościowy.

Źródła techniczne: [Godot 4.6 Sky shaders](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/sky_shader.html), [Sky](https://docs.godotengine.org/en/4.6/classes/class_sky.html), [CPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles3d.html). Brak tekstur lub geometrii z zewnętrznych źródeł.

## Sprawdzenie 2026-10-03

`tests/climate_view.tscn`: parsery i headless 0 błędów; rzeczywisty OpenGL 3.3 Compatibility na RX 7900 XTX również 0 błędów. Test ma własny 180-sekundowy watchdog i sprawdza dach zwykłej świątyni niezależnie od jaskini, natychmiastowe ukrycie kropli, limity trzech profili oraz zachowanie środowiska podwodnej kamery. Sześć rzeczywistych kadrów w `art/screenshots/climate` pokazuje dzień, zmierzch, noc, deszcz, anomalię i tarczę księżyca nad mapą.

W stałym kadrze północnego mostu test zgłosił 58 draw calls / 15 116 primitives bez deszczu i 59 / 17 932 podczas deszczu balanced: dodatkowy koszt emisji to jeden draw call i 2 816 primitives. To liczby renderera z tego kadru, nie benchmark FPS ani obietnica wydajności na starych kartach. Średnia jasność dolnego centralnego obszaru obrazu wyniosła 0.618 w dzień oraz 0.176 nocą. Kształt terenu pozostaje czytelny; lokalne materiały/regiony będą wymagały dalszego strojenia.

`setup` zachowuje już istniejący obiekt `Sky`, zmieniając jego materiał i ustawienia. Podmiana świeżo utworzonego, jeszcze nierenderowanego nieba ujawniła w Godot 4.6 Compatibility wyciek pary natywnych tekstur radiance; użycie tego samego zasobu omija tę ścieżkę bez wyłączania diagnostyki renderera. Test sprawdza zachowanie tożsamości zasobu.

Deszcz nie ma fizycznej kolizji, osobnych kałuż, śladów mokrego materiału ani dodatkowego systemu plusków. Wiek pojedynczych cząstek jest kosmetyczny i nie jest identyczny przy przewinięciu. Pełny stan czasu/frontu pogody należy do oddzielnego deterministycznego modelu; ten węzeł wyłącznie go prezentuje.
