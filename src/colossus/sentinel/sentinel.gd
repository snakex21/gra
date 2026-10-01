class_name Sentinel
extends GreyboxHumanoid
## Sentinel: the first complete boss (vertical slice of the colossus fight).
##
## Same pipeline as every colossus:
##   observe -> SentinelBrain.decide -> FairnessRules filter -> intent
##   -> attacks (TELEGRAPH / ACTIVE / RECOVERY) + movement -> locomotion / IK -> segments
## The brain only proposes; the fairness rules (separate object) clamp timings, enforce
## cooldowns and keep the weak point reachable.
##
## Encounter: DORMANT -> NOTICE -> ENGAGED -> COMBAT -> DEFEATED.
## Climb route: back of a calf (fur) -> back of the thigh -> hips -> back -> mantle onto the
## shoulders (REST surface: stand, no grip, stamina comes back) -> mane on the back of the
## neck -> back of the head -> head top, where the weak point is.
## Attacks: STOMP (lift a foot over the player, slam it down) and ARM SWEEP (low swing of
## the arm on the player's side). Hit volumes are capsules on the real limb bones.

signal encounter_changed(state: Encounter)
signal attack_started(attack: ColossusAttack)
signal attack_phase_changed(attack: ColossusAttack)
signal player_hit(player: Node3D, attack_kind: StringName, damage: float)
signal defeated

enum Encounter { DORMANT, NOTICE, ENGAGED, COMBAT, DEFEATED }

const OBSERVE := &"observe_player"
const APPROACH := &"approach"
const STOMP := &"stomp"
const ARM_SWEEP := &"arm_sweep"
const PROTECT := &"protect_weakpoint"
const RECOVER := &"recover"
const SEARCH := &"search_player"

## Sentinel body: the greybox humanoid plus a fur mane on the back of the neck (route to
## the head), a fur cap over the head (weak point), armour on the front of the thighs, and
## the shoulder plateau tagged as a rest surface.
const SENTINEL_PARTS := [
	[&"hips", Kind.FUR, Vector3(4.2, 1.6, 2.6), Vector3(0, 0.2, 0)],
	[&"spine", Kind.FUR, Vector3(3.4, 2.4, 2.4), Vector3(0, 1.1, 0)],
	[&"chest", Kind.STONE, Vector3(5.0, 2.8, 3.0), Vector3(0, 1.4, 0), &"rest"],
	[&"chest", Kind.FUR, Vector3(4.4, 2.9, 0.5), Vector3(0, 1.2, 1.6)],
	[&"neck", Kind.FUR, Vector2(0.8, 2.2), Vector3(0, 0.6, 0.1)],
	[&"neck", Kind.FUR, Vector3(2.0, 2.6, 0.9), Vector3(0, 0.7, 0.95)],
	[&"head", Kind.STONE, Vector3(2.0, 2.2, 2.2), Vector3(0, 1.1, 0)],
	[&"head", Kind.FUR, Vector3(2.1, 0.4, 2.5), Vector3(0, 2.3, 0.15)],
	[&"head", Kind.FUR, Vector3(2.1, 2.3, 0.8), Vector3(0, 1.25, 1.0)],
	[&"upper_arm_l", Kind.FUR, Vector2(0.8, 4.6), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.FUR, Vector2(0.7, 4.4), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.ARMOR, Vector3(0.5, 2.6, 1.3), Vector3(0.75, -2.0, 0)],
	[&"hand_l", Kind.STONE, Vector3(1.3, 1.8, 1.1), Vector3(0, -0.9, 0)],
	[&"thigh_l", Kind.FUR, Vector2(1.0, 4.4), Vector3(0, -1.9, 0)],
	[&"thigh_l", Kind.ARMOR, Vector3(1.5, 2.6, 0.45), Vector3(0, -1.9, -1.05)],
	[&"shin_l", Kind.FUR, Vector2(0.85, 4.0), Vector3(0, -1.7, 0)],
	[&"shin_l", Kind.ARMOR, Vector3(1.3, 2.8, 0.45), Vector3(0, -1.7, -0.85)],
	[&"foot_l", Kind.STONE, Vector3(1.7, 0.7, 3.6), Vector3(0, -0.05, -0.85)],
]
## Weak point on top of the head (head bone space).
const WEAK_POINT_LOCAL := Vector3(0, 2.52, 0.2)
## Body regions by bone (gripping the chest = "back", standing on it = "shoulder").
## The spec's regions are foot / calf / thigh / pelvis / back / shoulder / head; the neck
## (the mane on the way to the head) is reported separately.
const REGIONS := {
	&"foot_l": &"foot", &"foot_r": &"foot", &"shin_l": &"calf", &"shin_r": &"calf",
	&"thigh_l": &"thigh", &"thigh_r": &"thigh", &"hips": &"pelvis", &"spine": &"back",
	&"chest": &"back", &"neck": &"neck", &"head": &"head",
	&"upper_arm_l": &"arm", &"forearm_l": &"arm", &"hand_l": &"arm",
	&"upper_arm_r": &"arm", &"forearm_r": &"arm", &"hand_r": &"arm",
}

