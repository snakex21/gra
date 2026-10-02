class_name Phaedra
extends Quadratus
## Phaedra: the fourth boss. A long-necked four-legged colossus, timid and curious: it
## keeps its distance in the open and backs away from anyone who comes close, but it
## cannot resist looking for someone who hid. Its body is stone; only the top of it is
## fur: a cap on the head, a mane along the neck, the withers and the back.
##
## Loop: hide in a tunnel of the ruins. It walks to the mouth, lowers the neck and puts
## its head in (PEEK). Grab the fur cap on its head: startled, it lifts the head and the
## neck becomes a slope up to its back. Climb the mane: weak point in the middle of the
## neck, then on the withers. Both destroyed = defeated (it lies down).
##
##   PEEK: APPROACH (walk to the mouth, face it) -> LOWER -> HOLD -> RAISE -> cooldown
##
## The neck is a chain of three bones and the head; lowering it into a mouth is a small
## planar IK (CCD on the three neck joints) blended by the peek weight.
## Everything else (encounter, stomp, shake, fairness, weak points, defeat) is the shared
## quadruped boss behaviour (Quadratus' hooks).

enum Peek { NONE, APPROACH, LOWER, HOLD, RAISE }

const PEEK := &"peek"

## Bones (rest offsets). The neck bones point along their own -Z; the base pose raises
## the neck by NECK_RAISE (and levels the head), the peek lowers it.
const PH_BONES := [
	[&"body", &"", Vector3(0, 6.5, 0)],
	[&"neck", &"body", Vector3(0, 0.9, -3.8)],
	[&"neck2", &"neck", Vector3(0, 0, -3.2)],
	[&"neck3", &"neck2", Vector3(0, 0, -3.2)],
	[&"head", &"neck3", Vector3(0, 0, -3.0)],
	[&"fl_up", &"body", Vector3(-1.9, -1.1, -3.4)],
	[&"fl_low", &"fl_up", Vector3(0, -3.0, 0)],
	[&"fl_foot", &"fl_low", Vector3(0, -2.8, 0)],
	[&"fr_up", &"body", Vector3(1.9, -1.1, -3.4)],
	[&"fr_low", &"fr_up", Vector3(0, -3.0, 0)],
	[&"fr_foot", &"fr_low", Vector3(0, -2.8, 0)],
	[&"rl_up", &"body", Vector3(-1.9, -1.1, 3.6)],
	[&"rl_low", &"rl_up", Vector3(0, -3.0, 0)],
	[&"rl_foot", &"rl_low", Vector3(0, -2.8, 0)],
	[&"rr_up", &"body", Vector3(1.9, -1.1, 3.6)],
	[&"rr_low", &"rr_up", Vector3(0, -3.0, 0)],
	[&"rr_foot", &"rr_low", Vector3(0, -2.8, 0)],
]
const PH_LEGS := [[&"fl_up", &"fl_low", &"fl_foot"], [&"fr_up", &"fr_low", &"fr_foot"], [&"rl_up", &"rl_low", &"rl_foot"], [&"rr_up", &"rr_low", &"rr_foot"]]
const NECK_BONES := [&"neck", &"neck2", &"neck3"]
const NECK_LENGTHS := [3.2, 3.2, 3.0]
const NECK_RAISE := 0.5

