class_name HumanoidBoss
extends GreyboxHumanoid
## Shared boss logic for two-legged colossi (Valus, Gaius). Nothing here is about one
## boss: a concrete boss supplies its body, brain, weak point, regions and attacks
## through the hooks below and adds its own poses.
##
##   observe -> brain.decide -> FairnessRules + _extra_rules -> intent
##   -> attacks (PREPARE -> TELEGRAPH -> ACTIVE -> RECOVERY) + movement -> locomotion / IK
##
## Encounter: DORMANT -> NOTICE -> ENGAGED -> COMBAT -> DEFEATED. Built in here: the stomp
## (shared LimbStomp + shockwave), hit testing with the fairness grace for downed
## players, the weak point reaction (stagger, recover), the defeat (kneel and bow so a
## climber can get down), danger zones for Agro, stats for tests and soaks.

signal encounter_changed(state: Encounter)
signal attack_started(attack: ColossusAttack)
signal attack_phase_changed(attack: ColossusAttack)
signal player_hit(player: Node3D, attack_kind: StringName, damage: float)

enum Encounter { DORMANT, NOTICE, ENGAGED, COMBAT, DEFEATED }

const OBSERVE := &"observe_player"
const APPROACH := &"approach"
const STOMP := &"stomp"
const RECOVER := &"recover"
const SEARCH := &"search_player"

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
@export var shake_telegraph := 0.6
@export var recover_time := 1.3
## Distance to the weak point that counts as "player near the weak point".
@export var weakpoint_alert_distance := 3.5
@export_group("Defeat")
## The defeated colossus sinks onto its knees (pelvis drop, m) and bows forward (rad), so
## whoever holds on to its head ends up low enough to step off (no stranding up high).
@export var defeat_drop := 5.6
@export var defeat_bow := 1.6
## Seconds the whole sinking takes (slow: whoever holds on rides it down).
@export var defeat_time := 9.0

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

## The stomp motion (shared with every stomping colossus).
var _stomp := LimbStomp.new()
## Where the current / last stomp comes down (danger zone, shockwave centre).
var _slam_point: Vector3:
	get:
		return _stomp.slam_point
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


# --- hooks (override) -----------------------------------------------------------------

func _make_brain() -> ColossusBrain:
	return UtilityBrain.new()


## [bone, bone-space point, health]
func _weak_point_spec() -> Array:
	return [&"head", Vector3(0, 2.5, 0), 100.0]


## bone -> region name
func _regions() -> Dictionary:
	return {}


## Intent kinds that start an attack.
func _attack_kinds() -> Array[StringName]:
	return [STOMP]


## The attack for an intent (timings before the fairness clamp); null = none.
func _make_attack(it: ColossusIntent) -> ColossusAttack:
	if it.kind == STOMP:
		var a := ColossusAttack.make(STOMP, stomp_telegraph, stomp_active, stomp_recovery, true)
		a.limb = 0
		if is_instance_valid(it.target_player):
			var d0 := _flat(it.target_player.global_position - loco.legs[0].plant_pos).length()
			var d1 := _flat(it.target_player.global_position - loco.legs[1].plant_pos).length()
			a.limb = 0 if d0 <= d1 else 1
		return a
	return null


## Phase changes of an attack (start motions, sounds).
func _on_attack_phase(a: ColossusAttack) -> void:
	if a.kind == STOMP and a.phase == ColossusAttack.Phase.TELEGRAPH:
		var leg := loco.legs[a.limb]
		_stomp.height = stomp_height
		_stomp.begin(leg, _stomp_goal(a.target_point, leg))


## Every tick of a running attack (after its timers advanced).
func _attack_tick(a: ColossusAttack, delta: float) -> void:
	if a.kind == STOMP and a.phase == ColossusAttack.Phase.TELEGRAPH and is_instance_valid(a.target_player):
		_stomp.track(_stomp_goal(a.target_player.global_position, loco.legs[a.limb]), a, delta, _ground_under)


