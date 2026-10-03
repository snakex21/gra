# Cloud environment dressing pass

## Local integration accepted — 2026-10-03

The supplied package is now integrated into the current game together with the
separate core PCVR preview. This document retains the package's original cloud
evidence below as provenance; its former "unpublished" integration instructions
do not describe the current source checkout.

Local Godot 4.6.3 verification passed:

- Strict `environment_dressing` and `landscape_v5`, headless and actual
  Compatibility rendering, without script errors or resource leaks.
- Actual GPU transforms, common LOD bounds, stable placements and bounded
  instance tints; the test accepts the documented 16-bit channel precision of
  Compatibility, and still requires identical uploaded colours across LODs.
  [Godot MultiMesh precision](https://docs.godotengine.org/en/4.6/classes/class_multimesh.html#class-multimesh-method-set-instance-color).
- Four native captures in `art/screenshots/landscape_v5/`, including
  `understory_close.png` showing an actual groundcover colony.
- `graphics_quality`: identical 29,060-byte checkpoint across the quality
  transitions. `forbidden_lands --geometry-only`: 21 routes, 4,269 physical
  surface samples and no missing floors. `main_layout` and
  `climate_persistence` also passed after integration.

The full local landscape contains 7,531 groundcover placements in 2,454
groundcover MultiMesh nodes. Together with existing detail it has 3,663
MultiMesh nodes, 36 shared meshes and 266 build jobs. Visible groundcover
placement totals for low/balanced/high are 2,982 / 5,362 / 7,531. These
world-wide sums are not simultaneous draw calls or an FPS benchmark. The
native fixture measured a maximum single detail job of about 7 ms in one
run; the queue's 1.8 ms budget is checked between jobs. Low reduces visible
geometry and range, while allocated nodes and transform buffers remain.
Older GPU performance and stereo PCVR frame times still require hardware
measurements.

Run the maintained strict checks with:

```text
python tools/run_environment_tests.py
python tools/run_environment_tests.py --native
```

Logs and reports stay in `tests/output/`; the original handoff package is
preserved locally in `tests/output/environment_dressing_handoff/` and is
excluded from Godot import and version control. CI runs the headless checks.

## Original package notes

Base: `42cffe9f5b4a9a394c355a80ef50f7040fa8323e` on `claude/sharp-cray-x761iy`.

## Scope

- Continuous, gently warped biome colour transitions (approximately 240 m wide), including a gradual height-to-rock tint.
- Woodland density follows the same smooth regional weights instead of chunk-wide forest switches.
- Seeded colonies of existing Saltward grass tufts, dry grass and salt shrubs, with varied yaw and scale. The second pass arranges elongated roadside drifts and compact growth beside existing rocks, trees and ruins, with smaller colony edges and restrained regional tint.
- Groundcover uses the actual rendered triangle surface and rejects steep slopes, submerged land, the central shrine area, all arena discs and road corridors.
- Existing rocks and trees are reused. No new textures, AI images or third-party assets.

## Integration

This is a local, unpublished change. Apply the supplied commit/patch on a clean branch after reviewing concurrent work. Do not overwrite another working tree.

Production changes touch `src/world/forbidden_lands_terrain.gd`, the new `src/world/environment_groundcover.gd`, and a small render-only hook in `src/game/graphics_quality.gd`. If that terrain file has changed upstream, retain the newer gameplay code and reconcile only `biome_weights`, `biome_color`, the visual placement part of `_detail_chunk`, and its final `EnvironmentGroundcover.append_chunk(details, origin, groups)` call. Include the new `materials/environment/groundcover_atlas.tres`: it reuses the existing Saltward atlas and enables instance tint without changing other foliage materials.

No edits to co-op, NPCs, enemy AI, boss roster, navigation, collision, route generation, terrain height, saves or combat. Gameplay RNG is untouched. Art jobs remain reconstructible from fixed local seeds.

## Rendering budgets

The existing nine landscape kinds retain their shared atlas and three LODs. Understory reuses three existing opaque one-surface models and their three authored LODs (nine cached meshes, one shared opaque groundcover material using the existing foliage texture). Grass triangles per LOD: tuft 33/15/5; dry 27/12/4; shrub 297/141/44.

Groundcover is grouped in 64 m cells, with no shadows or transparency. Grass LOD ranges end at 28/55/85 m; shrubs at 45/85/140 m. Every instance is visual only. These are distance-culling limits, not measured frame-rate guarantees. Existing 256 detail jobs and ten cache/bridge jobs remain in place. The initial 20-colony experiment was reduced to ten colonies in the first commit and eight in the final composition pass to moderate object/build overhead.

Existing low/balanced/high settings select 35%/65%/100% of each batch (rounded up) and 70%/85%/100% of the listed distances. Balanced is the default. Changes apply in place using `visible_instance_count`; they do not reallocate meshes or regenerate placements. This reduces submitted geometry, not the preallocated CPU node or transform-buffer count. Late-built chunks inherit the active world profile. The GraphicsQuality hook stores render-only metadata and touches only batches tagged `groundcover_kind`.

## Run and test

Godot 4.4+ is required; this workspace uses 4.6.3. The repository's `tools/run_local.py` launcher targets Windows. On Linux, use the installed Godot binary with writable XDG directories and an explicit log path:

```
mkdir -p tools/runtime/{cache,config,data} tests/output
export XDG_CACHE_HOME="$PWD/tools/runtime/cache"
export XDG_CONFIG_HOME="$PWD/tools/runtime/config"
export XDG_DATA_HOME="$PWD/tools/runtime/data"
godot --path . --headless --editor --import --quit --log-file tests/output/import.log
godot --path . --headless tests/environment_dressing.tscn --log-file tests/output/dressing.log
godot --path . --headless tests/landscape_v5.tscn --log-file tests/output/landscape.log
godot --path . --headless tests/forbidden_lands.tscn -- --geometry-only
```

Normal play: `godot --path . -- --new-game`. The changes are integrated into the existing game and world builder, not a separate mock-up.

On a machine with a working graphics display, `godot --path . tests/landscape_v5.tscn` renders the actual forest, route and bridge fixtures and writes PNGs to `art/screenshots/landscape_v5/`. `tests/forbidden_lands_capture.tscn` captures the actual whole-world overview and terrain views. Run the same scene/camera on the baseline checkout to obtain a fair before/after pair.

## Verification limits

The cloud environment has no DISPLAY, X11 socket or Xvfb. An isolated Xorg attempt failed to establish sockets; a direct socket probe returned EPERM. No rendered screenshots or GPU/FPS measurements are claimed. Godot's dummy headless renderer does not expose uploaded MultiMesh transforms reliably: placement assertions use the exact sampled transforms, while GPU transform assertions are retained for real-renderer runs. Headless geometry tests do not establish whole-game gameplay correctness or fix any previously observed upstream headless crash. Visual acceptance should follow actual rendering on a permitted display.

## First-pass headless results (superseded metrics, 2026-10-03)

All following runs exited 0 on the first-pass commit a277962; they were rerun successfully after the second pass:

- Import / script registration
- `environment_dressing`: all 256 chunks, deterministic sampled placement bytes, road/arena/valley clearances, height/slope rejection, smooth biome seams, three profile transitions and late-built profile inheritance
- `landscape_v5`: unchanged physical/terrain vertex bytes, shared assets/materials and bounded LODs
- `forbidden_lands --geometry-only`: 21 route geometries, no action-driven Agro journey included
- `main_layout`: actual New Game, recording header, portable Continue, older-layout checkpoint and new-game reset
- `git diff --check`

Single-run comparison (not a stable hardware benchmark): baseline landscape build/dress 0.982 s, final 1.454 s; maximum detail job 0.883 ms → 3.073 ms. A job can exceed the queue's nominal 1.8 ms budget because the queue checks elapsed time between jobs. No FPS conclusion is possible from these headless timings.

Entire landscape: 1,002 → 4,197 MultiMesh nodes; 2,733 → 30,531 allocated instance transforms summed over all LODs; 27 → 36 shared meshes; 266 jobs unchanged. These world-wide allocations are not simultaneous draw calls. Additional node/resource RAM overhead was not measured.

Groundcover alone: 8,840 unique placements (5,060 tuft, 3,256 dry grass, 524 shrubs), 2,988 batches, 26,520 all-LOD allocated transforms. Their raw 3D transform payload is approximately 1,272,960 bytes (48 bytes each), excluding engine/GPU alignment and node/resource overhead. No new texture allocation is authored; an existing foliage atlas is reused, but its additional residency versus a baseline scene was not GPU-profiled.

The low/balanced/high visible placement sums are 3,581 / 6,248 / 8,840; all-LOD visible sums 10,743 / 18,744 / 26,520. Rounding each small batch upward makes effective percentages differ from the nominal ratios. Distance ranges enable only one nominal LOD band per batch; grass disappears past 59.5 / 72.25 / 85 m and shrubs past 98 / 119 / 140 m for low / balanced / high respectively. Actual camera/frustum-cull draw counts require rendering.

First-pass regression guards capped groundcover at 12,000 unique placements and 4,000 batches; the final pass tightens these to the actual first-pass ceiling (8,840 / 2,988). Integration onto later gameplay commits still requires those commits' own tests.

## Final composition pass and review fix

The first commit remains a reviewable checkpoint. A second commit redistributes a smaller candidate budget into roadside drifts and colonies beside actual landscape props. Eight colonies replace ten; no new species or textures are introduced. A separate shared material enables deterministic per-instance tint without modifying the original foliage material. Position-based colours are identical across LODs and settings. Compact colony edges are shorter than their centres.

Independent review identified an LOD correctness issue in the first pass: three-metre hysteresis on independently hidden LODs can hide both neighbours near a transition; different mesh bounds can also shift their distance centres. The final pass uses zero margins and an identical conservative custom AABB for all three LODs of each batch, covering every transformed mesh at every level. Regression tests check enclosure and initial-hidden culling conditions immediately before/at/after each quality-scaled boundary. These are source-semantics/headless checks, not a GPU visual test.

Final actual integrated world (with contextual landmark placement):

- Groundcover: 7,531 unique placements, 2,454 batches, 22,593 allocated all-LOD instances
- Visible placement pools low/balanced/high: 2,982 / 5,362 / 7,531
- Visible all-LOD sums low/balanced/high: 8,946 / 16,086 / 22,593
- Raw transform-plus-colour payload estimate: 1,445,952 bytes (64 bytes per instance). Colour increases bytes per instance versus the first pass, while total placements/batches decrease
- Entire landscape: 3,663 MultiMesh nodes, 26,604 allocated all-LOD instances, 36 shared meshes, 266 jobs
- The standalone fixture without landmark context is separately 7,001 placements / 2,388 batches; it is not the production-world total

Three sequential final headless runs all passed: build/dress 1.539 / 1.478 / 1.434 seconds; maximum individual detail job 2.892 / 4.533 / 4.750 milliseconds. Variability and overshoot of the nominal queue budget are explicitly retained. These figures do not prove frame-time smoothness. Real render performance remains an acceptance step.

Final PASS checks include import, all-world dressing and budget regression, contextual landmark placement and unchanged input transforms, deterministic colour, common AABB containment and no-gap semantics, live/incremental quality, unchanged physics/terrain, all 21 geometry routes, New Game/Continue, and whitespace checks. No action-driven whole-game soak or visual acceptance is claimed.
