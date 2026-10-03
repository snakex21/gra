class_name SpiderArena
const SPIDER_START := Vector3.ZERO
const SPIDER_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 45)
const HORSE_START := Vector3(8, 0, 42)

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.39, 0.4, 0.34)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	for side: float in [-1, 1]:
		for z: float in [-35, 0, 35]:
			TerrainKit.box(parent, Vector3(side * 34, 6, z), Vector3(3, 12, 3), stone)
	for at in Spider.ANCHORS:
		TerrainKit.box(parent, at + Vector3.DOWN * 1.25, Vector3(2, 0.3, 2), stone)
	return {"spider": [SPIDER_START, SPIDER_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "anchors": Spider.ANCHORS, "foot": Spider.FOOT}

static func dress(_parent: Node3D) -> void:
	pass

static func spawn(parent: Node3D, brain_seed := 97) -> Spider:
	var boss := Spider.new()
	boss.name = "Spider"
	boss.brain_seed = brain_seed
	parent.add_child(boss)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, SPIDER_YAW), SPIDER_START)
	boss.reset_encounter(xf, true)
	return boss

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 97, with_art := false) -> Dictionary:
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
	camera.player = player
	camera.focus_target = boss
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
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
	hud.message = "Spider więzi przejście w ruinach. Przetnij trzy świecące kotwice łukiem lub mieczem. Unikaj prostej sieci; po opuszczonym odnóżu wejdź na dwa znaki."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"spider": boss, "colossus": boss, "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": null}
