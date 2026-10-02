extends Node3D
## Etap 11: Avion, the great bird: climb a tower, catch a wing as it swoops past, climb
## onto its back and hold on when it rolls. The arena, Avion, Agro and the player are built in code
## (AvionArena.build_encounter). F5 resets the encounter.

var players: Array[PlayerCharacter] = []
var refs := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	refs = AvionArena.build_encounter(self, true, 41, not OS.has_environment("NO_ART"))
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var colossus: Avion = refs.avion
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as BossEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn"):
		(refs.player as PlayerCharacter).respawn()
	elif event.is_action_pressed(&"debug_colossus_mode"):
		colossus.cycle_debug_override()
	elif event.is_action_pressed(&"debug_draw"):
		var on := not colossus.debug_draw.visible
		colossus.debug_draw.visible = on
		(refs.horse as Horse).debug_draw.visible = on
	elif event.is_action_pressed(&"ride_steer_mode"):
		(refs.player as PlayerCharacter).riding.steer_relative = not (refs.player as PlayerCharacter).riding.steer_relative
