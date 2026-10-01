extends Node3D
## Milestone 1 sandbox: flat arena, a few ruins, one greybox colossus, N players.
## There is no global Player: players[] is built here and every system receives
## references explicitly.

@export var player_count := 1

var players: Array[PlayerCharacter] = []
var cameras: Array[PlayerCamera] = []

@onready var colossus: Colossus = $Colossus
@onready var spawn: Marker3D = $PlayerSpawn


func _ready() -> void:
	InputSetup.ensure_defaults()
	_build_ruins()
	for i in player_count:
		_spawn_player(i)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_player(index: int) -> void:
	var p := PlayerCharacter.new()
	p.name = "Player%d" % (index + 1)
	p.player_index = index
	add_child(p)
	p.global_position = spawn.global_position + Vector3(index * 1.5, 0.0, 0.0)
	p.facing = PlayerCharacter._flat_dir(colossus.global_position - p.global_position, Vector3.FORWARD)
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()

	var cam := PlayerCamera.new()
	cam.name = "Camera%d" % (index + 1)
	cam.player = p
	cam.focus_target = colossus
	add_child(cam)
	cam.current = index == 0
	cam.snap_behind_player()

	var input := FlatInputSource.new()
	input.name = "Input%d" % (index + 1)
	input.actions = p.actions
	input.view = cam
	add_child(input)

	p.died.connect(func() -> void: print("%s died" % p.name))
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.colossus = colossus
	hud.camera = cam
	layer.add_child(hud)
	add_child(layer)

	players.append(p)
	cameras.append(cam)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"respawn"):
		for p in players:
			p.respawn()
		for c in cameras:
			c.snap_behind_player()
	elif event.is_action_pressed(&"debug_colossus_mode"):
		colossus.cycle_debug_override()


## Static ruins: camera obstacles and a climbable wall (vines = ClimbPatch) with a
## walkable top, so climbing can be compared on static vs moving geometry.
func _build_ruins() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.6, 0.55)
	var vines := StandardMaterial3D.new()
	vines.albedo_color = Color(0.25, 0.38, 0.2)

	for i in 7:
		var a := i * TAU / 7.0 + 0.3
		var h := 5.0 + (i % 3) * 3.0
		_block(Vector3(cos(a) * 38.0, h * 0.5, sin(a) * 38.0), Vector3(2.2, h, 2.2), stone)

	# Climbable wall: stone core + vine patch on its front (+Z) face.
	var wall := _block(Vector3(14, 3.5, 6), Vector3(10, 7, 2), stone)
	var vine_shape := ClimbPatch.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 6.6, 0.3)
	vine_shape.shape = box
	vine_shape.position = Vector3(0, -0.2, 1.1)
	wall.add_child(vine_shape)
	var vine_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	vine_mesh.mesh = bm
	vine_mesh.position = vine_shape.position
	vine_mesh.material_override = vines
	wall.add_child(vine_mesh)


func _block(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	return body
