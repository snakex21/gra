extends "res://tests/arena_variety_dressing.gd"
## Additional campaign arenas. Keeps the original three-arena regression and
## its budgets intact; shares its independent upload/resource/LOD audit methods.
## godot --headless --path . --script tests/next_arena_dressing.gd
const NEXT_ARENAS := {"kuromori":90.0,"pelagia":84.0,"argus":86.0}
const NEXT_SELECTED_TRIANGLE_LIMITS := {"low":110000,"balanced":180000,"high":300000}
const PRIOR_PLACEMENT_HASHES := {
	"quadratus":"5063c28e2a7f25614014f92f25596feac2ed639565cca6659cff7a4bddd696ba",
	"phaedra":"1d187e45c836de10a37b47c4b309d23a2a208e7aec54a044a55c4c55af33da6a",
	"avion":"ec8de459dc94926f17721a0a79ff9dfac01c507c701975e76694ac44715b5aaf"
}
const PRESERVED_SOURCES := {
	"src/world/arena_edge_dressing.gd":"973889a1a3fd29023a1e861d0374cf5374c9dbb4c193ee5bb8fa2dd71cd406c8",
	"src/world/environment_groundcover.gd":"fd5038a2b71b6d0e7b6773c01348dc7c87e340c8407d49c3509dd5727bfcd982",
	"src/world/forbidden_lands.gd":"2198890d37dfa89dadfd1ac2a5e8ed21f371f71a06e1f81acc13d0947cf03837"
}

func live_obstacles(fixture: Node3D) -> Array:
	var result := []
	for shape: CollisionShape3D in fixture.find_children("*","CollisionShape3D",true,false):
		# The actual Ground body is the only exclusion, irrespective of collider
		# height, size, class, hierarchy or whether it can move during a puzzle.
		if shape.get_parent() == fixture.get_node("Ground"): continue
		var b: AABB = fixture.global_transform.affine_inverse()*shape.global_transform*shape.shape.get_debug_mesh().get_aabb()
		result.append([b,String(fixture.get_path_to(shape))])
	return result

func audit_source_and_prior() -> void:
	var preserved := {}
	for arena: String in PRIOR_PLACEMENT_HASHES:
		var actual := bytes_sha256(var_to_bytes(ArenaVarietyDressing.sample(arena)))
		check(actual == PRIOR_PLACEMENT_HASHES[arena],"Previous Nature Variety placements changed: " + arena)
		preserved[arena] = actual
	for path: String in PRESERVED_SOURCES:
		check(FileAccess.get_sha256("res://"+path)==PRESERVED_SOURCES[path],"Prior four edge arenas or dense world-biome source changed: " + path)
	var clearance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ArenaVarietyDressing.CLEARANCE_PATH))
	for path: String in clearance.next_arena_sources:
		check(FileAccess.get_sha256("res://"+path)==clearance.next_arena_sources[path],"Encounter changed since complete envelope audit: " + path)
	check(not ArenaVarietyDressing.CONFIG.has("barba"),"Barba unrestricted pursuit must not gain static feature islands")
	check(not clearance.arenas.has("barba"),"Removed Barba exclusions must not remain in the new clearance set")
	check(PelagiaArena.WATER_RADIUS==60 and Pelagia.RUINS_LOCAL==[Vector3(-24,0,-8),Vector3(0,0,-29),Vector3(24,0,-8)],"Pelagia water or steering goals changed")
	var argus_source := FileAccess.get_file_as_string("res://src/colossus/argus/argus.gd")
	check(argus_source.contains("desired_speed = 0.0\n\tdesired_turn = 0.0"),"Argus stationary guardian contract changed; re-audit full motion envelope")
	report.previous_variety_placement_sha256 = preserved
	report.preserved_edge_and_world_source_sha256 = PRESERVED_SOURCES

func assert_no_intersection(arena: String, records: Array, obstacles: Array) -> void:
	for row: Dictionary in records:
		var bounds: AABB = row.transform*info(row.kind).bounds
		var footprint := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
		for entry: Array in obstacles:
			var b: AABB = entry[0]
			check(not footprint.intersects(Rect2(Vector2(b.position.x,b.position.z),Vector2(b.size.x,b.size.z)).grow(.2),true),"Complete mesh touches actual obstacle: " + arena + "/" + entry[1])

