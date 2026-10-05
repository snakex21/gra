class_name ArenaArchitectureMaterials
extends RefCounted
## Layout-5 art-only facade finish. A strict authored shape/position allowlist
## skins existing meshes; no nodes, vertices, collider, anchor or route edits.
## Local triplanar stone relief is shading only, never displacement or fake steps.
const CONFIG := {
	"phoenix": "res://materials/arena_architecture/phoenix.tres",
	"spider": "res://materials/arena_architecture/spider.tres",
	"dormin": "res://materials/arena_architecture/dormin.tres",
	"barba": "res://materials/arena_architecture/barba.tres",
	"kuromori": "res://materials/arena_architecture/kuromori.tres",
	"argus": "res://materials/arena_architecture/argus.tres",
	"gaius": "res://materials/arena_architecture/gaius.tres",
	"dirge": "res://materials/arena_architecture/dirge.tres",
	"celosia_cenobia": "res://materials/arena_architecture/celosia_cenobia.tres",
	"malus": "res://materials/arena_architecture/malus.tres",
}
static var _materials := {}
static var _requests := {}

## Only synchronous tools/captures call this; streamed arenas use _material_ready.
static func material_for(arena: String) -> StandardMaterial3D:
	if not CONFIG.has(arena): return null
	if not _materials.has(arena):
		var material := load(CONFIG[arena]) as StandardMaterial3D
		if material == null:
			push_error("Invalid arena architecture material: " + CONFIG[arena])
			return null
		_materials[arena] = material
	return _materials[arena]

## Never call load_threaded_get until the worker has finished decoding all maps.
static func _material_ready(arena: String) -> bool:
	if _materials.has(arena): return true
	var path: String = CONFIG[arena]
	if not _requests.has(arena):
		var error := ResourceLoader.load_threaded_request(path, "Material")
		_requests[arena] = error
		if error != OK:
			push_error("Arena architecture material request failed: " + path)
			return true
		return false
	if _requests[arena] != OK: return true
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_requests[arena] = ERR_CANT_OPEN
		push_error("Arena architecture material load failed: " + path)
		return true
	var material := ResourceLoader.load_threaded_get(path) as StandardMaterial3D
	if material == null:
		_requests[arena] = ERR_INVALID_DATA
		push_error("Invalid arena architecture material: " + path)
		return true
	_materials[arena] = material
	return true

## Records are [local center, original box size]. Matching geometry explicitly
## fails closed if a future encounter reuses a node name for another purpose.
static func _specifications(arena: String, nested := false) -> Array:
	var specs := []
	match arena:
		"phoenix":
			if nested: return specs
			# Only masonry framing the two streams, never pools or falling water.
			for x in [-20.0, 20.0]:
				specs.append([Vector3(x, 12, -27), Vector3(18, 24, 3)])
				specs.append([Vector3(x, 23.5, -19), Vector3(18, 1, 19)])
				for side in [-1.0, 1.0]: specs.append([Vector3(x + side * 8.3, 8, -19), Vector3(2.2, 16, 14)])
		"spider":
			if nested: return specs
			# The low 2m anchor pads are gameplay cues and deliberately excluded.
			for x in [-34.0, 34.0]:
				for z in [-35.0, 0.0, 35.0]: specs.append([Vector3(x, 6, z), Vector3(3, 12, 3)])
		"dormin":
			if nested: return specs
			for x in [-40.0, 40.0]:
				for z in [-48.0, -23.0, 2.0, 27.0]: specs.append([Vector3(x, 9, z), Vector3(3, 18, 3)])
			specs.append([Vector3(0, 12, -53), Vector3(85, 24, 3)])
			specs.append([Vector3(0, 24.3, -53), Vector3(88, 1, 6)])
		"gaius":
			if nested: return specs
			for side in [-1.0, 1.0]: specs.append([Vector3(side * 7, 5, 62), Vector3(2.5, 10, 2.5)])
			specs.append([Vector3(0, 10.8, 62), Vector3(17, 1.6, 2.8)])
			for i in 9:
				var a := i * TAU / 9.0 + 0.35
				var r := 56.0 + (i % 3) * 4.0
				var h := 4.0 + (i % 4) * 2.5
				specs.append([Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(2.4, h, 2.4), Basis(Vector3.UP, a)])
			specs.append([Vector3(28, 1, 34), Vector3(6, 2, 3), Basis(Vector3.UP, 0.4)])
			specs.append([Vector3(-30, 1.2, 40), Vector3(4, 2.4, 4), Basis(Vector3.UP, 0.9)])
			specs.append([Vector3(-22, 0.8, -40), Vector3(5, 1.6, 3), Basis(Vector3.UP, 1.4)])
		"dirge":
			if nested: return specs
			for side in [-1.0, 1.0]:
				specs.append([Vector3(side * 100, 8, 0), Vector3(6, 16, 206)])
				specs.append([Vector3(side * 54, 8, 100), Vector3(86, 16, 6)])
			specs.append([Vector3(0, 8, -100), Vector3(194, 16, 6)])
		"celosia_cenobia":
			if nested: return specs
			# Refuge only. Charge columns, fire wall, flame and hearth stay authored.
			specs.append([Vector3(-20, 4.5, 5), Vector3(8, 1, 8)])
			for side in [-1.0, 1.0]: specs.append([Vector3(-20 + side * 3.5, 2, 1.5), Vector3(0.5, 4, 0.5)])
		"malus":
			if nested: return specs
			for p in [Vector3(0, 0, 104), Vector3(-11, 0, 90), Vector3(11, 0, 69), Vector3(-11, 0, 48), Vector3(-15, 0, 22)]:
				specs.append([p + Vector3(0, 3.8, 0), Vector3(8, 1, 9)])
				for side in [-1.0, 1.0]: specs.append([p + Vector3(side * 4, 1.7, 3.5), Vector3(0.7, 3.4, 0.7)])
				specs.append([p + Vector3(0, 1.7, -4), Vector3(8, 3.4, 0.7)])
			specs.append([Vector3(-15, 3.8, 4), Vector3(7, 1, 38)])
		"barba":
			if nested: return specs
			for side in [-1.0, 1.0]:
				specs.append([Vector3(side * 32, 6, 0), Vector3(2, 12, 78)])
				for z in [-32.0, 0.0, 30.0]:
					specs.append([Vector3(side * 26, 8, z), Vector3(2.2, 16, 2.2)])
			specs.append([Vector3(0, 6, -39), Vector3(66, 12, 2)])
		"kuromori":
			if nested: return specs
			specs.append([Vector3(0, 8, -25), Vector3(54, 16, 2)])
			for side in [-1.0, 1.0]:
				specs.append([Vector3(side * 26, 8, 0), Vector3(2, 16, 52)])
				specs.append([Vector3(side * 16, 8, 25), Vector3(22, 16, 2)])
			for level in [4.0, 8.0, 12.0]:
				for side in [-1.0, 1.0]:
					specs.append([Vector3(side * 23, level - 0.3, 0), Vector3(4, 0.6, 50)])
					specs.append([Vector3(side * 17, level - 0.3, -22), Vector3(14, 0.6, 4)])
				specs.append([Vector3(0, level - 0.3, 22), Vector3(48, 0.6, 4)])
			# These are the existing 48 visible treads, not new apparent steps.
			# Their collider layer remains zero; the hidden continuous ramp is excluded.
			for i in 48:
				var y := (i + 1) * 0.25
				specs.append([Vector3(19.6, y * 0.5, 20.0 - i * 0.75), Vector3(2.7, y, 0.8)])
		"argus":
			if nested:
				for side in [-1.0, 1.0]:
					specs.append([Vector3(side * 18, 11.5, -7), Vector3(7, 1, 8)])
					for z in [-10.0, -4.0]:
						specs.append([Vector3(side * 20, 5.5, z), Vector3(2.4, 11, 2.4)])
				specs.append([Vector3(0, 8, -24), Vector3(48, 16, 3)])
			else:
				for side in [-1.0, 1.0]:
					for z in [-55.0, -20.0, 20.0]:
						specs.append([Vector3(side * 36, 7, z), Vector3(3, 14, 3)])
	return specs

