extends Node3D
var refs := {}
var players: Array[PlayerCharacter] = []
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.2, 0.21)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.77, 0.7)
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	refs = KuromoriArena.build_encounter(self, true)
	players = refs.players
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"):
		refs.encounter.reset_encounter()
