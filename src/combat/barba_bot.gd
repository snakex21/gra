class_name BarbaBot
extends ValusBot
## Drives the cover/beard route using only ordinary PlayerActions.
var cover_reached := false
var beard_attached := false

func setup(p_player: PlayerCharacter, p_valus: HumanoidBoss, p_encounter: BossEncounter) -> void:
	super(p_player, p_valus, p_encounter)
	p_encounter.encounter_reset.connect(func(_n: int) -> void:
		beard_attached = false
		cover_reached = false)

func _physics_process(delta: float) -> void:
	var c := valus as Barba
	if c == null or player.dead or c.is_defeated() or beard_attached:
		super(delta)
		return
	time += delta
	phase_time += delta
	player.actions.attack_held = false
	player.actions.move = Vector2.ZERO
	if c.search_phase != Barba.SearchPhase.EXPOSED or c.kneel_weight < 0.97:
		player.actions.grab_held = false
		if _dist_to(c.cover_point()) > 0.5:
			_run_to(c.cover_point())
		else:
			cover_reached = true
		return
	var seg := _seg(&"head")
	var beard := seg.target_transform * Vector3(0, -7.2, -1.85)
	beard.y = c.global_position.y + 0.95
	if _dist_to(beard) > 4.0:
		player.actions.grab_held = false
		_run_to(beard)
		return
	_look(beard - player.global_position)
	player.actions.move = Vector2(0, 0.7)
	player.actions.grab_held = true
	if not player.is_climbing() and int(time * 60) % 90 == 0:
		player.actions.press_jump()
	if verbose and int(time * 60) % 300 == 0:
		_log("beard p %s target %s head %s grip %s" % [player.global_position, beard, seg.target_transform, player.is_climbing()])
	if player.is_climbing():
		beard_attached = true
		stats.grabs += 1
		_enter(Phase.CLIMB_HEAD)

func _reroute() -> void:
	if player.is_climbing() or valus.region_of(player) == &"head":
		super()
	else:
		beard_attached = false
		_enter(Phase.ENTER)
