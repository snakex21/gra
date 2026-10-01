class_name GaiusBot
extends ValusBot
## Scripted test driver for the Gaius fight. Same rules as ValusBot (PlayerActions only,
## timeouts recorded as stalls); its own start of the route:
##
##   stand in front, on the sword side (provoke the slam) -> step out of the telegraphed
##   slam -> the blade is stuck: run up it -> grab the wrapped fist -> forearm -> upper arm
##   -> crawl over the fur pauldron onto the shoulders -> (ValusBot from here: rest, mane,
##   head) -> on the helmet: charged strikes until it breaks -> weak point.

var gaius: Gaius
var stats_gaius := {"slams_provoked": 0, "blade_runs": 0, "helmet_strikes": 0}
var _blade_hop := 0.0


func setup(p_player: PlayerCharacter, p_valus: HumanoidBoss, p_encounter: BossEncounter) -> void:
	super(p_player, p_valus, p_encounter)
	gaius = p_valus as Gaius


## Start of the route: provoke a slam, then get onto the stuck blade.
func _approach_leg() -> void:
	var a := player.actions
	a.grab_held = false
	if _on_blade():
		stats_gaius.blade_runs += 1
		_enter(Phase.GRAB_LEG)
		return
	if gaius.sword_stuck():
		# Run up to the tip from in front of it, along the blade, and hop on.
		var tip := gaius.blade_tip()
		var hand := (gaius._seg_by_bone[&"hand_r"] as BodySegment).target_transform.origin
		var along := _flat(hand - tip).normalized()
		var run_in := tip - along * 2.5
		var to_run_in := _flat(run_in - player.global_position)
		var behind_tip := _flat(player.global_position - tip).dot(along) < 0.5
		if behind_tip and to_run_in.length() > 1.2 and _flat(player.global_position - tip).length() > 2.0:
			_run_to(run_in)
			return
		_look(along)
		a.move = Vector2(0, 1)
		_blade_hop += get_physics_process_delta_time()
		if _blade_hop > 0.35 and player.state == PlayerCharacter.State.GROUND:
			_blade_hop = 0.0
			a.press_jump()
		return
	if _evade():
		return
	if player.stamina.ratio() < 0.9 and _dist_to(gaius.global_position) > 12.0:
		return  # catch breath first (just fell off)
	# In front on the sword side, in the slam band: it will bring the sword down here.
	var spot := gaius.global_transform * Vector3(-2.5, 0, -15.0)
	spot.y = player.global_position.y
	if _flat(spot - player.global_position).length() > 1.0:
		_run_to(spot)
	else:
		_look(gaius.global_position - player.global_position)


func _on_blade() -> bool:
	var s: Object = player.get_support_body()
	return s is BodySegment and (s as BodySegment).bone_name == &"sword" and gaius.owns_body(s)


## Up the blade to the fist, grab it.
func _grab_leg() -> void:
	var a := player.actions
	if player.is_climbing():
		stats.grabs += 1
		_log("grabbed %s" % _grip_bone())
		_enter(Phase.CLIMB_BODY)
		return
	if not gaius.sword_stuck() and not _on_blade():
		_enter(Phase.APPROACH_LEG)
		return
	# Up the blade to the wrapped fist and grab it (the round forearm is no path to walk).
	var fist := (gaius._seg_by_bone[&"hand_r"] as BodySegment).target_transform * Vector3(0, -0.9, 0)
	var to := fist - player.global_position
	_look(to)
	a.move = Vector2(0, 1)
	a.grab_held = to.length() < 2.6
	var on_arm: bool = player.get_support_body() is BodySegment and gaius.owns_body(player.get_support_body())
	if not on_arm and player.state == PlayerCharacter.State.GROUND and phase_time > 1.0:
		_enter(Phase.APPROACH_LEG)


func _climb_body() -> void:
	var a := player.actions
	if player.is_climbing() and _grip_bone() == &"chest" and player.grip.world_normal().y > 0.75:
		# Over the pauldron: crawl in onto the shoulders, then stand (never on the edge).
		var chest := (player.grip.body as BodySegment).target_transform
		var lp := chest.affine_inverse() * player.grip.world_point()
		_look(chest * Vector3(0, 2.8, 0) - player.global_position)
		a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)
		a.grab_held = absf(lp.x) > 1.6 or _hold_on()
		return
	if player.is_climbing() and _grip_bone() in [&"hand_r", &"forearm_r", &"upper_arm_r"]:
		# Up the sword arm: head for the shoulder, not the body's centre.
		a.grab_held = true
		var shoulder := (gaius._seg_by_bone[&"upper_arm_r"] as BodySegment).target_transform.origin + Vector3.UP
		_look(shoulder - player.global_position)
		a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)
		return
	super()


## On the head: while the helmet holds, stand on it and strike it (charged).
func _on_head() -> void:
	if gaius.helmet.is_broken:
		super()
		return
	var a := player.actions
	if player.is_climbing():
		if _grip_bone() != &"head":
			_reroute()
			return
		# Hanging on the back of the head: climb on over the helmet's edge.
		a.grab_held = true
		a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)
		return
	if gaius.region_of(player) != &"head" and player.state != PlayerCharacter.State.AIR:
		_reroute()
		return
	var target := gaius.helmet.world_point()
	var d := _flat(target - player.global_position)
	if d.length() > 0.5 and player.sword.state == PlayerSword.State.READY:
		_run_to(target, 0.4)
		a.attack_held = false
		return
	_look(gaius.global_basis.z * -1.0)
	var sw := player.sword
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = not _shaking()
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0
		_:
			a.attack_held = false


func _reroute() -> void:
	if not player.is_climbing() and _on_blade():
		_enter(Phase.GRAB_LEG)
		return
	if player.is_climbing() and _grip_bone() == &"head" and not gaius.helmet.is_broken:
		_enter(Phase.CLIMB_HEAD)
		return
	super()


func _climb_head() -> void:
	if not gaius.helmet.is_broken and not player.is_climbing() and gaius.region_of(player) == &"head":
		_enter(Phase.ON_HEAD)
		return
	super()


func _on_struck(r: Dictionary) -> void:
	if String(r.get("reason", "")).begins_with("armor"):
		stats_gaius.helmet_strikes += 1
		_log("helmet %s" % r.reason)
		return
	super(r)


func _finish(won: bool, why: String) -> void:
	stats_gaius.slams_provoked = int(gaius.stats.attacks.get(Gaius.SWORD_SLAM, 0))
	stats.merge(stats_gaius, true)
	super(won, why)
