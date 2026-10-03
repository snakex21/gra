extends Node
## Actual campaign construction/hooks, with an inspection camera for one still.
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	var previous := []
	for kind: StringName in BossRoster.PLAYABLE:
		if kind == &"basaran":
			break
		previous.append(String(kind))
	game.start_from({"version": 2, "defeated": previous})
	game._wake(&"basaran")
	game.build_pending()
	_freeze_physics(game)
	var boss := game.colossus()
	if boss.get_node_or_null("ColossiV3Render") == null:
		push_error("Campaign capture did not attach V3 through GameWorld")
		get_tree().quit(1)
		return
	# Authored inspection positions only; no battle is advanced by this capture.
	var player := game.player()
	player.global_position = boss.to_global(Vector3(9, 0.95, -20))
	player.visual.rotation.y = PI
	(game.refs.horse as Horse).teleport(boss.to_global(Vector3(14, 0, -21)), boss.global_rotation.y)
	var cam := Camera3D.new()
	cam.fov = 48
	cam.far = 2000
	add_child(cam)
	cam.look_at_from_position(boss.to_global(Vector3(23, 16, -32)), boss.to_global(Vector3(0, 5.5, 0)))
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/screenshots/colossi_v3"))
	var path := ProjectSettings.globalize_path("res://art/screenshots/colossi_v3/08_campaign_basaran.png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("CAMPAIGN_ART_CAPTURE Basaran through GameWorld.with_art=true: ", path)
	get_tree().quit(0 if err == OK else 1)

func _freeze_physics(node: Node) -> void:
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_physics(child)
