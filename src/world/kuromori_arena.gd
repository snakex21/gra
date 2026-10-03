class_name KuromoriArena
## Three-level courtyard. North gallery has a gap for the wall-climbing lizard.
const KUROMORI_START := Vector3(0, 1.5, 0)
const PLAYER_START := Vector3(0, 0.95, 18)
const HORSE_START := Vector3(4, 0, 30)

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.44, 0.42, 0.32)
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.62, 0.58, 0.45)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(120, 2, 120), stone)
	TerrainKit.box(parent, Vector3(0, 8, -25), Vector3(54, 16, 2), pale)
	for side in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 26, 8, 0), Vector3(2, 16, 52), pale)
		TerrainKit.box(parent, Vector3(side * 16, 8, 25), Vector3(22, 16, 2), pale)
	for level in [4.0, 8.0, 12.0]:
		for side in [-1.0, 1.0]:
			TerrainKit.box(parent, Vector3(side * 23, level - 0.3, 0), Vector3(4, 0.6, 50), pale)
			TerrainKit.box(parent, Vector3(side * 17, level - 0.3, -22), Vector3(14, 0.6, 4), pale)
		TerrainKit.box(parent, Vector3(0, level - 0.3, 22), Vector3(48, 0.6, 4), pale)
	# The stair tread is visual; a continuous collision ramp keeps the ground
	# controller from catching on 48 vertical risers. All three galleries are reachable.
	var ramp := TerrainKit.ramp(parent, Vector3(19.6, 0, 20.8), 36.0, rad_to_deg(atan(12.0 / 36.0)), 2.7, stone)
	for child in ramp.get_children():
		if child is MeshInstance3D:
			child.visible = false
	for i in 48:
		var y := (i + 1) * 0.25
		var step := TerrainKit.box(parent, Vector3(19.6, y * 0.5, 20.0 - i * 0.75), Vector3(2.7, y, 0.8), stone)
		step.collision_layer = 0
	return {"kuromori": [KUROMORI_START, 0.0], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}

static func dress(parent: Node3D) -> void:
	for y in [4.0, 8.0, 12.0]:
		for x in [-15.0, -6.0, 6.0, 15.0]:
			ArenaArt.encounter_prop(parent, "kuromori_gallery_fragment", Vector3(x, y, 25))

static func build_encounter(parent: Node3D, with_input := false, seed := 67, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var boss := Kuromori.new()
	boss.name = "Kuromori"
	boss.brain_seed = seed
	boss.position = KUROMORI_START
	parent.add_child(boss)
	boss.reset_encounter()
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(HORSE_START, 0.0)
	var player := PlayerCharacter.new()
	player.name = "Player1"
	parent.add_child(player)
	player.global_position = parent.global_transform * PLAYER_START
	player.spawn_transform = player.global_transform
	var camera := PlayerCamera.new()
	camera.player = player
	camera.focus_target = boss
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var input: FlatInputSource
	if with_input:
		input = FlatInputSource.new()
		input.actions = player.actions
		input.view = camera
		parent.add_child(input)
	var encounter := BossEncounter.new()
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [player]
	encounter.setup(boss, players, horse)
	var hud := PlayerHud.new()
	hud.player = player
	hud.colossus = boss
	hud.camera = camera
	hud.encounter = encounter
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	hud.message = boss.encounter_hint()
	boss.phase_changed.connect(func(_phase: Kuromori.Phase) -> void: hud.message = boss.encounter_hint())
	return {"kuromori": boss, "colossus": boss, "player": player, "players": players, "horse": horse, "camera": camera, "input": input, "encounter": encounter, "hud": hud, "points": points}
