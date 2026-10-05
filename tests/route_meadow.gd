extends SceneTree
## Layout-five render dressing has deterministic coverage and bounded batch cost.
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var started := Time.get_ticks_usec()
	var count := 0
	var old_count := 0
	var cells := 0
	var kinds := {}
	var occupied := {}
	var minimum_distance := INF
	var max_chunk := 0
	var mesh_bounds := {}
	for z in range(-768, 256, 256):
		for x in range(0, 768, 256):
			var origin := Vector2i(x,z)
			var samples := EnvironmentGroundcover.sample_chunk(origin, {}, 5)
			check(var_to_bytes(samples) == var_to_bytes(EnvironmentGroundcover.sample_chunk(origin, {}, 5)), "Route meadow nondeterministic")
			var chunk_count := 0
			for cell in samples:
				for kind in samples[cell]:
					cells += 1
					for xf: Transform3D in samples[cell][kind]:
						count += 1
						chunk_count += 1
						kinds[kind] = kinds.get(kind,0) + 1
						if not mesh_bounds.has(kind):
							var merged := EnvironmentGroundcover.ASSET.mesh_for(kind,0).get_aabb()
							for lod in [1,2]: merged = merged.merge(EnvironmentGroundcover.ASSET.mesh_for(kind,lod).get_aabb())
							mesh_bounds[kind] = merged
						var bounds: AABB = xf * mesh_bounds[kind]
						check(not (bounds.position.x < 180 and bounds.end.x > -180 and bounds.position.z < 180 and bounds.end.z > -180), "Meadow mesh footprint breached protected shrine square")
						var p := Vector2(xf.origin.x,xf.origin.z)
						check(EnvironmentGroundcover.allowed(p,kind.begins_with("shrub_"),5,217.0 if kind.begins_with("shrub_") else 187.0,6.0),"Route meadow breached road/arena/slope clearance")
						check(absf(xf.origin.y-ForbiddenLandsTerrain.surface_height(p.x,p.y,5)+.035)<.001,"Route meadow floating")
						check(p.x>=x and p.x<x+256 and p.y>=z and p.y<z+256,"Meadow escaped chunk")
						var key := Vector2i(floori(p.x/EnvironmentGroundcover.ROUTE_SPACING),floori(p.y/EnvironmentGroundcover.ROUTE_SPACING))
						check(not occupied.has(key),"Duplicate meadow stratum")
						occupied[key] = p
			max_chunk = maxi(max_chunk,chunk_count)
			for layout in [1,2,3,4]:
				var legacy := EnvironmentGroundcover.sample_chunk(origin,{},layout)
				check(var_to_bytes(legacy) == var_to_bytes(EnvironmentGroundcover._sample_legacy(origin,{},layout)),"Historical sampler changed")
				if layout==4:
					for cell in legacy:
						for kind in legacy[cell]: old_count+=legacy[cell][kind].size()
	for key in occupied:
		for dz in range(-1,2):
			for dx in range(-1,2):
				var peer: Vector2i = key+Vector2i(dx,dz)
				if peer!=key and occupied.has(peer): minimum_distance=minf(minimum_distance,occupied[key].distance_to(occupied[peer]))
	check(count>old_count*12 and count>=6000 and count<35000,"Meadow coverage outside meaningful/bounded range")
	check(cells*3<=2400,"Route meadow batch budget exceeded")
	check(minimum_distance>=.59,"Meadow points too tightly packed")
	check(kinds.get("rock_02",0)>50,"Missing route rock scatter")
	ForbiddenLandsTerrain._materials()
	for profile in ["low", "balanced", "high"]:
		GraphicsQuality.apply(root, profile)
		check(ForbiddenLandsTerrain._terrain_mat.get_shader_parameter("low_detail") == (profile == "low"), "Ground material quality did not apply")
	GraphicsQuality.apply(root, "balanced")
	var report := {"failures":failures,"route_meadow_instances":count,"previous_route_instances":old_count,"density_multiplier":float(count)/maxi(old_count,1),"all_lod_batches":cells*3,"max_chunk_instances":max_chunk,"minimum_stratum_spacing_m":minimum_distance,"kinds":kinds,"sample_validation_usec":Time.get_ticks_usec()-started,"gpu_fps_measured":false}
	print("ROUTE_MEADOW: ",JSON.stringify(report))
	var file:=FileAccess.open("res://tests/output/route_meadow.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(1 if failures else 0)
