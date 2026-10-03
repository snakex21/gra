extends Node3D
## Real GameWorld temple, imported traveler/Mono hooks and binary checkpoints.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var game := GameWorld.new()
	game.name = "ActualTempleWorld"
	game.with_art = true
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	# Leave dressing queued for the remote arenas. The valley is fully authored;
	# disabling world ticks keeps an identical graph for the two LOD size samples.
	game.set_physics_process(false)
	await ticks(3)
	check(game.with_art and game.region_kind == GameWorld.VALLEY, "Temple fixture did not start a real world with art")
	var p := game.player()
	var art := p.visual.get_node_or_null("TravelerArt") as TravelerArt
	var altar := game.region.find_child("altar_*", true, false) as Node3D
	var mono := game.region.find_child("MonoSleeping", true, false) as Node3D
	check(art != null and art.model != null, "PlayerVisual hook did not attach the imported traveler in GameWorld")
	check(altar != null and mono != null, "Valley hook did not put Mono at the actual temple altar")
	if not art or not altar or not mono:
		get_tree().quit(1)
		return
	check_mono(altar, mono)
	art.auto_lod = false
	art.set_lod(0)
	await ticks(2)
	var near_data := WorldSnapshot.capture(game)
	var near_bytes := var_to_bytes(near_data)
	art.set_lod(2)
	await ticks(2)
	check(art.current_lod == 2, "Temple checkpoint fixture did not reach traveler LOD2")
	var data: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	var checkpoint := var_to_bytes(data)
	var encoded := var_to_str(data)
	check(not "TravelerArt" in encoded and not "TravelerModelLOD" in encoded and not "MonoSleeping" in encoded, "Checkpoint recorded purely cosmetic traveler/Mono nodes")
	check(not "res://models/characters/" in encoded and not "res://textures/characters/" in encoded and not "traveler_art.gd" in encoded, "Checkpoint embedded rendering assets or the traveler adapter")
	check(data.nodes.size() == near_data.nodes.size() and data.objects.size() == near_data.objects.size(), "Changing cosmetic LOD changed checkpoint topology")
	check(absi(checkpoint.size() - near_bytes.size()) < 1024, "Cosmetic LOD inflated the checkpoint by %d bytes" % (checkpoint.size() - near_bytes.size()))
	var checkpoint_folder := ProjectSettings.globalize_path("res://data/tests")
	DirAccess.make_dir_recursive_absolute(checkpoint_folder)
	var saved := FileAccess.open("res://data/tests/temple_characters_v3.checkpoint", FileAccess.WRITE)
	check(saved != null, "Temple checkpoint could not be saved inside the game folder")
	if saved:
		saved.store_buffer(checkpoint)
		saved.close()
	var at := p.global_position
	var game_time := game.state.play_time
	check(WorldSnapshot.restore(game, data), "WorldSnapshot restore failed with art=true and a prior traveler LOD2")
	p = game.player()
	art = p.visual.get_node_or_null("TravelerArt") as TravelerArt
	altar = game.region.find_child("altar_*", true, false) as Node3D
	mono = game.region.find_child("MonoSleeping", true, false) as Node3D
	check(p.global_position.distance_to(at) < .001 and is_equal_approx(game.state.play_time, game_time), "Art checkpoint restore changed player position or progress time")
	check(art != null and art.current_lod == 0 and art.model != null, "Restored traveler did not rebuild its independent render LOD0")
	check(altar != null and mono != null, "Restored art world lost Mono or the real altar")
	if not art or not altar or not mono:
		get_tree().quit(1)
		return
	check_mono(altar, mono)
	art.auto_lod = false
	for i in 2:
		check(is_instance_valid(art._arms[i]) and art._arms[i].get_parent() == p.visual._arms[i], "Restored traveler shoulder refers to the old freed world")
	p.actions.view_basis = Basis.IDENTITY
	p.actions.move = Vector2(0, 1)
	await ticks(90)
	check(p.global_position.z < at.z - 4.5 and p.state == PlayerCharacter.State.GROUND and not p.dead, "Restored art world could not continue walking through PlayerActions")
	p.actions.clear()
	await ticks(3)
	print("Temple characters v3: checkpoint LOD0=%d bytes, LOD2=%d bytes, nodes=%d, objects=%d" % [near_bytes.size(), checkpoint.size(), data.nodes.size(), data.objects.size()])
	if DisplayServer.get_name() != "headless":
		await capture_temple(game, p, art, altar)
	print("Temple characters v3: %d failure(s); actual GameWorld art, traveler/Mono hooks, altar orientation, lean LOD2 checkpoint, restore and action-driven continuation" % failures)
	get_tree().quit(1 if failures else 0)

