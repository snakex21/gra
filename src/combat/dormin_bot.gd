class_name DorminBot
extends ValusBot
var locks_completed := false
var back_completed := false
var _working_seal: DorminSeal

func setup(p_player: PlayerCharacter, p_valus: HumanoidBoss, p_encounter: BossEncounter) -> void:
	super(p_player, p_valus, p_encounter)
	p_encounter.encounter_reset.connect(func(_n: int) -> void:
		locks_completed = false
		back_completed = false
		_working_seal = null)

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	var c := valus as Dormin
	if not c._climb_open:
		time += delta
		player.actions.move = Vector2.ZERO
		player.actions.attack_held = false if _working_seal == null else player.actions.attack_held
		player.actions.grab_held = false
		if player.dead:
			player.actions.clear()
			return
		if _evade():
			player.actions.beam_held = false
			player.actions.attack_held = false
			return
		_puzzle(c)
		return
	if not locks_completed:
		locks_completed = true
		_enter(Phase.APPROACH_LEG)
	player.actions.beam_held = false
	super(delta)

func _puzzle(c: Dormin) -> void:
	_working_seal = null
	for seal in c.seals:
		if not seal.broken:
			_working_seal = seal
			break
	if _working_seal == null:
		return
	var seal := _working_seal
	var gap := 3.0 if seal.kind == DorminSeal.Kind.DAWN or (seal.kind == DorminSeal.Kind.SHADOW and seal.exposed_left <= 0) else .90
	var spot := seal.global_position + c._start_xf.basis.z * gap
	spot.y = c.arena_center.y + .95
	if _flat(spot - player.global_position).length() > .35:
		player.actions.attack_held = false
		player.actions.beam_held = seal.kind == DorminSeal.Kind.SHADOW and seal.exposed_left <= 0
		_run_to(spot)
		if seal.kind == DorminSeal.Kind.SHADOW and seal.exposed_left <= 0:
			player.actions.view_basis = Basis.looking_at(seal.global_position - SwordBeam.tip(player))
		return
	player.actions.beam_held = seal.exposed_left < 1.7 or seal.kind == DorminSeal.Kind.DAWN
	player.actions.view_basis = Basis.looking_at(seal.global_position - SwordBeam.tip(player))
	if seal.kind == DorminSeal.Kind.DAWN:
		return
	var sword := player.sword
	if seal.exposed_left >= 1.7:
		match sword.state:
			PlayerSword.State.READY:
				player.actions.attack_held = true
			PlayerSword.State.CHARGE:
				player.actions.attack_held = sword.charge < (.25 if seal.kind == DorminSeal.Kind.SHADOW else 1.0)
			_:
				player.actions.attack_held = false

func _climb_body() -> void:
	var c := valus as Dormin
	var sigil := c.back_sigil
	if sigil.state != WeakPoint.State.DESTROYED and player.is_climbing() and _grip_bone() == &"spine":
		player.actions.grab_held = true
		var segment := player.grip.body as BodySegment
		var normal := player.grip.world_normal()
		var goal := sigil.world_point()
		if normal.dot(segment.target_transform.basis.z) < .4:
			# Wrap round a side before aiming at the rear sigil, never through stone.
			goal = segment.target_transform * Vector3(1.92, player.grip.local_point.y, 1.32)
		var to := goal - player.grip.world_point()
		to -= normal * to.dot(normal)
		if (player.grip.world_point().distance_to(sigil.world_point()) > sigil.radius * .65 or goal != sigil.world_point()) and player.sword.state == PlayerSword.State.READY:
			var direction := to.normalized()
			var right := player.climb_up.cross(normal)
			player.actions.move = Vector2(direction.dot(right), direction.dot(player.climb_up)).normalized() * .6
			player.actions.attack_held = false
			return
		if _hold_on():
			player.actions.move = Vector2.ZERO
			return
		match player.sword.state:
			PlayerSword.State.READY:
				player.actions.attack_held = true
			PlayerSword.State.CHARGE:
				player.actions.attack_held = player.sword.charge < 1
			_:
				player.actions.attack_held = false
		return
	if sigil.state == WeakPoint.State.DESTROYED:
		back_completed = true
	super()
