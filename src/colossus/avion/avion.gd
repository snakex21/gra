class_name Avion
extends Colossus
## Avion: the sixth boss, a great bird (~30 m wingspan) over a lake with stone towers.
## A rigid body with a neck, a head, a tail fan and two-part wings that beat at the
## shoulders and elbows; it flies along a smooth path (yaw, pitch and speed limited,
## banking into its turns).
##
## Loop: climb a tower (or stand on the shore). It circles high above; when it sees you
## it screeches and banks (the telegraph), dives and pulls out low beside you, slowing
## right down at the lowest point so a wing sweeps just over your head - grab its fur.
## Climb round the wing onto its back and strike the spots on both wings and the tail.
## With someone on it, it glides in slow circles over the water (a fall lands in the
## lake) and rolls from side to side to throw them off.
##
##   intents: CIRCLE, SWOOP (telegraph -> dive -> pass -> climb), CARRY, SHAKE_BODY
## Fairness: no swoop at someone on it, a cooldown between swoops; rolls under the shared
## shake rules, none right after a weak point hit; over the water while anyone is on it.

signal encounter_changed(state: Encounter)

enum Encounter { DORMANT, COMBAT, DEFEATED }
enum Swoop { NONE, TELEGRAPH, DIVE, PASS, CLIMB }

const CIRCLE := &"circle"
const SWOOP := &"swoop"
const CARRY := &"carry"
const SHAKE_BODY := &"shake_body"

enum Kind { FUR, STONE }
const COLORS := {Kind.FUR: Color(0.42, 0.36, 0.28), Kind.STONE: Color(0.5, 0.5, 0.47)}

## Bones: [name, parent, rest offset]. Forward -Z, left -X.
const BONES := [
	[&"body", &"", Vector3.ZERO],
	[&"neck", &"body", Vector3(0, 0.6, -4.8)],
	[&"head", &"neck", Vector3(0, 0.2, -2.8)],
	[&"tail", &"body", Vector3(0, 0.3, 4.6)],
	[&"wing_l_in", &"body", Vector3(-1.6, 0.6, -0.5)],
	[&"wing_l_out", &"wing_l_in", Vector3(-7.0, 0, 0)],
	[&"wing_r_in", &"body", Vector3(1.6, 0.6, -0.5)],
	[&"wing_r_out", &"wing_r_in", Vector3(7.0, 0, 0)],
]
## Parts: [bone, kind, size, centre].
const PARTS := [
	[&"body", Kind.STONE, Vector3(3.2, 2.2, 9.0), Vector3(0, -0.1, 0)],
	[&"body", Kind.FUR, Vector3(2.8, 0.5, 8.4), Vector3(0, 1.2, 0)],
	[&"neck", Kind.STONE, Vector3(1.4, 1.4, 3.0), Vector3(0, 0, -1.2)],
	[&"neck", Kind.FUR, Vector3(1.2, 0.4, 2.8), Vector3(0, 0.85, -1.2)],
	[&"head", Kind.STONE, Vector3(1.6, 1.4, 2.6), Vector3(0, 0, -1.0)],
	[&"tail", Kind.FUR, Vector3(5.0, 0.4, 4.5), Vector3(0, 0, 2.0)],
	[&"wing_l_in", Kind.FUR, Vector3(7.0, 0.5, 4.0), Vector3(-3.5, 0, 0)],
	[&"wing_l_out", Kind.FUR, Vector3(6.0, 0.35, 3.0), Vector3(-3.0, 0, 0.3)],
	[&"wing_r_in", Kind.FUR, Vector3(7.0, 0.5, 4.0), Vector3(3.5, 0, 0)],
	[&"wing_r_out", Kind.FUR, Vector3(6.0, 0.35, 3.0), Vector3(3.0, 0, 0.3)],
]
## Weak points: [bone, local point] (on top of the inner wings and of the tail fan).
const WEAK := [[&"wing_l_in", Vector3(-4.5, 0.27, 0.6)], [&"wing_r_in", Vector3(4.5, 0.27, 0.6)], [&"tail", Vector3(0, 0.22, 2.6)]]
## Where under the inner wing a person should be when it passes (body space, the middle
## of the wing's span; the wing's underside is WING_UNDER above the body's centre).
const WING_REACH := 5.5
const WING_UNDER := 0.35

