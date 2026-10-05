class_name ArenaEdgeDressing
extends RefCounted
## Layout-5 only, render-only edge gardens. Never used by standalone/replay layouts.
## Authored patch islands leave the combat basin and the complete +Z ride-in bare.
const CONFIG := {
 "valus": {"seed":8311,"inner":76.0,"outer":142.0,"kinds":["biome_seedgrass","biome_wildflowers","biome_heather"],"shrub":"shrub_heather","rock":"rock_scree_cluster","ruin":"ruin_fallen_drums","centers":[Vector2(-68,90),Vector2(38,91),Vector2(-87,46),Vector2(89,46),Vector2(-121,-30),Vector2(75,-56),Vector2(-46,-115),Vector2(33,-115)]},
 "hydrus": {"seed":8312,"inner":82.0,"outer":141.0,"kinds":["biome_rush","biome_fern","biome_seedgrass"],"shrub":"shrub_hazel","rock":"rock_split_moss","ruin":"ruin_moss_steps","centers":[Vector2(42,115),Vector2(-82,50),Vector2(88,42),Vector2(-109,-35),Vector2(90,-59),Vector2(-37,-111),Vector2(31,-113)]},
 "basaran": {"seed":8313,"inner":111.0,"outer":151.0,"kinds":["biome_dry_scrub","biome_gravel","biome_heather"],"shrub":"shrub_windward","rock":"rock_standing_shard","ruin":"ruin_carved_plinth","centers":[Vector2(-39,126),Vector2(41,130),Vector2(-88,94),Vector2(91,94),Vector2(-125,30),Vector2(126,-30),Vector2(-83,-99),Vector2(59,-121)]},
 "phalanx": {"seed":8314,"inner":137.0,"outer":164.0,"kinds":["biome_dry_scrub","biome_gravel","biome_seedgrass"],"shrub":"shrub_windward","rock":"rock_scree_cluster","ruin":"ruin_fallen_drums","centers":[Vector2(-43,150),Vector2(46,151),Vector2(-112,107),Vector2(117,99),Vector2(-153,10),Vector2(150,-33),Vector2(-108,-113),Vector2(68,-141)]}
}
# Larger authored silhouettes, grouped rather than evenly scattered; all remain
# outside the combat disk and 44m entrance corridor. Units are arena-local metres.
const LANDMARK_GROUPS := {
 "valus": {"anchors":[Vector2(104,.5),Vector2(99,2.65),Vector2(129,3.35),Vector2(114,4.22),Vector2(119,5.42)],"rock":"rock_layered_shelf","ruin":"ruin_broken_wall","scale":6.5,"height":6.0},
 "hydrus": {"anchors":[Vector2(106,.28),Vector2(121,2.63),Vector2(106,3.40),Vector2(106,4.05),Vector2(121,5.25)],"rock":"rock_split_moss","ruin":"ruin_moss_steps","scale":5.2,"height":5.0},
 "basaran": {"anchors":[Vector2(133,.35),Vector2(133,2.50),Vector2(133,3.22),Vector2(133,4.12),Vector2(133,5.24)],"rock":"rock_standing_shard","ruin":"ruin_carved_plinth","scale":6.0,"height":7.0},
 "phalanx": {"anchors":[Vector2(155,.35),Vector2(155,2.82),Vector2(155,3.30),Vector2(155,4.45),Vector2(155,5.0)],"rock":"rock_layered_shelf","ruin":"ruin_fallen_drums","scale":4.5,"height":8.0}
}
static var _bounds := {}
static var _material_requests := {}

static func mesh_for(kind: String, lod: int) -> Mesh:
 return EnvironmentGroundcover.ASSET.mesh_for(kind,lod) if kind.begins_with("biome_") else AuthoredNatureCatalog.mesh_for(kind,lod)
static func material_for(kind: String) -> Material:
 return EnvironmentGroundcover.MATERIAL if kind.begins_with("biome_") else AuthoredNatureCatalog.material_for(kind)
