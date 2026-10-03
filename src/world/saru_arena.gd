class_name SaruArena
const SARU_START := Saru.START
const SARU_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 75)
const HORSE_START := Vector3(8, 0, 72)

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.43, 0.34)
	# Two clipped circular banks keep the seventy-metre chasm physically open.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var circle := PackedVector2Array()
	for i in 128:
		circle.append(Vector2.from_angle(TAU * i / 128.0) * 175.0)
	for side: float in [-1, 1]:
		var lower := 35.0 if side > 0 else -175.0
		var upper := 175.0 if side > 0 else -35.0
		var clip := PackedVector2Array([Vector2(-175, lower), Vector2(175, lower), Vector2(175, upper), Vector2(-175, upper)])
		var polygon: PackedVector2Array = Geometry2D.intersect_polygons(circle, clip)[0]
		_ground_part(ground, polygon, 0.0, -2.0, stone)
	parent.add_child(ground)
	var pit := StaticBody3D.new()
	pit.name = "ChasmFloor"
	pit.collision_layer = Layers.WORLD
	pit.collision_mask = 0
	var pit_clip := PackedVector2Array([Vector2(-175, -35), Vector2(175, -35), Vector2(175, 35), Vector2(-175, 35)])
	var pit_polygon: PackedVector2Array = Geometry2D.intersect_polygons(circle, pit_clip)[0]
	_ground_part(pit, pit_polygon, -22.0, -24.0, stone)
	parent.add_child(pit)
	TerrainKit.ramp(parent, Vector3(0, 0, 70), 28, rad_to_deg(atan(6.0 / 28.0)), 12, stone)
	TerrainKit.box(parent, Vector3(0, 5, 36), Vector3(130, 2, 12), stone).name = "LureGallery"
	TerrainKit.box(parent, Vector3(0, 5, -36), Vector3(10, 2, 12), stone).name = "NorthGallery"
	var bridge := SaruBridge.new()
	bridge.name = "SaruBridge"
	parent.add_child(bridge)
	return {"saru": [SARU_START, SARU_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "baits": SaruBridge.BAITS, "gallery": Vector3(0, 6.95, -40.5)}

static func _ground_part(body: StaticBody3D, polygon: PackedVector2Array, top: float, bottom: float, mat: Material) -> void:
	var vertices := PackedVector3Array()
	for p in polygon:
		vertices.append(Vector3(p.x, top, p.y))
		vertices.append(Vector3(p.x, bottom, p.y))
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = vertices
	shape.shape = convex
	body.add_child(shape)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, triangles.size(), 3):
		for height: float in [top, bottom]:
			surface.set_normal(Vector3.UP if height == top else Vector3.DOWN)
			for k in 3:
				var idx := triangles[i + (k if height == top else 2 - k)]
				var p := polygon[idx]
				surface.add_vertex(Vector3(p.x, height, p.y))
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var a := Vector3(p.x, top, p.y)
		var b := Vector3(q.x, top, q.y)
		var c := Vector3(q.x, bottom, q.y)
		var d := Vector3(p.x, bottom, p.y)
		surface.set_normal((b - a).cross(c - a).normalized())
		for point: Vector3 in [a, b, c, a, c, d]:
			surface.add_vertex(point)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = mat
	body.add_child(mesh)

static func dress(_parent: Node3D) -> void:
	pass

static func spawn(parent: Node3D, brain_seed := 101) -> Saru:
	var boss := Saru.new()
	boss.name = "Saru"
	boss.brain_seed = brain_seed
	parent.add_child(boss)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, SARU_YAW), SARU_START)
	boss.reset_encounter(xf, true)
	return boss

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 101, with_art := false) -> Dictionary:
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
	camera.player = player
	camera.focus_target = boss
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
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
	hud.message = "Saru broni przejścia nad przepaścią. Ustaw się za złotymi przeciwwagami na galerii, sprowokuj rzut i uniknij go. Dwa trafione bloki tworzą most do strażnika."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"saru": boss, "colossus": boss, "bridge": boss.bridge, "player": player, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": null}
