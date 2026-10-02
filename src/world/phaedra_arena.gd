class_name PhaedraArena
## Arena for Phaedra: a sunken fen basin with three ruined tunnels (stone passages with a
## roof) where a player can hide. Phaedra cannot reach in; it can only put its head into
## a mouth to look, which is the way onto it. Phaedra at the far side, the player and
## Agro at the entrance ~80 m away, as in every arena.
##
## build() makes the geometry and returns the tunnels; build_encounter() also creates
## Phaedra, the player, Agro, the camera, the HUD and the BossEncounter.

const PHAEDRA_START := Vector3(0, 0, -30)
const PLAYER_START := Vector3(0, 0.95, 80)
const HORSE_START := Vector3(4.5, 0, 77)
## Tunnels: centre, along X (true) or Z, length. Inside: 5 m wide, 3.2 m high.
const TUNNELS := [[Vector3(0, 0, 30), true, 14.0], [Vector3(-30, 0, -8), false, 14.0], [Vector3(30, 0, -12), false, 14.0]]
const TUNNEL_WIDTH := 5.0
const TUNNEL_HEIGHT := 3.2


static func build(parent: Node3D) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 2, 500)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	gm.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.4, 0.3)
	gm.material_override = gmat
	ground.add_child(gm)
	parent.add_child(ground)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.52, 0.46)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.38, 0.4, 0.36)
	# Entrance: two pillars, as in the other arenas.
	TerrainKit.box(parent, Vector3(-7, 5, 62), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(7, 5, 62), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(0, 10.8, 62), Vector3(17, 1.6, 2.8), dark)
	var tunnels := []
	for t in TUNNELS:
		tunnels.append(tunnel(parent, t[0], t[1], t[2], stone, dark))
	# Fallen blocks on the rim (landmarks, cover), never between a mouth and its open side.
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		var r := 58.0 + (i % 3) * 4.0
		TerrainKit.box(parent, Vector3(cos(a) * r, 1.5, sin(a) * r), Vector3(3.0, 3.0, 3.0), dark, Basis(Vector3.UP, a))
	return {"phaedra": [PHAEDRA_START, PI], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "tunnels": tunnels}


## A roofed stone passage. Returns {"aabb": interior, "mouths": [[ground point, outward]]}.
static func tunnel(parent: Node3D, center: Vector3, along_x: bool, length: float, stone: Material, roof: Material) -> Dictionary:
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var side := Vector3.BACK if along_x else Vector3.RIGHT
	var wall := 1.2
	var h := TUNNEL_HEIGHT
	for s in [-1.0, 1.0]:
		var c: Vector3 = center + side * s * (TUNNEL_WIDTH * 0.5 + wall * 0.5) + Vector3.UP * h * 0.5
		var size := Vector3(length, h, wall) if along_x else Vector3(wall, h, length)
		TerrainKit.box(parent, c, size, stone)
	var roof_size := Vector3(length, 0.7, TUNNEL_WIDTH + 2.0 * wall) if along_x else Vector3(TUNNEL_WIDTH + 2.0 * wall, 0.7, length)
	TerrainKit.box(parent, center + Vector3.UP * (h + 0.35), roof_size, roof)
	var half := axis * length * 0.5
	var inner := Vector3(length, h, TUNNEL_WIDTH) if along_x else Vector3(TUNNEL_WIDTH, h, length)
	var aabb := AABB(center - Vector3(inner.x, 0, inner.z) * 0.5, inner)
	return {"aabb": aabb, "mouths": [[center + half, axis], [center - half, -axis]], "center": center, "along_x": along_x, "length": length}


static func build_encounter(parent: Node3D, with_input := false, brain_seed := 17, with_art := false) -> Dictionary:
	var points := build(parent)
	var ph := Phaedra.new()
	ph.name = "Phaedra"
	ph.brain_seed = brain_seed
	ph.position = PHAEDRA_START
	ph.rotation.y = PI
	ph.tunnels = points.tunnels
	ph.arena_radius = 65.0
	parent.add_child(ph)
	ph.teleport(PHAEDRA_START, PI)
	ph.reset_encounter(ph.global_transform, true)
	if with_art:
		# Render-only: collision, climbing and AI are the greybox ones.
		ArenaArt.dress_fen(parent, points.tunnels, 75.0, 6047)
		ArenaArt.skin_colossus(ph)

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

	var cam := PlayerCamera.new()
	cam.name = "Camera1"
	cam.player = p
	cam.focus_target = ph
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
	encounter.setup(ph, players, horse)

	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = ph
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"phaedra": ph, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": ph.debug_draw, "input": input, "points": points, "tunnels": points.tunnels}
