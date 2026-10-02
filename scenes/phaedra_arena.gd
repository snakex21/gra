extends Node3D
## Etap 9: Phaedra, the shy long-necked colossus: hide in a tunnel, wait for its head and
## climb onto its neck. The arena, Phaedra, Agro and the player are built in code
## (PhaedraArena.build_encounter). F5 resets the encounter.

var players: Array[PlayerCharacter] = []
var refs := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	refs = PhaedraArena.build_encounter(self, true, 17, not OS.has_environment("NO_ART"))
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var colossus: Phaedra = refs.phaedra
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
