class_name Phalanx
extends Colossus
## Active air-barrier guardian. Bow-popped lift sacs create a low flight window;
## grab+jump from Agro near the deployed wing is the boarding action.
enum Encounter { DORMANT, COMBAT, DEFEATED }
enum Flight { PATROL, DESCEND, LOW, CARRY }
signal encounter_changed(state: Encounter)
enum Kind { FUR, STONE }
const BODY_OFFSETS := [-18.0, 0.0, 18.0]
var encounter := Encounter.DORMANT
var flight := Flight.PATROL
var flight_time := 0.0
var speed := 0.0
var yaw := 0.0
var brain_seed := 101
var weak_points: Array[WeakPoint] = []
var sacs: Array[ArrowTarget] = []
var popped: Array[bool] = [false, false, false]
var stats := {"sac_hits": 0, "horse_boardings": 0, "wing_grabs": 0, "weak_point_hits": 0, "wind_attacks": 0, "hits_on_player": 0}
var effects_enabled := true
var start_transform := Transform3D.IDENTITY
var _bone := {}
var _seg_by_bone := {}
var _sac_meshes: Array[MeshInstance3D] = []
var _wind_clock := 0.0
var _wind_active := false
var _wind_target := Vector3.ZERO
var _warning: MeshInstance3D
var _boarding_players := {}
var _carry_angle := 0.0
var _sigil_clock := 0.0
var _fur_patches: Array[ClimbPatch] = []
var _boarding_horses := {}
var _lost_rider := 0.0

