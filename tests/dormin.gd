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
	if "--capture" in OS.get_cmdline_user_args():
		await capture_dormin()
		get_tree().quit(0 if failures == 0 else 1)
		return
	world = Node3D.new()
	world.position = Vector3(155, 3, -97)
	world.rotation.y = -.38
	add_child(world)
	var refs := DorminArena.build_encounter(world)
	var c: Dormin = refs.dormin
	var p: PlayerCharacter = refs.player
	p.beam.lantern = "--lamp" in OS.get_cmdline_user_args()
	await ticks(2)
	check(c.seals.size() == 3 and not c._climb_open and c.weak_point.state == WeakPoint.State.PROTECTED, "Dormin body is exposed before the shadow locks")
	var bot := DorminBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	bot.verbose = "--verbose" in OS.get_cmdline_user_args()
	for i in 60 * (120 if "--short" in OS.get_cmdline_user_args() else 420):
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated(), "Dormin actions failed: locks %d window %s bot %s p %s grip %s stats %s" % [c.seals_broken, c._climb_open, bot.phase, p.global_position, bot._grip_bone(), bot.stats])
	if not c.is_defeated():
		print("SHADOW_DIAG at=", c.seals[2].global_position, " light=", c.seals[2].light_time, " exposed=", c.seals[2].exposed_left, " beam=", p.beam.raise, "/", p.beam.direction, " sword=", p.sword.state_name(), " actions=", p.actions.move, "/", p.actions.attack_held)
	check(c.seals_broken == 3 and c.windows > 0 and bot.locks_completed, "Dormin bypassed the three different locks")
	check(c.back_sigil.state == WeakPoint.State.DESTROYED and c.weak_point.state == WeakPoint.State.DESTROYED and c.stats.weak_point_hits >= 5, "Dormin victory skipped the back/crown sigils")
	check(not p.dead, "Wander dies at the end of the alternative finale")
	check(not c.stats.attacks.is_empty(), "Dormin never actively challenges the approaching player")
	refs.encounter.reset_encounter()
	bot.set_physics_process(false)
	p.actions.clear()
	await ticks(2)
	check(c.seals_broken == 0 and not c.seals.any(func(seal: DorminSeal) -> bool: return seal.broken) and c.back_sigil.health == 80 and c.weak_point.health == 100 and not c._climb_open, "Dormin reset did not restore locks and both sigils")
	check(not bot.locks_completed and not bot.back_completed, "Dormin driver kept completed stages across reset")
	bot.set_physics_process(true)
	for i in 60 * (120 if "--short" in OS.get_cmdline_user_args() else 420):
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated() and not p.dead and c.seals_broken == 3 and c.stats.weak_point_hits >= 5, "Dormin cannot be won again after reset: %s" % c.debug_text())
	print("Dormin: ", failures, " failure(s); three locks, body climb, two sigils, live Wander, transformed reset and repeated victory")
	get_tree().quit(0 if failures == 0 else 1)

func capture_dormin() -> void:
	world = load("res://scenes/dormin_arena.tscn").instantiate()
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
	var c: Dormin = refs.dormin
	var p: PlayerCharacter = refs.player
	c.debug_override = &"frozen"
	p.global_position = Vector3(5, .95, 32)
	p.actions.beam_held = true
	p.actions.view_basis = Basis.looking_at(c.seals[0].global_position - SwordBeam.tip(p))
	refs.camera.set_process(false)
	refs.camera.global_position = Vector3(24, 9, 34)
	refs.camera.look_at(Vector3(0, 8, 0))
	await ticks(40)
	await RenderingServer.frame_post_draw
	var path := PortablePaths.prepare("res://data/captures/dormin_courtyard.png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Dormin capture not saved")
	print("CAPTURE ", path)
