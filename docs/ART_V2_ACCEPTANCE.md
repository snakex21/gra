# Part 2 prototype acceptance

## Delivered and verified

- 40 new environment assets: 120 artist LOD GLBs, cheap separate colliders, 40 placement prefabs, one shared 1K atlas, reproducible generator and editable .blend
- Seven blended surface treatments, 360 m core terrain plus cheap distant continuation, flat modular temple, open plain, slope, dry patch, path, lake, canal and rock-arch canyon landmark
- Three rock families and second-generation ledge/cliff meshes; grouped and grounded escarpment placement
- Compatible ruin columns/bases/beams/walls/corners/arches/doors/stairs/floors/platform/altar/relief/channels/rubble
- Dry grass, fern, reed, shrubs, three living tree families, dead tree, roots and moss; seeded chunked MultiMeshes and explicit LOD bands
- Shared directional wind parameters; cheap opaque water; fixed daylight/sunset/moonlight; no dynamic weather
- Sentinel v2: 17 original visual parts and 51 main LOD GLBs plus six optional extended-foot LOD GLBs, rounded masses, faceted mask, tuft islands, 2K atlas, editable pre-triangulation meshes and joint loops, separate visual adapter
- Seven actual environment viewport captures and four actual Sentinel captures, including a ground-height route view
- Export validation, deterministic scene tests, 430 adapter assertions, 32 existing gameplay tests with 0 failures, structural rendering counters and eight-biome roadmap

## Explicit limits

- This is procedural low-poly prototype art, not a finished production hero sculpt or a complete eight-biome world
- Ground tiling reuses the original 512px maps; the new shared object atlas is 1K and Sentinel atlas is 2K
- Water is opaque visual geometry. No water gameplay, SSR, refraction or fluid simulation is implemented
- The humanoid is a rigid visual kit preserving the existing 17-joint contract, not a new weighted skin/IK system
- Captured performance counters are from software llvmpipe. Target-GPU frame time, shader texture-fetch cost and memory residency require hardware profiling
- Existing source assets, gameplay code, gameplay scenes/tests and project configuration are unchanged; integration/merge belongs to the gameplay owner
- Newer gameplay a3ef45a was tested using an art-only detached overlay: 430 adapter assertions pass with the extended feet; 116 full-suite checks passed, one timing test failed and caused three aggregate failures. Three interleaved clean/overlay timing pairs all exceed the same 0.6 ms threshold; hardware performance acceptance remains open. See `art/reports/v2/latest_gameplay_compatibility.json`
- Local commits are prepared on a branch based on the user’s uploaded assets commit. Publication is separate and must be verified before claiming files are on GitHub
