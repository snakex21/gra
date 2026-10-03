class_name Dirge
extends Hydrus
## Land pursuit puzzle, reusing the serpent's bone trail rather than its water AI.
## Its buried armour protects every sigil. A real eye arrow commits a blind charge;
## only a collision with the arena wall exposes the climbable back.
enum Pursuit { WAITING, WARNING, CHASING, BLINDED, STUNNED, RECOVERING }
const CHASE := &"dirge_chase"
const BLIND_CHARGE := &"blind_charge"
const STUN := &"wall_stun"
var pursuit := Pursuit.WAITING
var pursuit_time := 0.0
var eye_targets: Array[ArrowTarget] = []
var focus: PlayerCharacter
var eye_hits := 0
var wall_impacts := 0
var _exposure := 0.0
var _blind_direction := Vector3.FORWARD
var _hit_ids := {}
var _last_hit_at := -999.0
var _chase_cooldown := 0.0
var arena_basis := Basis.IDENTITY

func _init() -> void:
	super()
	water_level = 1.7
	swim_depth = 0.0
	wave_amplitude = 0.28
	weak_point_health = 60.0
	notice_radius = 85.0
	arena_radius = 100.0
	brain_seed = 67
	shake_after_flinch = 3.0
	shake_max_duration = 2.0

func _ready() -> void:
	super()
	add_to_group(&"danger_sources")
	var head: BodySegment = _seg_by_bone[&"head"]
	for side: float in [-1.0, 1.0]:
		var point := Vector3(side * 1.05, 0.95, -3.05)
		var eye := ArrowTarget.create(head, point, Vector3.FORWARD, 0.9, &"eye")
		eye.max_incidence_deg = 85.0
		eye.hit.connect(_on_eye_hit)
		eye_targets.append(eye)
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.55
		sphere.height = 1.1
		mesh.mesh = sphere
		mesh.position = point
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.65, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.48, 0.08)
		mat.emission_energy_multiplier = 3.0
		mesh.material_override = mat
		head.add_child(mesh)
	_update_protection()

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if is_defeated():
		return ColossusIntent.make(ColossusIntent.IDLE)
	if pursuit == Pursuit.WAITING:
		focus = _find_target(obs)
		if focus != null and (focus.is_riding() or focus.global_position.distance_to(global_position) < 24.0) and _chase_cooldown <= 0.0:
			_set_encounter(Encounter.COMBAT)
			_set_pursuit(Pursuit.WARNING)
	if pursuit == Pursuit.WARNING or pursuit == Pursuit.CHASING:
		if not is_instance_valid(focus) or focus.dead:
			focus = _find_target(obs)
		var chosen := ColossusIntent.make(CHASE)
		chosen.target_player = focus
		return chosen
	if pursuit == Pursuit.BLINDED:
		return ColossusIntent.make(BLIND_CHARGE)
	return ColossusIntent.make(STUN if pursuit == Pursuit.STUNNED else ColossusIntent.IDLE)

func _find_target(obs: ColossusObservation) -> PlayerCharacter:
	var selected: PlayerCharacter
	for info in obs.players:
		var p := info.player as PlayerCharacter
		if p == null or p.dead or owns_body(p.get_support_body()) or _flat(p.global_position - arena_center).length() > arena_radius + 10.0:
			continue
		if selected == null or (p.is_riding() and not selected.is_riding()) or (p.is_riding() == selected.is_riding() and p.global_position.distance_to(global_position) < selected.global_position.distance_to(global_position)):
			selected = p
	return selected

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	pursuit_time += delta
	_flinch_t += delta
	_chase_cooldown = maxf(0.0, _chase_cooldown - delta)
	if is_defeated():
		speed = move_toward(speed, 0.0, delta * 12.0)
		_roll = move_toward(_roll, 0.0, delta)
		_update_protection()
		return
	var want_speed := 0.0
	var goal := _head
	match pursuit:
		Pursuit.WARNING:
			rear_w = move_toward(rear_w, 1.0, delta)
			if is_instance_valid(focus):
				goal = focus.global_position
			if pursuit_time >= 2.0:
				_set_pursuit(Pursuit.CHASING)
		Pursuit.CHASING:
			rear_w = move_toward(rear_w, 0.25, delta)
			if is_instance_valid(focus):
				goal = focus.global_position
				var distance := _flat(goal - _head).length()
				want_speed = 14.0 if distance > 15.0 else 9.0
			# A breath between charges gives a player time to get back on Agro.
			if pursuit_time >= 30.0:
				_set_pursuit(Pursuit.RECOVERING)
		Pursuit.BLINDED:
			rear_w = move_toward(rear_w, 0.0, delta * 2.0)
			goal = _head + _blind_direction * 40.0
			want_speed = 18.0
			if _wall_ahead(delta):
				wall_impacts += 1
				_set_pursuit(Pursuit.STUNNED)
				want_speed = 0.0
				speed = 0.0
				if Fx.enabled:
					Fx.dust(get_parent(), _head, 4.0)
				if Sfx.enabled:
					Sfx.play(self, &"stomp", _head)
			elif pursuit_time > 14.0:
				# No suitable wall ahead: no free weak points; return to pursuit.
				_set_pursuit(Pursuit.RECOVERING)
		Pursuit.STUNNED:
			rear_w = move_toward(rear_w, 0.0, delta)
			_exposure = move_toward(_exposure, 1.0, delta / 1.0)
			if pursuit_time >= 75.0:
				_set_pursuit(Pursuit.RECOVERING)
		Pursuit.RECOVERING:
			_exposure = move_toward(_exposure, 0.0, delta / 2.5)
			if pursuit_time >= 6.0:
				_set_pursuit(Pursuit.WAITING)
				_chase_cooldown = 2.0
	if pursuit != Pursuit.STUNNED:
		_exposure = move_toward(_exposure, 0.0, delta)
	_roll = 0.1 * sin(_time * 3.0) * clampf(1.0 - _flinch_t / 1.4, 0.0, 1.0)
	speed = move_toward(speed, want_speed, delta * (8.0 if want_speed > speed else 16.0))
	_advance_land(delta, goal)
	_update_protection()

