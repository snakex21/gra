extends SceneTree
## Export loaded production render adapters, not a re-created character.
## Run with --headless --path CHECKOUT --script ABSOLUTE_SCRIPT -- OUT before|after COMMIT.
const SkinSnapshotBaker = preload("res://tools/art/skin_snapshot_baker.gd")
var capture_recenter_delta := Vector3.ZERO
var capture_recenter_transform := Transform3D.IDENTITY
var output: String
var variant: String
var baseline_commit: String
var world: Node3D
var records: Array = []
var source_hashes := {}
var capture_materials := {}
var diagnostic_logical_elbow_pole := false

func _initialize() -> void:
	call_deferred("run")

func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func track(path: String) -> void:
	path = path.get_slice("::", 0)
	if path.begins_with("res://") and FileAccess.file_exists(path):
		source_hashes[path] = FileAccess.get_sha256(path)

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func xf(t: Transform3D) -> Array:
	return [vec(t.basis.x), vec(t.basis.y), vec(t.basis.z), vec(t.origin)]

func json_data(value: Variant) -> Variant:
	if value is Vector3: return vec(value)
	if value is Transform3D: return xf(value)
	if value is Array:
		var array: Array = []
		for item in value: array.append(json_data(item))
		return array
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)] = json_data(value[key])
		return result
	return value

func rigid_anchor_info(player: PlayerCharacter) -> Dictionary:
	var art := player.visual.get_node("TravelerArt") as TravelerArt
	var result := {"player_world":xf(player.global_transform),"visual_world":xf(player.visual.global_transform),"capsule_radius":player._shape.radius,"capsule_height":player._shape.height}
	for side in 2:
		for pair in [["shoulder",player.visual._arms[side]],["elbow",art._forearms[side]],["wrist",art._wrists[side]],["grip",art._grips[side]],["hip",art._legs[side]],["knee",art._knees[side]],["ankle",art._ankles[side]]]:
			result[pair[0]+"_"+str(side)] = xf((pair[1] as Node3D).global_transform)
	return result

func horse_pose_info(horse: Horse) -> Dictionary:
	if horse == null: return {}
	var result := {"world":xf(horse.global_transform),"skeleton_world":xf(horse.skeleton.global_transform),"bones":[]}
	for index in horse.skeleton.get_bone_count():
		result.bones.append({"name":str(horse.skeleton.get_bone_name(index)),"parent":horse.skeleton.get_bone_parent(index),"rest":xf(horse.skeleton.get_bone_rest(index)),"pose":xf(horse.skeleton.get_bone_pose(index)),"global_pose":xf(horse.skeleton.get_bone_global_pose(index))})
	return result

func material_info(mat: Material) -> Dictionary:
	assert(mat is StandardMaterial3D, "Expected production StandardMaterial3D")
	var m := mat as StandardMaterial3D
	track(m.resource_path)
	var result := {"name": m.resource_name, "source": m.resource_path, "albedo": [m.albedo_color.r,m.albedo_color.g,m.albedo_color.b,m.albedo_color.a], "metallic_specular": m.metallic_specular, "roughness": m.roughness, "metallic": m.metallic, "normal_enabled": m.normal_enabled, "normal_scale": m.normal_scale, "cull_mode": m.cull_mode, "transparency": m.transparency, "textures": {}}
	for channel in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS,BaseMaterial3D.TEXTURE_METALLIC]:
		var texture := m.get_texture(channel)
		if texture:
			track(texture.resource_path)
			var image := texture.get_image()
			assert(image != null and not image.is_empty(), "Texture pixels unavailable")
			result.textures[str(channel)] = {"source": texture.resource_path, "width": image.get_width(), "height": image.get_height(), "format": image.get_format(), "pixels_sha256": digest(image.get_data())}
	return result