@export_group("Encounter")
@export var notice_radius := 42.0
@export var notice_time := 1.2
@export var engage_time := 1.0
@export_group("Attacks")
@export var stomp_telegraph := 0.9
@export var stomp_active := 0.3
@export var stomp_recovery := 1.6
@export var stomp_height := 3.2
@export var stomp_reach := 3.5
@export var stomp_damage := 60.0
@export var shockwave_radius := 6.0
@export var shockwave_damage := 22.0
@export var sweep_telegraph := 1.1
@export var sweep_active := 0.6
@export var sweep_recovery := 1.2
@export var sweep_damage := 35.0
## Pelvis drop and forward bow during a sweep (the hand has to come down to the ground).
@export var sweep_crouch := 3.2
@export var sweep_bow := 0.55
@export var shake_telegraph := 0.6
@export var recover_time := 1.3
## Distance to the weak point that counts as "player near the weak point".
@export var weakpoint_alert_distance := 3.5

var encounter := Encounter.DORMANT
var encounter_time := 0.0
var rules := FairnessRules.new()
## Attack in progress (null when none).
var attack: ColossusAttack
var last_attack: ColossusAttack
var weak_point: WeakPoint
## name -> HitVolume
var hit_volumes := {}
## Counters for tests and the long regression run.
var stats := {}
## Brain seed (the encounter reset rebuilds the brain with it).
var brain_seed := 7
var effects_enabled := true

var _slam_point := Vector3.ZERO
var _hover_point := Vector3.ZERO
var _stomp_impacted := false
var _sweep_w := 0.0
var _protect_w := 0.0
var _stagger := 0.0
var _stagger_t := -1.0
var _stagger_phase := 0.0
var _roar_w := 0.0
var _dormant_w := 1.0
var _defeat_t := 0.0
var _brace_w := 0.0
var _last_touchdown_seen := -999.0
var _start_xf := Transform3D.IDENTITY
var _attack_intent: ColossusIntent
## Player id -> last time it was knocked down / falling (fairness: no hit on a downed player).
var _down_since := {}
var _seg_by_bone := {}


func _ready() -> void:
	brain = SentinelBrain.new(brain_seed)
	super()
	add_to_group(&"danger_sources")
	for s in segments:
		_seg_by_bone[s.bone_name] = s
	weak_point = WeakPoint.create(_seg_by_bone[&"head"], WEAK_POINT_LOCAL, 100.0)
	weak_point.struck.connect(_on_weak_point_struck)
	weak_point.destroyed.connect(_on_weak_point_destroyed)
	_build_hit_volumes()
	_start_xf = global_transform
	_reset_stats()


func _parts() -> Array:
	return SENTINEL_PARTS


# --- encounter API ------------------------------------------------------------------

## Puts the boss back at its start (or ``xf``), dormant, weak point restored.
func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_start_xf = xf
	_end_attack(false)
	for leg in loco.legs:
		leg.scripted = false
	teleport(_start_xf.origin, _start_xf.basis.get_euler().y)
	brain = SentinelBrain.new(brain_seed)
	rules.reset()
	weak_point.reset()
	intent = ColossusIntent.make(ColossusIntent.IDLE)
	_intent_time = 0.0
	_shake_cooldown_left = 0.0
	_think_left = 0.0
	_time_on_body.clear()
	_off_body_time.clear()
	_down_since.clear()
	_shake = 0.0
	_target_shake = 0.0
	_sweep_w = 0.0
	_protect_w = 0.0
	_stagger = 0.0
	_stagger_t = -1.0
	_roar_w = 0.0
	_dormant_w = 1.0
	_defeat_t = 0.0
	_brace_w = 0.0
	extra_pelvis_drop = 0.0
	_set_encounter(Encounter.DORMANT)
	_reset_stats()


