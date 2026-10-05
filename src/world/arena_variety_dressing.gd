class_name ArenaVarietyDressing
extends RefCounted
## Authored 12-model Nature Variety integration. Layout 5 campaign only.
## Decorative outside complete combat disks/entry lanes: no collision, no RNG per frame.
const CONFIG := {
 "quadratus": {"inner":96.0,"outer":167.0,"floor":1.0,"seed":27101,
  "centers":[Vector2(-54.727,105.669),Vector2(49.878,121.133),Vector2(-113.816,22.405),Vector2(112.057,-29.987),Vector2(-54.077,-112.697),Vector2(36.569,-125.792)],
  "kinds":["rock_overhang","rock_dorsal_ridge","ruin_fallen_fluted_column","ruin_wall_corner","plant_spear_rosette","plant_creeping_juniper"]},
 "phaedra": {"inner":88.0,"outer":164.0,"floor":1.0,"seed":27102,
  "centers":[Vector2(-46.687,107.281),Vector2(48.362,109.823),Vector2(-112.225,20.04),Vector2(123.297,-25.957),Vector2(-54.624,-110.206),Vector2(68.391,-98.604)],
  "kinds":["rock_leaning_strata","rock_river_margin","ruin_voussoir_arch","ruin_dry_fountain","plant_flower_cushion","plant_creeping_juniper"]},
 "avion": {"inner":119.0,"outer":167.0,"floor":0.0,"seed":27103,
  "centers":[Vector2(-39.788,151.875),Vector2(47.822,133.705),Vector2(-135.938,4.113),Vector2(119.82,50.431),Vector2(-52.303,-122.284),Vector2(89.595,-98.294)],
  "kinds":["rock_river_margin","rock_leaning_strata","ruin_wall_corner","ruin_fallen_fluted_column","plant_seed_reeds","plant_flower_cushion"]},
 # These compositions sit beyond the complete authored encounter and climb
 # envelopes. Argus is stationary by _adjust_movement; its 175m observation
 # radius is not its moving-body footprint. The 86m disk also protects both
 # states and the entire sweep of its hinged gallery, plate, bridge and jump.
 "kuromori": {"inner":90.0,"outer":165.0,"floor":-.04,"seed":28101,"composition":"temple","skyline_scale":2.15,
  "centers":[Vector2(-63,112),Vector2(68,115),Vector2(-127,2),Vector2(129,-10),Vector2(-62,-112),Vector2(64,-115)],
  "kinds":["rock_overhang","rock_leaning_strata","ruin_voussoir_arch","ruin_wall_corner","ruin_fallen_fluted_column","plant_creeping_juniper","plant_spear_rosette"]},
 "pelagia": {"inner":84.0,"outer":165.0,"floor":0.0,"seed":28102,"composition":"shore",
  "centers":[Vector2(-63,113),Vector2(68,118),Vector2(-126,8),Vector2(128,-12),Vector2(-68,-109),Vector2(65,-112)],
  "kinds":["rock_river_margin","rock_leaning_strata","ruin_voussoir_arch","ruin_dry_fountain","ruin_fallen_fluted_column","plant_seed_reeds","plant_flower_cushion"]},
 "argus": {"inner":86.0,"outer":165.0,"floor":0.0,"seed":28103,"composition":"gallery",
  "centers":[Vector2(-63,111),Vector2(64,114),Vector2(-127,1),Vector2(130,-10),Vector2(-61,-114),Vector2(69,-112)],
  "kinds":["rock_dorsal_ridge","rock_overhang","ruin_wall_corner","ruin_fallen_fluted_column","ruin_voussoir_arch","plant_creeping_juniper","plant_spear_rosette"]}
}
static var _bounds := {}
static var _obstacles := {}
const CLEARANCE_PATH := "res://data/environment/arena_variety_clearance.json"

