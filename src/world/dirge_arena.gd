class_name DirgeArena
## A sand basin enclosed by solid ruin walls. Dirge guards the desert passage.
const DIRGE_START := Vector3(0, 0, -28)
const PLAYER_START := Vector3(4.5, 0.95, 25)
const HORSE_START := Vector3(0, 0, 25)

static func build(parent: Node3D) -> Dictionary:
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.65, 0.5, 0.3)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(220, 2, 220), sand).name = "DesertFloor"
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.4, 0.32, 0.22)
	for side: float in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 100, 8, 0), Vector3(6, 16, 206), wall).name = "CrashWallX"
		if side < 0.0:
			TerrainKit.box(parent, Vector3(0, 8, side * 100), Vector3(194, 16, 6), wall).name = "CrashWallZ"
		else:
			for x in [-1.0, 1.0]:
				TerrainKit.box(parent, Vector3(x * 54, 8, 100), Vector3(86, 16, 6), wall).name = "CrashWallEntrance"
	# Low ridges outside the pursuit lane distinguish the arena without trapping Agro.
	for i in 5:
		TerrainKit.box(parent, Vector3(-76, 0.4, -60 + i * 25), Vector3(16, 0.8, 12), sand, Basis(Vector3.UP, 0.2 * i))
	return {"dirge": [DIRGE_START, PI], "player": [PLAYER_START, PI], "horse": [HORSE_START, PI]}

static func dress(parent: Node3D) -> void:
	for i in 5:
		ArenaArt.encounter_prop(parent, "dirge_porous_rock", Vector3(-80, 0, -60 + i * 25), i * 0.3)

static func spawn(parent: Node3D, brain_seed := 67) -> Dirge:
	var boss := Dirge.new()
	boss.name = "Dirge"
	boss.brain_seed = brain_seed
	boss.water_level = parent.global_position.y + 1.7
	boss.arena_basis = parent.global_basis.orthonormalized()
	parent.add_child(boss)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, PI), DIRGE_START)
	boss.teleport(xf.origin, xf.basis.get_euler().y)
	boss.reset_encounter(xf, true)
	return boss

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 67, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var boss := spawn(parent, brain_seed)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(HORSE_START, PI)
	var player := PlayerCharacter.new()
	player.name = "Player1"
	parent.add_child(player)
	player.global_position = PLAYER_START
	player.facing = Vector3.BACK
	player.spawn_transform = player.global_transform
	player.actions.view_basis = Basis(Vector3.UP, PI)
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
	hint.text = "Dirge strzeże pustynnego przejścia. Jedź na Agro, traf oko, po zderzeniu ze ścianą wejdź na grzbiet."
	hint.position = Vector2(24, 24)
	layer.add_child(hint)
	return {"dirge": boss, "colossus": boss, "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "debug_draw": boss.debug_draw, "input": input, "points": points}
