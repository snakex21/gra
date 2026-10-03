class_name PhalanxArena
## Open desert air-barrier arena. Flat 350 m ground and a clear +Z entry.
const PHALANX_START := Vector3(0, 17, -10)
const PHALANX_YAW := 0.0
const PLAYER_START := Vector3(0, 0.95, 112)
const HORSE_START := Vector3(4.5, 0, 109)
static func build(parent: Node3D) -> Dictionary:
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.64, 0.57, 0.39)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), sand).name = "Ground"
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.41, 0.31)
	for side in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 11, 6, 138), Vector3(2, 12, 2), stone)
		TerrainKit.box(parent, Vector3(side * 80, 8, -48), Vector3(3, 16, 3), stone)
	return {"phalanx": [PHALANX_START, PHALANX_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}
static func dress(_parent: Node3D) -> void:
	pass
static func spawn(parent: Node3D, brain_seed := 101) -> Phalanx:
	var c := Phalanx.new()
	c.name = "Phalanx"
	c.brain_seed = brain_seed
	parent.add_child(c)
	c.arena_center = parent.global_position
	c.reset_encounter(parent.global_transform * Transform3D(Basis(Vector3.UP, PHALANX_YAW), PHALANX_START), true)
	return c
static func build_encounter(parent: Node3D, with_input := false, brain_seed := 101, with_art := false) -> Dictionary:
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
	hud.message = "Strażnik bariery. Przebij trzy worki łukiem. Przy niskim skrzydle: chwyt + skok z Agro."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"phalanx": c, "colossus": c, "player": p, "horse": horse, "camera": cam, "encounter": e, "hud": hud, "input": input, "points": points}
