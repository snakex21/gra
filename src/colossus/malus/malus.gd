class_name Malus
extends Colossus
## Fixed siege guardian. The service seam on the back reaches a pressure mark;
## that summons a hand. A bow shot to its wrist raises the hand to the upper route.
enum Encounter { DORMANT, COMBAT, DEFEATED }
enum Hand { SEALED, LOWERING, BOARD, RAISING, DOCKED }
signal encounter_changed(state: Encounter)
const HAND_HIGH := Vector3(9, 18, 0)
const HAND_LOW := Vector3(0, 7.3, 8)
const HAND_DOCK := Vector3(0, 18.8, 5.2)
var encounter := Encounter.DORMANT
var hand_phase := Hand.SEALED
var hand_time := 0.0
var brain_seed := 107
var effects_enabled := true
var weak_point: WeakPoint
var weak_points: Array[WeakPoint] = []
var pressure_mark: WeakPoint
var wrist: ArrowTarget
var stats := {"volleys": 0, "cover_blocks": 0, "hits_on_player": 0, "pressure_hits": 0, "wrist_hits": 0, "hand_riders": 0, "weak_point_hits": 0}
var start_transform := Transform3D.IDENTITY
var _bone := {}
var _seg_by_bone := {}
var _hand_position := HAND_HIGH
var _shot_clock := 0.0
var _shot_active := false
var _shot_target := Vector3.ZERO
var _warning: MeshInstance3D
var _upper_patches: Array[ClimbPatch] = []
var _hand_rider_seen := {}

func _ready() -> void:
	super()
	start_transform = global_transform
	add_to_group(&"danger_sources")
	pressure_mark = WeakPoint.create(_seg_by_bone[&"base"], Vector3(0, 7.25, 6.45), 100000.0)
	pressure_mark.name = "PressureMark"
	pressure_mark.rotation.x = PI * 0.5
	pressure_mark.radius = 1.2
	pressure_mark.struck.connect(func(_d: float, _h: float) -> void:
		if hand_phase == Hand.SEALED:
			stats.pressure_hits += 1
			hand_phase = Hand.LOWERING
			hand_time = 0.0
			pressure_mark.set_protected(true))
	wrist = ArrowTarget.create(_seg_by_bone[&"hand"], Vector3(1.5, 2.7, 0), Vector3.UP, 0.85, &"malus_wrist")
	wrist.max_incidence_deg = 160.0
	wrist.enabled = false
	var wrist_light := MeshInstance3D.new()
	var wrist_orb := SphereMesh.new()
	wrist_orb.radius = 0.38
	wrist_orb.height = 0.76
	wrist_light.mesh = wrist_orb
	wrist_light.position = wrist.local_point
	var wrist_mat := StandardMaterial3D.new()
	wrist_mat.albedo_color = Color(0.95, 0.75, 0.24)
	wrist_mat.emission_enabled = true
	wrist_mat.emission = Color(0.95, 0.55, 0.12)
	wrist_mat.emission_energy_multiplier = 1.5
	wrist_light.material_override = wrist_mat
	_seg_by_bone[&"hand"].add_child(wrist_light)
	wrist.hit.connect(func(_info: Dictionary) -> void:
		if hand_phase == Hand.BOARD:
			stats.wrist_hits += 1
			hand_phase = Hand.RAISING
			hand_time = 0.0)
	weak_point = WeakPoint.create(_seg_by_bone[&"head"], Vector3(0, 6.22, 0), 100.0)
	weak_points.append(weak_point)
	weak_point.set_protected(true)
	weak_point.struck.connect(func(_d: float, _h: float) -> void: stats.weak_point_hits += 1)
	weak_point.destroyed.connect(func() -> void:
		encounter = Encounter.DEFEATED
		encounter_changed.emit(encounter)
		defeated.emit())

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in [[&"base", Vector3.ZERO], [&"torso", Vector3.ZERO], [&"hand", HAND_HIGH], [&"head", Vector3(0, 25, 0)]]:
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
	_box(&"base", Vector3(0, 6, 0), Vector3(12, 12, 12), false)
	_box(&"base", Vector3(0, 3.75, 6.2), Vector3(2.4, 7.5, 0.5), true)
	_box(&"torso", Vector3(0, 18, 0), Vector3(6, 12, 5), false)
	_box(&"torso", Vector3(0, 19.6, 2.95), Vector3(3.3, 10.0, 0.8), true, true)
	_box(&"torso", Vector3(0, 24.8, 0), Vector3(6.4, 0.6, 7), true, true)
	# Cracked palm and fingers are grippable: the rear service seam meets the
	# underside when the summoned hand arrives, then wraps onto its deck.
	_box(&"hand", Vector3.ZERO, Vector3(5, 1.2, 5), true)
	_box(&"hand", Vector3(0, 0.6, 0), Vector3(5, 0.4, 5), true)
	_box(&"hand", Vector3(1.5, 1.7, 0), Vector3(1, 1.8, 1), false)
	_box(&"head", Vector3(0, 3, 0), Vector3(4.5, 6, 4.5), false)
	_box(&"head", Vector3(0, 3, 2.5), Vector3(3.5, 6.1, 0.8), true, true)
	_box(&"head", Vector3(0, 6, 0), Vector3(4.5, 0.4, 4.5), true, true)
	_warning = MeshInstance3D.new()
	_warning.name = "SiegeLockedAim"
	_warning.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 3.2
	ring.outer_radius = 3.5
	_warning.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.12, 0.02)
	mat.emission_energy_multiplier = 2.0
	_warning.material_override = mat
	_warning.visible = false
	add_child(_warning)

