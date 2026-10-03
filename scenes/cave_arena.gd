extends Node3D
var refs := {}
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.015, 0.025, 0.03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.2, 0.28, 0.32)
	env.environment.ambient_light_energy = 0.12
	add_child(env)
	refs = CaveArena.build_encounter(self, true, not OS.has_environment("NO_ART"))
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"):
		(refs.encounter as BossEncounter).reset_encounter()
