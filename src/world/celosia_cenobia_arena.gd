class_name CelosiaCenobiaArena
const COLOSSUS_START := Vector3.ZERO
const COLOSSUS_YAW := 0.0
const PLAYER_START := Vector3(-20, 0.95, 15)
const HORSE_START := Vector3(-28, 0, 14)
const COLUMNS := [Vector3(-5, 0, 1), Vector3(18, 0, -4), Vector3(28, 0, 12)]

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.43, 0.34)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	var wall := TerrainKit.box(parent, Vector3(0, 2, 12), Vector3(2, 4, 20), stone)
	wall.name = "FireBreakWall"
	wall.set_meta(&"celosia_fire_wall", true)
	for i in COLUMNS.size():
		var column := TerrainKit.box(parent, COLUMNS[i] + Vector3.UP * 3, Vector3(3.5, 6, 3.5), stone)
		column.name = "ChargeColumn%d" % i
		column.set_meta(&"cenobia_column", true)
	# A refuge gives a solo player time to combine the two threats.
	TerrainKit.box(parent, CelosiaCenobia.FIRE + Vector3.UP * 4.5, Vector3(8, 1, 8), stone).name = "RefugeRoof"
	for side: float in [-1.0, 1.0]:
		TerrainKit.box(parent, CelosiaCenobia.FIRE + Vector3(side * 3.5, 2, -3.5), Vector3(0.5, 4, 0.5), stone)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1, 0.45, 0.08)
	flame_mat.emission_enabled = true
	flame_mat.emission = flame_mat.albedo_color
	TerrainKit.box(parent, CelosiaCenobia.FIRE + Vector3(0, 0.15, -2.5), Vector3(1.4, 0.3, 1.4), stone)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.35
	flame_mesh.height = 0.9
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position = CelosiaCenobia.FIRE + Vector3(0, 0.7, -2.5)
	parent.add_child(flame)
	return {"celosia_cenobia": [COLOSSUS_START, COLOSSUS_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "fire": CelosiaCenobia.FIRE, "columns": COLUMNS}

static func dress(_parent: Node3D) -> void:
	pass

static func spawn(parent: Node3D, brain_seed := 89) -> CelosiaCenobia:
	var boss := CelosiaCenobia.new()
	boss.name = "CelosiaCenobia"
	boss.brain_seed = brain_seed
	parent.add_child(boss)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, COLOSSUS_YAW), COLOSSUS_START)
	boss.global_transform = xf
	boss.reset_encounter(xf, true)
	return boss

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 89, with_art := false) -> Dictionary:
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
	hud.message = "Dwa strażniki blokują przejście. Przy palenisku podnieś miecz (przytrzymaj V) i skieruj ogień na Celosię. Zwab taran Cenobii na kolumnę."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"celosia_cenobia": boss, "colossus": boss, "celosia": boss.guardians[0], "cenobia": boss.guardians[1], "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": null}