## Attack ended (finished or aborted): never leave a limb hanging.
func _attack_cleanup(a: ColossusAttack) -> void:
	if a.kind == STOMP and _stomp.leg != null:
		_stomp.abort(_ground_under(_stomp.leg.foot_pos), loco.time)


## Hit volumes active this tick.
func _attack_volumes(a: ColossusAttack) -> Array[HitVolume]:
	var out: Array[HitVolume] = []
	if a.kind == STOMP and a.phase == ColossusAttack.Phase.ACTIVE and not _stomp.impacted:
		out.append(hit_volumes[&"foot_l" if a.limb == 0 else &"foot_r"])
	return out


## A ground shockwave this tick: [centre, radius, damage] or [].
func _attack_shock(a: ColossusAttack) -> Array:
	if a.kind == STOMP and a.phase == ColossusAttack.Phase.ACTIVE and _stomp.impacted:
		return [_slam_point, shockwave_radius, shockwave_damage]
	return []


## [damage, push, knockdown seconds] for a direct hit.
func _hit_values(a: ColossusAttack, pl: PlayerCharacter) -> Array:
	return [stomp_damage, _flat(pl.global_position - _slam_point).normalized() * 6.0 + Vector3.UP * 2.0, 2.2]


## Danger zones of the running attack: [[centre, radius, seconds], ...].
func _attack_danger(a: ColossusAttack) -> Array:
	var out := []
	if a.kind == STOMP:
		if a.phase == ColossusAttack.Phase.PREPARE:
			# Already decided: the foot nearest the target will come down near it.
			var leg := loco.legs[maxi(a.limb, 0)]
			out.append([_stomp_goal(a.target_point, leg), shockwave_radius, a.telegraph_time + 0.18])
		elif a.phase == ColossusAttack.Phase.TELEGRAPH or a.phase == ColossusAttack.Phase.ACTIVE:
			var t_left := a.time_left() + (0.18 if a.phase == ColossusAttack.Phase.TELEGRAPH else 0.0)
			out.append([_slam_point, shockwave_radius, t_left])
	return out


## Attack opportunities for a player on the ground (``local`` in the boss' frame).
func _observe_player(info: ColossusObservation.PlayerInfo, _local: Vector3) -> void:
	var pl := info.player
	var best := 99.0
	for i in 2:
		var foot := loco.legs[i].plant_pos
		var d := Vector2(pl.global_position.x - foot.x, pl.global_position.z - foot.z).length()
		if d < 5.5 and absf(pl.global_position.y - foot.y) < 2.5 and d < best:
			best = d
			info.stomp_foot = i


func _extra_rules(_out: Array[StringName]) -> void:
	pass


## Per tick before movement (protection, special states).
func _update_extra(_it: ColossusIntent, _delta: float) -> void:
	pass


## Intents during which the boss stands still.
func _holds_still(it: ColossusIntent) -> bool:
	return it.kind == RECOVER


## Extra pelvis drop (crouch for an attack...).
func _extra_drop() -> float:
	return 0.0


func _reset_extra() -> void:
	pass


func _build_hit_volumes() -> void:
	for side in ["l", "r"]:
		hit_volumes[StringName("foot_" + side)] = HitVolume.make(StringName("foot_" + side), Vector3(0, -0.1, 0.7), Vector3(0, -0.1, -2.4), 1.1)


func _reset_stats() -> void:
	stats = {"attacks": {}, "hits_on_player": 0, "stomp_impacts": 0, "weak_point_hits": 0, "protects": 0, "steps": 0, "defeated_at": -1.0, "last_hit_damage": 0.0}


func _boss_label() -> String:
	return String(name).to_upper()


func _debug_extra() -> String:
	return ""


# --- setup ----------------------------------------------------------------------------

