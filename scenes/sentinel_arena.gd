extends Node3D
## Etap 5: the first complete boss fight. The arena, the Sentinel, Agro and the player are
## built in code (SentinelArena.build_encounter). F5 resets the encounter.

var players: Array[PlayerCharacter] = []
var refs := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	refs = SentinelArena.build_encounter(self, true)
	players.append(refs.player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var sentinel: Sentinel = refs.sentinel
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as SentinelEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn"):
		(refs.player as PlayerCharacter).respawn()
	elif event.is_action_pressed(&"debug_colossus_mode"):
		sentinel.cycle_debug_override()
	elif event.is_action_pressed(&"debug_draw"):
		var on := not (refs.debug_draw as CombatDebugDraw).visible
		(refs.debug_draw as CombatDebugDraw).visible = on
		sentinel.debug_draw.visible = on
		(refs.horse as Horse).debug_draw.visible = on
	elif event.is_action_pressed(&"ride_steer_mode"):
		(refs.player as PlayerCharacter).riding.steer_relative = not (refs.player as PlayerCharacter).riding.steer_relative