func _box(bone: StringName, at: Vector3, size: Vector3, fur: bool, upper := false) -> void:
	var seg: BodySegment = _seg_by_bone[bone]
	var col := ClimbPatch.new() if fur else CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = at
	seg.add_child(col)
	if upper:
		_upper_patches.append(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.29, 0.33, 0.3) if fur else Color(0.42, 0.43, 0.4)
	mesh.material_override = mat
	mesh.set_meta(&"kind", 0 if fur else 1)
	mesh.set_meta(&"part_size", size)
	seg.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"malus_siege")
func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	hand_time += delta
	if encounter == Encounter.DEFEATED:
		_shot_active = false
		_warning.visible = false
		return
	var players := _players()
	if encounter == Encounter.DORMANT:
		for p in players:
			if p.global_position.distance_to(global_position) < 135.0:
				encounter = Encounter.COMBAT
				encounter_changed.emit(encounter)
	match hand_phase:
		Hand.SEALED: _hand_position = HAND_HIGH
		Hand.LOWERING:
			_hand_position = HAND_HIGH.lerp(HAND_LOW, _smooth(clampf(hand_time / 5.0, 0, 1)))
			if hand_time >= 5.0:
				hand_phase = Hand.BOARD
				hand_time = 0.0
		Hand.BOARD: _hand_position = HAND_LOW
		Hand.RAISING:
			_hand_position = HAND_LOW.lerp(HAND_DOCK, _smooth(clampf(hand_time / 7.0, 0, 1)))
			if hand_time >= 7.0:
				hand_phase = Hand.DOCKED
				hand_time = 0.0
		Hand.DOCKED: _hand_position = HAND_DOCK
	var has_rider := false
	for p in players:
		if p.get_support_body() == _seg_by_bone[&"hand"] and p.global_position.distance_to(global_position) < 35.0:
			has_rider = true
			if not _hand_rider_seen.has(p.get_instance_id()):
				stats.hand_riders += 1
				_hand_rider_seen[p.get_instance_id()] = true
	wrist.enabled = hand_phase == Hand.BOARD and has_rider
	for patch in _upper_patches:
		if patch.disabled == (hand_phase == Hand.DOCKED):
			patch.set_deferred(&"disabled", hand_phase != Hand.DOCKED)
	weak_point.set_protected(hand_phase != Hand.DOCKED)
	_update_siege(delta, players)
	_warning.visible = _shot_active
	if _shot_active:
		_warning.global_position = _shot_target + Vector3.UP * 0.08

func _pose_bones(_delta: float) -> void:
	skeleton.set_bone_pose_position(_bone[&"hand"], _hand_position)
	# A visible recoil only after a telegraphed shot. The body is stationary.
	skeleton.set_bone_pose_rotation(_bone[&"head"], Quaternion.from_euler(Vector3(0, 0.015 * sin(_time), 0)))

func _update_siege(delta: float, players: Array[PlayerCharacter]) -> void:
	if encounter != Encounter.COMBAT or hand_phase != Hand.SEALED:
		_shot_active = false
		_shot_clock = 0.0
		return
	_shot_clock += delta
	if not _shot_active and _shot_clock >= 4.0:
		for p in players:
			if not owns_body(p.get_support_body()):
				_shot_target = p.global_position - Vector3.UP * 0.9
				_shot_active = true
				_shot_clock = 0.0
				stats.volleys += 1
				break
	if _shot_active and _shot_clock >= 2.2:
		var origin := global_transform * Vector3(0, 28, -3)
		var q := PhysicsRayQueryParameters3D.create(origin, _shot_target + Vector3.UP * 0.4, Layers.WORLD)
		var cover := get_world_3d().direct_space_state.intersect_ray(q)
		if not cover.is_empty():
			stats.cover_blocks += 1
		else:
			for p in players:
				if _flat(p.global_position - _shot_target).length() < 3.5 and p.global_position.y < global_position.y + 4.0:
					if p.apply_hit(38.0, _flat(p.global_position - global_position).normalized() * 6.0 + Vector3.UP * 3.0, 1.0, &"malus_siege"):
						stats.hits_on_player += 1
		_shot_active = false
		_shot_clock = 0.0

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf: start_transform = xf
	global_transform = start_transform
	encounter = Encounter.DORMANT
	hand_phase = Hand.SEALED
	hand_time = 0.0
	_hand_position = HAND_HIGH
	_shot_active = false
	_shot_clock = 0.0
	_warning.visible = false
	_hand_rider_seen.clear()
	weak_point.reset()
	weak_point.set_protected(true)
	pressure_mark.reset()
	wrist.enabled = false
	stats = {"volleys": 0, "cover_blocks": 0, "hits_on_player": 0, "pressure_hits": 0, "wrist_hits": 0, "hand_riders": 0, "weak_point_hits": 0}
	_pose_bones(0)
	_sync_segments()
	_sync_segments()
	for seg in segments: seg.reset_physics_interpolation()
func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED
func encounter_name() -> String:
	return Encounter.keys()[encounter]
func beam_weak_point() -> WeakPoint:
	return pressure_mark if hand_phase == Hand.SEALED else weak_point
func get_focus_point() -> Vector3:
	return global_transform * Vector3(0, 25, 0)
func get_danger_zones() -> Array:
	return [[_shot_target, 3.5, maxf(0.0, 2.2 - _shot_clock)]] if _shot_active else []
func region_of(p: Node3D) -> StringName:
	if not owns_body(p.get_support_body()): return &""
	return (p.get_support_body() as BodySegment).bone_name
func _players() -> Array[PlayerCharacter]:
	var out: Array[PlayerCharacter] = []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p is PlayerCharacter and not p.dead: out.append(p)
	return out
func debug_text() -> String:
	return "MALUS %s | hand %s | pressure/wrist %d/%d" % [encounter_name(), Hand.keys()[hand_phase], stats.pressure_hits, stats.wrist_hits]
static func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
