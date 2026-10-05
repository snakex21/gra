extends SceneTree
## Export actual production colossus render adapters, effective materials, and transforms.
## Run with --headless --path CHECKOUT --script ABSOLUTE_SCRIPT -- OUT before|after COMMIT.
var output: String
var variant: String
var baseline_commit: String
var world: Node3D
var records: Array = []
var source_hashes := {}

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

func material_info(mat: Material) -> Dictionary:
	assert(mat is StandardMaterial3D, "Expected production StandardMaterial3D")
	var m := mat as StandardMaterial3D
	track(m.resource_path)
	var result := {"name": m.resource_name, "source": m.resource_path, "albedo": [m.albedo_color.r,m.albedo_color.g,m.albedo_color.b,m.albedo_color.a], "roughness": m.roughness, "metallic": m.metallic, "normal_enabled": m.normal_enabled, "normal_scale": m.normal_scale, "roughness_texture_channel": m.roughness_texture_channel, "metallic_texture_channel": m.metallic_texture_channel, "emission_enabled": m.emission_enabled, "emission": [m.emission.r,m.emission.g,m.emission.b], "emission_energy_multiplier": m.emission_energy_multiplier, "cull_mode": m.cull_mode, "transparency": m.transparency, "textures": {}}
	for channel in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS,BaseMaterial3D.TEXTURE_METALLIC]:
		var texture := m.get_texture(channel)
		if texture:
			track(texture.resource_path)
			var image := texture.get_image()
			assert(image != null and not image.is_empty(), "Texture pixels unavailable")
			result.textures[str(channel)] = {"source": texture.resource_path, "width": image.get_width(), "height": image.get_height(), "format": image.get_format(), "pixels_sha256": digest(image.get_data())}
	return result

func flatten(node: Node, target: Node3D, lod: int) -> void:
	if node.is_queued_for_deletion(): return
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D and node.mesh:
		if node.name in ["LOD0", "LOD1", "LOD2"] and node.name != "LOD%d" % lod: return
		var original := node as MeshInstance3D
		var clone := MeshInstance3D.new()
		clone.name = "Mesh_%03d" % records.size()
		clone.mesh = original.mesh
		clone.transform = original.global_transform
		clone.cast_shadow = original.cast_shadow
		target.add_child(clone)
		clone.owner = target
		track(original.mesh.resource_path)
		var record := {"name": str(clone.name), "role": "sculpture" if str(original.name).begins_with("LOD") else "gameplay_visual", "source": original.mesh.resource_path, "transform": xf(original.global_transform), "surfaces": []}
		for surface in original.mesh.get_surface_count():
			var arrays := original.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var mat := original.get_active_material(surface)
			assert(mat != null)
			clone.set_surface_override_material(surface, mat)
			record.surfaces.append({"vertices": vertices.size(), "triangles": (indices.size() if not indices.is_empty() else vertices.size()) / 3, "array_sha256": digest(var_to_bytes(arrays)), "material": material_info(mat)})
		records.append(record)
	for child in node.get_children(): flatten(child, target, lod)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func collect_semantics(node: Node, result: Array) -> void:
	if node is WeakPoint:
		var w := node as WeakPoint
		result.append({"kind":"weak_point","name":str(w.name),"position":vec(w.global_position),"state":w.state,"radius":w.radius,"local_point":vec(w.local_point),"segment":str(w.segment.bone_name)})
		# Protected emission is clock-independent. Open pulse is frozen at the
		# actual _ready() material state to avoid wall-clock drift between pairs.
		if w.state == WeakPoint.State.PROTECTED: w._update_visual()
	for child in node.get_children(): collect_semantics(child,result)

func capture(subject: String, lod: int) -> void:
	source_hashes = {}
	for path in ["src/colossus/colossus_art_v3.gd","src/colossus/colossus.gd","src/colossus/body_segment.gd","src/world/arena_art.gd","src/combat/weak_point.gd","src/combat/armor_plate.gd","assets/colossi_v3_manifest.json","art/scripts/art_asset.gd","src/colossus/greybox/humanoid_boss.gd","src/colossus/greybox/greybox_humanoid.gd","src/colossus/"+subject+"/"+subject+".gd"]: track("res://"+path)
	var c: Colossus
	match subject:
		"valus": c = Valus.new()
		"gaius": c = Gaius.new()
		"pelagia": c = Pelagia.new()
	assert(c != null)
	c.name = subject.capitalize()
	world.add_child(c)
	freeze(c)
	# Follow the same production dressing stack as GameWorld.
	if c is Valus: ArenaArt.dress_valus(c)
	else: ArenaArt.skin_colossus(c)
	ArenaArt.dress_colossus_v3(c,StringName(subject))
	assert(c.has_meta(&"colossi_v3_profile"))
	freeze(c)
	c.skeleton.force_update_all_bone_transforms()
	c._sync_segments()
	await physics_frame
	await process_frame
	var semantics: Array = []
	collect_semantics(c,semantics)
	assert(not semantics.is_empty())
	assert(float(semantics[0].position[1]) > (15.0 if subject != "pelagia" else 5.0), "Segment transforms did not reach the actual physics-synced pose")
	var snapshot := Node3D.new()
	snapshot.name = "ColossusSnapshot"
	root.add_child(snapshot)
	records = []
	flatten(c,snapshot,lod)
	assert(records.size() > 0)
	var id := "%s_lod%d_%s" % [subject,lod,variant]
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	assert(gltf.append_from_scene(snapshot,state) == OK,"GLTF export failed")
	assert(gltf.write_to_filesystem(state,output.path_join(id+".glb")) == OK,"GLB write failed")
	var document := {"subject":subject,"lod":lod,"variant":variant,"baseline_commit":baseline_commit,"project_path":ProjectSettings.globalize_path("res://"),"meshes":records,"semantics":semantics,"source_sha256s":source_hashes.duplicate(),"pose":"production ready/rest skeleton; frozen before physics","preview_note":"Blender Cycles CPU preview of actual Godot-loaded production sculpture, effective materials, transforms and weak-point visuals. Open emission frozen at actual ready value; protected visuals updated by production helper. No reconstructed geometry, runtime GPU or performance claim."}
	var file := FileAccess.open(output.path_join(id+".json"),FileAccess.WRITE)
	assert(file)
	file.store_string(JSON.stringify(document,"\t"))
	file.close()
	print("COLOSSUS_EXPORT_SCENE_OK ",id," meshes=",records.size())
	snapshot.free()
	c.free()

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
	var subjects: Array = [args[3]] if args.size() == 5 else ["valus","gaius","pelagia"]
	for subject in subjects:
		if args.size() == 5: await capture(subject,int(args[4]))
		else:
			for lod in 3: await capture(subject,lod)
	world.free()
	print("COLOSSUS_EXPORT_OK variant=",variant," scenes=",1 if args.size() == 5 else 9)
	quit()