func _ready() -> void:
	super()
	start_transform = global_transform
	yaw = global_rotation.y
	add_to_group(&"danger_sources")
	for i in 3:
		var segment: BodySegment = _seg_by_bone[StringName("body%d" % i)]
		var sac := ArrowTarget.create(segment, Vector3(0, -3.0, 0), Vector3.DOWN, 1.7, i)
		sac.max_incidence_deg = 110.0
		sac.hit.connect(func(_info: Dictionary) -> void: _on_sac_hit(i))
		sacs.append(sac)
		var wp := WeakPoint.create(segment, Vector3(0, 2.22, 0), 40.0)
		wp.min_power = 0.5
		wp.set_protected(true)
		wp.struck.connect(func(_d: float, _h: float) -> void:
			stats.weak_point_hits += 1
			_flinched(1.0))
		wp.destroyed.connect(_on_sigil_destroyed)
		weak_points.append(wp)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for i in 3:
		var bone := StringName("body%d" % i)
		var idx := skeleton.add_bone(bone)
		_bone[bone] = idx
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, Vector3(0, 0, BODY_OFFSETS[i])))
		var seg := _segment(bone, idx)
		_box(seg, Vector3(0, 0, 0), Vector3(6, 4, 20), false)
		_box(seg, Vector3(0, 2.0, 0), Vector3(6.0, 0.4, 20.2), true)
		var sac_mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.6
		sm.height = 3.2
		sac_mesh.mesh = sm
		sac_mesh.position = Vector3(0, -2.5, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.79, 0.77, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(0.24, 0.23, 0.1)
		sac_mesh.material_override = mat
		seg.add_child(sac_mesh)
		_sac_meshes.append(sac_mesh)
	# Broad paired sail wings form a stable plateau. The outside curtain provides
	# the vertical climb from the saddle; the route then crosses the inner wing.
	for side in [-1.0, 1.0]:
		var idx := skeleton.add_bone("wing_l" if side < 0 else "wing_r")
		var bone := &"wing_l" if side < 0 else &"wing_r"
		_bone[bone] = idx
		skeleton.set_bone_rest(idx, Transform3D.IDENTITY)
		var seg := _segment(bone, idx)
		_box(seg, Vector3(side * 7.3, 1.7, 0), Vector3(11.4, 0.6, 8), true)
		_box(seg, Vector3(side * 12.7, 0, 0), Vector3(0.7, 4.0, 8), true)
	skeleton.reset_bone_poses()
	_warning = MeshInstance3D.new()
	_warning.name = "WindLockWarning"
	_warning.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 3.8
	ring.outer_radius = 4.0
	_warning.mesh = ring
	var warning_mat := StandardMaterial3D.new()
	warning_mat.albedo_color = Color(0.82, 0.95, 1.0)
	warning_mat.emission_enabled = true
	warning_mat.emission = Color(0.2, 0.8, 1.0)
	warning_mat.emission_energy_multiplier = 2.0
	_warning.material_override = warning_mat
	_warning.visible = false
	add_child(_warning)

func _segment(bone: StringName, idx: int) -> BodySegment:
	var seg := BodySegment.new()
	seg.name = "Seg_" + bone
	seg.colossus = self
	seg.bone_name = bone
	seg.bone_idx = idx
	add_child(seg)
	segments.append(seg)
	_seg_by_bone[bone] = seg
	return seg

func _box(seg: BodySegment, at: Vector3, size: Vector3, fur: bool) -> void:
	var col := ClimbPatch.new() if fur else CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = at
	seg.add_child(col)
	if fur:
		_fur_patches.append(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.34, 0.22) if fur else Color(0.59, 0.54, 0.41)
	mesh.material_override = mat
	mesh.set_meta(&"kind", 0 if fur else 1)
	mesh.set_meta(&"part_size", size)
	seg.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"phalanx_barrier")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	flight_time += delta
	_sigil_clock += delta
	for p in _boarding_horses.keys():
		var h: Horse = _boarding_horses[p]
		if not is_instance_valid(p) or not is_instance_valid(h):
			_boarding_horses.erase(p)
		elif p.is_climbing() or p.global_position.distance_to(h.global_position) > 5.0:
			p.remove_collision_exception_with(h)
			_boarding_horses.erase(p)
	if encounter == Encounter.DEFEATED:
		global_position.y = move_toward(global_position.y, arena_center.y + 2.4, delta * 0.8)
		return
	var players := _players()
	for p in players:
		if _flat(p.global_position - arena_center).length() < 125.0 and encounter == Encounter.DORMANT:
			encounter = Encounter.COMBAT
			encounter_changed.emit(encounter)
	var ridden := players.any(func(p: PlayerCharacter) -> bool: return owns_body(p.get_support_body()) and (p.is_climbing() or p.state == PlayerCharacter.State.GROUND) and p.global_position.distance_to(global_position) < 70.0)
	_lost_rider = 0.0 if ridden else _lost_rider + delta
	if flight == Flight.CARRY and _lost_rider > 3.0:
		flight = Flight.DESCEND
		flight_time = 0.0
	if ridden and flight != Flight.CARRY:
		flight = Flight.CARRY
		flight_time = 0.0
		_sigil_clock = 0.0
		_carry_angle = 0.0
	if flight == Flight.PATROL:
		var goal := arena_center
		goal = arena_center + start_transform.basis * Vector3(sin(_time * 0.055) * 28.0, 17.0, -10.0)
		speed = global_position.distance_to(goal) / maxf(delta, 0.001)
		global_position = global_position.lerp(goal, minf(1.0, delta * 0.55))
	elif flight == Flight.DESCEND:
		global_position.y = move_toward(global_position.y, arena_center.y + 3.4, delta * 1.4)
		if global_position.y <= arena_center.y + 3.41:
			flight = Flight.LOW
			flight_time = 0.0
	elif flight == Flight.LOW:
		# Slow level flight beside Agro. Its long low wing gives a generous boarding
		# window, while remaining well above the ground for someone on foot.
		global_position += start_transform.basis.x * delta * 0.55
		_try_horse_boarding(players)
		if flight_time > 65.0 and not ridden:
			flight = Flight.PATROL
			flight_time = 0.0
			popped = [false, false, false]
			for mesh in _sac_meshes:
				mesh.visible = true
	elif flight == Flight.CARRY:
		# Gentle sail across the guardian's own barrier; shallow yaw changes preserve
		# the long walking surface. It reacts with a warned roll, not fleeing.
		global_position.y = move_toward(global_position.y, arena_center.y + 10.0, delta * 0.6)
		_carry_angle += delta * 0.035
		yaw = start_transform.basis.get_euler().y + sin(_carry_angle) * 0.16
		global_position += (Basis(Vector3.UP, yaw) * Vector3.FORWARD) * delta * 0.8
	global_rotation.y = yaw
	var boardable := flight == Flight.CARRY or (flight == Flight.LOW and not _boarding_players.is_empty())
	for patch in _fur_patches:
		if patch.disabled == boardable:
			patch.set_deferred(&"disabled", not boardable)
	for i in 3:
		sacs[i].enabled = encounter != Encounter.DEFEATED and flight == Flight.PATROL and not popped[i]
		weak_points[i].set_protected(flight != Flight.CARRY or fmod(_sigil_clock, 12.0) > 9.0)
	_update_wind(delta, players)
	_warning.visible = _wind_active
	if _wind_active:
		_warning.global_position = Vector3(_wind_target.x, arena_center.y + 0.08, _wind_target.z)

