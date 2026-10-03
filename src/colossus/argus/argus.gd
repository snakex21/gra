class_name Argus
extends Valus
## Stone passage guardian. Lower limbs are armour; the gallery supplies the entry.
## It commits a stomp to the ruin counterweight, physically lifting the access slab.
## Two sigils: back, then crown. No weapon-as-bridge mechanic.
var ruins: ArgusRuins
var back_point: WeakPoint
var crown_point: WeakPoint
var weak_points: Array[WeakPoint] = []

func _init() -> void:
	notice_radius = 80.0
	stomp_telegraph = 1.6
	stomp_recovery = 2.3
	stomp_reach = 6.0
	shockwave_radius = 4.0
	shockwave_damage = 18.0
	arena_radius = 175.0
	brain_seed = 79
	shake_cooldown = 8.0

func _ready() -> void:
	ruins = get_parent().get_node_or_null("ArgusRuins") as ArgusRuins
	super()
	crown_point = weak_point
	back_point = WeakPoint.create(_seg_by_bone[&"chest"], Vector3(0, 1.2, 1.88), 80.0)
	back_point.struck.connect(_on_weak_point_struck)
	back_point.destroyed.connect(_on_weak_point_destroyed)
	weak_points = [back_point, crown_point]
	weak_point = back_point
	_update_protection()

func _parts() -> Array:
	var parts := Valus.VALUS_PARTS.duplicate(true)
	for part in parts:
		if part[0] in [&"hips", &"thigh_l", &"shin_l"] and part[1] == Kind.FUR:
			part[1] = Kind.STONE
	parts.append([&"head", Kind.ARMOR, Vector3(2.6, 0.45, 1.2), Vector3(0, 1.7, -1.05)])
	parts.append([&"chest", Kind.ARMOR, Vector3(5.8, 0.5, 1.0), Vector3(0, 2.9, -1.2)])
	return parts

func _weak_point_spec() -> Array:
	return [&"head", Valus.WEAK_POINT_LOCAL, 80.0]

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	obs.players = obs.players.filter(func(info: ColossusObservation.PlayerInfo) -> bool: return not _dead(info.player))
	if encounter != Encounter.COMBAT or attack != null and not attack.is_done() or not _time_on_body.is_empty():
		return super(obs)
	if ruins != null and not ruins.activated and STOMP not in obs.blocked_intents:
		for info in obs.players:
			var p := info.player as PlayerCharacter
			if p != null and not p.dead and not info.on_body and _flat(p.global_position - ruins.to_global(ArgusRuins.PLATE)).length() < 3.5:
				var stomp := ColossusIntent.make(STOMP)
				stomp.target_player = p
				return stomp
	if ruins != null and not ruins.activated:
		var watch := ColossusIntent.make(OBSERVE)
		watch.target_player = _focus_player(obs)
		return watch
	return super(obs)

func _attack_tick(a: ColossusAttack, delta: float) -> void:
	# The first stomp commits to the marked stone. The full 1.6 s warning permits a
	# sideways dodge; tracking would punish the very dodge needed by the puzzle.
	if a.kind == STOMP and ruins != null and not ruins.activated:
		return
	super(a, delta)

func _stomp_goal(p: Vector3, leg: LegState) -> Vector3:
	if ruins != null and not ruins.activated:
		var plate := ruins.to_global(ArgusRuins.PLATE)
		if _flat(plate - p).length() < 3.5:
			return plate
	return super(p, leg)

func _on_stomp_impact() -> void:
	super()
	if ruins != null:
		ruins.receive_impact(_slam_point)

func _adjust_movement(it: ColossusIntent, delta: float) -> void:
	super(it, delta)
	# A guardian occupying the passage keeps its feet beside the counterweight.
	# Body IK, attacks and shakes still animate; the gallery's jump remains predictable.
	desired_speed = 0.0
	desired_turn = 0.0

func _extra_rules(out: Array[StringName]) -> void:
	out.append(PROTECT)
	out.append(ColossusIntent.REPOSITION)

func _update_extra(_it: ColossusIntent, _delta: float) -> void:
	_update_protection()

func _update_protection() -> void:
	var open := ruins != null and ruins.route_open
	for wp in weak_points:
		wp.set_protected(not open or (wp == crown_point and back_point.state != WeakPoint.State.DESTROYED))

func _on_weak_point_destroyed() -> void:
	if weak_points.is_empty():
		return
	if weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.DESTROYED):
		_set_encounter(Encounter.DEFEATED)
	else:
		weak_point = crown_point
		_update_protection()

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if ruins != null:
		ruins.reset()
	if crown_point != null:
		weak_point = crown_point
	super(xf, use_xf)
	if back_point != null:
		back_point.reset()
		weak_point = back_point
	_update_protection()

func _debug_extra() -> String:
	return "ARGUS ruiny %s | zwab na płytę, uniknij stompu, przejdź galerią na grzbiet" % ("otwarte" if ruins != null and ruins.route_open else "zamknięte")