static func _clearance_ready() -> bool:
 if not _obstacles.is_empty(): return true
 if not FileAccess.file_exists(CLEARANCE_PATH):
  push_error("Missing authored arena clearance data; decorative layer skipped")
  return false
 var parsed = JSON.parse_string(FileAccess.get_file_as_string(CLEARANCE_PATH))
 if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("arenas") is Dictionary:
  push_error("Invalid authored arena clearance data; decorative layer skipped")
  return false
 var prepared := {}
 for arena: String in CONFIG:
  var entries = parsed.arenas.get(arena)
  if not entries is Array or entries.is_empty(): return false
  var footprints := []
  for entry in entries:
   if not entry is Dictionary: return false
   var p = entry.get("position")
   var size = entry.get("size")
   if not p is Array or not size is Array or p.size()!=3 or size.size()!=3: return false
   for axis in 3:
    if not (p[axis] is float or p[axis] is int) or not (size[axis] is float or size[axis] is int): return false
    if not is_finite(float(p[axis])) or not is_finite(float(size[axis])) or float(size[axis])<0: return false
   if float(size[0])<=0 or float(size[2])<=0: return false
   footprints.append(Rect2(Vector2(p[0],p[2]),Vector2(size[0],size[2])).grow(.25))
  prepared[arena] = footprints
 # Commit atomically: a malformed later arena cannot leave a usable partial cache.
 _obstacles = prepared
 return true

static func mesh_for(kind: String, lod: int) -> Mesh:
 return NatureVarietyCatalog.mesh_for(kind,lod)
static func material_for(kind: String) -> Material:
 return NatureVarietyCatalog.material_for(kind)
static func ranges(kind: String) -> Array:
 return [0.0,55.0,120.0,360.0] if not kind.begins_with("plant_") else [0.0,42.0,95.0,220.0]
static func bounds_for(kind: String) -> AABB:
 if not _bounds.has(kind):
  var b := mesh_for(kind,0).get_aabb()
  for lod in [1,2]: b = b.merge(mesh_for(kind,lod).get_aabb())
  _bounds[kind] = b
 return _bounds[kind]
static func allowed(arena: String, bounds: AABB) -> bool:
 var cfg: Dictionary = CONFIG[arena]
 var near := Vector2(clampf(0,bounds.position.x,bounds.end.x),clampf(0,bounds.position.z,bounds.end.z))
 if near.length() < float(cfg.inner): return false
 for x in [bounds.position.x,bounds.end.x]:
  for z in [bounds.position.z,bounds.end.z]:
   if Vector2(x,z).length() > float(cfg.outer): return false
 # Forty-eight metre continuous entrance and horse/camera sight corridor.
 if bounds.end.z > 0 and bounds.position.x < 24 and bounds.end.x > -24: return false
 # Offline-captured actual collider footprints protect existing trees, cliff bases,
 # pillars and cover. Tests independently re-read the production arena geometry.
 if not _clearance_ready() or not _obstacles.has(arena): return false
 var footprint := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
 for obstacle: Rect2 in _obstacles[arena]:
  if footprint.intersects(obstacle,true): return false
 return true
static func _record(arena: String, kind: String, at: Vector2, yaw: float, size: Vector3) -> Dictionary:
 var b := bounds_for(kind)
 var xf := Transform3D(Basis(Vector3.UP,yaw).scaled(size),Vector3(at.x,CONFIG[arena].floor-.015-b.position.y*size.y,at.y))
 return {"kind":kind,"transform":xf} if allowed(arena,xf*b) else {}