func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED


func encounter_name() -> String:
	return Encounter.keys()[encounter]


## Body region the player is on (&"" when not on the body).
func region_of(player: Node3D) -> StringName:
	if not player.has_method(&"get_support_body"):
		return &""
	var support: Object = player.get_support_body()
	if not owns_body(support):
		return &""
	var bone := (support as BodySegment).bone_name
	if bone == &"chest" and not (player.has_method(&"is_climbing") and player.is_climbing()):
		return &"shoulder"
	return REGIONS.get(bone, &"body")


## Danger zones for animals / AI: [[centre, radius, seconds_to_impact], ...].
func get_danger_zones() -> Array:
	var out := []
	if attack == null or attack.is_done() or encounter == Encounter.DEFEATED:
		return out
	match attack.kind:
		STOMP:
			if attack.phase == ColossusAttack.Phase.PREPARE:
				# Already decided: the foot nearest the target will come down near it.
				var leg := loco.legs[maxi(attack.limb, 0)]
				out.append([_stomp_goal(attack.target_point, leg), shockwave_radius, attack.telegraph_time + 0.18])
			elif attack.phase == ColossusAttack.Phase.TELEGRAPH or attack.phase == ColossusAttack.Phase.ACTIVE:
				var t_left := attack.time_left() + (0.18 if attack.phase == ColossusAttack.Phase.TELEGRAPH else 0.0)
				out.append([_slam_point, shockwave_radius, t_left])
		ARM_SWEEP:
			if attack.phase == ColossusAttack.Phase.TELEGRAPH or attack.phase == ColossusAttack.Phase.ACTIVE:
				out.append([global_position - global_basis.z * 6.0, 9.0, attack.time_left()])
	return out


# --- observation / decision ---------------------------------------------------------

func observe() -> ColossusObservation:
	var obs := super()
	obs.encounter = StringName(encounter_name())
	obs.attack_running = attack != null and not attack.is_done()
	obs.weak_point_open = weak_point.state == WeakPoint.State.OPEN
	obs.weak_point_progress = weak_point.progress()
	var inv := global_transform.affine_inverse()
	var wp := weak_point.world_point()
	for info in obs.players:
		var pl := info.player
		info.region = region_of(pl)
		info.near_weakpoint = pl.global_position.distance_to(wp) < weakpoint_alert_distance
		var local := inv * pl.global_position
		info.bearing = atan2(-local.x, -local.z)
		info.riding = pl.has_method(&"is_riding") and pl.is_riding()
		info.stomp_foot = -1
		info.sweep_side = 0
		if info.on_body or _dead(pl):
			continue
		# Stomp: on the ground close to a foot.
		var best := 99.0
		for i in 2:
			var foot := loco.legs[i].plant_pos
			var d := Vector2(pl.global_position.x - foot.x, pl.global_position.z - foot.z).length()
			if d < 5.5 and absf(pl.global_position.y - foot.y) < 2.5 and d < best:
				best = d
				info.stomp_foot = i
		# Sweep: in front, within the arm's arc.
		if local.z < -2.5 and local.z > -7.5 and absf(local.x) < 7.0 and pl.global_position.y - global_position.y < 3.0:
			info.sweep_side = 1 if local.x >= 0.0 else -1
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
	# Commitment: an attack or a stagger runs to its end.
	if attack != null and not attack.is_done():
		return intent
	if intent.kind == RECOVER and _intent_time < recover_time:
		return intent
	var chosen := brain.decide(obs)
	if chosen == null or chosen.kind in obs.blocked_intents:
		chosen = ColossusIntent.make(OBSERVE)
		chosen.target_player = target
	return chosen


func _rules_block() -> Array[StringName]:
	var out := rules.blocked(_time)
	if rules.protect_expired(_time):
		out.append(PROTECT)
	if rules.reposition_expired(_time):
		out.append(ColossusIntent.REPOSITION)
	if weak_point.state != WeakPoint.State.OPEN and intent.kind != PROTECT:
		out.append(PROTECT)
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
	_update_attack(it, delta)
	_update_protect(it)
	var effective := _effective_intent(it)
	Perf.end(&"boss_combat", tc)
	super(effective, delta)


