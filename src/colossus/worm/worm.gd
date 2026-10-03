class_name Worm
extends Colossus
## Defensive earth guardian. Two timed landings on a resonant slab summon an
## emergence; its mineral collar must break before the exposed climb window.
enum Encounter { DORMANT, COMBAT, DEFEATED }
enum Cycle { LISTEN, TELEGRAPH, RISE, ARMORED, EXPOSED, WITHDRAW, LOWER }
signal encounter_changed(state: Encounter)
const BURIED_Y := -14.0
const EMERGENCE_OFFSET := Vector3(0, 0, -8)
var encounter := Encounter.DORMANT
var cycle := Cycle.LISTEN
var cycle_time := 0.0
var brain_seed := 113
var effects_enabled := true
var weak_point: WeakPoint
var weak_points: Array[WeakPoint] = []
var plates: Array[WormMineralPlate] = []
var platform_centers: Array[Vector3] = []
var arena_frame := Transform3D.IDENTITY
var start_transform := Transform3D.IDENTITY
var station := -1
var completed := [false, false, false]
var stats := {"pulses": 0, "rhythms": 0, "emergences": 0, "armor_hits": 0, "sword_armor_hits": 0, "arrow_armor_hits": 0, "climb_entries": 0, "weak_point_hits": 0, "bursts": 0, "hits_on_player": 0}
var _seg_by_bone := {}
var _bone := {}
var _fur: Array[ClimbPatch] = []
var _last_pulse := [-100.0, -100.0, -100.0]
var _connected_players := {}
var _seen_riders := {}
var _warning: MeshInstance3D
var _emergence := Vector3.ZERO
var _root_y := BURIED_Y
var _last_station := -1

func _ready() -> void:
	super()
	body_height = 12.0
	start_transform = global_transform
	add_to_group(&"danger_sources")
	for i in 3:
		var w := WeakPoint.create(_seg_by_bone[&"crown"], Vector3((i - 1) * 1.15, 3.32, 0), 40.0)
		w.radius = 0.85
		w.min_power = 0.55
		w.set_protected(true)
		w.struck.connect(func(_d: float, _h: float) -> void: stats.weak_point_hits += 1)
		w.destroyed.connect(_sigil_destroyed.bind(i))
		weak_points.append(w)
	weak_point = weak_points[0]
	for side in [-1.0, 1.0]:
		var part := _box(&"base", Vector3(side * 1.1, 2.5, 2.9), Vector3(2.2, 4.8, 0.5), false)
		var a := WormMineralPlate.new()
		a.segment = _seg_by_bone[&"base"]
		a.shape = part.shape
		a.meshes.append(part.mesh)
		a.local_point = Vector3(side * 1.1, 1.1, 3.15)
		a.position = a.local_point
		a.radius = 1.1
		a.hits_to_break = 3
		a.name = "MineralCollar"
		a.segment.add_child(a)
		a.connect_arrow()
		a.cracked.connect(func(_n: int) -> void: stats.armor_hits += 1)
		a.mineral_hit.connect(func(source: StringName) -> void:
			if source == &"arrow": stats.arrow_armor_hits += 1
			else: stats.sword_armor_hits += 1)
		plates.append(a)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for b in [[&"base", Vector3.ZERO], [&"fore", Vector3(0, 4, 0)], [&"crown", Vector3(0, 8, 0)]]:
		var idx := skeleton.add_bone(b[0])
		_bone[b[0]] = idx
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[1]))
		var seg := BodySegment.new()
		seg.name = "Seg_" + b[0]
		seg.colossus = self
		seg.bone_name = b[0]
		seg.bone_idx = idx
		add_child(seg)
		segments.append(seg)
		_seg_by_bone[b[0]] = seg
	skeleton.reset_bone_poses()
	_box(&"base", Vector3(0, 2, 0), Vector3(5, 4, 5), false)
	_box(&"base", Vector3(0, 2, 2.6), Vector3(2.8, 4.2, 0.4), true)
	_box(&"fore", Vector3(0, 2, 0), Vector3(4.4, 4, 4.4), false)
	_box(&"fore", Vector3(0, 2, 2.5), Vector3(2.8, 4.2, 0.5), true)
	_box(&"crown", Vector3(0, 1.5, 0), Vector3(3.8, 3, 3.8), false)
	_box(&"crown", Vector3(0, 1.5, 2.35), Vector3(2.8, 3.2, 0.5), true)
	_box(&"crown", Vector3(0, 3.1, 0), Vector3(3.8, 0.4, 5.0), true)
	_warning = MeshInstance3D.new()
	_warning.name = "EmergenceWarning"
	_warning.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 4.2
	ring.outer_radius = 4.5
	_warning.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.36, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.18, 0.02)
	mat.emission_energy_multiplier = 2.0
	_warning.material_override = mat
	_warning.visible = false
	add_child(_warning)

