extends Node3D
## The real PCVR preview in simulation plus fail-closed startup with XR disabled.
const PreviewScript := preload("res://src/vr/pc_vr_scene.gd")
const DT := 1.0 / 60.0
var failures := 0
var cases: Array[String] = []
var deadline := Time.get_ticks_msec() + 90000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("PCVR scene watchdog expired after a stopped coroutine/runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count: await get_tree().physics_frame

func campaign_files() -> Dictionary:
	var result := {}
	var paths: Array[String] = [Settings.DEFAULT_PATH, "res://data/replays/last.replay"]
	for i in GameState.SLOTS:
		var slot := GameState.slot_path(i + 1)
		paths.append(slot)
		paths.append(slot + ".world")
	for path in paths:
		var resolved := PortablePaths.resolve(path)
		result[path] = FileAccess.get_file_as_bytes(resolved) if FileAccess.file_exists(resolved) else null
	return result

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://tests/output/" + name + ".png") == OK, "Could not save portable native preview capture")

func has_recording(node: Node) -> bool:
	if node is ActionReplay or node is ReplayViewer: return true
	for child in node.get_children():
		if has_recording(child): return true
	return false

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var files_before := campaign_files()
	var old_physics := Engine.physics_ticks_per_second
	var old_xr := get_viewport().use_xr
	check(not old_xr, "No-HMD scene fixture must run with --xr-mode off")
	var unavailable := PreviewScript.new()
	unavailable.simulated = false
	unavailable.with_art = false
	add_child(unavailable)
	await ticks(3)
	check(unavailable.startup_failed and unavailable.world == null and unavailable.rig == null and not get_viewport().use_xr, "Unavailable OpenXR startup did not fail closed before creating gameplay")
	check(Engine.physics_ticks_per_second == old_physics and campaign_files() == files_before, "Failed VR startup changed engine rate or campaign files")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	unavailable.free()
	await ticks(2)
	cases.append("XR-disabled startup fails closed without gameplay/save mutations")
	var preview := PreviewScript.new()
	preview.simulated = true
	preview.with_art = DisplayServer.get_name() != "headless"
	add_child(preview)
	# Test controls are explicit; no physical keyboard can steer this fixture.
	preview.set_physics_process(false)
	await ticks(3)
	var world := preview.world
	var rig := preview.rig
	check(not preview.startup_failed and world != null and rig != null and not rig.auto_step and not rig.ready_for_motion, "Explicit simulation did not build a manual, confirmation-gated preview")
	check(world.layout_version == 3 and world.settings.graphics_profile == "low" and world.save_path == "" and not world.with_input and world.companion() == null and world.companion_mode == &"off" and not has_recording(preview), "VR preview enabled campaign saves, desktop input, replay or companion gameplay")
	check(not world.is_physics_processing() and world.region_kind == &"valus" and world.colossus() is HumanoidBoss and not world.colossus().is_physics_processing() and not world.player().is_physics_processing(), "Preview did not freeze the actual Valus and flat player simulation")
	for item in world._pending:
		check(item[0] == &"valus", "VR preview retained another colossus arena build")
	var boss := world.colossus() as HumanoidBoss
	var boss_at := boss.global_transform
	var health := boss.weak_point.health
	var progress := world.state.to_dict()
	for i in 24:
		await get_tree().physics_frame
		world._build_step()
	check(not rig.ready_for_motion, "Simulated preview became ready without fresh confirmation")
	await capture("pc_vr_sim_ready")
	for i in 2:
		await get_tree().physics_frame
		rig.step(DT, {"left_tracked": true, "right_tracked": true}, true)
	await get_tree().physics_frame
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	for i in 18:
		await get_tree().physics_frame
		rig.step(DT, {"left_tracked": true, "right_tracked": true}, true)
		world._build_step()
	check(rig.ready_for_motion and rig.head.position.y > 1.0 and rig.head.current and world.refs.camera == rig.head, "Simulated preview could not start with a real XR camera observer")
	check(boss.global_transform.is_equal_approx(boss_at) and boss.weak_point.health == health and world.state.to_dict() == progress and not world.decision_client.enabled and campaign_files() == files_before, "PCVR preview advanced combat/campaign/local model or changed portable save files")
	await capture("pc_vr_sim_started")
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	preview._session_interrupted()
	await get_tree().physics_frame
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	check(not rig.ready_for_motion, "Session interruption resumed from stale held confirmation")
	preview._runtime_recentered()
	check(not rig.ready_for_motion and not get_viewport().use_xr, "Runtime recenter enabled motion or fake HMD output in simulation")
	cases.append("isolated low-profile simulation, real frozen Valus, explicit ready and interruption guards")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	preview.free()
	await ticks(2)
	check(Engine.physics_ticks_per_second == old_physics and get_viewport().use_xr == old_xr and campaign_files() == files_before, "Preview teardown failed to restore engine state or changed campaign data")
	print("PC_VR_SCENE: %d failure(s); cases=%s; monitor simulation only, no HMD claim" % [failures, str(cases)])
	get_tree().quit(1 if failures else 0)
