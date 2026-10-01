extends Node3D
## Etap 6: Quadratus. The arena, Quadratus, Agro and the player are built in code
## (QuadratusArena.build_encounter). F5 resets the encounter, Tab switches sword / bow.

var players: Array[PlayerCharacter] = []
var refs := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	refs = QuadratusArena.build_encounter(self, true)
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var q: Quadratus = refs.quadratus
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as BossEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn"):
		(refs.player as PlayerCharacter).respawn()
	elif event.is_action_pressed(&"debug_colossus_mode"):
		q.cycle_debug_override()
	elif event.is_action_pressed(&"debug_draw"):
		var on := not q.debug_draw.visible
		q.debug_draw.visible = on
		(refs.bow_draw as BowDebugDraw).visible = on
		(refs.horse as Horse).debug_draw.visible = on
	elif event.is_action_pressed(&"ride_steer_mode"):
		(refs.player as PlayerCharacter).riding.steer_relative = not (refs.player as PlayerCharacter).riding.steer_relative
