class_name WeaponArt
extends Node3D
## Imported equipment and cosmetic hand poses. Combat remains in PlayerSword/Bow.
const FOLDER := "res://models/weapons_v4/"
const DRAW_DISTANCE := 0.44
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
var suspension_straps: Array[MeshInstance3D] = []
var belt_loops: Array[MeshInstance3D] = []
var quiver: Node3D
var arrow: Node3D
var string_top: MeshInstance3D
var string_bottom: MeshInstance3D
var stored_string_top: MeshInstance3D
var stored_string_bottom: MeshInstance3D
var quiver_arrows: Array[Node3D] = []
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
	quiver_arrows.clear()
	suspension_straps.clear()
	belt_loops.clear()
	sword = _piece("sword", "SwordInHand", true)
	bow = _piece("bow", "BowInHand", true)
	stored_sword = _piece("sword", "SwordStored")
	stored_bow = _piece("bow", "BowStored")
	scabbard = _piece("scabbard", "Scabbard")
	_build_scabbard_suspension()
	quiver = _piece("quiver", "Quiver")
	arrow = _piece("arrow", "NockedArrow", true)
	string_top = _string("StringUpper")
	string_bottom = _string("StringLower")
	stored_string_top = _string("StoredStringUpper")
	stored_string_bottom = _string("StoredStringLower")
	# Reuse the actual arrow asset. The quiver itself is a hollow case, not a
	# merged arrow bundle. Tips sit above its bottom and feathers clear its mouth.
	for index in 3:
		var spare := _piece("arrow", "QuiverArrow%d" % index)
		if spare:
			spare.reparent(quiver, false)
			spare.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3((index - 1) * 0.028, 0.515 + index * 0.018, -0.010 + (0.022 if index == 1 else 0.0)))
			quiver_arrows.append(spare)
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
	# The belt attachment remains body-local in every pose. Only the imported
	# stored equipment and its real leather hangers move; combat anchors do not.
	var seat_weight := player.riding.cosmetic_seat_weight() if player.riding and player.riding.is_active() else 0.0
	var sheath_frame := _scabbard_carry_frame(seat_weight)
	if scabbard: scabbard.transform = sheath_frame
	stored_sword.transform = sheath_frame
	_update_scabbard_suspension(sheath_frame)
	# Bow belly faces away from the spine. The string lies between bow and back.
	stored_bow.transform = Transform3D(Basis(Vector3.BACK, lerpf(0.43, 0.60, seat_weight)) * Basis(Vector3.UP, PI), Vector3(-0.035, 0.11 + 0.15 * seat_weight, 0.32))
	if quiver: quiver.transform = Transform3D(Basis(Vector3.FORWARD, 0.16), Vector3(0.24, 0.29, 0.235))
	stored_string_top.visible = stored_bow.visible
	stored_string_bottom.visible = stored_bow.visible
	_set_line(stored_string_top, stored_bow.to_global(_top), stored_bow.to_global(_nock))
	_set_line(stored_string_bottom, stored_bow.to_global(_nock), stored_bow.to_global(_bottom))

	hand_errors = [0.0, 0.0]
	if traveler:
		var archery_weight := 1.0 if bow_active and player.bow.is_aiming() else 0.0
		if bow_active and player.bow.state in [PlayerBow.State.RELEASE, PlayerBow.State.RECOVERY]:
			var elapsed := player.bow.state_time + (player.bow.release_time if player.bow.state == PlayerBow.State.RECOVERY else 0.0)
			archery_weight = 1.0 - smoothstep(.08, .30, elapsed)
		traveler.pose_bow_body(archery_weight, player.bow.draw_frame(player))
		# The shoulder-carried quiver follows the same torso turn, so the
		# drawing forearm cannot pass through a pack left in the old frame.
		if quiver: quiver.transform = Transform3D(traveler.archery_torso_basis, Vector3.ZERO) * quiver.transform
		traveler.set_bow_draw_hand(false)
	if sword_active:
		_update_sword()
		if traveler: hand_errors[1] = traveler.pose_hand(1, _hand_goal(sword.global_transform))
	if bow_active:
		_update_bow(delta)
		if traveler:
			hand_errors[0] = traveler.pose_hand(0, _hand_goal(bow.global_transform))
			if player.bow.is_aiming():
				traveler.set_bow_draw_hand(true)
				hand_errors[1] = traveler.pose_bow_draw(arrow.global_transform)
				traveler.fit_bow_string(bow.to_global(_top + Vector3(0, -.014, .06999) * draw_value), bow.to_global(_bottom + Vector3(0, .014, .06999) * draw_value))
			elif player.bow.state in [PlayerBow.State.RELEASE, PlayerBow.State.RECOVERY]:
				var elapsed := player.bow.state_time + (player.bow.release_time if player.bow.state == PlayerBow.State.RECOVERY else 0.0)
				var returning := smoothstep(0.10, 0.30, elapsed)
				if returning < 1.0:
					var aim_basis := Basis.looking_at(player.bow.aim_dir, Vector3.RIGHT if absf(player.bow.aim_dir.y) > 0.95 else Vector3.UP)
					var released_hand := player.bow.bow_point(player) + aim_basis.z * (0.035 * smoothstep(0.0, 0.10, elapsed))
					traveler.set_bow_draw_hand(true, smoothstep(0.0, 0.065, elapsed))
					traveler.pose_bow_draw(Transform3D(aim_basis, released_hand), 1.0 - returning)
	else:
		arrow.visible = false
		string_top.visible = false
		string_bottom.visible = false

	if traveler and player.is_riding():
		if not bow_active: traveler.pose_rein_hand(0)
		if not sword_active and not (bow_active and (player.bow.is_aiming() or (traveler._draw_hand and traveler._draw_hand.visible))): traveler.pose_rein_hand(1)