func _effective_intent(it: ColossusIntent) -> ColossusIntent:
	var e := ColossusIntent.make(ColossusIntent.IDLE)
	e.target_player = it.target_player
	if encounter == Encounter.DORMANT or encounter == Encounter.DEFEATED:
		e.target_player = null
		return e
	match it.kind:
		OBSERVE, SEARCH, APPROACH:
			if is_instance_valid(it.target_player):
				e = ColossusIntent.make(ColossusIntent.FOCUS_PLAYER)
				e.target_player = it.target_player
		ColossusIntent.REPOSITION:
			e = it
		ColossusIntent.SHAKE_PLAYER:
			# Telegraph: brace first (a deep groan, the body tenses), then shake.
			if _intent_time >= shake_telegraph:
				e = it
	return e


func _adjust_movement(it: ColossusIntent, delta: float) -> void:
	# Bracing before a shake, crouching for a sweep, kneeling when defeated.
	var bracing := it.kind == ColossusIntent.SHAKE_PLAYER and _intent_time < shake_telegraph and encounter == Encounter.COMBAT
	_brace_w = move_toward(_brace_w, 1.0 if bracing else 0.0, delta / 0.3)
	if bracing:
		loco.bracing = true
	var attacking := attack != null and not attack.is_done()
	var still := attacking or encounter == Encounter.DEFEATED or encounter == Encounter.DORMANT or it.kind == RECOVER or it.kind == PROTECT
	if still and debug_override != &"manual":
		desired_speed = 0.0
		desired_turn = 0.0
	var drop := 0.0
	drop += 0.35 * _brace_w
	drop += sweep_crouch * _sweep_w
	if encounter == Encounter.DEFEATED:
		drop += 3.0 * _defeat_weight()
	extra_pelvis_drop = drop
	if attacking and attack.kind == STOMP:
		_update_stomp_leg()


func _update_encounter(delta: float) -> void:
	encounter_time += delta
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
	_roar_w = move_toward(_roar_w, 1.0 if encounter == Encounter.ENGAGED else 0.0, delta / 0.4)
	# Flinch after a weak point hit: envelope sin^2 over the recovery time and an oscillation
	# that starts at zero, so the pose (and anyone holding on to the head) never jumps.
	if _stagger_t >= 0.0:
		_stagger_t += delta
		if _stagger_t >= recover_time:
			_stagger_t = -1.0
	var env := 0.0
	if _stagger_t >= 0.0:
		env = pow(sin(PI * _stagger_t / recover_time), 2.0)
	_stagger = env
	_stagger_phase = maxf(_stagger_t, 0.0) * 6.0


func _set_encounter(e: Encounter) -> void:
	if e == encounter and encounter_time > 0.0:
		return
	encounter = e
	encounter_time = 0.0
	_think_left = 0.0
	if e == Encounter.DEFEATED:
		_target_shake = 0.0
		_shake_cooldown_left = 999.0
		stats.defeated_at = _time
		if effects_enabled:
			Sfx.play(self, &"defeat", global_position + Vector3.UP * 8.0)
		defeated.emit()
	encounter_changed.emit(e)


# --- attacks ------------------------------------------------------------------------

func _update_attack(it: ColossusIntent, delta: float) -> void:
	# Start a new attack when the intent asks for one and none is running.
	# Start a new attack when the intent asks for one; one intent starts at most one attack.
	if (attack == null or attack.is_done()) and encounter == Encounter.COMBAT:
		if (it.kind == STOMP or it.kind == ARM_SWEEP) and it != _attack_intent:
			_attack_intent = it
			_start_attack(it)
	if attack == null:
		return
	if attack.phase == ColossusAttack.Phase.PREPARE:
		attack.tick(delta)
		# Wait (briefly) for both feet to stand before winding up.
		var planted := loco.legs[0].is_planted() and loco.legs[1].is_planted()
		if planted and loco.speed < 0.4:
			attack.begin_telegraph()
			_on_phase(attack)
		elif attack.phase_time > 2.5:
			_end_attack(false)
		return
	if attack.phase == ColossusAttack.Phase.TELEGRAPH and attack.kind == STOMP:
		_track_stomp_target(delta)
	if attack.tick(delta):
		_on_phase(attack)
		if attack.is_done():
			_end_attack(true)


