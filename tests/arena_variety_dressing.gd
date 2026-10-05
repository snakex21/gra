extends SceneTree
## CPU/headless regression for production layout-5 campaign integration.
## Run: godot --headless --path . --script tests/arena_variety_dressing.gd
## Imported source geometry and CPU uploads are authoritative; no dummy GPU readback.
const BASELINE_GAME_SHA256 := ["09103346acead2d5f3d265af10a9af406a475c86ff9ac07b24cc2d5f6e2ab484","70a846c8732e7b454129ef4013e30e732ae3d718919370bf212a7bb9290ca908"] # Verified preserved-co-op and original delivery baselines
const INNER_DISKS := {"quadratus":96.0,"phaedra":88.0,"avion":119.0}
const PROFILES := {"low": [.35,.7], "balanced": [.65,.85], "high": [1.0,1.0]}
const PLACEMENT_LIMIT := 216
const BATCH_LIMIT := 150
const ALL_NEAR_TRIANGLE_LIMIT := 400000
const SELECTED_TRIANGLE_LIMITS := {"low": 300000, "balanced": 450000, "high": 650000}
var failures := 0
var report := {"arenas":{}, "legacy_layouts":[], "scope":"CPU imported geometry, actual production builders, distance-selected batches before frustum/occlusion; no GPU/FPS or screenshot claim"}
var mesh_cache := {}
var baseline_script: GDScript