## Stone body and legs; fur only on top: back, withers, mane, cap on the head.
const PH_PARTS := [
	[&"body", Kind.STONE, Vector3(4.2, 2.8, 8.8), Vector3(0, 0, 0)],
	[&"body", Kind.FUR, Vector3(3.4, 0.5, 7.6), Vector3(0, 1.62, 0.4)],
	[&"body", Kind.FUR, Vector3(2.6, 1.4, 2.0), Vector3(0, 1.3, -3.9)],
	# Mane: a fur ridge a little wider than the stone core, one continuous strip from the
	# head cap down to the withers (each piece overlaps the next joint).
	[&"neck", Kind.STONE, Vector3(1.8, 1.5, 3.4), Vector3(0, 0, -1.6)],
	[&"neck", Kind.FUR, Vector3(1.9, 0.5, 3.8), Vector3(0, 0.95, -1.6)],
	[&"neck2", Kind.STONE, Vector3(1.6, 1.4, 3.4), Vector3(0, 0, -1.6)],
	[&"neck2", Kind.FUR, Vector3(1.7, 0.5, 3.8), Vector3(0, 0.9, -1.6)],
	[&"neck3", Kind.STONE, Vector3(1.5, 1.3, 3.2), Vector3(0, 0, -1.5)],
	[&"neck3", Kind.FUR, Vector3(1.6, 0.5, 3.6), Vector3(0, 0.85, -1.5)],
	[&"head", Kind.STONE, Vector3(1.9, 1.6, 2.8), Vector3(0, 0, -1.2)],
	[&"head", Kind.FUR, Vector3(2.0, 0.5, 3.4), Vector3(0, 0.95, -0.8)],
	[&"fl_up", Kind.STONE, Vector2(0.8, 3.2), Vector3(0, -1.4, 0)],
	[&"fr_up", Kind.STONE, Vector2(0.8, 3.2), Vector3(0, -1.4, 0)],
	[&"rl_up", Kind.STONE, Vector2(0.9, 3.2), Vector3(0, -1.4, 0)],
	[&"rr_up", Kind.STONE, Vector2(0.9, 3.2), Vector3(0, -1.4, 0)],
	[&"fl_low", Kind.STONE, Vector2(0.6, 3.0), Vector3(0, -1.4, 0)],
	[&"fr_low", Kind.STONE, Vector2(0.6, 3.0), Vector3(0, -1.4, 0)],
	[&"rl_low", Kind.STONE, Vector2(0.6, 3.0), Vector3(0, -1.4, 0)],
	[&"rr_low", Kind.STONE, Vector2(0.6, 3.0), Vector3(0, -1.4, 0)],
	[&"fl_foot", Kind.STONE, Vector3(1.4, 0.5, 1.7), Vector3(0, -0.25, -0.15)],
	[&"fr_foot", Kind.STONE, Vector3(1.4, 0.5, 1.7), Vector3(0, -0.25, -0.15)],
	[&"rl_foot", Kind.STONE, Vector3(1.4, 0.5, 1.7), Vector3(0, -0.25, -0.15)],
	[&"rr_foot", Kind.STONE, Vector3(1.4, 0.5, 1.7), Vector3(0, -0.25, -0.15)],
]
## Weak points: the upper neck (on the mane, just behind the head), then the withers.
const NECK_WP_LOCAL := Vector3(0, 1.11, -1.5)
const WITHERS_WP_LOCAL := Vector3(0, 2.02, -3.9)
## Where the head bone goes in a peek: in front of the mouth, at this height (the fur cap
## then sits at ~2.4 m: reachable from the tunnel floor).
const PEEK_HEAD_OUT := 1.3
const PEEK_HEAD_HEIGHT := 1.35

@export_group("Peek")
@export var peek_stand := 11.0
@export var peek_lower_time := 1.6
@export var peek_hold := 9.0
@export var peek_raise_time := 1.8
@export var peek_cooldown := 5.0
@export var peek_approach_max := 40.0
## Walking to a mouth it trots (lighter than Quadratus: quicker to speed up and stop).
@export var peek_speed := 4.0

## Hiding places (set by the arena): [{"aabb": AABB, "mouths": [[pos, outward], ...]}].
var tunnels: Array = []
var peek := Peek.NONE
var peek_t := 0.0
## 0 head up .. 1 head in the mouth.
var peek_w := 0.0
var peek_mouth := Vector3.ZERO
var peek_out := Vector3.FORWARD
var peeks := 0
var _peek_cooldown_left := 0.0
var _neck_ik := [NECK_RAISE, 0.0, 0.0]
var _neck_yaw := 0.0


func _init() -> void:
	body_height = 11.0
	walk_speed = 1.7
	turn_rate = 0.26
	shake_frequency = 1.0
	stomp_height = 2.6
	stomp_reach = 3.4
	shockwave_radius = 6.0
	brain_seed = 17
	notice_radius = 70.0


