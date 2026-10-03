extends Node3D
var refs := {}
var players: Array[PlayerCharacter] = []
func _ready() -> void:
	InputSetup.ensure_defaults()
	TrialMenu.attach(self)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_SKY
	sky.environment.sky = Sky.new()
	sky.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	refs = PhoenixArena.build_encounter(self, true, 113, not OS.has_environment("NO_ART"))
	players = refs.players
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"encounter_reset"):
		refs.encounter.reset_encounter()
