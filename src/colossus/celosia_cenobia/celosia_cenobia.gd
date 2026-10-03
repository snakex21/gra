class_name CelosiaCenobia
extends Colossus
## One encounter, two simultaneous guardians; both sigils are required for victory.
const STARTS := [Vector3(-14, 0, 8), Vector3(18, 0, -10)]
const FIRE := Vector3(-20, 0, 5)
var guardians: Array[PairedSentinel] = []
var weak_points: Array[WeakPoint] = []
var torch_carriers: Array[PlayerCharacter] = []
var stats := {"armour_breaks": 0, "weak_point_hits": 0}
var _won := false
var _flame: MeshInstance3D
var _columns: Array[StaticBody3D] = []
var brain_seed := 89

func _init() -> void:
	arena_radius = 175.0
	body_height = 3.2

func _ready() -> void:
	super()
	process_physics_priority = -12
	for guardian in guardians:
		weak_points.append(guardian.weak_point)
		guardian.weak_point.struck.connect(func(_d: float, _h: float) -> void: stats.weak_point_hits += 1)
	var flame := SphereMesh.new()
	flame.radius = 0.22
	flame.height = 0.6
	_flame = MeshInstance3D.new()
	_flame.top_level = true
	_flame.mesh = flame
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.45, 0.06)
	_flame.material_override = mat
	_flame.visible = false
	add_child(_flame)
	for node in get_parent().get_children():
		if node is StaticBody3D and node.has_meta(&"cenobia_column"):
			_columns.append(node)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	skeleton.add_bone(&"encounter_anchor")
	for i in 2:
		var guardian := PairedSentinel.new()
		guardian.name = "Celosia" if i == 0 else "Cenobia"
		guardian.coordinator = self
		guardian.index = i
		guardian.position = STARTS[i]
		guardian.rotation.y = PI
		add_child(guardian)
		guardians.append(guardian)

func _execute_intent(_it: ColossusIntent, _delta: float) -> void:
	var alive: Array[PlayerCharacter] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p != null and not p.dead and p.global_position.distance_to(global_position) < arena_radius:
			alive.append(p)
			if p.weapon == PlayerCharacter.Weapon.SWORD and p.actions.beam_held and p.global_position.distance_to(to_global(FIRE)) < 4.0 and not torch_carriers.has(p):
				torch_carriers.append(p)
	# The flame stays on the sword while it is lowered for repositioning. Raising
	# and aiming it still gates repulsion; switching weapon/death/reset extinguishes
	# it. Otherwise an unfavourable approach angle traps the player at the hearth.
	torch_carriers = torch_carriers.filter(func(p: PlayerCharacter) -> bool: return is_instance_valid(p) and not p.dead and p.weapon == PlayerCharacter.Weapon.SWORD)
	for i in guardians.size():
		guardians[i].target = alive[i % alive.size()] if not alive.is_empty() else null
	var raised := torch_carriers.filter(func(p: PlayerCharacter) -> bool: return p.actions.beam_held)
	_flame.visible = not raised.is_empty()
	if _flame.visible:
		_flame.global_position = SwordBeam.tip(raised[0])

func fire_carrier(beast: PairedSentinel) -> PlayerCharacter:
	var nearest: PlayerCharacter
	for p in torch_carriers:
		if not p.actions.beam_held:
			continue
		if nearest == null or p.global_position.distance_to(beast.global_position) < nearest.global_position.distance_to(beast.global_position):
			nearest = p
	return nearest

func fire_faces(beast: PairedSentinel) -> bool:
	var p := fire_carrier(beast)
	if p == null:
		return false
	var to := beast.get_focus_point() - SwordBeam.tip(p)
	return to.length() < 15.0 and (-p.actions.view_basis.z).dot(to.normalized()) > 0.5

func sheltered(p: PlayerCharacter) -> bool:
	var local := to_local(p.global_position)
	return Vector2(local.x - FIRE.x, local.z - FIRE.z).length() < 4.0 and local.y < 3.5

func wall_impact(beast: PairedSentinel, collider: Object) -> bool:
	if not collider is Node:
		return false
	var node := collider as Node
	if beast.index == 0 and beast.mode == PairedSentinel.Mode.FIRE_RETREAT and node.has_meta(&"celosia_fire_wall"):
		stats.armour_breaks += 1
		return true
	if beast.index == 1 and beast.mode == PairedSentinel.Mode.CHARGE and node.has_meta(&"cenobia_column"):
		for child in node.get_children():
			if child is CollisionShape3D:
				child.set_deferred(&"disabled", true)
			elif child is MeshInstance3D:
				child.visible = false
		stats.armour_breaks += 1
		return true
	return false

func on_guardian_defeated() -> void:
	if not _won and guardians.all(func(g: PairedSentinel) -> bool: return g.is_defeated()):
		_won = true
		defeated.emit()

func owns_body(obj: Object) -> bool:
	return obj is BodySegment and guardians.has((obj as BodySegment).colossus)

func is_defeated() -> bool:
	return _won

func beam_weak_point() -> WeakPoint:
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			return wp
	return null

func get_focus_point() -> Vector3:
	return (guardians[0].global_position + guardians[1].global_position) * 0.5 + Vector3.UP * 2.0

func get_danger_zones() -> Array:
	var zones := []
	for guardian in guardians:
		zones.append_array(guardian.get_danger_zones())
	return zones

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		global_transform = xf
	_won = false
	torch_carriers.clear()
	stats = {"armour_breaks": 0, "weak_point_hits": 0}
	for guardian in guardians:
		guardian.reset_guardian()
	for column in _columns:
		for child in column.get_children():
			if child is CollisionShape3D:
				child.set_deferred(&"disabled", false)
			elif child is MeshInstance3D:
				child.visible = true

func debug_text() -> String:
	return "CELOSIA + CENOBIA | ogień/schronienie i taranowanie kolumn | %s/%s" % [PairedSentinel.Mode.keys()[guardians[0].mode], PairedSentinel.Mode.keys()[guardians[1].mode]]

func encounter_hint() -> String:
	if _won:
		return "Obaj strażnicy pokonani. Przejście jest wolne."
	if not guardians[0].armour_open:
		return "Przy palenisku podnieś miecz (V), potem opuść go i ustaw się tak, by Celosia miała mur za plecami. Unieś płomień i odeprzyj ją na mur; schronienie chroni przed szarżami."
	if not guardians[1].armour_open:
		return "Celosia wraca do ataku. Ustaw kolumnę między sobą a Cenobią. Gdy zapowie taran, zejdź z jego linii."
	return "Oba pancerze są otwarte. Rozdziel strażników, chwyć odsłonięte futro z tyłu i zniszcz oba znaki."
