class_name Pelagia
extends Colossus
## Amphibious ruin guardian prototype. Three stone teeth on the back steer it into
## three buttresses; each impact opens the shell sigil for one sword strike.
enum Encounter { DORMANT, NOTICE, COMBAT, DEFEATED }
enum RuinPhase { WAIT, STEERING, IMPACT_TELEGRAPH, EXPOSED, RECOVER }
signal ruin_impact(index: int)
signal ruins_restored
const RUINS_LOCAL := [Vector3(-24, 0, -8), Vector3(0, 0, -29), Vector3(24, 0, -8)]
const CONTROL_POINTS := [Vector3(-2.8, 5.5, -2), Vector3(0, 5.5, -3.8), Vector3(2.8, 5.5, -2)]
const SIGIL_LOCAL := Vector3(0, 5.5, 3)
var encounter := Encounter.DORMANT
var ruin_phase := RuinPhase.WAIT
var phase_time := 0.0
var encounter_time := 0.0
var weak_points: Array[WeakPoint] = []
var teeth: Array[WeakPoint] = []
var weak_point: WeakPoint
var broken_ruins: Array[bool] = [false, false, false]
var selected_ruin := -1
var ruin_goal := Vector3.ZERO
var start_transform := Transform3D.IDENTITY
var yaw := 0.0
var speed := 0.0
var brain_seed := 71
var effects_enabled := true
@export var guard_telegraph := 2.4
var stats := {"tooth_hits": 0, "ruin_impacts": 0, "weak_point_hits": 0, "pulses": 0, "hits_on_player": 0, "defeated_at": -1.0}
var _back: BodySegment
var _pulse_clock := 0.0
var _pulse_target := Vector3.ZERO
var _pulse_active := false
var _pulse_hit := {}
var _pulse_warning: MeshInstance3D

func _ready() -> void:
	super()
	start_transform = global_transform
	yaw = global_rotation.y
	add_to_group(&"danger_sources")
	weak_point = WeakPoint.create(_back, SIGIL_LOCAL, 100.0)
	weak_points.append(weak_point)
	weak_point.set_protected(true)
	weak_point.struck.connect(_on_sigil_struck)
	weak_point.destroyed.connect(_on_destroyed)
	for i in 3:
		var tooth := WeakPoint.create(_back, CONTROL_POINTS[i], 100000.0)
		tooth.name = "SteeringTooth%d" % i
		tooth.radius = 1.15
		tooth.struck.connect(func(_damage: float, _health: float) -> void: _on_tooth_struck(i))
		teeth.append(tooth)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	var idx := skeleton.add_bone("back")
	skeleton.set_bone_rest(idx, Transform3D.IDENTITY)
	_back = BodySegment.new()
	_back.name = "Seg_back"
	_back.colossus = self
	_back.bone_name = &"back"
	_back.bone_idx = idx
	add_child(_back)
	segments.append(_back)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.37, 0.45, 0.39)
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.19, 0.34, 0.23)
	var tooth := StandardMaterial3D.new()
	tooth.albedo_color = Color(0.73, 0.72, 0.58)
	_box(Vector3(0, 3, 0), Vector3(8.4, 4, 11), stone)
	_box(Vector3(0, 5.2, 0), Vector3(8.4, 0.5, 11), moss, true)
	_box(Vector3(0, 2.7, 5.7), Vector3(5.0, 5.2, 0.9), moss, true)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 4.35, 2.8, 0), Vector3(0.6, 5.0, 9), moss, true)
		for z in [-4.0, 4.0]:
			_box(Vector3(side * 3.1, 1.3, z), Vector3(2.5, 2.6, 3), stone)
	_box(Vector3(0, 4.2, -6.0), Vector3(5.0, 3.0, 3.2), stone)
	for at in CONTROL_POINTS:
		_box(at + Vector3.DOWN * 0.25, Vector3(1.3, 0.6, 1.3), tooth)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.3, 6.8, -6), Vector3(0.9, 3.0, 0.9), tooth)
	_pulse_warning = MeshInstance3D.new()
	_pulse_warning.name = "LockedPulseWarning"
	_pulse_warning.top_level = true
	var ring := TorusMesh.new()
	ring.inner_radius = 3.75
	ring.outer_radius = 4.0
	_pulse_warning.mesh = ring
	var warning := StandardMaterial3D.new()
	warning.albedo_color = Color(1.0, 0.48, 0.12)
	warning.emission_enabled = true
	warning.emission = Color(1.0, 0.22, 0.02)
	warning.emission_energy_multiplier = 2.0
	_pulse_warning.material_override = warning
	_pulse_warning.visible = false
	add_child(_pulse_warning)

