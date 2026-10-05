extends Node3D
## Left-hip suspension, all-LOD equipment switching and unchanged hand/arrow axes.
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func check_imported_suspension_rings(gear: WeaponArt, lod: int) -> void:
	# The attachment coordinates must correspond to real imported brass rings,
	# not just matching invented endpoints in both production and test code.
	# Their outer-X rim is separated from the main scabbard suspension band.
	var nearest := [INF, INF]
	for node in gear.scabbard.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh: continue
		var into_case := gear.scabbard.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if not material or not "bronze" in material.resource_name.to_lower(): continue
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := into_case * vertex
				for index in 2:
					var ring_rim := Vector3(.052, .145 if index == 0 else .31, .004)
					nearest[index] = minf(nearest[index], point.distance_to(ring_rim))
	for index in 2:
		check(float(nearest[index]) < .004, "LOD%d authored suspension endpoint has no real bronze ring rim %d" % [lod, index])

func check_suspension(gear: WeaponArt, context: String) -> void:
	check(is_instance_valid(gear.scabbard), context + ": missing scabbard")
	if not is_instance_valid(gear.scabbard): return
	var frame := gear.scabbard.transform
	var transitioning := gear.player.riding and gear.player.riding.phase in [PlayerRiding.Phase.MOUNTING, PlayerRiding.Phase.DISMOUNTING]
	check(gear.scabbard.is_visible_in_tree(), context + ": empty or occupied scabbard disappeared")
	check(gear.scabbard.get_parent() == gear and not gear.scabbard.top_level, context + ": scabbard lost body-local attachment")
	check(gear.stored_sword.transform.is_equal_approx(frame), context + ": stored blade and scabbard frames differ")
	var mouth := frame * Vector3(0, .125, 0)
	var tip := frame * Vector3(0, 1.124, 0)
	# Broad anatomical bounds deliberately avoid locking the presentation to one
	# candidate's exact translation or seated sweep.
	check(frame.origin.x < -.20 and frame.origin.x > -.65, context + ": mount is not outside the left hip")
	check(frame.origin.y > -.25 and frame.origin.y < .25, context + ": mount migrated from waist to shoulder/leg")
	# Anatomical envelope rejects the old detached 23–33 cm hangers and keeps
	# the mouth alongside the waist, rather than just checking ring connectivity.
	check(mouth.x > -.30 and mouth.z < .10, context + ": mouth floats away from the left hip")
	check(absf(frame.basis.x.dot(Vector3.RIGHT)) < (.60 if transitioning else .10), context + ": crossguard points inward through the hip instead of fore/aft")
	check(mouth.x < -.20 and tip.x < mouth.x, context + ": sheath crosses inward through the body")
	check((transitioning or tip.y < mouth.y) and tip.z > mouth.z + .20, context + ": sheath no longer hangs rearward/downward")
	check(frame.is_finite() and absf(frame.basis.determinant() - 1.0) < .0001, context + ": mount has invalid or changed asset scale")
	check(gear.suspension_straps.size() == 2 and gear.belt_loops.size() == 2, context + ": expected two straps and two belt loops")
	check(gear.find_children("ScabbardSuspensionStrap*", "MeshInstance3D", false, false).size() == 2, context + ": duplicate or missing suspension straps")
	check(gear.find_children("SwordBeltLoop*", "MeshInstance3D", false, false).size() == 2, context + ": duplicate or missing belt loops")
	for label in ["Scabbard", "SwordStored", "SwordInHand", "BowStored", "BowInHand", "Quiver", "NockedArrow"]:
		check(gear.find_children(label, "Node3D", false, false).size() == 1, context + ": duplicate or missing " + label)
	if gear.suspension_straps.size() != 2 or gear.belt_loops.size() != 2: return
	for index in 2:
		var strap := gear.suspension_straps[index]
		var loop := gear.belt_loops[index]
		check(is_instance_valid(strap) and is_instance_valid(loop), context + ": stale LOD suspension references")
		if not is_instance_valid(strap) or not is_instance_valid(loop): continue
		check(strap.get_parent() == gear and loop.get_parent() == gear and not strap.top_level and not loop.top_level, context + ": suspension does not inherit body motion")
		check(strap.is_visible_in_tree() and loop.is_visible_in_tree(), context + ": suspension is hidden")
		check(strap.mesh != null and loop.mesh != null, context + ": suspension has no real geometry")
		if not strap.mesh or not loop.mesh: continue
		var bounds := strap.mesh.get_aabb()
		check(bounds.size.x > .01 and bounds.size.z > .002, context + ": suspension strap lacks visible width/thickness")
		var ring := frame * Vector3(.043, .145 if index == 0 else .31, .004)
		var end_a := strap.transform * Vector3(0, bounds.position.y, 0)
		var end_b := strap.transform * Vector3(0, bounds.end.y, 0)
		# The front arc temporarily lengthens the first hanger by design;
		# keep the tighter static envelope and unchanged second-strap cap.
		var max_length := (.22 if transitioning else .20) if index == 0 else .28
		check(end_a.distance_to(end_b) < max_length, context + ": overlong leather suspension %d (%.4f m)" % [index, end_a.distance_to(end_b)])
		var ring_is_b := end_b.distance_to(ring) < end_a.distance_to(ring)
		var ring_end := end_b if ring_is_b else end_a
		var belt_end := end_a if ring_is_b else end_b
		check(ring_end.distance_to(ring) < .0001, context + ": strap does not reach its authored bronze suspension ring")
		check(belt_end.distance_to(loop.position) < .0001, context + ": strap does not reach its belt loop")
		var anchor := loop.position
		check(anchor.x < -.10 and anchor.x > -.20 and anchor.y >= -.110 and anchor.y <= -.053 and absf(anchor.z) < .10, context + ": loop is not on the visible waist girdle")
		# Actual imported belt is narrowed by .79 in X/Z, unlike the hidden
		# legacy radius-.31 cylinder. Check its surface, not an exact mount point.
		var lower := clampf((anchor.y + .110) / .035, 0.0, 1.0)
		var upper := clampf((anchor.y + .075) / .022, 0.0, 1.0)
		var rx := lerpf(.224, .214, lower) * .79 if anchor.y <= -.075 else lerpf(.214, .210, upper) * .79
		var rz := lerpf(.151, .140, lower) * .79 if anchor.y <= -.075 else lerpf(.140, .139, upper) * .79
		var belt_x := -rx * sqrt(maxf(0.0, 1.0 - pow(anchor.z / rz, 2.0)))
		check(absf(anchor.x - belt_x) < .012, context + ": loop floats away from the actual elliptical belt")
		var loop_bounds := loop.mesh.get_aabb()
		var lowest := INF
		var highest := -INF
		for corner in 8:
			var point := loop.transform * loop_bounds.get_endpoint(corner)
			lowest = minf(lowest, point.y)
			highest = maxf(highest, point.y)
		check(lowest <= -.110 and highest >= -.053, context + ": loop does not span the girdle height")