func _start_attack(it: ColossusIntent) -> void:
	var a: ColossusAttack
	if it.kind == STOMP:
		a = ColossusAttack.make(STOMP, stomp_telegraph, stomp_active, stomp_recovery, true)
	else:
		a = ColossusAttack.make(ARM_SWEEP, sweep_telegraph, sweep_active, sweep_recovery, true)
	rules.clamp_attack(a)
	a.target_player = it.target_player
	if is_instance_valid(it.target_player):
		a.target_point = it.target_player.global_position
		var local := global_transform.affine_inverse() * a.target_point
		if it.kind == STOMP:
			var d0 := _flat(a.target_point - loco.legs[0].plant_pos).length()
			var d1 := _flat(a.target_point - loco.legs[1].plant_pos).length()
			a.limb = 0 if d0 <= d1 else 1
		else:
			a.limb = 0 if local.x >= 0.0 else 1
	else:
		a.limb = 0
	attack = a
	last_attack = a
	rules.on_attack_start(a.kind, _time)
	stats.attacks[a.kind] = int(stats.attacks.get(a.kind, 0)) + 1
	attack_started.emit(a)


func _end_attack(finished: bool) -> void:
	if attack == null:
		return
	if attack.kind == STOMP:
		var leg := loco.legs[attack.limb] if attack.limb >= 0 else null
		if leg and leg.scripted:
			# Never leave a foot hanging: plant it where it is (over the ground).
			leg.target_pos = _ground_under(leg.foot_pos)
			leg.target_normal = Vector3.UP
			StepMath.plant(leg, loco.time)
			leg.scripted = false
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
				leg.scripted = true
				leg.phase = LegState.Phase.SWING
				leg.swing_t = 0.0
				leg.lift_pos = leg.plant_pos
				leg.lift_normal = leg.plant_normal
				leg.lift_yaw = leg.plant_yaw
				leg.target_yaw = leg.plant_yaw
				leg.target_normal = Vector3.UP
				_stomp_impacted = false
				_slam_point = _stomp_goal(a.target_point, leg)
				leg.target_pos = _slam_point
		ARM_SWEEP:
			if a.phase == ColossusAttack.Phase.ACTIVE and effects_enabled:
				Sfx.play(self, &"swing", global_position + Vector3.UP * 6.0)


## Where the stomping foot can come down near ``p`` (within reach of its plant).
func _stomp_goal(p: Vector3, leg: LegState) -> Vector3:
	var off := _flat(p - leg.plant_pos)
	if off.length() > stomp_reach:
		off = off.normalized() * stomp_reach
	# Not under the other foot or the body centre.
	var goal := leg.plant_pos + off
	var other := loco.legs[1 - loco.legs.find(leg)]
	var away := _flat(goal - other.plant_pos)
	if away.length() < 2.6:
		goal = other.plant_pos + (away.normalized() if away.length() > 0.01 else global_basis.x) * 2.6
	return _ground_under(goal)


func _ground_under(p: Vector3) -> Vector3:
	var g := loco.probe_ground(get_world_3d().direct_space_state, p, global_position.y)
	return g[0]


## During the first 60% of the wind-up the raised foot drifts after the target (2 m/s at
## most); after that the slam point is locked, so a late dodge always works.
func _track_stomp_target(delta: float) -> void:
	if attack.phase_t() > 0.6 or not is_instance_valid(attack.target_player):
		return
	var leg := loco.legs[attack.limb]
	var want := _stomp_goal(attack.target_player.global_position, leg)
	var step := _flat(want - _slam_point)
	if step.length() > 2.0 * delta:
		step = step.normalized() * 2.0 * delta
	_slam_point = _ground_under(_slam_point + step) if step.length() > 1e-4 else _slam_point
	leg.target_pos = _slam_point


func _update_stomp_leg() -> void:
	var leg := loco.legs[attack.limb]
	if not leg.scripted:
		return
	var up := Vector3.UP * stomp_height
	match attack.phase:
		ColossusAttack.Phase.TELEGRAPH:
			var t := minf(1.0, attack.phase_t() / 0.75)
			var s := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
			_hover_point = leg.lift_pos.lerp(_slam_point, s * 0.85) + up * s
			# A slight tremble at the top of the wind-up.
			if t >= 1.0:
				_hover_point += Vector3.UP * 0.05 * sin(attack.phase_time * 30.0)
			leg.foot_pos = _hover_point
			leg.swing_t = 0.5 * s
		ColossusAttack.Phase.ACTIVE:
			var t := minf(1.0, attack.phase_time / 0.18)
			leg.foot_pos = _hover_point.lerp(_slam_point, t * t)
			leg.swing_t = 0.5 + 0.5 * t
			if t >= 1.0 and not _stomp_impacted:
				_stomp_impacted = true
				leg.target_pos = _slam_point
				StepMath.plant(leg, loco.time)
				leg.scripted = false
				_on_stomp_impact()