func check_mono(altar: Node3D, mono: Node3D) -> void:
	var local := altar.to_local(mono.global_position)
	check(local.distance_to(Vector3(0, 1.64, 0)) < .001, "Mono is not on the actual altar's local top plane: %s" % local)
	check(mono.global_basis.z.normalized().dot(altar.global_basis.x.normalized()) > .999 and mono.global_basis.y.normalized().dot(altar.global_basis.y.normalized()) > .999, "Mono head/face orientation does not match the altar X axis and upward face")
	check(mono.find_children("*", "CollisionObject3D", true, false).is_empty(), "Mono art unexpectedly added gameplay collisions")
	var geometry := mono.find_child("*", true, false) as MeshInstance3D
	if not geometry:
		var meshes := mono.find_children("*", "MeshInstance3D", true, false)
		geometry = meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	check(geometry != null and geometry.mesh != null, "Sleeping Mono has no imported render mesh")
	if geometry and geometry.mesh:
		var bounds := geometry.get_aabb()
		var min_y := INF
		var max_x := -INF
		var min_x := INF
		for i in 8:
			var point := altar.to_local(geometry.to_global(bounds.get_endpoint(i)))
			min_y = minf(min_y, point.y)
			max_x = maxf(max_x, point.x)
			min_x = minf(min_x, point.x)
		check(min_y > 1.648 and min_y < 1.660 and min_x > -1.36 and max_x < 1.36, "Mono clips below the altar top or extends beyond its 2.7m width")

func capture_temple(game: GameWorld, p: PlayerCharacter, art: TravelerArt, altar: Node3D) -> void:
	p.set_physics_process(false)
	art.set_process(false)
	var gear := p.visual.get_node_or_null("WeaponArt") as Node3D
	if gear:
		gear.set_process(false)
		gear.visible = false
	art.set_lod(0)
	p.global_position = altar.global_position + Vector3(-1.85, Valley.ground_height(altar.global_position.x - 1.85, altar.global_position.z - .65) - altar.global_position.y + .90, -.65)
	p.visual.transform = Transform3D.IDENTITY
	art.pose_preview(&"idle")
	(game.refs.camera as PlayerCamera).set_physics_process(false)
	(game.refs.camera as PlayerCamera).set_process(false)
	(game.refs.hud as PlayerHud).visible = false
	var camera := Camera3D.new()
	camera.name = "TempleCharactersCaptureCamera"
	add_child(camera)
	camera.fov = 38
	camera.global_position = altar.global_position + Vector3(2.65, 3.55, -5.80)
	camera.look_at(altar.global_position + Vector3(-.55, 1.20, -.20))
	camera.current = true
	var toward_camera := camera.global_position - p.global_position
	p.visual.rotation.y = atan2(-toward_camera.x, -toward_camera.z)
	# Soft local bounce for the close inspection, without changing gameplay or
	# replacing the temple's sun, sky, materials, geometry and real actor hooks.
	var bounce := OmniLight3D.new()
	bounce.name = "CaptureBounce"
	add_child(bounce)
	bounce.global_position = altar.global_position + Vector3(-2.0, 3.4, -2.8)
	bounce.omni_range = 9
	bounce.light_color = Color(.82,.88,1)
	bounce.light_energy = 1.1
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://data/captures/temple_characters_v3.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Actual temple character capture failed")
	print("Saved ", path)