func check_transition_cycle(player: PlayerCharacter, art: TravelerArt, gear: WeaponArt, horse: Horse, lod: int, cycle: int) -> void:
	var route: Vector3 = [Vector3(-1.15, .895, 0), Vector3(1.15, .895, 0), Vector3(0, .895, -2.0), Vector3(0, .895, 2.0)][cycle % 4]
	var foot_position := horse.global_transform * route
	player.global_position = foot_position
	player.riding.mount_now(horse)
	player.riding._from_local = horse.body_transform().affine_inverse() * foot_position
	for phase in [PlayerRiding.Phase.MOUNTING, PlayerRiding.Phase.DISMOUNTING]:
		player.riding.phase = phase
		player.riding._to_local = route
		var previous := Transform3D.IDENTITY
		for step in 33:
			player.riding._t = step / 32.0
			player.riding.update(0)
			player.weapon = PlayerCharacter.Weapon.SWORD if step % 2 == 0 else PlayerCharacter.Weapon.BOW
			player.sword.reset()
			player.bow.reset()
			var gameplay_frame := player.global_transform
			art.pose_preview(&"ride" if player.riding.is_active() else &"idle", .7)
			gear.update_equipment(0)
			var context := "LOD%d cycle%d phase%d step%d" % [lod, cycle, phase, step]
			check_suspension(gear, context)
			check(gear.sword.visible == (player.weapon == PlayerCharacter.Weapon.SWORD), context + ": held sword visibility did not follow rapid switch")
			check(gear.stored_sword.visible == not gear.sword.visible, context + ": stored sword visibility disagrees with hand")
			check(player.global_transform.is_equal_approx(gameplay_frame), context + ": cosmetic attachment moved gameplay rider")
			if step > 0:
				check(gear.scabbard.position.distance_to(previous.origin) < .10 and gear.scabbard.basis.y.distance_to(previous.basis.y) < .30, context + ": mount/dismount attachment snaps")
			previous = gear.scabbard.transform
	check(not player.riding.is_active(), "Dismount cycle left the native riding phase active")
	player.state = PlayerCharacter.State.GROUND
	player.position = Vector3(0, .895, 0)
	player.visual.transform = Transform3D.IDENTITY

