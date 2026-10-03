extends Node
var failures := 0
var world: Node3D
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	if "--capture-devil" in OS.get_cmdline_user_args():
		await capture_devil()
		get_tree().quit(0 if failures == 0 else 1)
		return
	if "--capture-phoenix" in OS.get_cmdline_user_args():
		await capture_phoenix()
		get_tree().quit(0 if failures == 0 else 1)
		return
	await test_devil()
	world.free()
	await ticks(2)
	await test_devil_ambush()
	world.free()
	await ticks(2)
	await test_phoenix()
	world.free()
	await ticks(2)
	await test_phoenix_flame()
	world.free()
	await ticks(2)
	print("Devil/Phoenix: ", failures, " failure(s)")
	get_tree().quit(0 if failures == 0 else 1)
func test_devil() -> void:
	world = Node3D.new()
	world.position = Vector3(87, 5, -43)
	world.rotation.y = .74
	add_child(world)
	var refs := DevilArena.build_encounter(world)
	var c: Devil = refs.devil
	var p: PlayerCharacter = refs.player
	check(p.global_position.distance_to(world.global_transform * DevilArena.PLAYER_START) < .01, "Devil player placement ignores transformed parent")
	await ticks(2)
	check(c.weak_point.state == WeakPoint.State.PROTECTED and not c._patch_open, "Devil is climbable before light")
	var bot := DevilBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	bot.verbose = "--verbose" in OS.get_cmdline_user_args()
	for i in 60 * 180:
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated(), "Devil bot failed: phase %s p %s state %s stats %s" % [bot.phase, p.global_position, c.debug_text(), bot.stats])
	check(c.stats.light_breaks > 0 and c.stats.landings > 0 and bot.light_completed, "Devil skipped ceiling light puzzle")
	check(bot.stats.grabs > 0 and c.stats.weak_point_hits >= 3, "Devil victory skipped climb or charged sword")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.phase == Devil.Phase.HANGING and not c._patch_open and c.weak_point.health == 120, "Devil reset did not restore hanging guardian")
	print("PASS Devil actions, ceiling, light, landing, climb, sword and transformed reset")
func test_devil_ambush() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := DevilArena.build_encounter(world)
	var c: Devil = refs.devil
	var p: PlayerCharacter = refs.player
	p.global_position = Vector3(0, .95, 12)
	for i in 900:
		await ticks(1)
		if c.phase == Devil.Phase.WARNING:
			break
	check(c.phase == Devil.Phase.WARNING and c._warning.visible and not c.get_danger_zones().is_empty(), "Devil ambush has no telegraph")
	p.actions.view_basis = Basis.looking_at(Vector3.RIGHT)
	p.actions.move = Vector2(0, 1)
	var hp := p.health
	await ticks(280)
	p.actions.move = Vector2.ZERO
	check(p.health == hp and c.stats.ambushes > 0, "Devil locked ambush cannot be dodged")
	check(c.weak_point.state == WeakPoint.State.PROTECTED, "Unlit Devil landing must keep the sigil closed")
	print("PASS Devil active locked ambush, warning and evade")

func capture_devil() -> void:
	world = load("res://scenes/devil_arena.tscn").instantiate()
	add_child(world)
	var refs: Dictionary = world.refs
	refs.input.set_physics_process(false)
	refs.input.set_process(false)
	refs.hud.show_debug = false
	refs.hud.show_help = false
	refs.hud.message = ""
	refs.hud.hide()
	for layer in world.get_node("TrialMenu").get_children():
		if layer is CanvasLayer:
			layer.visible = false
	var c: Devil = refs.devil
	var p: PlayerCharacter = refs.player
	var camera: PlayerCamera = refs.camera
	check_guardian_art(c)
	p.global_position = Vector3(0, .95, 14)
	c.debug_override = &"frozen"
	p.actions.beam_held = true
	p.actions.view_basis = Basis.looking_at(c.get_focus_point() - SwordBeam.tip(p))
	camera.set_process(false)
	camera.global_position = Vector3(8, 10, 8)
	camera.look_at(Vector3(0, 17, -4))
	await ticks(30)
	await RenderingServer.frame_post_draw
	var path := PortablePaths.prepare("res://data/captures/devil_ceiling.png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Devil capture not saved")
	print("CAPTURE ", path)
	c.debug_override = &""
	var bot := DevilBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	for i in 60 * 90:
		await ticks(1)
		if c.phase == Devil.Phase.EXPOSED:
			break
	check(c.phase == Devil.Phase.EXPOSED and c._patch_open, "Devil capture never opened the illuminated landing")
	bot.set_physics_process(false)
	c.debug_override = &"frozen"
	p.actions.clear()
	p.global_position = Vector3(0, .95, 5)
	p.actions.beam_held = true
	p.actions.view_basis = Basis.looking_at(c.get_focus_point() - SwordBeam.tip(p))
	camera.global_position = Vector3(8, 5, 9)
	camera.look_at(Vector3(0, 2.6, -4))
	await ticks(25)
	await RenderingServer.frame_post_draw
	path = PortablePaths.prepare("res://data/captures/devil_landed.png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Devil landed capture not saved")
	print("CAPTURE ", path)