static func _sample_step(state: Dictionary) -> bool:
 var cfg: Dictionary = CONFIG[state.arena]
 if cfg.has("composition"): return _sample_composition_step(state)
 var patch: int = state.cursor
 var anchor: Vector2 = cfg.centers[patch]
 var radial := anchor.normalized()
 var tangent := Vector2(-radial.y,radial.x)
 var yaw := -atan2(radial.y,radial.x)
 # Unequal masses form a broken crest with a low apron, not a ring of clones.
 for slot in 4:
  var kind: String = cfg.kinds[slot]
  var p: Vector2 = anchor + tangent * [-5.5,5.0,-8.0,7.0][slot] + radial * [2.0,3.0,-6.0,-5.0][slot]
  var scale_xz: float = [2.6,2.2,1.65,1.7][slot] * (1.0+float(patch%3)*.08)
  var scale_y: float = [3.1,2.4,1.85,1.5][slot]
  var record := _record(state.arena,kind,p,yaw+.24*slot,Vector3(scale_xz,scale_y,scale_xz))
  if not record.is_empty(): state.records.append(record)
 var rng := RandomNumberGenerator.new()
 rng.seed = int(cfg.seed)+patch*103
 # Ground-hugging fan around each rock/ruin island, discrete existing assets.
 for slot in 32:
  var a := rng.randf_range(-PI,PI)
  var r := rng.randf_range(5.0,13.0)
  var p: Vector2 = anchor + Vector2(cos(a)*r,sin(a)*r*.65) - radial*3.0
  var kind: String = cfg.kinds[4+slot%2]
  var scale_xz := rng.randf_range(1.1,1.9)
  var scale_y := rng.randf_range(.8,1.25)
  var record := _record(state.arena,kind,p,rng.randf_range(-PI,PI),Vector3(scale_xz,scale_y,scale_xz))
  if not record.is_empty(): state.records.append(record)
 state.cursor += 1
 return int(state.cursor) >= cfg.centers.size()
## Seven substantial stone masses form each authored island: a tall rear
## silhouette, two connected ruin pieces and a descending low foreground apron.
## Plants follow the same island, not a uniform scatter or a replacement floor.
## This path is deliberately separate so prior three-arena poses stay byte exact.
static func _sample_composition_step(state: Dictionary) -> bool:
 var cfg: Dictionary = CONFIG[state.arena]
 var patch: int = state.cursor
 var anchor: Vector2 = cfg.centers[patch]
 var radial := anchor.normalized()
 var tangent := Vector2(-radial.y,radial.x)
 var yaw := -atan2(radial.y,radial.x)
 var relief: float = 1.0 + .07 * float(patch % 3)
 var slots := [
  [0,Vector2(-6.5,5.5),Vector3(3.7,4.2,3.2),-.22],
  [1,Vector2(5.5,7.0),Vector3(3.6,4.5,3.3),.38],
  [2,Vector2(-7.5,-3.5),Vector3(2.6,2.9,2.4),.13],
  [3,Vector2(4.0,-4.0),Vector3(2.7,2.4,2.5),-.18],
  [4,Vector2(12.0,1.0),Vector3(2.7,2.4,2.5),.42],
  [0,Vector2(-15.0,-1.0),Vector3(2.5,2.0,2.1),.58],
  [1,Vector2(0.0,-11.5),Vector3(2.9,1.8,2.4),-.48]
 ]
 for slot: Array in slots:
  var offset: Vector2 = slot[1]
  var at := anchor + tangent * offset.x + radial * offset.y
  var scale: Vector3 = slot[2] * Vector3(relief,1.0,relief)
  if int(slot[0]) == 2: scale.y *= float(cfg.get("skyline_scale",1.0))
  var record := _record(state.arena,cfg.kinds[slot[0]],at,yaw+float(slot[3]),scale)
  if not record.is_empty():
   record["feature_island"] = patch
   state.records.append(record)
 var rng := RandomNumberGenerator.new()
 rng.seed = int(cfg.seed)+patch*103
 # Two irregular, elongated vegetation aprons read with the stone feature from
 # the encounter and entrance. Wetland reeds stay on Pelagia's flat dry bank.
 for slot in 40:
  var along := rng.randf_range(-19.0,19.0)
  var depth := rng.randf_range(-15.5,9.0)
  var at := anchor + tangent * along + radial * depth
  var scale_xz := rng.randf_range(1.35,2.15)
  var scale_y := rng.randf_range(.95,1.5)
  var record := _record(state.arena,cfg.kinds[5+slot%2],at,rng.randf_range(-PI,PI),Vector3(scale_xz,scale_y,scale_xz))
  if not record.is_empty():
   record["feature_island"] = patch
   state.records.append(record)
 state.cursor += 1
 return int(state.cursor) >= cfg.centers.size()

static func sample(arena: String) -> Array:
 if not CONFIG.has(arena) or not _clearance_ready(): return []
 var state := {"arena":arena,"records":[],"cursor":0}
 while not _sample_step(state): pass
 return state.records

