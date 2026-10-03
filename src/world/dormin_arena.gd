class_name DorminArena
## Outdoor shrine courtyard finale, same portable standalone encounter API.
const DORMIN_START := Vector3.ZERO
const DORMIN_YAW := 0.0
const PLAYER_START := Vector3(0, .95, 90)
const HORSE_START := Vector3(5, 0, 87)
static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(.39, .42, .39)
	TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), stone).name = "Ground"
	for side in [-1.0, 1.0]:
		for z in [-48.0, -23.0, 2.0, 27.0]:
			TerrainKit.box(parent, Vector3(side * 40, 9, z), Vector3(3, 18, 3), stone)
	TerrainKit.box(parent, Vector3(0, 12, -53), Vector3(85, 24, 3), stone)
	TerrainKit.box(parent, Vector3(0, 24.3, -53), Vector3(88, 1, 6), stone)
	return {"dormin": [DORMIN_START, DORMIN_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}
static func dress(parent: Node3D) -> void:
	for side in [-1.0, 1.0]:
		for z in [-48.0, -23.0, 2.0, 27.0]:
			ArenaArt.encounter_prop(parent, "kuromori_gallery_fragment", Vector3(side * 40, 18, z))
		ArenaArt.encounter_prop(parent, "pelagia_shrine_cap", Vector3(side * 40, 0, 52))
static func spawn(parent: Node3D, seed := 127) -> Dormin:
	var c := Dormin.new()
	c.name = "Dormin"
	c.brain_seed = seed
	parent.add_child(c)
	var start := parent.global_transform * Transform3D(Basis(Vector3.UP, DORMIN_YAW), DORMIN_START)
	c.reset_encounter(start, true)
	return c
static func build_encounter(parent: Node3D, with_input := false, seed := 127, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var c := spawn(parent, seed)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(parent.global_transform * HORSE_START, parent.global_rotation.y)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = parent.global_transform * PLAYER_START
	p.spawn_transform = p.global_transform
	p.beam.target = c.beam_target()
	var camera := PlayerCamera.new()
	camera.player = p
	camera.focus_target = c
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [p]
	encounter.setup(c, players, horse)
	var input: FlatInputSource
	if with_input:
		input = FlatInputSource.new()
		input.actions = p.actions
		input.view = camera
		parent.add_child(input)
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = camera
	hud.colossus = c
	hud.horse = horse
	hud.encounter = encounter
	hud.message = c.encounter_hint()
	layer.add_child(hud)
	parent.add_child(layer)
	c.seals_changed.connect(func(_count: int) -> void:
		hud.message = c.encounter_hint()
		p.beam.target = c.beam_target())
	c.back_sigil.destroyed.connect(func() -> void: p.beam.target = c.beam_target())
	c.defeated.connect(func() -> void:
		encounter.banner = "DORMIN ROZPROSZONY — WANDER ŻYJE"
		hud.message = c.encounter_hint())
	return {"dormin": c, "colossus": c, "player": p, "players": players, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": c.debug_draw}