func bytes_sha256(data:PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func shape_record(s: CollisionShape3D) -> Array:
	var sh := s.shape
	var shape_data: Variant = sh.get_faces() if sh is ConcavePolygonShape3D else sh.points if sh is ConvexPolygonShape3D else sh.size if sh is BoxShape3D else [sh.radius,sh.height] if sh is CylinderShape3D else sh.get_class()
	return [s.global_transform,s.disabled,s.get_parent().collision_layer,s.get_parent().collision_mask,sh.get_class(),shape_data]

func physical_bytes(fixture: Node3D) -> PackedByteArray:
	var records := []
	for s: CollisionShape3D in fixture.find_children("*","CollisionShape3D",true,false):
		records.append(shape_record(s))
	return var_to_bytes(records)

func terrain_bytes(fixture: Node3D) -> PackedByteArray:
	var records := []
	for m: MeshInstance3D in fixture.find_children("*","MeshInstance3D",true,false):
		if m.get_parent() is StaticBody3D:
			var arrays := []
			for surface in m.mesh.get_surface_count():
				arrays.append(m.mesh.surface_get_arrays(surface))
			records.append([m.global_transform,arrays])
	return var_to_bytes(records)


func info(kind: String) -> Dictionary:
	if mesh_cache.has(kind): return mesh_cache[kind]
	var bounds := AABB()
	var triangles := []
	for lod in 3:
		var mesh := ArenaVarietyDressing.mesh_for(kind,lod)
		check(mesh != null,"Missing imported variety mesh: " + kind)
		if mesh == null: return {}
		check(mesh==ArenaVarietyDressing.mesh_for(kind,lod),"Geometry resource not reused: " + kind)
		check(mesh.get_surface_count()==1,"Multiple surfaces: " + kind)
		bounds = mesh.get_aabb() if lod==0 else bounds.merge(mesh.get_aabb())
		var count := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			count += int(indices.size()/3) if indices != null and not indices.is_empty() else int(arrays[Mesh.ARRAY_VERTEX].size()/3)
			check(mesh.surface_get_material(surface)==null,"Embedded material bypasses shared palette: " + kind)
		triangles.append(count)
		check(count==int(NatureVarietyCatalog.models()[kind].triangles[lod]),"Catalog triangle count differs from actual mesh: " + kind)
	check(triangles[0]>triangles[1] and triangles[1]>triangles[2],"LODs do not strictly reduce " + kind)
	check(bounds.is_equal_approx(ArenaVarietyDressing.bounds_for(kind)),"Production full-LOD bounds differ: " + kind)
	check(bounds.is_equal_approx(NatureVarietyCatalog.bounds_for(kind)),"Catalog full-LOD bounds differ: " + kind)
	mesh_cache[kind] = {"bounds":bounds,"triangles":triangles}
	return mesh_cache[kind]

func variety_nodes(fixture: Node3D) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for n: MultiMeshInstance3D in fixture.find_children("*","MultiMeshInstance3D",true,false):
		if n.has_meta(&"arena_variety_kind"): nodes.append(n)
	return nodes

func baseline_game_script() -> GDScript:
	var source := FileAccess.get_file_as_string("res://src/game/game_world.gd")
	# Reconstruct the same historical fixture after the separately audited,
	# material-only architecture continuation. Keep the original baseline hash
	# and edge/variety hook checks; do not accept unrelated gameplay edits.
	var architecture_hook := "\t\tArenaArchitectureMaterials.append(root, String(kind))\n"
	var architecture_gate := "\tif layout_version == 5:\n\t\tArenaGroundMaterials.append(root, String(kind))\n" + architecture_hook
	check(source.count(architecture_hook) == 1 and source.contains(architecture_gate), "Architecture continuation must retain its exact layout-5-only gate")
	var cave_hook := "\t\tArenaCaveFloorMaterials.append(root, String(kind))\n"
	check(source.count(cave_hook) == 1 and source.contains(architecture_gate + cave_hook), "Cave floor continuation must retain its exact layout-5-only gate")
	var executable_source := source
	source = source.replace(cave_hook, "").replace(architecture_hook, "")
	var hook := "\tif layout_version == 5:\n\t\tArenaVarietyDressing.append(root, String(kind))\n\n"
	check(source.count(hook)==1,"New campaign hook must occur once and explicitly protect layouts 1–4")
	source = source.replace(hook,"")
	report.game_world_without_new_hook_sha256 = source.sha256_text()
	check(source.sha256_text() in BASELINE_GAME_SHA256,"Removing only the exact hook does not match either verified pre-change baseline; preserve custom game code and review the integration separately")
	# Keep the newer architecture on both sides of this variety-only fixture.
	source = executable_source.replace(hook, "")
	source = source.replace("class_name GameWorld\n","")
	var script := GDScript.new()
	script.source_code = source
	check(script.reload()==OK,"Unable to compile baseline campaign fixture")
	return script

func legacy_descriptor(fixture: Node3D) -> PackedByteArray:
	var rows := []
	for n: Node in fixture.find_children("*","",true,false):
		if n.has_meta(&"arena_variety_kind"): continue
		var row := [n.get_class()]
		if n is Node3D: row.append(n.transform)
		if n is MeshInstance3D:
			row.append([n.mesh.get_aabb(),n.visible,n.layers,n.material_override.resource_path if n.material_override else ""])
		if n is MultiMeshInstance3D:
			row.append([n.multimesh.instance_count,n.multimesh.mesh.get_aabb(),n.visibility_range_begin,n.visibility_range_end])
		rows.append(row)
	return var_to_bytes(rows)

func audit_legacy() -> void:
	var current := GameWorld.new()
	var baseline: Node3D = baseline_script.new()
	for layout in [1,2,3,4]:
		current.layout_version=layout
		baseline.layout_version=layout
		for arena: String in INNER_DISKS:
			var first := Node3D.new()
			var other := Node3D.new()
			root.add_child(first);root.add_child(other)
			current._build_arena(StringName(arena),first)
			baseline._build_arena(StringName(arena),other)
			check(variety_nodes(first).is_empty(),"Legacy layout gained variety: %d/%s" % [layout,arena])
			check(physical_bytes(first)==physical_bytes(other),"Legacy physics changed: %d/%s" % [layout,arena])
			check(terrain_bytes(first)==terrain_bytes(other),"Legacy terrain vertices changed: %d/%s" % [layout,arena])
			check(legacy_descriptor(first)==legacy_descriptor(other),"Legacy art/material/LOD changed: %d/%s" % [layout,arena])
			first.free();other.free()
		report.legacy_layouts.append(layout)
	current.free();baseline.free()

func footprint_distance(bounds: AABB, p: Vector2) -> float:
	return Vector2(maxf(maxf(bounds.position.x-p.x,p.x-bounds.end.x),0),maxf(maxf(bounds.position.z-p.y,p.y-bounds.end.z),0)).length()

func obstacle_bounds(fixture: Node3D) -> Array:
	var result := []
	for s: CollisionShape3D in fixture.find_children("*","CollisionShape3D",true,false):
		var b: AABB = fixture.global_transform.affine_inverse()*s.global_transform*s.shape.get_debug_mesh().get_aabb()
		if b.end.y<=1.5 or maxf(b.size.x,b.size.z)>80: continue
		var owner_node := s.get_parent().get_parent()
		var label := str(owner_node.get("model_id")) if owner_node.get_script() and "model_id" in owner_node else String(fixture.get_path_to(s))
		result.append([b,label+"@"+str(b.get_center())])
	return result

func inspect_records(arena: String, records: Array, fixture: Node3D) -> Dictionary:
	var cfg: Dictionary = ArenaVarietyDressing.CONFIG[arena]
	check(float(cfg.inner)==float(INNER_DISKS[arena]),"Protected combat disk changed: " + arena)
	var obstacles := obstacle_bounds(fixture)
	var clearance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/environment/arena_variety_clearance.json"))
	var authored:Array=clearance.arenas[arena]
	check(authored.size()==obstacles.size(),"Authored exclusion data no longer covers actual legacy obstacle count: " + arena)
	for actual:Array in obstacles:
		var found:=false
		for exclusion:Dictionary in authored:
			var pos:Array=exclusion.position;var size:Array=exclusion.size
			var b:=AABB(Vector3(pos[0],pos[1],pos[2]),Vector3(size[0],size[1],size[2]))
			if b.is_equal_approx(actual[0]): found=true;break
		check(found,"Authored exclusion data omits/misstates actual legacy obstacle: " + str(actual[1]))
	var starts := GameWorld.arena_starts(StringName(arena))
	# Include the standalone arena's authored spawns as well as campaign starts.
	if arena=="quadratus": starts.append_array([QuadratusArena.PLAYER_START,QuadratusArena.HORSE_START])
	if arena=="phaedra": starts.append_array([PhaedraArena.PLAYER_START,PhaedraArena.HORSE_START])
	var counts := {}
	var hits := {}
	var nearest_spawn := INF
	var minimum_radius := INF
	var maximum_radius := 0.0
	var approach_margin := INF
	var tallest := 0.0
	var ground_top := -INF
	for visual: MeshInstance3D in fixture.get_node("Ground").find_children("*","MeshInstance3D",false,false):
		var b: AABB = fixture.global_transform.affine_inverse()*visual.global_transform*visual.mesh.get_aabb()
		ground_top=maxf(ground_top,b.end.y)
	for r: Dictionary in records:
		var xf: Transform3D = r.transform
		var b: AABB = xf*info(r.kind).bounds
		counts[r.kind]=int(counts.get(r.kind,0))+1
		minimum_radius=minf(minimum_radius,footprint_distance(b,Vector2.ZERO))
		tallest=maxf(tallest,b.size.y)
		if b.end.z>0: approach_margin=minf(approach_margin,minf(absf(b.position.x),absf(b.end.x))-24.0)
		check(footprint_distance(b,Vector2.ZERO)>=float(cfg.inner)-.001,"Union LOD footprint enters combat/water disk: " + arena)
		for x in [b.position.x,b.end.x]:
			for z in [b.position.z,b.end.z]:
				maximum_radius=maxf(maximum_radius,Vector2(x,z).length())
				check(Vector2(x,z).length()<=float(cfg.outer)+.001,"Union LOD footprint leaves safe rim: " + arena)
		check(not (b.end.z>0 and b.position.x<24 and b.end.x> -24),"Full footprint enters 48m horse/camera entrance: " + arena)
		for start: Vector3 in starts:
			var d := footprint_distance(b,Vector2(start.x,start.z))
			nearest_spawn=minf(nearest_spawn,d)
			check(d>=14,"Full footprint enters spawn/camera reserve: " + arena)
		check(absf(b.position.y-(ground_top-.015))<.001,"Full mesh bottom is not grounded on actual visual floor: " + arena)
		if arena=="avion":
			check(footprint_distance(b,Vector2.ZERO)>AvionArena.WATER_RADIUS,"Variety enters Avion water")
			check(is_zero_approx(AvionArena.ground_height(b.position.x,b.position.z)),"Avion placement not on flat shore")
		for obstacle: Array in obstacles:
			var ob: AABB=obstacle[0]
			if b.position.x<ob.end.x+.2 and b.end.x>ob.position.x-.2 and b.position.z<ob.end.z+.2 and b.end.z>ob.position.z-.2:
				if not hits.has(obstacle[1]): hits[obstacle[1]]=[]
				hits[obstacle[1]].append({"kind":r.kind,"position":str(xf.origin),"bounds":str(b)})
	check(hits.is_empty(),"Variety clips %d existing tall obstacle footprints in %s; see JSON tall_obstacle_overlaps" % [hits.size(),arena])
	check(counts.size()==6,"Arena lost one of its six configured models: " + arena)
	for kind:String in cfg.kinds.slice(0,4): check(counts.get(kind,0)==6,"Arena lost a complete landmark group: " + arena+"/"+kind)
	return {"kinds":counts,"minimum_footprint_radius_m":minimum_radius,"maximum_footprint_radius_m":maximum_radius,"extra_approach_clearance_m":approach_margin,"nearest_spawn_footprint_m":nearest_spawn,"maximum_height_m":tallest,"actual_ground_surface_y":ground_top,"tall_obstacle_overlaps":hits}

func descriptor(nodes: Array[MultiMeshInstance3D]) -> PackedByteArray:
	var rows := []
	for n in nodes: rows.append([n.name,n.transform,n.multimesh.instance_count,n.multimesh.custom_aabb,n.multimesh.mesh.get_rid(),n.material_override.get_rid()])
	return var_to_bytes(rows)

func inspect_batches(arena: String, records: Array, fixture: Node3D) -> Dictionary:
	var expected := ArenaVarietyDressing.batch_records(arena)
	var nodes := variety_nodes(fixture)
	check(nodes.size()==expected.size()*3,"Lost or extra LOD batches: " + arena)
	check(nodes.size()<=BATCH_LIMIT,"Arena exceeds batch ceiling: " + arena)
	var snapshots := descriptor(nodes)
	var physical_snapshot:=physical_bytes(fixture)
	var terrain_snapshot:=terrain_bytes(fixture)
	var profiles := {}
	var cameras := {"approach":Vector3(0,3,170),"spawn":GameWorld.arena_starts(StringName(arena))[0]+Vector3(0,2,7),"combat_center":Vector3(0,4,0)}
	for i in ArenaVarietyDressing.CONFIG[arena].centers.size():
		var center: Vector2=ArenaVarietyDressing.CONFIG[arena].centers[i]
		cameras["rim_%d"%i]=Vector3(center.x,3,center.y)
	var near_cost := 0
	for r:Dictionary in records: near_cost+=int(info(r.kind).triangles[0])
	check(near_cost<=ALL_NEAR_TRIANGLE_LIMIT,"Arena exceeds all-near CPU triangle ceiling: " + arena)
	for profile: String in ["low","balanced","high","low"]:
		GraphicsQuality.apply(fixture,profile)
		var visible := 0
		var costs := {}
		var draw_batches := {}
		for label: String in cameras: costs[label]=0;draw_batches[label]=0
		for index in expected.size():
			var batch: Dictionary=expected[index]
			var landmark: bool=not batch.kind.begins_with("plant_")
			var population: int=batch.transforms.size() if landmark else maxi(1,ceili(batch.transforms.size()*PROFILES[profile][0]))
			visible+=population
			var shared:=AABB()
			for i in batch.transforms.size():
				var b: AABB=batch.transforms[i]*info(batch.kind).bounds
				shared=b if i==0 else shared.merge(b)
			var ranges:=ArenaVarietyDressing.ranges(batch.kind)
			for lod in 3:
				var n: MultiMeshInstance3D=nodes[index*3+lod]
				check(n.multimesh.instance_count==batch.transforms.size(),"Batch population differs from sampler")
				check(n.get_script()==null and n.get_child_count()==0 and not n.is_processing() and not n.is_physics_processing(),"Decoration gained gameplay/per-frame behavior")
				check(n.multimesh.mesh==ArenaVarietyDressing.mesh_for(batch.kind,lod),"Batch duplicates geometry resource")
				check(n.position.is_equal_approx(shared.get_center()),"All-LOD union visibility center differs")
				var global_bounds:=n.multimesh.custom_aabb;global_bounds.position+=n.position
				check(global_bounds.is_equal_approx(shared),"Shared AABB fails complete union-LOD footprint")
				check(n.multimesh.visible_instance_count==population,"Quality population mismatch")
				check(n.material_override==ArenaVarietyDressing.material_for(batch.kind),"Duplicated/wrong material")
				check(n.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Unexpected shadow draw")
				check(n.visibility_range_begin_margin==0 and n.visibility_range_end_margin==0,"LOD hysteresis can hide bands")
				check(n.visibility_range_fade_mode==GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,"LOD fade causes overlapping draws")
				check(is_equal_approx(n.visibility_range_begin,ranges[lod]*PROFILES[profile][1]) and is_equal_approx(n.visibility_range_end,ranges[lod+1]*PROFILES[profile][1]),"Live quality ranges differ")
				if lod<2:
					check(is_equal_approx(n.visibility_range_end,nodes[index*3+lod+1].visibility_range_begin),"Gap/overlap in LOD bands")
				for label: String in cameras:
					var distance: float=shared.get_center().distance_to(cameras[label])
					if distance>=n.visibility_range_begin and distance<n.visibility_range_end:
						costs[label]+=population*int(info(batch.kind).triangles[lod]);draw_batches[label]+=1
		check(descriptor(nodes)==snapshots,"Quality rebuilt/repositioned render instances")
		check(physical_bytes(fixture)==physical_snapshot,"Live graphics quality changed collider data")
		check(terrain_bytes(fixture)==terrain_snapshot,"Live graphics quality changed terrain data")
		check(var_to_bytes(records)==var_to_bytes(ArenaVarietyDressing.sample(arena)),"Quality altered deterministic placements")
		profiles[profile]={"visible_placements":visible,"distance_selected_triangles":costs,"distance_selected_draw_batches":draw_batches}
	check(profiles.low.visible_placements<profiles.balanced.visible_placements and profiles.balanced.visible_placements<profiles.high.visible_placements,"Quality does not reduce plants")
	return {"lod_nodes":nodes.size(),"groups":expected.size(),"all_near_triangles":near_cost,"profiles":profiles}

func inspect_uploads(arena: String, world_xf: Transform3D) -> void:
	var source:=FileAccess.get_file_as_string("res://src/world/arena_variety_dressing.gd")
	var sink:="mm.set_instance_transform(i,xf)"
	check(source.count(sink)==1,"Cannot locate unique production transform upload")
	source=source.replace("class_name ArenaVarietyDressing\n","")
	source=source.replace(sink,sink+"\n  captured.append([int(state.batch),int(state.lod),i,xf])")
	source+="\nstatic var captured := []\n"
	var script:=GDScript.new();script.source_code=source
	check(script.reload()==OK,"CPU transform upload instrument did not compile")
	var fixture:=Node3D.new();root.add_child(fixture);fixture.transform=world_xf
	script.append(fixture,arena)
	var batches:=ArenaVarietyDressing.batch_records(arena)
	var nodes:=variety_nodes(fixture)
	var expected_count:=0
	for batch:Dictionary in batches: expected_count+=batch.transforms.size()*3
	check(script.captured.size()==expected_count,"Actual uploads lost or duplicated placements")
	for call:Array in script.captured:
		var node:MultiMeshInstance3D=nodes[call[0]*3+call[1]]
		var uploaded:Transform3D=call[3]
		var expected:Transform3D=batches[call[0]].transforms[call[2]]
		check((node.global_transform*uploaded).is_equal_approx(world_xf*expected),"CPU upload changes pose under translated/rotated/scaled arena")
	fixture.free()

func audit_arena(arena: String) -> void:
	var game:=GameWorld.new();game.layout_version=5
	var baseline:Node3D=baseline_script.new();baseline.layout_version=5
	var fixture:=Node3D.new();var before:=Node3D.new()
	root.add_child(fixture);root.add_child(before)
	baseline._build_arena(StringName(arena),before)
	var physics_before:=physical_bytes(before)
	var terrain_before:=terrain_bytes(before)
	game._build_arena(StringName(arena),fixture)
	check(physical_bytes(fixture)==physics_before,"Actual layout-5 builder changed colliders/layers: " + arena)
	check(terrain_bytes(fixture)==terrain_before,"Actual layout-5 builder changed terrain topology/heights: " + arena)
	check(legacy_descriptor(fixture)==legacy_descriptor(before),"Actual layout-5 builder changed existing scene art: " + arena)
	var records:=ArenaVarietyDressing.sample(arena)
	check(records.size()>=150 and records.size()<=PLACEMENT_LIMIT,"Placement budget outside 150–216: " + arena)
	check(var_to_bytes(records)==var_to_bytes(ArenaVarietyDressing.sample(arena)),"Sampling changed on rebuild")
	var entry:=inspect_records(arena,records,fixture)
	entry.merge(inspect_batches(arena,records,fixture))
	var job:=ArenaArt.plan(func() -> void:ArenaVarietyDressing.append(before,arena))
	check(variety_nodes(before).is_empty(),"Planning eagerly attached variety")
	var work_units:=0
	var deadline:=Time.get_ticks_msec()+10000
	while not job.step(2000,1):
		work_units+=1
		if Time.get_ticks_msec()>deadline:
			check(false,"Planner exceeded ten-second deadline: " + arena);break
	check(work_units>30,"Lost incremental bounded jobs")
	check(physical_bytes(before)==physics_before,"Queued dressing changed colliders")
	check(terrain_bytes(before)==terrain_before,"Queued dressing changed terrain")
	check(descriptor(variety_nodes(before))==descriptor(variety_nodes(fixture)),"Queued/direct construction differs")
	entry.placements=records.size();entry.placement_bytes_sha256=bytes_sha256(var_to_bytes(records));entry.planner_steps=work_units;entry.warm_planner_max_step_usec=job.max_step_usec
	entry.cpu_uploads_checked=records.size()*3
	inspect_uploads(arena,Transform3D(Basis(Vector3.UP,.71).scaled(Vector3(1.1,1.2,.9)),Vector3(641,8,-311)))
	report.arenas[arena]=entry
	fixture.free();before.free();game.free();baseline.free()


func audit_full_campaign_queues() -> void:
	var metrics:={}
	var game:=GameWorld.new();game.layout_version=5
	for arena:String in INNER_DISKS:
		var direct:=Node3D.new();var queued:=Node3D.new()
		root.add_child(direct);root.add_child(queued)
		game._build_arena(StringName(arena),direct)
		var job:=ArenaArt.plan(func() -> void:game._build_arena(StringName(arena),queued))
		check(variety_nodes(queued).is_empty(),"Full campaign planning eagerly attached variety")
		var steps:=0
		var deadline:=Time.get_ticks_msec()+10000
		while not job.step(2000,1):
			steps+=1
			if Time.get_ticks_msec()>deadline:
				check(false,"Full campaign queue deadline: " + arena);break
			if steps%100==0: await process_frame
		check(descriptor(variety_nodes(direct))==descriptor(variety_nodes(queued)),"Full production queued/direct variety differs: " + arena)
		check(physical_bytes(direct)==physical_bytes(queued),"Full production queued/direct physics differs: " + arena)
		check(terrain_bytes(direct)==terrain_bytes(queued),"Full production queued/direct terrain differs: " + arena)
		metrics[arena]={"steps":steps,"max_step_usec":job.max_step_usec}
		direct.free();queued.free()
	game.free()
	report.full_production_queued_sync_checked=metrics

func audit_cancelled_planners() -> void:
	for midway in [false,true]:
		var fixture:=Node3D.new();root.add_child(fixture)
		var job:=ArenaArt.plan(func() -> void:ArenaVarietyDressing.append(fixture,"quadratus"))
		var deadline:=Time.get_ticks_msec()+5000
		if midway:
			while variety_nodes(fixture).is_empty():
				job.step(2000,1)
				if Time.get_ticks_msec()>deadline:
					check(false,"Could not reach mid-upload cancellation");fixture.free();return
		fixture.free()
		while not job.step(2000,1):
			if Time.get_ticks_msec()>deadline:
				check(false,"Freed-parent queue did not finish");return
		check(job.cursor==job.jobs.size(),"Cancelled queue retained work")
	report.cancelled_before_and_during_upload_checked=true

func audit_opt_out() -> void:
	var game:=GameWorld.new();game.layout_version=5;game.with_art=false
	for arena:String in INNER_DISKS:
		var fixture:=Node3D.new();root.add_child(fixture)
		game._build_arena(StringName(arena),fixture)
		check(variety_nodes(fixture).is_empty(),"with_art=false gained variety")
		fixture.free()
	var fixture:=Node3D.new();root.add_child(fixture)
	ArenaVarietyDressing.append(fixture,"valus")
	check(fixture.get_child_count()==0 and ArenaVarietyDressing.sample("valus").is_empty(),"Unsupported arena is not a no-op")
	fixture.free();game.free()
	report.with_art_false_and_unsupported_arena_checked=true

func run() -> void:
	var began:=Time.get_ticks_usec()
	baseline_script=baseline_game_script()
	audit_legacy()
	for arena:String in INNER_DISKS: audit_arena(arena)
	await audit_full_campaign_queues()
	audit_cancelled_planners()
	audit_opt_out()
	var totals:={}
	for profile:String in PROFILES:
		var total:=0
		for entry:Dictionary in report.arenas.values(): total+=int(entry.profiles[profile].distance_selected_triangles.values().max())
		check(total<=SELECTED_TRIANGLE_LIMITS[profile],"Aggregate distance-selected triangle ceiling exceeded: " + profile)
		totals[profile]=total
	report.conservative_sum_of_arena_camera_maxima=totals
	report.total_placements=0;report.total_lod_nodes=0
	for entry:Dictionary in report.arenas.values(): report.total_placements+=entry.placements;report.total_lod_nodes+=entry.lod_nodes
	check(mesh_cache.size()==12,"Production three-arena integration does not exercise all 12 models")
	report.actual_imported_models=mesh_cache
	report.source_sha256={}
	for path:String in ["res://src/game/game_world.gd","res://src/world/arena_variety_dressing.gd","res://src/world/nature_variety_catalog.gd","res://data/environment/arena_variety_clearance.json","res://data/environment/nature_variety_catalog.json","res://data/environment/nature_variety_source_manifest.json"]:
		report.source_sha256[path]=FileAccess.get_sha256(path)
	report.failures=failures;report.elapsed_usec=Time.get_ticks_usec()-began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file:=FileAccess.open("res://tests/output/arena_variety_dressing.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "));file.close()
	print("ARENA_VARIETY_DRESSING: ",JSON.stringify(report))
	quit(1 if failures else 0)
