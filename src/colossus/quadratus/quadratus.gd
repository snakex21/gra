class_name Quadratus
extends GreyboxQuadruped
## Quadratus: the second boss, a huge four-legged colossus. Not "Valus on four legs":
## its body is out of reach while it stands, so the fight is about bringing it down.
##
##   observe -> QuadratusBrain.decide -> FairnessRules filter -> intent
##   -> attacks / reactions + movement -> four-leg locomotion (gait, tilt, support) / IK
##
## Loop: keep moving between and around its legs, wait until a hind hoof lifts (its
## glowing sole tips backwards in every step), shoot it from behind. The hit leg loses
## its support (LegState.support -> 0): the step planner stops using it, the other three
## carry the weight, the body pitches and rolls down onto that corner and the thigh fur
## comes within reach. Climb the thigh, the flank, onto the back: weak point on the rump,
## then along the back and the neck to the crown. Both destroyed = defeated.
##
## Encounter: DORMANT -> NOTICE -> ENGAGED -> COMBAT -> DEFEATED (it lies down).
## Attacks: STOMP (front hoof) and HEAD_ATTACK (rear up, swing the head down).
## On the body: SHAKE_BODY (roll and buck of the torso, braced first) and, after a weak
## point hit, a stagger. Everything under the FairnessRules (telegraphs, recoveries,
## cooldowns, shake limits, no shaking while it kneels).

signal encounter_changed(state: Encounter)
signal attack_started(attack: ColossusAttack)
signal attack_phase_changed(attack: ColossusAttack)
signal player_hit(player: Node3D, attack_kind: StringName, damage: float)
signal foot_hit(leg: int)
signal buckle_changed(phase: Buckle)

enum Encounter { DORMANT, NOTICE, ENGAGED, COMBAT, DEFEATED }
## Reaction of a leg hit by an arrow: the knee gives (REACT), the body rests on three legs
## (KNEEL), then the leg pushes up again (RISE).
enum Buckle { NONE, REACT, KNEEL, RISE }

const OBSERVE := &"observe"
const APPROACH := &"approach"
const TURN := &"turn"
const STOMP := &"stomp"
const HEAD_ATTACK := &"head_attack"
const REACT_FOOT := &"react_to_foot_hit"
const LOWER_BODY := &"lower_body"
const RECOVER := &"recover"
const SHAKE_BODY := &"shake_body"

## Bones (rest offsets, unrotated). Forward -Z, left -X. The body bone sits above the hip
## centre; the legs hang from the body, so a tilted body tilts every hip with it.
const BONES := [
	[&"body", &"", Vector3(0, 8.6, 0)],
	[&"neck", &"body", Vector3(0, 0.6, -6.2)],
	[&"head", &"neck", Vector3(0, 0.8, -3.0)],
	[&"fl_up", &"body", Vector3(-2.7, -1.4, -5.0)],
	[&"fl_low", &"fl_up", Vector3(0, -4.0, 0)],
	[&"fl_foot", &"fl_low", Vector3(0, -3.6, 0)],
	[&"fr_up", &"body", Vector3(2.7, -1.4, -5.0)],
	[&"fr_low", &"fr_up", Vector3(0, -4.0, 0)],
	[&"fr_foot", &"fr_low", Vector3(0, -3.6, 0)],
	[&"rl_up", &"body", Vector3(-2.7, -1.4, 5.0)],
	[&"rl_low", &"rl_up", Vector3(0, -4.0, 0)],
	[&"rl_foot", &"rl_low", Vector3(0, -3.6, 0)],
	[&"rr_up", &"body", Vector3(2.7, -1.4, 5.0)],
	[&"rr_low", &"rr_up", Vector3(0, -4.0, 0)],
	[&"rr_foot", &"rr_low", Vector3(0, -3.6, 0)],
]
const LEGS := [[&"fl_up", &"fl_low", &"fl_foot"], [&"fr_up", &"fr_low", &"fr_foot"], [&"rl_up", &"rl_low", &"rl_foot"], [&"rr_up", &"rr_low", &"rr_foot"]]

