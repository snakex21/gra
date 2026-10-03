class_name BasaranArena
## Basaran seals the volcanic crossing under Dormin's influence.
const BASARAN_START := Vector3(0, 0, -28)
const PLAYER_START := Vector3(0, 0.95, 46)
const HORSE_START := Vector3(4.5, 0, 43)
const GEYSERS := [Vector3(0, 0, 0), Vector3(-32, 0, -20)]

static func build(parent: Node3D) -> Dictionary:
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.25, 0.24, 0.2)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(240, 2, 240), ground).name = "VolcanicGround"
	for i in GEYSERS.size():
		var vent := BasaranGeyser.new()
		vent.name = "Geyser%d" % (i + 1)
		vent.position = GEYSERS[i]
		vent.offset = i * 8.0
		parent.add_child(vent)
	for i in 12:
		var a := TAU * i / 12.0
		if i == 3:
			continue # The continuous world's entrance comes from local +Z.
		var h := 8.0 + i % 4
		TerrainKit.box(parent, Vector3(cos(a) * 95, h * 0.5, sin(a) * 95), Vector3(10, h, 7), ground, Basis(Vector3.UP, a))
	return {"basaran": [BASARAN_START, PI], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}

static func dress(parent: Node3D) -> void:
	for at in GEYSERS:
		ArenaArt.encounter_prop(parent, "basaran_vent_ring", at)

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 61, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var boss := Basaran.new()
	boss.name = "Basaran"
	boss.brain_seed = brain_seed
	boss.position = BASARAN_START
	boss.rotation.y = PI
	parent.add_child(boss)
	boss.teleport(BASARAN_START, PI)
	boss.reset_encounter(boss.global_transform, true)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(HORSE_START, 0.0)
	var player := PlayerCharacter.new()
	player.name = "Player1"
	parent.add_child(player)
	player.global_position = PLAYER_START
	player.spawn_transform = player.global_transform
	player.actions.view_basis = Basis.IDENTITY
	player.reset_physics_interpolation()
	ArrowSystem.of(player)
	var camera := PlayerCamera.new()
	camera.name = "Camera1"
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
	encounter.name = "Encounter"
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [player]
	encounter.setup(boss, players, horse)
	encounter.encounter_reset.connect(func(_n: int) -> void: ArrowSystem.of(player).clear())
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.show_debug = false
	hud.show_help = false
	hud.player = player
	hud.colossus = boss
	hud.camera = camera
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	var hint := Label.new()
	hint.text = "Basaran blokuje przeprawę. Zwab go na gejzer, traf odsłoniętą stopę, wejdź na zad."
	hint.position = Vector2(24, 24)
	layer.add_child(hint)
	return {"basaran": boss, "colossus": boss, "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "debug_draw": boss.debug_draw, "input": input, "points": points}