@export_group("Flight")
## Height of the patrol circle above the arena's ground, and its radius.
@export var circle_height := 32.0
@export var circle_radius := 70.0
@export var cruise_speed := 14.0
@export var carry_speed := 9.0
@export var carry_height := 22.0
@export var carry_radius := 24.0
@export var turn_rate := 0.55
@export var pitch_rate := 0.7
@export var accel := 3.0
@export_group("Swoop")
@export var swoop_telegraph := 1.6
@export var swoop_speed := 17.0
## Speed at the lowest point (it all but hangs there for a moment).
@export var pass_speed := 4.5
## A dive that has not reached its low point by then pulls up.
@export var swoop_dive_limit := 7.0
@export var swoop_cooldown := 7.0
@export var notice_radius := 120.0
@export_group("Encounter")
@export var weak_point_health := 80.0
## Over this water (set by the arena) while someone is on it.
@export var water_level := -1000.0

var encounter := Encounter.DORMANT
var weak_points: Array[WeakPoint] = []
var brain_seed := 41
var swoop := Swoop.NONE
var swoop_t := 0.0
var speed := 0.0
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var flap := 0.0
var stats := {}
var debug_draw: Node3D
## The low point of the current swoop (world).
var low_point := Vector3.ZERO

var _bone := {}
var _seg_by_bone := {}
var _start_xf := Transform3D.IDENTITY
var _yaw_rate := 0.0
var _flap_phase := 0.0
var _flap_w := 1.0
var _swoop_cooldown_left := 0.0
var _swoop_dir := Vector3.FORWARD
var _swoop_target: Node3D
var _flinch_t := 999.0
var _shake := 0.0


func _init() -> void:
	body_height = 6.0
	arena_radius = 120.0
	shake_max_duration = 2.6
	shake_cooldown = 6.0


func _ready() -> void:
	brain = AvionBrain.new(brain_seed)
	super()
	_start_xf = global_transform
	for w in WEAK:
		var wp := WeakPoint.create(_seg_by_bone[w[0]], w[1], weak_point_health)
		wp.struck.connect(_on_weak_point_struck)
		wp.destroyed.connect(_on_weak_point_destroyed)
		weak_points.append(wp)
	debug_draw = Node3D.new()
	debug_draw.name = "DebugDraw"
	debug_draw.visible = false
	add_child(debug_draw)
	_reset_stats()


func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in BONES:
		var idx := skeleton.add_bone(b[0])
		_bone[b[0]] = idx
		if b[1] != &"":
			skeleton.set_bone_parent(idx, _bone[b[1]])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()
	var mats := {}
	for k in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[k]
		m.roughness = 1.0 if k == Kind.FUR else 0.7
		mats[k] = m
	for part in PARTS:
		var bone: StringName = part[0]
		var seg: BodySegment = _seg_by_bone.get(bone)
		if seg == null:
			seg = BodySegment.new()
			seg.name = "Seg_" + bone
			seg.colossus = self
			seg.bone_name = bone
			seg.bone_idx = _bone[bone]
			add_child(seg)
			segments.append(seg)
			_seg_by_bone[bone] = seg
		var col: CollisionShape3D = ClimbPatch.new() if part[1] == Kind.FUR else CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = part[2]
		col.shape = shape
		col.position = part[3]
		seg.add_child(col)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[2]
		mesh.mesh = bm
		mesh.position = part[3]
		mesh.material_override = mats[part[1]]
		mesh.set_meta(&"kind", 0 if part[1] == Kind.FUR else 1)
		mesh.set_meta(&"part_size", part[2])
		seg.add_child(mesh)


## Places the bird in the air at ``pos`` flying towards ``p_yaw``.
func teleport(pos: Vector3, p_yaw: float) -> void:
	yaw = p_yaw
	pitch = 0.0
	roll = 0.0
	speed = cruise_speed
	global_transform = Transform3D(_flight_basis(), pos)
	_pose_bones(0.0)
	_sync_segments()
	_sync_segments()
	for s in segments:
		s.reset_physics_interpolation()


func _flight_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)


