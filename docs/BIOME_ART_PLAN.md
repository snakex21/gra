# Ancient Frontier: biome art plan

## Part 2, first coherent environment tranche

Base: user's `assets` upload `a838b5b`. No merge from a gameplay branch and no edits to `src/`, `scenes/`, gameplay tests, or `project.godot`.

Ancient Valley is a 360 × 360 metre art test, not a finished gameplay world. The empty central basin, legible winding route, temple, lake, slope, dry patch, canyon and distant rock-arch landmark are composed to test scale and silhouette. The tree/rock placement is deliberately sparse. The seed is exposed on `ancient_valley.gd`; changing it deterministically regenerates scatter without editing gameplay.

### Implemented environment assets

40 original additions / 120 explicit LOD GLBs, one surface per model. Editable source: `art/source/ancient_valley_v2.blend`; reproducible generator: `tools/art/generate_ancient_valley.py`.

- Ruins: column, broken column, base, 4 m beam, wall, broken wall, corner, arch, door, stairs, floor, platform, altar, abstract relief, channel, two rubble arrangements
- Geology: slate, chalk and basalt families (three silhouettes each), ledge, cliff, open rock arch
- Vegetation: dry grass, fern, reed, moss patch, heather, thorn shrub, cypress, oak, willow, dead tree, roots
- Shared 1K atlas; seven blended terrain surface treatments: dry earth, grass, rock, path, sand, wet earth, ruin stone. Wet earth shares earth texture data with a distinct color/roughness response. Ground tiles reuse the original 512px seamless maps; no claim that these are newly authored 2K ground textures
- Shared wind direction and strength for foliage/water; rooted vertex displacement, no dynamic weather
- Opaque lake and shallow canal. No SSR, refraction, water physics, swimming implementation, or reflection render target
- Fixed day, sunset and moonlight presets; no time-of-day simulation

### Module and collision contract

Metres; +Y up; -Z forward; ground-centre pivots. Floors/platforms/beams/walls use a 4 m grid. Columns are 2 m wide at the plinth. Temple floors deliberately overlap a tiny margin to avoid cracks; decorative floor collision is supplied by the terrain. Arches/doors use separate pier/voussoir boxes, never a convex hull closing the opening. Channels use a bed plus two edge boxes. Stairs use one wedge. Rock hull exports are coarse; tree collisions are trunks only. Vegetation has no collision or shadows. Terrain has a separate 91 × 91 height field.

### Cost evidence and limits

`art/reports/v2/export_budgets.json`: actual GLB triangles, monotonic LOD verification, collision triangle caps, atlas dimensions and gameplay-scope fence. Unique mesh totals are not the same as the cost of all placed instances.

`art/reports/v2/runtime_tests.json`: actual instanced scene counts, collision shape count, height probes and repeated-seed scatter equality.

`art/reports/v2/render_costs.json`: actual Godot viewport draw calls / primitives / objects / texture memory for seven fixed views. The adapter is software llvmpipe; these counts are useful structural evidence, not a target-hardware FPS benchmark. Texture memory includes the loaded project/review resources. Shadows add passes; count the captured view rather than assuming one draw per model.

Terrain: 9 chunks, 28,800 render triangles plus a 1,152-triangle non-collidable distant continuation. Foliage: 24 m cells, three explicit distance bands 0–32 / 32–62 / 62–95 m. Solid props normally use 45 / 105 / 340 m; cliffs use 90 / 190 / 580 m. All LODs are loaded resources; visibility bands reduce rendered geometry, not automatically disk size or all resident memory. One directional light, bounded shadow distance, no realtime GI.

## Eight-biome expansion roadmap

These are future reuse/gap plans, not claims that eight biomes are delivered.

| Biome | Reuse now | Missing signature assets | Cost strategy |
|---|---|---|---|
| Ancient grass valley | Temple kit, slate, grass, oak | Hand-authored hero temple damage and ground decals | Existing shared atlas, sparse foliage, low horizon meshes |
| Salt desert | Chalk, dry grass, dead trees, sand treatment | Salt crust, eroded needles, wind-carved banks | Opaque ground shader; few shadow casters |
| Highland plateau | Basalt, ledges, cliffs, cypress | Scree seams, tall broken escarpments | Large LOD silhouettes; terrain chunk culling |
| Wetland ruins | Willow, reeds, channels, lake | Root islands, submerged module variants | Shared opaque water; keep transparent effects optional |
| Moss forest | Oak, fern, moss, roots | Mature hollow trunks, dense understory variety | Clustered MultiMeshes; cap shadowed trees |
| Coastal ravine | Chalk, rock arch, sand | Eroded sea stacks, foam shoreline cards | No ocean simulation; distance impostor study later |
| Volcanic basin | Basalt, rock families, sparse dead trees | Fissures, cooled lava textures | Static emissive accents; no volumetric smoke by default |
| Frost sanctuary | Modular temple, cliff silhouettes | Snow caps, ice crust, frost vegetation | Shared material variant, simple snow mask, no particle storm |

## Reproduce and review

1. `blender -b --python tools/art/generate_ancient_valley.py`
2. `godot --headless --editor --path . --import`
3. `python tools/art/validate_ancient_valley.py`
4. `godot --headless --path . --script art/tests/test_ancient_valley.gd`
5. Open `art/tests/ancient_valley.tscn` in Godot, or run `bash tools/art/capture_ancient_valley.sh` from a real display

Review controls: 1/2/3 lighting, V view, H overlay. Captures are actual viewport images under `art/screenshots/v2/`. Headless validation does not substitute for visual review. The scene contains an art review camera only; the gameplay camera is untouched.

## Remaining quality work

This is a coherent procedural art expansion, not a claim of final production sculpt quality. Hero-specific erosion, less repetitive distant cliff silhouettes, authored foliage silhouettes, seam-focused module reviews, and hardware profiling remain worthwhile. A dedicated Sentinel v2 visual/source pass is maintained separately. Integration with gameplay should be performed by the gameplay owner after reviewing the visual adapter contract.