func inspect_next_records(arena: String, records: Array, fixture: Node3D) -> Dictionary:
	var cfg: Dictionary = ArenaVarietyDressing.CONFIG[arena]
	check(cfg.inner==NEXT_ARENAS[arena],"Protected encounter disk changed: " + arena)
	var clearance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ArenaVarietyDressing.CLEARANCE_PATH))
	var authored: Array = clearance.arenas[arena]
	var obstacles := live_obstacles(fixture)
	var baseline_count := obstacles.size()
	if arena == "argus":
		var ruins: ArgusRuins = fixture.get_node("ArgusRuins")
		# Check more sweep states than the bake uses; all records must avoid the
		# actual collider at each state, including 0.125/0.375/0.625/0.875.
		for weight in [.125,.25,.375,.5,.625,.75,.875,1.0]:
			ruins.weight=weight;ruins._refresh()
			var live := live_obstacles(fixture)
			assert_no_intersection(arena,records,live)
			if weight in [.25,.5,.75,1.0]:
				for row: Array in live:
					if String(row[1]).contains("HingedGalleryRamp"): obstacles.append(row)
			# Entire analytic footprint of the ramp's continuous sweep lies inside
			# the protected disk, not merely the sampled AABBs.
			var analytic := AABB(Vector3(14.5,-1.2,-7.0),Vector3(7,14,52))
			for r: Dictionary in records:
				var b: AABB=r.transform*info(r.kind).bounds
				check(not Rect2(Vector2(b.position.x,b.position.z),Vector2(b.size.x,b.size.z)).intersects(Rect2(Vector2(analytic.position.x,analytic.position.z),Vector2(analytic.size.x,analytic.size.z)),true),"Argus full ramp sweep entered")
			ruins.weight=0;ruins._refresh()
	check(authored.size()==obstacles.size(),"Baked exclusions differ from all actual collision shapes: "+arena)
	for actual: Array in obstacles:
		var found := false
		for record: Dictionary in authored:
			var p: Array=record.position;var s: Array=record.size
			if AABB(Vector3(p[0],p[1],p[2]),Vector3(s[0],s[1],s[2])).is_equal_approx(actual[0]): found=true;break
		check(found,"Baked exclusion missing actual obstacle or moving state: "+arena+"/"+actual[1])
	assert_no_intersection(arena,records,obstacles)
	var counts := {};var patch_counts := []
	var nearest := INF;var maximum := 0.0;var nearest_start := INF;var tallest := 0.0
	var large := 0;var large_area := 0.0
	var ground_top := -INF
	for visual: MeshInstance3D in fixture.get_node("Ground").find_children("*","MeshInstance3D",false,false):
		var b: AABB=fixture.global_transform.affine_inverse()*visual.global_transform*visual.mesh.get_aabb()
		ground_top=maxf(ground_top,b.end.y)
	for r: Dictionary in records:
		var b: AABB=r.transform*info(r.kind).bounds
		counts[r.kind]=int(counts.get(r.kind,0))+1
		nearest=minf(nearest,footprint_distance(b,Vector2.ZERO));tallest=maxf(tallest,b.size.y)
		check(footprint_distance(b,Vector2.ZERO)>=float(cfg.inner)-.001,"Mesh enters encounter/water/climb reserve: "+arena)
		for x in [b.position.x,b.end.x]:
			for z in [b.position.z,b.end.z]:
				maximum=maxf(maximum,Vector2(x,z).length())
				check(Vector2(x,z).length()<=float(cfg.outer)+.001,"Mesh leaves safe disc: "+arena)
		check(not (b.end.z>0 and b.position.x<24 and b.end.x> -24),"Mesh enters full 48m entrance corridor: "+arena)
		for p: Vector3 in GameWorld.arena_starts(StringName(arena)):
			nearest_start=minf(nearest_start,footprint_distance(b,Vector2(p.x,p.z)))
			check(footprint_distance(b,Vector2(p.x,p.z))>=14,"Mesh enters player/horse/camera spawn reserve: "+arena)
		check(absf(b.position.y-(ground_top-.015))<.001,"Mesh not grounded on actual floor: "+arena)
		if arena=="pelagia":
			check(footprint_distance(b,Vector2.ZERO)>PelagiaArena.WATER_RADIUS+20,"Mesh crowds swimming/shore exit path")
			check(is_zero_approx(PelagiaArena.ground_height(b.position.x,b.position.z)),"Mesh not on flat Pelagia dry bank")
		if not String(r.kind).begins_with("plant_"):
			large+=1;large_area+=b.size.x*b.size.z
			check(maxf(b.size.x,b.size.z)>5,"A counted landmark is merely a small prop: "+arena+"/"+r.kind)
	check(counts.size()==cfg.kinds.size(),"Arena lost configured Nature Variety kinds: "+arena)
	check(large==42,"Arena lost a complete seven-stone feature island: "+arena)
	check(tallest>=7.0,"Arena lacks substantial vertical silhouette: "+arena)
	check(large_area>1200,"Arena landmark footprint is too small: "+arena)
	for index in cfg.centers.size():
		var state := {"arena":arena,"cursor":index,"records":[]}
		ArenaVarietyDressing._sample_step(state)
		var landmarks := 0
		for row: Dictionary in state.records:
			if not String(row.kind).begins_with("plant_" ): landmarks+=1
		check(landmarks==7 and state.records.size()>=40,"Incomplete feature island: "+arena+"/%d"%index)
		patch_counts.append({"landmarks":landmarks,"plants":state.records.size()-landmarks})
	return {"kinds":counts,"island_populations":patch_counts,"large_landmarks":large,"summed_landmark_aabb_area_m2":large_area,"maximum_height_m":tallest,"minimum_footprint_radius_m":nearest,"maximum_footprint_radius_m":maximum,"nearest_spawn_footprint_m":nearest_start,"actual_obstacle_count":baseline_count,"exclusion_count_with_moving_states":obstacles.size(),"ground_top_y":ground_top,"actual_obstacle_intersections":0,"combat_scope":"Complete static gameplay footprint and bounded boss/body/climb paths. Kuromori poison may target a player anywhere; no arbitrary poison-target separation claim."}

