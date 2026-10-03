extends Node3D
## Etap 7: Gaius, the knight with a sword. The arena, Gaius, Agro and the player are
## built in code (GaiusArena.build_encounter). F5 resets the encounter.

var players: Array[PlayerCharacter] = []
var refs := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	refs = GaiusArena.build_encounter(self, true, 13, not OS.has_environment("NO_ART"))
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var valus: Gaius = refs.gaius
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as BossEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn"):
		(refs.player as PlayerCharacter).respawn()
	elif event.is_action_pressed(&"debug_colossus_mode"):
		valus.cycle_debug_override()
	elif event.is_action_pressed(&"debug_draw"):
		var on := not (refs.debug_draw as CombatDebugDraw).visible
		(refs.debug_draw as CombatDebugDraw).visible = on
		valus.debug_draw.visible = on
		(refs.horse as Horse).debug_draw.visible = on
	elif event.is_action_pressed(&"ride_steer_mode"):
		(refs.player as PlayerCharacter).riding.steer_relative = not (refs.player as PlayerCharacter).riding.steer_relative