func _advance_land(delta: float, goal: Vector3) -> void:
	var to := _flat(goal - _head)
	if to.length() > 0.5 and pursuit != Pursuit.STUNNED:
		var want_yaw := atan2(-to.x, -to.z)
		yaw += clampf(angle_difference(yaw, want_yaw), -0.7 * delta, 0.7 * delta)
	var direction := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var next := _head + direction * speed * delta
	# Chase can turn at the rim; a blinded charge must actually strike the wall.
	var local := arena_basis.inverse() * (next - arena_center)
	if pursuit != Pursuit.BLINDED and (absf(local.x) > 91.0 or absf(local.z) > 91.0):
		yaw += delta * 2.0
		speed = minf(speed, 3.0)
		next = _head + Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed * delta
	next.y = water_level
	_head = next
	if _trail.is_empty() or _head.distance_to(_trail[-1]) >= TRAIL_STEP:
		_trail.append(_head)
		if _trail.size() > 280:
			_trail = _trail.slice(-160)

func _wall_ahead(delta: float) -> bool:
	var from := Vector3(_head.x, arena_center.y + 2.0, _head.z)
	var to := from + _blind_direction * (3.4 + maxf(speed, 18.0) * delta)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD))
	return not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.4

func _pose_bones(delta: float) -> void:
	super(delta)
	for i in range(1, SEG_COUNT):
		var idx: int = _bone[_bone_name(i)]
		var pose := skeleton.get_bone_pose(idx)
		pose.origin.y -= lerpf(3.3, 0.7, _exposure)
		skeleton.set_bone_pose(idx, pose)

func _post_sync(_delta: float) -> void:
	if pursuit != Pursuit.CHASING or _time - _last_hit_at < 3.0:
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p == null or p.dead or owns_body(p.get_support_body()) or p.balance.state == Balance.State.FALLEN:
			continue
		if _flat(p.global_position - head_point()).length() < 3.7:
			var away := _flat(p.global_position - _head).normalized()
			if p.apply_hit(28.0, away * 9.0 + Vector3.UP * 2.5, 1.2, &"dirge_charge"):
				_last_hit_at = _time
				stats.player_hits = int(stats.player_hits) + 1

func _on_eye_hit(_info: Dictionary) -> void:
	if pursuit != Pursuit.CHASING:
		return
	eye_hits += 1
	_blind_direction = Basis(Vector3.UP, yaw) * Vector3.FORWARD
	_set_pursuit(Pursuit.BLINDED)
	_update_protection()

func _update_protection() -> void:
	for wp in weak_points:
		wp.set_protected(pursuit != Pursuit.STUNNED or _exposure < 0.8)
	for eye in eye_targets:
		eye.enabled = pursuit == Pursuit.CHASING

func _set_pursuit(next: Pursuit) -> void:
	pursuit = next
	pursuit_time = 0.0
	_think_left = 0.0

func get_danger_zones() -> Array:
	if pursuit == Pursuit.WARNING:
		return [[head_point() + Basis(Vector3.UP, yaw) * Vector3.FORWARD * 12, 5.0, 2.0 - pursuit_time]]
	return []

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	pursuit = Pursuit.WAITING
	pursuit_time = 0.0
	_exposure = 0.0
	_chase_cooldown = 0.0
	focus = null
	eye_hits = 0
	wall_impacts = 0
	_last_hit_at = -999.0
	_hit_ids.clear()
	super(xf, use_xf)
	_update_protection()

func debug_text() -> String:
	return "DIRGE %s %.1fs | Agro: uciekaj, strzel w oko, po zderzeniu wejdź na grzbiet\n%s" % [Pursuit.keys()[pursuit], pursuit_time, super().replace("HYDRUS", "DIRGE")]

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