func audit_next_arena(arena: String) -> void:
	var game:=GameWorld.new();game.layout_version=5
	var baseline:Node3D=baseline_script.new();baseline.layout_version=5
	var fixture:=Node3D.new();var before:=Node3D.new()
	root.add_child(fixture);root.add_child(before)
	baseline._build_arena(StringName(arena),before)
	var physics_before:=physical_bytes(before);var terrain_before:=terrain_bytes(before)
	game._build_arena(StringName(arena),fixture)
	check(physical_bytes(fixture)==physics_before,"Layout-5 physical collider data changed: "+arena)
	check(terrain_bytes(fixture)==terrain_before,"Layout-5 floor geometry changed: "+arena)
	check(legacy_descriptor(fixture)==legacy_descriptor(before),"Existing arena art changed: "+arena)
	var records:=ArenaVarietyDressing.sample(arena)
	check(records.size()>=260 and records.size()<=282,"Bounded feature population outside 260–282: "+arena)
	check(var_to_bytes(records)==var_to_bytes(ArenaVarietyDressing.sample(arena)),"Non-deterministic rebuild: "+arena)
	var entry:=inspect_next_records(arena,records,fixture)
	entry.merge(inspect_batches(arena,records,fixture))
	var job:=ArenaArt.plan(func() -> void:ArenaVarietyDressing.append(before,arena))
	check(variety_nodes(before).is_empty(),"Planning eagerly adds features: "+arena)
	var steps:=0;var deadline:=Time.get_ticks_msec()+10000
	while not job.step(2000,1):
		steps+=1
		if Time.get_ticks_msec()>deadline: check(false,"Queue timeout: "+arena);break
	check(steps>30,"Queue lost bounded incremental work: "+arena)
	check(descriptor(variety_nodes(before))==descriptor(variety_nodes(fixture)),"Direct/queued builds differ: "+arena)
	check(physical_bytes(before)==physics_before and terrain_bytes(before)==terrain_before,"Queued art changes gameplay geometry: "+arena)
	inspect_uploads(arena,Transform3D(Basis(Vector3.UP,.71).scaled(Vector3(1.1,1.2,.9)),Vector3(641,8,-311)))
	entry.placements=records.size();entry.placement_sha256=bytes_sha256(var_to_bytes(records));entry.planner_steps=steps;entry.max_step_usec=job.max_step_usec;entry.cpu_uploads_checked=records.size()*3
	report.arenas[arena]=entry
	fixture.free();before.free();game.free();baseline.free()