func _box(bone: StringName, at: Vector3, size: Vector3, fur: bool) -> Dictionary:
	var seg: BodySegment = _seg_by_bone[bone]
	var col := ClimbPatch.new() if fur else CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = at
	seg.add_child(col)
	if fur: _fur.append(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.3, 0.25) if fur else Color(0.43, 0.34, 0.26)
	mesh.material_override = mat
	mesh.set_meta(&"kind", 0 if fur else 1)
	mesh.set_meta(&"part_size", size)
	seg.add_child(mesh)
	return {"shape": col, "mesh": mesh}

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"worm_resonance")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	if encounter == Encounter.DEFEATED: return
	cycle_time += delta
	var players := _players()
	for p in players:
		if not _connected_players.has(p.get_instance_id()):
			p.landed.connect(_landing.bind(p))
			_connected_players[p.get_instance_id()] = true
		if encounter == Encounter.DORMANT and _flat(p.global_position - arena_frame.origin).length() < 110:
			encounter = Encounter.COMBAT
			encounter_changed.emit(encounter)
	var riders := false
	for p in players:
		if owns_body(p.get_support_body()) and p.global_position.distance_to(global_position) < 20 and (p.is_climbing() or p.state == PlayerCharacter.State.GROUND):
			riders = true
			if not _seen_riders.has(p.get_instance_id()):
				_seen_riders[p.get_instance_id()] = true
				stats.climb_entries += 1
	match cycle:
		Cycle.LISTEN: _root_y = BURIED_Y
		Cycle.TELEGRAPH:
			if cycle_time >= 2.8:
				_burst(players)
				stats.emergences += 1
				_enter(Cycle.RISE)
		Cycle.RISE:
			_root_y = lerpf(BURIED_Y, 0, _smooth(clampf(cycle_time / 3.0, 0, 1)))
			if cycle_time >= 3.0: _enter(Cycle.ARMORED)
		Cycle.ARMORED:
			if plates[0].is_broken and plates[1].is_broken:
				_enter(Cycle.EXPOSED)
			elif cycle_time > 26.0: _enter(Cycle.WITHDRAW)
		Cycle.EXPOSED:
			if not riders and cycle_time > 45: _enter(Cycle.WITHDRAW)
		Cycle.WITHDRAW:
			# The three-second warning also gives a climber time to descend. Never
			# pull an attached player under the terrain or cut off their route.
			if cycle_time >= 3.0 and not riders: _enter(Cycle.LOWER)
		Cycle.LOWER:
			_root_y = lerpf(0, BURIED_Y, _smooth(clampf(cycle_time / 3.5, 0, 1)))
			if cycle_time >= 3.5: _enter(Cycle.LISTEN)
	if cycle != Cycle.LISTEN:
		global_transform = Transform3D(arena_frame.basis, _emergence + arena_frame.basis.y * _root_y)
	for a in plates:
		a.enabled = cycle == Cycle.ARMORED
		a.arrow_target.enabled = a.enabled and not a.is_broken
	var climb_open := cycle in [Cycle.EXPOSED, Cycle.WITHDRAW]
	for fur in _fur:
		if fur.disabled == climb_open: fur.set_deferred(&"disabled", not climb_open)
	for i in 3:
		weak_points[i].set_protected(cycle != Cycle.EXPOSED or i != station)
	_warning.visible = cycle in [Cycle.TELEGRAPH, Cycle.WITHDRAW]
	if _warning.visible:
		_warning.global_position = _emergence + arena_frame.basis * Vector3(0, 0.09, 3.5)

