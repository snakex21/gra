extends SceneTree
## Material-only next-four-arena layout-5 contract; headless CPU/identity checks.
## Independent copy of the earlier-seven contract intentionally preserves that suite unchanged.
const EXPECTED := {"barba":1,"kuromori":2,"pelagia":1,"argus":1}
const TILE_METRES := {"barba":16.0,"kuromori":18.0,"pelagia":14.0,"argus":20.0}
var failures := 0
var report := {"arenas":{},"legacy_layouts":[],"gpu_fps_measured":false,"scope":"Headless CPU queue time, exact geometry/physics/resource identity and texture source budgets; no GPU, FPS, draw-call or residency measurement"}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func digest(value: Variant) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func meshes(parent: Node3D) -> Array[MeshInstance3D]:
	var result:Array[MeshInstance3D]=[]
	for node:MeshInstance3D in parent.find_children("*","MeshInstance3D",true,false):result.append(node)
	return result

func geometry_bytes(parent: Node3D) -> PackedByteArray:
	var rows:=[]
	for node in meshes(parent):
		var surfaces:=[]
		for surface in node.mesh.get_surface_count():
			surfaces.append([node.mesh.get_class(),node.mesh.surface_get_arrays(surface)])
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.visible,node.layers,surfaces])
	return var_to_bytes(rows)

func physics_bytes(parent: Node3D) -> PackedByteArray:
	var rows:=[]
	for node:CollisionShape3D in parent.find_children("*","CollisionShape3D",true,false):
		var properties:=[]
		for property:Dictionary in node.shape.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_STORAGE and not String(property.name).begins_with("resource_"):
				properties.append([property.name,node.shape.get(property.name)])
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.disabled,node.get_parent().collision_layer,node.get_parent().collision_mask,node.shape.get_class(),properties])
	return var_to_bytes(rows)

func resource_ids(parent: Node3D) -> PackedByteArray:
	var rows:=[]
	for node in meshes(parent):
		var surfaces:=[]
		for surface in node.mesh.get_surface_count():
			var mat:=node.mesh.surface_get_material(surface)
			surfaces.append(mat.get_instance_id() if mat else 0)
		rows.append([node.get_instance_id(),node.mesh.get_instance_id(),surfaces])
	for node:CollisionShape3D in parent.find_children("*","CollisionShape3D",true,false):
		rows.append([node.get_instance_id(),node.shape.get_instance_id()])
	return var_to_bytes(rows)

func coated(parent: Node3D) -> Array[MeshInstance3D]:
	var result:Array[MeshInstance3D]=[]
	for node in meshes(parent):
		if node.has_meta(&"arena_ground_material"):result.append(node)
	return result

func expected_target(node: MeshInstance3D, arena: String, parent: Node3D) -> bool:
	# Match the authored floor role independently of the production selector.
	# Kuromori's first authored body is the courtyard. Its 48 steps, all
	# galleries/walls, and hidden climb ramp must retain their original material.
	var body:=node.get_parent()
	if not body is StaticBody3D or body.get_parent()!=parent:return false
	if body.name==&"Ground":return true
	return arena=="kuromori" and body==parent.get_child(0)

func appearance_bytes(parent: Node3D) -> PackedByteArray:
	var rows:=[]
	for node in meshes(parent):
		rows.append([node.material_override.resource_path if node.material_override else "",node.get_meta(&"arena_ground_material","")])
	return var_to_bytes(rows)