## Body: one long fur torso (walkable top), a stone saddle on the back (rest), armour
## over the shoulders' flanks, fur only on the upper part of the thighs (out of reach
## while the legs stand), stone shins and hooves, a fur neck and a fur cap on the head.
const PARTS := [
	[&"body", Kind.FUR, Vector3(6.4, 4.4, 7.0), Vector3(0, 0, -3.0)],
	[&"body", Kind.FUR, Vector3(6.0, 4.0, 6.4), Vector3(0, -0.1, 3.4)],
	[&"body", Kind.STONE, Vector3(3.6, 0.5, 3.4), Vector3(0, 2.45, -1.0), &"rest"],
	# Haunches: fur flush with the outside of the thighs, from the hip up to the back (the
	# way from a lowered thigh onto the rump, no overhang under the belly).
	[&"body", Kind.FUR, Vector3(0.9, 4.0, 3.4), Vector3(-3.4, -0.1, 4.8)],
	[&"body", Kind.FUR, Vector3(0.9, 4.0, 3.4), Vector3(3.4, -0.1, 4.8)],
	[&"body", Kind.ARMOR, Vector3(0.5, 3.4, 4.8), Vector3(-3.42, -0.2, -3.8)],
	[&"body", Kind.ARMOR, Vector3(0.5, 3.4, 4.8), Vector3(3.42, -0.2, -3.8)],
	[&"neck", Kind.FUR, Vector3(2.6, 2.6, 3.6), Vector3(0, 0.3, -1.2)],
	[&"head", Kind.STONE, Vector3(2.6, 2.2, 3.0), Vector3(0, 0.2, -0.9)],
	[&"head", Kind.FUR, Vector3(2.7, 0.5, 2.6), Vector3(0, 1.5, -0.6)],
	[&"fl_up", Kind.FUR, Vector2(1.05, 3.0), Vector3(0, -1.1, 0)],
	[&"fr_up", Kind.FUR, Vector2(1.05, 3.0), Vector3(0, -1.1, 0)],
	[&"rl_up", Kind.FUR, Vector2(1.15, 3.2), Vector3(0, -1.2, 0)],
	[&"rr_up", Kind.FUR, Vector2(1.15, 3.2), Vector3(0, -1.2, 0)],
	[&"fl_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"fr_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"rl_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"rr_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"fl_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"fr_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"rl_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"rr_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
]
## Weak points: on the rump (body bone space) and the crown (head bone space).
const RUMP_LOCAL := Vector3(0, 1.92, 5.0)
const CROWN_LOCAL := Vector3(0, 1.77, -0.5)
## Glowing sole of each hind hoof (foot bone space; the sole faces down).
const SOLE_LOCAL := Vector3(0, -0.62, -0.2)
## Legs whose soles are arrow targets.
const TARGET_LEGS := [2, 3]
## The intended climb route (debug overlay): [bone, bone-space point].
const ROUTE := [
	[&"rl_up", Vector3(-1.15, -2.4, 0)], [&"rl_up", Vector3(-1.15, -0.6, 0)],
	[&"body", Vector3(-3.85, -1.0, 4.8)], [&"body", Vector3(-3.85, 1.6, 4.8)],
	[&"body", Vector3(-2.6, 1.9, 4.8)], [&"body", Vector3(0, 1.92, 5.0)],
	[&"body", Vector3(0, 2.7, -1.0)], [&"body", Vector3(0, 2.2, -5.8)],
	[&"neck", Vector3(0, 1.6, -1.2)], [&"head", Vector3(0, 1.75, -0.5)],
]

@export_group("Encounter")
@export var notice_radius := 45.0
@export var notice_time := 1.4
@export var engage_time := 1.2
@export_group("Attacks")
@export var stomp_telegraph := 1.0
@export var stomp_active := 0.3
@export var stomp_recovery := 1.8
@export var stomp_height := 3.6
@export var stomp_reach := 4.0
@export var stomp_damage := 60.0
@export var shockwave_radius := 7.0
@export var shockwave_damage := 24.0
@export var head_telegraph := 1.1
@export var head_active := 0.45
@export var head_recovery := 1.5
@export var head_damage := 40.0
@export var shake_telegraph := 0.7
@export var recover_time := 1.6
@export_group("Foot hit")
## Knee gives (support 1 -> 0) over this long once the hoof is down...
@export var buckle_time := 0.9
## ...the hit is a reaction for this long (no decisions)...
@export var react_time := 1.4
## ...then it rests on three legs (the climb window)...
@export var kneel_time := 11.0
## ...and pushes itself up again.
@export var rise_time := 2.6
## No new foot hit counts until this long after rising.
@export var buckle_cooldown := 4.0
## A sole must be lifted this high to be hit.
@export var sole_min_lift := 0.25
@export var weak_point_health := 80.0

var encounter := Encounter.DORMANT
var encounter_time := 0.0
var rules := FairnessRules.new()
var attack: ColossusAttack
var last_attack: ColossusAttack
var rump: WeakPoint
var crown: WeakPoint
var weak_points: Array[WeakPoint] = []
var arrow_targets: Array[ArrowTarget] = []
var hit_volumes := {}
var stats := {}
var brain_seed := 11
var effects_enabled := true
var buckle := Buckle.NONE
var buckle_leg := -1
var buckle_t := 0.0

var _stomp := LimbStomp.new()
var _stomp_leg := -1
var _head_w := 0.0
var _stagger_t := -1.0
var _stagger := 0.0
var _stagger_phase := 0.0
var _roar_w := 0.0
var _dormant_w := 1.0
var _defeat_t := 0.0
var _brace_w := 0.0
var _react_w := 0.0
var _buckle_cooldown_left := 0.0
var _last_touchdown_seen := -999.0
var _start_xf := Transform3D.IDENTITY
var _attack_intent: ColossusIntent
var _down_since := {}
var _seg_by_bone := {}


func _init() -> void:
	body_height = 13.0
	walk_speed = 1.3
	turn_rate = 0.2
	shake_frequency = 0.8


func _rig() -> Dictionary:
	return {"bones": BONES, "legs": LEGS, "upper": 4.0, "lower": 3.6, "ankle": 0.6, "body_above_hips": 1.4, "hip_height": 7.2}


func _parts() -> Array:
	return PARTS


func _ready() -> void:
	brain = QuadratusBrain.new(brain_seed)
	super()
	add_to_group(&"danger_sources")
	loco.max_body_tilt = 0.4
	loco.buckle_reach = 0.38
	for s in segments:
		_seg_by_bone[s.bone_name] = s
	rump = WeakPoint.create(_seg_by_bone[&"body"], RUMP_LOCAL, weak_point_health)
	crown = WeakPoint.create(_seg_by_bone[&"head"], CROWN_LOCAL, weak_point_health)
	weak_points = [rump, crown]
	for wp in weak_points:
		wp.struck.connect(_on_weak_point_struck.bind(wp))
		wp.destroyed.connect(_on_weak_point_destroyed)
	for i in TARGET_LEGS:
		var t := ArrowTarget.create(_seg_by_bone[leg_bones[i][2]], SOLE_LOCAL, Vector3.DOWN, 0.8, i)
		t.max_incidence_deg = 80.0
		t.hit.connect(_on_sole_hit)
		arrow_targets.append(t)
	_stomp.height = stomp_height
	rules.cooldowns = {STOMP: 6.0, HEAD_ATTACK: 6.0}
	_build_hit_volumes()
	_start_xf = global_transform
	_reset_stats()


# --- encounter API ------------------------------------------------------------------

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_start_xf = xf
	_end_attack(false)
	for leg in loco.legs:
		leg.scripted = false
		leg.support = 1.0
	teleport(_start_xf.origin, _start_xf.basis.get_euler().y)
	brain = QuadratusBrain.new(brain_seed)
	rules.reset()
	for wp in weak_points:
		wp.reset()
	intent = ColossusIntent.make(ColossusIntent.IDLE)
	_intent_time = 0.0
	_shake_cooldown_left = 0.0
	_think_left = 0.0
	_time_on_body.clear()
	_off_body_time.clear()
	_down_since.clear()
	_shake = 0.0
	_target_shake = 0.0
	_head_w = 0.0
	_stagger_t = -1.0
	_stagger = 0.0
	_roar_w = 0.0
	_dormant_w = 1.0
	_defeat_t = 0.0
	_brace_w = 0.0
	_react_w = 0.0
	_buckle_cooldown_left = 0.0
	buckle = Buckle.NONE
	buckle_leg = -1
	buckle_t = 0.0
	extra_pelvis_drop = 0.0
	extra_pitch = 0.0
	extra_roll = 0.0
	_set_encounter(Encounter.DORMANT)
	_reset_stats()


func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED


func encounter_name() -> String:
	return Encounter.keys()[encounter]


func buckle_name() -> String:
	return Buckle.keys()[buckle]


## Movement state (debug / tests): IDLE, WALK, TURN, REPOSITION, ATTACK, STAGGER,
## KNEEL (lowered body), RECOVER (rising / recovering).
func move_state() -> StringName:
	if encounter == Encounter.DEFEATED or buckle == Buckle.KNEEL or buckle == Buckle.REACT:
		return &"KNEEL"
	if buckle == Buckle.RISE or intent.kind == RECOVER:
		return &"RECOVER"
	if attack != null and not attack.is_done():
		return &"ATTACK"
	if _stagger > 0.05 or _shake > 0.05:
		return &"STAGGER"
	if intent.kind == ColossusIntent.REPOSITION:
		return &"REPOSITION"
	if loco.speed > 0.15:
		return &"WALK"
	if absf(loco.yaw_rate) > 0.02:
		return &"TURN"
	return &"IDLE"


func region_of(player: Node3D) -> StringName:
	if not player.has_method(&"get_support_body"):
		return &""
	var support: Object = player.get_support_body()
	if not owns_body(support):
		return &""
	var seg := support as BodySegment
	match seg.bone_name:
		&"body":
			var local := seg.target_transform.affine_inverse() * player.global_position
			return &"rump" if local.z > 1.0 else &"back"
		&"neck":
			return &"neck"
		&"head":
			return &"head"
	var b := String(seg.bone_name)
	if b.ends_with("_up"):
		return &"thigh"
	if b.ends_with("_low"):
		return &"shin"
	return &"hoof"


func get_danger_zones() -> Array:
	var out := []
	if attack == null or attack.is_done() or encounter == Encounter.DEFEATED:
		return out
	match attack.kind:
		STOMP:
			if attack.phase == ColossusAttack.Phase.PREPARE and _stomp_leg >= 0:
				out.append([_stomp_goal(attack.target_point, loco.legs[_stomp_leg]), shockwave_radius, attack.telegraph_time + 0.2])
			elif attack.phase == ColossusAttack.Phase.TELEGRAPH or attack.phase == ColossusAttack.Phase.ACTIVE:
				out.append([_stomp.slam_point, shockwave_radius, attack.time_left()])
		HEAD_ATTACK:
			if attack.phase == ColossusAttack.Phase.TELEGRAPH or attack.phase == ColossusAttack.Phase.ACTIVE:
				out.append([global_position - global_basis.z * 13.0, 6.0, attack.time_left()])
	return out


## Is the hoof of leg ``i`` up with its sole showing (arrow can count)?
func sole_exposed(i: int) -> bool:
	var leg := loco.legs[i]
	if leg.phase != LegState.Phase.SWING or leg.scripted:
		return false
	return sole_world(i).y - _ground_under(sole_world(i)).y > sole_min_lift


func weak_points_left() -> int:
	var n := 0
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			n += 1
	return n


# --- observation / decision ---------------------------------------------------------

func observe() -> ColossusObservation:
	var obs := super()
	obs.encounter = StringName(encounter_name())
	obs.attack_running = attack != null and not attack.is_done()
	obs.weak_point_open = weak_points_left() > 0
	obs.weak_point_progress = 1.0 - float(weak_points_left()) / weak_points.size()
	obs.facts = {"buckle": StringName(buckle_name()), "buckle_t": buckle_t, "move_state": move_state()}
	var inv := global_transform.affine_inverse()
	for info in obs.players:
		var pl := info.player
		info.region = region_of(pl)
		info.near_weakpoint = false
		for wp in weak_points:
			if wp.state == WeakPoint.State.OPEN and pl.global_position.distance_to(wp.world_point()) < 4.0:
				info.near_weakpoint = true
		var local := inv * pl.global_position
		info.bearing = atan2(-local.x, -local.z)
		info.riding = pl.has_method(&"is_riding") and pl.is_riding()
		info.stomp_foot = -1
		info.opportunities.clear()
		if info.on_body or _dead(pl):
			continue
		var best := 99.0
		for i in 2:
			var foot := loco.legs[i].plant_pos
			var d := Vector2(pl.global_position.x - foot.x, pl.global_position.z - foot.z).length()
			if d < 6.5 and absf(pl.global_position.y - foot.y) < 2.5 and d < best:
				best = d
				info.stomp_foot = i
		if info.stomp_foot >= 0:
			info.opportunities.append(STOMP)
		# Head: in front of the chest, along the head's swing.
		if local.z < -7.0 and local.z > -17.0 and absf(local.x) < 5.0 and pl.global_position.y - global_position.y < 3.0:
			info.opportunities.append(HEAD_ATTACK)
	return obs


func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if debug_override != &"":
		return super(obs)
	var target := _focus_player(obs)
	match encounter:
		Encounter.DORMANT, Encounter.DEFEATED:
			return ColossusIntent.make(ColossusIntent.IDLE)
		Encounter.NOTICE, Encounter.ENGAGED:
			var o := ColossusIntent.make(OBSERVE)
			o.target_player = target
			return o
	if attack != null and not attack.is_done():
		return intent
	if intent.kind == RECOVER and _intent_time < recover_time and buckle == Buckle.NONE:
		return intent
	var chosen := brain.decide(obs)
	if chosen == null or chosen.kind in obs.blocked_intents:
		chosen = ColossusIntent.make(OBSERVE)
		chosen.target_player = target
	return chosen


func _shake_kinds() -> Array[StringName]:
	return [SHAKE_BODY]


func _rules_block() -> Array[StringName]:
	var out := rules.blocked(_time)
	if ColossusIntent.SHAKE_PLAYER in out:
		out.append(SHAKE_BODY)
	if rules.reposition_expired(_time):
		out.append(ColossusIntent.REPOSITION)
	if buckle != Buckle.NONE:
		# Down on one knee: no attacks, no walking and no shaking (the climb window).
		out.append_array([STOMP, HEAD_ATTACK, SHAKE_BODY, APPROACH, TURN, ColossusIntent.REPOSITION])
	else:
		out.append_array([REACT_FOOT, LOWER_BODY])
	return out


func _focus_player(obs: ColossusObservation) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for info in obs.players:
		if _dead(info.player):
			continue
		var d := info.distance - (100.0 if info.on_body else 0.0)
		if d < best_d:
			best_d = d
			best = info.player
	return best


# --- per tick -----------------------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	var tc := Perf.begin()
	_update_encounter(delta)
	_update_buckle(delta)
	_update_attack(it, delta)
	_update_targets()
	rules.on_reposition(it.kind == ColossusIntent.REPOSITION and encounter == Encounter.COMBAT, _time)
	var effective := _effective_intent(it)
	Perf.end(&"boss_combat", tc)
	super(effective, delta)


func _effective_intent(it: ColossusIntent) -> ColossusIntent:
	var e := ColossusIntent.make(ColossusIntent.IDLE)
	e.target_player = it.target_player
	if encounter == Encounter.DORMANT or encounter == Encounter.DEFEATED:
		e.target_player = null
		return e
	if buckle != Buckle.NONE:
		return e
	match it.kind:
		OBSERVE, TURN:
			if is_instance_valid(it.target_player):
				e = ColossusIntent.make(ColossusIntent.FOCUS_PLAYER)
				e.target_player = it.target_player
		APPROACH:
			if is_instance_valid(it.target_player):
				e = ColossusIntent.make(ColossusIntent.REPOSITION)
				e.target_player = it.target_player
				e.target_position = it.target_player.global_position
		ColossusIntent.REPOSITION:
			e = it
		SHAKE_BODY:
			if _intent_time >= shake_telegraph:
				e = it
	return e


func _adjust_movement(it: ColossusIntent, delta: float) -> void:
	var bracing := it.kind == SHAKE_BODY and _intent_time < shake_telegraph and encounter == Encounter.COMBAT
	_brace_w = move_toward(_brace_w, 1.0 if bracing else 0.0, delta / 0.3)
	if bracing:
		loco.bracing = true
	var attacking := attack != null and not attack.is_done()
	var still := attacking or buckle != Buckle.NONE or encounter == Encounter.DEFEATED or encounter == Encounter.DORMANT or it.kind == RECOVER
	# Down on a knee it never walks, not even under a debug driver.
	if (still and debug_override != &"manual") or buckle != Buckle.NONE:
		desired_speed = 0.0
		desired_turn = 0.0
	if it.kind == TURN and not still:
		# Turning to face someone behind: a slow walk round in an arc, never a spin on
		# the spot like an object.
		desired_speed = walk_speed * 0.35
	if it.kind == APPROACH and is_instance_valid(it.target_player):
		var d := _flat(it.target_player.global_position - global_position).length()
		desired_speed *= clampf((d - 11.0) / 6.0, 0.0, 1.0)
	var drop := 0.3 * _brace_w
	if encounter == Encounter.DEFEATED:
		drop += 1.2 * _defeat_weight()
	extra_pelvis_drop = drop
	if attacking and attack.kind == STOMP and _stomp.update(attack, loco.time):
		_on_stomp_impact()


func _update_encounter(delta: float) -> void:
	encounter_time += delta
	_buckle_cooldown_left = maxf(0.0, _buckle_cooldown_left - delta)
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as PlayerCharacter
		if pc and not pc.dead and (pc.balance.state == Balance.State.FALLEN or pc.state == PlayerCharacter.State.AIR):
			rules.on_player_down(_time)
			_down_since[pc.get_instance_id()] = _time
	match encounter:
		Encounter.DORMANT:
			_dormant_w = move_toward(_dormant_w, 1.0, delta)
			for p in get_tree().get_nodes_in_group(&"players"):
				var pl := p as Node3D
				var d := Vector2(pl.global_position.x - global_position.x, pl.global_position.z - global_position.z).length()
				var on_us: bool = pl.has_method(&"get_support_body") and owns_body(pl.get_support_body())
				if (d < notice_radius or on_us) and not _dead(pl):
					_set_encounter(Encounter.NOTICE)
					break
		Encounter.NOTICE:
			_dormant_w = move_toward(_dormant_w, 0.0, delta / notice_time)
			if encounter_time >= notice_time:
				_set_encounter(Encounter.ENGAGED)
		Encounter.ENGAGED:
			_dormant_w = move_toward(_dormant_w, 0.0, delta)
			if encounter_time >= engage_time:
				_set_encounter(Encounter.COMBAT)
		Encounter.COMBAT:
			_dormant_w = move_toward(_dormant_w, 0.0, delta)
		Encounter.DEFEATED:
			_defeat_t += delta
			for leg in loco.legs:
				leg.support = move_toward(leg.support, 0.0, delta / 5.0)
	_roar_w = move_toward(_roar_w, 1.0 if encounter == Encounter.ENGAGED else 0.0, delta / 0.5)
	if _stagger_t >= 0.0:
		_stagger_t += delta
		if _stagger_t >= recover_time:
			_stagger_t = -1.0
	_stagger = pow(sin(PI * _stagger_t / recover_time), 2.0) if _stagger_t >= 0.0 else 0.0
	_stagger_phase = maxf(_stagger_t, 0.0) * 5.0


func _set_encounter(e: Encounter) -> void:
	if e == encounter and encounter_time > 0.0:
		return
	encounter = e
	encounter_time = 0.0
	_think_left = 0.0
	if e == Encounter.DEFEATED:
		_end_attack(false)
		_target_shake = 0.0
		_shake_cooldown_left = 999.0
		stats.defeated_at = _time
		if effects_enabled:
			Sfx.play(self, &"defeat", global_position + Vector3.UP * 8.0)
		defeated.emit()
	encounter_changed.emit(e)


# --- foot hit / buckle --------------------------------------------------------------

func _update_targets() -> void:
	var live := encounter != Encounter.DEFEATED and encounter != Encounter.DORMANT and buckle == Buckle.NONE and _buckle_cooldown_left <= 0.0
	for t in arrow_targets:
		t.enabled = live and sole_exposed(int(t.tag))


func _on_sole_hit(info: Dictionary) -> void:
	var i := int(info.tag)
	stats.foot_hits = int(stats.foot_hits) + 1
	if effects_enabled:
		Sfx.play(self, &"weak_hit", info.point)
		Fx.burst(get_parent(), info.point)
	if encounter != Encounter.COMBAT:
		_set_encounter(Encounter.COMBAT)
	_end_attack(false)
	buckle_leg = i
	_set_buckle(Buckle.REACT)
	var r := ColossusIntent.make(REACT_FOOT)
	_set_intent(r)
	foot_hit.emit(i)


func _set_buckle(b: Buckle) -> void:
	buckle = b
	buckle_t = 0.0
	_think_left = 0.0
	if b == Buckle.NONE:
		buckle_leg = -1
		_buckle_cooldown_left = buckle_cooldown
	else:
		stats.buckles = int(stats.buckles) + (1 if b == Buckle.REACT else 0)
	buckle_changed.emit(b)


func _update_buckle(delta: float) -> void:
	_react_w = move_toward(_react_w, 1.0 if buckle == Buckle.REACT else 0.0, delta / 0.3)
	if buckle == Buckle.NONE:
		if encounter != Encounter.DEFEATED:
			for leg in loco.legs:
				leg.support = move_toward(leg.support, 1.0, delta / rise_time)
		return
	buckle_t += delta
	var leg := loco.legs[buckle_leg]
	match buckle:
		Buckle.REACT, Buckle.KNEEL:
			# The knee gives once the hoof is down (a swinging leg lands first).
			if leg.is_planted():
				leg.support = move_toward(leg.support, 0.0, delta / buckle_time)
			if buckle == Buckle.REACT and buckle_t >= react_time:
				_set_buckle(Buckle.KNEEL)
			elif buckle == Buckle.KNEEL and buckle_t >= kneel_time:
				_set_buckle(Buckle.RISE)
		Buckle.RISE:
			leg.support = move_toward(leg.support, 1.0, delta / rise_time)
			if leg.support >= 1.0:
				_set_buckle(Buckle.NONE)
	if encounter == Encounter.DEFEATED:
		buckle = Buckle.NONE
		buckle_leg = -1


# --- attacks ------------------------------------------------------------------------

func _update_attack(it: ColossusIntent, delta: float) -> void:
	if (attack == null or attack.is_done()) and encounter == Encounter.COMBAT and buckle == Buckle.NONE:
		if (it.kind == STOMP or it.kind == HEAD_ATTACK) and it != _attack_intent:
			_attack_intent = it
			_start_attack(it)
	if attack == null or attack.is_done():
		return
	if attack.phase == ColossusAttack.Phase.PREPARE:
		attack.tick(delta)
		# Wait (briefly) for every hoof to stand before winding up.
		var planted := true
		for leg in loco.legs:
			planted = planted and leg.is_planted()
		if planted and loco.speed < 0.4:
			attack.begin_telegraph()
			_on_phase(attack)
		elif attack.phase_time > 3.0:
			_end_attack(false)
		return
	if attack.phase == ColossusAttack.Phase.TELEGRAPH and attack.kind == STOMP and is_instance_valid(attack.target_player):
		_stomp.track(_stomp_goal(attack.target_player.global_position, loco.legs[_stomp_leg]), attack, delta, _ground_under)
	if attack.tick(delta):
		_on_phase(attack)
		if attack.is_done():
			_end_attack(true)


func _start_attack(it: ColossusIntent) -> void:
	var a: ColossusAttack
	if it.kind == STOMP:
		a = ColossusAttack.make(STOMP, stomp_telegraph, stomp_active, stomp_recovery, true)
	else:
		a = ColossusAttack.make(HEAD_ATTACK, head_telegraph, head_active, head_recovery, true)
	rules.clamp_attack(a)
	a.target_player = it.target_player
	a.limb = 0
	if is_instance_valid(it.target_player):
		a.target_point = it.target_player.global_position
		if it.kind == STOMP:
			var d0 := _flat(a.target_point - loco.legs[0].plant_pos).length()
			var d1 := _flat(a.target_point - loco.legs[1].plant_pos).length()
			a.limb = 0 if d0 <= d1 else 1
	_stomp_leg = a.limb if it.kind == STOMP else -1
	attack = a
	last_attack = a
	rules.on_attack_start(a.kind, _time)
	stats.attacks[a.kind] = int(stats.attacks.get(a.kind, 0)) + 1
	attack_started.emit(a)


func _end_attack(finished: bool) -> void:
	if attack == null or attack.is_done():
		return
	if attack.kind == STOMP and _stomp.leg != null:
		_stomp.abort(_ground_under(_stomp.leg.foot_pos), loco.time)
	if finished or attack.phase != ColossusAttack.Phase.PREPARE:
		rules.on_attack_end(attack, _time)
	for h in hit_volumes.values():
		(h as HitVolume).active = false
	attack.phase = ColossusAttack.Phase.DONE
	_think_left = 0.0


func _on_phase(a: ColossusAttack) -> void:
	attack_phase_changed.emit(a)
	match a.kind:
		STOMP:
			if a.phase == ColossusAttack.Phase.TELEGRAPH:
				var leg := loco.legs[a.limb]
				_stomp.begin(leg, _stomp_goal(a.target_point, leg))
		HEAD_ATTACK:
			if a.phase == ColossusAttack.Phase.ACTIVE and effects_enabled:
				Sfx.play(self, &"swing", get_focus_point())


func _stomp_goal(p: Vector3, leg: LegState) -> Vector3:
	var off := _flat(p - leg.plant_pos)
	if off.length() > stomp_reach:
		off = off.normalized() * stomp_reach
	var goal := leg.plant_pos + off
	# Never under another hoof.
	for other in loco.legs:
		if other == leg:
			continue
		var away := _flat(goal - other.plant_pos)
		if away.length() < 2.8:
			goal = other.plant_pos + (away.normalized() if away.length() > 0.01 else global_basis.x) * 2.8
	return _ground_under(goal)


func _ground_under(p: Vector3) -> Vector3:
	var g := loco.probe_ground(get_world_3d().direct_space_state, p, global_position.y)
	return g[0]


func _on_stomp_impact() -> void:
	stats.stomp_impacts = int(stats.stomp_impacts) + 1
	if effects_enabled:
		Fx.dust(get_parent(), _stomp.slam_point, 2.4)
		Sfx.play(self, &"stomp", _stomp.slam_point)


func _post_sync(delta: float) -> void:
	super(delta)
	var th := Perf.begin()
	for h in hit_volumes.values():
		var hv := h as HitVolume
		var seg: BodySegment = _seg_by_bone.get(hv.bone)
		if seg:
			hv.update(seg.target_transform)
		hv.active = false
	if attack != null and not attack.is_done() and encounter != Encounter.DEFEATED:
		_test_hits()
	_footstep_effects()
	Perf.end(&"boss_hits", th)


func _test_hits() -> void:
	var volumes: Array[HitVolume] = []
	if attack.kind == STOMP and attack.phase == ColossusAttack.Phase.ACTIVE and not _stomp.impacted:
		volumes.append(hit_volumes[leg_bones[attack.limb][2]])
	elif attack.kind == HEAD_ATTACK and attack.phase == ColossusAttack.Phase.ACTIVE:
		volumes.append(hit_volumes[&"head"])
	for v in volumes:
		v.active = true
	var shock := attack.kind == STOMP and attack.phase == ColossusAttack.Phase.ACTIVE and _stomp.impacted
	if volumes.is_empty() and not shock:
		return
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as PlayerCharacter
		if pl == null or pl.dead or attack.hit_ids.has(pl.get_instance_id()):
			continue
		# Fairness: nobody is hit again while down / just after getting up.
		var down_at := float(_down_since.get(pl.get_instance_id(), -999.0))
		if _time - down_at < rules.downed_grace and (_time - attack.age < down_at + 1e-3 or pl.balance.state == Balance.State.FALLEN):
			continue
		if pl.has_method(&"get_support_body") and owns_body(pl.get_support_body()):
			continue
		Perf.count(&"boss_hit_tests")
		var center := pl.global_position
		if pl.is_riding() and is_instance_valid(pl.riding.horse):
			center = pl.riding.horse.global_position + Vector3.UP * 1.4
		for v in volumes:
			if v.touches(center, 0.55, 0.35 if not pl.is_riding() else 1.0):
				_hit_player(pl)
				break
		if shock and not attack.hit_ids.has(pl.get_instance_id()):
			var d := Vector2(pl.global_position.x - _stomp.slam_point.x, pl.global_position.z - _stomp.slam_point.z).length()
			if d < shockwave_radius and pl.global_position.y - _stomp.slam_point.y < 2.2:
				var close := 1.0 - d / shockwave_radius
				var out := _flat(pl.global_position - _stomp.slam_point).normalized()
				attack.hit_ids[pl.get_instance_id()] = true
				var dmg := shockwave_damage * (0.4 + 0.6 * close)
				if pl.apply_hit(dmg, out * (3.0 + 5.0 * close) + Vector3.UP * 3.0, 1.4 if close > 0.4 else 0.0, &"shockwave"):
					_count_hit(pl, &"shockwave", dmg)


func _hit_player(pl: PlayerCharacter) -> void:
	attack.hit_ids[pl.get_instance_id()] = true
	var dmg := stomp_damage if attack.kind == STOMP else head_damage
	var push := Vector3.ZERO
	var knock := 1.6
	if attack.kind == STOMP:
		push = _flat(pl.global_position - _stomp.slam_point).normalized() * 6.0 + Vector3.UP * 2.0
		knock = 2.2
	else:
		push = -global_basis.z * 8.0 + Vector3.UP * 4.0
	if pl.apply_hit(dmg, push, knock, attack.kind):
		_count_hit(pl, attack.kind, dmg)
	if effects_enabled:
		Sfx.play(self, &"impact", pl.global_position)


func _count_hit(pl: Node3D, kind: StringName, dmg: float) -> void:
	stats.hits_on_player = int(stats.hits_on_player) + 1
	player_hit.emit(pl, kind, dmg)


func _footstep_effects() -> void:
	if loco.last_touchdown != _last_touchdown_seen:
		_last_touchdown_seen = loco.last_touchdown
		stats.steps = int(stats.steps) + 1
		if effects_enabled and loco.last_step_leg >= 0:
			var p := loco.legs[loco.last_step_leg].plant_pos
			Fx.dust(get_parent(), p, 1.2)
			Sfx.play(self, &"step", p)


# --- weak points --------------------------------------------------------------------

func _on_weak_point_struck(damage: float, _left: float, wp: WeakPoint) -> void:
	stats.weak_point_hits = int(stats.weak_point_hits) + 1
	if effects_enabled:
		Sfx.play(self, &"weak_hit", wp.world_point())
		Fx.burst(get_parent(), wp.world_point())
	if encounter == Encounter.DORMANT or encounter == Encounter.NOTICE or encounter == Encounter.ENGAGED:
		_set_encounter(Encounter.COMBAT)
	_stagger_t = 0.0
	if encounter == Encounter.COMBAT and buckle == Buckle.NONE and weak_points_left() > 0:
		_set_intent(ColossusIntent.make(RECOVER))
	stats.last_hit_damage = damage


func _on_weak_point_destroyed() -> void:
	if weak_points_left() == 0:
		_set_encounter(Encounter.DEFEATED)


func _defeat_weight() -> float:
	var t := clampf(_defeat_t / 6.0, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# --- poses --------------------------------------------------------------------------

func _pose_overrides(delta: float) -> void:
	var t0 := Perf.begin()
	var heading := attack != null and attack.kind == HEAD_ATTACK and not attack.is_done() and attack.phase != ColossusAttack.Phase.PREPARE
	_head_w = move_toward(_head_w, 1.0 if heading else 0.0, delta / 0.3)
	var dw := _defeat_weight() if encounter == Encounter.DEFEATED else 0.0
	var stag := _stagger
	# Neck / head: lowered while dormant or defeated, raised for the roar, tossed in a
	# reaction or a stagger, reared and swung down in the head attack.
	var neck_pitch := -0.35 * _dormant_w + 0.3 * _roar_w - 0.5 * dw + 0.35 * _react_w + 0.08 * stag * sin(_stagger_phase)
	var head_pitch := -0.2 * _dormant_w + 0.2 * _roar_w - 0.3 * dw + 0.06 * stag * sin(_stagger_phase * 1.3)
	if _head_w > 0.0:
		var hp := _head_swing()
		neck_pitch = lerpf(neck_pitch, hp.x, _head_w)
		head_pitch = lerpf(head_pitch, hp.y, _head_w)
	_add_rot(&"neck", Vector3(neck_pitch, 0.05 * stag * sin(_stagger_phase * 0.7), 0))
	_add_rot(&"head", Vector3(head_pitch, 0, 0.04 * stag * sin(_stagger_phase)))
	# Stagger and reaction: the torso heaves (pitch) and rolls a little.
	extra_pitch = 0.025 * stag * sin(_stagger_phase * 0.8) + 0.04 * _react_w
	extra_roll = 0.03 * stag * sin(_stagger_phase * 0.6)
	Perf.end(&"boss_pose", t0)


## Head attack: [neck pitch, head pitch] by phase (rear up, swing down, come back).
func _head_swing() -> Vector2:
	var a := last_attack
	var up := Vector2(0.55, 0.35)
	var down := Vector2(-0.65, -0.45)
	match a.phase:
		ColossusAttack.Phase.TELEGRAPH:
			return Vector2.ZERO.lerp(up, _smooth(a.phase_t()))
		ColossusAttack.Phase.ACTIVE:
			return up.lerp(down, _smooth(a.phase_t()))
		ColossusAttack.Phase.RECOVERY:
			return down.lerp(Vector2.ZERO, _smooth(a.phase_t()))
	return Vector2.ZERO


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _add_rot(bone: StringName, euler: Vector3) -> void:
	var idx: int = _bone[bone]
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * Quaternion.from_euler(euler))


func _build_hit_volumes() -> void:
	for i in 2:
		var foot: StringName = leg_bones[i][2]
		hit_volumes[foot] = HitVolume.make(foot, Vector3(0, -0.2, 0.8), Vector3(0, -0.2, -1.2), 1.2)
	hit_volumes[&"head"] = HitVolume.make(&"head", Vector3(0, 0.2, 0.4), Vector3(0, 0.0, -2.6), 1.5)


func _reset_stats() -> void:
	stats = {"attacks": {}, "hits_on_player": 0, "stomp_impacts": 0, "weak_point_hits": 0, "steps": 0, "defeated_at": -1.0, "last_hit_damage": 0.0, "foot_hits": 0, "buckles": 0}


# --- debug --------------------------------------------------------------------------

func debug_text() -> String:
	var lines := PackedStringArray()
	lines.append("QUADRATUS %s (%.1fs)  move %s  intent %s  attack %s" % [encounter_name(), encounter_time, move_state(), intent.describe(), attack.describe() if attack != null and not attack.is_done() else "-"])
	lines.append("foot hit: %s leg %d (%.1fs)  cooldown %.1fs  hits %d  soles %s" % [buckle_name(), buckle_leg, buckle_t, _buckle_cooldown_left, int(stats.foot_hits), ", ".join(PackedStringArray(arrow_targets.map(func(t: ArrowTarget) -> String: return "%s %s" % [LEG_NAMES[int(t.tag)], "OPEN" if t.enabled else "-"])))])
	var wps := PackedStringArray()
	for wp in weak_points:
		wps.append("%s %.0f/%.0f" % [wp.state_name(), wp.health, wp.max_health])
	var region := "-"
	for p in get_tree().get_nodes_in_group(&"players"):
		var r := region_of(p)
		if r != &"":
			region = "%s on %s" % [p.name, r]
	lines.append("weak points rump %s crown %s  shake cooldown %.1fs  player %s" % [wps[0], wps[1], _shake_cooldown_left, region])
	lines.append("blocked: %s" % ", ".join(PackedStringArray(_blocked_intents())))
	lines.append(brain.debug_text())
	lines.append(locomotion_debug_text())
	return "\n".join(lines)


func _draw_debug_extra(d: QuadrupedDebugDraw) -> void:
	for t in arrow_targets:
		d.circle(t.world_point(), t.world_normal(), t.radius, Color.CYAN if t.enabled else Color(0.4, 0.4, 0.5))
		d.line(t.world_point(), t.world_point() + t.world_normal() * 1.5, Color.CYAN if t.enabled else Color(0.4, 0.4, 0.5))
	for wp in weak_points:
		var c := Color.CYAN if wp.state == WeakPoint.State.OPEN else Color.GRAY
		d.circle(wp.world_point(), Vector3.UP, wp.radius, c)
		d.cross(wp.world_point(), wp.radius, c)
	for h in hit_volumes.values():
		var hv := h as HitVolume
		d.line(hv.world_a, hv.world_b, Color.RED if hv.active else Color(0.5, 0.5, 0.5))
	for z in get_danger_zones():
		d.circle((z[0] as Vector3) + Vector3.UP * 0.2, Vector3.UP, z[1], Color(1, 0.6, 0.1))
	var prev := Vector3.INF
	for r in ROUTE:
		var seg: BodySegment = _seg_by_bone.get(r[0])
		var p: Vector3 = seg.target_transform * (r[1] as Vector3)
		if prev != Vector3.INF:
			d.line(prev, p, Color.YELLOW)
		prev = p
	if buckle_leg >= 0:
		d.cross(loco.legs[buckle_leg].plant_pos, 1.5, Color.ORANGE)


static func _dead(n: Node) -> bool:
	return n is PlayerCharacter and (n as PlayerCharacter).dead