func _rig() -> Dictionary:
	return {"bones": PH_BONES, "legs": PH_LEGS, "upper": 3.0, "lower": 2.8, "ankle": 0.5, "body_above_hips": 1.1, "hip_height": 5.4}


func _parts() -> Array:
	return PH_PARTS


func _make_brain() -> ColossusBrain:
	return PhaedraBrain.new(brain_seed)


func _weak_point_specs() -> Array:
	return [[&"neck3", NECK_WP_LOCAL, weak_point_health, false], [&"body", WITHERS_WP_LOCAL, weak_point_health, false]]


func _target_legs() -> Array:
	return []


func _attack_cooldowns() -> Dictionary:
	return {STOMP: 5.0}


func _boss_label() -> String:
	return "PHAEDRA"


func _update_crown() -> void:
	pass


func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	peek = Peek.NONE
	peek_t = 0.0
	peek_w = 0.0
	peeks = 0
	_peek_cooldown_left = 0.0
	_neck_ik = [NECK_RAISE, 0.0, 0.0]
	_neck_yaw = 0.0
	super(xf, use_xf)


func region_of(player: Node3D) -> StringName:
	if not player.has_method(&"get_support_body"):
		return &""
	var support: Object = player.get_support_body()
	if not owns_body(support):
		return &""
	match (support as BodySegment).bone_name:
		&"body":
			return &"back"
		&"neck", &"neck2", &"neck3":
			return &"neck"
		&"head":
			return &"head"
	return &"leg"


## The tunnel (index) a player stands in, or -1.
func tunnel_of(p: Node3D) -> int:
	for i in tunnels.size():
		if (tunnels[i].aabb as AABB).grow(0.2).has_point(p.global_position):
			return i
	return -1


## The tunnel (index) whose mouth is at ``p``, or -1.
func tunnel_of_point(p: Vector3) -> int:
	for i in tunnels.size():
		for m in tunnels[i].mouths:
			if (m[0] as Vector3).distance_to(p) < 0.5:
				return i
	return -1


## Mouth of tunnel ``i`` nearer to us: [pos, outward].
func near_mouth(i: int) -> Array:
	var best: Array = []
	var best_d := INF
	for m in tunnels[i].mouths:
		var d := _flat((m[0] as Vector3) - global_position).length()
		if d < best_d:
			best_d = d
			best = m
	return best


func head_point() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"head"]).origin


func peek_name() -> String:
	return Peek.keys()[peek]


# --- decision ------------------------------------------------------------------------

func observe() -> ColossusObservation:
	var obs := super()
	obs.facts["peek"] = StringName(peek_name())
	for info in obs.players:
		if info.on_body or _dead(info.player):
			continue
		var t := tunnel_of(info.player)
		if t >= 0:
			obs.facts["player_tunnel"] = t
			obs.facts["peek_mouth"] = near_mouth(t)[0]
			break
	return obs


func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if debug_override == &"" and encounter == Encounter.COMBAT and peek != Peek.NONE:
		return intent
	var chosen := super(obs)
	if chosen.kind == PEEK and peek == Peek.NONE and encounter == Encounter.COMBAT:
		_start_peek(chosen.target_position)
	return chosen


func _rules_block() -> Array[StringName]:
	var out := super()
	var someone_on := false
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.has_method(&"get_support_body") and owns_body(p.get_support_body()):
			someone_on = true
	if someone_on or _peek_cooldown_left > 0.0 or tunnels.is_empty():
		out.append(PEEK)
	if peek != Peek.NONE:
		out.append_array([STOMP, HEAD_ATTACK, SHAKE_BODY, LURCH])
	return out


func _start_peek(mouth: Vector3) -> void:
	var best: Array = []
	var best_d := INF
	for t in tunnels:
		for m in t.mouths:
			var d := (m[0] as Vector3).distance_to(mouth)
			if d < best_d:
				best_d = d
				best = m
	if best.is_empty():
		return
	peek_mouth = best[0]
	peek_out = (best[1] as Vector3).normalized()
	_set_peek(Peek.APPROACH)


