extends Node3D
## Agro test scene: open ground, ramp/bumps/step course, rocks, a narrow passage, an
## impassable wall and a cliff. The player starts next to Agro.

var players: Array[PlayerCharacter] = []
var horse: Horse
var points := {}


func _ready() -> void:
	InputSetup.ensure_defaults()
	points = AgroArena.build(self)
	horse = Horse.new()
	horse.name = "Agro"
	add_child(horse)
	horse.teleport(Vector3(2, 0, 16), 0.0)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	add_child(p)
	p.global_position = Vector3(0.6, 0.95, 16.3)
	p.spawn_transform = p.global_transform
	players.append(p)
	var cam := PlayerCamera.new()
	cam.player = p
	add_child(cam)
	cam.current = true
	cam.snap_behind_player()
	var input := FlatInputSource.new()
	input.actions = p.actions
	input.view = cam
	add_child(input)
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = cam
	hud.horse = horse
	layer.add_child(hud)
	add_child(layer)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"respawn"):
		for p in players:
			p.respawn()
	elif event.is_action_pressed(&"debug_draw"):
		horse.debug_draw.visible = not horse.debug_draw.visible
	elif event.is_action_pressed(&"ride_steer_mode"):
		for p in players:
			p.riding.steer_relative = not p.riding.steer_relative
