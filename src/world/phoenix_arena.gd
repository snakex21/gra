class_name PhoenixArena
## Shallow waterfall courtyard with a continuous 350m support plane.
const PHOENIX_START := Vector3.ZERO
const PHOENIX_YAW := 0.0
const PLAYER_START := Vector3(0, .95, 90)
const HORSE_START := Vector3(5, 0, 87)
static func build(parent: Node3D) -> Dictionary:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(.38, .35, .26)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), rock).name = "Ground"
	for stream: Vector3 in Phoenix.STREAMS_LOCAL:
		var water := WaterBody.new()
		water.name = "StreamPool"
		water.radius = 6
		water.position = stream + Vector3.UP * .05
		parent.add_child(water)
		TerrainKit.box(parent, stream + Vector3(0, 12, -15), Vector3(18, 24, 3), rock)
		TerrainKit.box(parent, stream + Vector3(0, 23.5, -7), Vector3(18, 1, 19), rock)
		for side in [-1.0, 1.0]:
			TerrainKit.box(parent, stream + Vector3(side * 8.3, 8, -7), Vector3(2.2, 16, 14), rock)
		var fall := MeshInstance3D.new()
		fall.name = "FallingWater"
		var quad := QuadMesh.new()
		quad.size = Vector2(8.6, 22)
		fall.mesh = quad
		fall.position = stream + Vector3(0, 11, -1.8)
		var flow := StandardMaterial3D.new()
		flow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flow.albedo_color = Color(.42, .73, .82, .3)
		flow.roughness = .22
		flow.cull_mode = BaseMaterial3D.CULL_DISABLED
		fall.material_override = flow
		parent.add_child(fall)
	return {"phoenix": [PHOENIX_START, PHOENIX_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}
static func dress(parent: Node3D) -> void:
	for side in [-1.0, 1.0]:
		ArenaArt.encounter_prop(parent, "dirge_porous_rock", Vector3(side * 42, 0, -37))
		ArenaArt.encounter_prop(parent, "pelagia_shrine_cap", Vector3(side * 20, 24.0, -27))
static func spawn(parent: Node3D, seed := 113) -> Phoenix:
	var c := Phoenix.new()
	c.name = "Phoenix"
	c.brain_seed = seed
	parent.add_child(c)
	c.reset_encounter(parent.global_transform * Transform3D(Basis(Vector3.UP, PHOENIX_YAW), PHOENIX_START), true)
	return c
static func build_encounter(parent: Node3D, with_input := false, seed := 113, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var c := spawn(parent, seed)
	if with_art:
		GuardianVisuals.dress(c, "phoenix")
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(parent.global_transform * HORSE_START, parent.global_rotation.y)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = parent.global_transform * PLAYER_START
	p.spawn_transform = p.global_transform
	var camera := PlayerCamera.new()
	camera.player = p
	camera.focus_target = c
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [p]
	encounter.setup(c, players, horse)
	var input: FlatInputSource
	if with_input:
		input = FlatInputSource.new()
		input.actions = p.actions
		input.view = camera
		parent.add_child(input)
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = camera
	hud.colossus = c
	hud.horse = horse
	hud.encounter = encounter
	hud.message = c.encounter_hint()
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	c.phase_changed.connect(func(_phase: Phoenix.Phase) -> void: hud.message = c.encounter_hint())
	return {"phoenix": c, "colossus": c, "player": p, "players": players, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": c.debug_draw}
