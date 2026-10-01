class_name GaiusArena
## Arena for Gaius: the basin of the Valus arena (open ground in front of him for the
## sword to come down, ruins and rocks on the rim). Gaius in the middle facing the
## entrance, the player and Agro ~80 m away.

const GAIUS_START := Vector3(0, 0, 0)


## Everything for a playable / testable fight (see ValusArena.build_encounter).
static func build_encounter(parent: Node3D, with_input := false, brain_seed := 13, with_art := false) -> Dictionary:
	var points := ValusArena.build(parent)
	var g := Gaius.new()
	g.name = "Gaius"
	g.brain_seed = brain_seed
	g.position = GAIUS_START
	g.rotation.y = PI
	parent.add_child(g)
	g.teleport(GAIUS_START, PI)
	g.reset_encounter(g.global_transform, true)
	if with_art:
		# Render-only: collision, climbing and AI are the greybox ones.
		ArenaArt.dress_arena(parent, Vector3(0, 0, 1), 55.0, 5113)
		ArenaArt.skin_colossus(g)

	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(ValusArena.HORSE_START, 0.0)

	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = ValusArena.PLAYER_START
	p.facing = Vector3.FORWARD
	p.spawn_transform = p.global_transform
	p.actions.view_basis = Basis.IDENTITY
	p.reset_physics_interpolation()
	ArrowSystem.of(p)

	var cam := PlayerCamera.new()
	cam.name = "Camera1"
	cam.player = p
	cam.focus_target = g
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
	encounter.setup(g, players, horse)

	var draw := CombatDebugDraw.new()
	draw.valus = g
	parent.add_child(draw)

	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = g
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"gaius": g, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": draw, "input": input, "points": points}