static func _collect(parent: Node3D, specs: Array, result: Array[MeshInstance3D]) -> void:
	for node: Node in parent.get_children():
		if not node is StaticBody3D: continue
		var body := node as StaticBody3D
		# Named live mechanics are excluded even if a future revision moves them
		# onto one of the static facade positions. Never mutate their shared mats.
		if body.has_meta(&"cenobia_column") or body.has_meta(&"celosia_fire_wall"): continue
		if body.name in [&"Ground", &"CoverRoof", &"HingedGalleryRamp", &"StompCounterweight", &"GalleryBridge", &"JumpToGuardian"]: continue
		for child: Node in body.get_children():
			if not child is MeshInstance3D: continue
			var mesh := child as MeshInstance3D
			if not mesh.visible or not mesh.mesh is BoxMesh: continue
			if not mesh.transform.is_equal_approx(Transform3D.IDENTITY): continue
			for spec: Array in specs:
				if body.basis.is_equal_approx(spec[2] if spec.size() > 2 else Basis.IDENTITY) and body.position.is_equal_approx(spec[0]) and (mesh.mesh as BoxMesh).size.is_equal_approx(spec[1]):
					result.append(mesh)
					break

static func _targets(parent: Node3D, arena: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect(parent, _specifications(arena), result)
	if arena == "argus":
		for child: Node in parent.get_children():
			if child is ArgusRuins:
				_collect(child as Node3D, _specifications(arena, true), result)
	return result

static func _coat(target: MeshInstance3D, arena: String) -> void:
	if not is_instance_valid(target): return
	var material := _materials.get(arena) as StandardMaterial3D
	if material == null: return
	target.material_override = material
	target.set_meta(&"arena_architecture_material", arena)

static func append(parent: Node3D, arena: String) -> void:
	if not CONFIG.has(arena): return
	var targets := _targets(parent, arena)
	if ArenaArt._planner:
		ArenaArt._planner.jobs.append(func() -> bool: return _material_ready(arena))
		for target: MeshInstance3D in targets:
			# A streamed arena can unload before this job reaches the queue head.
			# Capture a RefCounted weak handle, never a soon-to-be-freed Node.
			var target_ref: WeakRef = weakref(target)
			ArenaArt._planner.add(func() -> void:
				var alive := target_ref.get_ref() as MeshInstance3D
				if alive: _coat(alive, arena))
	else:
		material_for(arena)
		for target: MeshInstance3D in targets:
			_coat(target, arena)
