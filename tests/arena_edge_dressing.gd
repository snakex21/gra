extends SceneTree
## CPU-authoritative imported geometry, campaign hook and render-only regression.
## Run: godot --headless --path . --script tests/arena_edge_dressing.gd
## Does not read dummy-renderer MultiMesh transform buffers or claim GPU/FPS cost.
const PROFILES := {"low": [.35,.7], "balanced": [.65,.85], "high": [1.0,1.0]}
const PLACEMENT_LIMIT := 650
const BATCH_LIMIT := 240 # Three LOD nodes per bounded cell/kind group.
const TRIANGLE_LIMITS := {"low": 230000, "balanced": 410000, "high": 620000}
var failures := 0
var report := {"arenas": {}, "legacy_layouts": [], "cost_scope": "CPU imported triangles, distance-selected batches, before frustum/occlusion; not GPU time"}
var mesh_cache := {}
var phalanx_carry_visual_bottom := INF

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
		var mesh := ArenaEdgeDressing.mesh_for(kind,lod)
		check(mesh != null, "Missing imported mesh: " + kind)
		if mesh == null: return {}
		check(mesh.get_surface_count()==1,"Multiple surfaces: " + kind)
		bounds = mesh.get_aabb() if lod==0 else bounds.merge(mesh.get_aabb())
		var count := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			count += int(indices.size()/3) if indices != null and not indices.is_empty() else int(arrays[Mesh.ARRAY_VERTEX].size()/3)
		triangles.append(count)
	check(triangles[0]>triangles[1] and triangles[1]>triangles[2],"LODs do not strictly reduce " + kind)
	mesh_cache[kind] = {"bounds": bounds, "triangles": triangles}
	return mesh_cache[kind]

func edge_nodes(fixture: Node3D) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for n: MultiMeshInstance3D in fixture.find_children("*","MultiMeshInstance3D",true,false):
		if n.has_meta(&"arena_edge_kind"): nodes.append(n)
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
	source = source.replace(cave_hook, "").replace(architecture_hook, "")
	var hook := "\n\tif layout_version == 5:\n\t\tArenaGroundMaterials.append(root, String(kind))\n\t\tArenaEdgeDressing.append(root, String(kind))\n"
	check(source.count(hook)==1,"Campaign gate must occur once and explicitly protect layouts 1–4")
	source = source.replace("class_name GameWorld\n","").replace(hook,"\n")
	var script := GDScript.new()
	script.source_code = source
	check(script.reload()==OK,"Unable to compile baseline campaign fixture")
	return script

func legacy_descriptor(fixture: Node3D) -> PackedByteArray:
	var rows := []
	for n: Node in fixture.find_children("*","",true,false):
		var row := [n.get_class()]
		if n is Node3D: row.append(n.transform)
		if n is MeshInstance3D:
			row.append([n.mesh.get_aabb(),n.visible,n.layers,n.material_override.resource_path if n.material_override else ""])
		if n is MultiMeshInstance3D:
			row.append([n.multimesh.instance_count,n.multimesh.mesh.get_aabb(),n.visibility_range_begin,n.visibility_range_end])
		rows.append(row)
	return var_to_bytes(rows)

func audit_legacy() -> void:
	var baseline_script := baseline_game_script()
	var current := GameWorld.new()
	var baseline: Node3D = baseline_script.new()
	for layout in [1,2,3,4]:
		current.layout_version=layout
		baseline.layout_version=layout
		for arena: String in ArenaEdgeDressing.CONFIG:
			var first := Node3D.new()
			var other := Node3D.new()
			root.add_child(first);root.add_child(other)
			current._build_arena(StringName(arena),first)
			baseline._build_arena(StringName(arena),other)
			check(edge_nodes(first).is_empty(),"Legacy layout gained dressing: %d/%s" % [layout,arena])
			check(physical_bytes(first)==physical_bytes(other),"Legacy physics changed: %d/%s" % [layout,arena])
			check(terrain_bytes(first)==terrain_bytes(other),"Legacy terrain vertices changed: %d/%s" % [layout,arena])
			check(legacy_descriptor(first)==legacy_descriptor(other),"Legacy art structure/material/LOD changed: %d/%s" % [layout,arena])
			first.free();other.free()
		report.legacy_layouts.append(layout)
	current.free();baseline.free()

