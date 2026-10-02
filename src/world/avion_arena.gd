class_name AvionArena
## Arena for Avion: a wide lake in a shallow basin with five tall stone towers standing
## out of it (creepers on their sides to climb from the water, flat tops to wait on),
## a shore all round. Avion circles high above the lake; anyone it carries falls into
## the water. The way in from +Z, the player and Agro on the shore.

const WATER_Y := -0.8
const WATER_RADIUS := 98.0
const DEEP := -8.0
const TOWER_TOP := 9.0
const TOWERS := [[Vector3(0, 0, 45), 3.0], [Vector3(48, 0, 12), 3.2], [Vector3(30, 0, -42), 3.0], [Vector3(-30, 0, -42), 3.2], [Vector3(-48, 0, 12), 3.0]]
const AVION_START := Vector3(70, 32, 0)
const AVION_YAW := PI
const PLAYER_START := Vector3(0, 0.95, 128)
const HORSE_START := Vector3(4.5, 0, 125)


static func ground_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	if r >= 112.0:
		return 0.0
	if r >= 92.0:
		return lerpf(-1.4, 0.0, smoothstep(92.0, 112.0, r))
	if r >= 76.0:
		return lerpf(DEEP, -1.4, smoothstep(76.0, 92.0, r))
	return DEEP + 0.3 * sin(x * 0.07) * cos(z * 0.09)


static func build(parent: Node3D) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var mesh := _basin_mesh(WorldMap.GROUND_RADIUS + 1.0, 4.0)
	var gs := CollisionShape3D.new()
	gs.shape = mesh.create_trimesh_shape()
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	gm.mesh = mesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.44, 0.45, 0.37)
	gm.material_override = gmat
	ground.add_child(gm)
	parent.add_child(ground)
	var water := WaterBody.new()
	water.name = "Lake"
	water.radius = WATER_RADIUS
	water.position = Vector3(0, WATER_Y, 0)
	parent.add_child(water)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.55, 0.52)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.4, 0.41, 0.38)
	var vine := StandardMaterial3D.new()
	vine.albedo_color = Color(0.26, 0.37, 0.21)
	TerrainKit.box(parent, Vector3(-7, 5, 140), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(7, 5, 140), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(0, 10.8, 140), Vector3(17, 1.6, 2.8), dark)
	var towers := []
	for t in TOWERS:
		towers.append(_tower(parent, t[0], t[1], stone, vine))
	for i in 6:
		var a := i * TAU / 6.0 + 0.4
		if absf(angle_difference(a, PI * 0.5)) < 0.3:
			continue
		TerrainKit.box(parent, Vector3(cos(a) * 122.0, 1.5, sin(a) * 122.0), Vector3(3.0, 3.0, 3.0), dark, Basis(Vector3.UP, a))
	return {"avion": [AVION_START, AVION_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "towers": towers, "water": water}


## A stone tower from the lake bed to TOWER_TOP, creepers on four sides from under the
## water to the top (climbable), a flat top to stand on.
static func _tower(parent: Node3D, at: Vector3, radius: float, stone: Material, vine: Material) -> Dictionary:
	var body := StaticBody3D.new()
	body.name = "Tower"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var bottom := DEEP - 1.0
	var h := TOWER_TOP - bottom
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = h
	col.shape = cyl
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.15
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = stone
	body.add_child(mi)
	# The creepers end just under the top's edge: the climb ends in a mantle onto the top
	# (not a crawl onto the creepers' own flat end).
	var climb_top := TOWER_TOP - 0.3
	var climb_h := climb_top - (WATER_Y - 2.4)
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var patch := ClimbPatch.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, climb_h, 0.5)
		patch.shape = bs
		patch.position = dir * (radius + 0.2) + Vector3.UP * (climb_top - climb_h * 0.5 - (bottom + h * 0.5))
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
	# The creepers' outward directions in world space (the arena may be turned in the world).
	var dirs: Array[Vector3] = []
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		dirs.append((parent.global_basis * Vector3(cos(a), 0, sin(a))).normalized())
	return {"center": parent.global_transform * (at + Vector3.UP * TOWER_TOP), "radius": radius, "creepers": dirs}


static func _basin_mesh(half: float, cell: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / cell)
	for iz in n:
		for ix in n:
			var x0 := -half + ix * cell
			var z0 := -half + iz * cell
			# A disc (the arenas sit side by side in the world; no corners into the next).
			if Vector2(x0 + cell * 0.5, z0 + cell * 0.5).length() > half + cell:
				continue
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var x: float = x0 + c.x * cell
				var z: float = z0 + c.y * cell
				st.set_uv(Vector2(x, z) * 0.2)
				st.add_vertex(Vector3(x, ground_height(x, z), z))
	st.generate_normals()
	return st.commit()


## Avion in an arena root (local frame of ``parent``).
static func spawn(parent: Node3D, brain_seed := 41) -> Avion:
	var av := Avion.new()
	av.name = "Avion"
	av.brain_seed = brain_seed
	av.water_level = (parent.global_transform * Vector3(0, WATER_Y, 0)).y
	# The node starts at the lake's centre (its arena centre), then flies from the start.
	av.position = Vector3.ZERO
	parent.add_child(av)
	var yaw := parent.global_transform.basis.get_euler().y + AVION_YAW
	var start := parent.global_transform * AVION_START
	av.teleport(start, yaw)
	av.reset_encounter(Transform3D(Basis(Vector3.UP, yaw), start), true)
	return av


static func build_encounter(parent: Node3D, with_input := false, brain_seed := 41, with_art := false) -> Dictionary:
	var points := build(parent)
	var av := spawn(parent, brain_seed)
	if with_art:
		ArenaArt.dress_arena(parent, Vector3(0, 0, 1), 105.0, 8231, WATER_RADIUS + 6.0)
		ArenaArt.skin_colossus(av)
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
	cam.focus_target = av
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
	encounter.setup(av, players, horse)
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = av
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"avion": av, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": av.debug_draw, "input": input, "points": points, "towers": points.towers}