# Keep the native try_dismount/release/_finish lifecycle, replacing only the
# terrain query so every dismount direction is deterministic in this empty scene.
class ReinTransitionRiding extends PlayerRiding:
	var forced_spot := Vector3.ZERO
	func _init(owner_player: PlayerCharacter) -> void:
		super(owner_player)
	func _find_dismount_spot() -> Variant:
		return forced_spot

func rein_script_state(object: Object) -> Dictionary:
	var result := {}
	for property in object.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = object.get(property.name)
		if value is Array or value is Dictionary: value = value.duplicate(true)
		result[property.name] = value
	return result

func rein_gameplay_state(player: PlayerCharacter, horse: Horse) -> Array:
	return [player.global_transform, player.velocity, player.facing, player.surface_velocity,
		player.state, player.weapon, player.collision_layer, player.collision_mask,
		player._shape, player.actions, player.sword, player.bow, player.riding,
		rein_script_state(player.actions), rein_script_state(player.riding),
		horse.global_transform, horse.velocity, horse.collision_layer, horse.collision_mask,
		horse.controller, rein_script_state(horse.controller), rein_script_state(horse.intent),
		horse.current_rider, horse.command, horse.command_target, horse.command_position]

func check_rein_sample(player: PlayerCharacter, horse: Horse, reins: AgroReins, delta: float, context: String) -> Array[Vector3]:
	# Independently calculate the established bit/hand/saddle targets and exact
	# exponential endpoint smoothing, before asking production to rebuild the mesh.
	var body := horse.body_transform()
	var inv := horse.global_transform.affine_inverse()
	var targets: Array[Vector3] = [body * Vector3(-.21, .47, -.27), body * Vector3(.21, .47, -.27)]
	var rider := horse.current_rider as PlayerCharacter
	if is_instance_valid(rider) and rider.riding.phase == PlayerRiding.Phase.RIDING:
		var rider_art := rider.visual.get_node("TravelerArt") as TravelerArt
		if not rider.bow.is_aiming() and not (rider_art._draw_hand and rider_art._draw_hand.visible):
			var grip := rider_art._grips[0 if rider.weapon == PlayerCharacter.Weapon.SWORD else 1]
			for side in 2: targets[side] = grip.global_position + body.basis.x * (-.009 if side == 0 else .009)
	var expected_ends: Array[Vector3] = []
	for side in 2:
		var target := inv * targets[side]
		expected_ends.append(reins._ends[side].lerp(target, 1.0 - exp(-20.0 * delta)) if reins._ends.size() == 2 else target)
	var gameplay_before := rein_gameplay_state(player, horse)
	reins.update_reins(delta)
	check(rein_gameplay_state(player, horse) == gameplay_before, context + ": cosmetic reins changed rider/horse physics, actions, steering, or riding state")
	check(reins.get_parent() == horse and reins.straps.get_parent() == reins and not reins.top_level and not reins.straps.top_level, context + ": reins lost their horse-local visual attachment")
	check(reins.find_children("*", "CollisionObject3D", true, false).is_empty(), context + ": cosmetic reins introduced collision")
	var mesh := reins.straps.mesh
	check(mesh != null and mesh.get_surface_count() == 1, context + ": missing or accumulated rein surfaces")
	if not mesh or mesh.get_surface_count() != 1: return []
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES and indices.size() == 120 and AgroReins.TRIANGLE_COUNT == 40, context + ": rein topology is no longer 40 triangles")
	check(vertices.size() == 28 and normals.size() == 28, context + ": rein cross-section topology changed")
	if vertices.size() != 28 or normals.size() != 28: return []
	var finite := true
	for vertex in vertices: finite = finite and vertex.is_finite()
	for normal in normals: finite = finite and normal.is_finite()
	check(finite, context + ": invalid rein vertices or normals")
	var centers: Array[Vector3] = []
	for ring in 7:
		var center := Vector3.ZERO
		for corner in 4: center += vertices[ring * 4 + corner] * .25
		centers.append(center)
	var head := horse.skeleton.global_transform * horse.skeleton.get_bone_global_pose(horse._bone[&"head"])
	check(reins._ends.size() == 2, context + ": endpoint state count changed")
	if reins._ends.size() != 2: return centers
	var expected_indices := PackedInt32Array()
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var bit := inv * (head * Vector3(sign_x * .120, -.3471, -.5148))
		var midpoint := inv * (body * Vector3(sign_x * .31, .36, -.85))
		var original_rings := [0, 2, 3] if side == 0 else [4, 5, 6]
		check(centers[original_rings[0]].distance_to(bit) < .00001, context + ": rein left its bit attachment")
		check(reins._ends[side].distance_to(expected_ends[side]) < .00001, context + ": bit/hand/saddle endpoint interpolation changed")
		check(centers[original_rings[2]].distance_to(reins._ends[side]) < .00001, context + ": rein mesh no longer reaches its smoothed hand/saddle endpoint")
		check(centers[original_rings[1]].distance_to(midpoint) < .00001, context + ": original rein midpoint changed")
		# The inserted left bend must preserve all 24 original vertices, not
		# merely their centers. Reconstruct the baseline three-ring frames;
		# the entire right strap must remain geometrically identical.
		var original_points: Array[Vector3] = [bit, midpoint, expected_ends[side]]
		for point in 3:
			var tangent := (original_points[mini(point + 1, 2)] - original_points[maxi(point - 1, 0)]).normalized()
			var across := tangent.cross(Vector3.UP).normalized()
			if across.length_squared() < .01: across = Vector3.RIGHT
			var normal := tangent.cross(across).normalized()
			var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for corner in 4:
				var index: int = original_rings[point] * 4 + corner
				var expected_vertex: Vector3 = original_points[point] + across * corners[corner].x * .0045 + normal * corners[corner].y * .0025
				check(vertices[index].distance_to(expected_vertex) < .00001, context + ": original rein cross-section vertex changed")
				check(normals[index].distance_to(normal * corners[corner].y) < .0001, context + ": original rein cross-section normal changed")
		var offset := 0 if side == 0 else 16
		for segment in (3 if side == 0 else 2):
			for edge in 4:
				var a := offset + segment * 4 + edge
				var b := offset + segment * 4 + (edge + 1) % 4
				expected_indices.append_array([a, b, b + 4, a, b + 4, a + 4])
	check(indices == expected_indices, context + ": rein strip connectivity changed beyond the inserted left bend")
	return centers