func _ready() -> void:
	brain = _make_brain()
	super()
	add_to_group(&"danger_sources")
	for s in segments:
		_seg_by_bone[s.bone_name] = s
	var spec := _weak_point_spec()
	weak_point = WeakPoint.create(_seg_by_bone[spec[0]], spec[1], spec[2])
	weak_point.struck.connect(_on_weak_point_struck)
	weak_point.destroyed.connect(_on_weak_point_destroyed)
	_build_hit_volumes()
	_start_xf = global_transform
	_reset_stats()


# --- encounter API ------------------------------------------------------------------

## Puts the boss back at its start (or ``xf``), dormant, weak point restored.
func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_start_xf = xf
	_end_attack(false)
	for leg in loco.legs:
		leg.scripted = false
	teleport(_start_xf.origin, _start_xf.basis.get_euler().y)
	brain = _make_brain()
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
	_stagger = 0.0
	_stagger_t = -1.0
	_roar_w = 0.0
	_dormant_w = 1.0
	_defeat_t = 0.0
	_brace_w = 0.0
	extra_pelvis_drop = 0.0
	_reset_extra()
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
	return _regions().get(bone, &"body")


## Danger zones for animals / AI: [[centre, radius, seconds_to_impact], ...].
func get_danger_zones() -> Array:
	if attack == null or attack.is_done() or encounter == Encounter.DEFEATED:
		return []
	return _attack_danger(attack)


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
		info.opportunities.clear()
		if info.on_body or _dead(pl):
			continue
		_observe_player(info, local)
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
	if rules.reposition_expired(_time):
		out.append(ColossusIntent.REPOSITION)
	_extra_rules(out)
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
	_update_extra(it, delta)
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
	# Bracing before a shake, crouching for an attack, kneeling when defeated.
	var bracing := it.kind == ColossusIntent.SHAKE_PLAYER and _intent_time < shake_telegraph and encounter == Encounter.COMBAT
	_brace_w = move_toward(_brace_w, 1.0 if bracing else 0.0, delta / 0.3)
	if bracing:
		loco.bracing = true
	var attacking := attack != null and not attack.is_done()
	var still := attacking or encounter == Encounter.DEFEATED or encounter == Encounter.DORMANT or _holds_still(it)
	if still and debug_override != &"manual":
		desired_speed = 0.0
		desired_turn = 0.0
	var drop := 0.0
	drop += 0.35 * _brace_w
	drop += _extra_drop()
	if encounter == Encounter.DEFEATED:
		drop += defeat_drop * _defeat_weight()
	extra_pelvis_drop = drop
	if attacking and attack.kind == STOMP and _stomp.update(attack, loco.time):
		_on_stomp_impact()


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
		_end_attack(false)
		_target_shake = 0.0
		_shake_cooldown_left = 999.0
		stats.defeated_at = _time
		if effects_enabled:
			Sfx.play(self, &"defeat", global_position + Vector3.UP * 8.0)
		defeated.emit()
	encounter_changed.emit(e)


# --- attacks ------------------------------------------------------------------------

func _update_attack(it: ColossusIntent, delta: float) -> void:
	# Start a new attack when the intent asks for one; one intent starts at most one attack.
	if (attack == null or attack.is_done()) and encounter == Encounter.COMBAT:
		if it.kind in _attack_kinds() and it != _attack_intent:
			_attack_intent = it
			_start_attack(it)
	if attack == null or attack.is_done():
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
	_attack_tick(attack, delta)
	if attack.tick(delta):
		_on_phase(attack)
		if attack.is_done():
			_end_attack(true)


func _start_attack(it: ColossusIntent) -> void:
	var a := _make_attack(it)
	if a == null:
		return
	rules.clamp_attack(a)
	a.target_player = it.target_player
	if is_instance_valid(it.target_player):
		a.target_point = it.target_player.global_position
	attack = a
	last_attack = a
	rules.on_attack_start(a.kind, _time)
	stats.attacks[a.kind] = int(stats.attacks.get(a.kind, 0)) + 1
	attack_started.emit(a)