func _on_stomp_impact() -> void:
	stats.stomp_impacts = int(stats.stomp_impacts) + 1
	if effects_enabled:
		Fx.dust(get_parent(), _slam_point, 2.2)
		Sfx.play(self, &"stomp", _slam_point)


## Hit volumes vs players, after the segments followed the bones this tick.
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
	if attack.kind == STOMP and attack.phase == ColossusAttack.Phase.ACTIVE and not _stomp_impacted:
		volumes.append(hit_volumes[&"foot_l" if attack.limb == 0 else &"foot_r"])
	elif attack.kind == ARM_SWEEP and attack.phase == ColossusAttack.Phase.ACTIVE:
		var side := "l" if attack.limb == 0 else "r"
		volumes.append(hit_volumes[StringName("forearm_" + side)])
		volumes.append(hit_volumes[StringName("hand_" + side)])
	for v in volumes:
		v.active = true
	var shock := attack.kind == STOMP and attack.phase == ColossusAttack.Phase.ACTIVE and _stomp_impacted
	if volumes.is_empty() and not shock:
		return
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as PlayerCharacter
		if pl == null or pl.dead or attack.hit_ids.has(pl.get_instance_id()):
			continue
		# Fairness: someone knocked down (or falling) by something else is not hit again
		# while down and for a moment after getting up.
		if _time - float(_down_since.get(pl.get_instance_id(), -999.0)) < rules.downed_grace and attack.age > 0.0 and not attack.hit_ids.has(pl.get_instance_id()):
			if _time - attack.age < float(_down_since.get(pl.get_instance_id(), -999.0)) + 1e-3 or pl.balance.state == Balance.State.FALLEN:
				continue
		if pl.has_method(&"get_support_body") and owns_body(pl.get_support_body()):
			continue  # its own attacks do not hit a climber on its body
		Perf.count(&"boss_hit_tests")
		for v in volumes:
			if v.touches(pl.global_position, 0.55, 0.35):
				_hit_player(pl, v)
				break
		if shock and not attack.hit_ids.has(pl.get_instance_id()):
			var d := Vector2(pl.global_position.x - _slam_point.x, pl.global_position.z - _slam_point.z).length()
			if d < shockwave_radius and pl.global_position.y - _slam_point.y < 2.2:
				var close := 1.0 - d / shockwave_radius
				var out := _flat(pl.global_position - _slam_point).normalized()
				attack.hit_ids[pl.get_instance_id()] = true
				var dmg := shockwave_damage * (0.4 + 0.6 * close)
				if pl.apply_hit(dmg, out * (3.0 + 5.0 * close) + Vector3.UP * 3.0, 1.4 if close > 0.4 else 0.0, &"shockwave"):
					_count_hit(pl, &"shockwave", dmg)


func _hit_player(pl: PlayerCharacter, _v: HitVolume) -> void:
	attack.hit_ids[pl.get_instance_id()] = true
	var dmg := stomp_damage if attack.kind == STOMP else sweep_damage
	var push := Vector3.ZERO
	var knock := 1.6
	if attack.kind == STOMP:
		push = _flat(pl.global_position - _slam_point).normalized() * 6.0 + Vector3.UP * 2.0
		knock = 2.2
	else:
		var side := global_basis.x * (1.0 if attack.limb == 0 else -1.0)
		push = -side * 9.0 + Vector3.UP * 4.0
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
			Fx.dust(get_parent(), p, 1.0)
			Sfx.play(self, &"step", p)


# --- weak point / protection / stagger ----------------------------------------------

func _update_protect(it: ColossusIntent) -> void:
	var on := it.kind == PROTECT and encounter == Encounter.COMBAT and not rules.protect_expired(_time)
	if on != (weak_point.state == WeakPoint.State.PROTECTED):
		weak_point.set_protected(on)
		rules.on_protect(on, _time)
		if on:
			stats.protects = int(stats.protects) + 1
	rules.on_reposition(it.kind == ColossusIntent.REPOSITION and encounter == Encounter.COMBAT, _time)


