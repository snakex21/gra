class_name MalusArena
## Siege route: alternating shelters, covered passages and a rear service entrance.
const MALUS_START := Vector3.ZERO
const MALUS_YAW := PI
const PLAYER_START := Vector3(0, 0.95, 120)
const HORSE_START := Vector3(7, 0, 116)
const ROUTE := [Vector3(0, 0, 104), Vector3(-11, 0, 90), Vector3(11, 0, 69), Vector3(-11, 0, 48), Vector3(-15, 0, 22), Vector3(-15, 0, -13), Vector3(0, 0, -8)]
static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.43, 0.38)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	var cover := []
	for p in ROUTE.slice(0, 5):
		var roof := TerrainKit.box(parent, p + Vector3(0, 3.8, 0), Vector3(8, 1, 9), stone)
		roof.name = "SiegeCover"
		cover.append(roof)
		for side in [-1.0, 1.0]:
			TerrainKit.box(parent, p + Vector3(side * 4.0, 1.7, 3.5), Vector3(0.7, 3.4, 0.7), stone)
		TerrainKit.box(parent, p + Vector3(0, 1.7, -4), Vector3(8, 3.4, 0.7), stone)
	# A low protected final gallery keeps the run round the giant distinct from
	# walking into a leg; the entry at +Z remains open for the valley corridor.
	TerrainKit.box(parent, Vector3(-15, 3.8, 4), Vector3(7, 1, 38), stone)
	return {"malus": [MALUS_START, MALUS_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "cover": cover, "route": ROUTE}
static func dress(_parent: Node3D) -> void:
	pass
static func spawn(parent: Node3D, brain_seed := 107) -> Malus:
	var c := Malus.new()
	c.name = "Malus"
	c.brain_seed = brain_seed
	parent.add_child(c)
	c.reset_encounter(parent.global_transform * Transform3D(Basis(Vector3.UP, MALUS_YAW), MALUS_START), true)
	return c
static func build_encounter(parent: Node3D, with_input := false, brain_seed := 107, with_art := false) -> Dictionary:
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
	hud.message = "Strażnik finałowej bramy. Biegnij między osłonami, obejdź go i uderz znak z tyłu. Na dłoni traf nadgarstek łukiem."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"malus": c, "colossus": c, "player": p, "horse": horse, "camera": cam, "encounter": e, "hud": hud, "input": input, "points": points, "route": points.route, "cover": points.cover}