func rein_local_deflection(horse: Horse, centers: Array[Vector3]) -> Vector3:
	var baseline := centers[0].lerp(centers[2], .4)
	return horse.body_transform().basis.inverse() * (horse.global_basis * (centers[1] - baseline))

func check_rein_transitions(player: PlayerCharacter, art: TravelerArt, gear: WeaponArt, horse: Horse) -> void:
	var reins := horse.get_node_or_null("AgroReins") as AgroReins
	check(reins != null, "Production horse is missing cosmetic reins")
	if not reins: return
	var saved_riding := player.riding
	var test_riding := ReinTransitionRiding.new(player)
	player.riding = test_riding
	var saved_horse_frame := horse.global_transform
	var front_profile: Array[Vector3] = []
	var routes := [Vector3(0, .895, -2.0), Vector3(-1.15, .895, 0), Vector3(1.15, .895, 0), Vector3(0, .895, 2.0)]
	# A translated, pitched/yawed/rolled horse catches world-axis offsets. The
	# added bend is measured in the body-bone frame, not the collision root.
	for rotated in 2:
		horse.global_transform = saved_horse_frame if rotated == 0 else Transform3D(Basis.from_euler(Vector3(.13, 1.1, -.09)), Vector3(3, .7, -4))
		horse.set_rider(null)
		var empty := check_rein_sample(player, horse, reins, 1.0, "unmounted horse frame%d" % rotated)
		if empty.size() == 7: check(rein_local_deflection(horse, empty).length() < .00001, "Unmounted horse received a front-transition rein offset")
		for route_index in routes.size():
			var route: Vector3 = routes[route_index]
			player.global_position = horse.global_transform * route
			check(test_riding.try_mount(), "Could not start native rein mount test")
			for phase in [PlayerRiding.Phase.MOUNTING, PlayerRiding.Phase.DISMOUNTING]:
				if phase == PlayerRiding.Phase.DISMOUNTING:
					test_riding.forced_spot = route
					check(test_riding.try_dismount(), "Could not start native rein dismount test")
					check(horse.current_rider == null and test_riding.horse == horse, "Native dismount did not release current_rider while retaining its transition horse")
				var previous: Array[Vector3] = []
				var previous_deflection := Vector3.ZERO
				for step in 65:
					test_riding._t = step / 64.0
					test_riding.update(0)
					player.weapon = PlayerCharacter.Weapon.SWORD if step % 2 == 0 else PlayerCharacter.Weapon.BOW
					player.sword.reset()
					player.bow.reset()
					art.pose_preview(&"ride" if test_riding.is_active() else &"idle", .7)
					gear.update_equipment(0)
					var context := "reins frame%d route%d phase%d step%d" % [rotated, route_index, phase, step]
					var centers := check_rein_sample(player, horse, reins, 1.0 / 60.0, context)
					if centers.size() != 7: continue
					var deflection := rein_local_deflection(horse, centers)
					check(deflection.length() <= .23, context + ": cosmetic left-rein bend exceeds 23 cm")
					if route_index != 0 or step in [0, 64]:
						check(deflection.length() < .00001, context + ": correction leaked outside the front transition or persisted at a phase endpoint")
					elif step == 32:
						check(deflection.length() > .01, context + ": front transition has no left-rein clearance correction")
					if step > 0:
						# The .30-.50 rise stays below 28 mm per 1/64 sample at the 23 cm envelope.
						check(deflection.distance_to(previous_deflection) < .028, context + ": left-rein correction snaps between samples")
						# Bit/bend/midpoint movement is independently bounded. Hand/saddle
						# endpoints can have large target changes at RIDING or on a
						# weapon switch; check_rein_sample verifies their exact native
						# exponential trajectory instead of imposing a new speed cap.
						for point in [0, 1, 2, 4, 5]:
							check(centers[point].distance_to(previous[point]) < .028, context + ": rein bit/bend/midpoint centerline has a discontinuity")
						if step in [1, 64]: check(deflection.distance_to(previous_deflection) < .003, context + ": rein correction has a non-smooth phase boundary")
					if route_index == 0:
						var sample_index := (0 if phase == PlayerRiding.Phase.MOUNTING else 65) + step
						if rotated == 0: front_profile.append(deflection)
						else: check(deflection.distance_to(front_profile[sample_index]) < .00002, context + ": correction is camera/world-local rather than horse-body-local")
					previous = centers
					previous_deflection = deflection
				# Repeated phase-end updates must leave the added bend at rest while
				# the usual hand/saddle endpoint smoothing continues unchanged.
				for settle in 3:
					var settled := check_rein_sample(player, horse, reins, 1.0 / 60.0, "reins phase-end settle%d" % settle)
					if settled.size() == 7: check(rein_local_deflection(horse, settled).length() < .00001, "Rein bend pops after transition completion")
			check(test_riding.phase == PlayerRiding.Phase.NONE and test_riding.horse == null and horse.current_rider == null, "Rein test did not finish the native dismount lifecycle")
	# Exercise free-hand versus saddle endpoints after rapid equipment changes,
	# including an aiming bow, without any transition bend correction.
	test_riding.mount_now(horse)
	for mode in 12:
		player.weapon = PlayerCharacter.Weapon.SWORD if mode % 3 == 0 else PlayerCharacter.Weapon.BOW
		player.sword.reset()
		player.bow.reset()
		if mode % 3 == 2:
			player.bow.state = PlayerBow.State.AIM
			player.bow.draw = .7
		art.pose_preview(&"ride", .7)
		gear.update_equipment(0)
		var centers := check_rein_sample(player, horse, reins, 0.0 if mode % 4 == 0 else 1.0 / 60.0, "seated rapid reins mode%d" % mode)
		if centers.size() == 7: check(rein_local_deflection(horse, centers).length() < .00001, "Seated equipment change retained front-transition correction")
	test_riding._finish(Vector3.ZERO)
	horse.global_transform = saved_horse_frame
	player.riding = saved_riding
	player.bow.reset()
	player.state = PlayerCharacter.State.GROUND
	player.position = Vector3(0, .895, 0)
	player.visual.transform = Transform3D.IDENTITY

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var horse := Horse.new()
	add_child(horse)
	freeze(horse)
	for frame in 90: horse._pose(1.0 / 60.0)
	var player := PlayerCharacter.new()
	add_child(player)
	freeze(player)
	player.position = Vector3(0, .895, 0)
	var gear := player.visual.get_node("WeaponArt") as WeaponArt
	var art := player.visual.get_node("TravelerArt") as TravelerArt
	gear.auto_lod = false
	art.auto_lod = false
	var original_shape := player._shape
	var original_actions := player.actions
	var original_sword := player.sword
	var original_bow := player.bow
	for lod in [0, 1, 2, 0]:
		art.set_lod(lod)
		gear.set_lod(lod)
		check_imported_suspension_rings(gear, lod)
		check(gear.quiver_arrows.size() == 3, "Quiver did not retain three real arrow assets at LOD%d" % lod)
		for spare in gear.quiver_arrows:
			check(spare.get_parent() == gear.quiver, "Spare arrow does not inherit the quiver attachment")
			var tip := spare.transform * Vector3(0, 0, -.80)
			check(tip.y > -.31 and tip.y < -.20, "Spare arrow tip pierces the quiver bottom or floats too high")
			check(spare.position.y > .50 and spare.position.y < .56, "Quiver feathers do not clear its mouth")
			check(absf(tip.x) < .04 and absf(tip.z) < .04, "Spare arrow tip escapes the quiver wall")
		for mode in [&"idle", &"climb"]:
			player.state = PlayerCharacter.State.CLIMB if mode == &"climb" else PlayerCharacter.State.GROUND
			player.weapon = PlayerCharacter.Weapon.SWORD
			player.sword.reset()
			art.pose_preview(mode, .7)
			gear.update_equipment(0)
			var sheath_frame := gear.scabbard.transform
			check_suspension(gear, "LOD%d %s" % [lod, mode])
			check(gear.sword.visible == (mode == &"idle") and gear.stored_sword.visible == (mode == &"climb"), "Sword/scabbard visibility is wrong while standing or climbing")
			check(gear.stored_bow.visible and gear.stored_string_top.visible and gear.stored_string_bottom.visible, "Stored bow lost its own string")
			var bow_frame := gear.stored_bow.transform
			var quiver_frame := gear.quiver.transform
			player.visual.rotation = Vector3(.35, 1.1, -.18)
			gear.update_equipment(0)
			check(gear.scabbard.transform.is_equal_approx(sheath_frame) and gear.stored_bow.transform.is_equal_approx(bow_frame) and gear.quiver.transform.is_equal_approx(quiver_frame), "A stored mount uses a camera/world-axis correction")
			check_suspension(gear, "LOD%d rotated %s" % [lod, mode])
			player.visual.transform = Transform3D.IDENTITY
		player.state = PlayerCharacter.State.GROUND
		player.weapon = PlayerCharacter.Weapon.BOW
		for draw in [0.0, .35, 1.0]:
			player.bow.state = PlayerBow.State.AIM
			player.bow.draw = draw
			player.bow.aim_dir = Vector3(0, .12, -1).normalized()
			player.actions.view_basis = Basis.looking_at(player.bow.aim_dir)
			art.pose_preview(&"idle", .7)
			gear.update_equipment(0)
			check_suspension(gear, "LOD%d bow draw %.2f" % [lod, draw])
			check(gear.stored_sword.visible and not gear.sword.visible, "Sword is not sheathed while using the bow")
			check(gear.arrow.global_position.distance_to(player.bow.bow_point(player)) < .0001, "Held nock no longer equals the physical launch point")
			check((-gear.arrow.global_basis.z).dot(player.bow.aim_dir) > .99999, "Held arrow points away from gameplay aim")
			check(art._string_contact.global_position.distance_to(gear.arrow.global_position) < .001, "Draw fingers do not hook the actual string nock")
			check((-art._wrists[1].global_basis.y).dot((art._wrists[1].global_position - art._forearms[1].global_position).normalized()) > .9999, "Drawing wrist bends away from forearm")
			check(float(gear.hand_errors[0]) < .04 and float(gear.hand_errors[1]) < .04, "Drawn weapon left its hand: %s" % [gear.hand_errors])
			check(not gear.stored_bow.visible and not gear.stored_string_top.visible and not gear.stored_string_bottom.visible, "Stored bow string remains after equipping")
		for cycle in 4: check_transition_cycle(player, art, gear, horse, lod, cycle)
		check(player._shape == original_shape and player.actions == original_actions and player.sword == original_sword and player.bow == original_bow, "Cosmetic mount work replaced native collision/actions/combat")
		check(gear.find_children("*", "CollisionObject3D", true, false).is_empty(), "Weapon mounts introduced collision")
	check_rein_transitions(player, art, gear, horse)
	player.free()
	horse.free()
	print("WEAPON_MOUNTS: %d failures; %d checks; LOD0/1/2/0, hip straps/loops/endpoints, empty sheath, rotation, climb, 16 four-direction mount/dismount cycles at 33 samples each with rapid switches, spare arrows, unchanged bow contacts, body-local rein continuity/endpoints and released-rider dismounts" % [failures, checks])
	get_tree().quit(1 if failures else 0)
