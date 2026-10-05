# Colossus material comparison evidence

The pipeline exports the actual Godot-loaded Valus, Gaius and Pelagia production
sculptures. Blender does not recreate the models, edit UVs, repaint materials, add
wear, or invent replacement anatomy. Before is the clean `d0569c3aee1af97c9b19d868c840201a158bfedd`
checkout. After uses the material-pass worktree or an independently imported copy.

## Capture contract

- Instantiate the production colossus classes, then run the same `ArenaArt`
  dressing stack used by `GameWorld`, ending in `ColossusArtV3`
- Freeze controllers and physics processing at their production ready/rest skeleton
- Force pending skeleton transforms, use production `_sync_segments`, and await
  physics/process frames so `AnimatableBody3D`'s actual global transforms settle
- Keep all visible production meshes and the current weak-point/helmet visuals
- Capture each of the three authored LODs separately at identical camera settings;
  runtime distance culling is deliberately bypassed for inspection
- Record exact loaded arrays (including UVs and normals), effective materials,
  compressed texture pixels, transforms and source SHA-256s, then export using
  Godot `GLTFDocument`
- Protected weak points use their production visual updater. Open weak-point
  emission stays at its actual `_ready` value, avoiding wall-clock pulse drift

This is frozen material-authoring evidence, not live gameplay, a Godot framebuffer,
GPU validation, animation validation or a performance measurement. Gaius's blade
is in the existing rest skeleton pose. Studio lights and background are presentation
only; no studio floor occludes the blade. Blender's fixed AgX view transform differs
from Godot. Godot-specific shadow flags are not transported by GLB.

## Reproduce

Import both checkouts first with writable XDG locations and an explicit `--log-file`.
The project otherwise logs under `res://data/logs`. Never reimport a cache while
another process exports or runs tests against it. The baseline must be clean.

```sh
python tools/art/capture_colossus_previews.py /tmp/colossus-evidence \
  --baseline-root /path/to/clean-baseline \
  --after-root /path/to/independent-imported-after-copy --width 960 --samples 64
python tools/art/verify_colossus_previews.py /tmp/colossus-evidence
python tools/art/assemble_colossus_previews.py /tmp/colossus-evidence
python -m unittest discover -s tools/art -p 'test_colossus_preview_audit.py' -v
```

`--variant before|after`, `--export-only`, `--render-only` support staged operation.
`--quick` renders LOD0 overview, surface and weak-point views for early visual review.
The final evidence covers 9 scene pairs and 15 image pairs (30 original PNGs):
all three overview LODs plus LOD0 surface and weak-point context for all three bosses.
Blender Cycles runs on CPU, 64 samples, seed 42, no denoising, with the same cameras,
lights, resolution and color transform for every before/after pair. Pelagia's
weak-point view is from the rear so the three steering controls and protected shell
sigil are not hidden behind the front horns.

## Fail-closed verification

`verify_colossus_previews.py` requires exact array hashes and transforms. Weak-point
semantic positions, states, radii and gameplay visual materials must remain exact.
Only sculpture materials may switch from the old shared atlas to the scoped finish;
normal strength, culling, transparency, emission and other non-PBR fields stay exact.
The new ORM bindings require roughness G and metallic B with scalar multipliers 1.
It also checks 2048² source textures, VRAM compression, mipmaps, proper normal-map
importing and imported-cache source MD5s.

Every snapshot is bound to actual source SHA-256s. Every image is bound to its GLB,
renderer script and output digest. The verifier rejects stale output or mismatched
camera/light/settings. `verification.json` retains these checks. Capture provenance
records the baseline commit and source worktrees; release tooling independently binds
all referenced sources to the final packaged commit.

`review_board` shows overview and surface comparisons; `lod_board` shows all LODs;
`weakpoint_board` shows protected/open gameplay context. Original render PNGs remain
untouched. Boards only resize and label them, retaining image and composer digests.
PNG boards are the full-quality reference; JPEGs are compact delivery previews.
