# Milestone 1 — czy wspinanie po poruszającym się kolosie jest stabilne i przyjemne?

## Co zostało zweryfikowane automatycznie

`tools/run_tests.sh` uruchamia 14 testów headless (ok. 2 s):

| Test | Co sprawdza | Wynik |
|---|---|---|
| rig_segments_follow_bones | 17 segmentów podąża za kośćmi, kolos chodzi | ✅ |
| grab_and_hold_on_walking_leg | 6 s trzymania łydki idącego kolosa: dryf w przestrzeni segmentu, odległość kotwicy od collidera | ✅ dryf 0,00000 m przy prędkości powierzchni do 2,7 m/s |
| climb_leg_to_shoulders_frozen / _walking | trasa łydka → udo → biodra → kręgosłup → podhang pod łopatkami → plecy → wciągnięcie na barki | ✅ ok. 7 s, zostaje ~50% staminy, działa też na idącym i skręcającym kolosie |
| traverse_around_limb | obejście uda dookoła (normalna obraca się o 180°) | ✅ |
| armor_blocks_climbing | pancerz na goleni blokuje trasę, gracz nie spada | ✅ |
| exhaustion_drops_player | stamina 0 → puszczenie → lądowanie; brak chwytu, dopóki gracz jest wyczerpany; regeneracja | ✅ |
| brain_shakes_and_rules_limit_it | UtilityBrain próbuje zrzucić gracza po ~2,7 s na ciele, a reguła ogranicza wstrząs do ≤3 s | ✅ |
| shake_drains_more_than_hanging | wstrząs: ok. 20 staminy/s, wiszenie: 3/s | ✅ |
| release_inherits_surface_velocity | puszczenie w trakcie wstrząsu przekazuje prędkość ciała (~4,9 m/s) | ✅ |
| jump_off_and_regrab_midair | skok wzdłuż powierzchni i złapanie się w locie (+1,6 m) | ✅ |
| static_wall_climb_and_mantle | ten sam system na statycznej ścianie z pnączami | ✅ |
| performance_budget | koszt klatki | ✅ ok. 0,25 ms |

`tools/capture_screenshots.sh` uruchamia prawdziwą scenę (renderer, kamera, HUD) z autopilotem
i zapisuje zrzuty: chwyt nogi, wspinanie na idącym kolosie, barki, wstrząs na głowie, upadek.

## Czego NIE da się zweryfikować automatycznie (checklista playtestu)

„Przyjemne na padzie/klawiaturze” wymaga człowieka. Proszę sprawdzić w sandboxie:

- [ ] Czy prędkość wspinania (1,6 m/s) i drenaż staminy dają napięcie, ale nie frustrację?
- [ ] Czy przejście pod nawis (łopatki, spód bioder) jest zrozumiałe, czy „góra” nie myli?
- [ ] Czy kamera przy wspinaniu po plecach/ramieniu pokazuje to, co trzeba?
      (brak auto-prowadzenia jest celowy, a Q/L1 kadruje kolosa)
- [ ] Czy wstrząs jest czytelny (kołysanie ciała gracza, kropka w pierścieniu) i czy da się go przetrwać z pełną staminą?
- [ ] Czy skok wzdłuż powierzchni i ponowne złapanie się działają intuicyjnie?
- [ ] Mysz vs pad: czułość, martwe strefy.

Parametry do strojenia są w `@export` w `PlayerCharacter` (grupy Locomotion / Climbing /
Stamina / Shake response), `GreyboxHumanoid` i `Colossus`.

## Znane ograniczenia (świadome, bez udawania, że działa)

- Brak IK stóp: stopy lekko ślizgają się po ziemi (ETAP 3).
- Brak obrażeń od upadku i animacji lądowania (ETAP 2).
- Stojąc na barkach podczas wstrząsu, gracz jest tylko niesiony. Nie ma jeszcze wytrącania
  z równowagi (ETAP 2: reakcje kolosa).
- Ciało gracza podczas wspinania nie koliduje z innymi segmentami (np. ramię może przez nie
  przeniknąć wizualnie). Kotwica i tak pozostaje poprawna.
- Po wciągnięciu się na krawędź trzeba puścić i ponownie wcisnąć chwyt, żeby złapać się znowu.
  Jest to celowe: zapobiega natychmiastowemu ponownemu złapaniu futra pod stopami.
- Jeden gracz i jedna kamera. `players[]` jest gotowe, split-screen dojdzie w ETAPIE 8.
- Brak miecza, słabych punktów i łuku.

## Następne kroki (ETAP 2)

1. Playtest wg checklisty, strojenie parametrów.
2. Kamera: tryb „wspinanie” z lekkim odsunięciem od powierzchni, obsługa sytuacji, gdy ciało
   kolosa zasłania gracza (przezroczystość lub przesunięcie), dwóch graczy.
3. Upadki: obrażenia, przewrót, wytrącenie z równowagi przy wstrząsie na płaskiej powierzchni.
4. Reakcje kolosa: próba strącenia ręką (swat) jako druga intencja, reakcja na trafienie.
5. Dopracowanie chwytu: animacja rąk, łapanie się przy spadaniu wzdłuż ciała.
