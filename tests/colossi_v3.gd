extends Node
const KINDS := ["valus", "quadratus", "gaius", "phaedra", "avion", "barba", "hydrus", "kuromori", "basaran", "dirge", "celosia_cenobia", "pelagia", "phalanx", "argus", "malus", "devil", "phoenix", "spider", "worm", "saru"]
var failures := 0
var report := {"contracts": [], "fights": []}

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	_geometry()
	for kind: String in KINDS:
		_contract(kind)
	check(report.contracts.size() == KINDS.size(), "Some model contracts did not run")
	if not OS.get_cmdline_user_args().has("--contracts-only"):
		for kind: String in KINDS:
			if OS.get_cmdline_user_args().is_empty() or OS.get_cmdline_user_args().has(kind):
				await _fight(StringName(kind))
	var file := FileAccess.open("res://art/reports/colossi_v3/runtime.json", FileAccess.WRITE)
	report["failures"] = failures
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("Colossi V3: %d failures; %d physics contracts; %d dressed fights" % [failures, report.contracts.size(), report.fights.size()])
	get_tree().quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _geometry() -> void:
	ColossusArtV3._load_manifest()
	var manifest: Dictionary = ColossusArtV3._manifest
	check(manifest.profiles.size() == 21, "Expected twenty-one distinct body profiles")
	for kind: String in manifest.profiles:
		check(manifest.profiles[kind].lod_triangles[0] <= 50000, kind + " exceeds near geometry budget")
	for entry: Dictionary in manifest.assets:
		var last := 1000000
		for level in 3:
			var mesh: Mesh = ColossusArtV3.Asset.mesh_for(entry.id, level, "colossi_v3")
			var triangles := 0
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			check(triangles == int(entry.lod_triangles[level]), entry.id + " triangle count mismatch")
			check(triangles > 0 and triangles < last, entry.id + " LOD did not reduce geometry")
			last = triangles
			if level == 0:
				var bounds := AABB()
				for index in entry.bounds_godot.size():
					var point := Vector3(entry.bounds_godot[index][0], entry.bounds_godot[index][1], entry.bounds_godot[index][2])
					bounds = AABB(point, Vector3.ZERO) if index == 0 else bounds.expand(point)
				check(mesh.get_aabb().position.distance_to(bounds.position) < 0.02 and mesh.get_aabb().end.distance_to(bounds.end) < 0.02, entry.id + " GLB axis or bounds mismatch")
	report["geometry_assets"] = manifest.assets.size()
	report["body_profiles"] = manifest.profiles.size()

func _contract(kind: String) -> void:
	var root := Node3D.new()
	root.transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(700, 12, -550))
	add_child(root)
	var script := load("res://src/colossus/%s/%s.gd" % [kind, kind]) as Script
	var c := script.new() as Colossus
	root.add_child(c)
	root.process_mode = Node.PROCESS_MODE_DISABLED
	var before := _physics(c)
	var count := ColossusArtV3.dress(c, StringName(kind))
	check(count > 0, kind + " has no sculptures")
	check(_physics(c) == before, kind + " art mutated physics or sigils")
	check(ColossusArtV3.dress(c, StringName(kind)) == 0, kind + " art is not idempotent")
	var lods := c.find_children("LOD*", "MeshInstance3D", true, false)
	for visual: MeshInstance3D in lods:
		check(visual.mesh != null, kind + " missing mesh export")
		check(visual.get_children().is_empty(), kind + " GLB contains extra nodes")
	var entry := {"kind": kind, "segments": count, "lod_nodes": lods.size(), "physics_unchanged": _physics(c) == before}
	report.contracts.append(entry)
	root.free()

func _physics(c: Colossus) -> Array:
	var snapshot := []
	for child in c.get_children():
		if child is Colossus:
			snapshot.append(_physics(child))
	for i in c.skeleton.get_bone_count():
		snapshot.append([c.skeleton.get_bone_rest(i), c.skeleton.get_bone_pose(i)])
	for seg: BodySegment in c.segments:
		snapshot.append([seg.transform, seg.collision_layer, seg.collision_mask])
		for child in seg.get_children():
			if child is CollisionShape3D:
				snapshot.append([child.get_instance_id(), child.transform, child.shape.get_rid(), child.disabled])
			elif child is WeakPoint:
				snapshot.append([child.transform, child.health, child.state])
	return snapshot

func _fight(kind: StringName) -> void:
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	game.outro_time = 0
	game.fade_time = 0.1
	add_child(game)
	var previous: Array = []
	for k in BossRoster.PLAYABLE:
		if k == kind:
			break
		previous.append(String(k))
	game.start_from({"version": 2, "defeated": previous})
	game._wake(kind)
	var c := game.colossus()
	check(ColossusArtV3.dress(c, kind) > 0, "fight has no V3 visuals: " + String(kind))
	var arena: Dictionary = game.arenas[kind]
	var p := game.player()
	var start: Array = arena.points.get("player", [GameWorld.arena_starts(kind)[0], 0.0])
	p.global_transform = arena.xf * Transform3D(Basis(Vector3.UP, float(start[1])), start[0])
	p.facing = -p.global_basis.z
	p.actions.view_basis = p.global_basis
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var horse: Horse = game.refs.horse
	var hs: Array = arena.points.get("horse", [GameWorld.arena_starts(kind)[1], 0.0])
	var hx: Transform3D = arena.xf * Transform3D(Basis(Vector3.UP, float(hs[1])), hs[0])
	horse.teleport(hx.origin, hx.basis.get_euler().y)
	for i in 3:
		await get_tree().physics_frame
	var controller := GameBot.new()
	add_child(controller)
	controller.setup(game)
	for i in 60 * 360:
		await get_tree().physics_frame
		if not controller.stats.boss_results.is_empty() or not controller.result.is_empty():
			break
	var won: bool = not controller.stats.boss_results.is_empty() and controller.stats.boss_results[0].won
	check(won, "V3 dressed fight failed: %s %s %s" % [kind, controller.result, controller.stats.boss_results])
	var entry := {"kind": String(kind), "won": won, "fights": controller.stats.boss_results.duplicate(true), "deaths": game.state.deaths, "model_art": "Colossi V3", "arena_art": false}
	report.fights.append(entry)
	print("V3 dressed %s: %s" % [kind, str(entry)])
	controller.free()
	game.free()
	for i in 3:
		await get_tree().physics_frame