func _box(at: Vector3, size: Vector3, mat: Material, climb := false) -> void:
	var col := ClimbPatch.new() if climb else CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = at
	_back.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	mesh.set_meta(&"kind", 0 if climb else 1)
	mesh.set_meta(&"part_size", size)
	_back.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"pelagia_steer" if ruin_phase == RuinPhase.STEERING else &"pelagia_guard")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	phase_time += delta
	encounter_time += delta
	if encounter == Encounter.DEFEATED:
		speed = move_toward(speed, 0.0, delta * 2.0)
		return
	var living := _living_players()
	if encounter == Encounter.DORMANT and not living.is_empty():
		for p in living:
			if p.global_position.distance_to(global_position) < 55.0:
				encounter = Encounter.NOTICE
				encounter_time = 0.0
				break
	if encounter == Encounter.NOTICE and encounter_time >= 2.0:
		encounter = Encounter.COMBAT
	if encounter != Encounter.COMBAT:
		return
	if ruin_phase == RuinPhase.STEERING:
		var to := _flat(ruin_goal - global_position)
		var desired := atan2(-to.x, -to.z)
		yaw = rotate_toward(yaw, desired, delta * 0.42)
		var angle := absf(wrapf(desired - yaw, -PI, PI))
		speed = move_toward(speed, 3.2 * clampf(1.0 - angle, 0.0, 1.0), delta * 1.5)
		global_position += Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed * delta
		if to.length() < 9.0:
			ruin_phase = RuinPhase.IMPACT_TELEGRAPH
			phase_time = 0.0
	elif ruin_phase == RuinPhase.IMPACT_TELEGRAPH:
		speed = move_toward(speed, 0.0, delta * 2.0)
		if phase_time >= 2.4:
			broken_ruins[selected_ruin] = true
			stats.ruin_impacts += 1
			ruin_impact.emit(selected_ruin)
			ruin_phase = RuinPhase.EXPOSED
			phase_time = 0.0
			weak_point.set_protected(false)
			if effects_enabled:
				Fx.dust(get_parent(), ruin_goal, 3.0)
				Sfx.play(self, &"stomp", ruin_goal)
	elif ruin_phase == RuinPhase.EXPOSED:
		speed = 0.0
		if phase_time >= 22.0:
			ruin_phase = RuinPhase.RECOVER
			phase_time = 0.0
			weak_point.set_protected(true)
	elif ruin_phase == RuinPhase.RECOVER:
		speed = 0.0
		if phase_time >= 2.0:
			ruin_phase = RuinPhase.WAIT
			phase_time = 0.0
			selected_ruin = -1
			# A missed opportunity may be repeated: ruined stone still pins the shell.
			if not broken_ruins.has(false):
				broken_ruins = [false, false, false]
	global_rotation.y = yaw
	for i in 3:
		teeth[i].set_protected(ruin_phase != RuinPhase.WAIT or broken_ruins[i])
	_update_guard_pulse(delta, living)
	_pulse_warning.visible = _pulse_active
	if _pulse_active:
		_pulse_warning.global_position = Vector3(_pulse_target.x, maxf(global_position.y - 0.2, _pulse_target.y + 0.8), _pulse_target.z)

func _pose_bones(_delta: float) -> void:
	# Very gentle water rocking. The control deck stays a continuous walkable frame.
	var rocking := 0.012 * sin(_time * 1.3)
	var brace := 0.05 * sin(PI * clampf(phase_time / 2.4, 0.0, 1.0)) if ruin_phase == RuinPhase.IMPACT_TELEGRAPH else 0.0
	skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(brace, 0, rocking)))

