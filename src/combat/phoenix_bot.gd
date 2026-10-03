class_name PhoenixBot
extends WingedGuardianBot
var water_lure_completed := false
func _can_board() -> bool:
	return guardian._patch_open and (guardian as Phoenix).phase == Phoenix.Phase.COOLED
func _puzzle(_delta: float) -> void:
	var c := guardian as Phoenix
	var stream: Vector3 = Phoenix.STREAMS_LOCAL[0]
	var away := WingedGuardianBot._flat(stream - c._local_at).normalized()
	if away.length() < .1:
		away = Vector3(-.8, 0, -.6)
	var safe := c._spawn_xf * (stream + away * 9 + Vector3.UP * .95)
	_go(safe)
	if c.stats.coolings > 0:
		water_lure_completed = true

func _physics_process(delta: float) -> void:
	super(delta)
	if player == null or phase == Phase.DONE:
		return
	var c := guardian as Phoenix
	if c.phase == Phoenix.Phase.REHEATING and c.phase_time > 3:
		player.actions.grab_held = false
		player.actions.attack_held = false
		var away := WingedGuardianBot._flat(player.global_position - c.global_position).normalized()
		if away.length() < .1:
			away = c.global_basis.z
		_go(player.global_position + away * 8)
		_phase(Phase.PUZZLE)
