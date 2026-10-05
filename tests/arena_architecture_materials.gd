extends SceneTree
## Independent, CPU-only contract for the layout-5 architecture material pass.
## Run: godot --headless --path . --script tests/arena_architecture_materials.gd
## The authored manifests below never call the production selector to decide
## which geometry is allowed to change. No GPU/FPS/residency claims are made.
const EXPECTED := {"phoenix":8,"spider":6,"dormin":10,"barba":9,"kuromori":68,"argus":13,"gaius":15,"dirge":5,"celosia_cenobia":3,"malus":21}
const TILE_METRES := {"phoenix":10.0,"spider":10.0,"dormin":12.0,"barba":8.0,"kuromori":8.0,"argus":10.0,"gaius":8.0,"dirge":10.0,"celosia_cenobia":8.0,"malus":10.0}
const META := &"arena_architecture_material"
const MECHANICS := [&"HingedGalleryRamp",&"StompCounterweight",&"GalleryBridge",&"JumpToGuardian"]
var failures := 0
var checks := 0
var report := {"arenas":{},"legacy_layouts":[],"gpu_fps_measured":false,"scope":"Headless CPU queue timings, exact target mapping, geometry/physics/resource identity, mechanism behavior and texture source budgets; no GPU, FPS, draw-call or residency measurement"}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func meshes(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: MeshInstance3D in parent.find_children("*","MeshInstance3D",true,false):
		result.append(node)
	return result

func coated(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in meshes(parent):
		if node.has_meta(META): result.append(node)
	return result

func value_signature(value: Variant, depth := 0) -> Variant:
	if value is Texture2D:
		return [value.get_class(),value.resource_path,value.get_size()]
	if value is Resource:
		if depth >= 4: return [value.get_class(),value.resource_path]
		var rows := []
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE and not String(property.name).begins_with("resource_"):
				rows.append([property.name,value_signature(value.get(property.name),depth+1)])
		return [value.get_class(),value.resource_path,rows]
	if value is Array:
		var rows := []
		for item: Variant in value: rows.append(value_signature(item,depth+1))
		return rows
	return value

func geometry_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		var surfaces := []
		for surface in node.mesh.get_surface_count():
			var primitive: int = node.mesh.surface_get_primitive_type(surface) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			surfaces.append([node.mesh.get_class(),primitive,node.mesh.surface_get_arrays(surface)])
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.visible,node.layers,surfaces])
	return var_to_bytes(rows)

func physics_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node: CollisionShape3D in parent.find_children("*","CollisionShape3D",true,false):
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.disabled,node.get_parent().collision_layer,node.get_parent().collision_mask,value_signature(node.shape)])
	return var_to_bytes(rows)

func identity_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node: Node in parent.find_children("*","",true,false):
		rows.append([node.get_instance_id(),node.get_parent().get_instance_id(),node.get_class()])
		if node is Node3D: rows.append(node.transform)
		if node is MeshInstance3D:
			var surfaces := []
			for surface in node.mesh.get_surface_count():
				var material: Material = node.mesh.surface_get_material(surface)
				var override: Material = node.get_surface_override_material(surface)
				surfaces.append([material.get_instance_id() if material else 0,override.get_instance_id() if override else 0])
			rows.append([node.mesh.get_instance_id(),node.mesh.get_rid(),surfaces])
		if node is CollisionShape3D: rows.append([node.shape.get_instance_id(),node.shape.get_rid()])
	return var_to_bytes(rows)

func appearance_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		rows.append([value_signature(node.material_override),node.get_meta(META,"")])
	return var_to_bytes(rows)

func snapshot(parent: Node3D) -> Dictionary:
	check(not meshes(parent).is_empty(),"Geometry snapshot fixture must contain meshes")
	var geometry := geometry_bytes(parent)
	check(geometry.size()>100,"Geometry snapshot is empty or incomplete")
	return {"geometry":geometry,"physics":physics_bytes(parent),"identity":identity_bytes(parent),"nodes":parent.find_children("*","",true,false).size(),"colliders":parent.find_children("*","CollisionShape3D",true,false).size(),"mesh_count":meshes(parent).size(),"root_transform":parent.transform}

func check_unchanged(parent: Node3D, before: Dictionary, label: String) -> void:
	check(geometry_bytes(parent)==before.geometry,"Geometry arrays/transforms/visibility changed: "+label)
	check(physics_bytes(parent)==before.physics,"Collider shapes/transforms/layers changed: "+label)
	check(identity_bytes(parent)==before.identity,"Tree identity, transforms, mesh/shape objects or surface materials changed: "+label)
	check(parent.find_children("*","",true,false).size()==before.nodes,"Nodes added or removed: "+label)
	check(parent.transform==before.root_transform,"Arena placement changed: "+label)