## Decode the shared nature atlas off the streaming callback; never block on get.
static func _material_ready(kind: String) -> bool:
 if kind.begins_with("biome_"): return true
 var path: String = AuthoredNatureCatalog.models()[kind].material
 if AuthoredNatureCatalog._materials.has(path): return true
 if not _material_requests.has(path):
  var error := ResourceLoader.load_threaded_request(path,"Material")
  if error != OK:
   push_error("Arena atlas request failed: " + path)
   return true
  _material_requests[path] = true
  return false
 var status := ResourceLoader.load_threaded_get_status(path)
 if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
 if status != ResourceLoader.THREAD_LOAD_LOADED:
  push_error("Arena atlas load failed: " + path)
  return true
 AuthoredNatureCatalog._materials[path] = ResourceLoader.load_threaded_get(path)
 return true

static func ranges(kind: String) -> Array:
 # Only this arena layer keeps distant silhouettes across the broad combat basin.
 # LOD0/1 distances stay unchanged; the extra reach uses the smallest mesh only.
 if kind.begins_with("rock_") or kind.begins_with("ruin_"): return [0.0,55.0,120.0,360.0]
 return EnvironmentGroundcover.quality_ranges(kind)
static func bounds_for(kind: String) -> AABB:
 if not _bounds.has(kind):
  var b := mesh_for(kind,0).get_aabb()
  for lod in [1,2]: b = b.merge(mesh_for(kind,lod).get_aabb())
  _bounds[kind] = b
 return _bounds[kind]

static func allowed(arena: String, bounds: AABB) -> bool:
 var cfg: Dictionary = CONFIG[arena]
 # Nearest point of the entire transformed union-of-LOD footprint to the basin.
 var near := Vector2(clampf(0,bounds.position.x,bounds.end.x),clampf(0,bounds.position.z,bounds.end.z))
 if near.length() < float(cfg.inner): return false
 for x in [bounds.position.x,bounds.end.x]:
  for z in [bounds.position.z,bounds.end.z]:
   if Vector2(x,z).length() > float(cfg.outer): return false
 # Full 44m horse/camera/sightline corridor, continued to the rim and beyond.
 if bounds.end.z > 0 and bounds.position.x < 22 and bounds.end.x > -22: return false
 return true

static func _state(arena: String) -> Dictionary:
 var rng := RandomNumberGenerator.new()
 rng.seed = int(CONFIG[arena].seed)
 return {"arena":arena,"rng":rng,"cursor":0,"records":[],"batches":[],"batch":0,"lod":0}

static func _sample_step(state: Dictionary, count := 32) -> bool:
 var cfg: Dictionary = CONFIG[state.arena]
 var rng: RandomNumberGenerator = state.rng
 # Each 21x21m island has a dense centre, scalloped perimeter and internal gaps.
 var end := mini(int(state.cursor)+count,cfg.centers.size()*121)
 for index in range(int(state.cursor),end):
  var patch := index / 121
  var slot := index % 121
  var q := Vector2((slot%11-5)*2.0,(slot/11-5)*2.0) + Vector2(rng.randf_range(-.8,.8),rng.randf_range(-.8,.8))
  var angle := patch * 1.13
  q = q.rotated(angle)
  var norm := Vector2(q.x/12.0,q.y/10.0).length()
  var accept := rng.randf()
  var choice := rng.randf()
  var p: Vector2 = cfg.centers[patch] + q
  var kind: String = cfg.kinds[0 if choice < .62 else (1 if choice < .84 else 2)]
  var size := rng.randf_range(1.55,2.15)
  var vertical := rng.randf_range(.86,1.35)
  if slot in [17,49,91]:
   kind = cfg.shrub; size = rng.randf_range(.6,.95); vertical = size
  elif slot in [29,78]:
   kind = cfg.rock; size = rng.randf_range(.28,.48); vertical = size*.7
  elif slot == 60 and patch%2 == 0:
   kind = cfg.ruin; size = .36; vertical = .28
  var yaw := rng.randf_range(-PI,PI)
  if norm > 1.0 or accept > lerpf(.96,.60,norm): continue
  var floor_y := -.04 if state.arena == "basaran" and maxf(absf(p.x),absf(p.y)) > 120.0 else 0.0
  # Valus campaign disc has its visible top at +1m (legacy physics untouched).
  if state.arena == "valus": floor_y = 1.0
  var xf := Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(size,vertical,size)),Vector3(p.x,floor_y-.025,p.y))
  if not allowed(state.arena,xf*bounds_for(kind)): continue
  state.records.append({"kind":kind,"transform":xf})
 state.cursor = end
 if end >= cfg.centers.size()*121:
  state.records.append_array(landmark_records(state.arena))
 return end >= cfg.centers.size()*121

