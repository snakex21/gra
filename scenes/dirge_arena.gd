extends Node3D
var refs := {}
var players: Array[PlayerCharacter] = []
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	refs = DirgeArena.build_encounter(self, true)
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as BossEncounter).reset_encounter()