func _try_horse_boarding(players: Array[PlayerCharacter]) -> void:
	for p in players:
		if not p.is_riding() or p.riding.phase != PlayerRiding.Phase.RIDING or not p.actions.grab_held:
			continue
		var local := global_transform.affine_inverse() * p.global_position
		if absf(absf(local.x) - 17.3) > 3.0 or absf(local.z) > 5.0:
			continue
		if not p.actions.consume_jump():
			continue
		var direction := -global_basis.x * signf(local.x)
		var h := p.riding.horse
		p.add_collision_exception_with(h)
		_boarding_horses[p] = h
		p.riding._finish(direction * 8.0 + Vector3.UP * 6.5)
		p.facing = direction
		stats.horse_boardings += 1
		_boarding_players[p.get_instance_id()] = true

func _post_sync(_delta: float) -> void:
	for p in _players():
		if _boarding_players.has(p.get_instance_id()) and p.is_climbing() and owns_body(p.grip.body):
			stats.wing_grabs += 1
			_boarding_players.erase(p.get_instance_id())

func _pose_bones(_delta: float) -> void:
	var roll := 0.035 * sin(_time * 0.9) if flight == Flight.CARRY else 0.0
	for bone in _bone:
		skeleton.set_bone_pose_rotation(_bone[bone], Quaternion.from_euler(Vector3(0, 0, roll)))

func _update_wind(delta: float, players: Array[PlayerCharacter]) -> void:
	if encounter != Encounter.COMBAT or flight != Flight.PATROL:
		_wind_active = false
		_wind_clock = 0.0
		return
	_wind_clock += delta
	if not _wind_active and _wind_clock > 8.0:
		for p in players:
			if p.global_position.distance_to(global_position) < 90.0:
				_wind_target = p.global_position
				_wind_active = true
				_wind_clock = 0.0
				stats.wind_attacks += 1
				break
	if _wind_active and _wind_clock >= 2.4:
		for p in players:
			if _flat(p.global_position - _wind_target).length() < 4.0:
				if p.apply_hit(24.0, Vector3.UP * 3.0, 0.7, &"phalanx_barrier_wind"):
					stats.hits_on_player += 1
		_wind_active = false
		_wind_clock = 0.0

func _on_sac_hit(index: int) -> void:
	if popped[index]:
		return
	popped[index] = true
	_sac_meshes[index].visible = false
	stats.sac_hits += 1
	if not popped.has(false):
		flight = Flight.DESCEND
		flight_time = 0.0

func _on_sigil_destroyed() -> void:
	if weak_points_left() == 0:
		encounter = Encounter.DEFEATED
		encounter_changed.emit(encounter)
		defeated.emit()

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		start_transform = xf
	global_transform = start_transform
	yaw = global_rotation.y
	encounter = Encounter.DORMANT
	flight = Flight.PATROL
	flight_time = 0.0
	_time = 0.0
	_sigil_clock = 0.0
	_lost_rider = 0.0
	for p in _boarding_horses:
		if is_instance_valid(p) and is_instance_valid(_boarding_horses[p]):
			p.remove_collision_exception_with(_boarding_horses[p])
	_boarding_horses.clear()
	_boarding_players.clear()
	popped = [false, false, false]
	for mesh in _sac_meshes:
		mesh.visible = true
	for wp in weak_points:
		wp.reset()
		wp.set_protected(true)
	_wind_active = false
	_wind_clock = 0.0
	_warning.visible = false
	stats = {"sac_hits": 0, "horse_boardings": 0, "wing_grabs": 0, "weak_point_hits": 0, "wind_attacks": 0, "hits_on_player": 0}
	_pose_bones(0.0)
	_sync_segments()
	_sync_segments()
	for seg in segments:
		seg.reset_physics_interpolation()

func _players() -> Array[PlayerCharacter]:
	var out: Array[PlayerCharacter] = []
	for p in get_tree().get_nodes_in_group(&"players"):
		if p is PlayerCharacter and not p.dead:
			out.append(p)
	return out
func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED
func encounter_name() -> String:
	return Encounter.keys()[encounter]
func beam_weak_point() -> WeakPoint:
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			return wp
	return null
func weak_points_left() -> int:
	return weak_points.filter(func(w: WeakPoint) -> bool: return w.state != WeakPoint.State.DESTROYED).size()
func get_focus_point() -> Vector3:
	return global_position
func get_danger_zones() -> Array:
	return [[_wind_target, 4.0, maxf(0.0, 2.4 - _wind_clock)]] if _wind_active else []
func boarding_point() -> Vector3:
	return global_transform * Vector3(17.3, -3.4, 0)
func region_of(p: Node3D) -> StringName:
	return &"wing" if owns_body(p.get_support_body()) and String((p.get_support_body() as BodySegment).bone_name).begins_with("wing") else (&"back" if owns_body(p.get_support_body()) else &"")
func debug_text() -> String:
	return "PHALANX %s / %s | sacs %s | sigils %d" % [encounter_name(), Flight.keys()[flight], popped, weak_points_left()]
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
