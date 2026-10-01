extends Node
## Quick look at the art layer: both arenas with the art pack, a few fixed views
## (no bot). Saves tests/output/art_*.png. Run with tools/capture_screenshots.sh art.

const VIEWS := [
	["valus", "art_01_valus_arena", Vector3(18, 4, 46), Vector3(0, 8, 0)],
	["valus", "art_02_valus_close", Vector3(9, 6, 14), Vector3(0, 10, 0)],
	["quadratus", "art_03_quadratus_arena", Vector3(-20, 4, 42), Vector3(0, 6, 0)],
	["quadratus", "art_04_quadratus_close", Vector3(12, 5, 14), Vector3(0, 7, 0)],
]

var _i := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	_next()


func _next() -> void:
	for c in get_children():
		c.queue_free()
	if _i >= VIEWS.size():
		get_tree().quit()
		return
	var v: Array = VIEWS[_i]
	var scene: Node3D = load("res://scenes/%s_arena.tscn" % v[0]).instantiate()
	add_child(scene)
	for k in 30:
		await get_tree().physics_frame
	var refs: Dictionary = scene.refs
	if refs.input:
		(refs.input as Node).queue_free()
	(refs.hud as Control).visible = false
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.global_position = v[2]
	cam.look_at(v[3])
	cam.fov = 60.0
	cam.current = true
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % v[1]))
	print("shot ", v[1])
	_i += 1
	_next()
