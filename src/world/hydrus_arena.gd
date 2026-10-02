class_name HydrusArena
## Arena for Hydrus: a round lake in a basin. A shallow shore all round, then a steep bank
## down to a deep middle (the serpent dives there); six stone pillars stand out of the
## water, with creepers on their sides to climb out on them and flat tops to stand and wait
## on. The way in from +Z, the player and Agro on the shore ~95 m from the middle (Agro
## does not swim: it stops at the water's edge).
##
## build() makes the ground, the water and the pillars; build_encounter() also creates
## Hydrus, the player, Agro, the camera, the HUD and the BossEncounter.

const WATER_Y := -0.6
const WATER_RADIUS := 72.0
const DEEP := -9.0
## Hydrus' head at the start (on its cruising circle, swimming round it).
const HYDRUS_START := Vector3(34, 0, 0)
const HYDRUS_YAW := PI
const PLAYER_START := Vector3(0, 0.95, 95)
const HORSE_START := Vector3(4.5, 0, 92)
const PILLARS := [[Vector3(0, 0, 30), 2.4], [Vector3(26, 0, 15), 2.2], [Vector3(26, 0, -15), 2.4], [Vector3(0, 0, -30), 2.2], [Vector3(-26, 0, -15), 2.4], [Vector3(-26, 0, 15), 2.2]]
const PILLAR_TOP := 1.4


## Ground height of the basin at local (x, z).
static func ground_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	if r >= 74.0:
		return 0.0
	if r >= 60.0:
		return lerpf(-1.1, 0.0, smoothstep(60.0, 74.0, r))
	if r >= 44.0:
		return lerpf(DEEP, -1.1, smoothstep(44.0, 60.0, r))
	return DEEP + 0.4 * sin(x * 0.11) * cos(z * 0.13)


static func build(parent: Node3D) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var mesh := _basin_mesh(176.0, 4.0)
	var gs := CollisionShape3D.new()
	gs.shape = mesh.create_trimesh_shape()
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	gm.mesh = mesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.42, 0.44, 0.36)
	gm.material_override = gmat
	ground.add_child(gm)
	parent.add_child(ground)

	var water := WaterBody.new()
	water.name = "Lake"
	water.radius = WATER_RADIUS
	water.position = Vector3(0, WATER_Y, 0)
	parent.add_child(water)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.52, 0.53, 0.5)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.38, 0.4, 0.37)
	var vine := StandardMaterial3D.new()
	vine.albedo_color = Color(0.25, 0.36, 0.2)
	# Entrance: two pillars on the shore.
	TerrainKit.box(parent, Vector3(-7, 5, 110), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(7, 5, 110), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(0, 10.8, 110), Vector3(17, 1.6, 2.8), dark)
	var pillars := []
	for pl in PILLARS:
		pillars.append(_pillar(parent, pl[0], pl[1], stone, vine))
	# Fallen blocks on the shore (landmarks, cover).
	for i in 7:
		var a := i * TAU / 7.0 + 0.3
		var r := 84.0 + (i % 3) * 5.0
		if absf(angle_difference(a, PI * 0.5)) < 0.3:
			continue
		TerrainKit.box(parent, Vector3(cos(a) * r, 1.5, sin(a) * r), Vector3(3.0, 3.0, 3.0), dark, Basis(Vector3.UP, a))
	return {"hydrus": [HYDRUS_START, HYDRUS_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "pillars": pillars, "water": water}


## A stone column from the lake bed to above the surface, with creepers (climbable) on
## four sides from under the water up to its top.
static func _pillar(parent: Node3D, at: Vector3, radius: float, stone: Material, vine: Material) -> Dictionary:
	var body := StaticBody3D.new()
	body.name = "Pillar"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var bottom := DEEP - 1.0
	var h := PILLAR_TOP - bottom
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = h
	col.shape = cyl
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.1
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = stone
	body.add_child(mi)
	var climb_h := PILLAR_TOP - (WATER_Y - 2.4)
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var patch := ClimbPatch.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, climb_h, 0.5)
		patch.shape = bs
		patch.position = dir * (radius + 0.2) + Vector3.UP * (PILLAR_TOP - climb_h * 0.5 - (bottom + h * 0.5))
		patch.basis = Basis.looking_at(dir, Vector3.UP)
		body.add_child(patch)
		var vm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		vm.mesh = bm
		vm.material_override = vine
		vm.transform = patch.transform
		body.add_child(vm)
	body.position = at + Vector3.UP * (bottom + h * 0.5)
	parent.add_child(body)
	return {"center": parent.global_transform * (at + Vector3.UP * PILLAR_TOP), "radius": radius}


static func _basin_mesh(half: float, cell: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := -half + ix * cell
			var z0 := -half + iz * cell
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var x: float = x0 + c.x * cell
				var z: float = z0 + c.y * cell
				st.set_uv(Vector2(x, z) * 0.2)
				st.add_vertex(Vector3(x, ground_height(x, z), z))
	st.generate_normals()
	return st.commit()


## Hydrus in an arena root (local frame of ``parent``).
static func spawn(parent: Node3D, brain_seed := 29) -> Hydrus:
	var h := Hydrus.new()
	h.name = "Hydrus"
	h.brain_seed = brain_seed
	h.water_level = (parent.global_transform * Vector3(0, WATER_Y, 0)).y
	# The node sits at the lake's centre (its arena centre); the body swims from the start.
	h.position = Vector3.ZERO
	parent.add_child(h)
	var yaw := parent.global_transform.basis.get_euler().y + HYDRUS_YAW
	h.teleport(parent.global_transform * HYDRUS_START, yaw)
	h.reset_encounter(Transform3D(Basis(Vector3.UP, yaw), parent.global_transform * HYDRUS_START), true)
	return h


static func build_encounter(parent: Node3D, with_input := false, brain_seed := 29, with_art := false) -> Dictionary:
	var points := build(parent)
	var hy := spawn(parent, brain_seed)
	if with_art:
		ArenaArt.dress_arena(parent, Vector3(0, 0, 1), 80.0, 7129)
		ArenaArt.skin_colossus(hy)

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
	cam.focus_target = hy
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
	encounter.setup(hy, players, horse)

	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = hy
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"hydrus": hy, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": hy.debug_draw, "input": input, "points": points, "pillars": points.pillars}