func _scabbard_carry_frame(seat_weight: float) -> Transform3D:
	var base_axis := Vector3(-0.055, -0.79, 0.61).lerp(Vector3(-0.24, -0.59, 0.77), seat_weight).normalized()
	var origin := Vector3(-0.23, 0.025, -0.03).lerp(Vector3(-0.22, -0.025, -0.02), seat_weight)
	var axis := base_axis
	# Side carry keeps the guard fore/aft and the blade's broad face alongside
	# the thigh, instead of pointing the guard inward through the tunic.
	var roll := -PI * 0.5
	var mouth := origin + base_axis * 0.125
	if player.riding and player.riding.phase in [PlayerRiding.Phase.MOUNTING, PlayerRiding.Phase.DISMOUNTING]:
		var riding := player.riding
		var t := clampf(riding._t, 0.0, 1.0)
		var route := riding._from_local if riding.phase == PlayerRiding.Phase.MOUNTING else riding._to_local
		if route.z < -0.5 and absf(route.z) > absf(route.x):
			# The front approach swings smoothly outside the neck. Cosmetic
			# rein slack follows the same broad window; no phase-local snap.
			var lift := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.65, 1.0, t))
			axis = base_axis.lerp(Vector3(-0.20, 0.258819, 0.965926).normalized(), lift).normalized()
			mouth.x -= 0.04 * lift
		elif route.x > 0.25:
			# Lift over the far side of the saddle, pivoting around the actual
			# mouth. A small longitudinal turn keeps the guard off the raised knee.
			var lift := sin(PI * t)
			axis = base_axis.lerp(Vector3(-0.10, 0.25, 0.99).normalized(), lift).normalized()
			var turn := smoothstep(0.0, 0.45, t) * (1.0 - smoothstep(0.55, 1.0, t))
			roll += deg_to_rad(30.0) * turn
	origin = mouth - axis * 0.125
	return Transform3D(_basis_y(axis, Vector3.RIGHT) * Basis(Vector3.UP, roll), origin)

