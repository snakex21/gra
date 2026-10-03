extends Node3D
var refs := {}
var players: Array[PlayerCharacter] = []
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(.015, .025, .03)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color(.2, .28, .32)
	sky.environment.ambient_light_energy = .16
	add_child(sky)
	refs = DevilArena.build_encounter(self, true, 109, not OS.has_environment("NO_ART"))
	players = refs.players
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"):
		refs.encounter.reset_encounter()
