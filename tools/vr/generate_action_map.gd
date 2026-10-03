extends SceneTree
## Generate/verify the small, explicit core OpenXR map; no runtime or headset needed.
## python tools/run_local.py godot --headless --xr-mode off --path . --script tools/vr/generate_action_map.gd
## Append -- --verify-only to load/test the checked-in map without rewriting it.
const InputReader = preload("res://src/vr/pc_vr_input.gd")
const TARGET := "res://src/vr/quest_action_map.tres"
const LEFT := "/user/hand/left"
const RIGHT := "/user/hand/right"
const TOUCH := "/interaction_profiles/oculus/touch_controller"
const SIMPLE := "/interaction_profiles/khr/simple_controller"
const SPECS := {
	"grip_pose": [OpenXRAction.OPENXR_ACTION_POSE, [LEFT, RIGHT], "Controller grip pose"],
	"aim_pose": [OpenXRAction.OPENXR_ACTION_POSE, [LEFT, RIGHT], "Controller aim pose"],
	"move": [OpenXRAction.OPENXR_ACTION_VECTOR2, [LEFT], "Move with left stick"],
	"turn": [OpenXRAction.OPENXR_ACTION_VECTOR2, [RIGHT], "Turn with right stick"],
	"confirm": [OpenXRAction.OPENXR_ACTION_BOOL, [RIGHT], "Confirm"],
	"back": [OpenXRAction.OPENXR_ACTION_BOOL, [RIGHT], "Back"],
	"recenter": [OpenXRAction.OPENXR_ACTION_BOOL, [LEFT], "Recenter"],
	"pause": [OpenXRAction.OPENXR_ACTION_BOOL, [LEFT], "Pause"],
}
const TOUCH_BINDINGS := [
	["grip_pose", LEFT + "/input/grip/pose"], ["grip_pose", RIGHT + "/input/grip/pose"],
	["aim_pose", LEFT + "/input/aim/pose"], ["aim_pose", RIGHT + "/input/aim/pose"],
	["move", LEFT + "/input/thumbstick"], ["turn", RIGHT + "/input/thumbstick"],
	["confirm", RIGHT + "/input/a/click"], ["back", RIGHT + "/input/b/click"],
	["recenter", LEFT + "/input/y/click"], ["pause", LEFT + "/input/x/click"],
	# This is a legal core left-hand path. X remains available if runtime owns menu.
	["pause", LEFT + "/input/menu/click"],
]
const SIMPLE_BINDINGS := [
	["grip_pose", LEFT + "/input/grip/pose"], ["grip_pose", RIGHT + "/input/grip/pose"],
	["aim_pose", LEFT + "/input/aim/pose"], ["aim_pose", RIGHT + "/input/aim/pose"],
	["confirm", RIGHT + "/input/select/click"], ["back", RIGHT + "/input/menu/click"],
	["recenter", LEFT + "/input/select/click"], ["pause", LEFT + "/input/menu/click"],
	# Simple controllers expose no stick; unsupported movement stays zero.
]
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void: push_error("XR action map watchdog"); quit(2))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _build() -> OpenXRActionMap:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "pc_vr"
	action_set.localized_name = "PC VR controls"
	action_set.priority = 0
	var actions := {}
	for name: String in SPECS:
		var action := OpenXRAction.new()
		action.resource_name = name
		action.action_type = SPECS[name][0]
		action.toplevel_paths = PackedStringArray(SPECS[name][1])
		action.localized_name = SPECS[name][2]
		action_set.add_action(action)
		actions[name] = action
	action_map.add_action_set(action_set)
	for path: String in [TOUCH, SIMPLE]:
		var profile := OpenXRInteractionProfile.new()
		profile.interaction_profile_path = path
		var bindings: Array = TOUCH_BINDINGS if path == TOUCH else SIMPLE_BINDINGS
		for spec: Array in bindings:
			var binding := OpenXRIPBinding.new()
			binding.action = actions[spec[0]]
			binding.binding_path = spec[1]
			profile.bindings.append(binding)
		action_map.add_interaction_profile(profile)
	return action_map