func _pose_bones(_delta: float) -> void:
	var a := flap * _flap_w
	skeleton.set_bone_pose(_bone[&"wing_l_in"], Transform3D(Basis(Vector3.BACK, -a), BONES[4][2]))
	skeleton.set_bone_pose(_bone[&"wing_l_out"], Transform3D(Basis(Vector3.BACK, -a * 0.6), BONES[5][2]))
	skeleton.set_bone_pose(_bone[&"wing_r_in"], Transform3D(Basis(Vector3.BACK, a), BONES[6][2]))
	skeleton.set_bone_pose(_bone[&"wing_r_out"], Transform3D(Basis(Vector3.BACK, a * 0.6), BONES[7][2]))
	skeleton.set_bone_pose(_bone[&"tail"], Transform3D(Basis(Vector3.RIGHT, -pitch * 0.5), BONES[3][2]))


# --- encounter API --------------------------------------------------------------------

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_start_xf = xf
	_set_encounter(Encounter.DORMANT)
	for wp in weak_points:
		wp.reset()
	swoop = Swoop.NONE
	swoop_t = 0.0
	_swoop_cooldown_left = 0.0
	_flinch_t = 999.0
	_shake_cooldown_left = 0.0
	_time_on_body.clear()
	_off_body_time.clear()
	intent = ColossusIntent.make(ColossusIntent.IDLE)
	teleport(_start_xf.origin, _start_xf.basis.get_euler().y)
	_reset_stats()


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
	var n := 0
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			n += 1
	return n


func get_focus_point() -> Vector3:
	return global_position


func get_danger_zones() -> Array:
	return []


func swoop_name() -> String:
	return Swoop.keys()[swoop]


func _set_encounter(e: Encounter) -> void:
	if e == encounter:
		return
	encounter = e
	encounter_changed.emit(e)
	if e == Encounter.DEFEATED:
		defeated.emit()


# --- brain, rules ---------------------------------------------------------------------

func observe() -> ColossusObservation:
	var obs := super()
	obs.facts["swoop_ready"] = _swoop_cooldown_left <= 0.0 and swoop == Swoop.NONE
	return obs


func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if encounter == Encounter.DEFEATED:
		return ColossusIntent.make(ColossusIntent.IDLE)
	if encounter == Encounter.DORMANT:
		for info in obs.players:
			if Vector2(info.position.x - arena_center.x, info.position.z - arena_center.z).length() < notice_radius or info.on_body:
				_set_encounter(Encounter.COMBAT)
		if encounter == Encounter.DORMANT:
			return ColossusIntent.make(CIRCLE)
	# A swoop under way is flown to its end.
	if swoop != Swoop.NONE:
		return intent
	return super(obs)


func _shake_kinds() -> Array[StringName]:
	return [SHAKE_BODY]


func _rider_time() -> float:
	var on := 0.0
	for p in get_tree().get_nodes_in_group(&"players"):
		on = maxf(on, _time_on_body.get(p.get_instance_id(), 0.0))
	return on


func _rules_block() -> Array[StringName]:
	var out: Array[StringName] = []
	var on := _rider_time()
	if on > 0.0 or _swoop_cooldown_left > 0.0:
		out.append(SWOOP)
	if on < 3.0 or _flinch_t < 4.0 or not _over_water():
		out.append(SHAKE_BODY)
	return out


func _over_water() -> bool:
	return water_level > -999.0 and Vector2(global_position.x - arena_center.x, global_position.z - arena_center.z).length() < carry_radius + 15.0


