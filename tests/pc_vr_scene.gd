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

func physical_floor_y(actor: CharacterBody3D) -> float:
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .3, actor.global_position - Vector3.UP * 1.5, Layers.WORLD)
	query.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return NAN if hit.is_empty() else (hit.position as Vector3).y

func horizontal_forward(camera: Camera3D) -> Vector3:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	return forward.normalized()

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var files_before := campaign_files()
	var old_physics := Engine.physics_ticks_per_second
	var old_xr := get_viewport().use_xr
	check(not old_xr, "No-HMD scene fixture must run with --xr-mode off")
	check(PreviewScript.floor_reference_supported(XRInterface.XR_PLAY_AREA_STAGE) and PreviewScript.floor_reference_supported(XRInterface.XR_PLAY_AREA_ROOMSCALE), "Floor reference helper rejected Stage/local-floor reference spaces")
	for mode in [XRInterface.XR_PLAY_AREA_UNKNOWN, XRInterface.XR_PLAY_AREA_3DOF, XRInterface.XR_PLAY_AREA_SITTING, XRInterface.XR_PLAY_AREA_CUSTOM, -1, 999]:
		check(not PreviewScript.floor_reference_supported(mode), "Non-floor LOCAL/unknown/custom reference was treated as floor-relative")
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
	preview.set_process_unhandled_input(false)
	await ticks(3)
	var world := preview.world
	var rig := preview.rig
	check(not preview.startup_failed and world != null and rig != null and not rig.auto_step and not rig.ready_for_motion, "Explicit simulation did not build a manual, confirmation-gated preview")
	check(world.layout_version == 3 and world.settings.graphics_profile == "low" and world.save_path == "" and not world.with_input and world.companion() == null and world.companion_mode == &"off" and not has_recording(preview), "VR preview enabled campaign saves, desktop input, replay or companion gameplay")
	check(not world.is_physics_processing() and world.region_kind == &"valus" and world.colossus() is HumanoidBoss and not world.colossus().is_physics_processing() and not world.player().is_physics_processing(), "Preview did not freeze the actual Valus and flat player simulation")
	var actor := world.player()
	var arena_xf: Transform3D = world.arenas[&"valus"].xf
	var spawn_local := arena_xf.affine_inverse() * actor.global_position
	check(spawn_local.distance_to(Vector3(-1.3, .95, -6)) < .001, "VR scene did not use its close left-calf spawn at a real capsule center")
	check(is_equal_approx(actor._shape.height, 1.8) and is_equal_approx(actor._shape.radius, .35), "Real PCVR player capsule differs from its 1.8 m centered body contract")
	check(is_equal_approx(rig.eye_height, 1.70) and is_equal_approx(rig.world_scale, 1.0), "Scene default is not a 1.70 m eye target at physical world scale")
	var desired_forward := (arena_xf.basis * Vector3.BACK).normalized()
	check(rig.recenter_forward.normalized().dot(desired_forward) > .999, "Close spawn calibration does not face the back of Valus from its left calf")
	# Different measured standing height and room yaw must still calibrate the
	# virtual body correctly; the simulation's 1.65 m default alone cannot prove it.
	rig.head.transform = Transform3D(Basis.from_euler(Vector3(-.1, .62, .02)), Vector3(.18, 1.92, -.12))
	# Both tracked hands are raised in front of the physical user's room yaw,
	# as when reaching for fur. Keep them in view for native visual inspection.
	var room_yaw := Basis(Vector3.UP, .62)
	rig.left.transform = Transform3D(room_yaw * Basis.from_euler(Vector3(-.12, .1, .03)), rig.head.position + room_yaw * Vector3(-.29, -.30, -.55))
	rig.right.transform = Transform3D(room_yaw * Basis.from_euler(Vector3(-.08, -.12, -.02)), rig.head.position + room_yaw * Vector3(.30, -.32, -.55))
	var raw_head := rig.head.transform
	var raw_left := rig.left.transform
	var raw_right := rig.right.transform
	var left_relative := rig.head.global_transform.affine_inverse() * rig.left.global_transform
	var right_relative := rig.head.global_transform.affine_inverse() * rig.right.global_transform
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
	for i in 2:
		await get_tree().physics_frame
		rig.step(DT, {"left_tracked": true, "right_tracked": true}, true)
	await capture("pc_vr_sim_ready")
	await get_tree().physics_frame
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	for i in 18:
		await get_tree().physics_frame
		rig.step(DT, {"left_tracked": true, "right_tracked": true}, true)
		world._build_step()
	check(rig.ready_for_motion and rig.head.current and world.refs.camera == rig.head, "Simulated preview could not start with a real XR camera observer")
	var floor_y := physical_floor_y(actor)
	check(is_finite(floor_y) and absf(actor.global_position.y - .9 - floor_y) < .015 and absf(rig.head.global_position.y - floor_y - 1.70) < .015, "Actual Valus scene did not place capsule feet on collision floor and eyes 1.70 m above it")
	check(is_equal_approx(rig.height_offset, rig.eye_height - 1.92) and rig.head.transform == raw_head and rig.left.transform == raw_left and rig.right.transform == raw_right, "Scene calibration rewrote raw tracked poses or used an unexplained body-center offset")
	check(horizontal_forward(rig.head).dot(desired_forward) > .999 and Vector2(rig.head.global_position.x - actor.global_position.x, rig.head.global_position.z - actor.global_position.z).length() < .001, "Scene confirmation did not deliberately calibrate head yaw/XZ at the capsule")
	var actual_left_relative := rig.head.global_transform.affine_inverse() * rig.left.global_transform
	var actual_right_relative := rig.head.global_transform.affine_inverse() * rig.right.global_transform
	# Float32 global transforms at the real arena position lose tens of microns
	# on inverse multiplication. Raw poses above remain exact; allow 0.2 mm here.
	check(actual_left_relative.origin.distance_to(left_relative.origin) < .0002 and actual_right_relative.origin.distance_to(right_relative.origin) < .0002 and actual_left_relative.basis.is_equal_approx(left_relative.basis) and actual_right_relative.basis.is_equal_approx(right_relative.basis), "Scene height/yaw calibration changed tracked hand collocation")
	check(boss.global_transform.is_equal_approx(boss_at) and boss.weak_point.health == health and world.state.to_dict() == progress and not world.decision_client.enabled and campaign_files() == files_before, "PCVR preview advanced combat/campaign/local model or changed portable save files")
	await capture("pc_vr_sim_started")
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	preview._session_interrupted()
	await get_tree().physics_frame
	rig.step(DT, {"confirm": true, "left_tracked": true, "right_tracked": true}, true)
	check(not rig.ready_for_motion, "Session interruption resumed from stale held confirmation")
	preview._runtime_recentered()
	check(not rig.ready_for_motion and not get_viewport().use_xr, "Runtime recenter enabled motion or fake HMD output in simulation")
	cases.append("isolated low-profile simulation, actual centered capsule/floor, 1.70 m eye calibration, close-calf yaw/raw hands and interruption guards")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	preview.free()
	await ticks(2)
	check(Engine.physics_ticks_per_second == old_physics and get_viewport().use_xr == old_xr and campaign_files() == files_before, "Preview teardown failed to restore engine state or changed campaign data")
	print("PC_VR_SCENE: %d failure(s); cases=%s; monitor simulation only, no HMD claim" % [failures, str(cases)])
	get_tree().quit(1 if failures else 0)