func _verify(action_map: OpenXRActionMap) -> void:
	check(action_map.get_action_set_count() == 1, "one core action set")
	check(action_map.get_interaction_profile_count() == 2, "Touch plus simple fallback only")
	var action_set := action_map.get_action_set(0)
	check(action_set.resource_name == "pc_vr", "registered set name")
	check(action_set.get_action_count() == 8, "eight contract actions")
	var actions := {}
	for action: OpenXRAction in action_set.actions:
		var name := action.resource_name
		check(SPECS.has(name) and not actions.has(name), "unique known action")
		if not SPECS.has(name):
			continue
		actions[name] = action
		check(action.action_type == SPECS[name][0], "action type " + name)
		check(action.toplevel_paths == PackedStringArray(SPECS[name][1]), "hand restriction " + name)
	for profile: OpenXRInteractionProfile in action_map.interaction_profiles:
		check(profile.interaction_profile_path in [TOUCH, SIMPLE], "core interaction profile")
		check(profile.binding_modifiers.is_empty(), "no extension binding modifiers")
		var expected: Array = TOUCH_BINDINGS if profile.interaction_profile_path == TOUCH else SIMPLE_BINDINGS
		check(profile.get_binding_count() == expected.size(), "complete bindings")
		var paths := {}
		for binding: OpenXRIPBinding in profile.bindings:
			var name := binding.action.resource_name
			var path := binding.binding_path
			check(actions.get(name) == binding.action, "serialized binding references registered action")
			check(not paths.has(path), "no competing actions on same physical input")
			paths[path] = true
			check([name, path] in expected, "exact core input binding")
			check(binding.binding_modifiers.is_empty() and not path.contains("ext"), "no extended input or modifier")
			var hand := LEFT if path.begins_with(LEFT + "/") else RIGHT
			check(binding.action.toplevel_paths.has(hand), "binding belongs to action hand")
	check(actions.get("move").toplevel_paths == PackedStringArray([LEFT]), "left movement only")
	check(actions.get("turn").toplevel_paths == PackedStringArray([RIGHT]), "right turning only")

func _verify_input() -> void:
	check(ClassDB.class_has_method("XRController3D", "get_is_active"), "engine active API")
	check(ClassDB.class_has_method("XRController3D", "get_has_tracking_data"), "engine current tracking API")
	var empty := InputReader.read(null, null)
	check(empty.size() == 8 and empty.move == Vector2.ZERO and empty.turn == 0.0, "missing controllers neutral")
	check(not empty.confirm and not empty.back and not empty.recenter and not empty.pause, "missing buttons neutral")
	var origin := XROrigin3D.new()
	root.add_child(origin)
	var left_tracker := XRControllerTracker.new()
	left_tracker.name = &"left_hand"
	left_tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	var right_tracker := XRControllerTracker.new()
	right_tracker.name = &"right_hand"
	right_tracker.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	for tracker: XRControllerTracker in [left_tracker, right_tracker]:
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
	var left := XRController3D.new()
	left.tracker = &"left_hand"
	left.pose = &"grip"
	origin.add_child(left)
	var right := XRController3D.new()
	right.tracker = &"right_hand"
	right.pose = &"grip"
	origin.add_child(right)
	# XRNode3D consumes pose-change signals after binding to a registered tracker.
	# Publish a fresh simulated sample after both nodes enter the tree.
	for tracker: XRControllerTracker in [left_tracker, right_tracker]:
		tracker.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	left_tracker.set_input(&"move", Vector2(0.25, 0.75))
	right_tracker.set_input(&"turn", Vector2(0.6, 0.2))
	left_tracker.set_input(&"recenter", true)
	left_tracker.set_input(&"pause", true)
	right_tracker.set_input(&"confirm", true)
	right_tracker.set_input(&"back", true)
	var sample := InputReader.read(left, right)
	check(sample.left_tracked and sample.right_tracked, "simulated engine trackers active/current")
	check(sample.move.is_equal_approx(Vector2(0.25, 0.75)) and is_equal_approx(sample.turn, 0.6), "handed axes and positive forward")
	check(sample.confirm and sample.back and sample.recenter and sample.pause, "button levels read")
	check(InputReader.read(left, right) == sample, "reader does not latch button edges")
	left_tracker.invalidate_pose(&"grip")
	sample = InputReader.read(left, right)
	check(not sample.left_tracked and sample.right_tracked, "pose invalidation is detected")
	check(sample.move == Vector2.ZERO and not sample.recenter and not sample.pause, "stale left inputs zeroed")
	check(sample.confirm and sample.back and sample.turn > 0.5, "other tracked hand retained")
	left_tracker.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right_tracker.invalidate_pose(&"grip")
	sample = InputReader.read(left, right)
	check(not sample.right_tracked and sample.left_tracked, "right tracking loss")
	check(sample.turn == 0.0 and not sample.confirm and not sample.back, "stale right inputs zeroed")
	left_tracker.set_input(&"move", Vector2(NAN, INF))
	check(InputReader.read(left, right).move == Vector2.ZERO, "non finite axis neutral")
	left_tracker.set_input(&"move", Vector2(5.0, -5.0))
	check(is_equal_approx(InputReader.read(left, right).move.length(), 1.0), "oversized axis bounded")
	XRServer.remove_tracker(left_tracker)
	XRServer.remove_tracker(right_tracker)
	origin.free()

func _run() -> void:
	if not "--verify-only" in OS.get_cmdline_user_args():
		var action_map := _build()
		check(ResourceSaver.save(action_map, TARGET) == OK, "saved explicit action map")
	var loaded := ResourceLoader.load(TARGET, "OpenXRActionMap", ResourceLoader.CACHE_MODE_IGNORE) as OpenXRActionMap
	check(loaded != null, "real engine loads action map")
	if loaded != null:
		_verify(loaded)
	_verify_input()
	print("PC VR ACTION MAP: %d checks, %d failures (headless, XR off; no hardware claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)