func flatten(node: Node, target: Node3D, lod: int) -> bool:
	if node.is_queued_for_deletion(): return true
	if node is Node3D and not node.is_visible_in_tree(): return true
	if node is MeshInstance3D and node.mesh:
		if node.get_parent().name in ["AgroArtV3","AgroSkin"] and node.name != "LOD%d" % lod: return true
		var original := node as MeshInstance3D
		var baked := SkinSnapshotBaker.bake(original)
		if not baked.ok:
			push_error("CHARACTER_EXPORT_SKIN_FAILURE: " + baked.error)
			return false
		var clone := MeshInstance3D.new()
		clone.name = "Mesh_%03d_%s" % [records.size(), original.name]
		clone.mesh = baked.mesh
		clone.skin = null
		clone.skeleton = NodePath("")
		clone.transform = original.global_transform
		clone.cast_shadow = original.cast_shadow
		target.add_child(clone)
		clone.owner = target
		track(original.mesh.resource_path)
		var record := {"name": str(clone.name), "source": original.mesh.resource_path, "transform": xf(original.global_transform), "skin_snapshot": baked.proof, "surfaces": []}
		if baked.proof.skinned: track(baked.proof.skin_source)
		for surface in original.mesh.get_surface_count():
			var arrays := clone.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var mat := original.get_active_material(surface)
			assert(mat != null)
			# One private material per original active resource across this snapshot.
			# Avoid suffix-renamed duplicate skin materials and preserve scalar transport.
			var material_id := mat.get_instance_id()
			if not capture_materials.has(material_id): capture_materials[material_id] = mat.duplicate(true)
			clone.mesh.surface_set_material(surface, capture_materials[material_id])
			clone.set_surface_override_material(surface, capture_materials[material_id])
			record.surfaces.append({"vertices": vertices.size(), "triangles": (indices.size() if not indices.is_empty() else vertices.size()) / 3, "array_sha256": digest(var_to_bytes(arrays)), "material": material_info(mat)})
		records.append(record)
	for child in node.get_children():
		if not flatten(child, target, lod): return false
	return true

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func capture(subject: String, lod: int) -> bool:
	source_hashes = {}
	track(get_script().resource_path)
	capture_materials.clear()
	for path in ["tools/art/export_character_preview.gd","tools/art/skin_snapshot_baker.gd","src/player/player_character.gd","src/player/player_visual.gd","src/player/traveler_art.gd","src/player/traveler_surface_pose.gd","src/player/player_riding.gd","src/player/weapon_art.gd","src/horse/horse.gd","src/horse/agro_art.gd","src/horse/agro_reins.gd","src/combat/player_bow.gd","art/scripts/traveler_visual_import.gd","models/characters/travelers_v3/traveler_lod0.glb.import","models/characters/travelers_v3/traveler_lod1.glb.import","models/characters/travelers_v3/traveler_lod2.glb.import"]: track("res://" + path)
	var fixture := Node3D.new()
	fixture.name = "Fixture"
	world.add_child(fixture)
	var horse: Horse
	var player: PlayerCharacter
	var surface_report := {"legacy_rigid": true}
	if subject == "agro_stand" or subject.begins_with("rider"):
		horse = Horse.new()
		horse.name = "Agro"
		fixture.add_child(horse)
		freeze(horse)
		# Settle only the production pose integrator to a fixed neutral carriage.
		# No animation reconstruction or custom bone transforms.
		for frame in 360: horse._pose(1.0 / 120.0)
		pose_horse(horse, subject)
	if subject != "agro_stand":
		player = PlayerCharacter.new()
		player.name = "Traveler"
		fixture.add_child(player)
		freeze(player)
		player.position = Vector3(0,.895,0)
		player.visual.transform = Transform3D.IDENTITY
		var art := player.visual.get_node("TravelerArt") as TravelerArt
		art.auto_lod = false
		art.set_lod(lod)
		if diagnostic_logical_elbow_pole and art.has_method("set_surface_logical_elbow_pole"): art.call("set_surface_logical_elbow_pole",true)
		var mode: StringName = &"idle"
		if subject == "traveler_walk": mode = &"walk"
		if subject == "traveler_climb":
			mode = &"climb"
			player.state = PlayerCharacter.State.CLIMB
		if subject.begins_with("rider"):
			if "mount" in subject and not "dismount" in subject:
				player.position = Vector3(-1.15, .895, 0)
				assert(player.riding.try_mount(), "Mount fixture could not start")
				player.state = PlayerCharacter.State.RIDE
				var frames := 9 if "025" in subject else (18 if "050" in subject else 27)
				for frame in frames: player.riding.update(1.0 / 60.0)
			else:
				player.riding.mount_now(horse)
				if "dismount" in subject:
					assert(player.riding.try_dismount(), "Dismount fixture could not start")
					var frames := 10 if "025" in subject else (20 if "050" in subject else 29)
					for frame in frames: player.riding.update(1.0 / 60.0)
			player.visual.update_visual(player, 1.0)
			mode = &"ride"
		art.pose_preview(mode, .7)
		var gear := player.visual.get_node("WeaponArt") as WeaponArt
		gear.auto_lod = false
		gear.set_lod(lod)
		gear.update_equipment(0.0)
		# Cosmetic surface follows the final production limb/weapon IK transforms.
		# A before checkout predating surface skinning has no updater.
		if art.has_method("update_surface_pose"): art.call("update_surface_pose")
		if art.has_method("surface_pose_report"):
			surface_report = art.call("surface_pose_report")
			if not surface_report.get("active", false):
				push_error("CHARACTER_EXPORT_SKIN_FAILURE: cosmetic surface pose is inactive: " + str(surface_report))
				fixture.free()
				return false
		elif player.visual.find_child("Traveler_TunicSurface*", true, false) != null:
			push_error("CHARACTER_EXPORT_SKIN_FAILURE: surface rig has no pose report accessor")
			fixture.free()
			return false
	if horse and horse.has_node("AgroReins"): horse.get_node("AgroReins").update_reins(1.0)
	var snapshot := Node3D.new()
	snapshot.name = "CharacterSnapshot"
	root.add_child(snapshot)
	records = []
	if horse:
		# Traverse both old rigid attachment frames and the continuous AgroSkin
		# under its original Skeleton3D; flatten selects exactly one visible LOD.
		if not flatten(horse, snapshot, lod):
			snapshot.free()
			fixture.free()
			return false
	if player and not flatten(player.visual, snapshot, lod):
		snapshot.free()
		fixture.free()
		return false
	assert(records.size() > 0)
	var id := "%s_lod%d_%s" % [subject,lod,variant]
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	assert(gltf.append_from_scene(snapshot,state) == OK, "GLTF scene export failed")
	assert(gltf.write_to_filesystem(state, output.path_join(id + ".glb")) == OK, "GLB write failed")
	var document := {"subject":subject,"lod":lod,"variant":variant,"baseline_commit":baseline_commit,"project_path":ProjectSettings.globalize_path("res://"),"meshes":records,"source_sha256s":source_hashes.duplicate(),"pose_step":.7,"surface_pose_report":json_data(surface_report),"rigid_anchors":rigid_anchor_info(player) if player else {},"horse_pose_frames":360,"prescribed_horse_pose":subject,"capture_recenter_delta":vec(capture_recenter_delta),"capture_recenter_transform":xf(capture_recenter_transform),"horse_native_pose":horse_pose_info(horse),"player_position":vec(player.global_position) if player else null,"riding":player.is_riding() if player else false,"preview_note":"Blender Cycles CPU preview of Godot-loaded runtime adapters. Loaded mesh arrays with current Skeleton3D/Skin deformation CPU-baked using Godot 4.6 renderer-equivalent linear blending; full source/baked proof per mesh, original global transforms, active materials and texture pixels. Frozen cosmetic pose helper; horse production pose integrator and real rider saddle mount. No GPU/runtime-render or animation-performance claim."}
	var file := FileAccess.open(output.path_join(id + ".json"),FileAccess.WRITE)
	assert(file)
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	print("CHARACTER_EXPORT_SCENE_OK ",id," meshes=",records.size())
	snapshot.free()
	fixture.free()
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [3,5]:
		push_error("Expected OUT before|after BASELINE_COMMIT [SUBJECT LOD]")
		quit(2)
		return
	output = args[0]
	variant = args[1]
	baseline_commit = args[2]
	assert(variant in ["before","after"])
	DirAccess.make_dir_recursive_absolute(output)
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	world = Node3D.new()
	root.add_child(world)
	# Physics support only; deliberately absent from exported character meshes.
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20,.2,20)
	shape.shape = box
	shape.position.y = -.1
	ground.add_child(shape)
	world.add_child(ground)
	await physics_frame
	await physics_frame
	for path in ["tools/art/export_character_preview.gd","tools/art/skin_snapshot_baker.gd","src/player/player_character.gd","src/player/player_visual.gd","src/player/traveler_art.gd","src/player/traveler_surface_pose.gd","src/player/player_riding.gd","src/player/weapon_art.gd","src/horse/horse.gd","src/horse/agro_art.gd","src/horse/agro_reins.gd","src/combat/player_bow.gd","art/scripts/traveler_visual_import.gd","models/characters/travelers_v3/traveler_lod0.glb.import","models/characters/travelers_v3/traveler_lod1.glb.import","models/characters/travelers_v3/traveler_lod2.glb.import"]: track("res://" + path)
	var subjects: Array = [args[3]] if args.size() == 5 else ["traveler_idle","traveler_walk","traveler_climb","agro_stand","rider"]
	for subject in subjects:
		var lods: Array = [int(args[4])] if args.size() == 5 else [0, 1, 2]
		for lod in lods:
			if not capture(subject,lod):
				world.free()
				quit(1)
				return
	world.free()
	print("CHARACTER_EXPORT_OK variant=",variant," scenes=",1 if args.size() == 5 else 15)
	quit()