func test_phoenix() -> void:
	world = Node3D.new()
	world.position = Vector3(-131, 2, 75)
	world.rotation.y = -.53
	add_child(world)
	var refs := PhoenixArena.build_encounter(world)
	var c: Phoenix = refs.phoenix
	var p: PlayerCharacter = refs.player
	await ticks(2)
	check(c.weak_point.state == WeakPoint.State.PROTECTED and not c._patch_open, "Phoenix shield starts open")
	var bot := PhoenixBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	bot.verbose = "--verbose" in OS.get_cmdline_user_args()
	for i in 60 * 200:
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated(), "Phoenix bot failed: p %s c %s phase %s bot %s" % [p.global_position, c.debug_text(), bot.phase, bot.stats])
	check(c.stats.coolings > 0 and bot.stats.grabs > 0 and c.stats.weak_point_hits >= 3, "Phoenix victory bypassed water or climb")
	refs.encounter.reset_encounter()
	bot.set_physics_process(false)
	p.actions.clear()
	await ticks(2)
	check(c.phase == Phoenix.Phase.HOT and c.weak_point.health == 120 and not c._patch_open, "Phoenix reset did not restore heat shield")
	p.global_position = world.global_transform * Vector3(-25.7, .95, -19.5)
	for i in 1800:
		await ticks(1)
		if c.phase == Phoenix.Phase.COOLED:
			break
	check(c.phase == Phoenix.Phase.COOLED, "Phoenix could not cool again after reset")
	await ticks(60 * 26)
	check(c.weak_point.state == WeakPoint.State.PROTECTED and not c._patch_open, "Phoenix heat did not rebuild after cooldown")
	print("PASS Phoenix lure, waterfall cooling, climb, sword, transformed placement, reset and rebuilding heat")

func capture_phoenix() -> void:
	world = load("res://scenes/phoenix_arena.tscn").instantiate()
	add_child(world)
	var refs: Dictionary = world.refs
	refs.input.set_physics_process(false)
	refs.input.set_process(false)
	refs.hud.show_debug = false
	refs.hud.show_help = false
	refs.hud.message = ""
	refs.hud.hide()
	for layer in world.get_node("TrialMenu").get_children():
		if layer is CanvasLayer:
			layer.visible = false
	var c: Phoenix = refs.phoenix
	var bot := PhoenixBot.new()
	check_guardian_art(c)
	world.add_child(bot)
	bot.setup(refs.player, c, refs.encounter)
	for i in 60 * 150:
		await ticks(1)
		if c.phase == Phoenix.Phase.COOLED:
			break
	check(c.phase == Phoenix.Phase.COOLED, "Phoenix capture route did not reach waterfall cooling")
	refs.hud.message = ""
	refs.camera.set_process(false)
	refs.camera.global_position = c.global_position + Vector3(9, 5, 11)
	refs.camera.look_at(c.global_position + Vector3.UP * 1)
	await ticks(2)
	await RenderingServer.frame_post_draw
	var path := PortablePaths.prepare("res://data/captures/phoenix_cooled.png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Phoenix capture not saved")
	print("CAPTURE ", path)

func test_phoenix_flame() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := PhoenixArena.build_encounter(world)
	var c: Phoenix = refs.phoenix
	var p: PlayerCharacter = refs.player
	p.global_position = Vector3(0, .95, 13)
	for i in 600:
		await ticks(1)
		if c.fire_active:
			break
	check(c.fire_active and c._warning.visible and not c.get_danger_zones().is_empty(), "Phoenix flame has no telegraph: active=%s warning=%s zones=%s state=%s" % [c.fire_active, c._warning.visible, c.get_danger_zones(), c.debug_text()])
	var hp := p.health
	p.actions.view_basis = Basis.looking_at(Vector3.RIGHT)
	p.actions.move = Vector2(0, 1)
	await ticks(115)
	p.actions.move = Vector2.ZERO
	check(p.health == hp and c.stats.get("flame_casts", 0) > 0, "Phoenix locked flame cannot be evaded")
	for i in 600:
		await ticks(1)
		if c.stats.hits_on_player > 0:
			break
	check(c.stats.hits_on_player > 0, "Phoenix never actively attacks a stationary intruder")
	print("PASS Phoenix locked flame warning, dodge and active damage")

func check_guardian_art(c: WingedGuardian) -> void:
	for bone in [&"body", &"wing_l", &"wing_r"]:
		var segment: BodySegment = c._seg_by_bone[bone]
		var art := segment.get_node_or_null("GuardianArt")
		check(art != null and art.get_child_count() == 3, "%s is missing the three imported Blender LODs" % bone)
		if art == null:
			continue
		var previous := 100000
		for child in art.get_children():
			check(child is MeshInstance3D and child.mesh != null and child.position == Vector3.ZERO, "%s has an invalid or displaced visual" % bone)
			if not child is MeshInstance3D or child.mesh == null:
				continue
			var mesh: Mesh = child.mesh
			var triangles := 0
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
			check(triangles > 0 and triangles < previous and triangles <= 8000, "%s LOD triangle budget/reduction is invalid: %d" % [bone, triangles])
			previous = triangles
			check(child.layers == (2 if c is Devil else 1), "%s visual uses the wrong cave/daylight layer" % bone)
		for child in segment.get_children():
			if child.has_meta(&"guardian_placeholder"):
				check(not child.visible, "%s shows overlapping rig and Blender geometry" % bone)
