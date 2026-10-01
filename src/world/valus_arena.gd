class_name ValusArena
## Greybox arena for the first boss: a wide open basin with a few gentle height changes,
## scattered ruins and rocks at the edge (never a maze), the Valus in the middle, the
## player and Agro at the entrance ~80 m away. Gameplay works on these placeholders; art
## assets can replace the boxes later without changing the layout.
##
## build() makes the geometry; build_encounter() also creates the Valus, the player,
## Agro, the camera, the HUD and the BossEncounter, and returns them all.

const VALUS_START := Vector3(0, 0, 0)
const PLAYER_START := Vector3(0, 0.95, 80)
const HORSE_START := Vector3(4.5, 0, 77)
## Cheap world-space grid on the ground so scale and motion read in the greybox.
const GRID_SHADER := """shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.5, 0.48, 0.38);
uniform vec3 line_color : source_color = vec3(0.4, 0.38, 0.3);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float grid(vec2 p, float cell, float width) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	vec2 fw = fwidth(p) * 0.75 + width;
	vec2 l = 1.0 - smoothstep(vec2(0.0), fw, g);
	return max(l.x, l.y);
}
void fragment() {
	float g = max(grid(world_pos.xz, 2.0, 0.02) * 0.4, grid(world_pos.xz, 10.0, 0.06));
	ALBEDO = mix(base_color, line_color, g);
	ROUGHNESS = 1.0;
}
"""


static func build(parent: Node3D) -> Dictionary:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 2, 500)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	gm.mesh = plane
	var grid := Shader.new()
	grid.code = GRID_SHADER
	var gmat := ShaderMaterial.new()
	gmat.shader = grid
	gm.material_override = gmat
	ground.add_child(gm)
	parent.add_child(ground)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.6, 0.58, 0.53)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.45, 0.44, 0.41)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.5, 0.46, 0.36)
	# Entrance: two pillars the player rides / walks through.
	TerrainKit.box(parent, Vector3(-7, 5, 62), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(7, 5, 62), Vector3(2.5, 10, 2.5), stone)
	TerrainKit.box(parent, Vector3(0, 10.8, 62), Vector3(17, 1.6, 2.8), dark)
	# Height differences: a low terrace with a ramp on the west, a mound on the east.
	TerrainKit.ramp(parent, Vector3(-46, 0, 18), 14.0, 8.0, 14.0, dirt)
	TerrainKit.box(parent, Vector3(-46, 0.0, -6.0), Vector3(14, 3.94, 20), dirt)
	TerrainKit.ramp(parent, Vector3(44, 0, -20), 10.0, 10.0, 10.0, dirt)
	TerrainKit.box(parent, Vector3(44, 0.0, -37), Vector3(10, 3.52, 14), dirt)
	# Ruins on the rim: broken columns and fallen blocks (cover, landmarks, camera tests).
	for i in 9:
		var a := i * TAU / 9.0 + 0.35
		var r := 56.0 + (i % 3) * 4.0
		var h := 4.0 + (i % 4) * 2.5
		TerrainKit.box(parent, Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(2.4, h, 2.4), stone if i % 2 == 0 else dark, Basis(Vector3.UP, a))
	TerrainKit.box(parent, Vector3(28, 1.0, 34), Vector3(6, 2, 3), dark, Basis(Vector3.UP, 0.4))
	TerrainKit.box(parent, Vector3(-30, 1.2, 40), Vector3(4, 2.4, 4), stone, Basis(Vector3.UP, 0.9))
	TerrainKit.box(parent, Vector3(-22, 0.8, -40), Vector3(5, 1.6, 3), dark, Basis(Vector3.UP, 1.4))
	# A few rocks (Agro avoids them, the player can use them to break line of sight).
	for rk in [[Vector3(18, 0, 52), 2.0], [Vector3(-16, 0, 58), 1.6], [Vector3(36, 0, 8), 2.4], [Vector3(-34, 0, -24), 2.2]]:
		var c: Vector3 = rk[0]
		var s: float = rk[1]
		TerrainKit.box(parent, c + Vector3(0, s * 0.45, 0), Vector3(s * 1.3, s * 0.9, s * 1.1), dark, Basis(Vector3.UP, c.x * 0.1))
	return {
		"valus": [VALUS_START, PI],
		"player": [PLAYER_START, 0.0],
		"horse": [HORSE_START, 0.0],
	}


## Everything for a playable / testable fight. ``with_input`` adds the keyboard/mouse/pad
## input source (scenes); tests and bots drive PlayerActions themselves.
static func build_encounter(parent: Node3D, with_input := false, brain_seed := 7, with_art := false) -> Dictionary:
	var points := build(parent)
	var valus := Valus.new()
	valus.name = "Valus"
	valus.brain_seed = brain_seed
	valus.position = VALUS_START
	valus.rotation.y = PI
	parent.add_child(valus)
	valus.teleport(VALUS_START, PI)
	valus.reset_encounter(valus.global_transform, true)
	if with_art:
		# Render-only: collision, climbing and AI are the greybox ones.
		ArenaArt.dress_arena(parent, Vector3(0, 0, 1), 55.0)
		ArenaArt.dress_valus(valus)

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
	cam.focus_target = valus
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
	encounter.setup(valus, players, horse)

	var draw := CombatDebugDraw.new()
	draw.valus = valus
	parent.add_child(draw)

	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = valus
	hud.camera = cam
	hud.horse = horse
	hud.encounter = encounter
	layer.add_child(hud)
	parent.add_child(layer)
	return {"valus": valus, "player": p, "horse": horse, "camera": cam, "encounter": encounter, "hud": hud, "debug_draw": draw, "input": input, "points": points}
