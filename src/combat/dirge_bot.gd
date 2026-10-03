class_name DirgeBot
extends HydrusBot
## Mounted arrow puzzle followed by the shared physical serpent climb/strike driver.
## No teleport, target.evaluate, WeakPoint.try_hit or direct damage is used.
var horse: Horse
var mounted_shots := 0
var _jump_timer := 0.0
var _last_grab_jump := -999.0

func setup(p_player: PlayerCharacter, p_dirge: Hydrus, p_encounter: BossEncounter, p_horse: Horse = null) -> void:
	super(p_player, p_dirge, p_encounter)
	horse = p_horse
	player.bow.shot.connect(func(_arrow: Dictionary) -> void:
		if player.is_riding():
			mounted_shots += 1)

func _enter_lake() -> void:
	_wait()

func _wait() -> void:
	var boss := hydrus as Dirge
	var a := player.actions
	a.move = Vector2.ZERO
	a.attack_held = false
	if player.is_climbing():
		if hydrus.owns_body(player.grip.body):
			stats.grabs += 1
			_enter(Phase.CLIMB)
		else:
			a.grab_held = false
		return
	if boss.pursuit == Dirge.Pursuit.STUNNED:
		if player.is_riding():
			a.grab_held = true
			if horse.controller.speed < 1.5 and int(time * 60.0) % 20 == 0:
				a.press_interact()
			return
		_weapon(PlayerCharacter.Weapon.SWORD)
		a.grab_held = false
		var tuft := _nearest_tuft()
		if tuft == Vector3.INF:
			return
		var distance := _flat(tuft - player.global_position).length()
		if distance > 1.25:
			_go(tuft, 1.0)
		else:
			_look(tuft - player.global_position)
			a.move = Vector2(0, 0.5)
			a.grab_held = true
			if player.state == PlayerCharacter.State.GROUND and time - _last_grab_jump > 1.5:
				a.press_jump()
				_last_grab_jump = time
		return
	a.grab_held = false
	if not player.is_riding():
		if horse == null:
			return
		var seat := horse.saddle_transform().origin
		if _flat(seat - player.global_position).length() < 2.0:
			a.press_interact()
		else:
			_go(seat)
		return
	if player.riding.phase != PlayerRiding.Phase.RIDING:
		return
	_weapon(PlayerCharacter.Weapon.BOW)
	# First straight stretch leads the blind charge into the far wall.
	var c := horse.controller
	var local := boss.arena_basis.inverse() * (player.global_position - boss.arena_center)
	var goal := boss.arena_center + boss.arena_basis * Vector3(42, 0, 82)
	if local.z > 70:
		goal = boss.arena_center + boss.arena_basis * Vector3(65, 0, 70)
	var to := _flat(goal - player.global_position)
	if boss.pursuit == Dirge.Pursuit.BLINDED:
		_look(to)
		a.move = Vector2(0, 1)
		return
	var target: ArrowTarget
	for eye in boss.eye_targets:
		if target == null or eye.world_point().distance_to(player.global_position) < target.world_point().distance_to(player.global_position):
			target = eye
	if target != null and target.enabled and player.global_position.distance_to(target.world_point()) < 70.0:
		var from := player.bow.bow_point(player)
		var p := target.world_point()
		var v := (p - target.previous_frame() * target.local_point) / get_physics_process_delta_time()
		var relative := v - player.velocity
		var flight := from.distance_to(p) / player.bow.speed_for(1.0)
		var aim := p
		for i in 4:
			aim = p + relative * flight
			flight = from.distance_to(aim) / player.bow.speed_for(1.0)
		var dir := PlayerBow.launch_direction(from, aim, player.bow.speed_for(1.0))
		if dir != Vector3.ZERO:
			a.view_basis = Basis.looking_at(dir)
			a.aim_origin = from
			a.attack_held = player.bow.state not in [PlayerBow.State.RELEASE, PlayerBow.State.RECOVERY] and player.bow.state != PlayerBow.State.AIM
			if player.bow.is_aiming():
				var angle := c.forward().signed_angle_to(to.normalized(), Vector3.UP)
				a.move = Vector2(clampf(-angle, -0.4, 0.4), 0)
		else:
			_look(to)
			a.move = Vector2(0, 1)
	else:
		_look(to)
		a.move = Vector2(0, 1)
	if time - _jump_timer > 0.65 and c.speed < 12.0:
		a.press_jump()
		_jump_timer = time

func _hold_on() -> bool:
	return player.balance.state >= Balance.State.STUMBLE or hydrus._flinch_t < 1.2

func _nearest_tuft() -> Vector3:
	var best := Vector3.INF
	var boss := hydrus as Dirge
	for seg in boss.segments:
		for child in seg.get_children():
			if child is ClimbPatch and absf(child.position.x) > 1.5:
				var point: Vector3 = seg.target_transform * (child as ClimbPatch).position
				# The outside of the tuft, not the inside of a solid segment.
				point += seg.target_transform.basis.x * signf(child.position.x) * 0.85
				if best == Vector3.INF or _flat(point - player.global_position).length() < _flat(best - player.global_position).length():
					best = point
	return best

func _weapon(wanted: PlayerCharacter.Weapon) -> void:
	if player.weapon != wanted:
		player.actions.press_switch_weapon()

func _finish(won: bool, why: String) -> void:
	super(won, why)
	result["mounted_shots"] = mounted_shots
	result["eye_hits"] = (hydrus as Dirge).eye_hits
	result["wall_impacts"] = (hydrus as Dirge).wall_impacts
