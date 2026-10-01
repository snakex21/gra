class_name QuadratusArena
## Greybox arena for Quadratus: a wide, flat plain (room to ride around it and to get
## behind it), a shallow slope and a low rise on the sides (uneven ground for the four
## legs), a few rocks and broken pillars on the rim. Quadratus in the middle facing the
## entrance, the player and Agro ~80 m away.
##
## build() makes the geometry; build_encounter() also creates Quadratus, the player,
## Agro, the camera, the HUD, the debug overlays and the BossEncounter.

const QUADRATUS_START := Vector3(0, 0, 0)
const PLAYER_START := Vector3(0, 0.95, 80)
const HORSE_START := Vector3(4.5, 0, 77)


static func build(parent: Node3D) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	gm.mesh = plane
	var grid := Shader.new()
	grid.code = ValusArena.GRID_SHADER
	var gmat := ShaderMaterial.new()
	gmat.shader = grid
	gmat.set_shader_parameter(&"base_color", Color(0.52, 0.5, 0.4))
	gm.material_override = gmat
	ground.add_child(gm)
	parent.add_child(ground)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.6, 0.58, 0.53)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.45, 0.44, 0.41)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.5, 0.46, 0.36)
	# A gentle slope and a low rise beside the centre (Quadratus walks over them).
	TerrainKit.ramp(parent, Vector3(-40, 0, 10), 18.0, 6.0, 22.0, dirt)
	TerrainKit.box(parent, Vector3(-40, 0.89, -14.0), Vector3(22, 3.78, 12), dirt)
	TerrainKit.box(parent, Vector3(42, 0.2, -8), Vector3(16, 1.0, 18), dirt, Basis(Vector3.UP, 0.3))
	# Rim: broken pillars and fallen blocks (landmarks, cover from the head attack).
	for i in 11:
		var a := i * TAU / 11.0 + 0.2
		var r := 78.0 + (i % 3) * 5.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.35:
			continue  # keep the entrance (player side, +Z) open
		var h := 3.0 + (i % 4) * 2.5
		TerrainKit.box(parent, Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(2.6, h, 2.6), stone if i % 2 == 0 else dark, Basis(Vector3.UP, a))
	for rk in [[Vector3(24, 0, 46), 2.2], [Vector3(-26, 0, 50), 1.8], [Vector3(46, 0, 24), 2.6], [Vector3(-50, 0, -40), 2.4], [Vector3(30, 0, -52), 2.0]]:
		var c: Vector3 = rk[0]
		var s: float = rk[1]
		TerrainKit.box(parent, c + Vector3(0, s * 0.45, 0), Vector3(s * 1.3, s * 0.9, s * 1.1), dark, Basis(Vector3.UP, c.x * 0.1))
	return {"quadratus": [QUADRATUS_START, PI], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}


static func build_encounter(parent: Node3D, with_input := false, brain_seed := 11) -> Dictionary:
	var points := build(parent)
	var q := Quadratus.new()
	q.name = "Quadratus"
	q.brain_seed = brain_seed
	q.position = QUADRATUS_START
	q.rotation.y = PI
	parent.add_child(q)
	q.teleport(QUADRATUS_START, PI)
	q.reset_encounter(q.global_transform, true)

	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(HORSE_START, 0.0)

	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = PLAYER_START
	p.facing = Vector3.FORWARD
	p.spawn_transform = p.global_transform
	p.actions.view_basis = Basis.IDENTITY
	p.reset_physics_interpolation()
	ArrowSystem.of(p)

	var cam := PlayerCamera.new()
	cam.name = "Camera1"
	cam.player = p
	cam.focus_target = q
	parent.add_child(cam)
	cam.current = true
	cam.snap_behind_player()

	var input: FlatInputSource = null
	if with_input:
		input = FlatInputSource.new()
		input.actions = p.actions
		input.view = cam
		parent.add_child(input)

	var encounter := BossEncounter.new()
	encounter.name = "Encounter"
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [p]
	encounter.setup(q, players, horse)
	encounter.encounter_reset.connect(func(_n: int) -> void: ArrowSystem.of(p).clear())

	var bow_draw := BowDebugDraw.new()
	bow_draw.player = p
	parent.add_child(bow_draw)

	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = q
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"quadratus": q, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": q.debug_draw, "bow_draw": bow_draw, "input": input, "points": points}
