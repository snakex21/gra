class_name BasaranBot
extends QuadratusBot
## Uses only the same PlayerActions as QuadratusBot; adds lure + stationary vent shot.
func _position() -> void:
	var boss := quadratus as Basaran
	if _kneeling() or boss.vent_state == Basaran.VentState.EXPOSED:
		super()
		return
	_want_weapon(PlayerCharacter.Weapon.BOW)
	player.actions.attack_held = false
	player.actions.grab_held = false
	if _evade():
		return
	var best: BasaranGeyser
	for node in get_tree().get_nodes_in_group(&"basaran_geysers"):
		var vent := node as BasaranGeyser
		if best == null or vent.global_position.distance_to(boss.global_position) < best.global_position.distance_to(boss.global_position):
			best = vent
	if best == null:
		return
	# Wait beyond the vent, keeping the boss moving across its centre.
	var to := _flat(best.global_position - boss.global_position).normalized()
	if to.length() < 0.2:
		to = -boss.global_basis.z
	var spot := best.global_position + to * 16.0
	if _flat(spot - player.global_position).length() > 1.0:
		_run_around_to(spot)
	else:
		_look(boss.get_focus_point() - player.global_position)

func _best_shot() -> Dictionary:
	var boss := quadratus as Basaran
	if boss.vent_state != Basaran.VentState.EXPOSED:
		return {}
	var from := player.bow.bow_point(player)
	var best := {}
	for target in boss.arrow_targets:
		var p := target.world_point()
		var dir := PlayerBow.launch_direction(from, p, player.bow.speed_for(1.0))
		if dir == Vector3.ZERO:
			continue
		var facing := dir.dot(-target.world_normal())
		if best.is_empty() or facing > best.score:
			best = {"leg": target.tag, "dir": dir, "t": from.distance_to(p) / player.bow.speed_for(1.0), "dist": from.distance_to(p), "ready": target.enabled and facing > 0.2 and _clear_line(from, p), "score": facing}
	return best

func _on_back() -> void:
	_want_weapon(PlayerCharacter.Weapon.SWORD)
	var wp := quadratus.rump
	var a := player.actions
	if wp.state != WeakPoint.State.OPEN:
		a.grab_held = false
		a.attack_held = false
		if player.state == PlayerCharacter.State.GROUND and not quadratus.owns_body(player.get_support_body()):
			_enter(Phase.POSITION)
		return
	if player.is_climbing():
		a.grab_held = true
		if _grip_near_wp():
			_enter(Phase.STRIKE)
			return
		if player.grip.world_normal().y < 0.6:
			_look(quadratus.get_focus_point() - player.global_position)
		else:
			_look(wp.world_point() - player.grip.world_point())
		a.move = Vector2.ZERO if _hold_on() else Vector2(0, 0.8)
		return
	a.grab_held = false
	var d := _flat(wp.world_point() - player.global_position)
	if d.length() > 0.6:
		_run_to(wp.world_point(), 0.7)
	elif player.stamina.ratio() > 0.8:
		a.grab_held = true