static func _batches(records: Array) -> Array:
 var cells := {}
 for record: Dictionary in records:
  var p: Vector3 = record.transform.origin
  var cell_size := 256.0 if record.kind.begins_with("rock_") or record.kind.begins_with("ruin_") else 64.0
  var key := "%s:%d:%d" % [record.kind,floori(p.x/cell_size),floori(p.z/cell_size)]
  # New authored islands have local, bounded LOD origins: seven kinds x six
  # islands x three LODs = 126 draw nodes, independent of cell boundaries.
  if record.has("feature_island"): key = "%s:island:%d" % [record.kind,int(record.feature_island)]
  if not cells.has(key): cells[key] = {"kind":record.kind,"transforms":[]}
  cells[key].transforms.append(record.transform)
 # A stable shuffled prefix keeps every quality profile spread across each island.
 var rng := RandomNumberGenerator.new()
 rng.seed = 912731
 for batch: Dictionary in cells.values():
  var xfs: Array = batch.transforms
  for i in range(xfs.size()-1,0,-1):
   var j := rng.randi_range(0,i)
   var swap = xfs[i]
   xfs[i] = xfs[j]
   xfs[j] = swap
 return cells.values()
static func batch_records(arena: String) -> Array:
 return _batches(sample(arena))

static func append(parent: Node3D, arena: String) -> void:
 if not CONFIG.has(arena) or not _clearance_ready(): return
 var state := {"arena":arena,"records":[],"batches":[],"batch":0,"lod":0,"cursor":0}
 var parent_ref: WeakRef = weakref(parent)
 var step := func() -> bool:
  var target: Node3D = parent_ref.get_ref()
  return true if target == null else _build_step(target,state)
 if ArenaArt._planner:
  for kind: String in CONFIG[arena].kinds:
   for lod in 3:
    ArenaArt._planner.add(func() -> void: mesh_for(kind,lod))
   ArenaArt._planner.add(func() -> void: bounds_for(kind))
  ArenaArt._planner.jobs.append(step)
 else:
  while not step.call(): pass

static func _build_step(parent: Node3D,state: Dictionary) -> bool:
 if not is_instance_valid(parent): return true
 if int(state.cursor) < CONFIG[state.arena].centers.size():
  if _sample_step(state): state.batches = _batches(state.records)
  return false
 if int(state.batch) >= state.batches.size(): return true
 var batch: Dictionary = state.batches[state.batch]
 var kind: String = batch.kind
 var transforms: Array = batch.transforms
 var prepared: Dictionary
 if int(state.lod) == 0:
  var bounds := AABB()
  for i in transforms.size():
   var b: AABB = transforms[i]*bounds_for(kind)
   bounds = b if i==0 else bounds.merge(b)
  state.prepared = {"center":bounds.get_center(),"bounds":bounds}
 prepared = state.prepared
 var mm := MultiMesh.new()
 mm.transform_format = MultiMesh.TRANSFORM_3D
 mm.mesh = mesh_for(kind,state.lod)
 mm.instance_count = transforms.size()
 var local_bounds: AABB = prepared.bounds
 local_bounds.position -= prepared.center
 mm.custom_aabb = local_bounds
 for i in transforms.size():
  var xf: Transform3D = transforms[i]
  xf.origin -= prepared.center
  mm.set_instance_transform(i,xf)
 var node := MultiMeshInstance3D.new()
 node.name = "ArenaVariety_%s_%d_LOD%d" % [kind,state.batch,state.lod]
 node.position = prepared.center
 node.multimesh = mm
 node.material_override = material_for(kind)
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.lod_bias = 100
 node.set_meta(&"groundcover_kind",kind)
 node.set_meta(&"groundcover_lod",state.lod)
 node.set_meta(&"arena_variety_kind",state.arena)
 node.set_meta(&"groundcover_ranges",ranges(kind))
 node.set_meta(&"authored_landmark",kind.begins_with("rock_") or kind.begins_with("ruin_"))
 EnvironmentGroundcover.apply_quality(node,EnvironmentGroundcover._profile_for(parent))
 parent.add_child(node)
 state.lod += 1
 if state.lod == 3:
  state.lod = 0
  state.batch += 1
 return int(state.batch) >= state.batches.size()
