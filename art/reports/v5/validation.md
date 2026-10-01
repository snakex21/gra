# Mirewood — final-source verification, 2026-10-01

## Passed scoped checks

- 31 distinct models; 93 actual GLBs. Export validation: 1261 checks.
- Blender source validation: 1158 checks, including every editable LOD, packed atlas,
  isotropic architecture UV metrics and all clear visual passage probes.
- Godot art-only runtime: 1219 checks, zero assertions failed. Includes
  opt-in passive collision, imported mesh/material identity, contiguous LOD ranges,
  clear/hit passage probes, terrain mesh interior-edge continuity, deterministic
  scatter, finite ground contacts and near-edge rays.
- Isolated regeneration: 99/99 byte-identical runtime contracts (93 GLBs, five PNGs,
  manifest); the original source was untouched. Blender binary metadata excluded.
- Manual editing: unflagged regeneration refused; selected edited LOD0 differs;
  only the selected model's three LODs exported. Original source hash unchanged.
- 11 actual Godot 1280×720 viewport captures, from the final models/scripts,
  inspected individually and again as a final contact sheet. No painted-over PNGs.
  After capture, the unused script default id was corrected to root_island;
  every shown prefab explicitly sets its id, so this changes no rendered view.
  The final default construction and full scoped runtime suite were re-tested.
  Review corrected hollow trunk silhouette, fern attachment, tree foliage,
  stair direction and catalogue labels. Four catalogue pages cover all 31 models.

## Exact content and workload

Unique library triangles LOD0/1/2: [63577, 18544, 7059].
438 simple library collision shapes. GLBs: 8.05 MB;
editable source: 3.85 MB; five source textures:
6.95 MB. Five textures, each 1024×1024.
Landscape: 69 props plus 992 logical vegetation instances. 31 hidden catalogue
items remain loaded; three vegetation bands allocate 2976 instanced transforms.

Landscape view counters: 91–167 draw calls,
102,878–152,178 submitted primitives.
Catalogue: 33–43 draw calls.
Renderer-reported textures: 55.07–55.33 MB.
Counters include UI, shadow passes, sky and render targets where applicable;
these are not source totals, per-asset VRAM, or target-hardware FPS.
Godot 4.6.3, Compatibility OpenGL, Mesa llvmpipe, one shadow light,
130 m shadow distance, project shadow atlas 4096. No GPU performance PASS claim.

## Explicit non-passing boundary rays

24/49 point rays exactly on heightfield cell/triangle boundaries missed.
49/49 offset rays and 49/49 finite-sphere contacts passed. The original exact-ray
misses remain reported, not converted into a PASS. Prior pack's independent
flat-heightfield control showed the same 24/49 backend behavior. No player query,
physics configuration, traversal controller or collision layer was changed.

## Integration and scope

Art base: f48162425002ec23562a271c11b4abd8b6c593cf.
Isolated gameplay snapshot: 23ec961224956a095d5b7be7f0e11deae07ec228.
177 tracked gameplay source/scene/test/project files are byte-identical to that
snapshot. Independent Mirewood smoke: 1219 checks, zero failures on the isolated
overlay. No actors, Sentinel adapter, Valus visual cues or gameplay scenes changed.

The separate compatibility full-import attempt was killed with exit 137 during
inherited texture reimport; its actual incomplete log is preserved. Reused the
verified cache for byte-identical art exports for the scoped art smoke. This does
not establish that the abandoned full-import attempt passed. Earlier fresh art
imports under resource contention also exited 137; copying known import metadata
and using serialized desktop import completed successfully. Final `import.log`,
`review_compile.log` and `capture.log` are successful runs; there was no renderer
or source exception in the final capture. A temporary local worker-pool override
used during initial recovery was removed; it is not delivered as a game setting.

No new full-game performance suite was run: resource window was reserved for the
other active work after scoped verification. The prior Saltwind report at the
same gameplay snapshot remains historical evidence only: 134/139 passed, five
failed (CPU 0.702 ms > 0.6 ms plus four aggregates), with 11 baseline flags.
This pack does not claim to fix or re-pass those tests. Hardware GPU, Godot 4.4.1,
Forward+, consoles and mobile are untested.

## Limits

Procedural low-poly art study, not a finished navigable gameplay map or sculpted
hero production pass. Tapered tube facets, hard LOD changes, coarse root proxies,
dark bark and sparse canopy are visible design/tradeoff choices. Broken boardwalk
and hollow structures deliberately preserve openings. Water has no swimming
or support collision. Heightfield caveat above matters for downstream integration.
No push or merge was performed. New assets CC0-1.0; new pipeline MIT.