func authored_manifest(arena: String) -> Array:
	# Records are [hierarchy, position, size, architectural role], transcribed from
	# each authored builder, independently of ArenaArchitectureMaterials.
	var rows := []
	match arena:
		"phoenix":
			for x in [-20.0,20.0]:
				rows.append(["root",Vector3(x,12,-27),Vector3(18,24,3),"stream_back_wall"])
				rows.append(["root",Vector3(x,23.5,-19),Vector3(18,1,19),"stream_cap"])
				for offset in [-8.3,8.3]: rows.append(["root",Vector3(x+offset,8,-19),Vector3(2.2,16,14),"stream_side_wall"])
		"spider":
			for x in [-34.0,34.0]:
				for z in [-35.0,0.0,35.0]: rows.append(["root",Vector3(x,6,z),Vector3(3,12,3),"outer_pillar"])
		"dormin":
			for x in [-40.0,40.0]:
				for z in [-48.0,-23.0,2.0,27.0]: rows.append(["root",Vector3(x,9,z),Vector3(3,18,3),"shrine_pillar"])
			rows.append(["root",Vector3(0,12,-53),Vector3(85,24,3),"shrine_wall"])
			rows.append(["root",Vector3(0,24.3,-53),Vector3(88,1,6),"shrine_cap"])
		"gaius":
			rows = [["root",Vector3(-7,5,62),Vector3(2.5,10,2.5),"entry"],["root",Vector3(7,5,62),Vector3(2.5,10,2.5),"entry"],["root",Vector3(0,10.8,62),Vector3(17,1.6,2.8),"lintel"]]
			for i in range(9):
				var angle := 0.35 + TAU * i / 9.0
				var radius: float = [56.0,60.0,64.0][i % 3]
				var height: float = [4.0,6.5,9.0,11.5][i % 4]
				rows.append(["root",Vector3(cos(angle)*radius,height/2,sin(angle)*radius),Vector3(2.4,height,2.4),"rim_pillar"])
			rows.append(["root",Vector3(28,1,34),Vector3(6,2,3),"fallen_block"])
			rows.append(["root",Vector3(-30,1.2,40),Vector3(4,2.4,4),"fallen_block"])
			rows.append(["root",Vector3(-22,.8,-40),Vector3(5,1.6,3),"fallen_block"])
		"dirge":
			for p in [Vector3(-100,8,0),Vector3(100,8,0)]: rows.append(["root",p,Vector3(6,16,206),"crash_wall"])
			for p in [Vector3(-54,8,100),Vector3(54,8,100)]: rows.append(["root",p,Vector3(86,16,6),"entry_wall"])
			rows.append(["root",Vector3(0,8,-100),Vector3(194,16,6),"back_wall"])
		"celosia_cenobia":
			rows = [["root",Vector3(-20,4.5,5),Vector3(8,1,8),"refuge_roof"],["root",Vector3(-23.5,2,1.5),Vector3(.5,4,.5),"refuge_support"],["root",Vector3(-16.5,2,1.5),Vector3(.5,4,.5),"refuge_support"]]
		"malus":
			for center in [Vector3(0,0,104),Vector3(-11,0,90),Vector3(11,0,69),Vector3(-11,0,48),Vector3(-15,0,22)]:
				rows.append(["root",center+Vector3(0,3.8,0),Vector3(8,1,9),"cover_roof"])
				rows.append(["root",center+Vector3(-4,1.7,3.5),Vector3(.7,3.4,.7),"cover_support"])
				rows.append(["root",center+Vector3(4,1.7,3.5),Vector3(.7,3.4,.7),"cover_support"])
				rows.append(["root",center+Vector3(0,1.7,-4),Vector3(8,3.4,.7),"cover_wall"])
			rows.append(["root",Vector3(-15,3.8,4),Vector3(7,1,38),"final_gallery"])
		"barba":
			rows = [
				["root",Vector3(-32,6,0),Vector3(2,12,78),"wall"],
				["root",Vector3(32,6,0),Vector3(2,12,78),"wall"],
				["root",Vector3(0,6,-39),Vector3(66,12,2),"wall"],
			]
			for pos in [Vector3(-26,8,-32),Vector3(-26,8,0),Vector3(-26,8,30),Vector3(26,8,-32),Vector3(26,8,0),Vector3(26,8,30)]:
				rows.append(["root",pos,Vector3(2.2,16,2.2),"pillar"])
		"kuromori":
			rows = [
				["root",Vector3(0,8,-25),Vector3(54,16,2),"wall"],
				["root",Vector3(-26,8,0),Vector3(2,16,52),"wall"],
				["root",Vector3(26,8,0),Vector3(2,16,52),"wall"],
				["root",Vector3(-16,8,25),Vector3(22,16,2),"wall"],
				["root",Vector3(16,8,25),Vector3(22,16,2),"wall"],
			]
			for y in [3.7,7.7,11.7]:
				rows.append(["root",Vector3(-23,y,0),Vector3(4,.6,50),"gallery"])
				rows.append(["root",Vector3(23,y,0),Vector3(4,.6,50),"gallery"])
				rows.append(["root",Vector3(-17,y,-22),Vector3(14,.6,4),"gallery"])
				rows.append(["root",Vector3(17,y,-22),Vector3(14,.6,4),"gallery"])
				rows.append(["root",Vector3(0,y,22),Vector3(48,.6,4),"gallery"])
			for step in range(1,49):
				rows.append(["root",Vector3(19.6,step/8.0,20.75-step*.75),Vector3(2.7,step/4.0,.8),"visible_stair"])
		"argus":
			for pos in [Vector3(-36,7,-55),Vector3(-36,7,-20),Vector3(-36,7,20),Vector3(36,7,-55),Vector3(36,7,-20),Vector3(36,7,20)]:
				rows.append(["root",pos,Vector3(3,14,3),"outer_pillar"])
			for pos in [Vector3(-20,5.5,-10),Vector3(-20,5.5,-4),Vector3(20,5.5,-10),Vector3(20,5.5,-4)]:
				rows.append(["ruins",pos,Vector3(2.4,11,2.4),"support_pillar"])
			rows.append(["ruins",Vector3(0,8,-24),Vector3(48,16,3),"back_wall"])
			rows.append(["ruins",Vector3(-18,11.5,-7),Vector3(7,1,8),"fixed_gallery"])
			rows.append(["ruins",Vector3(18,11.5,-7),Vector3(7,1,8),"fixed_gallery"])
	return rows