# --- flight -------------------------------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	_swoop_cooldown_left = maxf(0.0, _swoop_cooldown_left - delta)
	_flinch_t += delta
	if encounter == Encounter.DEFEATED:
		_glide_down(delta)
		return
	var goal := _circle_point(circle_radius, circle_height, 0.45)
	var want := cruise_speed
	# Anyone on it: it keeps over the lake's middle (whoever falls, falls into the water).
	if _rider_time() > 0.0:
		goal = _circle_point(carry_radius, carry_height, 0.35)
	var beat := 0.35
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	match it.kind:
		SWOOP:
			var r := _update_swoop(it, delta)
			goal = r[0]
			want = r[1]
			beat = r[2]
		CARRY:
			goal = _circle_point(carry_radius, carry_height, 0.35)
			want = carry_speed
			beat = 0.0
		SHAKE_BODY:
			goal = _circle_point(carry_radius, carry_height, 0.35)
			want = carry_speed
			beat = 0.0
			_shake = clampf(it.strength, 0.4, 1.0)
	_fly(goal, want, delta)
	# Wing beats: strong when climbing or slow, none while gliding with a rider.
	var climbing := clampf(pitch / 0.4, 0.0, 1.0)
	var amp := maxf(beat, 0.4 * climbing) if it.kind != CARRY and it.kind != SHAKE_BODY else 0.0
	_flap_phase += delta * TAU * 1.2
	flap = lerpf(flap, 0.08 + amp * sin(_flap_phase), 1.0 - exp(-8.0 * delta))


func _circle_point(radius: float, height: float, lead: float) -> Vector3:
	var off := global_position - arena_center
	var a := atan2(off.z, off.x) + lead
	return arena_center + Vector3(cos(a) * radius, height, sin(a) * radius)


## One tick along the flight path: turn (limited) towards ``goal``, climb or dive
## (limited), speed up or slow down, bank into the turn (plus a roll when shaking).
func _fly(goal: Vector3, want_speed: float, delta: float) -> void:
	var to := goal - global_position
	var flat := Vector2(to.x, to.z).length()
	if flat > 0.5:
		var want_yaw := atan2(-to.x, -to.z)
		# Diving it turns sharper (wings half folded).
		var rate := turn_rate * (2.2 if swoop == Swoop.DIVE else 1.0)
		var turn := clampf(angle_difference(yaw, want_yaw), -rate * delta, rate * delta)
		yaw += turn
		_yaw_rate = turn / delta
	# With someone on it: a gentle glider (climbs, dives and banks shallow); only the
	# shake is meant to throw them off.
	var ridden := _rider_time() > 0.0
	var max_pitch := 0.18 if ridden else 0.5
	var want_pitch := clampf(atan2(to.y, maxf(flat, 1.0)), -0.65 if not ridden else -max_pitch, max_pitch)
	pitch = move_toward(pitch, want_pitch, pitch_rate * delta)
	speed = move_toward(speed, want_speed, (accel * 2.0 if want_speed < speed else accel) * delta)
	var max_bank := 0.3 if ridden else 0.6
	var bank := clampf(-_yaw_rate * speed * 0.09, -max_bank, max_bank) + _shake * 0.55 * sin(_time * TAU * 0.9)
	roll = lerpf(roll, bank, 1.0 - exp(-3.0 * delta))
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	var pos := global_position + dir * speed * delta
	# Never into the ground or the water.
	var floor_y := arena_center.y + 3.0
	if water_level > -999.0:
		floor_y = maxf(floor_y, water_level + 3.0)
	if swoop == Swoop.NONE or swoop == Swoop.CLIMB:
		pos.y = maxf(pos.y, floor_y)
	global_transform = Transform3D(_flight_basis(), pos)


