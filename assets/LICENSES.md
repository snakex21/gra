# Saltward art prototype — source and licence manifest

This manifest applies **only to the new Saltward art pack**. It does not relicense
the existing game, `src/`, `scenes/`, `tests/`, or the repository as a whole.
The pre-existing repository README still leaves its project-wide licence to the owner.

## Original assets: CC0-1.0

The geometry, textures, palettes, layout and the Saltward Sentinel design in this
pack are original work generated for this repository. No models, textures, maps,
audio, characters, extracted files, screenshots or other assets from Shadow of
the Colossus or any other commercial game were used. The reference is limited
to broad ideas: scale, solitude, worn stone and readable material regions.

The new artistic assets are dedicated to the public domain under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
See the [legal text](https://creativecommons.org/publicdomain/zero/1.0/legalcode).
To the extent possible under law, the contributors waive copyright and related
rights in these assets. They are provided without warranty. Attribution is welcome
but not required. Do not infer any trademark rights or endorsement.

| Files | Authoring / provenance | Licence |
|---|---|---|
| `art/source/saltward_kit.blend` | Original meshes, two editable source scenes; packed procedural textures | CC0-1.0 |
| `models/environment/*.glb` | Original scripted geometry and separate coarse collision hulls | CC0-1.0 |
| `models/colossus/*.glb` | Original rigid visual parts, fitted to the existing segment contract | CC0-1.0 |
| `textures/environment/*.png` | Deterministic NumPy-generated value noise and original palette; no photographs | CC0-1.0 |
| `environment/**/*.tscn`, `art/tests/*.tscn` | Original art scene composition / prefabs | CC0-1.0 |
| `materials/environment/*.tres` | Original material parameters and texture references | CC0-1.0 |
| `art/screenshots/*.png` | Actual Godot viewport captures of this art prototype | CC0-1.0 |
| `assets/art_manifest.json`, `assets/colossus_visual_contract.json` | Generated original asset inventory and factual integration metadata | CC0-1.0 |

Per-asset provenance, LOD counts and collision strategy are in
`assets/art_manifest.json`. Checksums are in `assets/art_checksums.json`.
The baseline skeleton metadata describes the existing game; it is not a new rig.

## Original pipeline code: MIT

New scripts in `tools/art/`, `art/scripts/`, `art/tests/*.gd`, and the new terrain
shader `materials/environment/terrain.gdshader` are under the MIT licence in
`tools/art/LICENSE`. This scope excludes pre-existing gameplay source and tests.

## Tools and external assets

- No downloaded asset packs, external texture libraries, proprietary services,
  paid add-ons, external fonts, music or sound effects are included
- Blender 4.3.2 and Godot 4.6.3 were used as authoring/runtime tools, not bundled
  into the asset pack. Their own licences continue to apply to the tools
- NumPy ships with the tested Blender build; runtime use of the GLBs requires
  neither Blender nor NumPy and makes no network requests

## Part 2 original additions

The same asset-only CC0-1.0 dedication applies to `art/source/ancient_valley_v2.blend`,
`art/source/sentinel_v2.blend`, `models/ancient_valley/`, `models/sentinel_v2/`,
`textures/ancient_valley/`, `textures/sentinel_v2/`, `environment/ancient_valley/`,
and the actual viewport captures in `art/screenshots/v2/` and `art/screenshots/sentinel_v2/`.
Their new generators, adapters, tests and shaders are under `tools/art/LICENSE` (MIT).
These are original procedural assets. Existing gameplay code and repository-wide
licensing remain outside this scope.

## Part 3 original additions — Stonewater Crossing

The same asset-only CC0-1.0 dedication applies to `art/source/stonewater.blend`,
`models/stonewater/`, `environment/stonewater/`, `environment/stonewater_crossing.tscn`,
`assets/stonewater_manifest.json`, and actual viewport captures in `art/screenshots/v3/`.
The new generators, single-model exporter, render adapter, showcase scripts and tests
are MIT under `tools/art/LICENSE`. Geometry and composition are original procedural
work. Existing Ancient Valley atlas is reused, with no additional external assets,
photos, fonts, audio or commercial reference geometry. This does not relicense gameplay.

## Part 4 original additions — Saltwind Expanse

The same asset-only CC0-1.0 dedication applies to `art/source/saltwind.blend`,
`models/saltwind/`, `textures/saltwind/`, `environment/saltwind/`,
`environment/saltwind_expanse.tscn`, `assets/saltwind_manifest.json`, and actual
viewport captures in `art/screenshots/v4/`. New generators, exporter, render
scripts, shaders and tests are MIT under `tools/art/LICENSE`. Geometry, texture
fields and composition are original local procedural work. No reference-game
assets, third-party art libraries, photos, fonts, AI-generated images or audio
are included. Existing gameplay code is not relicensed.

## Mirewood Fen (part 5)

Original geometry and locally generated textures in `models/mirewood/`,
`textures/mirewood/` and `art/source/mirewood.blend`: CC0-1.0.
Original generator, exporter, Godot art-only components and QA under
`tools/art/*mirewood*`, `art/scripts/mirewood*`, `art/tests/*mirewood*`: MIT,
under the existing `tools/art/LICENSE`. No downloaded models, commercial-game
assets, third-party textures, paid generation service or ImageGen was used.
Shared local primitive/UV helpers retain the earlier pipeline's MIT terms.
Existing game code is not relicensed.

Last verified: 2026-10-01.
