class_name WeaponArt
extends Node3D
## Imported equipment and cosmetic hand poses. Combat remains in PlayerSword/Bow.
const FOLDER := "res://models/weapons_v4/"
const DRAW_DISTANCE := 0.34
static var _scenes := {}
var player: PlayerCharacter
var visual: PlayerVisual
var current_lod := -1
var auto_lod := true
var sword: Node3D
var bow: Node3D
var stored_sword: Node3D
var stored_bow: Node3D
var scabbard: Node3D
var quiver: Node3D
var arrow: Node3D
var string_top: MeshInstance3D
var string_bottom: MeshInstance3D
var draw_value := 0.0
var hand_errors := [0.0, 0.0]
var _clock := 0.0
var _tip_y := 1.09
var _top := Vector3(0, 0.70, 0.13)
var _bottom := Vector3(0, -0.70, 0.13)
var _nock := Vector3(0, 0.06, 0.13)
var _flex_meshes: Array[MeshInstance3D] = []

static func attach(to_visual: PlayerVisual, to_player: PlayerCharacter) -> WeaponArt:
	var old := to_visual.get_node_or_null("WeaponArt") as WeaponArt
	if old: return old
	var art := WeaponArt.new()
	art.name = "WeaponArt"
	art.player = to_player
	art.visual = to_visual
	to_visual.add_child(art)
	return art

static func _scene(id: String, lod: int) -> PackedScene:
	var path := FOLDER + id + "_lod%d.glb" % lod
	if not ResourceLoader.exists(path): return null
	if not _scenes.has(path): _scenes[path] = load(path) as PackedScene
	return _scenes[path]

static func dress_arrow(carrier: MeshInstance3D) -> void:
	var scene := _scene("arrow", 1)
	if not scene or carrier.has_node("ArrowModel"): return
	var model := scene.instantiate() as Node3D
	model.name = "ArrowModel"
	# Nock origin agrees with the held arrow and the physical spawn position.
	# Keep the stable historical carrier type/key for old checkpoints.
	carrier.mesh = null
	carrier.add_child(model)

func _ready() -> void:
	process_priority = 20
	set_lod(0)

func _piece(id: String, label: String, top_level := false) -> Node3D:
	var packed := _scene(id, current_lod)
	if not packed: return null
	var node := packed.instantiate() as Node3D
	node.name = label
	add_child(node)
	node.top_level = top_level
	return node

func set_lod(level: int) -> void:
	level = clampi(level, 0, 2)
	if current_lod == level: return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	current_lod = level
	_flex_meshes.clear()
	sword = _piece("sword", "SwordInHand", true)
	bow = _piece("bow", "BowInHand", true)
	stored_sword = _piece("sword", "SwordStored")
	stored_bow = _piece("bow", "BowStored")
	scabbard = _piece("scabbard", "Scabbard")
	quiver = _piece("quiver", "Quiver")
	arrow = _piece("arrow", "NockedArrow", true)
	string_top = _string("StringUpper")
	string_bottom = _string("StringLower")
	if sword: _tip_y = _marker(sword, "BladeTip", Vector3(0, _tip_y, 0)).y
	if bow:
		_top = _marker(bow, "StringTop", _top)
		_bottom = _marker(bow, "StringBottom", _bottom)
		_nock = _marker(bow, "NockRest", _nock)
		for mesh: MeshInstance3D in bow.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh and mesh.find_blend_shape_by_name("BowDraw") >= 0:
				_flex_meshes.append(mesh)
	update_equipment(0.0)

func _marker(root: Node3D, label: String, fallback: Vector3) -> Vector3:
	var marker := root.find_child(label + "*", true, false) as Node3D
	return root.to_local(marker.global_position) if marker else fallback

func _string(label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.0018
	cylinder.bottom_radius = 0.0018
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.66, 0.49)
	mat.roughness = 0.9
	node.mesh = cylinder
	node.material_override = mat
	add_child(node)
	node.top_level = true
	return node

func _process(delta: float) -> void:
	update_equipment(delta)
	_clock += delta
	if auto_lod and _clock >= 0.25:
		_clock = 0.0
		var camera := get_viewport().get_camera_3d()
		if camera:
			var distance := camera.global_position.distance_to(player.global_position)
			set_lod(0 if distance < 12.0 else (1 if distance < 35.0 else 2))

