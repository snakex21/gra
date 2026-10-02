extends Node3D
## Close-up of the Wanderer and Agro (procedural textures) in the Valus arena with art.
## Saves tests/output/characters_*.png. Run with tools/capture_screenshots.sh characters.

var tick := 0
var refs := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	InputSetup.ensure_defaults()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -Valley.SUN_DIRECTION.normalized(), Vector3.UP)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(env)
	ArenaArt._daylight(self)
	var w := Node3D.new()
	add_child(w)
	refs = ValusArena.build_encounter(w, false, 7, true)
	(refs.valus as Valus).debug_override = &"frozen"
	(refs.hud as PlayerHud).show_debug = false
	(refs.hud as PlayerHud).show_help = false
	(refs.debug_draw as Node3D).visible = false
	(refs.valus as Valus).debug_draw.visible = false
	(refs.horse as Horse).debug_draw.visible = false


func _physics_process(_delta: float) -> void:
	tick += 1
	var p: PlayerCharacter = refs.player
	var h: Horse = refs.horse
	var cam: PlayerCamera = refs.camera
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	var focus := (p.global_position + h.global_position) * 0.5 + Vector3.UP * 0.4
	if tick == 30:
		cam.global_position = focus + Vector3(3.2, 1.2, -2.6)
		cam.look_at(focus)
	if tick == 40:
		_shot("characters_01_side")
	if tick == 50:
		cam.global_position = focus + Vector3(-2.4, 1.0, 3.4)
		cam.look_at(focus)
	if tick == 60:
		_shot("characters_02_back")
	if tick == 70:
		get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	print("shot ", name)
