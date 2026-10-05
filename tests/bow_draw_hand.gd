extends Node3D
## The imported split-finger string hook and neutral wrist follow actual nock.
var failures := 0
var checks := 0
var max_contact := 0.0
var min_wrist_dot := 1.0
var min_surface_wrist_dot := 1.0
var max_finger_gap := 0.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func freeze(node: Node) -> void:
	node.set_process(false); node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func finger_gaps(art: TravelerArt, gear: WeaponArt) -> Array:
	var mesh := art._draw_hand.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var morphs := mesh.surface_get_blend_shape_arrays(0)
	var gaps := [INF, INF, INF]
	var centers := [-.020, .013, .031]
	var nock := gear.arrow.global_position
	var ends := [gear.bow.to_global(gear._top + Vector3(0,-.014,.06999) * gear.draw_value), gear.bow.to_global(gear._bottom + Vector3(0,.014,.06999) * gear.draw_value)]
	for i in base.size():
		if base[i].y > -.077: continue
		var point := base[i]
		for shape in morphs.size():
			var weight := art._draw_hand.get_blend_shape_value(shape)
			var values: PackedVector3Array = morphs[shape][Mesh.ARRAY_VERTEX]
			point += (values[i] - base[i] if mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else values[i]) * weight
		point = art._draw_hand.to_global(point)
		for finger in 3:
			if absf(base[i].z - centers[finger]) < .006:
				var near := Geometry3D.get_closest_point_to_segment(point, nock, ends[0 if finger == 0 else 1])
				gaps[finger] = minf(gaps[finger], point.distance_to(near))
	return gaps

func _ready() -> void:
	InputSetup.ensure_defaults(); Sfx.enabled = false; Fx.enabled = false
	var horse := Horse.new(); add_child(horse); freeze(horse)
	for frame in 90: horse._pose(1.0 / 60.0)
	var p := PlayerCharacter.new(); add_child(p); freeze(p)
	var art := p.visual.get_node("TravelerArt") as TravelerArt
	var gear := p.visual.get_node("WeaponArt") as WeaponArt
	art.auto_lod = false; gear.auto_lod = false
	for riding in [false, true]:
		for slope in [Vector3.ZERO, Vector3(.15, .30, -.12)]:
			horse.rotation = slope
			if riding: p.riding.mount_now(horse)
			else:
				p.riding.phase = PlayerRiding.Phase.NONE; p.state = PlayerCharacter.State.GROUND
				p.position = Vector3(0,.895,0); p.visual.transform = Transform3D.IDENTITY
			for lod in 3:
				art.set_lod(lod); gear.set_lod(lod)
				check(art._draw_hand != null and art._string_contact != null, "LOD%d missing authored drawing hand/contact" % lod)
				if not art._draw_hand or not art._string_contact: continue
				check(art._draw_hand.find_blend_shape_by_name("ReleaseOpen") >= 0, "LOD%d lost relaxed finger release" % lod)
				for yaw in [-1.2, -.6, 0.0, .6, 1.2]:
					for pitch in [-.65, 0.0, .65]:
						p.bow.aim_dir = Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch) * Vector3.FORWARD
						p.actions.view_basis = Basis.looking_at(p.bow.aim_dir)
						for draw in [0.0, .35, 1.0]:
							p.weapon = PlayerCharacter.Weapon.BOW; p.bow.state = PlayerBow.State.AIM; p.bow.draw = draw
							art.pose_preview(&"ride" if riding else &"idle", .7)
							var physical := p.bow.bow_point(p)
							var root_before := p.global_transform
							gear.update_equipment(0); art.update_surface_pose()
							var context := "riding=%s slope=%s LOD%d yaw%.2f pitch%.2f draw%.2f" % [riding,slope,lod,yaw,pitch,draw]
							var contact := art._string_contact.global_position.distance_to(physical)
							max_contact = maxf(max_contact,contact)
							check(contact < .001, context+": hook does not touch string: %.5f" % contact)
							var wrist_dot := (-art._wrists[1].global_basis.y).dot((art._wrists[1].global_position-art._forearms[1].global_position).normalized())
							min_wrist_dot = minf(min_wrist_dot,wrist_dot)
							check(wrist_dot > .9999, context+": wrist bends independently of forearm")
							check(gear.arrow.global_position.distance_to(physical) < .00001 and (-gear.arrow.global_basis.z).dot(p.bow.aim_dir) > .99999, context+": visual/physical arrow diverged")
							check(p.global_transform == root_before, context+": pose moved gameplay root")
							check(art._draw_hand.visible and not art._closed_right_hand.visible, context+": overlapping hands")
							check(not art.bow_string_fit_clamped, context+": finger fit exceeded authored bounds")
							for gap in finger_gaps(art, gear):
								max_finger_gap = maxf(max_finger_gap, gap)
								check(gap < .003, context+": drawing finger misses actual string by %.4fm" % gap)
							check(art._wrists[1].global_basis.is_finite() and absf(art._wrists[1].global_basis.determinant()-1)<.0001, context+": invalid wrist basis")
							var report := art.surface_pose_report()
							check(report.get("active",false), context+": inactive cosmetic skin")
							if report.get("active",false):
								var skin := art._surface_pose.skeleton
								var elbow: Vector3 = skin.to_global(report.sides[1].elbow)
								var surface_dot := (-art._wrists[1].global_basis.y).dot((art._wrists[1].global_position-elbow).normalized())
								min_surface_wrist_dot = minf(min_surface_wrist_dot,surface_dot)
								check(surface_dot > .94, context+": visible forearm/wrist misaligned %.4f" % surface_dot)
				# Release opens fingers, follows through, then returns to existing carry.
				p.bow.aim_dir = Vector3.FORWARD; p.actions.view_basis = Basis.IDENTITY
				for state in [PlayerBow.State.RELEASE, PlayerBow.State.RECOVERY, PlayerBow.State.IDLE]:
					p.bow.state = state; p.bow.state_time = .075 if state == PlayerBow.State.RELEASE else .40
					gear.update_equipment(0)
					check(art._draw_hand.visible == (state == PlayerBow.State.RELEASE), "Release/carry hand visibility incorrect")
					if riding and state == PlayerBow.State.RELEASE:
						var reins := horse.get_node("AgroReins") as AgroReins
						reins.update_reins(1.0)
						for side in 2:
							var saddle := horse.to_local(horse.body_transform() * Vector3(-.21 if side == 0 else .21,.47,-.27))
							check(reins._ends[side].distance_to(saddle) < .0001, "Reins follow drawing fingers during release")
					if state == PlayerBow.State.RELEASE:
						check(art._draw_hand.get_blend_shape_value(art._draw_hand.find_blend_shape_by_name("ReleaseOpen")) > .99, "Fingers do not release string")
				p.weapon = PlayerCharacter.Weapon.SWORD; gear.update_equipment(0)
				check(not art._draw_hand.visible and art._closed_right_hand.visible, "Sword did not restore closed grip")
	p.free(); horse.free()
	print("BOW_DRAW_HAND: %d failures; %d checks; max_contact=%.7f min_wrist_dot=%.7f min_surface_wrist_dot=%.7f max_finger_gap=%.7f" % [failures,checks,max_contact,min_wrist_dot,min_surface_wrist_dot,max_finger_gap])
	get_tree().quit(1 if failures else 0)