func _set_peek(p: Peek) -> void:
	peek = p
	peek_t = 0.0
	_think_left = 0.0
	if p == Peek.LOWER:
		peeks += 1
		stats.peeks = int(stats.get("peeks", 0)) + 1
	elif p == Peek.NONE:
		_peek_cooldown_left = peek_cooldown


func _stand_point() -> Vector3:
	return peek_mouth + peek_out * peek_stand


# --- per tick ------------------------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	_update_peek(delta)
	super(it, delta)


func _update_peek(delta: float) -> void:
	_peek_cooldown_left = maxf(0.0, _peek_cooldown_left - delta)
	if encounter != Encounter.COMBAT:
		if peek != Peek.NONE and encounter == Encounter.DEFEATED:
			peek = Peek.NONE
		peek_w = move_toward(peek_w, 0.0, delta / peek_raise_time)
		return
	if peek == Peek.NONE:
		peek_w = move_toward(peek_w, 0.0, delta / peek_raise_time)
		return
	peek_t += delta
	var on_head := false
	for p in get_tree().get_nodes_in_group(&"players"):
		if region_of(p) in [&"head", &"neck"]:
			on_head = true
	match peek:
		Peek.APPROACH:
			var hidden := false
			for p in get_tree().get_nodes_in_group(&"players"):
				hidden = hidden or tunnel_of(p) >= 0
			if not hidden or peek_t > peek_approach_max:
				_set_peek(Peek.NONE)
				return
			var to := _flat(_stand_point() - global_position)
			var facing := (-global_basis.z).signed_angle_to(-peek_out, Vector3.UP)
			if to.length() < 1.6 and absf(facing) < 0.1 and loco.speed < 0.3:
				_set_peek(Peek.LOWER)
		Peek.LOWER:
			peek_w = move_toward(peek_w, 1.0, delta / peek_lower_time)
			if on_head:
				_set_peek(Peek.RAISE)
			elif peek_w >= 1.0:
				_set_peek(Peek.HOLD)
		Peek.HOLD:
			peek_w = 1.0
			if on_head or peek_t >= peek_hold:
				# Startled (someone grabbed its head) or bored: the head comes up.
				_set_peek(Peek.RAISE)
		Peek.RAISE:
			peek_w = move_toward(peek_w, 0.0, delta / peek_raise_time)
			if peek_w <= 0.0:
				_set_peek(Peek.NONE)


func _adjust_movement(it: ColossusIntent, delta: float) -> void:
	super(it, delta)
	if intent.kind != LURCH:
		loco.max_accel = 0.9
		loco.max_decel = 1.6
		loco.max_jerk = 2.5
		loco.speed_gain = 2.0
	if encounter != Encounter.COMBAT or peek == Peek.NONE:
		return
	desired_speed = 0.0
	desired_turn = 0.0
	var face := (-global_basis.z).signed_angle_to(-peek_out, Vector3.UP)
	if peek == Peek.APPROACH:
		var to := _flat(_stand_point() - global_position)
		if to.length() > 1.2:
			var angle := (-global_basis.z).signed_angle_to(to.normalized(), Vector3.UP)
			desired_turn = clampf(angle * 1.2, -turn_rate, turn_rate)
			desired_speed = peek_speed * clampf(to.length() / 6.0, 0.2, 1.0) * clampf(1.1 - absf(angle), 0.15, 1.0)
		else:
			desired_turn = clampf(face * 1.2, -turn_rate * 0.6, turn_rate * 0.6)
	elif peek != Peek.RAISE:
		# Lowered: keep facing the mouth (small corrections only, no steps away).
		desired_turn = clampf(face * 0.8, -0.05, 0.05)
	# The front dips a little while the head is down.
	extra_pelvis_drop += 0.5 * peek_w


# --- poses ---------------------------------------------------------------------------