## Closes the running attack (also one that just reached DONE): limbs back, the rules
## learn that it ended (cooldowns), hit volumes off. Safe to call twice.
func _end_attack(finished: bool) -> void:
	if attack == null or attack.get_meta(&"closed", false):
		return
	attack.set_meta(&"closed", true)
	_attack_cleanup(attack)
	if finished or attack.phase != ColossusAttack.Phase.PREPARE:
		rules.on_attack_end(attack, _time)
	for h in hit_volumes.values():
		(h as HitVolume).active = false
	attack.phase = ColossusAttack.Phase.DONE
	_think_left = 0.0


func _on_phase(a: ColossusAttack) -> void:
	attack_phase_changed.emit(a)
	_on_attack_phase(a)


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
	var volumes := _attack_volumes(attack)
	for v in volumes:
		v.active = true
	var shock := _attack_shock(attack)
	if volumes.is_empty() and shock.is_empty():
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
		if not shock.is_empty() and not attack.hit_ids.has(pl.get_instance_id()):
			var c: Vector3 = shock[0]
			var radius: float = shock[1]
			var d := Vector2(pl.global_position.x - c.x, pl.global_position.z - c.z).length()
			if d < radius and pl.global_position.y - c.y < 2.2:
				var close := 1.0 - d / radius
				var out := _flat(pl.global_position - c).normalized()
				attack.hit_ids[pl.get_instance_id()] = true
				var dmg: float = float(shock[2]) * (0.4 + 0.6 * close)
				if pl.apply_hit(dmg, out * (3.0 + 5.0 * close) + Vector3.UP * 3.0, 1.4 if close > 0.4 else 0.0, &"shockwave"):
					_count_hit(pl, &"shockwave", dmg)


func _hit_player(pl: PlayerCharacter, _v: HitVolume) -> void:
	attack.hit_ids[pl.get_instance_id()] = true
	var hv := _hit_values(attack, pl)
	if pl.apply_hit(hv[0], hv[1], hv[2], attack.kind):
		_count_hit(pl, attack.kind, hv[0])
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


# --- weak point / stagger / defeat --------------------------------------------------

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
	var t := clampf(_defeat_t / defeat_time, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# --- pose helpers --------------------------------------------------------------------

static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _blend_rot(bone: StringName, q: Quaternion, w: float) -> void:
	var idx: int = _bone[bone]
	var cur := skeleton.get_bone_pose_rotation(idx)
	skeleton.set_bone_pose_rotation(idx, cur.slerp(q, clampf(w, 0.0, 1.0)))


func _add_rot(bone: StringName, euler: Vector3) -> void:
	var idx: int = _bone[bone]
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * Quaternion.from_euler(euler))


## Points an upper arm along ``dir_body`` (direction in the colossus' own space, so a bowed
## torso does not swing the arm backwards) and keeps the forearm almost straight.
func _set_arm(bone: StringName, dir_body: Vector3, w: float) -> void:
	var chest := skeleton.get_bone_global_pose(_bone[&"chest"]).basis.orthonormalized()
	var d := (chest.inverse() * dir_body).normalized()
	var q := Quaternion(Vector3.DOWN, d)
	_blend_rot(bone, q, w)
	var fore := StringName(String(bone).replace("upper_arm", "forearm"))
	_blend_rot(fore, Quaternion.from_euler(Vector3(-0.12, 0, 0)), w)


# --- debug --------------------------------------------------------------------------

func debug_text() -> String:
	var lines := PackedStringArray()
	lines.append("%s %s (%.1fs)  intent %s  attack %s" % [_boss_label(), encounter_name(), encounter_time, intent.describe(), attack.describe() if attack != null and not attack.is_done() else "-"])
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
	var extra := _debug_extra()
	if extra != "":
		lines.append(extra)
	lines.append("blocked: %s" % ", ".join(PackedStringArray(_blocked_intents())))
	lines.append(brain.debug_text())
	lines.append(locomotion_debug_text())
	return "\n".join(lines)


static func _dead(n: Node) -> bool:
	return n is PlayerCharacter and (n as PlayerCharacter).dead
