extends Node3D

const Controller := preload("res://src/companion/companion_controller.gd")
signal tick_finished
var failures := 0
var checks := 0
var deadline := Time.get_ticks_msec() + 90000


class ThreatBoss extends Colossus:
	var zones: Array = []
	func get_danger_zones() -> Array:
		return zones
	func _ready() -> void:
		set_physics_process(false)
	func get_focus_point() -> Vector3:
		return global_position + Vector3.UP * 4.0


func _ready() -> void:
	process_physics_priority = 2000
	Sfx.enabled = false
	Fx.enabled = false
	InputSetup.ensure_defaults()
	call_deferred("run")


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Companion controller watchdog: timeout or runtime error")
		get_tree().quit(1)


func ticks(count: int) -> void:
	for i in count:
		await tick_finished


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size
	shape.shape = mesh
	body.add_child(shape)
	parent.add_child(body)
	return body


func fixture(floor_size := Vector3(120.0, 1.0, 120.0)) -> Dictionary:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.set_physics_process(false)
	game.region = Node3D.new()
	game.region.name = "Region"
	game.add_child(game.region)
	game.region_kind = GameWorld.VALLEY
	box(game.region, Vector3(0.0, -0.5, 0.0), floor_size)
	var host := PlayerCharacter.new()
	host.name = "Player1"
	host.position = Vector3(0.0, 0.95, -15.0)
	game.region.add_child(host)
	var companion := PlayerCharacter.new()
	companion.name = "Player2"
	companion.player_index = 2
	companion.position = Vector3(0.0, 0.95, 0.0)
	game.region.add_child(companion)
	game.refs = {"player": host}
	var controller := Controller.new()
	controller.name = "CompanionController"
	game.region.add_child(controller)
	controller.setup(game, companion, 901)
	return {"game": game, "host": host, "actor": companion, "controller": controller}


func run() -> void:
	await test_follow_and_input_ownership()
	await test_cliff_and_wall()
	await test_danger_and_bow()
	await test_world_checkpoint()
	print("COMPANION_CONTROLLER failures=%d checks=%d; real actor follow, input ownership/fade/death, physical cliff/wall, bounded threat evade, real bow, full GameWorld binary continuation" % [failures, checks])
	get_tree().quit(1 if failures else 0)


func test_follow_and_input_ownership() -> void:
	var f := fixture()
	var game: GameWorld = f.game
	var actor: PlayerCharacter = f.actor
	var host: PlayerCharacter = f.host
	var controller: Controller = f.controller
	await ticks(4)
	var before := actor.global_position.distance_to(host.global_position)
	await ticks(180)
	check(actor.global_position.distance_to(host.global_position) < before - 6.0, "Real companion did not move toward the actual host")
	check(controller.navigation_updates <= 32 and controller.navigation_rays < 250, "Companion navigation exceeded its bounded 10Hz query budget")
	check(actor.riding.horse == null and not actor.actions._call_pressed and not actor.actions._interact_pressed and not actor.actions.grab_held, "Companion stole Agro or started a climbing autopilot")
	actor.set_physics_process(false)
	controller.external_drive = true
	actor.actions.move = Vector2(0.7, -0.4)
	actor.actions.attack_held = true
	actor.actions.press_interact()
	var recorded := actor.actions.snapshot()
	var decision_count := controller.policy.decisions
	await ticks(16)
	check(actor.actions.snapshot() == recorded and controller.policy.decisions == decision_count, "External drive cleared or changed a replay frame/RNG")
	controller.external_drive = false
	game.phase = GameWorld.Phase.FADE_OUT
	await ticks(1)
	check(actor.actions.move == Vector2.ZERO and not actor.actions.attack_held and not actor.actions._interact_pressed, "Companion produced input during a fade")
	game.phase = GameWorld.Phase.PLAYING
	game.region_kind = &""
	actor.actions.move = Vector2.ONE
	await ticks(1)
	check(actor.actions.move == Vector2.ZERO, "Companion produced input on the title screen")
	game.region_kind = GameWorld.VALLEY
	host.dead = true
	await ticks(1)
	check(actor.actions.move == Vector2.ZERO and controller.observation().leader_downed, "Companion ignored host death")
	host.dead = false
	actor.dead = true
	await ticks(1)
	check(actor.actions.move == Vector2.ZERO and controller.observation().player_downed, "Downed companion kept moving")
	actor.dead = false
	controller.mode = &"local_model"
	controller.accept_decision(&"hold")
	controller.navigation_left = 0.0
	await ticks(8)
	check(controller.intent == &"hold" and actor.actions.move == Vector2.ZERO, "Accepted safe model hold did not reach actions")
	var accepted := controller.accepted_intent
	controller.accept_decision(&"run_arbitrary_code")
	check(controller.accepted_intent == accepted and controller.allowed_intents().size() == 5, "Controller accepted an unknown model command")
	controller.accepted_left = 0.0
	controller.decision_left = 0.0
	controller.navigation_left = 0.0
	await ticks(8)
	check(controller.policy.decisions > decision_count and controller.intent in controller.allowed_intents(), "Local model outage did not resume fallback policy")
	game.free()
	await ticks(2)


