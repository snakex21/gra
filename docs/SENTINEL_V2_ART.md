# Sentinel v2 — original rigid visual kit

An approximately 17 m humanoid using the existing 17 segment origins. This is an art-owned prototype, not a new gameplay implementation or a finished hero sculpt.

## Deliverables

- Editable `art/source/sentinel_v2.blend`, with joint-reference empties, hidden pre-triangulation source meshes, and LOD0/1/2 meshes
- `models/sentinel_v2/`: 17 original rigid parts × three artist LODs, plus two optional extended-foot variants × three LODs
- `textures/sentinel_v2/atlas_2k.png`: shared 2048 × 2048 original procedural atlas
- `tools/art/generate_sentinel_v2.py`: deterministic source using repository-owned primitive functions
- `art/scripts/sentinel_v2_adapter.gd`: one-way adapter; attaches to existing `Seg_*` nodes and hides/restores only original render meshes
- `art/tests/ancient_valley_sentinel.tscn`: separate art review scene, frozen existing humanoid in Ancient Valley
- `art/screenshots/sentinel_v2/`: four actual Godot viewport captures, including back and joint detail

## Topology and readability

Capsule limb/neck surfaces now have ten longitudinal rings with 20 vertices around each ring, versus six rings/16 sides in the first kit. Those are editable mesh loops; the source is not a skinned replacement rig. Core torso/head/hand/foot volumes use tapered rounded ring profiles. Two broad curved ceremonial bands and an asymmetric faceted mask replace the first pass’s box-like plates. Irregular short tuft islands break up the fur surface. Each GLB is rigidly attached at its existing segment origin, preserving the animation and physics owner's interfaces. LOD reductions are 1.0 / 0.48 / 0.18 target ratios, with actual triangle counts in `art/reports/v2/sentinel_budgets.json`.

Brown ridged fur is the visual signal for existing fur/grip regions. Pale worn stone and smooth dark armor signal the existing non-grip regions. Geometry does not assign grip permissions. The mask, turquoise seam and rib cadence are original abstract motifs. There are no imported/extracted commercial-game assets.

## Verification

`python tools/art/validate_sentinel_v2.py` validates all 57 GLBs, monotonic LODs, atlas dimensions and outer envelope differences against the approved v1 visuals (<15 cm bound tolerance). That tolerance is an art envelope check, not proof of pixel-perfect collision matching in every pose.

`godot --headless --path . res://art/tests/test_sentinel_v2.tscn` passes 430 assertions on the actual uploaded `assets` branch humanoid: 17 attachments, stable skeleton identity, unchanged collision shape resources/transforms/disabled flags, local identity transforms, animation-following over 30 physics frames, and restoration on adapter removal.

Actual viewport workload is in `art/reports/v2/sentinel_render_costs.json`. The entire environment plus character was rendered with the software llvmpipe adapter. This is no claim about target-hardware FPS.

## Integration and remaining polish

Attach the adapter with its `target_path` pointing to an existing colossus whose 17 segment names match. Missing names fail closed; no partial replacement. Removing it restores the greybox render visibility. The adapter reads existing PARTS geometry constants and selects the 3.6 m foot variant at z=-0.85 when that contract is present; otherwise it keeps the 2.8 m uploaded-assets foot. It does not branch on commit IDs. The gameplay owner should review grip reach/readability under real climbing and movement before adopting it. No player/climbing/locomotion/IK/Agro/physics/camera code was edited.

A final hero sculpt, hand-authored fur breakup, and pose-specific seam/clearance polishing remain beyond this coherent procedural v2 prototype. The rigid architecture intentionally follows the existing contract; it does not claim a new weighted deformation rig.
