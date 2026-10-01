extends GameWorld
## Etap 8: the whole game. The temple in the valley, the beam of the sword, the three
## arenas behind their gates, the save. ``-- --new-game`` (or NEW_GAME=1) ignores the save.


func _ready() -> void:
	super()
	InputSetup.ensure_defaults()
	with_art = not OS.has_environment("NO_ART")
	start(OS.has_environment("NEW_GAME") or "--new-game" in OS.get_cmdline_user_args())
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset") and refs.has("encounter"):
		(refs.encounter as BossEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn") and player():
		player().respawn()
	elif event.is_action_pressed(&"ride_steer_mode") and player():
		player().riding.steer_relative = not player().riding.steer_relative
	elif event.is_action_pressed(&"debug_draw"):
		for k in ["debug_draw", "bow_draw"]:
			if refs.get(k) is Node3D:
				(refs[k] as Node3D).visible = not (refs[k] as Node3D).visible
