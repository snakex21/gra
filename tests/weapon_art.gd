extends Node3D
## Real actions, imported equipment, native arrows, mount and binary restoration.
var failures := 0
var camera: Camera3D
var deadline := Time.get_ticks_msec() + 120000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Weapon integration test timed out or stopped after a runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame
	await get_tree().process_frame

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	for id in ["sword", "bow", "arrow", "scabbard", "quiver"]:
		for lod in 3:
			var packed := load(WeaponArt.FOLDER + id + "_lod%d.glb" % lod) as PackedScene
			check(packed != null, "Weapon GLB failed to import: %s LOD%d" % [id, lod])
			if not packed: continue
			var instance := packed.instantiate() as Node3D
			add_child(instance)
			check(not instance.find_children("*", "MeshInstance3D", true, false).is_empty(), "Imported weapon contains no render geometry")
			check(instance.find_children("*", "CollisionObject3D", true, false).is_empty(), "Equipment added gameplay collision")
			if id == "bow":
				check(instance.find_child("StringTop*", true, false) != null and instance.find_child("StringBottom*", true, false) != null and instance.find_child("NockRest*", true, false) != null, "Bow lost attachment markers")
				var morph := false
				for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
					morph = morph or mesh.find_blend_shape_by_name("BowDraw") >= 0
				check(morph, "Bow LOD%d has no actual limb deformation" % lod)
			instance.free()
	var game := GameWorld.new()
	game.layout_version = 2
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	game.start(true)
	game.set_physics_process(false)
	var p := game.player()
	p.global_position = Valley.on_ground(Vector3(12, 0, -38)) + Vector3.UP * .9
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	await ticks(30)
	var gear := p.visual.get_node_or_null("WeaponArt") as WeaponArt
	var art := p.visual.get_node_or_null("TravelerArt") as TravelerArt
	check(gear != null and gear.sword != null and gear.bow != null, "Main PlayerVisual did not attach imported equipment")
	if not gear or not gear.sword or not gear.bow:
		get_tree().quit(1)
		return
	gear.auto_lod = false
	art.auto_lod = false
	check(gear.sword.visible and gear.stored_bow.visible and not gear.stored_sword.visible, "Selected sword/bow carrying visibility is wrong")
	check(not p.visual._blade.visible, "Legacy box sword overlaps the imported sword")
	check(gear.hand_errors[1] < .04, "Sword grip does not sit in the right hand: %.4fm" % gear.hand_errors[1])
	if DisplayServer.get_name() != "headless":
		make_camera(game, p)
		await shot("01_sword_equipped", p)
	# A real beam raise must put the rendered tip at the gameplay light origin.
	p.actions.view_basis = Basis.IDENTITY
	p.actions.beam_held = true
	await ticks(40)
	gear.update_equipment(0)
	check(p.beam.raise > .99, "Sword could not be raised through actions")
	check(gear.sword.to_global(Vector3(0, gear._tip_y, 0)).distance_to(SwordBeam.tip(p)) < .01, "Beam originates outside the imported blade tip")
	check(gear.hand_errors[1] < .04, "Raised sword is disconnected from the hand")
	if camera: await shot("02_sword_raised", p)
	p.beam.lantern = true
	await ticks(2)
	check(p.visual._lantern.visible, "Equipment broke cave sword flashlight")
	p.beam.lantern = false
	p.actions.beam_held = false
	await ticks(35)
	p.actions.press_switch_weapon()
	await ticks(4)
	check(p.weapon == PlayerCharacter.Weapon.BOW and gear.bow.visible and gear.stored_sword.visible and not gear.sword.visible, "Action weapon switch did not equip the bow and sheath sword")
	p.actions.view_basis = Basis.looking_at(Vector3(0, .12, -1).normalized())
	p.actions.attack_held = true
	await ticks(75)
	gear.update_equipment(0)
	check(p.bow.state == PlayerBow.State.AIM and gear.draw_value > .99 and gear.arrow.visible, "Real full bow draw has no visible arrow/string deformation")
	check(gear.string_top.visible and gear.string_bottom.visible and not gear._flex_meshes.is_empty(), "The drawn bow has no string or flexing limb")
	check(gear.arrow.global_position.distance_to(p.bow.launch_point) < .01, "The fully drawn nock does not match the physical arrow launch point")
	check(float(gear.hand_errors[0]) < .04 and float(gear.hand_errors[1]) < .04, "Archery hands miss their grips: %s" % [gear.hand_errors])
	if camera: await shot("03_bow_draw", p)
	var near := WorldSnapshot.capture(game)
	for lod in [1, 2]:
		gear.set_lod(lod)
		art.set_lod(lod)
		await ticks(3)
		gear.update_equipment(0)
		check(gear.bow.visible and gear.arrow.visible and float(gear.hand_errors[0]) < .04, "Weapon/hand attachment disappeared at LOD%d" % lod)
	var data := WorldSnapshot.capture(game)
	var text := var_to_str(data)
	check(not "WeaponArt" in text and not "weapons_v4" in text and not "HandGrip_" in text, "World checkpoint recorded cosmetic equipment or wrists")
	check(data.nodes.size() == near.nodes.size() and data.objects.size() == near.objects.size() and var_to_bytes(data).size() == var_to_bytes(near).size(), "Equipment LOD changed the saved simulation graph")
	check(WorldSnapshot.restore(game, bytes_to_var(var_to_bytes(data))), "Binary checkpoint could not resume a fully drawn bow")
	p = game.player()
	gear = p.visual.get_node("WeaponArt") as WeaponArt
	art = p.visual.get_node("TravelerArt") as TravelerArt
	gear.auto_lod = false
	art.auto_lod = false
	await ticks(4)
	gear.update_equipment(0)
	check(p.bow.is_aiming() and gear.bow.visible and gear.arrow.visible, "Restored draw lost its gameplay state or equipment")
	var before_release := gear.arrow.global_position
	p.actions.attack_held = false
	await ticks(2)
	var arrows := ArrowSystem.of(p)
	check(p.bow.shots == 1 and not arrows.arrows.is_empty(), "Releasing the bow did not fire a physical arrow")
	check((p.bow.last_shot.point as Vector3).distance_to(before_release) < .03, "Full draw release jumped away from the visible nock")
	check(not gear.arrow.visible, "A second nocked arrow remains visible after release")
	if not arrows.arrows.is_empty():
		var arrow_node := arrows.arrows[0].node as MeshInstance3D
		check(arrow_node.mesh == null and arrow_node.has_node("ArrowModel"), "Projectile is still a box instead of the imported arrow")
		check((arrow_node.get_node("ArrowModel") as Node3D).position.length() < .001, "Flying arrow jumps relative to the held arrow nock")
		data = WorldSnapshot.capture(game)
		check(WorldSnapshot.restore(game, bytes_to_var(var_to_bytes(data))), "Flight checkpoint could not restore the imported arrow carrier")
		p = game.player()
		arrows = ArrowSystem.of(p)
		await ticks(5)
		check(not arrows.arrows.is_empty() and (arrows.arrows[0].node as Node).has_node("ArrowModel"), "Restored flight lost the rendered arrow or stable native node")
	# An early release must be just as continuous as the fully drawn shot.
	await ticks(40)
	p.actions.attack_held = true
	await ticks(25)
	gear = p.visual.get_node("WeaponArt") as WeaponArt
	gear.update_equipment(0)
	check(p.bow.draw > .2 and p.bow.draw < .8, "Partial-draw fixture is outside its release window")
	before_release = gear.arrow.global_position
	check(before_release.distance_to(p.bow.launch_point) < .01, "Partial draw nock does not follow the physical launch point")
	p.actions.attack_held = false
	await ticks(2)
	check(p.bow.shots == 2 and (p.bow.last_shot.point as Vector3).distance_to(before_release) < .03, "Partial bow release has a visible jump or did not fire")
	# Mount with actions; the ordinary equipment hook follows the new rider pose.
	p.actions.clear()
	var horse: Horse = game.refs.horse
	p.global_position = horse.saddle_transform().origin - horse.global_basis.x * 1.4
	p.global_position.y = horse.global_position.y + .95
	p.reset_physics_interpolation()
	await ticks(20)
	p.actions.press_interact()
	await ticks(120)
	check(p.is_riding(), "Equipment fixture failed to mount Agro through actions")
	p.actions.attack_held = true
	p.actions.view_basis = Basis.looking_at(Vector3(-.3, .1, -1).normalized())
	await ticks(75)
	gear = p.visual.get_node("WeaponArt") as WeaponArt
	gear.update_equipment(0)
	check(p.bow.is_aiming() and gear.bow.visible and gear.arrow.visible and float(gear.hand_errors[0]) < .04, "Bow/hand pose does not work in the actual mounted state")
	check(gear.arrow.global_position.distance_to(p.bow.bow_point(p)) < .0001, "Mounted held nock is detached from the corrected physical muzzle")
	if camera: await shot("04_bow_on_agro", p)
	# The corrected mounted socket survives a binary restore, without persisting
	# an ArrowModel offset or introducing any second visual projectile origin.
	var mounted_point := p.bow.bow_point(p)
	data = WorldSnapshot.capture(game)
	check(WorldSnapshot.restore(game, bytes_to_var(var_to_bytes(data))), "Mounted draw checkpoint failed to restore")
	p = game.player()
	gear = p.visual.get_node("WeaponArt") as WeaponArt
	gear.update_equipment(0)
	check(p.is_riding() and p.bow.bow_point(p).distance_to(mounted_point) < .0001, "Mounted checkpoint changed the physical muzzle")
	check(gear.arrow.global_position.distance_to(mounted_point) < .0001, "Mounted checkpoint detached visible arrow from physical muzzle")
	var mounted_launches: Array = []
	p.bow.shot.connect(func(a: Dictionary) -> void:
		var model := (a.node as Node3D).get_node("ArrowModel") as Node3D
		mounted_launches.append({"start":a.start,"tail":model.global_position,"local":model.position,"velocity":a.vel}))
	for repeated in 2:
		gear.update_equipment(0)
		var held_tail := gear.arrow.global_position
		p.actions.attack_held = false
		await ticks(2)
		check(mounted_launches.size() == repeated + 1, "Repeated mounted release did not create exactly one projectile")
		if mounted_launches.size() > repeated:
			var launch: Dictionary = mounted_launches[repeated]
			check((launch.start as Vector3).distance_to(held_tail) < .03, "Repeated mounted shot jumps away from held nock")
			check((launch.tail as Vector3).distance_to(launch.start) < .0001 and launch.local == Vector3.ZERO, "Mounted projectile hides a physical/visual origin mismatch")
		await ticks(40)
		p.actions.attack_held = true
		await ticks(25 if repeated == 0 else 75)
	p.actions.clear()
	game.free()
	await ticks(2)
	# A real climbing sword strike, rather than an inspection-only pose.
	game = GameWorld.new()
	game.layout_version = 2
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	game._wake(&"valus")
	p = game.player()
	p.global_position = game.arenas[&"valus"].xf * ValusArena.PLAYER_START
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var bot := ValusBot.new()
	add_child(bot)
	bot.setup(p, game.colossus(), game.refs.encounter)
	var saw_charge := false
	var saw_strike := false
	# Let the bot acquire a genuine fur grip, then exercise the action being tested
	# directly. Reaching a weak point belongs to the encounter tests.
	for i in 60 * 45:
		await ticks(1)
		if p.is_climbing(): break
	bot.set_physics_process(false)
	p.actions.clear()
	p.actions.grab_held = true
	p.actions.attack_held = true
	for i in 90:
		await ticks(1)
		if p.sword.charge > .35: p.actions.attack_held = false
		if p.is_climbing() and p.sword.is_busy():
			saw_charge = saw_charge or p.sword.state == PlayerSword.State.CHARGE
			saw_strike = saw_strike or p.sword.state == PlayerSword.State.STRIKE
			gear = p.visual.get_node("WeaponArt") as WeaponArt
			gear.update_equipment(0)
			check(gear.sword.visible and not gear.stored_sword.visible, "Climbing attack did not draw the physical sword model")
		if saw_charge and saw_strike: break
	p.actions.attack_held = false
	await ticks(30)
	check(saw_charge and saw_strike and p.sword.strikes > 0, "No real climbing charge and sword strike were observed")
	if not saw_charge or not saw_strike:
		print("Climb fixture: player=%s at=%s sword=%s bot=%s stats=%s" % [p.get_display_state(), p.global_position, p.sword.state_name(), ValusBot.Phase.keys()[bot.phase], bot.stats])
	bot.free()
	game.free()
	await ticks(2)
	print("Weapon art: %d failure(s); 15 GLBs, real sword/light, bow draw/release, visible arrows, all LOD grips, mount, climbing strike and binary restores" % failures)
	get_tree().quit(1 if failures else 0)

func make_camera(game: GameWorld, p: PlayerCharacter) -> void:
	(game.refs.camera as PlayerCamera).set_physics_process(false)
	(game.refs.camera as PlayerCamera).set_process(false)
	(game.refs.hud as PlayerHud).visible = false
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 35
	camera.current = true
	var fill := OmniLight3D.new()
	add_child(fill)
	fill.position = p.global_position + Vector3(-2, 2, -3)
	fill.light_energy = 2
	fill.omni_range = 8
	fill.light_color = Color(.83, .89, 1)

func shot(label: String, p: PlayerCharacter) -> void:
	camera.current = true
	var aiming := p.bow.is_aiming()
	var direction := -p.actions.view_basis.z if aiming else p.facing
	var right := direction.cross(Vector3.UP).normalized()
	camera.global_position = p.global_position + right * 2.1 + direction * 3.3 + Vector3.UP * 1.15
	camera.look_at(p.global_position + Vector3.UP * .22 + direction * .12)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://art/screenshots/weapons_v4/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(get_viewport().get_texture().get_image().save_png(folder + label + ".png") == OK, "Equipment renderer capture failed")
