# Validation and measured render cost — 2026-10-01

## Result

- Original deterministic Blender build: completed with `ART_GENERATION_OK assets=36`
- Actual Godot import: passed, no parse/import errors in the final run
- Art contract suite: **809 checks passed**
- Export validator: **36 assets, 108 explicit LOD GLBs, 13 PNG textures**, all finite and within texture limits; GLB bounds match manifest
- Separate coarse collision exports: **9 hulls × 48 triangles**; other modules use primitive/ramp/heightfield proxies
- Single-asset source re-export: passed for `rock_01`, LODs 320 / 152 / 56; evidence in `single_asset_export.log`
- Both showcase and opt-in original-sandbox wrapper ran and produced actual viewport PNGs
- Diff guard: existing `src/`, `scenes/`, `tests/`, `project.godot`, existing test scripts and CI are byte-for-byte unchanged from b615585

## Existing gameplay tests: not a full green suite

Both baseline and after runs pass **31 functional/probe tests** and fail the
same existing `test_performance_budget` on the shared cloud CPU:

- Before art work: **0.758 ms/tick** versus the historical ~0.25 ms reference
- After art work: **0.718 ms/tick** versus the same reference

The original test scene does not load the art scenes. No test threshold or
assertion was changed. These two noisy shared-host observations do not establish
an art performance improvement or regression. See `gameplay_baseline.log` and
`gameplay_after.log`; do not label the entire legacy suite passed.

## Actual renderer counters

Godot 4.6.3-stable (official); gl_compatibility; Mesa llvmpipe (LLVM 19.1.7, 256 bits); internal
viewport **1280×720**. The software renderer reports an unsupported VSync-mode
warning, then successfully renders the scenes. No GPU hardware FPS claim is made.

| View | Draw calls | Submitted primitives |
|---|---:|---:|
| 01_basin_day | 304 | 65654 |
| 02_basin_sunset | 304 | 65642 |
| 03_basin_night | 304 | 65660 |
| 04_sentinel_front | 257 | 81457 |
| 05_ruin_modules | 253 | 77518 |
| 06_ground_vegetation | 178 | 63019 |

These are Godot `Performance` counters for real rendered frames, including work
such as shadow passes, not a count of unique source triangles. Scene contents:
**133 modular asset instances, 1713 grass instances,
17 rigid colossus visual attachments**, one sun, procedural sky.

- Renderer texture-memory counter: **50,742,893 bytes** (includes renderer allocations such as sky/render targets; not just PNG files)
- Renderer buffer-memory counter: **9,151,420 bytes**
- Unique source LOD0 triangles, all 36 assets: **12,687**
- All runtime GLB files: **2,010,584 bytes**
- Worst-case RGBA8 + mip estimate for all 13 source textures: **22,369,621 bytes**; this is a format estimate, not the renderer counter

Full machine-readable evidence: `asset_budgets.json`, `render_costs.json`.

## Screenshots

`../screenshots/01_basin_day.png`, `02_basin_sunset.png`, `03_basin_night.png`,
`04_sentinel_front.png`, `05_ruin_modules.png`, `06_ground_vegetation.png`,
`07_sandbox_integration.png` are directly saved Godot viewport images, without
retouching, compositing, or Blender rendering. The final wrapper image retains
the original HUD, including its software-host frame-rate reading; this is not
the user's target machine and is not a performance promise.

## Deliberate limitations

This is an art prototype: hard LOD transitions, opaque low-poly foliage,
rigid segment visuals, approximate static collisions, one small authored basin.
The existing greybox player and its gameplay are untouched. No target GPU,
VR, mobile, console, Forward+ benchmark, full-world streaming, animation-retargeting,
weather, water, audio or VFX work is claimed.

## Independent review

The frozen implementation received a separate review: clean import, the 809 art
checks, plus 182 additional GLB/metadata, identity-transform, collider and terrain
normal checks. The review caught and corrected an inverse-axis metadata error
before final delivery. Every exported LOD0 bound is now checked against its GLB.

An isolated edited-source round trip widened rock_03 by 10% while retaining its
34 m source-catalogue offset. Only that asset's four GLBs and its manifest entry
changed; all other models and textures stayed byte-identical. Output was
320 / 152 / 56 visual triangles and a 48-triangle collision hull; local-space
bounds updated by 1.1×, without baking the catalogue offset into the runtime mesh.

The ground/vegetation review camera was moved away from a foreground boulder.
Screenshot 06 and its renderer counters were then recaptured in Godot. This
change is confined to the isolated art scene, not the gameplay camera.