## Telegraph (circling, screeching, banked towards the target) -> dive to the low point
## beside the target -> pass slowly with the wing over it -> climb away.
## Returns [goal, speed, wing beat].
func _update_swoop(it: ColossusIntent, delta: float) -> Array:
	if swoop == Swoop.NONE:
		swoop = Swoop.TELEGRAPH
		swoop_t = 0.0
		_swoop_target = it.target_player
		stats.swoops = int(stats.swoops) + 1
		Sfx.play(self, &"roar", global_position)
	swoop_t += delta
	var target: Node3D = _swoop_target if is_instance_valid(_swoop_target) else null
	match swoop:
		Swoop.TELEGRAPH:
			if _rider_time() > 0.0:
				# Someone got on before it dived: no swoop with a rider.
				swoop = Swoop.NONE
				_swoop_cooldown_left = swoop_cooldown
				_think_left = 0.0
				return [_circle_point(carry_radius, carry_height, 0.35), carry_speed, 0.0]
			if target:
				_aim_low_point(target)
			if swoop_t >= swoop_telegraph:
				swoop = Swoop.DIVE
				swoop_t = 0.0
			return [_circle_point(circle_radius, circle_height, 0.45), cruise_speed, 0.2]
		Swoop.DIVE:
			if target and swoop_t < 1.0:
				_aim_low_point(target)
			# Line up with the pass direction a little before the low point.
			var entry := low_point - _swoop_dir * 24.0 + Vector3.UP * 4.0
			var d := global_position.distance_to(low_point)
			var goal := entry if global_position.distance_to(entry) > 6.0 and d > 20.0 else low_point
			if d < 3.5 or (global_position - low_point).dot(_swoop_dir) > 0.0 and d < 12.0:
				swoop = Swoop.PASS
				swoop_t = 0.0
			elif swoop_t > swoop_dive_limit:
				# Could not line up (the target moved, a tight turn): pull up, try later.
				swoop = Swoop.CLIMB
				swoop_t = 0.0
				stats.swoops_aborted = int(stats.get("swoops_aborted", 0)) + 1
			return [goal, lerpf(pass_speed, swoop_speed, clampf((d - 6.0) / 24.0, 0.0, 1.0)), 0.0]
		Swoop.PASS:
			# Slow and level past the low point, the wing over the target.
			if swoop_t > 2.2:
				swoop = Swoop.CLIMB
				swoop_t = 0.0
				if _rider_time() > 0.0:
					# Someone caught on: no climb away, it glides up to its carrying circle.
					swoop = Swoop.NONE
					_swoop_cooldown_left = swoop_cooldown
					_think_left = 0.0
			return [low_point + _swoop_dir * 30.0, pass_speed, 0.0]
		Swoop.CLIMB:
			if swoop_t > 5.0 or global_position.y > arena_center.y + circle_height - 4.0:
				swoop = Swoop.NONE
				_swoop_cooldown_left = swoop_cooldown
				_think_left = 0.0
			# With someone on it a gentle climb (it wants them over the lake, not off).
			var up := 10.0 if _rider_time() > 0.0 else 30.0
			return [global_position + _swoop_dir * 40.0 + Vector3.UP * up, cruise_speed, 0.7]
	return [global_position, speed, 0.0]


## The low point: beside the target so the inner wing passes over its head, coming
## along the direction we are flying in now.
func _aim_low_point(target: Node3D) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 1.0:
		_swoop_dir = to.normalized()
	var side := _swoop_dir.cross(Vector3.UP).normalized()
	var feet := target.global_position.y - 0.9
	low_point = target.global_position + side * WING_REACH
	low_point.y = feet + 2.0 - WING_UNDER


func _glide_down(delta: float) -> void:
	var goal := arena_center + Vector3(0, 0, 0)
	if water_level > -999.0:
		goal.y = water_level + 1.0
	speed = move_toward(speed, 0.0 if global_position.distance_to(goal) < 4.0 else 6.0, 2.0 * delta)
	flap = lerpf(flap, 0.25, delta)
	roll = lerpf(roll, 0.0, delta)
	pitch = lerpf(pitch, 0.0, delta)
	var to := goal - global_position
	if to.length() > 0.5:
		yaw += clampf(angle_difference(yaw, atan2(-to.x, -to.z)), -turn_rate * delta, turn_rate * delta)
		var step := to.normalized() * minf(speed * delta, to.length())
		global_transform = Transform3D(_flight_basis(), global_position + step)


func _on_weak_point_struck(_damage: float, _left: float) -> void:
	stats.weak_point_hits = int(stats.weak_point_hits) + 1
	if encounter == Encounter.DORMANT:
		_set_encounter(Encounter.COMBAT)
	_flinch_t = 0.0
	_flinched(1.0)


func _on_weak_point_destroyed() -> void:
	if weak_points_left() == 0:
		_set_encounter(Encounter.DEFEATED)


func _reset_stats() -> void:
	stats = {"swoops": 0, "weak_point_hits": 0}


func debug_text() -> String:
	var wps := []
	for wp in weak_points:
		wps.append("%.0f" % wp.health)
	return "AVION %s  intent %s  swoop %s  speed %.1f  alt %.1f  weak points %s\n%s" % [encounter_name(), intent.kind, swoop_name(), speed, global_position.y - arena_center.y, ", ".join(wps), super()]
