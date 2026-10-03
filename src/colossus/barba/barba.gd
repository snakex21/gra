class_name Barba
extends Valus
## Redesign prototype: hide below the arch, lure a deliberate inspection, climb the
## lowered beard. Arm/leg stone prevents bypassing the arena puzzle.
enum SearchPhase { HUNT, APPROACH_COVER, TELEGRAPH, EXPOSED }
const INSPECT := &"barba_inspect"
const COVER_LOCAL := Vector3(0, 0, -27)
const INSPECTION_LOCAL := Vector3(0, 0, -15)
@export var inspection_telegraph := 2.0
@export var exposure_duration := 35.0
var search_phase := SearchPhase.HUNT
var search_time := 0.0
var kneel_weight := 0.0
var inspections := 0
var beard_grabs := 0
var _beard_riders := {}

func _init() -> void:
	brain_seed = 61
	arena_radius = 30.0
	walk_speed = 2.2
	notice_radius = 45.0

func _parts() -> Array:
	var parts := []
	for p in VALUS_PARTS:
		var part: Array = p.duplicate()
		if part[1] == Kind.FUR and part[0] != &"head":
			part[1] = Kind.STONE
		parts.append(part)
	# Long front beard overlaps the crown's front fur; lower end hangs near ground
	# during the inspection. The wide mantle catches a solo climber's hands.
	parts.append([&"head", Kind.FUR, Vector3(2.3, 9.8, 0.8), Vector3(0, -3.4, -1.2)])
	parts.append([&"head", Kind.FUR, Vector3(2.3, 3.0, 0.8), Vector3(0, 1.0, -1.2)])
	return parts

func cover_point() -> Vector3:
	return _start_xf.origin + _start_xf.basis * COVER_LOCAL

func inspection_point() -> Vector3:
	return _start_xf.origin + _start_xf.basis * INSPECTION_LOCAL

func player_in_cover(p: Node3D) -> bool:
	var d := _start_xf.affine_inverse() * p.global_position - COVER_LOCAL
	return absf(d.x) < 4.0 and absf(d.z) < 3.8 and d.y < 3.5

func _extra_rules(out: Array[StringName]) -> void:
	out.append(PROTECT)
	if search_phase != SearchPhase.HUNT:
		out.append(STOMP)
		out.append(ARM_SWEEP)
		out.append(ColossusIntent.SHAKE_PLAYER)

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if debug_override != &"" or encounter != Encounter.COMBAT:
		return super(obs)
	if search_phase == SearchPhase.HUNT:
		for info in obs.players:
			if not _dead(info.player) and player_in_cover(info.player):
				if attack != null and not attack.is_done():
					return super(obs)
				search_phase = SearchPhase.APPROACH_COVER
				search_time = 0.0
				break
	if search_phase == SearchPhase.APPROACH_COVER:
		var it := ColossusIntent.make(ColossusIntent.REPOSITION)
		it.target_position = inspection_point()
		if _flat(global_position - it.target_position).length() < 1.2:
			search_phase = SearchPhase.TELEGRAPH
			search_time = 0.0
		return it
	if search_phase in [SearchPhase.TELEGRAPH, SearchPhase.EXPOSED]:
		return ColossusIntent.make(INSPECT)
	return super(obs)

func _update_extra(_it: ColossusIntent, delta: float) -> void:
	search_time += delta
	if encounter == Encounter.DEFEATED:
		return
	if search_phase == SearchPhase.TELEGRAPH and search_time >= inspection_telegraph:
		search_phase = SearchPhase.EXPOSED
		search_time = 0.0
		inspections += 1
	var ridden := false
	for p in get_tree().get_nodes_in_group(&"players"):
		if owns_body(p.get_support_body()):
			ridden = true
			if p.is_climbing():
				if not _beard_riders.has(p.get_instance_id()):
					beard_grabs += 1
					_beard_riders[p.get_instance_id()] = true
			else:
				_beard_riders.erase(p.get_instance_id())
		else:
			_beard_riders.erase(p.get_instance_id())
	if search_phase == SearchPhase.EXPOSED and search_time >= exposure_duration and not ridden:
		search_phase = SearchPhase.HUNT
		search_time = 0.0
	var target := 1.0 if search_phase == SearchPhase.EXPOSED else 0.0
	kneel_weight = move_toward(kneel_weight, target, delta / 2.0)
	weak_point.set_protected(search_phase != SearchPhase.EXPOSED)

func _holds_still(it: ColossusIntent) -> bool:
	return it.kind == INSPECT or super(it)

func _extra_drop() -> float:
	return 5.7 * kneel_weight + super()

func _pose_overrides(delta: float) -> void:
	super(delta)
	# A shallow bow leaves the beard vertical, keeps its route physically stable,
	# and gives the long lowering animation an obvious silhouette.
	for bone in [&"spine", &"chest", &"neck", &"head"]:
		_blend_rot(bone, Quaternion.IDENTITY, kneel_weight)
	_add_rot(&"head", Vector3(0, 0.06 * _stagger * sin(_stagger_phase), 0))

func _reset_extra() -> void:
	super()
	search_phase = SearchPhase.HUNT
	search_time = 0.0
	kneel_weight = 0.0
	inspections = 0
	beard_grabs = 0
	_beard_riders.clear()

func _debug_extra() -> String:
	return "Barba %s %.1f s | inspections %d" % [SearchPhase.keys()[search_phase], search_time, inspections]
