class_name DevilBot
extends WingedGuardianBot
var light_completed := false
func _puzzle(_delta: float) -> void:
	var c := guardian as Devil
	if c.phase in [Devil.Phase.HANGING, Devil.Phase.WARNING]:
		var safe := c._spawn_xf * Vector3(0, .95, 12)
		if _flat(safe - player.global_position).length() > 1.0:
			_go(safe)
		player.actions.beam_held = true
		player.actions.view_basis = Basis.looking_at(c.get_focus_point() - SwordBeam.tip(player))
	else:
		player.actions.move = Vector2.ZERO
	if c.stats.light_breaks > 0:
		light_completed = true
