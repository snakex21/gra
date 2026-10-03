class_name WormArena
## Three low resonant slabs surround the sealed earth passage.
const WORM_START := Vector3(0, -14, 0)
const WORM_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 92)
const HORSE_START := Vector3(7, 0, 88)
const PLATFORMS := [Vector3(0, 0, 42), Vector3(-27, 0, 9), Vector3(27, 0, 9)]
static func build(parent: Node3D) -> Dictionary:
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.49, 0.4, 0.27)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), earth).name = "Ground"
	var mineral := StandardMaterial3D.new()
	mineral.albedo_color = Color(0.5, 0.55, 0.51)
	var slabs := []
	for i in PLATFORMS.size():
		var slab := TerrainKit.box(parent, PLATFORMS[i] + Vector3(0, -0.1, 0), Vector3(8, 0.2, 8), mineral)
		# Flush collision permits a run onto the slab; the thin visible cap avoids
		# coplanar flicker with the courtyard floor.
		for child in slab.get_children():
			if child is MeshInstance3D: child.position.y = 0.025
		slab.name = "ResonantSlab%d" % i
		slab.set_meta(&"resonant_station", i)
		slabs.append(slab)
		# Four readable tick marks around each slab. Central access remains open.
		for side in [-1.0, 1.0]:
			var mark := TerrainKit.box(parent, PLATFORMS[i] + Vector3(side * 5, 0.2, 0), Vector3(0.4, 0.4, 2.5), mineral)
			mark.collision_layer = 0
	return {"worm": [WORM_START, WORM_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "slabs": slabs, "platforms": PLATFORMS}
static func dress(_parent: Node3D) -> void:
	pass
static func spawn(parent: Node3D, brain_seed := 113) -> Worm:
	var c := Worm.new()
	c.name = "Worm"
	c.brain_seed = brain_seed
	parent.add_child(c)
	c.arena_frame = parent.global_transform
	for at in PLATFORMS: c.platform_centers.append(at)
	c.reset_encounter(parent.global_transform * Transform3D(Basis(Vector3.UP, WORM_YAW), WORM_START), true)
	return c
static func build_encounter(parent: Node3D, with_input := false, brain_seed := 113, with_art := false) -> Dictionary:
	var points := build(parent)
	var c := spawn(parent, brain_seed)
	if with_art: dress(parent)
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
	hud.message = "Strażnik ziemnego przejścia słyszy drgania. Na każdej płycie wyląduj dwukrotnie w rytmie 1–1,8 s. Poczekaj na wyjście, skrusz mineralny kołnierz łukiem lub mieczem i wejdź na odsłonięty grzbiet."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"worm": c, "colossus": c, "player": p, "horse": horse, "camera": cam, "encounter": e, "hud": hud, "input": input, "points": points, "platforms": points.platforms, "slabs": points.slabs}