func validate_material(arena: String, material: StandardMaterial3D) -> void:
	check(material!=null,"Missing material: " + arena)
	if material==null:return
	check(material==ArenaGroundMaterials.material_for(arena),"Material cache does not preserve identity: " + arena)
	check(material.uv1_triplanar and not material.uv1_world_triplanar,"Coordinates must be local triplanar: " + arena)
	check(material.uv1_scale.is_equal_approx(Vector3.ONE/TILE_METRES[arena]),"Wrong authored texture scale: " + arena)
	check(material.normal_enabled and material.normal_scale>0,"Normal detail disabled: " + arena)
	check(not material.heightmap_enabled,"Surface introduced displacement/parallax: " + arena)
	check(material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Floor material became transparent: " + arena)
	check(material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,"Missing filtered mipmaps: " + arena)
	for slot in ["albedo","normal","roughness"]:
		var texture:Texture2D=material.get(slot+"_texture")
		check(texture!=null and texture.get_size()==Vector2(512,512),"Missing/non-budget 512px map: " + arena + "/" + slot)
		if texture:check(texture.resource_path=="res://textures/arena_ground/%s_%s.png"%[arena,slot],"Wrong texture provenance: " + arena + "/" + slot)

func audit_append(arena: String) -> void:
	var game:=GameWorld.new()
	var parent:=Node3D.new();parent.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(parent)
	parent.transform=Transform3D(Basis(Vector3.UP,.71),Vector3(641,8,-311))
	# Freeze animated geysers while cold texture decoding yields to process frames.
	game._build_arena_ground(StringName(arena),parent)
	var before_geometry:=geometry_bytes(parent)
	var before_physics:=physics_bytes(parent)
	var before_ids:=resource_ids(parent)
	var all_nodes:=parent.find_children("*","",true,false).size()
	var old_materials:={}
	for node in meshes(parent):old_materials[node.get_instance_id()]=node.material_override
	# First contact is the production asynchronous queue, before cache warmup.
	var job:=ArenaArt.plan(func() -> void:ArenaGroundMaterials.append(parent,arena))
	check(coated(parent).is_empty(),"Planning eagerly changed floor materials: " + arena)
	check(job.jobs.size()==EXPECTED[arena]+1,"Work not split into one load plus one assignment per mesh: " + arena)
	var steps:=0
	var deadline:=Time.get_ticks_msec()+15000
	while not job.step(1000,1):
		steps+=1
		if Time.get_ticks_msec()>deadline:
			check(false,"Material queue timed out: " + arena)
			parent.free();game.free();return
		await process_frame
	var material:=ArenaGroundMaterials.material_for(arena)
	validate_material(arena,material)
	var applied:=coated(parent)
	check(applied.size()==EXPECTED[arena],"Wrong material target count: " + arena)
	var target_rows:=[]
	for node in meshes(parent):
		check(node.has_meta(&"arena_ground_material")==expected_target(node,arena,parent),"Target selection differs from authored geometry: "+arena+"/"+str(node.get_parent().position))
		if node.has_meta(&"arena_ground_material"):
			check(node.material_override==material and node.get_meta(&"arena_ground_material")==arena,"Wrong/shared material assignment: " + arena)
			check(node.get_parent().get_parent()==parent and node.get_parent() is StaticBody3D,"Coated art, water or encounter child: " + arena)
			target_rows.append({"body":str(node.get_parent().name),"position":str(node.get_parent().position),"mesh_class":node.mesh.get_class()})
		else:
			check(node.material_override==old_materials[node.get_instance_id()],"Changed non-target material: " + arena)
	ArenaGroundMaterials.append(parent,arena)
	check(coated(parent).size()==EXPECTED[arena],"Repeated assignment duplicated targets: " + arena)
	for profile in ["low","balanced","high","low","balanced"]:
		GraphicsQuality.apply(parent,profile)
		for node in applied:check(node.material_override==material,"Quality replaced shared floor material: " + arena)
	check(geometry_bytes(parent)==before_geometry,"Material pass changed exact mesh arrays/transforms: " + arena)
	check(physics_bytes(parent)==before_physics,"Material pass changed collider shapes/transforms/layers: " + arena)
	check(resource_ids(parent)==before_ids,"Material pass rebuilt a mesh/shape or mutated a mesh surface material: " + arena)
	check(parent.find_children("*","",true,false).size()==all_nodes,"Material pass added/removed nodes: " + arena)
	var second:=Node3D.new();root.add_child(second)
	game._build_arena_ground(StringName(arena),second)
	var warm_began:=Time.get_ticks_usec()
	ArenaGroundMaterials.append(second,arena)
	var warm_usec:=Time.get_ticks_usec()-warm_began
	for node in coated(second):check(node.material_override==material,"Second arena instance duplicates material/texture resources: " + arena)
	report.arenas[arena]={"target_meshes":applied.size(),"targets":target_rows,"floor_and_obstacle_meshes":meshes(parent).size(),"texture_tile_metres":TILE_METRES[arena],"stream_steps":steps,"max_step_usec":job.max_step_usec,"warm_assignment_usec":warm_usec,"geometry_sha256":digest(before_geometry),"physics_sha256":digest(before_physics),"shared_material":true,"exact_resource_identity_preserved":true,"added_nodes":0,"added_colliders":0,"added_meshes":0,"rotated_translated_parent_checked":true}
	second.free();parent.free();game.free()

func baseline_script() -> GDScript:
	var source:=FileAccess.get_file_as_string("res://src/game/game_world.gd")
	var hook:="\t\tArenaGroundMaterials.append(root, String(kind))\n"
	check(source.count(hook)==1,"Material campaign hook must be unique")
	check(source.contains("\tif layout_version == 5:\n"+hook),"Material campaign hook lost explicit layout-5 gate")
	source=source.replace("class_name GameWorld\n","").replace(hook,"")
	var script:=GDScript.new();script.source_code=source
	check(script.reload()==OK,"Baseline campaign fixture does not compile")
	return script

func audit_campaign() -> void:
	var current:=GameWorld.new()
	var baseline:Node3D=baseline_script().new()
	for layout in [1,2,3,4,5]:
		current.layout_version=layout;baseline.layout_version=layout
		for arena:String in EXPECTED:
			var first:=Node3D.new();var other:=Node3D.new()
			root.add_child(first);root.add_child(other)
			current._build_arena(StringName(arena),first);baseline._build_arena(StringName(arena),other)
			check(coated(first).size()==(EXPECTED[arena] if layout==5 else 0),"Wrong campaign layout target count: %d/%s"%[layout,arena])
			check(coated(other).is_empty(),"Baseline fixture unexpectedly coated")
			check(geometry_bytes(first)==geometry_bytes(other),"Campaign hook changed exact arena geometry: %d/%s"%[layout,arena])
			check(physics_bytes(first)==physics_bytes(other),"Campaign hook changed arena physics: %d/%s"%[layout,arena])
			if layout<5:check(appearance_bytes(first)==appearance_bytes(other),"Legacy appearance changed: %d/%s"%[layout,arena])
			first.free();other.free()
		if layout<5:report.legacy_layouts.append(layout)
	current.layout_version=5;current.with_art=false
	for arena:String in EXPECTED:
		var fixture:=Node3D.new();root.add_child(fixture)
		current._build_arena(StringName(arena),fixture)
		check(coated(fixture).is_empty(),"Physics/replay art-off path gained new materials: "+arena)
		fixture.free()
	var artless:=Node3D.new();root.add_child(artless)
	current._build_arena(&"gaius",artless)
	var before:=resource_ids(artless)
	ArenaGroundMaterials.append(artless,"unknown")
	check(resource_ids(artless)==before and coated(artless).is_empty(),"Unsupported arena changed resources/materials")
	check(ArenaGroundMaterials.material_for("unknown")==null,"Unsupported arena acquired a floor material")
	artless.free();current.free();baseline.free()
	report.all_art_off_arenas_checked=true
	report.kuromori_galleries_steps_walls_and_ramp_unchanged=true

func audit_production_staging() -> void:
	var game:=GameWorld.new();game.layout_version=5
	var metrics:={}
	for arena:String in EXPECTED:
		var direct:=Node3D.new();var staged:=Node3D.new()
		direct.process_mode=Node.PROCESS_MODE_DISABLED;staged.process_mode=Node.PROCESS_MODE_DISABLED
		root.add_child(direct);root.add_child(staged)
		game._build_arena(StringName(arena),direct)
		game.arenas[StringName(arena)]={"root":staged,"points":{}}
		game._queue_arena(StringName(arena),staged)
		game._build_step()
		check(coated(staged).is_empty(),"Stage zero changed materials before art: "+arena)
		check(game._pending.size()==1,"Stage zero failed to enqueue art: "+arena)
		var steps:=0;var max_usec:=0
		var deadline:=Time.get_ticks_msec()+20000
		while not game.arenas_ready():
			var began:=Time.get_ticks_usec()
			game._build_step()
			max_usec=maxi(max_usec,Time.get_ticks_usec()-began)
			steps+=1
			if steps==2:GraphicsQuality.apply(staged,"low")
			if steps==7:GraphicsQuality.apply(staged,"high")
			if Time.get_ticks_msec()>deadline:
				check(false,"Production material staging timed out: "+arena);break
			if steps%20==0:await process_frame
		check(game._art_jobs.is_empty(),"Completed arena retained an art job: "+arena)
		GraphicsQuality.apply(direct,"balanced");GraphicsQuality.apply(staged,"balanced")
		check(coated(staged).size()==EXPECTED[arena],"Production staging lost material assignments: "+arena)
		check(appearance_bytes(direct)==appearance_bytes(staged),"Production staging changed mesh materials: "+arena)
		check(geometry_bytes(direct)==geometry_bytes(staged),"Production staging differs from direct mesh geometry: "+arena)
		check(physics_bytes(direct)==physics_bytes(staged),"Production staging differs from direct physics: "+arena)
		metrics[arena]={"stage1_steps":steps,"max_stage_call_usec":max_usec,"quality_switched_during_staging":true,"direct_geometry_physics_materials_equal":true}
		direct.free();staged.free()
	game.free()
	report.production_staging=metrics

func audit_cancelled_queue() -> void:
	var game:=GameWorld.new()
	for arena:String in EXPECTED:
		for midway in [false,true]:
			var parent:=Node3D.new();root.add_child(parent)
			game._build_arena_ground(StringName(arena),parent)
			var job:=ArenaArt.plan(func() -> void:ArenaGroundMaterials.append(parent,arena))
			var count:=job.jobs.size()
			if midway:
				job.step(1000,1);job.step(1000,1)
				check(coated(parent).size()==1,"Unable to exercise cancellation after first assignment: "+arena)
			parent.free()
			var deadline:=Time.get_ticks_msec()+15000
			while not job.step(1000,1):
				if Time.get_ticks_msec()>deadline:
					check(false,"Cancelled material queue did not complete: "+arena)
					game.free();return
				await process_frame
			check(job.cursor==count,"Cancelled material queue skipped/retained a job: "+arena)
	report.cancelled_before_and_during_assignment_checked=true
	game.free()

func audit_production_stop_cleanup() -> void:
	var checkpoints:={}
	# Exercise the real title/stop cleanup with a partially built production
	# region, before and after its first art work unit. It must retain no queue.
	for arena:String in EXPECTED:
		for midway in [false,true]:
			var game:=GameWorld.new();game.layout_version=5;game.with_input=false;game.save_path=""
			root.add_child(game)
			game.region=Node3D.new();game.add_child(game.region)
			var parent:=Node3D.new();game.region.add_child(parent)
			var parent_ref:WeakRef=weakref(parent)
			game.arenas[StringName(arena)]={"root":parent,"points":{}}
			game._queue_arena(StringName(arena),parent)
			game._build_step()
			if midway:
				game._build_step()
				# Floor-only Barba legitimately completes inside one stage call.
				# Other arenas retain their sliced decoration job at this point.
				if not game.arenas_ready():
					check(not game._art_jobs.is_empty(),"Pending art has no production job: "+arena)
			else:
				check(not game._pending.is_empty(),"No pre-art pending queue: "+arena)
			checkpoints[arena+("_after_first_art_step" if midway else "_before_art")]={"pending":game._pending.size(),"art_jobs":game._art_jobs.size(),"already_completed":game.arenas_ready()}
			var shared_material:=ArenaGroundMaterials.material_for(arena)
			game.stop()
			check(game._pending.is_empty() and game._art_jobs.is_empty(),"Stop retained production jobs: "+arena)
			check(game.arenas.is_empty() and game.region==null and parent_ref.get_ref()==null,"Stop retained arena/region: "+arena)
			check(ArenaGroundMaterials.material_for(arena)==shared_material,"Stop discarded reusable shared floor resources: "+arena)
			game.free()
	report.production_stop_cleanup_before_and_during_art_checked=true
	report.production_stop_checkpoints=checkpoints

func run() -> void:
	var began:=Time.get_ticks_usec()
	for arena:String in EXPECTED:await audit_append(arena)
	audit_campaign()
	await audit_production_staging()
	await audit_cancelled_queue()
	audit_production_stop_cleanup()
	report.failures=failures;report.elapsed_usec=Time.get_ticks_usec()-began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file:=FileAccess.open("res://tests/output/next_arena_ground.json",FileAccess.WRITE)
	check(file!=null,"Unable to write material report")
	if file:file.store_string(JSON.stringify(report,"  "));file.close()
	print("NEXT_ARENA_GROUND: ",JSON.stringify(report))
	quit(1 if failures else 0)