## Prescribed trajectories use production gait planning and pose integration.
## They exercise pose/contact extremes, not live-controller pathfinding or FPS.
func pose_horse(horse: Horse, label: String) -> void:
	if label in ["rider", "agro_stand"] or "mount" in label: return
	var gait := 1
	if "trot" in label: gait = 2
	if "gallop" in label: gait = 3
	var desired_phase := .25
	if "phase050" in label: desired_phase = .50
	if "phase075" in label: desired_phase = .75
	horse.controller.gait = gait
	horse.controller.gait_level = gait
	horse.controller.speed = HorseController.GAIT_SPEED[gait]
	horse._prev_speed = horse.controller.speed
	var dt := 1.0 / 120.0
	for tick in 2400:
		var previous := horse.gait_planner.clock
		horse.controller.yaw_rate = .6 if "turn" in label else 0.0
		horse.controller.yaw += horse.controller.yaw_rate * dt
		horse.controller.steer_dir = horse.controller.forward().rotated(Vector3.UP, 1.0 if "turn" in label else 0.0)
		horse.controller.position += horse.controller.forward() * horse.controller.speed * dt
		horse.global_transform = Transform3D(horse.controller.body_basis(), horse.controller.position)
		horse.gait_planner.update(horse.controller, dt, world.get_world_3d().direct_space_state)
		if "slope" in label:
			# Synthetic 12 degree uphill contact field, explicitly not live terrain.
			for leg in horse.gait_planner.legs:
				leg.foot_pos.y = -tan(deg_to_rad(12.0)) * (leg.foot_pos.z - horse.global_position.z)
				leg.foot_normal = Vector3(0,1,tan(deg_to_rad(12.0))).normalized()
		horse._pose(dt)
		if tick > 360 and previous < desired_phase and horse.gait_planner.clock >= desired_phase: break
	# Recenter the complete production pose for identical cameras. Vis_* nodes
	# are top_level in production, so moving Horse alone would strand the hooves.
	capture_recenter_delta = -horse.global_position
	capture_recenter_transform = horse.global_transform.affine_inverse()
	horse.global_transform = Transform3D.IDENTITY
	for attachment in horse._visuals:
		var node := attachment[0] as Node3D
		var expected := horse.skeleton.global_transform * horse.skeleton.get_bone_global_pose(attachment[1])
		node.global_transform = expected
		assert(node.global_transform.is_equal_approx(expected), "Rigid hoof did not follow recentered skeleton")
	for i in 4:
		if horse.gait_planner.legs[i].is_planted():
			assert(horse.sole_world(i).distance_to(capture_recenter_transform * horse.gait_planner.legs[i].foot_pos) < .005, "Recentered planted hoof differs from production target")