func _landing(speed: float, _tier: int, _damage: float, p: PlayerCharacter) -> void:
	if cycle != Cycle.LISTEN or speed < 4 or p.dead: return
	for i in platform_centers.size():
		if completed[i]: continue
		var at: Vector3 = arena_frame * platform_centers[i]
		if _flat(p.global_position - at).length() > 3.5: continue
		stats.pulses += 1
		var elapsed: float = _time - _last_pulse[i]
		_last_pulse[i] = _time
		if elapsed < 1.0 or elapsed > 1.8: return
		station = i
		stats.rhythms += 1
		_emergence = arena_frame * (platform_centers[i] + EMERGENCE_OFFSET)
		if station != _last_station or completed[_last_station]:
			for a in plates: a.reset()
		_last_station = station
		_enter(Cycle.TELEGRAPH)
		return

func _burst(players: Array[PlayerCharacter]) -> void:
	stats.bursts += 1
	var at := _emergence + arena_frame.basis * Vector3(0, 0, 3.5)
	for p in players:
		var safe_center: Vector3 = arena_frame * platform_centers[station]
		if _flat(p.global_position - safe_center).length() < 2.5: continue
		if _flat(p.global_position - at).length() < 4.4 and p.global_position.y < at.y + 3.0:
			if p.apply_hit(28, _flat(p.global_position - at).normalized() * 6 + Vector3.UP * 3, 0.7, &"worm_emergence"):
				stats.hits_on_player += 1

func _sigil_destroyed(i: int) -> void:
	completed[i] = true
	if not completed.has(false):
		encounter = Encounter.DEFEATED
		_warning.visible = false
		encounter_changed.emit(encounter)
		defeated.emit()
	else: _enter(Cycle.WITHDRAW)

func _pose_bones(_delta: float) -> void:
	# Small continuous surveying motion, no abrupt shake during an exposed window.
	var yaw := 0.025 * sin(_time * 0.7) if cycle == Cycle.EXPOSED else 0.0
	skeleton.set_bone_pose_rotation(_bone[&"crown"], Quaternion.from_euler(Vector3(0, yaw, 0)))

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf: start_transform = xf
	global_transform = start_transform
	encounter = Encounter.DORMANT
	cycle = Cycle.LISTEN
	cycle_time = 0
	_root_y = BURIED_Y
	station = -1
	_last_station = -1
	completed = [false, false, false]
	_last_pulse = [-100.0, -100.0, -100.0]
	_seen_riders.clear()
	_warning.visible = false
	for a in plates:
		a.reset()
		a.enabled = false
		a.arrow_target.enabled = false
	for w in weak_points:
		w.reset()
		w.set_protected(true)
	for fur in _fur: fur.set_deferred(&"disabled", true)
	stats = {"pulses": 0, "rhythms": 0, "emergences": 0, "armor_hits": 0, "sword_armor_hits": 0, "arrow_armor_hits": 0, "climb_entries": 0, "weak_point_hits": 0, "bursts": 0, "hits_on_player": 0}
	_pose_bones(0)
	_sync_segments()
	_sync_segments()
	for seg in segments: seg.reset_physics_interpolation()
func _enter(next: Cycle) -> void:
	cycle = next
	cycle_time = 0
	if next == Cycle.EXPOSED: _seen_riders.clear()
func _players() -> Array[PlayerCharacter]:
	var out: Array[PlayerCharacter] = []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p is PlayerCharacter and not p.dead: out.append(p)
	return out
func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED
func encounter_name() -> String:
	return Encounter.keys()[encounter]
func beam_weak_point() -> WeakPoint:
	return weak_points[station] if station >= 0 else weak_points[0]
func get_focus_point() -> Vector3:
	return global_position + Vector3.UP * 9 if cycle != Cycle.LISTEN else arena_frame.origin + Vector3.UP * 2
func get_danger_zones() -> Array:
	return [[_emergence + arena_frame.basis * Vector3(0, 0, 3.5), 4.4, maxf(0, 2.8 - cycle_time)]] if cycle == Cycle.TELEGRAPH else []
func debug_text() -> String:
	return "WORM %s | %s | slab %d | sigils %s | mineral %d/%d" % [encounter_name(), Cycle.keys()[cycle], station, completed, plates[0].hits, plates[1].hits]
static func _smooth(u: float) -> float:
	return u * u * (3 - 2 * u)
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