func audit_kuromori_body_envelope() -> void:
	var fixture:=Node3D.new();root.add_child(fixture)
	var boss:=Kuromori.new();boss.effects_enabled=false;boss.position=KuromoriArena.KUROMORI_START
	fixture.add_child(boss);boss.set_physics_process(false);boss.reset_encounter()
	var rows:=ArenaVarietyDressing.sample("kuromori")
	var wall:=Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3(0,9,-21))
	var belly:=Transform3D(Basis(Vector3.RIGHT,PI),Vector3(0,1.6,-6))
	var phases:=[[Kuromori.Phase.DORMANT,1.0,wall],[Kuromori.Phase.CRAWL,4.0,wall],[Kuromori.Phase.CLIMB_WALL,3.0,wall],[Kuromori.Phase.ON_WALL,22.0,wall],[Kuromori.Phase.FALL,2.0,wall],[Kuromori.Phase.BELLY,24.0,belly],[Kuromori.Phase.RECOVER,3.0,belly],[Kuromori.Phase.RECOVER,3.0,wall],[Kuromori.Phase.DEFEATED,1.0,belly]]
	var largest_radius:=0.0;var poses:=0;var shapes_checked:=0
	# Every body/climb shape has a rotation-invariant enclosing sphere. The
	# maximum source sphere plus the home-relative origin interval is a complete
	# bound for continuous phase interpolation, in addition to live pose samples.
	var local_radius:=0.0
	for shape: CollisionShape3D in boss._body.find_children("*","CollisionShape3D",true,false):
		var local: AABB=shape.transform*shape.shape.get_debug_mesh().get_aabb()
		for x in [local.position.x,local.end.x]:
			for y in [local.position.y,local.end.y]:
				for z in [local.position.z,local.end.z]: local_radius=maxf(local_radius,Vector3(x,y,z).length())
	check(21.0+local_radius<90.0,"Kuromori complete continuous body envelope exceeds protected disk")
	for phase: Array in phases:
		for i in 41:
			boss.phase=phase[0];boss.phase_time=float(phase[1])*float(i)/40.0;boss._start_pose=phase[2]
			boss._execute_intent(ColossusIntent.make(ColossusIntent.IDLE),0.0);boss._sync_segments()
			var actual:=[]
			for segment: BodySegment in boss.segments:
				for shape: CollisionShape3D in segment.find_children("*","CollisionShape3D",true,false):
					var b: AABB=segment.target_transform*shape.transform*shape.shape.get_debug_mesh().get_aabb()
					actual.append([b,"Kuromori body/climb phase %d sample %d"%[phase[0],i]])
					for x in [b.position.x,b.end.x]:
						for z in [b.position.z,b.end.z]:largest_radius=maxf(largest_radius,Vector2(x,z).length())
					shapes_checked+=1
			assert_no_intersection("kuromori",rows,actual);poses+=1
	check(largest_radius<35.0,"Kuromori actual home-relative motion envelope expanded")
	report.kuromori_body_motion={"poses_checked":poses,"body_and_climb_shapes_checked":shapes_checked,"max_actual_aabb_corner_radius_m":largest_radius,"continuous_rotation_invariant_radius_m":21.0+local_radius,"protected_radius_m":90.0,"poison_limit":"Poison follows a player at arbitrary range. These tests prove body/climb and authored-route separation, not arbitrary exterior poison warning visibility."}
	fixture.free()

func audit_next_full_queues() -> void:
	var game:=GameWorld.new();game.layout_version=5
	var metrics:={}
	for arena: String in NEXT_ARENAS:
		var a:=Node3D.new();var b:=Node3D.new();root.add_child(a);root.add_child(b)
		game._build_arena(StringName(arena),a)
		var job:=ArenaArt.plan(func() -> void:game._build_arena(StringName(arena),b))
		check(variety_nodes(b).is_empty(),"Full arena planner attaches features eagerly")
		var steps:=0;var deadline:=Time.get_ticks_msec()+10000
		while not job.step(2000,1):
			steps+=1
			if Time.get_ticks_msec()>deadline:check(false,"Full arena queue exceeded timeout");break
			if steps%100==0:await process_frame
		check(descriptor(variety_nodes(a))==descriptor(variety_nodes(b)),"Full queued/direct features differ")
		check(physical_bytes(a)==physical_bytes(b) and terrain_bytes(a)==terrain_bytes(b),"Full queued/direct geometry differs")
		metrics[arena]={"steps":steps,"max_step_usec":job.max_step_usec}
		a.free();b.free()
	game.free();report.full_production_queued_sync_checked=metrics
	for arena: String in NEXT_ARENAS:
		for midway in [false,true]:
			var fixture:=Node3D.new();root.add_child(fixture)
			var job:=ArenaArt.plan(func() -> void:ArenaVarietyDressing.append(fixture,arena))
			if midway:
				while variety_nodes(fixture).is_empty():job.step(2000,1)
			fixture.free()
			while not job.step(2000,1):pass
			check(job.cursor==job.jobs.size(),"Cancelled next-arena queue retains work")
	report.all_next_arenas_cancelled_before_and_during_upload_checked=true

