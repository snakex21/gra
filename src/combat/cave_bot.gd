class_name CaveBot
extends ValusBot
## The climbing driver plus the cave's light lure. Only writes PlayerActions.
func _physics_process(delta: float) -> void:
	super(delta)
	if not is_instance_valid(player) or not is_instance_valid(valus):
		return
	var cave := valus as CaveColossus
	if cave and cave.shelter == CaveColossus.Shelter.HIDDEN and not player.is_climbing() and not player.dead:
		player.actions.move = Vector2.ZERO
		player.actions.beam_held = true
		player.actions.view_basis = Basis.looking_at(cave.get_focus_point() - SwordBeam.tip(player))
	else:
		player.actions.beam_held = false