static func landmark_records(arena: String) -> Array:
 var cfg: Dictionary = LANDMARK_GROUPS[arena]
 var result := []
 for anchor: Vector2 in cfg.anchors:
  var angle: float = anchor.y
  var radial := Vector2(cos(angle),sin(angle))
  var tangent := Vector2(-radial.y,radial.x)
  for slot in 4:
   # Main outcrop, offset shoulder, foot scree, and one ruined architectural accent.
   var kind: String = cfg.rock if slot < 2 else ("rock_scree_cluster" if slot == 2 else cfg.ruin)
   var p: Vector2 = radial * anchor.x + tangent * [-4.0,4.0,0.0,8.5][slot] + radial * [0.0,1.5,-5.0,-3.0][slot]
   var scale_xz: float = float(cfg.scale) * [1.0,.72,1.25,.8][slot]
   # Rear Phalanx outcrops stay below its imported V3 lower-sac silhouette
   # during a prolonged CARRY pass. Front/side groups can be taller safely.
   var height: float = minf(float(cfg.height),5.5) if arena == "phalanx" and p.y < -100.0 else float(cfg.height)
   var scale_y: float = height * [1.0,.7,.55,.9][slot]
   var floor_y := 1.0 if arena == "valus" else (-.04 if arena == "basaran" and maxf(absf(p.x),absf(p.y))>120.0 else 0.0)
   var xf := Transform3D(Basis(Vector3.UP,-angle+.35*slot).scaled(Vector3(scale_xz,scale_y,scale_xz)),Vector3(p.x,floor_y-.025,p.y))
   if allowed(arena,xf*bounds_for(kind)):
    result.append({"kind":kind,"transform":xf})
 return result

static func sample(arena: String) -> Array:
 if not CONFIG.has(arena): return []
 var state := _state(arena)
 while not _sample_step(state): pass
 return state.records

static func _batches(records: Array) -> Array:
 var cells := {}
 for record: Dictionary in records:
  var p: Vector3 = record.transform.origin
  var cell_size := 256.0 if record.kind.begins_with("rock_") or record.kind.begins_with("ruin_") else 64.0
  var key := "%s:%d:%d" % [record.kind,floori(p.x/cell_size),floori(p.z/cell_size)]
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
 if not CONFIG.has(arena): return
 var state := _state(arena)
 var parent_ref: WeakRef = weakref(parent)
 var step := func() -> bool:
  var target: Node3D = parent_ref.get_ref()
  return true if target == null else _build_step(target,state)
 if ArenaArt._planner:
  var cfg: Dictionary = CONFIG[arena]
  var kinds: Array = cfg.kinds.duplicate()
  kinds.append_array([cfg.shrub,cfg.rock,cfg.ruin,LANDMARK_GROUPS[arena].rock,LANDMARK_GROUPS[arena].ruin,"rock_scree_cluster"])
  for kind: String in kinds:
   for lod in 3:
    ArenaArt._planner.add(func() -> void: mesh_for(kind,lod))
   ArenaArt._planner.add(func() -> void: bounds_for(kind))
   ArenaArt._planner.jobs.append(func() -> bool: return _material_ready(kind))
  ArenaArt._planner.jobs.append(step)
 else:
  while not step.call(): pass

static func _build_step(parent: Node3D,state: Dictionary) -> bool:
 if not is_instance_valid(parent): return true
 if int(state.cursor) < CONFIG[state.arena].centers.size()*121:
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
 node.name = "ArenaEdge_%s_%d_LOD%d" % [kind,state.batch,state.lod]
 node.position = prepared.center
 node.multimesh = mm
 node.material_override = material_for(kind)
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.lod_bias = 100
 node.set_meta(&"groundcover_kind",kind)
 node.set_meta(&"groundcover_lod",state.lod)
 node.set_meta(&"arena_edge_kind",state.arena)
 node.set_meta(&"groundcover_ranges",ranges(kind))
 node.set_meta(&"authored_landmark",kind.begins_with("rock_") or kind.begins_with("ruin_"))
 EnvironmentGroundcover.apply_quality(node,EnvironmentGroundcover._profile_for(parent))
 parent.add_child(node)
 state.lod += 1
 if state.lod == 3:
  state.lod = 0
  state.batch += 1
 return int(state.batch) >= state.batches.size()
