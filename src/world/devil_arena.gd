class_name DevilArena
## Closed cave encounter using the established shell and render-only cave kit.
const DEVIL_START := Vector3.ZERO
const DEVIL_YAW := 0.0
const PLAYER_START := Vector3(0, .95, 90)
const HORSE_START := Vector3(4.5, 0, 87)

static func build(parent: Node3D) -> Dictionary:
	CaveArena.build(parent)
	return {"devil": [DEVIL_START, DEVIL_YAW], "player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}

static func dress(parent: Node3D) -> void:
	CaveArena.dress(parent)

static func spawn(parent: Node3D, seed := 109) -> Devil:
	var c := Devil.new()
	c.name = "Devil"
	c.brain_seed = seed
	parent.add_child(c)
	var start := parent.global_transform * Transform3D(Basis(Vector3.UP, DEVIL_YAW), DEVIL_START)
	c.reset_encounter(start, true)
	return c

static func build_encounter(parent: Node3D, with_input := false, seed := 109, with_art := false) -> Dictionary:
	var points := build(parent)
	if with_art:
		dress(parent)
	var c := spawn(parent, seed)
	if with_art:
		GuardianVisuals.dress(c, "devil")
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(parent.global_transform * HORSE_START, parent.global_rotation.y)
	var player := PlayerCharacter.new()
	player.name = "Player1"
	parent.add_child(player)
	player.global_position = parent.global_transform * PLAYER_START
	player.spawn_transform = player.global_transform
	player.beam.lantern = true
	var camera := PlayerCamera.new()
	camera.player = player
	camera.focus_target = c
	parent.add_child(camera)
	camera.current = true
	camera.snap_behind_player()
	var encounter := BossEncounter.new()
	parent.add_child(encounter)
	var players: Array[PlayerCharacter] = [player]
	encounter.setup(c, players, horse)
	var input: FlatInputSource
	if with_input:
		input = FlatInputSource.new()
		input.actions = player.actions
		input.view = camera
		parent.add_child(input)
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = player
	hud.camera = camera
	hud.horse = horse
	hud.colossus = c
	hud.encounter = encounter
	hud.message = c.encounter_hint()
	layer.add_child(hud)
	parent.add_child(layer)
	c.phase_changed.connect(func(_phase: Devil.Phase) -> void: hud.message = c.encounter_hint())
	return {"devil": c, "colossus": c, "player": player, "players": players, "horse": horse, "camera": camera, "encounter": encounter, "hud": hud, "input": input, "points": points, "debug_draw": c.debug_draw}