func obstacle_bounds(fixture: Node3D) -> Array:
	var result := []
	for s: CollisionShape3D in fixture.find_children("*","CollisionShape3D",true,false):
		var b: AABB = fixture.global_transform.affine_inverse()*s.global_transform*s.shape.get_debug_mesh().get_aabb()
		# Keep tall authored obstacles, tree trunks and backdrop walls. Low rocks may
		# deliberately sit amid a colony, but no climb/camera passage may be buried.
		if b.end.y<=1.5 or maxf(b.size.x,b.size.z)>80: continue
		var owner_node := s.get_parent().get_parent()
		var label := str(owner_node.get("model_id")) if owner_node.get_script() else String(fixture.get_path_to(s))
		result.append([b, label + "@" + str(b.get_center())])
	return result

func footprint_distance(bounds: AABB, p: Vector2) -> float:
	return Vector2(maxf(maxf(bounds.position.x-p.x,p.x-bounds.end.x),0),maxf(maxf(bounds.position.z-p.y,p.y-bounds.end.z),0)).length()

func inspect_records(arena: String, records: Array, fixture: Node3D) -> Dictionary:
	var cfg: Dictionary = ArenaEdgeDressing.CONFIG[arena]
	var obstacles := obstacle_bounds(fixture)
	var starts := GameWorld.arena_starts(StringName(arena))
	var counts := {}
	var obstacles_hit := {}
	var rock_overlaps := {}
	var nearest_spawn := INF
	var minimum_radius := INF
	var maximum_radius := 0.0
	var approach_margin := INF
	for r: Dictionary in records:
		var xf: Transform3D = r.transform
		var b: AABB = xf*info(r.kind).bounds
		counts[r.kind]=int(counts.get(r.kind,0))+1
		minimum_radius=minf(minimum_radius,footprint_distance(b,Vector2.ZERO))
		if b.end.z>0:
			approach_margin=minf(approach_margin,minf(absf(b.position.x),absf(b.end.x))-22.0)
		check(footprint_distance(b,Vector2.ZERO)>=float(cfg.inner)-.001,"Full LOD footprint enters combat/water: " + arena)
		for x in [b.position.x,b.end.x]:
			for z in [b.position.z,b.end.z]:
				maximum_radius=maxf(maximum_radius,Vector2(x,z).length())
				check(Vector2(x,z).length()<=float(cfg.outer)+.001,"Full LOD footprint leaves rim: " + arena)
		check(not (b.end.z>0 and b.position.x<22 and b.end.x> -22),"Full footprint enters 44m approach: " + arena)
		for start: Vector3 in starts:
			var d := footprint_distance(b,Vector2(start.x,start.z))
			nearest_spawn=minf(nearest_spawn,d)
			check(d>=14,"Full footprint enters spawn/camera reserve: " + arena)
		var ground_node: Node3D = fixture.get_node("Ground")
		if arena=="basaran" and maxf(absf(xf.origin.x),absf(xf.origin.z))<=120: ground_node=fixture.get_node("VolcanicGround")
		var expected_y := -INF
		for visual: MeshInstance3D in ground_node.find_children("*","MeshInstance3D",false,false):
			var visual_bounds: AABB = fixture.global_transform.affine_inverse()*visual.global_transform*visual.mesh.get_aabb()
			expected_y=maxf(expected_y,visual_bounds.end.y)
		check(absf(xf.origin.y-(expected_y-.025))<.001,"Wrong actual arena floor Y: " + arena)
		for obstacle: Array in obstacles:
			var ob: AABB=obstacle[0]
			if b.position.x<ob.end.x+.2 and b.end.x>ob.position.x-.2 and b.position.z<ob.end.z+.2 and b.end.z>ob.position.z-.2:
				var overlaps: Dictionary = rock_overlaps if String(obstacle[1]).begins_with("rock_") and String(r.kind).begins_with("biome_") else obstacles_hit
				if not overlaps.has(obstacle[1]): overlaps[obstacle[1]]=[]
				overlaps[obstacle[1]].append({"kind":r.kind,"position":str(xf.origin),"bounds":str(b)})
	check(obstacles_hit.is_empty(),"Plants obscure existing tall collision footprints in %s: %s" % [arena,obstacles_hit])
	return {"kinds":counts,"minimum_footprint_radius_m":minimum_radius,"maximum_footprint_radius_m":maximum_radius,"extra_approach_clearance_m":approach_margin,"nearest_spawn_footprint_m":nearest_spawn,"tall_obstacle_overlaps":obstacles_hit,"permitted_legacy_rock_overlaps":rock_overlaps}

