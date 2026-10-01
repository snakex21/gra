# Stonewater Crossing — validation and cost evidence

Date: 2026-10-01. Blender 4.3.2; Godot 4.6.3 stable. No remote writes.
Art base: `99ed94f7f163f6239209f0b1f835c56bd53bab84`.

## New-art checks

- Export validator: **705 checks passed**. 18 distinct assets, 54 GLBs, one surface
  each, finite positions/normals/UVs, valid padded atlas coordinates, no zero-area
  triangles, no embedded images, decreasing LOD budgets and unchanged gameplay scope
- Godot runtime: **618 assertions passed**, including all 26 manifest passage/floor
  probes plus an additional aqueduct aperture ray. Shared mesh/material identity,
  all LOD bands, opt-in collision and idempotent construction verified
- Blender source: **210 shell coverage rays passed** at/around structural mortar
  boundaries; **120 planar UV aspect-ratio tests passed** on the ribbed pier
- Single-asset edit/export workflow: `parapet_end` re-exported in an isolated
  temporary destination, matching all three budgets `[320,60,48]` and LOD0 bounds
- Import, explicit review-script compilation and full scene headless smoke passed
- Eight fresh actual Godot viewport PNGs passed the capture launcher's existence,
  size, timestamp, success-marker and nonzero render-counter checks
- Earlier Valley exports/runtime and Sentinel-v2 exports/430 runtime checks also
  passed in the final art worktree; their files were not changed by this tranche

Commands are reproducible from repository root:

```sh
python3 tools/art/validate_stonewater.py
blender -b --python-exit-code 1 --python tools/art/test_stonewater_source.py
godot --headless --path . --editor --import
godot --headless --path . --script art/tests/test_stonewater.gd
godot --headless --path . --script art/scripts/stonewater_review.gd --check-only
godot --headless --path . --quit-after 120 art/tests/stonewater.tscn
tools/art/capture_stonewater.sh
```

On this sandbox, writable `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`
were supplied under `/tmp`; the capture launcher configures them itself.
Initial editor-settings errors from inherited read-only directories were corrected
before final import. An unsupported Environment enum in the first review draft
was removed, explicit compile checking added, and all final runs repeated.

## Geometry and material cost

- Unique library triangles: **26,152 / 5,796 / 2,424** for LOD0/1/2
- 54 visual GLBs total approximately **2.63 MB**, editable source approximately
  **1.95 MB**. Exact final byte counts: `export_budgets.json`
- **230 independent static collision shapes**, maximum 42 in a single module
- Curved opening proxy chord deviation <=6 cm; outer curved surfaces <=7 cm
- **Zero new texture images**; new models use the existing shared 1024px atlas
- One mesh surface per visual GLB; no per-model texture or material duplication
- Showcase: 69 new-kit instances, 32 reused Valley props, 34 foliage instances in
  two no-shadow MultiMeshes; separate 18-instance LOD0 review catalogue
- Near terrain: 13,824 triangles / 12 chunks plus coarse distant continuation
- One shadow-casting directional light, two splits, 130m range, configured 4096px
  directional shadow atlas; no shadow-casting local lights
- Landscape LOD bands 52/120/420m; review catalogue 250/400/900m; foliage cull 150m
- Loaded scene inventory includes eight material resources, including review-only
  catalogue backdrop and two scale-staff materials. All new GLB instances share one
  atlas material. Texture-reusing pads/water are separate shared scene materials

## Actual rendering evidence

`render_costs.json` contains every view's measured draw calls, primitives, objects,
texture/buffer/video allocations and a separate configured scene inventory.
`capture_source_hashes.json` binds these captures to the exact model and script
inputs. Eight files in `art/screenshots/v3/` are untouched Godot viewport images,
not Blender renders, image generation, or retouched concept art.

The renderer is Compatibility/OpenGL on **Mesa llvmpipe**, 1280×720. Counters
include relevant shadow/UI work; source triangles and configured LOD nodes are
not frame submissions. Renderer memory counters include sky/fonts/render targets
and are not per-asset resident VRAM or hardware peak memory. No target-device FPS,
Forward+ GPU performance, Godot 4.4.1 runtime result or Windows performance is claimed.


| Actual viewport | Draw calls | Rendered primitives |
|---|---:|---:|
| 01_crossing_day | 224 | 51,865 |
| 02_crossing_sunset | 223 | 51,463 |
| 03_crossing_blue_hour | 226 | 51,941 |
| 04_bridge_detail | 204 | 128,345 |
| 05_cistern_interior | 81 | 91,385 |
| 06_oculus_court | 167 | 111,115 |
| 07_canyon_floor | 220 | 160,803 |
| 08_kit_catalogue | 87 | 68,084 |

Renderer allocations in this run: 53,320,641 texture bytes, 10,233,396 buffer bytes, 63,554,037 reported video bytes (about 63.6 MB, decimal). These include the review scene and are not a target GPU benchmark.

## Visual review corrections

Actual render inspection drove these corrections before final capture:

1. Closed accidental structural arch/vault slits, preserving intentional apertures
2. Replaced anisotropic face UV normalization with aspect-preserving projection
3. Stitched near/far terrain boundaries without visible missing wedges
4. Framed the hero from the aqueduct side; made catalogue labels readable
5. Grounded supports, added bearing caps, aligned buttress upper bearings and scale staff
6. Removed excessive water specular highlights; reused existing stone texture on pads

Hard LOD transitions, varying texel density between differently sized atlas faces,
coarse collision shapes and the deliberately simple static water remain explicit
prototype trade-offs. The showcase is an art assembly, not a finished playable level.

## Gameplay baseline and compatibility

See `baseline/baseline_summary.md` for exact snapshot hashes, commands, pass/fail
counts and the final tested upstream revision. The existing strict 0.6ms CPU test
fails in pristine controls as well as historical art baselines; it is not silently
waived or represented as a full pass. The direct functional checks pass in the
completed clean controls; dependent aggregate failures are identified separately.

Scoped compatibility overlays copy only new Stonewater files and absent standalone
Valley dependencies. Existing ArenaArt, bosses, player, cameras, physics, scenes,
tests and project configuration are never overwritten. The original colossus
contract and all gameplay paths remain byte-identical to the art base.

Latest gameplay adds boss-specific climb-cue meshes; the older generic Sentinel-v2
adapter is not automatically appropriate for Valus/Gaius. Stonewater is independent
of that adapter and does not attempt to replace any boss visual or rig.
