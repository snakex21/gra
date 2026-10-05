extends SceneTree
## Focused real-controller standing/transition check. No authored-bone overrides.
const DT := 1.0 / 60.0
var output := ""
var baseline_script := ""
var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func state(h: Horse) -> Dictionary:
	var hip := h.skeleton.get_bone_global_pose(h._bone[&"fl_up"]).origin
	var knee := h.skeleton.get_bone_global_pose(h._bone[&"fl_low"]).origin
	var ankle := h.skeleton.get_bone_global_pose(h._bone[&"fl_hoof"]).origin
	var bend := rad_to_deg((knee - hip).normalized().angle_to((ankle - knee).normalized()))
	return {"body_height": h._height, "saddle_y": h.saddle_transform().origin.y, "fore_bend_degrees": bend, "knee_forward_offset": absf(knee.z - hip.z), "gait": h.controller.gait, "speed": h.controller.speed}

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func setup(slope: float) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	ground.rotation.x = slope
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 0.2, 1000)
	collision.shape = box
	collision.position.y = -0.1
	ground.add_child(collision)
	world.add_child(ground)
	await ticks(2)
	var horse: Horse = Horse.new() if baseline_script == "" else load(baseline_script).new()
	world.add_child(horse)
	var driver := ScriptedHorseDriver.new()
	driver.hold_speed = 0.0
	world.add_child(driver)
	horse.set_rider(driver)
	await ticks(300)
	return {"world": world, "horse": horse, "driver": driver}

func transition(speed: float) -> void:
	var w := await setup(0.0)
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	var before := state(h)
	check(absf(h._height - (1.39 if baseline_script == "" else 1.27)) < 0.001, "Flat idle settles to expected height")
	if baseline_script == "":
		check(before.fore_bend_degrees < 16.0 and before.fore_bend_degrees > 12.0, "Relaxed foreleg flexion remains short of lockout")
	h.reset_foot_stats()
	var previous_height := h._height
	var previous_rate := 0.0
	var maximum_rate := 0.0
	var maximum_accel := 0.0
	var peak := {}
	var maximum_sole_error := 0.0
	var maximum_idle_rate := 0.0
	var maximum_idle_accel := 0.0
	var prior_idle_weight := h._gait_w[0]
	var maximum_start_rate := 0.0
	var maximum_start_accel := 0.0
	var moving := {}
	d.hold_speed = speed
	for tick in 1200:
		if tick == 600:
			moving = state(h)
			d.hold_speed = 0.0
		await physics_frame
		var rate := (h._height - previous_height) / DT
		maximum_rate = maxf(maximum_rate, absf(rate))
		if absf(rate - previous_rate) / DT > maximum_accel:
			peak = {"tick": tick, "gait": h.controller.gait, "speed": h.controller.speed, "idle_weight": h._gait_w[0], "height": h._height, "height_clamps": h.height_clamps}
		maximum_accel = maxf(maximum_accel, absf(rate - previous_rate) / DT)
		if h._gait_w[0] > 0.0 or prior_idle_weight > 0.0:
			maximum_idle_rate = maxf(maximum_idle_rate, absf(rate))
			maximum_idle_accel = maxf(maximum_idle_accel, absf(rate - previous_rate) / DT)
		if tick < 600:
			maximum_start_rate = maxf(maximum_start_rate, absf(rate))
			maximum_start_accel = maxf(maximum_start_accel, absf(rate - previous_rate) / DT)
		prior_idle_weight = h._gait_w[0]
		previous_height = h._height
		previous_rate = rate
		for i in 4:
			if h.gait_planner.legs[i].is_planted():
				maximum_sole_error = maxf(maximum_sole_error, h.sole_world(i).distance_to(h.gait_planner.legs[i].foot_pos))
	var row := {"peak_accel_state": peak, "requested_speed": speed, "before": before, "moving": moving, "stopped": state(h), "max_idle_affected_rate_mps": maximum_idle_rate, "max_idle_affected_accel_mps2": maximum_idle_accel, "max_start_rate_mps": maximum_start_rate, "max_start_accel_mps2": maximum_start_accel, "max_body_height_rate_mps": maximum_rate, "max_body_height_accel_mps2": maximum_accel, "max_planted_sole_error_m": maximum_sole_error, "feet": h.foot_stats.duplicate(), "height_clamps": h.height_clamps}
	rows.append(row)
	check(maximum_idle_rate < 1.0 and maximum_start_rate < 1.0, "Idle-affected and starting body height rates below 1 m/s")
	check(maximum_idle_accel < 40.0 and maximum_start_accel < 40.0, "Idle-affected and starting transitions have no large height acceleration spike")
	check(maximum_sole_error < 0.001, "Idle transitions preserve planted sole targets")
	check(h.foot_stats.slip_max < 0.05 and h.foot_stats.reach_max < 0.03, "Idle transitions preserve hoof slip/reach limits")
	check(h.controller.speed < 0.01 and h.controller.gait == HorseController.Gait.IDLE, "Stops back in idle")
	w.world.free()
	await ticks(2)

func slope_standing() -> void:
	var w := await setup(deg_to_rad(10.0))
	var h: Horse = w.horse
	var maximum_error := 0.0
	for i in 4:
		maximum_error = maxf(maximum_error, h.sole_world(i).distance_to(h.gait_planner.legs[i].foot_pos))
	rows.append({"slope_degrees": 10.0, "standing": state(h), "max_sole_error_m": maximum_error, "feet": h.foot_stats.duplicate()})
	check(maximum_error < 0.001, "Standing on real 10-degree collider keeps all four soles planted")
	w.world.free()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2:
		push_error("Expected report JSON path")
		quit(2)
		return
	output = args[0]
	if args.size() == 2: baseline_script = args[1]
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	for speed in [1.7, 4.2, 9.5]:
		await transition(speed)
	await slope_standing()
	var f := FileAccess.open(output, FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed": failures.is_empty(), "baseline_pose_override": baseline_script, "baseline_pose_sha256": FileAccess.get_sha256(baseline_script) if baseline_script != "" else "", "known_limit": "Whole-path stop peaks remain reported, but assertions cover the changed idle-weight interval and initial acceleration. Baseline moving-gait hard reach clamps can exceed these smoothness thresholds while idle weight is zero.", "failures": failures, "fixed_dt": DT, "source_sha256": FileAccess.get_sha256("res://src/horse/horse.gd"), "scope": "Actual HorseController via ScriptedHorseDriver, production physics and gait. Flat idle starts, walk/trot/gallop commands then stops, and idle on real 10-degree slope collider. Not GPU or visual evidence.", "results": rows}, "\t"))
	f.close()
	print("AGRO_STANDING_POSE_", "PASS" if failures.is_empty() else "FAIL", " ", output)
	quit(0 if failures.is_empty() else 1)