func audit_next_scope() -> void:
	var game:=GameWorld.new();var old:Node3D=baseline_script.new()
	for layout in [1,2,3,4,5]:
		game.layout_version=layout;old.layout_version=layout
		game.with_art=layout!=5;old.with_art=layout!=5
		for arena: String in NEXT_ARENAS:
			var a:=Node3D.new();var b:=Node3D.new();root.add_child(a);root.add_child(b)
			game._build_arena(StringName(arena),a);old._build_arena(StringName(arena),b)
			check(variety_nodes(a).is_empty(),"Old layout/art opt-out gains new features")
			check(physical_bytes(a)==physical_bytes(b) and terrain_bytes(a)==terrain_bytes(b) and legacy_descriptor(a)==legacy_descriptor(b),"Old layout/art opt-out changed")
			a.free();b.free()
	game.free();old.free()
	report.layouts_1_to_4_and_with_art_false_unchanged=true

func audit_next_fail_closed() -> void:
	var source:=FileAccess.get_file_as_string("res://src/world/arena_variety_dressing.gd")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ArenaVarietyDressing.CLEARANCE_PATH))
	var rows:={}
	for arena: String in NEXT_ARENAS:
		for fault: String in ["missing","empty","invalid"]:
			var bad:=base.duplicate(true)
			if fault=="missing":bad.arenas.erase(arena)
			elif fault=="empty":bad.arenas[arena]=[]
			else:bad.arenas[arena]=[{"position":[0,0,0],"size":[0,2,2]}]
			var path:="res://tests/output/next_clearance_fault_"+arena+"_"+fault+".json"
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(bad));file.close()
			var script:=GDScript.new();script.source_code=source.replace("class_name ArenaVarietyDressing\n","").replace(ArenaVarietyDressing.CLEARANCE_PATH,path)
			check(script.reload()==OK,"Fail-closed fixture does not compile")
			var parent:=Node3D.new();root.add_child(parent)
			script.append(parent,arena)
			var ok:bool=script.sample(arena).is_empty() and script.sample("quadratus").is_empty() and script._obstacles.is_empty() and parent.get_child_count()==0
			check(ok,"Missing/malformed next-arena data permits a partial usable cache")
			rows[arena+"_"+fault]=ok;parent.free()
	report.new_exclusions_fail_closed=rows

func run() -> void:
	var began:=Time.get_ticks_usec()
	baseline_script=baseline_game_script()
	audit_source_and_prior()
	audit_next_scope()
	for arena: String in NEXT_ARENAS: audit_next_arena(arena)
	audit_kuromori_body_envelope()
	await audit_next_full_queues()
	audit_next_fail_closed()
	var totals:={}
	for profile: String in NEXT_SELECTED_TRIANGLE_LIMITS:
		var cost:=0
		for entry: Dictionary in report.arenas.values(): cost+=int(entry.profiles[profile].distance_selected_triangles.values().max())
		check(cost<=NEXT_SELECTED_TRIANGLE_LIMITS[profile],"Combined next-arena selected triangle budget exceeded: "+profile)
		totals[profile]=cost
	check(mesh_cache.size()==12,"New integrated arenas do not exercise all twelve original shared models")
	report.conservative_sum_of_arena_camera_maxima=totals
	report.failures=failures;report.elapsed_usec=Time.get_ticks_usec()-began
	var file:=FileAccess.open("res://tests/output/next_arena_dressing.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("NEXT_ARENA_DRESSING: ",JSON.stringify(report))
	quit(1 if failures else 0)