func test_world_checkpoint() -> void:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	game.settings.companion_mode = &"programmed"
	game.layout_version = 2
	add_child(game)
	game.start(true)
	await ticks(45)
	var controller: Controller = game.refs.get("companion_controller")
	check(is_instance_valid(controller) and is_instance_valid(game.companion()), "Full GameWorld did not integrate a companion")
	if not is_instance_valid(controller):
		game.free()
		return
	controller.decision_left = 0.25
	var checkpoint: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	var rng_before: int = controller.policy.rng.state
	await ticks(120)
	var position := game.companion().global_position
	var rng_after: int = controller.policy.rng.state
	var decision_count := controller.policy.decisions
	var next_decision := controller.decision_left
	var navigation_updates := controller.navigation_updates
	check(WorldSnapshot.restore(game, checkpoint), "Full binary checkpoint could not restore companion actors/controller")
	controller = game.refs.get("companion_controller")
	check(controller.policy.rng.state == rng_before and controller.actor == game.companion(), "Checkpoint lost policy RNG or actor reference")
	await ticks(120)
	check(game.companion().global_position.distance_to(position) < 0.001, "Restored companion movement diverged under identical world input")
	check(controller.policy.rng.state == rng_after and controller.policy.decisions == decision_count and absf(controller.decision_left - next_decision) < 0.000001 and controller.navigation_updates == navigation_updates, "Binary continuation changed companion decisions/timers/query cadence")
	game.free()
	await ticks(2)


func test_cliff_and_wall() -> void:
	# A deep gap sits between the actor and host. No invisible teleport/jump solves it.
	var f := fixture(Vector3(12.0, 1.0, 12.0))
	var game: GameWorld = f.game
	var actor: PlayerCharacter = f.actor
	var controller: Controller = f.controller
	f.host.set_physics_process(false)
	f.host.position = Vector3(0.0, 0.95, -16.0)
	actor.position = Vector3(0.0, 0.95, -3.5)
	var saw_cliff := false
	for i in 180:
		await ticks(1)
		saw_cliff = saw_cliff or controller.near_cliff
	check(actor.global_position.y > 0.7 and actor.global_position.z > -5.6, "Companion ran off a real cliff")
	check(saw_cliff, "Navigation did not expose the cliff observation")
	game.free()
	await ticks(2)
	f = fixture()
	game = f.game
	actor = f.actor
	controller = f.controller
	box(game.region, Vector3(0.0, 1.5, -6.0), Vector3(5.0, 3.0, 1.0))
	await ticks(260)
	check(actor.global_position.z < -7.0 and actor.global_position.y > 0.7, "Companion could not detour around a physical wall: pos=%s nav=%s blocked=%s" % [actor.global_position, controller._nav_direction, controller.navigation_blocked])
	game.free()
	await ticks(2)


func test_danger_and_bow() -> void:
	var f := fixture()
	var game: GameWorld = f.game
	var actor: PlayerCharacter = f.actor
	var controller: Controller = f.controller
	var boss := ThreatBoss.new()
	boss.name = "ThreatBoss"
	boss.position = Vector3(0.0, 0.0, 5.0)
	game.region.add_child(boss)
	game.refs.colossus = boss
	await ticks(4)
	var center := actor.global_position
	boss.zones = [[center, 3.0]]
	controller.mode = &"local_model"
	controller.accept_decision(&"hold")
	controller.navigation_left = 0.0
	await ticks(42)
	check(actor.global_position.distance_to(center) > 2.0 and controller.intent == &"evade", "Threat did not override a model hold with bounded evasion")
	boss.zones.clear()
	boss.position = Vector3(0.0, 0.0, -30.0)
	f.host.position = Vector3(0.0, 0.95, -12.0)
	actor.position = Vector3(0.0, 0.95, -10.0)
	actor.velocity = Vector3.ZERO
	controller.accept_decision(&"support")
	controller.shot_left = 0.0
	controller.navigation_left = 0.0
	var initial_shots := actor.bow.shots
	await ticks(90)
	check(actor.bow.shots == initial_shots + 1, "Companion support did not release one real bow arrow")
	check(actor.bow.last_shot.get("dir", Vector3.ZERO).dot(Vector3.FORWARD) > 0.8, "Support release turned away from the actual boss")
	await ticks(180)
	check(actor.bow.shots == initial_shots + 1, "Bow support fired too often")
	check(not actor.actions.grab_held and not actor.actions._interact_pressed, "Support attempted a compulsory boss mechanic")
	f.host.set_physics_process(false)
	f.host.position.y = 35.0
	f.host.state = PlayerCharacter.State.CLIMB
	controller.navigation_left = 0.0
	await ticks(7)
	check(controller.support_available and controller.observation().leader_climbing, "Host climbing height prevented ground bow support")
	game.free()
	await ticks(2)