func _pose_overrides(delta: float) -> void:
	super(delta)
	var t0 := Perf.begin()
	var dw := _defeat_weight() if encounter == Encounter.DEFEATED else 0.0
	# Base: the neck raised, the head level; lying down when defeated.
	var base := [lerpf(NECK_RAISE, -0.25, dw), 0.0, 0.0]
	var w := peek_w
	if w > 0.0:
		_solve_neck(delta)
	for i in 3:
		var bone: StringName = NECK_BONES[i]
		var idx: int = _bone[bone]
		var pitch := lerpf(base[i], _neck_ik[i], w)
		# Only the base neck bone has a pose from before (look, roar, stagger); the others
		# are posed here alone, every tick from scratch.
		var own := skeleton.get_bone_pose_rotation(idx).slerp(Quaternion.IDENTITY, w) if i == 0 else Quaternion.IDENTITY
		var yaw := _neck_yaw * w if i == 0 else 0.0
		skeleton.set_bone_pose_rotation(idx, own * Quaternion.from_euler(Vector3(0, yaw, 0)) * Quaternion.from_euler(Vector3(pitch, 0, 0)))
	var neck_sum := 0.0
	for i in 3:
		neck_sum += lerpf(base[i], _neck_ik[i], w)
	# The head: level when up, nose slightly down into the mouth when peeking.
	var head_idx: int = _bone[&"head"]
	var head_own := skeleton.get_bone_pose_rotation(head_idx).slerp(Quaternion.IDENTITY, w)
	skeleton.set_bone_pose_rotation(head_idx, head_own * Quaternion.from_euler(Vector3(-neck_sum - 0.12 * w, 0, 0)))
	Perf.end(&"boss_pose", t0)


## CCD in the body's vertical plane: neck joint pitches that put the head bone at the
## peek target (in front of the mouth, at PEEK_HEAD_HEIGHT above the ground there).
func _solve_neck(_delta: float) -> void:
	var body_xf := skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"body"])
	var target_w := peek_mouth + peek_out * PEEK_HEAD_OUT
	target_w.y = _ground_under(target_w).y + PEEK_HEAD_HEIGHT
	var t := body_xf.affine_inverse() * target_w
	var base: Vector3 = PH_BONES[1][2]
	# Planar target: forward distance (along -Z, including any sideways offset) and height.
	var tgt := Vector2(-Vector2(t.x - base.x, t.z - base.z).length(), t.y - base.y)
	# Sideways: the neck base turns towards the target (the body only roughly faces it).
	_neck_yaw = clampf(atan2(-(t.x - base.x), -(t.z - base.z)), -0.5, 0.5)
	var a: Array = _neck_ik.duplicate()
	for it in 10:
		for j in range(2, -1, -1):
			var pts := _chain_points(a)
			var jp: Vector2 = pts[j]
			var ep: Vector2 = pts[3]
			var ang := (ep - jp).angle_to(tgt - jp)
			# In (z, y) with forward = -z: a positive pitch rotates towards +y.
			a[j] = clampf(a[j] - ang, -1.3 if j == 0 else -0.7, 0.7 if j == 0 else 0.4)
	_neck_ik = a


## Joint positions (z, y) in the body plane for neck pitches ``a`` (relative angles).
func _chain_points(a: Array) -> Array:
	var pts := [Vector2.ZERO]
	var phi := 0.0
	var p := Vector2.ZERO
	for i in 3:
		phi += a[i]
		p += Vector2(-cos(phi), sin(phi)) * NECK_LENGTHS[i]
		pts.append(p)
	return pts


func debug_text() -> String:
	return super() + "\npeek %s (%.1fs) w %.2f  mouth %s  peeks %d  cooldown %.1fs" % [peek_name(), peek_t, peek_w, str(peek_mouth.snapped(Vector3.ONE * 0.1)), peeks, _peek_cooldown_left]


func _draw_debug_extra(d: QuadrupedDebugDraw) -> void:
	super(d)
	if peek != Peek.NONE:
		d.cross(peek_mouth, 1.0, Color.MAGENTA)
		d.cross(_stand_point(), 1.0, Color.MAGENTA)
		d.line(head_point(), peek_mouth, Color.MAGENTA)
