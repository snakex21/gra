extends Node3D
var players: Array[PlayerCharacter] = []
var refs := {}
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	refs = PhalanxArena.build_encounter(self, true, 101, not OS.has_environment("NO_ART"))
	players.append(refs.player)
	if DisplayServer.get_name() != "headless": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"): refs.encounter.reset_encounter()
	elif event.is_action_pressed(&"respawn"): refs.player.respawn()
