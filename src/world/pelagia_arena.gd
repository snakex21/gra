class_name PelagiaArena
## Flooded shrine, 120 m wide lake and three large buttresses at its inner rim.
const WATER_Y := -0.4
const WATER_RADIUS := 60.0
const PELAGIA_START := Vector3.ZERO
const PELAGIA_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 78)
const HORSE_START := Vector3(8, 0, 75)

static func ground_height(x: float, z: float) -> float:
	return lerpf(-6.0, 0.0, smoothstep(48.0, 64.0, Vector2(x, z).length()))

static func build(parent: Node3D) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A circular basin reaches the shared corridor at radius170; it cannot overlap
	# the adjacent arena's foundation when all21 campaign slots are occupied.
	for ring in 44:
		for wedge in 96:
			for uv: Vector2 in [Vector2.ZERO, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO, Vector2.DOWN, Vector2.ONE]:
				var radius: float = (ring + uv.y) * 175.0 / 44.0
				var angle: float = (wedge + uv.x) * TAU / 96.0
				var x := cos(angle) * radius
				var z := sin(angle) * radius
				st.add_vertex(Vector3(x, ground_height(x, z), z))
	st.generate_normals()
	var mesh := st.commit()
	var floor := StaticBody3D.new()
	floor.name = "Ground"
	floor.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	floor.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mud := StandardMaterial3D.new()
	mud.albedo_color = Color(0.24, 0.32, 0.27)
	mi.material_override = mud
	floor.add_child(mi)
	parent.add_child(floor)
	var water := WaterBody.new()
	water.name = "Lake"
	water.radius = WATER_RADIUS
	water.position.y = WATER_Y
	parent.add_child(water)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.51, 0.57, 0.49)
	var ruins := []
	for i in 3:
		var at: Vector3 = Pelagia.RUINS_LOCAL[i]
		var pillar := TerrainKit.box(parent, at + Vector3.UP * 0.5, Vector3(6, 13, 6), stone)
		pillar.name = "Buttress%d" % i
		pillar.set_meta(&"pelagia_ruin_index", i)
		pillar.set_meta(&"intact_material", stone)
		ruins.append(pillar)
	for side in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 8, 6, 72), Vector3(2, 12, 2), stone)
	return {"pelagia": [PELAGIA_START, PELAGIA_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "water": water, "ruins": ruins}

static func dress(parent: Node3D) -> void:
	for at in Pelagia.RUINS_LOCAL:
		ArenaArt.encounter_prop(parent, "pelagia_shrine_cap", at + Vector3.UP * 6.85)

static func spawn(parent: Node3D, brain_seed := 71) -> Pelagia:
	var c := Pelagia.new()
	c.name = "Pelagia"
	c.brain_seed = brain_seed
	parent.add_child(c)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, PELAGIA_YAW), PELAGIA_START)
	c.reset_encounter(xf, true)
	c.ruin_impact.connect(func(index: int) -> void:
		for ruin in parent.get_children():
			if ruin.get_meta(&"pelagia_ruin_index", -1) == index:
				ruin.set_meta(&"broken", true)
				for child in ruin.get_children():
					if child is MeshInstance3D:
						var cracked := StandardMaterial3D.new()
						cracked.albedo_color = Color(0.3, 0.35, 0.31)
						child.material_override = cracked)
	c.ruins_restored.connect(func() -> void:
		for ruin in parent.get_children():
			if ruin.has_meta(&"pelagia_ruin_index"):
				ruin.set_meta(&"broken", false)
				for child in ruin.get_children():
					if child is MeshInstance3D:
						child.material_override = ruin.get_meta(&"intact_material"))
	return c

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 71, with_art := false) -> Dictionary:
	var points := build(parent)
	var c := spawn(parent, brain_seed)
	if with_art:
		dress(parent)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(parent.global_transform * HORSE_START, parent.global_rotation.y)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = parent.global_transform * PLAYER_START
	p.spawn_transform = p.global_transform
	var cam := PlayerCamera.new()
	cam.player = p
	cam.focus_target = c
	parent.add_child(cam)
	cam.current = true
	cam.snap_behind_player()
	var e := BossEncounter.new()
	parent.add_child(e)
	var players: Array[PlayerCharacter] = [p]
	e.setup(c, players, horse)
	var input: FlatInputSource = null
	if with_input:
		input = FlatInputSource.new()
		input.actions = p.actions
		input.view = cam
		parent.add_child(input)
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = cam
	hud.horse = horse
	hud.colossus = c
	hud.encounter = e
	hud.message = "Strażnik zatopionej bramy. Wejdź od tyłu; cios w kamienny ząb kieruje go ku ruinie."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"pelagia": c, "colossus": c, "player": p, "horse": horse, "camera": cam, "encounter": e, "hud": hud, "input": input, "points": points, "ruins": points.ruins, "water": points.water}
