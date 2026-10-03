class_name BarbaArena
## A 64 x 78 m temple courtyard. Low arch has cover below it, while the centre
## remains open for the boss and a climber to see the entire inspection animation.
const BARBA_START := Vector3.ZERO
const BARBA_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 38)
const HORSE_START := Vector3(7, 0, 34)

static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.48, 0.44, 0.36)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.28, 0.28, 0.25)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	for side in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 32, 6, 0), Vector3(2, 12, 78), dark)
		TerrainKit.box(parent, Vector3(side * 5.5, 2.2, -27), Vector3(2, 4.4, 9), stone)
		for z in [-32.0, 0.0, 30.0]:
			TerrainKit.box(parent, Vector3(side * 26, 8, z), Vector3(2.2, 16, 2.2), stone)
	TerrainKit.box(parent, Vector3(0, 4.6, -27), Vector3(13, 1, 9), stone).name = "CoverRoof"
	TerrainKit.box(parent, Vector3(0, 6, -39), Vector3(66, 12, 2), dark)
	return {"barba": [BARBA_START, BARBA_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0], "cover": Barba.COVER_LOCAL}

static func dress(parent: Node3D) -> void:
	ArenaArt.encounter_prop(parent, "barba_shelter", Vector3(0, 0, -27))

static func spawn(parent: Node3D, brain_seed := 61) -> Barba:
	var c := Barba.new()
	c.name = "Barba"
	c.brain_seed = brain_seed
	parent.add_child(c)
	var xf := parent.global_transform * Transform3D(Basis(Vector3.UP, BARBA_YAW), BARBA_START)
	c.teleport(xf.origin, xf.basis.get_euler().y)
	c.reset_encounter(xf, true)
	return c

static func build_encounter(parent: Node3D, with_input := false, brain_seed := 61, with_art := false) -> Dictionary:
	var points := build(parent)
	var c := spawn(parent, brain_seed)
	if with_art:
		dress(parent)
		ArenaArt.skin_colossus(c)
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
	hud.message = "Strażnik blokuje przejście. Ukryj się pod łukiem; przy pochyleniu złap brodę."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"barba": c, "colossus": c, "player": p, "horse": horse, "camera": cam, "encounter": e, "hud": hud, "input": input, "points": points, "debug_draw": c.debug_draw}