func descriptor(nodes: Array[MultiMeshInstance3D]) -> PackedByteArray:
	var rows := []
	for n in nodes:
		rows.append([n.name,n.transform,n.multimesh.instance_count,n.multimesh.custom_aabb,n.multimesh.mesh.get_rid()])
	return var_to_bytes(rows)

func inspect_batches(arena: String, records: Array, fixture: Node3D) -> Dictionary:
	var expected := ArenaEdgeDressing.batch_records(arena)
	var nodes := edge_nodes(fixture)
	check(nodes.size()==expected.size()*3,"Lost or extra LOD batches: " + arena)
	check(nodes.size()<=BATCH_LIMIT,"Arena exceeds batch ceiling: " + arena)
	var snapshots := descriptor(nodes)
	var profiles := {}
	for profile: String in PROFILES:
		GraphicsQuality.apply(fixture,profile)
		var visible := 0
		var costs := {"approach":0,"spawn":0,"edge":0}
		var starts:=GameWorld.arena_starts(StringName(arena))
		var cameras := {"approach":Vector3(0,3,162),"spawn":starts[0]+Vector3(0,2,7),"edge":Vector3(cfg_first(arena).x*.87,2,cfg_first(arena).y*.87)}
		for index in expected.size():
			var batch: Dictionary=expected[index]
			var landmark: bool=batch.kind.begins_with("rock_") or batch.kind.begins_with("ruin_")
			var population: int = batch.transforms.size() if landmark else maxi(1,ceili(batch.transforms.size()*PROFILES[profile][0]))
			visible+=population
			var shared:=AABB()
			for i in batch.transforms.size():
				var b: AABB=batch.transforms[i]*info(batch.kind).bounds
				shared=b if i==0 else shared.merge(b)
			var ranges:=ArenaEdgeDressing.ranges(batch.kind)
			for lod in 3:
				var n: MultiMeshInstance3D=nodes[index*3+lod]
				check(n.multimesh.instance_count==batch.transforms.size(),"Batch population differs from sampler")
				check(n.position.is_equal_approx(shared.get_center()),"All-LOD union visibility center differs")
				var global_bounds:=n.multimesh.custom_aabb;global_bounds.position+=n.position
				check(global_bounds.is_equal_approx(shared),"Shared AABB fails to enclose complete mesh footprints")
				check(n.multimesh.visible_instance_count==population,"Quality population mismatch")
				check(n.material_override==ArenaEdgeDressing.material_for(batch.kind),"Duplicated/wrong material")
				check(n.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Unexpected shadow draw")
				check(n.visibility_range_begin_margin==0 and n.visibility_range_end_margin==0,"LOD hysteresis can hide bands")
				check(is_equal_approx(n.visibility_range_begin,ranges[lod]*PROFILES[profile][1]) and is_equal_approx(n.visibility_range_end,ranges[lod+1]*PROFILES[profile][1]),"Quality ranges differ from production")
				for label: String in cameras:
					var distance: float=shared.get_center().distance_to(cameras[label])
					if distance>=n.visibility_range_begin and distance<n.visibility_range_end:
						costs[label]+=population*info(batch.kind).triangles[lod]
		check(descriptor(nodes)==snapshots,"Quality rebuilt/repositioned render instances")
		check(var_to_bytes(records)==var_to_bytes(ArenaEdgeDressing.sample(arena)),"Quality altered deterministic placements")
		profiles[profile]={"visible_placements":visible,"distance_selected_triangles":costs}
	check(profiles.low.visible_placements<profiles.balanced.visible_placements and profiles.balanced.visible_placements<profiles.high.visible_placements,"Quality does not reduce colony population")
	return {"lod_nodes":nodes.size(),"groups":expected.size(),"profiles":profiles}

func cfg_first(arena: String) -> Vector2:
	return ArenaEdgeDressing.CONFIG[arena].centers[0]

func inspect_uploads(arena: String, world_xf: Transform3D) -> void:
	# Record the production CPU upload arguments in memory. Dummy rendering does
	# not retain buffers; a synthetic GPU readback would falsely report identity.
	var source:=FileAccess.get_file_as_string("res://src/world/arena_edge_dressing.gd")
	var sink:="mm.set_instance_transform(i,xf)"
	check(source.count(sink)==1,"Cannot locate the unique production transform upload")
	source=source.replace("class_name ArenaEdgeDressing\n","")
	source=source.replace(sink,sink+"\n  captured.append([int(state.batch),int(state.lod),i,xf])")
	source+="\nstatic var captured := []\n"
	var script:=GDScript.new();script.source_code=source
	check(script.reload()==OK,"CPU transform upload instrument did not compile")
	var fixture:=Node3D.new();root.add_child(fixture);fixture.transform=world_xf
	script.append(fixture,arena)
	var batches:=ArenaEdgeDressing.batch_records(arena)
	var nodes:=edge_nodes(fixture)
	var expected_count:=0
	for batch:Dictionary in batches:expected_count+=batch.transforms.size()*3
	check(script.captured.size()==expected_count,"Actual uploads lost or duplicated placements")
	for call:Array in script.captured:
		var batch:Dictionary=batches[call[0]]
		var node:MultiMeshInstance3D=nodes[call[0]*3+call[1]]
		var uploaded:Transform3D=call[3]
		var expected:Transform3D=batch.transforms[call[2]]
		check((node.global_transform*uploaded).is_equal_approx(world_xf*expected),"Actual CPU upload changes pose under translated/rotated arena")
	fixture.free()

func audit_arena(arena: String) -> void:
	var game:=GameWorld.new();game.layout_version=4
	var fixture:=Node3D.new();root.add_child(fixture)
	game._build_arena(StringName(arena),fixture)
	var physics_before:=physical_bytes(fixture)
	var terrain_before:=terrain_bytes(fixture)
	var records:=ArenaEdgeDressing.sample(arena)
	var landmarks:=ArenaEdgeDressing.landmark_records(arena)
	check(landmarks.size()==20,"Each arena must retain five complete four-prop landmark groups: " + arena)
	check(var_to_bytes(records.slice(records.size()-20))==var_to_bytes(landmarks),"Landmark records missing or duplicated in sampler: " + arena)
	var landmark_heights:=[]
	for landmark:Dictionary in landmarks:
		var landmark_bounds:AABB=landmark.transform*info(landmark.kind).bounds
		landmark_heights.append(landmark_bounds.size.y)
		if arena=="phalanx":
			check(landmark_bounds.end.y<7.5,"Phalanx landmark exceeds side/front silhouette ceiling")
			if landmark_bounds.position.z< -100:
				# The V3 imported sac sculpture hangs below the 4m collider.
				# Compare every LOD with both extreme CARRY rolls, not physics only.
				check(landmark_bounds.end.y<5.0,"Rear Phalanx landmark exceeds lower flight-path cap")
				check(phalanx_carry_visual_bottom-landmark_bounds.end.y>.75,"Rear Phalanx landmark obscures imported CARRY body/sac sculpture")
		# Every group intentionally includes low foot scree; the three other
		# accents must remain substantial silhouettes rather than tiny props.
		check(landmark_bounds.size.y>=(.8 if landmark.kind=="rock_scree_cluster" else (2.5 if String(landmark.kind).begins_with("ruin_") else 3.0)),"Landmark silhouette lost its authored scale: " + arena)
	check(float(landmark_heights.max())>=4.5,"Arena lacks a substantial landmark silhouette: " + arena)
	check(records.size()>=180 and records.size()<=PLACEMENT_LIMIT,"Placement growth outside 180–650 per-arena budget: " + arena)
	check(var_to_bytes(records)==var_to_bytes(ArenaEdgeDressing.sample(arena)),"Sampling changed on rebuild")
	var entry:=inspect_records(arena,records,fixture)
	var job:=ArenaArt.plan(func() -> void: ArenaEdgeDressing.append(fixture,arena))
	check(edge_nodes(fixture).is_empty(),"Planning eagerly attached edge art")
	var work_units:=0
	var waiting_frames:=0
	var deadline:=Time.get_ticks_msec()+2000
	while not job.step(2000,1):
		work_units+=1
		if Time.get_ticks_msec()>deadline:
			check(false,"Planner exceeded two-second fixture deadline: " + arena)
			fixture.free();game.free();quit(1);return
		# The production streamer polls background atlas decoding once per tick.
		# Give the worker a frame rather than interpreting tight-loop polls as
		# expensive work units or blocking on load_threaded_get prematurely.
		var material_pending:=false
		for path:String in ArenaEdgeDressing._material_requests:
			if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				material_pending=true
		if material_pending:
			waiting_frames+=1
			await process_frame
	check(job.max_step_usec<10000,"One render-only work unit blocked over 10ms: " + arena)
	check(work_units>30,"Build lost bounded incremental work")
	check(physical_bytes(fixture)==physics_before,"Dressing changed actual collider shapes/transforms/layers")
	check(terrain_bytes(fixture)==terrain_before,"Dressing changed terrain triangles/transforms")
	entry.merge(inspect_batches(arena,records,fixture))
	entry.placements=records.size();entry.landmarks=landmarks.size();entry.landmark_heights_m=landmark_heights;entry.planner_steps=work_units;entry.max_step_usec=job.max_step_usec
	entry.material_wait_frames=waiting_frames
	# Translation/yaw belongs to the root, never the local placement document.
	fixture.transform=Transform3D(Basis(Vector3.UP,.71),Vector3(641,8,-311))
	check(var_to_bytes(records)==var_to_bytes(ArenaEdgeDressing.sample(arena)),"Moved arena regenerated local dressing")
	var direct:=Node3D.new();root.add_child(direct)
	game.layout_version=5
	game._build_arena(StringName(arena),direct)
	check(descriptor(edge_nodes(direct))==descriptor(edge_nodes(fixture)),"Incremental/direct construction differs")
	inspect_uploads(arena,fixture.transform)
	report.arenas[arena]=entry
	fixture.free();direct.free();game.free()

func audit_cancelled_planners() -> void:
	for midway in [false,true]:
		var fixture:=Node3D.new();root.add_child(fixture)
		var job:=ArenaArt.plan(func() -> void:ArenaEdgeDressing.append(fixture,"valus"))
		var deadline:=Time.get_ticks_msec()+5000
		if midway:
			while edge_nodes(fixture).is_empty():
				job.step(2000,1)
				if Time.get_ticks_msec()>deadline:
					check(false,"Could not reach mid-upload cancellation fixture")
					fixture.free();return
				await process_frame
		fixture.free()
		while not job.step(2000,1):
			if Time.get_ticks_msec()>deadline:
				check(false,"Freed-parent edge planner did not complete")
				return
			await process_frame
		check(job.cursor==job.jobs.size(),"Cancelled edge queue retained unfinished work")
	report.cancelled_before_and_during_upload_checked=true

func audit_default_world_ranges() -> void:
	var count:=0
	for spec in [["grass_tuft",false,false],["shrub_salt",false,false],["grass_meadow_soft",true,false],["shrub_meadow",true,false],["biome_fern",false,false],["rock_layered_shelf",false,true]]:
		for lod in 3:
			var node:=MultiMeshInstance3D.new()
			node.multimesh=MultiMesh.new();node.multimesh.mesh=BoxMesh.new();node.multimesh.instance_count=10
			node.set_meta(&"groundcover_kind",spec[0]);node.set_meta(&"groundcover_lod",lod)
			node.set_meta(&"route_meadow",spec[1]);node.set_meta(&"authored_landmark",spec[2])
			check(not node.has_meta(&"groundcover_ranges"),"World range fixture unexpectedly opts into arena ranges")
			var original:=EnvironmentGroundcover.quality_ranges(spec[0],spec[1],spec[2])
			for profile:String in PROFILES:
				EnvironmentGroundcover.apply_quality(node,profile)
				check(is_equal_approx(node.visibility_range_begin,original[lod]*PROFILES[profile][1]) and is_equal_approx(node.visibility_range_end,original[lod+1]*PROFILES[profile][1]),"Arena range hook changed ordinary world LOD: " + spec[0])
				check(node.multimesh.visible_instance_count==(10 if spec[2] else ceili(10*PROFILES[profile][0])),"Arena range hook changed ordinary world density")
				count+=1
			node.free()
	report.original_world_range_profile_cases=count

func audit_phalanx_visual_envelope() -> void:
	# phalanx.gd CARRY approaches center y=10 and _pose_bones rolls ±.035rad.
	# ColossusArtV3 mounts these imported GLBs on the existing unscaled bones.
	for segment in 3:
		for lod in 3:
			var mesh:Mesh=ColossusArtV3.Asset.mesh_for("phalanx_body%d"%segment,lod,"colossi_v3")
			check(mesh!=null,"Missing imported Phalanx flight-envelope mesh")
			if mesh==null:continue
			for roll in [-.035,0.0,.035]:
				var envelope:AABB=Transform3D(Basis(Vector3.BACK,roll),Vector3(0,10,0))*mesh.get_aabb()
				phalanx_carry_visual_bottom=minf(phalanx_carry_visual_bottom,envelope.position.y)
	check(phalanx_carry_visual_bottom>5.5 and phalanx_carry_visual_bottom<6.0,"Imported Phalanx visual flight envelope changed; recheck landmark clearance")
	report.phalanx_imported_carry_visual_bottom_m=phalanx_carry_visual_bottom

func run() -> void:
	var began:=Time.get_ticks_usec()
	audit_legacy()
	audit_phalanx_visual_envelope()
	for arena: String in ArenaEdgeDressing.CONFIG: await audit_arena(arena)
	await audit_cancelled_planners()
	audit_default_world_ranges()
	var totals:={}
	for profile: String in PROFILES:
		var sum_max:=0
		for arena: String in report.arenas:
			var costs: Dictionary=report.arenas[arena].profiles[profile].distance_selected_triangles
			sum_max+=int(costs.values().max())
		check(sum_max<=TRIANGLE_LIMITS[profile],"Added arena layer triangle ceiling exceeded: " + profile)
		totals[profile]=sum_max
	report.conservative_sum_of_arena_camera_maxima=totals
	report.total_placements=0;report.total_lod_nodes=0
	for entry:Dictionary in report.arenas.values():
		report.total_placements+=entry.placements
		report.total_lod_nodes+=entry.lod_nodes
	report.failures=failures;report.elapsed_usec=Time.get_ticks_usec()-began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file:=FileAccess.open("res://tests/output/arena_edge_dressing.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "));file.close()
	print("ARENA_EDGE_DRESSING: ",JSON.stringify(report))
	quit(1 if failures else 0)