func update_equipment(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(visual): return
	if not sword or not bow: return
	visual._blade.visible = false
	var traveler := visual.get_node_or_null("TravelerArt") as TravelerArt
	var climbing := player.is_climbing()
	var free_hands := not player.dead and player.state != PlayerCharacter.State.SWIM and player.balance.state != Balance.State.FALLEN
	var sword_active := free_hands and player.weapon == PlayerCharacter.Weapon.SWORD and (not climbing or player.sword.is_busy())
	var bow_active := free_hands and player.weapon == PlayerCharacter.Weapon.BOW and not climbing
	sword.visible = sword_active
	bow.visible = bow_active
	stored_sword.visible = not sword_active
	stored_bow.visible = not bow_active
	# Back equipment follows the same cosmetic body orientation on Agro and walls.
	var sheath_basis := _basis_y(Vector3(-0.38, -0.78, 0.50).normalized(), Vector3.RIGHT)
	if scabbard: scabbard.transform = Transform3D(sheath_basis, Vector3(-0.31, 0.09, 0.10))
	stored_sword.transform = Transform3D(sheath_basis, Vector3(-0.31, 0.09, 0.10))
	stored_bow.transform = Transform3D(Basis(Vector3.FORWARD, -0.25), Vector3(0.10, 0.05, 0.26))
	if quiver: quiver.transform = Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(0.27, -0.05, 0.30))
	hand_errors = [0.0, 0.0]
	if sword_active:
		_update_sword()
		if traveler: hand_errors[1] = traveler.pose_hand(1, _hand_goal(sword.global_transform))
	if bow_active:
		_update_bow(delta)
		if traveler:
			hand_errors[0] = traveler.pose_hand(0, _hand_goal(bow.global_transform))
			if player.bow.is_aiming():
				hand_errors[1] = traveler.pose_hand(1, _hand_goal(arrow.global_transform))
	else:
		arrow.visible = false
		string_top.visible = false
		string_bottom.visible = false

func _update_sword() -> void:
	var local_hand := Vector3(0.29, -0.11, -0.05)
	var axis := (visual.global_basis * Vector3(0.35, -0.66, -0.66)).normalized()
	var at := visual.to_global(local_hand)
	var attack := player.sword
	if player.beam.raise > 0.01:
		var raised := player.beam.raise
		var tip := SwordBeam.tip(player)
		var up_axis := (Vector3.UP + visual.global_basis.x * -0.14).normalized()
		var raised_hand := tip - up_axis * _tip_y
		at = at.lerp(raised_hand, raised)
		axis = axis.slerp(up_axis, raised).normalized()
	elif attack.state == PlayerSword.State.CHARGE:
		at = visual.to_global(Vector3(0.30, 0.39, 0.03))
		axis = (visual.global_basis * Vector3(-0.12, 0.96, 0.26)).normalized()
	elif attack.state == PlayerSword.State.STRIKE:
		var progress := clampf(attack.state_time / attack.strike_time, 0.0, 1.0)
		at = visual.to_global(Vector3(0.28, lerpf(0.39, 0.12, progress), lerpf(0.03, -0.25, progress)))
		axis = (visual.global_basis * Vector3(0.0, cos(progress * PI), -sin(progress * PI))).normalized()
	elif player.is_climbing():
		at = visual.to_global(Vector3(0.29, 0.43, -0.10))
		axis = (visual.global_basis * Vector3(0.0, 0.2, -1.0)).normalized()
	sword.global_transform = Transform3D(_basis_y(axis, visual.global_basis.x), at)

func _update_bow(delta: float) -> void:
	var aiming := player.bow.is_aiming()
	var want := player.bow.draw if aiming else 0.0
	draw_value = move_toward(draw_value, want, delta * (3.0 if aiming else 18.0)) if delta > 0.0 else want
	if aiming:
		var basis := Basis.looking_at(player.bow.aim_dir, Vector3.RIGHT if absf(player.bow.aim_dir.y) > 0.95 else Vector3.UP)
		# The draw hand keeps the physical nock while the bow arm extends. This
		# also prevents a jump when releasing before full draw, without changing aim.
		var current_nock := _nock + Vector3.BACK * (DRAW_DISTANCE * draw_value)
		bow.global_transform = Transform3D(basis, player.bow.bow_point(player) - basis * current_nock)
	else:
		bow.global_transform = visual.global_transform * Transform3D(Basis(Vector3.RIGHT, -0.10), Vector3(-0.29, -0.11, -0.07))
	for mesh in _flex_meshes:
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name("BowDraw"), draw_value)
	var nock := _nock + Vector3.BACK * (DRAW_DISTANCE * draw_value)
	var top := _top + Vector3(0, -0.014, 0.06999) * draw_value
	var bottom := _bottom + Vector3(0, 0.014, 0.06999) * draw_value
	_set_line(string_top, bow.to_global(top), bow.to_global(nock))
	_set_line(string_bottom, bow.to_global(nock), bow.to_global(bottom))
	string_top.visible = true
	string_bottom.visible = true
	arrow.visible = aiming
	arrow.global_transform = Transform3D(bow.global_basis, bow.to_global(nock))

static func _hand_goal(weapon_xf: Transform3D) -> Transform3D:
	# The fingers wrap about the hand's -Y axis; all grips use the asset's +Y axis.
	return Transform3D(weapon_xf.basis * Basis(Vector3.FORWARD, PI), weapon_xf.origin)

static func _basis_y(y: Vector3, hint_x: Vector3) -> Basis:
	var x := hint_x - y * hint_x.dot(y)
	if x.length_squared() < 0.0001: x = y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.UP)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())

static func _set_line(line: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var basis := _basis_y((b - a).normalized(), Vector3.RIGHT)
	line.global_transform = Transform3D(Basis(basis.x, basis.y * maxf(length, 0.001), basis.z), (a + b) * 0.5)