func _on_weak_point_struck(damage: float, _left: float) -> void:
	stats.weak_point_hits = int(stats.weak_point_hits) + 1
	if effects_enabled:
		Sfx.play(self, &"weak_hit", weak_point.world_point())
		Fx.burst(get_parent(), weak_point.world_point())
	if encounter == Encounter.DORMANT or encounter == Encounter.NOTICE:
		_set_encounter(Encounter.COMBAT)
	# Reaction: a violent flinch (the climber has to hold on), then a short recovery
	# during which nothing else is chosen.
	_stagger_t = 0.0
	if encounter == Encounter.COMBAT and weak_point.state != WeakPoint.State.DESTROYED:
		var r := ColossusIntent.make(RECOVER)
		_set_intent(r)
	stats.last_hit_damage = damage


func _on_weak_point_destroyed() -> void:
	_set_encounter(Encounter.DEFEATED)


func _defeat_weight() -> float:
	var t := clampf(_defeat_t / 6.0, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# --- poses --------------------------------------------------------------------------

func _pose_overrides(delta: float) -> void:
	var t0 := Perf.begin()
	# Sweep weight: wind-up, swing and return all blend the arm in and out smoothly.
	var sweeping := attack != null and attack.kind == ARM_SWEEP and attack.phase in [ColossusAttack.Phase.TELEGRAPH, ColossusAttack.Phase.ACTIVE, ColossusAttack.Phase.RECOVERY]
	var sweep_target := 0.0
	if sweeping:
		sweep_target = 1.0 if attack.phase != ColossusAttack.Phase.RECOVERY else 1.0 - attack.phase_t()
	_sweep_w = move_toward(_sweep_w, sweep_target, delta / 0.35)
	_protect_w = move_toward(_protect_w, 1.0 if weak_point.state == WeakPoint.State.PROTECTED else 0.0, delta / 0.4)

	var dw := _defeat_weight() if encounter == Encounter.DEFEATED else 0.0
	# Torso: bow while dormant / defeated, rise for the roar, bend into a sweep, flinch.
	var stag := _stagger
	var pitch := -0.25 * _dormant_w + 0.18 * _roar_w - sweep_bow * _sweep_w - 0.5 * dw + 0.05 * stag * sin(_stagger_phase)
	var twist := 0.0
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	if sweeping or _sweep_w > 0.0:
		var side := 1.0 if (last_attack != null and last_attack.limb == 0) else -1.0
		var r := _sweep_arm(side)
		twist = r[0]
		if side > 0.0:
			arm_l = r[1]
		else:
			arm_r = r[1]
	_add_rot(&"spine", Vector3(pitch * 0.5, twist * 0.5, 0.03 * stag * sin(_stagger_phase * 1.3)))
	_add_rot(&"chest", Vector3(pitch * 0.5, twist * 0.5, 0.0))
	if arm_l != Vector3.ZERO:
		_set_arm(&"upper_arm_l", arm_l, _sweep_w)
	if arm_r != Vector3.ZERO:
		_set_arm(&"upper_arm_r", arm_r, _sweep_w)
	if _protect_w > 0.0:
		# Raise the right arm beside the head (a guard gesture; the head itself closes).
		_set_arm(&"upper_arm_r", Vector3(-0.55, 0.82, 0.15).normalized(), _protect_w)
		_blend_rot(&"forearm_r", Quaternion.from_euler(Vector3(-1.2, 0, 0)), _protect_w)
	if _roar_w > 0.0:
		_set_arm(&"upper_arm_l", Vector3(0.75, -0.65, -0.1).normalized(), _roar_w * 0.7)
		_set_arm(&"upper_arm_r", Vector3(-0.75, -0.65, -0.1).normalized(), _roar_w * 0.7)
	# Head: bowed while dormant / defeated, ducks while protecting, shakes in a flinch.
	var head_pitch := -0.45 * _dormant_w - 0.25 * _protect_w - 0.55 * dw + 0.2 * _roar_w
	_add_rot(&"neck", Vector3(head_pitch * 0.5 + 0.07 * stag * sin(_stagger_phase), 0, 0))
	_add_rot(&"head", Vector3(head_pitch * 0.5, 0.06 * stag * sin(_stagger_phase * 0.7), 0))
	if dw > 0.0:
		for b in [&"upper_arm_l", &"upper_arm_r"]:
			_blend_rot(b, Quaternion.IDENTITY, dw)
	Perf.end(&"boss_pose", t0)


## Arm direction (chest space) and torso twist for the sweep, by phase.
## Returns [twist, arm_dir].
func _sweep_arm(side: float) -> Array:
	var a := last_attack
	var theta := 0.0     # 0 = out to the side, PI/2 = straight ahead
	var elev := 0.1      # angle from hanging straight down
	var twist := 0.0
	match a.phase:
		ColossusAttack.Phase.TELEGRAPH:
			var t := _smooth(a.phase_t())
			theta = lerpf(0.0, -0.6, t)
			elev = lerpf(0.1, 1.35, t)
			twist = 0.45 * side * t
		ColossusAttack.Phase.ACTIVE:
			var t := _smooth(a.phase_t())
			theta = lerpf(-0.6, PI * 0.95, t)
			elev = lerpf(1.35, 0.62, _smooth(minf(1.0, a.phase_t() * 3.0)))
			twist = lerpf(0.45, -0.45, t) * side
		_:
			theta = PI * 0.95
			elev = 0.62
			twist = -0.45 * side
	var out := Vector3(side, 0, 0)
	var h := out * cos(theta) + Vector3.FORWARD * sin(theta)
	var d := (h * sin(elev) + Vector3.DOWN * cos(elev)).normalized()
	return [twist, d]


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Points an upper arm along ``dir_body`` (direction in the colossus' own space, so a bowed
## torso does not swing the arm backwards) and keeps the forearm almost straight.
func _set_arm(bone: StringName, dir_body: Vector3, w: float) -> void:
	var chest := skeleton.get_bone_global_pose(_bone[&"chest"]).basis.orthonormalized()
	var d := (chest.inverse() * dir_body).normalized()
	var q := Quaternion(Vector3.DOWN, d)
	_blend_rot(bone, q, w)
	var fore := StringName(String(bone).replace("upper_arm", "forearm"))
	_blend_rot(fore, Quaternion.from_euler(Vector3(-0.12, 0, 0)), w)


func _blend_rot(bone: StringName, q: Quaternion, w: float) -> void:
	var idx: int = _bone[bone]
	var cur := skeleton.get_bone_pose_rotation(idx)
	skeleton.set_bone_pose_rotation(idx, cur.slerp(q, clampf(w, 0.0, 1.0)))


func _add_rot(bone: StringName, euler: Vector3) -> void:
	var idx: int = _bone[bone]
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * Quaternion.from_euler(euler))


func _build_hit_volumes() -> void:
	for side in ["l", "r"]:
		hit_volumes[StringName("foot_" + side)] = HitVolume.make(StringName("foot_" + side), Vector3(0, -0.1, 0.7), Vector3(0, -0.1, -2.4), 1.1)
		hit_volumes[StringName("forearm_" + side)] = HitVolume.make(StringName("forearm_" + side), Vector3(0, -0.5, 0), Vector3(0, -4.2, 0), 0.95)
		hit_volumes[StringName("hand_" + side)] = HitVolume.make(StringName("hand_" + side), Vector3(0, 0, 0), Vector3(0, -1.8, 0), 1.0)


func _reset_stats() -> void:
	stats = {"attacks": {}, "hits_on_player": 0, "stomp_impacts": 0, "weak_point_hits": 0, "protects": 0, "steps": 0, "defeated_at": -1.0, "last_hit_damage": 0.0}


# --- debug --------------------------------------------------------------------------

func debug_text() -> String:
	var lines := PackedStringArray()
	lines.append("SENTINEL %s (%.1fs)  intent %s  attack %s" % [encounter_name(), encounter_time, intent.describe(), attack.describe() if attack != null and not attack.is_done() else "-"])
	var timers := "-"
	if attack != null and not attack.is_done():
		timers = "telegraph %.2f  active %.2f  recovery %.2f  (left %.2f)" % [attack.telegraph_time, attack.active_time, attack.recovery_time, attack.time_left()]
	lines.append("attack timers: %s" % timers)
	var region := "-"
	var target := "-"
	for p in get_tree().get_nodes_in_group(&"players"):
		var r := region_of(p)
		if r != &"":
			region = "%s on %s" % [p.name, r]
	if intent.target_player:
		target = intent.target_player.name
	lines.append("weak point %s %.0f%% (hits %d, rejected %d: %s)  shake cooldown %.1fs  player region %s  target %s" % [weak_point.state_name(), weak_point.progress() * 100.0, weak_point.hits_accepted, weak_point.hits_rejected, weak_point.last_reason, _shake_cooldown_left, region, target])
	lines.append("blocked: %s" % ", ".join(PackedStringArray(_blocked_intents())))
	lines.append(brain.debug_text())
	lines.append(locomotion_debug_text())
	return "\n".join(lines)


static func _dead(n: Node) -> bool:
	return n is PlayerCharacter and (n as PlayerCharacter).dead
