class_name WingedGuardian
extends Colossus
## Small common rigid climbing rig. Each guardian supplies its own encounter loop.
signal encounter_changed(state: Encounter)
enum Encounter { DORMANT, COMBAT, DEFEATED }
const BONES := [[&"body", &"", Vector3.ZERO], [&"wing_l", &"body", Vector3(-1.6, 0.4, -0.3)], [&"wing_r", &"body", Vector3(1.6, 0.4, -0.3)]]
var encounter := Encounter.DORMANT
var weak_point: WeakPoint
var weak_points: Array[WeakPoint] = []
var brain_seed := 109
var stats := {}
var debug_draw: Node3D
var _bone := {}
var _seg_by_bone := {}
var _spawn_xf := Transform3D.IDENTITY
var _grip_patch: ClimbPatch
var _patch_open := false
var _wing_angle := 0.12
var _roll := 0.0
var _body_material: StandardMaterial3D

func _init() -> void:
	body_height = 5.0
	arena_radius = 21.0
	think_interval = 0.15

func _ready() -> void:
	_spawn_xf = global_transform
	super()
	weak_point = WeakPoint.create(_seg_by_bone[&"body"], Vector3(0, 1.24, 0), 120.0)
	weak_point.radius = 0.78
	weak_point.struck.connect(_on_struck)
	weak_point.destroyed.connect(func() -> void: _set_encounter(Encounter.DEFEATED))
	weak_points.append(weak_point)
	debug_draw = Node3D.new()
	debug_draw.name = "DebugDraw"
	debug_draw.visible = false
	add_child(debug_draw)
	reset_encounter()

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for record in BONES:
		var index := skeleton.add_bone(record[0])
		_bone[record[0]] = index
		if record[1] != &"":
			skeleton.set_bone_parent(index, _bone[record[1]])
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, record[2]))
		var segment := BodySegment.new()
		segment.name = "Seg_" + record[0]
		segment.colossus = self
		segment.bone_name = record[0]
		segment.bone_idx = index
		add_child(segment)
		segments.append(segment)
		_seg_by_bone[record[0]] = segment
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.27, 0.24, 0.32)
	_body_material.roughness = 0.93
	var body: BodySegment = _seg_by_bone[&"body"]
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.38, 2.38, 4.98)
	var solid := CollisionShape3D.new()
	solid.shape = shape
	body.add_child(solid)
	_grip_patch = ClimbPatch.new()
	var fur := BoxShape3D.new()
	fur.size = Vector3(3.4, 2.4, 5.0)
	_grip_patch.shape = fur
	_grip_patch.disabled = true
	body.add_child(_grip_patch)
	_visual(body, Vector3(3.4, 2.4, 5.0), Vector3.ZERO)
	_visual(body, Vector3(1.4, 1.1, 1.7), Vector3(0, 0.3, -3.0))
	for side in [-1.0, 1.0]:
		var wing: BodySegment = _seg_by_bone[&"wing_l" if side < 0 else &"wing_r"]
		_visual(wing, Vector3(6.4, 0.15, 3.4), Vector3(side * 3.2, 0, 0.4))
		# Membranes are decoration; the continuous body patch is the climbing route.
	_pose_bones(0.0)

func _visual(segment: BodySegment, size: Vector3, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "RigGreybox"
	mesh.set_meta(&"guardian_placeholder", true)
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _body_material
	segment.add_child(mesh)

func _pose_bones(_delta: float) -> void:
	for side in [-1.0, 1.0]:
		var name: StringName = &"wing_l" if side < 0 else &"wing_r"
		var origin: Vector3 = BONES[1 if side < 0 else 2][2]
		skeleton.set_bone_pose(_bone[name], Transform3D(Basis(Vector3.BACK, side * _wing_angle), origin))

func _set_exposed(open: bool) -> void:
	weak_point.set_protected(not open)
	if _patch_open != open:
		_patch_open = open
		_grip_patch.set_deferred(&"disabled", not open)

func _set_motion(local_at: Vector3, roll: float) -> void:
	_roll = roll
	global_transform = Transform3D(_spawn_xf.basis * Basis(Vector3.BACK, roll), _spawn_xf * local_at)

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_spawn_xf = xf
	arena_center = _spawn_xf.origin
	_time = 0.0
	_think_left = 0.0
	_intent_time = 0.0
	_time_on_body.clear()
	_off_body_time.clear()
	_set_encounter(Encounter.DORMANT)
	weak_point.reset()
	stats = {"weak_point_hits": 0, "hits_on_player": 0, "light_breaks": 0, "ambushes": 0, "landings": 0, "coolings": 0}
	_reset_motion()
	_set_exposed(false)
	_pose_bones(0)
	_sync_segments()
	_sync_segments()
	for segment in segments:
		segment.reset_physics_interpolation()

func teleport(pos: Vector3, yaw: float) -> void:
	_spawn_xf = Transform3D(Basis(Vector3.UP, yaw), pos)
	arena_center = pos
	_reset_motion()
	_pose_bones(0)
	_sync_segments()
	_sync_segments()

func _reset_motion() -> void:
	_set_motion(Vector3(0, 2.25, 0), 0)

func _set_encounter(next: Encounter) -> void:
	if next == encounter:
		return
	encounter = next
	encounter_changed.emit(next)
	if next == Encounter.DEFEATED:
		defeated.emit()

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if encounter == Encounter.DORMANT:
		for p in obs.players:
			if not p.player.dead and p.distance < 45.0:
				_set_encounter(Encounter.COMBAT)
	return ColossusIntent.make(&"guardian")

func _on_struck(_damage: float, _left: float) -> void:
	stats.weak_point_hits += 1
	_flinched(0.5)

func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED

func encounter_name() -> String:
	return Encounter.keys()[encounter]

func beam_weak_point() -> WeakPoint:
	return weak_point if not is_defeated() else null

func weak_points_left() -> int:
	return 0 if is_defeated() else 1

func get_focus_point() -> Vector3:
	return global_position

func _rider_present() -> bool:
	for p in get_tree().get_nodes_in_group(&"players"):
		if not p.dead and (owns_body(p.get_support_body()) or p.is_climbing() and owns_body(p.grip.body)):
			return true
	return false

func _living_target() -> PlayerCharacter:
	var closest: PlayerCharacter
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p and not p.dead and (closest == null or p.global_position.distance_to(global_position) < closest.global_position.distance_to(global_position)):
			closest = p
	return closest

func get_danger_zones() -> Array:
	return []

func encounter_hint() -> String:
	return "Strażnik pilnuje przejścia."

func debug_text() -> String:
	return "%s %s: core %.0f, hits %d\n%s" % [name, encounter_name(), weak_point.health, stats.weak_point_hits, super()]