func independent_targets(parent: Node3D, arena: String) -> Dictionary:
	var result := {}
	for spec: Array in authored_manifest(arena):
		var found := []
		for node in meshes(parent):
			var body := node.get_parent()
			if not body is StaticBody3D or not node.mesh is BoxMesh: continue
			var owner_ok: bool = body.get_parent()==parent if spec[0]=="root" else body.get_parent() is ArgusRuins and body.get_parent().get_parent()==parent
			if owner_ok and body.position.is_equal_approx(spec[1]) and node.mesh.size.is_equal_approx(spec[2]): found.append(node)
		check(found.size()==1,"Authored target missing/duplicated: %s/%s/%s"%[arena,spec[3],spec[1]])
		if found.size()==1: result[found[0].get_instance_id()]={"mesh":found[0],"role":spec[3]}
	check(result.size()==EXPECTED[arena],"Independent manifest total changed: "+arena)
	return result

func validate_material(arena: String, material: StandardMaterial3D) -> void:
	check(material!=null,"Missing architecture material: "+arena)
	if material==null: return
	check(material==ArenaArchitectureMaterials.material_for(arena),"Material cache lost identity: "+arena)
	check(material.resource_path=="res://materials/arena_architecture/%s.tres"%arena,"Wrong architecture material provenance: "+arena)
	check(material.uv1_triplanar and not material.uv1_world_triplanar,"Architecture coordinates are not local triplanar: "+arena)
	check(material.uv1_scale.is_equal_approx(Vector3.ONE/TILE_METRES[arena]),"Wrong architecture tile scale: "+arena)
	check(material.normal_enabled and material.normal_scale>0,"Normal relief disabled: "+arena)
	check(not material.heightmap_enabled,"Architecture introduced displacement/parallax: "+arena)
	check(not material.emission_enabled,"Static architecture acquired mechanism emission: "+arena)
	check(material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Architecture became transparent: "+arena)
	check(material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,"Architecture missing filtered mipmaps: "+arena)
	var source_bytes := 0
	for slot in ["albedo","normal","roughness"]:
		var texture: Texture2D = material.get(slot+"_texture")
		check(texture!=null and texture.get_size()==Vector2(512,512),"Missing/non-budget 512px map: "+arena+"/"+slot)
		var path := "res://textures/arena_architecture/%s_%s.png"%[arena,slot]
		if texture: check(texture.resource_path==path,"Wrong texture provenance: "+arena+"/"+slot)
		var file := FileAccess.open(path,FileAccess.READ)
		check(file!=null,"Missing source texture: "+path)
		if file:
			check(file.get_length()<=900000,"Architecture map exceeds source budget: "+path)
			source_bytes += file.get_length()
			file.close()
		var sidecar := FileAccess.get_file_as_string(path+".import")
		check(sidecar.contains("mipmaps/generate=true") and sidecar.contains("compress/mode=2"),"Map import lost mipmaps/compression: "+path)
	check(source_bytes<=900000,"Architecture material source triplet exceeds 900KB: "+arena)
	report.arenas[arena]={"source_png_bytes":source_bytes}

func audit_append(arena: String) -> void:
	var game := GameWorld.new()
	var parent := Node3D.new()
	parent.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(parent)
	parent.transform=Transform3D(Basis(Vector3.UP,.71),Vector3(641,8,-311))
	game._build_arena_ground(StringName(arena),parent)
	# Preserve the prior ground pass, including both Kuromori floors.
	ArenaGroundMaterials.append(parent,arena)
	var expected := independent_targets(parent,arena)
	var before := snapshot(parent)
	var before_appearance := appearance_bytes(parent)
	var old_materials := {}
	var original_resources := {}
	for node in meshes(parent):
		old_materials[node.get_instance_id()]=node.material_override
		if node.material_override:
			original_resources[node.material_override.get_instance_id()]=[node.material_override,var_to_bytes(value_signature(node.material_override))]
	var selected := ArenaArchitectureMaterials._targets(parent,arena)
	check(selected.size()==expected.size(),"Production selector differs from independent manifest: "+arena)
	for node in selected: check(expected.has(node.get_instance_id()),"Production selector admitted unrelated geometry: "+arena)
	# A second planned arena is unloaded before the first cold request starts.
	# Its deferred loader and weak target closures must remain safe to drain.
	var discarded := Node3D.new();discarded.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(discarded)
	game._build_arena_ground(StringName(arena),discarded)
	var discarded_ref: WeakRef = weakref(ArenaArchitectureMaterials._targets(discarded,arena)[0])
	var cold_cancelled := ArenaArt.plan(func() -> void: ArenaArchitectureMaterials.append(discarded,arena))
	check(cold_cancelled.jobs.size()==EXPECTED[arena]+1,"Cold unload did not queue all targets: "+arena)
	discarded.free()
	check(discarded_ref.get_ref()==null,"Cold queue retained an unloaded target: "+arena)
	var job := ArenaArt.plan(func() -> void: ArenaArchitectureMaterials.append(parent,arena))
	check(coated(parent).is_empty() and appearance_bytes(parent)==before_appearance,"Planning eagerly changed materials: "+arena)
	check(job.jobs.size()==EXPECTED[arena]+1,"Expected one load job plus one assignment per target: "+arena)
	check(not cold_cancelled.step(1000,1) and cold_cancelled.cursor==0,"Cold unloaded material load did not yield at threaded request: "+arena)
	check(coated(parent).is_empty(),"Cold threaded request assigned materials early: "+arena)
	check(ArenaArchitectureMaterials._requests.has(arena),"Cold append bypassed threaded loading: "+arena)
	var steps := 1
	var deadline := Time.get_ticks_msec()+15000
	while not job.step(1000,1):
		steps += 1
		if Time.get_ticks_msec()>deadline:
			check(false,"Architecture material queue timed out: "+arena)
			parent.free();game.free();return
		await process_frame
	while not cold_cancelled.step(1000,1):
		if Time.get_ticks_msec()>deadline:
			check(false,"Cold unloaded queue failed to drain: "+arena)
			parent.free();game.free();return
		await process_frame
	check(cold_cancelled.cursor==cold_cancelled.jobs.size(),"Cold unloaded queue retained jobs: "+arena)
	var material := ArenaArchitectureMaterials.material_for(arena)
	validate_material(arena,material)
	var rows := []
	var roles := {}
	for node in meshes(parent):
		var id := node.get_instance_id()
		check(node.has_meta(META)==expected.has(id),"Exact authored mapping violated: "+arena+"/"+str(node.get_parent().position))
		if expected.has(id):
			check(node.material_override==material and node.get_meta(META,"")==arena,"Wrong target assignment: "+arena)
			var role: String = expected[id].role
			roles[role]=int(roles.get(role,0))+1
			rows.append({"body":str(node.get_parent().name),"position":str(node.get_parent().position),"size":str(node.mesh.size),"role":role})
			if role=="visible_stair": check(node.visible and node.get_parent().collision_layer==0,"Kuromori tread visibility/collision changed")
		else:
			check(node.material_override==old_materials[id],"Changed unrelated material identity: "+arena)
	for stored: Array in original_resources.values():
		check(var_to_bytes(value_signature(stored[0]))==stored[1],"Mutated original/shared material resource: "+arena)
	check(coated(parent).size()==EXPECTED[arena],"Wrong coated target total: "+arena)
	ArenaArchitectureMaterials.append(parent,arena)
	for profile in ["low","balanced","high","low","balanced"]:
		GraphicsQuality.apply(parent,profile)
		for node in coated(parent): check(node.material_override==material,"Quality changed architecture material: "+arena)
	check_unchanged(parent,before,arena)
	var second := Node3D.new();second.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(second)
	game._build_arena_ground(StringName(arena),second)
	var warm_began := Time.get_ticks_usec()
	ArenaArchitectureMaterials.append(second,arena)
	var warm_usec := Time.get_ticks_usec()-warm_began
	check(coated(second).size()==EXPECTED[arena],"Second arena lost targets: "+arena)
	for node in coated(second): check(node.material_override==material,"Arena instances duplicate shared material resources: "+arena)
	report.arenas[arena].merge({"target_meshes":coated(parent).size(),"roles":roles,"targets":rows,"total_meshes":meshes(parent).size(),"tile_metres":TILE_METRES[arena],"stream_steps":steps,"max_step_usec":maxi(job.max_step_usec,cold_cancelled.max_step_usec),"cold_unload_max_step_usec":cold_cancelled.max_step_usec,"warm_assignment_usec":warm_usec,"geometry_sha256":digest(before.geometry),"physics_sha256":digest(before.physics),"nodes_before":before.nodes,"nodes_after":parent.find_children("*","",true,false).size(),"added_meshes":meshes(parent).size()-before.mesh_count,"added_colliders":parent.find_children("*","CollisionShape3D",true,false).size()-before.colliders,"exact_resource_identity_preserved":true,"cold_unloaded_queue_checked":true,"rotated_translated_parent_checked":true,"prior_ground_materials_preserved":true})
	second.free();parent.free();game.free()

func baseline_script() -> GDScript:
	var source := FileAccess.get_file_as_string("res://src/game/game_world.gd")
	var hook := "\t\tArenaArchitectureMaterials.append(root, String(kind))\n"
	check(source.count(hook)==1,"Architecture campaign hook must be unique")
	check(source.contains("\tif layout_version == 5:\n\t\tArenaGroundMaterials.append(root, String(kind))\n"+hook),"Architecture hook lost explicit layout-5 gate")
	source=source.replace("class_name GameWorld\n","").replace(hook,"")
	var script := GDScript.new();script.source_code=source
	check(script.reload()==OK,"Uncoated campaign fixture does not compile")
	return script

func audit_campaign() -> void:
	var current := GameWorld.new()
	var baseline: Node3D = baseline_script().new()
	for layout in [1,2,3,4,5]:
		current.layout_version=layout;baseline.layout_version=layout
		for arena: String in EXPECTED:
			var first := Node3D.new();var other := Node3D.new()
			first.process_mode=Node.PROCESS_MODE_DISABLED;other.process_mode=Node.PROCESS_MODE_DISABLED
			root.add_child(first);root.add_child(other)
			current._build_arena(StringName(arena),first);baseline._build_arena(StringName(arena),other)
			check(coated(first).size()==((4 if arena=="gaius" else EXPECTED[arena]) if layout==5 else 0),"Wrong layout coating: %d/%s"%[layout,arena])
			check(coated(other).is_empty(),"Baseline unexpectedly coated: "+arena)
			check(geometry_bytes(first)==geometry_bytes(other),"Campaign hook changed geometry: %d/%s"%[layout,arena])
			check(physics_bytes(first)==physics_bytes(other),"Campaign hook changed physics: %d/%s"%[layout,arena])
			if layout<5: check(appearance_bytes(first)==appearance_bytes(other),"Legacy appearance changed: %d/%s"%[layout,arena])
			else:
				var current_meshes := meshes(first)
				var original_meshes := meshes(other)
				check(current_meshes.size()==original_meshes.size(),"Production art mesh topology changed: "+arena)
				for index in current_meshes.size():
					var mesh := current_meshes[index]
					if mesh.has_meta(META):
						check(mesh.visible,"Hidden replaced greybox was coated: "+arena)
					else:
						check(value_signature(mesh.material_override)==value_signature(original_meshes[index].material_override),"Production replacement/art material changed: "+arena+"/"+str(index))
			first.free();other.free()
		if layout<5: report.legacy_layouts.append(layout)
	current.layout_version=5;current.with_art=false
	for arena: String in EXPECTED:
		var direct := Node3D.new();var staged := Node3D.new()
		root.add_child(direct);root.add_child(staged)
		current._build_arena(StringName(arena),direct)
		current.arenas[StringName(arena)]={"root":staged,"points":{}}
		current._queue_arena(StringName(arena),staged)
		current._build_step()
		check(current.arenas_ready() and current._art_jobs.is_empty(),"Art-off path retained decoration jobs: "+arena)
		check(coated(direct).is_empty() and coated(staged).is_empty(),"Art-off replay acquired architecture materials: "+arena)
		check(geometry_bytes(direct)==geometry_bytes(staged) and physics_bytes(direct)==physics_bytes(staged),"Art-off staged geometry changed: "+arena)
		check(appearance_bytes(direct)==appearance_bytes(staged),"Art-off staged appearance changed: "+arena)
		direct.free();staged.free()
	current.free();baseline.free()
	report.art_off_direct_and_streamed_checked=true

func audit_production_staging() -> void:
	var game := GameWorld.new();game.layout_version=5
	var metrics := {}
	for arena: String in EXPECTED:
		var direct := Node3D.new();var staged := Node3D.new()
		direct.process_mode=Node.PROCESS_MODE_DISABLED;staged.process_mode=Node.PROCESS_MODE_DISABLED
		root.add_child(direct);root.add_child(staged)
		game._build_arena(StringName(arena),direct)
		game.arenas[StringName(arena)]={"root":staged,"points":{}}
		game._queue_arena(StringName(arena),staged);game._build_step()
		check(coated(staged).is_empty(),"Stage zero coated architecture before art: "+arena)
		check(game._pending.size()==1,"Stage zero did not enqueue art: "+arena)
		var steps := 0;var max_usec := 0
		var deadline := Time.get_ticks_msec()+20000
		while not game.arenas_ready():
			var began := Time.get_ticks_usec();game._build_step()
			max_usec=maxi(max_usec,Time.get_ticks_usec()-began);steps+=1
			if steps==2: GraphicsQuality.apply(staged,"low")
			if steps==7: GraphicsQuality.apply(staged,"high")
			if Time.get_ticks_msec()>deadline:
				check(false,"Production architecture staging timed out: "+arena);break
			if steps%20==0: await process_frame
		check(game._art_jobs.is_empty(),"Completed arena retained an art job: "+arena)
		GraphicsQuality.apply(direct,"balanced");GraphicsQuality.apply(staged,"balanced")
		check(coated(staged).size()==(4 if arena=="gaius" else EXPECTED[arena]),"Staging lost assignments: "+arena)
		check(appearance_bytes(direct)==appearance_bytes(staged),"Staged materials differ from direct: "+arena)
		check(geometry_bytes(direct)==geometry_bytes(staged),"Staged geometry differs from direct: "+arena)
		check(physics_bytes(direct)==physics_bytes(staged),"Staged physics differs from direct: "+arena)
		metrics[arena]={"stage1_steps":steps,"max_stage_call_usec":max_usec,"quality_switched_during_staging":true}
		direct.free();staged.free()
	game.free();report.production_staging=metrics

func audit_cancelled_queue() -> void:
	var game := GameWorld.new()
	for arena: String in EXPECTED:
		for midway in [false,true]:
			var parent := Node3D.new();root.add_child(parent)
			game._build_arena_ground(StringName(arena),parent)
			var target_ref: WeakRef = weakref(ArenaArchitectureMaterials._targets(parent,arena)[0])
			var job := ArenaArt.plan(func() -> void: ArenaArchitectureMaterials.append(parent,arena))
			var count := job.jobs.size()
			if midway:
				job.step(1000,1);job.step(1000,1)
				check(coated(parent).size()==1,"Cancellation did not follow exactly one assignment: "+arena)
			parent.free()
			check(target_ref.get_ref()==null,"Queued work retained freed target: "+arena)
			var deadline := Time.get_ticks_msec()+15000
			while not job.step(1000,1):
				if Time.get_ticks_msec()>deadline:
					check(false,"Cancelled architecture queue did not drain: "+arena);game.free();return
				await process_frame
			check(job.cursor==count,"Cancelled queue retained/skipped jobs: "+arena)
	game.free();report.cancelled_before_and_after_first_assignment_checked=true

func audit_production_stop_cleanup() -> void:
	var checkpoints := {}
	for arena: String in EXPECTED:
		for midway in [false,true]:
			var game := GameWorld.new();game.layout_version=5;game.with_input=false;game.save_path=""
			root.add_child(game)
			game.region=Node3D.new();game.add_child(game.region)
			var parent := Node3D.new();game.region.add_child(parent)
			var parent_ref: WeakRef = weakref(parent)
			game.arenas[StringName(arena)]={"root":parent,"points":{}}
			game._queue_arena(StringName(arena),parent);game._build_step()
			if midway: game._build_step()
			checkpoints[arena+("_after_art_step" if midway else "_before_art")]={"pending":game._pending.size(),"art_jobs":game._art_jobs.size()}
			var material := ArenaArchitectureMaterials.material_for(arena)
			game.stop()
			check(game._pending.is_empty() and game._art_jobs.is_empty(),"Stop retained arena queues: "+arena)
			check(game.arenas.is_empty() and game.region==null and parent_ref.get_ref()==null,"Stop retained arena hierarchy: "+arena)
			check(ArenaArchitectureMaterials.material_for(arena)==material,"Stop discarded shared architecture resource: "+arena)
			game.free()
	report.production_stop_checkpoints=checkpoints

func mechanism_state(ruins: ArgusRuins) -> Dictionary:
	var material := ruins._plate_mesh.material_override as StandardMaterial3D
	return {"activated":ruins.activated,"route_open":ruins.route_open,"impacts":ruins.impacts,"weight":ruins.weight,"ramp_transform":ruins.ramp.transform,"emission_enabled":material.emission_enabled,"emission":material.emission,"emission_energy":material.emission_energy_multiplier}

func audit_argus_mechanism() -> void:
	var game := GameWorld.new()
	var coated_arena := Node3D.new();var baseline := Node3D.new()
	coated_arena.process_mode=Node.PROCESS_MODE_DISABLED;baseline.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(coated_arena);root.add_child(baseline)
	coated_arena.transform=Transform3D(Basis(Vector3.UP,.83),Vector3(610,9,-280));baseline.transform=coated_arena.transform
	game._build_arena_ground(&"argus",coated_arena);game._build_arena_ground(&"argus",baseline)
	var ruins := coated_arena.get_node("ArgusRuins") as ArgusRuins
	var control := baseline.get_node("ArgusRuins") as ArgusRuins
	var before := snapshot(coated_arena)
	var protected := {}
	for name: StringName in MECHANICS:
		var body := ruins.get_node(NodePath(name))
		var mesh := body.get_child(1) as MeshInstance3D
		protected[name]=[body,mesh,mesh.material_override]
	var plate_material := ruins._plate_mesh.material_override
	ArenaArchitectureMaterials.append(coated_arena,"argus")
	check(mechanism_state(ruins)==mechanism_state(control),"Architecture changed Argus initial mechanism state")
	check(not ruins.route_open and not ruins.activated and ruins.impacts==0,"Argus starts activated")
	check((plate_material as StandardMaterial3D).emission==Color(.45,.17,.03),"Inactive Argus counterweight emission changed")
	check(not ruins.receive_impact(ruins.to_global(ArgusRuins.PLATE+Vector3(10,0,0))),"Far impact opened Argus route")
	check(not control.receive_impact(control.to_global(ArgusRuins.PLATE+Vector3(10,0,0))),"Baseline rejected-impact fixture invalid")
	check(ruins.receive_impact(ruins.to_global(ArgusRuins.PLATE)) and control.receive_impact(control.to_global(ArgusRuins.PLATE)),"Valid transformed Argus impact was rejected")
	check(not ruins.receive_impact(ruins.to_global(ArgusRuins.PLATE)),"Argus repeated impact accepted")
	check(not control.receive_impact(control.to_global(ArgusRuins.PLATE)),"Baseline repeated impact accepted")
	for frame in 30:
		ruins._physics_process(.1);control._physics_process(.1)
		check(mechanism_state(ruins)==mechanism_state(control),"Architecture changed Argus activation trajectory at sample "+str(frame))
	check(ruins.route_open and ruins.activated and ruins.impacts==1 and is_equal_approx(ruins.weight,1),"Argus ramp did not open normally")
	check((plate_material as StandardMaterial3D).emission==Color(.08,.32,.42),"Activated Argus counterweight lost blue emission")
	check(geometry_bytes(coated_arena)==geometry_bytes(baseline) and physics_bytes(coated_arena)==physics_bytes(baseline),"Argus moving geometry/physics diverged after activation")
	for name: StringName in protected:
		var stored: Array = protected[name]
		check(ruins.get_node(NodePath(name))==stored[0] and stored[1].material_override==stored[2] and not stored[1].has_meta(META),"Architecture replaced or coated live Argus mechanic: "+String(name))
	check(ruins._plate_mesh.material_override==plate_material,"Counterweight material identity changed during activation")
	check(not ArenaArchitectureMaterials.material_for("argus").emission_enabled,"Counterweight emission leaked into shared architecture material")
	ruins.reset();control.reset()
	check(mechanism_state(ruins)==mechanism_state(control),"Argus reset state differs from baseline")
	check(not ruins.route_open and not ruins.activated and ruins.weight==0 and ruins.impacts==0,"Argus reset incomplete")
	check_unchanged(coated_arena,before,"Argus after full activation/reset")
	report.argus_mechanism={"transformed_impact_checked":true,"activation_samples":30,"excluded_mechanics":MECHANICS,"inactive_and_active_emission_checked":true,"route_activation_and_reset_checked":true,"geometry_physics_equal_to_uncoated_baseline":true}
	coated_arena.free();baseline.free();game.free()

func audit_fail_closed() -> void:
	var fixture := Node3D.new();root.add_child(fixture)
	var material := StandardMaterial3D.new()
	var nested := Node3D.new();fixture.add_child(nested)
	TerrainKit.box(nested,Vector3(-32,6,0),Vector3(2,12,78),material)
	for name: StringName in [&"Ground",&"CoverRoof",&"HingedGalleryRamp",&"StompCounterweight",&"GalleryBridge",&"JumpToGuardian"]:
		TerrainKit.box(fixture,Vector3(-32,6,0),Vector3(2,12,78),material).name=name
	var rotated := TerrainKit.box(fixture,Vector3(-32,6,0),Vector3(2,12,78),material,Basis(Vector3.UP,.1))
	var offset := TerrainKit.box(fixture,Vector3(-32,6,0),Vector3(2,12,78),material)
	(offset.get_child(1) as MeshInstance3D).position.x=.1
	var hidden := TerrainKit.box(fixture,Vector3(-32,6,0),Vector3(2,12,78),material)
	(hidden.get_child(1) as MeshInstance3D).visible=false
	TerrainKit.box(fixture,Vector3(-32,6,0),Vector3(2,11,78),material)
	TerrainKit.box(fixture,Vector3(-31,6,0),Vector3(2,12,78),material)
	var before := snapshot(fixture);var appearance := appearance_bytes(fixture)
	ArenaArchitectureMaterials.append(fixture,"barba")
	check(coated(fixture).is_empty() and appearance_bytes(fixture)==appearance,"Selector coated excluded named, nested, invisible or altered geometry")
	check(rotated.basis!=Basis.IDENTITY,"Rotated fail-closed fixture invalid")
	check_unchanged(fixture,before,"fail-closed fixtures")
	var unsupported := []
	for arena in ["valus","quadratus","phaedra","hydrus","avion","basaran","phalanx","pelagia","unknown",""]:
		var job := ArenaArt.plan(func() -> void: ArenaArchitectureMaterials.append(fixture,arena))
		check(job.jobs.is_empty() and ArenaArchitectureMaterials.material_for(arena)==null,"Unsupported arena planned/loaded architecture: "+arena)
		ArenaArchitectureMaterials.append(fixture,arena)
		check(appearance_bytes(fixture)==appearance,"Unsupported arena changed appearance: "+arena)
		unsupported.append(arena)
	report.fail_closed={"nested_art_hidden_transformed_wrong_shape_named_mechanics_checked":true,"unsupported_arenas":unsupported}
	fixture.free()

func audit_custom_exclusions() -> void:
	var game := GameWorld.new()
	for arena in ["phoenix","spider","dormin"]:
		var parent := Node3D.new();parent.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(parent)
		# Standalone builders remain uncoated, including art-enabled trial dressing.
		var builder: Script = load("res://src/world/%s_arena.gd"%arena)
		builder.call("build",parent);builder.call("dress",parent)
		check(coated(parent).is_empty(),"Standalone trial unexpectedly acquired architecture: "+arena)
		for mesh in meshes(parent): check(not mesh.has_meta(&"arena_ground_material"),"Standalone trial acquired ground coating: "+arena)
		parent.free()
		parent=Node3D.new();parent.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(parent)
		game._build_arena_ground(StringName(arena),parent)
		var excluded := {}
		for mesh in meshes(parent):
			if not mesh.get_parent() is StaticBody3D or (mesh.mesh is BoxMesh and mesh.mesh.size.is_equal_approx(Vector3(2,.3,2))):
				excluded[mesh.get_instance_id()]=[mesh,mesh.material_override]
		if arena=="phoenix": check(excluded.size()==4,"Expected two pools and two falling-water meshes")
		if arena=="spider": check(excluded.size()==3,"Expected all three anchor pads")
		ArenaGroundMaterials.append(parent,arena);ArenaArchitectureMaterials.append(parent,arena)
		for row: Array in excluded.values():
			check(row[0].material_override==row[1] and not row[0].has_meta(META) and not row[0].has_meta(&"arena_ground_material"),"Coated custom water or anchor pad: "+arena)
		parent.free()
		# Every authored facade fails closed for altered shape, basis, position,
		# mesh-local transform, visibility or nested ownership.
		for spec: Array in authored_manifest(arena):
			var fixture := Node3D.new();root.add_child(fixture)
			var material := StandardMaterial3D.new()
			TerrainKit.box(fixture,spec[1]+Vector3.RIGHT*.2,spec[2],material)
			TerrainKit.box(fixture,spec[1],spec[2]+Vector3.UP*.2,material)
			TerrainKit.box(fixture,spec[1],spec[2],material,Basis(Vector3.UP,.1))
			var offset := TerrainKit.box(fixture,spec[1],spec[2],material)
			(offset.get_child(1) as MeshInstance3D).position.x=.1
			var hidden := TerrainKit.box(fixture,spec[1],spec[2],material)
			(hidden.get_child(1) as MeshInstance3D).visible=false
			var nested := Node3D.new();fixture.add_child(nested)
			TerrainKit.box(nested,spec[1],spec[2],material)
			check(ArenaArchitectureMaterials._targets(fixture,arena).is_empty(),"Custom facade accepted altered or nested shape: "+arena)
			fixture.free()
	game.free()
	report.custom_exclusions={"water_meshes":4,"anchor_pads":3,"standalone_build_and_dress_uncoated":true,"all_authored_facade_transforms_fail_closed":true}

func audit_remaining_ground_and_reset() -> void:
	var game := GameWorld.new()
	var ground_counts := {"gaius":5,"dirge":7,"celosia_cenobia":1,"malus":1}
	for arena: String in ground_counts:
		var parent := Node3D.new();parent.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(parent)
		game._build_arena_ground(StringName(arena),parent)
		var before := snapshot(parent)
		var originals := {}
		for mesh in meshes(parent): originals[mesh.get_instance_id()]=mesh.material_override
		ArenaGroundMaterials.append(parent,arena)
		var count := 0
		for mesh in meshes(parent):
			var body := mesh.get_parent()
			var expected: bool = body.name==&"Ground"
			if arena=="dirge": expected = expected or body.name==&"DesertFloor" or (mesh.mesh is BoxMesh and mesh.mesh.size.is_equal_approx(Vector3(16,.8,12)) and is_equal_approx(body.position.x,-76))
			if arena=="gaius": expected = expected or (mesh.mesh is BoxMesh and body.position.x in [-46.0,44.0] and mesh.mesh.size.y<4.0)
			check(mesh.has_meta(&"arena_ground_material")==expected,"Remaining floor exact target mismatch: "+arena+"/"+str(body.position))
			if expected:
				count+=1
				check(mesh.material_override==ArenaGroundMaterials.material_for(arena),"Remaining floor wrong material: "+arena)
			else: check(mesh.material_override==originals[mesh.get_instance_id()],"Remaining floor touched unrelated mesh: "+arena)
		check(count==ground_counts[arena],"Remaining floor total mismatch: "+arena)
		check_unchanged(parent,before,"remaining ground "+arena)
		if arena=="celosia_cenobia":
			ArenaArchitectureMaterials.append(parent,arena)
			var boss := CelosiaCenobiaArena.spawn(parent)
			var column := parent.get_node("ChargeColumn0") as StaticBody3D
			var column_mesh := column.get_child(1) as MeshInstance3D
			var column_material := column_mesh.material_override
			var wall := parent.get_node("FireBreakWall")
			var wall_material := (wall.get_child(1) as MeshInstance3D).material_override
			boss.guardians[1].mode=PairedSentinel.Mode.CHARGE
			check(boss.wall_impact(boss.guardians[1],column),"Coated encounter lost charge impact")
			await process_frame
			check(not column_mesh.visible and (column.get_child(0) as CollisionShape3D).disabled,"Coated column failed to break")
			boss.reset_encounter()
			await process_frame
			check(column_mesh.visible and not (column.get_child(0) as CollisionShape3D).disabled,"Coated column failed to reset")
			check(column_mesh.material_override==column_material and column_material==originals[column_mesh.get_instance_id()],"Column reset material identity changed")
			check((wall.get_child(1) as MeshInstance3D).material_override==wall_material and wall_material==originals[(wall.get_child(1) as MeshInstance3D).get_instance_id()],"Fire wall material changed")
			boss.guardians[0].mode=PairedSentinel.Mode.FIRE_RETREAT
			check(boss.wall_impact(boss.guardians[0],wall),"Fire wall lost retreat interaction")
			boss.reset_encounter()
			check(boss.stats.armour_breaks==0,"Combined encounter stats failed to reset")
		parent.free()
	game.free()
	report.remaining_ground={"exact_counts":ground_counts,"untargeted_material_identity_preserved":true,"combined_charge_break_and_reset_checked":true,"fire_retreat_checked":true}


func run() -> void:
	var began := Time.get_ticks_usec()
	for arena: String in EXPECTED: await audit_append(arena)
	audit_campaign()
	await audit_production_staging()
	await audit_cancelled_queue()
	audit_production_stop_cleanup()
	audit_argus_mechanism()
	audit_fail_closed()
	audit_custom_exclusions()
	await audit_remaining_ground_and_reset()
	report.failures=failures;report.checks=checks;report.elapsed_usec=Time.get_ticks_usec()-began
	report.status="PASS" if failures==0 else "FAIL"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/arena_architecture_materials.json",FileAccess.WRITE)
	check(file!=null,"Unable to write architecture audit report")
	if file: file.store_string(JSON.stringify(report,"  "));file.close()
	print("ARENA_ARCHITECTURE_MATERIALS: ",JSON.stringify(report))
	quit(1 if failures else 0)
