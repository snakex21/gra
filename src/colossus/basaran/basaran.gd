class_name Basaran
extends Quadratus
## Playable geyser puzzle prototype on the stable quadruped climbing rig.
## Ordinary walking never opens its feet. A vent first warns, then raises the shell;
## an arrow to the lifted sole removes support and tips the body into a climb window.
enum VentState { SEEKING, LIFTING, EXPOSED, LOWERING }
var vent_state := VentState.SEEKING
var vent_time := 0.0
var geyser: BasaranGeyser
var _lift := 0.0
var geyser_lifts := 0

func _init() -> void:
	super()
	walk_speed = 2.8
	turn_rate = 0.35
	notice_radius = 85.0
	kneel_time = 48.0
	kneel_time_crown = 48.0
	weak_point_health = 120.0
	brain_seed = 61
	arena_radius = 74.0

func _parts() -> Array:
	var out := Quadratus.PARTS.duplicate(true)
	# A broad stone carapace around the retained fur strip and climbable rear haunch.
	out.append([&"body", Kind.ARMOR, Vector3(1.4, 1.8, 9.5), Vector3(-2.25, 2.45, -0.3)])
	out.append([&"body", Kind.ARMOR, Vector3(1.4, 1.8, 9.5), Vector3(2.25, 2.45, -0.3)])
	for z: float in [-4.0, -1.0, 2.0]:
		out.append([&"body", Kind.STONE, Vector3(1.0, 2.0, 1.0), Vector3(-2.3, 3.7, z)])
		out.append([&"body", Kind.STONE, Vector3(1.0, 2.0, 1.0), Vector3(2.3, 3.7, z)])
	return out

func _weak_point_specs() -> Array:
	return [[&"body", Quadratus.RUMP_LOCAL, weak_point_health, true]]

func _boss_label() -> String:
	return "BASARAN"

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if encounter != Encounter.COMBAT or buckle != Buckle.NONE or attack != null and not attack.is_done() or not _time_on_body.is_empty():
		return super(obs)
	if vent_state != VentState.SEEKING:
		return ColossusIntent.make(OBSERVE)
	var target := _focus_player(obs)
	# It attacks intruders near the front feet; approaching from farther away remains
	# predictable enough to lure the heavy shell across a vent.
	if target != null:
		for info in obs.players:
			if info.player == target:
				for kind in [STOMP, HEAD_ATTACK]:
					if kind in info.opportunities and kind not in obs.blocked_intents:
						var threat := ColossusIntent.make(kind)
						threat.target_player = target
						return threat
	var chosen := ColossusIntent.make(APPROACH)
	chosen.target_player = target
	return chosen

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	_update_vent(delta)
	super(it, delta)

func _update_vent(delta: float) -> void:
	vent_time += delta
	if is_defeated() or buckle != Buckle.NONE:
		vent_state = VentState.SEEKING
		_lift = move_toward(_lift, 0.0, delta * 2.0)
		return
	match vent_state:
		VentState.SEEKING:
			_lift = move_toward(_lift, 0.0, delta)
			if encounter == Encounter.COMBAT and _buckle_cooldown_left <= 0.0:
				for node in get_tree().get_nodes_in_group(&"basaran_geysers"):
					var vent := node as BasaranGeyser
					if vent and vent.phase == BasaranGeyser.Phase.ERUPTING and vent.contains(global_position):
						geyser = vent
						vent_state = VentState.LIFTING
						vent_time = 0.0
						geyser_lifts += 1
						_end_attack(false)
						break
		VentState.LIFTING:
			_lift = move_toward(_lift, 1.0, delta / 1.5)
			if vent_time >= 1.5:
				vent_state = VentState.EXPOSED
				vent_time = 0.0
		VentState.EXPOSED:
			if vent_time >= 18.0:
				vent_state = VentState.LOWERING
				vent_time = 0.0
		VentState.LOWERING:
			_lift = move_toward(_lift, 0.0, delta)
			if _lift <= 0.0:
				vent_state = VentState.SEEKING

func _adjust_movement(it: ColossusIntent, delta: float) -> void:
	super(it, delta)
	if vent_state != VentState.SEEKING:
		desired_speed = 0.0
		desired_turn = 0.0
		extra_pelvis_drop -= 1.4 * _lift
		extra_pitch = -0.12 * _lift
	if buckle == Buckle.REACT or buckle == Buckle.KNEEL:
		# A sustained visible tilt; IK still keeps the other three feet planted.
		extra_roll += (-0.16 if buckle_leg == 2 else 0.16)

func _pose_legs(inv: Transform3D) -> void:
	super(inv)
	# Turn the raised rear soles towards the archer; the glowing mark is on the sole.
	if _lift > 0.01 and buckle == Buckle.NONE:
		for i in [2, 3]:
			var idx: int = _bone[leg_bones[i][2]]
			var q := skeleton.get_bone_pose_rotation(idx)
			skeleton.set_bone_pose_rotation(idx, q * Quaternion(Vector3.RIGHT, -1.15 * _lift))

func sole_exposed(_i: int) -> bool:
	return vent_state == VentState.EXPOSED and _lift > 0.95

func _update_crown() -> void:
	if rump.state != WeakPoint.State.DESTROYED:
		rump.set_protected(buckle not in [Buckle.REACT, Buckle.KNEEL])

func _rules_block() -> Array[StringName]:
	var blocked := super()
	if vent_state != VentState.SEEKING:
		blocked.append_array([STOMP, HEAD_ATTACK, SHAKE_BODY, LURCH])
	return blocked

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	vent_state = VentState.SEEKING
	vent_time = 0.0
	_lift = 0.0
	geyser_lifts = 0
	geyser = null
	super(xf, use_xf)
	for node in get_tree().get_nodes_in_group(&"basaran_geysers"):
		(node as BasaranGeyser).reset()

func debug_text() -> String:
	return "Gejzer %s %.1fs | zwab na strumień, traf podniesioną stopę, wejdź na zad\n%s" % [VentState.keys()[vent_state], vent_time, super()]
