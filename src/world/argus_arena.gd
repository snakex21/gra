class_name ArgusArena
## Open entrance +Z; the ruined galleries frame a guardian standing in the passage.
const ARGUS_START := Vector3.ZERO
const ARGUS_YAW := PI
const PLAYER_START := Vector3(0, 0.95, 75)
const HORSE_START := Vector3(8, 0, 72)

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.45, 0.36)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	var ruins := ArgusRuins.new()
	ruins.name = "ArgusRuins"
	parent.add_child(ruins)
	for side: float in [-1.0, 1.0]:
		for z: float in [-55.0, -20.0, 20.0]:
			TerrainKit.box(parent, Vector3(side * 36, 7, z), Vector3(3, 14, 3), stone)
	return {"argus": [ARGUS_START, ARGUS_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "plate": ArgusRuins.PLATE, "gallery": Vector3(0, 12, -6)}

static func dress(_parent: Node3D) -> void:
	pass

static func spawn(parent: Node3D, brain_seed := 79) -> Argus:
	var boss := Argus.new()
	boss.name = "Argus"
	boss.brain_seed = brain_seed
	parent.add_child(boss)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, ARGUS_YAW), ARGUS_START)
	boss.teleport(xf.origin, xf.basis.get_euler().y)
	boss.reset_encounter(xf, true)
	return boss

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 79, with_art := false) -> Dictionary:
	var points := build(parent)
	var boss := spawn(parent, brain_seed)
	if with_art:
		dress(parent)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(parent.global_transform * HORSE_START, parent.global_rotation.y)
	var player := PlayerCharacter.new()
	player.name = "Player1"
	parent.add_child(player)
	player.global_position = parent.global_transform * PLAYER_START
	player.facing = -parent.global_basis.z
	player.actions.view_basis = parent.global_basis
	player.spawn_transform = player.global_transform
	player.reset_physics_interpolation()
	var camera := PlayerCamera.new()
	camera.name = "Camera1"
	camera.player = player
	camera.focus_target = boss
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
	encounter.name = "Encounter"
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [player]
	encounter.setup(boss, players, horse)
	var input: FlatInputSource
	if with_input:
		input = FlatInputSource.new()
		input.actions = player.actions
		input.view = camera
		parent.add_child(input)
	var hud := PlayerHud.new()
	hud.player = player
	hud.colossus = boss
	hud.camera = camera
	hud.horse = horse
	hud.encounter = encounter
	hud.show_debug = false
	hud.show_help = false
	hud.message = "Argus blokuje przejście. Zwab stomp na oznaczoną płytę, uniknij go, przejdź podniesioną galerią na grzbiet."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"argus": boss, "colossus": boss, "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": boss.debug_draw, "ruins": boss.ruins}
