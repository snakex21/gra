extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	for kind in ["phoenix", "spider", "dormin"]:
		var arena := Node3D.new()
		root.add_child(arena)
		arena.position = Vector3(150, 4, -99)
		arena.rotation.y = .37
		var builder: Script = load("res://src/world/%s_arena.gd" % kind)
		var refs: Dictionary = builder.call("build_encounter", arena)
		GameWorld._disc_ground(arena)
		arena.process_mode = Node.PROCESS_MODE_DISABLED
		await process_frame
		var meshes := {}
		for mesh: MeshInstance3D in arena.find_children("*", "MeshInstance3D", true, false):
			meshes[mesh] = [mesh.mesh, mesh.material_override]
		var shapes := {}
		for shape: CollisionShape3D in arena.find_children("*", "CollisionShape3D", true, false):
			shapes[shape] = shape.shape
		ArenaGroundMaterials.append(arena, kind)
		ArenaArchitectureMaterials.append(arena, kind)
		var count := 0
		for mesh: MeshInstance3D in meshes:
			if mesh.has_meta("arena_ground_material") or mesh.has_meta("arena_architecture_material"):
				count += 1
		check(count == {"phoenix":9, "spider":7, "dormin":11}[kind], kind + " full encounter coating count")
		for cycle in 3:
			if kind == "spider":
				for anchor in refs.spider.anchors: anchor.try_hit(anchor.world_point(), 1.0, &"sword")
				refs.spider.route_open = true
				refs.spider.lowering = 1.0
			if kind == "dormin":
				for seal in refs.dormin.seals: seal._break()
			if kind == "phoenix":
				refs.phoenix._phase(Phoenix.Phase.COOLED)
				refs.phoenix.heat = 0.0
			refs.encounter.reset_encounter()
			await process_frame
			for mesh: MeshInstance3D in meshes:
				check(mesh.mesh == meshes[mesh][0], kind + " reset mesh identity")
				if mesh.has_meta("arena_ground_material"):
					check(mesh.material_override == ArenaGroundMaterials.material_for(kind), kind + " retained ground coating")
				elif mesh.has_meta("arena_architecture_material"):
					check(mesh.material_override == ArenaArchitectureMaterials.material_for(kind), kind + " retained structure coating")
				else:
					check(mesh.material_override == meshes[mesh][1], kind + " excluded live material identity")
			for shape: CollisionShape3D in shapes:
				check(shape.shape == shapes[shape], kind + " reset shape identity")
			if kind == "phoenix":
				check(refs.phoenix.phase == Phoenix.Phase.HOT and refs.phoenix.heat == 1.0, "Phoenix reset hot state")
			if kind == "spider":
				check(not refs.spider.route_open and refs.spider.lowering == 0, "Spider reset route closed")
				for anchor in refs.spider.anchors: check(not anchor.is_cut, "Spider anchor reset")
			if kind == "dormin":
				check(refs.dormin.seals_broken == 0 and not refs.dormin._climb_open, "Dormin reset locks closed")
				for seal in refs.dormin.seals: check(not seal.broken, "Dormin seal reset")
		arena.free()
		await process_frame
	print("LIVE_RESET_PROBE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