func _update_sword() -> void:
	var local_hand := Vector3(0.29, -0.11, -0.05)
	var axis := (visual.global_basis * Vector3(0.35, -0.66, -0.66)).normalized()
	if player.is_riding():
		# A downward blade intersects Agro's shoulder once the rider is seated.
		# Rest it upright outside the rider's right knee, with elbow comfortably bent.
		local_hand = Vector3(0.36, 0.03, -0.18)
		axis = (visual.global_basis * Vector3(0.14, 0.93, -0.34)).normalized()
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
	var draw_travel := DRAW_DISTANCE * draw_value
	if aiming:
		var basis := Basis.looking_at(player.bow.aim_dir, Vector3.RIGHT if absf(player.bow.aim_dir.y) > 0.95 else Vector3.UP)
		# The draw hand keeps the physical nock while the bow arm extends. This
		# also prevents a jump when releasing before full draw, without changing aim.
		draw_travel = _reachable_draw_travel(basis, draw_travel)
		var current_nock := _nock + Vector3.BACK * draw_travel
		bow.global_transform = Transform3D(basis, player.bow.bow_point(player) - basis * current_nock)
	else:
		bow.global_transform = visual.global_transform * Transform3D(Basis(Vector3.RIGHT, -0.10), Vector3(-0.39, 0.18, -0.28) if player.is_riding() else Vector3(-0.45, -0.11, -0.07))
	for mesh in _flex_meshes:
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name("BowDraw"), draw_value)
	var nock := _nock + Vector3.BACK * draw_travel
	var top := _top + Vector3(0, -0.014, 0.06999) * draw_value
	var bottom := _bottom + Vector3(0, 0.014, 0.06999) * draw_value
	_set_line(string_top, bow.to_global(top), bow.to_global(nock))
	_set_line(string_bottom, bow.to_global(nock), bow.to_global(bottom))
	string_top.visible = true
	string_bottom.visible = true
	arrow.visible = aiming
	arrow.global_transform = Transform3D(bow.global_basis, bow.to_global(nock))

func _reachable_draw_travel(basis: Basis, wanted: float) -> float:
	var traveler := visual.get_node_or_null("TravelerArt") as TravelerArt
	if not traveler or traveler._wrists.is_empty(): return wanted
	# With a right-cheek anchor, slopes and off-axis aim give the bow arm less
	# available reach. Limit only its cosmetic extension; the nock, arrow axis
	# and gameplay muzzle remain identical. Solve the line/sphere intersection.
	var grip_basis := basis * Basis(Vector3.FORWARD, PI)
	var wrist_at_rest := player.bow.bow_point(player) - basis * _nock - grip_basis * traveler._grips[0].position
	var relative := wrist_at_rest - visual._arms[0].global_position
	var reach := traveler._forearms[0].position.length() + traveler._wrists[0].position.length() - .005
	var direction := -basis.z
	var projection := relative.dot(direction)
	var discriminant := projection * projection - relative.length_squared() + reach * reach
	if discriminant < 0.0: return 0.0
	return minf(wanted, maxf(0.0, -projection + sqrt(discriminant)))

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

func _build_scabbard_suspension() -> void:
	# Solid leather strips, not a painted line or a disconnected floating case.
	var leather := StandardMaterial3D.new()
	leather.resource_name = "Sword belt suspension leather"
	leather.albedo_color = Color(0.22, 0.105, 0.046)
	leather.roughness = 0.84
	for index in 2:
		var strap := MeshInstance3D.new()
		strap.name = "ScabbardSuspensionStrap%d" % index
		var strip := BoxMesh.new()
		strip.size = Vector3(0.023, 1.0, 0.006)
		strap.mesh = strip
		strap.material_override = leather
		add_child(strap)
		suspension_straps.append(strap)
		var loop := MeshInstance3D.new()
		loop.name = "SwordBeltLoop%d" % index
		var loop_mesh := TorusMesh.new()
		loop_mesh.inner_radius = 0.011
		loop_mesh.outer_radius = 0.017
		loop_mesh.rings = 12
		loop_mesh.ring_segments = 8
		loop.mesh = loop_mesh
		loop.material_override = leather
		add_child(loop)
		belt_loops.append(loop)

func _update_scabbard_suspension(frame: Transform3D) -> void:
	for index in 2:
		# Front/rear belt anchors straddle the left iliac crest. Loops physically
		# wrap the existing 57 mm leather girdle; straps end at the brass rings.
		var anchor := Vector3(-0.151, -0.078, -0.052 if index == 0 else 0.052)
		var ring := frame * Vector3(0.043, 0.145 if index == 0 else 0.31, 0.004)
		var direction := (ring - anchor).normalized()
		var strap := suspension_straps[index]
		strap.transform = Transform3D(_basis_y(direction, Vector3.FORWARD).scaled_local(Vector3(1, anchor.distance_to(ring), 1)), (anchor + ring) * 0.5)
		# Torus lies in XZ by default; put its opening around the vertical belt.
		belt_loops[index].transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).scaled_local(Vector3(2.15, 0.62, 0.65)), anchor)
