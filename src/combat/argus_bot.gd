class_name ArgusBot
extends ValusBot
## Terrain puzzle and gallery entry, then the stable humanoid climb driver.
var route_stage := 0
var gallery_entries := 0
var _gallery_jumped := false

func setup(p_player: PlayerCharacter, p_argus: HumanoidBoss, p_encounter: BossEncounter) -> void:
	super(p_player, p_argus, p_encounter)
	p_encounter.encounter_reset.connect(func(_n: int) -> void:
		route_stage = 0
		gallery_entries = 0)
	p_encounter.encounter_reset.connect(func(_n: int) -> void: _gallery_jumped = false)

func _approach_leg() -> void:
	var boss := valus as Argus
	var ruins := boss.ruins
	var a := player.actions
	a.grab_held = false
	if ruins == null:
		return
	if player.weapon != PlayerCharacter.Weapon.SWORD:
		a.press_switch_weapon()
	if player.is_riding():
		a.grab_held = true
		if int(time * 60.0) % 20 == 0:
			a.press_interact()
		return
	if player.is_climbing() and boss.owns_body(player.grip.body):
		a.grab_held = true
		stats.grabs += 1
		_enter(Phase.STRIKE if boss.back_point.state != WeakPoint.State.DESTROYED else Phase.CLIMB_BODY)
		return
	var local := ruins.to_local(player.global_position)
	if not ruins.activated and route_stage > 0 and (boss.attack == null or boss.attack.is_done()) and phase_time > 10.0:
		route_stage = 0
	if route_stage == 0:
		var bait := ruins.to_global(ArgusRuins.PLATE) + Vector3.UP * 0.87
		if boss.attack != null and boss.attack.kind == HumanoidBoss.STOMP and boss.attack.phase == ColossusAttack.Phase.TELEGRAPH:
			route_stage = 1
			stats.evades += 1
		elif ruins.activated:
			route_stage = 1
		else:
			if _dist_to(bait) > 0.45:
				_run_to(bait)
			return
	if route_stage == 1:
		var safe := ruins.to_global(Vector3(10, 0.95, 50))
		_run_to(safe)
		if _dist_to(safe) < 1.0:
			route_stage = 2
		return
	if route_stage == 2:
		var entry := ruins.to_global(Vector3(18, 0.95, 48))
		_run_to(entry)
		if _dist_to(entry) < 0.8 and ruins.route_open:
			route_stage = 3
		return
	if route_stage == 3:
		var top := ruins.to_global(Vector3(18, 12.95, -6.5))
		_run_to(top)
		if local.z < -1.8 and local.y > 12.0 and not _gallery_jumped and player.state == PlayerCharacter.State.GROUND:
			a.press_jump()
			_gallery_jumped = true
		if _dist_to(top) < 0.8 and local.y > 12.3 and player.state == PlayerCharacter.State.GROUND:
			route_stage = 4
		return
	if route_stage == 4:
		var gallery := ruins.to_global(Vector3(0, 12.95, -6))
		_run_to(gallery, 0.8)
		if _dist_to(gallery) < 0.8:
			route_stage = 5
			gallery_entries += 1
		return
	var point := boss.back_point.world_point()
	_look(point - player.global_position)
	a.move = Vector2(0, 0.65)
	a.grab_held = true

func _strike(delta: float) -> void:
	var boss := valus as Argus
	if boss.weak_point == boss.crown_point:
		if _grip_bone() not in [&"head", &"neck"]:
			_enter(Phase.CLIMB_BODY)
			return
		super(delta)
		return
	var a := player.actions
	a.grab_held = true
	if not player.is_climbing():
		a.attack_held = false
		_reroute()
		return
	var wp := boss.back_point
	var sw := player.sword
	var normal := player.grip.world_normal()
	var to := wp.world_point() - player.grip.world_point()
	to -= normal * to.dot(normal)
	if to.length() > 0.65 and sw.state == PlayerSword.State.READY and not _hold_on():
		var right := player.climb_up.cross(normal)
		a.move = Vector2(to.dot(right), to.dot(player.climb_up)).normalized() * 0.7
		a.attack_held = false
		return
	if _hold_on() and sw.state != PlayerSword.State.CHARGE:
		a.attack_held = false
		return
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = true
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0
		_:
			a.attack_held = false

func _finish(won: bool, why: String) -> void:
	super(won, why)
	result["gallery_entries"] = gallery_entries
	result["terrain_impacts"] = (valus as Argus).ruins.impacts