func _living_players() -> Array[PlayerCharacter]:
	var result: Array[PlayerCharacter] = []
	for n in get_tree().get_nodes_in_group(&"players"):
		if n is PlayerCharacter and not n.dead:
			result.append(n)
	return result

func _update_guard_pulse(delta: float, living: Array[PlayerCharacter]) -> void:
	# The guardian challenges swimmers approaching its head. A locked circle gives
	# 2.4 seconds to dodge; its rear moss remains a deliberate entry opportunity.
	if ruin_phase != RuinPhase.WAIT:
		_pulse_clock = 0.0
		_pulse_active = false
		return
	_pulse_clock += delta
	if _pulse_clock >= 5.0 and not _pulse_active:
		for p in living:
			if owns_body(p.get_support_body()):
				continue
			var local := global_transform.affine_inverse() * p.global_position
			if local.z < 1.0 and _flat(local).length() < 42.0:
				_pulse_target = p.global_position
				_pulse_active = true
				_pulse_clock = 0.0
				_pulse_hit.clear()
				stats.pulses += 1
				break
	if _pulse_active and _pulse_clock >= guard_telegraph:
		for p in living:
			if not _pulse_hit.has(p.get_instance_id()) and not owns_body(p.get_support_body()) and _flat(p.global_position - _pulse_target).length() < 4.0:
				p.apply_hit(28.0, Vector3.UP * 4.0, 1.0, &"pelagia_guard_pulse")
				_pulse_hit[p.get_instance_id()] = true
				stats.hits_on_player += 1
		_pulse_active = false
		_pulse_clock = 0.0

func _on_tooth_struck(index: int) -> void:
	if encounter != Encounter.COMBAT or ruin_phase != RuinPhase.WAIT or broken_ruins[index]:
		return
	stats.tooth_hits += 1
	selected_ruin = index
	ruin_goal = start_transform * RUINS_LOCAL[index]
	ruin_phase = RuinPhase.STEERING
	phase_time = 0.0
	for t in teeth:
		t.set_protected(true)

func _on_sigil_struck(_damage: float, _left: float) -> void:
	stats.weak_point_hits += 1
	# One opening buys one strike. Three fully charged strikes still need all ruins.
	weak_point.set_protected(true)
	ruin_phase = RuinPhase.RECOVER
	phase_time = 0.0

func _on_destroyed() -> void:
	encounter = Encounter.DEFEATED
	stats.defeated_at = _time
	defeated.emit()

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		start_transform = xf
	global_transform = start_transform
	yaw = global_rotation.y
	speed = 0.0
	encounter = Encounter.DORMANT
	ruin_phase = RuinPhase.WAIT
	phase_time = 0.0
	encounter_time = 0.0
	selected_ruin = -1
	broken_ruins = [false, false, false]
	_pulse_clock = 0.0
	_pulse_active = false
	_pulse_warning.visible = false
	weak_point.reset()
	weak_point.set_protected(true)
	for t in teeth:
		t.reset()
	stats = {"tooth_hits": 0, "ruin_impacts": 0, "weak_point_hits": 0, "pulses": 0, "hits_on_player": 0, "defeated_at": -1.0}
	_sync_segments()
	_sync_segments()
	for s in segments:
		s.reset_physics_interpolation()
	ruins_restored.emit()

func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED
func encounter_name() -> String:
	return Encounter.keys()[encounter]
func get_focus_point() -> Vector3:
	return _back.target_transform * Vector3(0, 5, -4)
func beam_weak_point() -> WeakPoint:
	if ruin_phase == RuinPhase.EXPOSED or is_defeated():
		return weak_point
	for i in 3:
		if not broken_ruins[i]:
			return teeth[i]
	return weak_point
func get_danger_zones() -> Array:
	return [[_pulse_target, 4.0, maxf(0.0, guard_telegraph - _pulse_clock)]] if _pulse_active else []
func region_of(p: Node3D) -> StringName:
	return &"back" if owns_body(p.get_support_body()) else &""
func get_speed() -> float:
	return speed
func debug_text() -> String:
	return "PELAGIA %s | %s | ruins %s" % [encounter_name(), RuinPhase.keys()[ruin_phase], broken_ruins]
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
