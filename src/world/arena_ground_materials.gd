class_name ArenaGroundMaterials
extends RefCounted
## Campaign layout-5 surface pass. Materials only: never mutate meshes or physics.
## Main arena floors are XZ-centred and root-aligned, so local triplanar coordinates
## remain stable when GameWorld places or rotates the arena in the campaign.
## The two Basaran slabs share one seamless XZ material; rotated rim blocks keep
## object-local stone grain. Quadratus's broad earth rises likewise keep local
## projection. Legacy standalone trials/layouts do not call append.
const CONFIG := {
	"worm": "res://materials/arena_ground/worm.tres",
	"saru": "res://materials/arena_ground/saru.tres",
	"saru_chasm": "res://materials/arena_ground/saru_chasm.tres",
	"phoenix": "res://materials/arena_ground/phoenix.tres",
	"spider": "res://materials/arena_ground/spider.tres",
	"dormin": "res://materials/arena_ground/dormin.tres",
	"valus": "res://materials/arena_ground/valus.tres",
	"hydrus": "res://materials/arena_ground/hydrus.tres",
	"basaran": "res://materials/arena_ground/basaran.tres",
	"phalanx": "res://materials/arena_ground/phalanx.tres",
	"quadratus": "res://materials/arena_ground/quadratus.tres",
	"phaedra": "res://materials/arena_ground/phaedra.tres",
	"avion": "res://materials/arena_ground/avion.tres",
	"barba": "res://materials/arena_ground/barba.tres",
	"pelagia": "res://materials/arena_ground/pelagia.tres",
	"argus": "res://materials/arena_ground/argus.tres",
	"kuromori": "res://materials/arena_ground/kuromori.tres",
	"gaius": "res://materials/arena_ground/gaius.tres",
	"dirge": "res://materials/arena_ground/dirge.tres",
	"celosia_cenobia": "res://materials/arena_ground/celosia_cenobia.tres",
	"malus": "res://materials/arena_ground/malus.tres",
}
static var _materials := {}
static var _requests := {}

## Only synchronous tools/captures call this; streamed arenas use _material_ready.
static func material_for(arena: String) -> StandardMaterial3D:
	if not CONFIG.has(arena): return null
	if not _materials.has(arena):
		_materials[arena] = load(CONFIG[arena])
	return _materials[arena]

## Never call load_threaded_get until the worker has finished decoding all maps.
static func _material_ready(arena: String) -> bool:
	if _materials.has(arena): return true
	var path: String = CONFIG[arena]
	if not _requests.has(arena):
		var error := ResourceLoader.load_threaded_request(path, "Material")
		_requests[arena] = error
		if error != OK:
			push_error("Arena ground material request failed: " + path)
			return true
		return false
	if _requests[arena] != OK: return true
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_requests[arena] = ERR_CANT_OPEN
		push_error("Arena ground material load failed: " + path)
		return true
	_materials[arena] = ResourceLoader.load_threaded_get(path)
	return true

static func _kuromori_floor(body: StaticBody3D, mesh: MeshInstance3D) -> bool:
	# Kuromori's unnamed courtyard sits 4 cm above the named campaign foundation.
	# Pin both original shapes and transforms; a broad low-box predicate could
	# accidentally select galleries, stairs or an invisible collision ramp.
	if not body.basis.is_equal_approx(Basis.IDENTITY) or not mesh.transform.is_equal_approx(Transform3D.IDENTITY): return false
	if mesh.mesh is BoxMesh:
		var size := (mesh.mesh as BoxMesh).size
		if body.position.is_equal_approx(Vector3(0, -1, 0)):
			return size.is_equal_approx(Vector3(120, 2, 120))
		return body.name == &"Ground" and body.position.is_equal_approx(Vector3(0, -1.04, 0)) and size.is_equal_approx(Vector3(350, 2, 350))
	if body.name == &"Ground" and body.position.is_equal_approx(Vector3(0, -1.04, 0)) and mesh.mesh is CylinderMesh:
		var disc := mesh.mesh as CylinderMesh
		return is_equal_approx(disc.height, 2.0) and is_equal_approx(disc.top_radius, 175.0) and is_equal_approx(disc.bottom_radius, 175.0)
	return false

## Custom courtyards have one authored support plane, converted to a disc by
## GameWorld. Pin both forms; a reused Ground name must not admit other meshes.
static func _custom_floor(body: StaticBody3D, mesh: MeshInstance3D) -> bool:
	if body.name != &"Ground" or not body.position.is_equal_approx(Vector3(0, -1, 0)): return false
	if not body.basis.is_equal_approx(Basis.IDENTITY) or not mesh.transform.is_equal_approx(Transform3D.IDENTITY) or not mesh.visible: return false
	if mesh.mesh is BoxMesh:
		return (mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(350, 2, 350))
	if mesh.mesh is CylinderMesh:
		var disc := mesh.mesh as CylinderMesh
		return is_equal_approx(disc.height, 2.0) and is_equal_approx(disc.top_radius, 175.0) and is_equal_approx(disc.bottom_radius, 175.0)
	return false

static func _remaining_ground(body: StaticBody3D, mesh: MeshInstance3D, arena: String) -> bool:
	if not mesh.transform.is_equal_approx(Transform3D.IDENTITY) or not mesh.mesh is BoxMesh: return false
	var size := (mesh.mesh as BoxMesh).size
	if arena == "dirge":
		if body.name == &"DesertFloor":
			return body.position.is_equal_approx(Vector3(0, -1, 0)) and size.is_equal_approx(Vector3(220, 2, 220))
		for i in 5:
			if body.position.is_equal_approx(Vector3(-76, 0.4, -60 + i * 25)) and body.basis.is_equal_approx(Basis(Vector3.UP, 0.2 * i)) and size.is_equal_approx(Vector3(16, 0.8, 12)): return true
	if arena == "gaius":
		for spec in [[Vector3(-46, 0, -6), Vector3(14, 3.94, 20)], [Vector3(44, 0, -37), Vector3(10, 3.52, 14)]]:
			if body.position.is_equal_approx(spec[0]) and size.is_equal_approx(spec[1]) and body.basis.is_equal_approx(Basis.IDENTITY): return true
		for spec in [[Vector3(-46, 0, 18), 14.0, 8.0, 14.0], [Vector3(44, 0, -20), 10.0, 10.0, 10.0]]:
			var angle := deg_to_rad(float(spec[2]))
			var rotation := Basis(Vector3.RIGHT, angle)
			var center: Vector3 = spec[0] + Vector3(0, float(spec[1]) * 0.5 * tan(angle), -float(spec[1]) * 0.5) - rotation.y
			if body.position.is_equal_approx(center) and body.basis.is_equal_approx(rotation) and size.is_equal_approx(Vector3(float(spec[3]), 2, float(spec[1]) / cos(angle) + 0.6)): return true
	return false

## Saru's authored UV-less banks must never become a full disc or include the
## bridge. Pin complete mesh arrays rather than trusting Ground names or bounds.
## A future topology change fails closed and requires an explicit material audit.
const SARU_SURFACES := {
	"saru": [
		"14222ec050613830511b53caa2e9bc54072dd5a57bdfffa4067db215cb6ea028",
		"d45a4674e9046519bf03d7cc17091a6b13bf0588198aa52a4731e465c46f2d52",
		"7552461658b9941f093625b14d22818156d1aa3af6d1745d22845b14c89a743c",
		"aa52f6086eb6f76d567f989e35de8230d459c79863aa9969e9d171002c46f2d6",
	],
	"saru_chasm": ["65fc7e74213f39970f2c23ed7c093df6949fa69264fcaa2d8d3bf0d78904c174"],
}

static func _saru_floor(body: StaticBody3D, mesh: MeshInstance3D, arena: String) -> bool:
	var expected_name := &"Ground" if arena == "saru" else &"ChasmFloor"
	if body.name != expected_name or body.collision_layer != Layers.WORLD or body.collision_mask != 0: return false
	if not body.transform.is_equal_approx(Transform3D.IDENTITY) or not mesh.transform.is_equal_approx(Transform3D.IDENTITY): return false
	if not mesh.visible or not mesh.mesh is ArrayMesh or mesh.mesh.get_surface_count() != 1: return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(mesh.mesh.surface_get_arrays(0)))
	return hash.finish().hex_encode() in SARU_SURFACES[arena]

static func _targets(parent: Node3D, arena: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for body: Node in parent.get_children():
		if not body is StaticBody3D: continue
		var floor_mesh := body.name == &"Ground" or (arena == "basaran" and body.name == &"VolcanicGround")
		# Barba, Pelagia and Argus deliberately coat only this named floor.
		# Their shelter, shrine buttresses, water and interactive ruin materials
		# are encounter state; do not expand these to the broad-rock exceptions.
		for child: Node in body.get_children():
			if not child is MeshInstance3D: continue
			var mesh := child as MeshInstance3D
			if arena in ["saru", "saru_chasm"]:
				if _saru_floor(body as StaticBody3D, mesh, arena): result.append(mesh)
				continue
			if arena in ["phoenix", "spider", "dormin", "worm"]:
				if _custom_floor(body as StaticBody3D, mesh): result.append(mesh)
				continue
			# The three broad, low original Quadratus ramp/rise boxes are ground,
			# not pillars or cover. Keep their silhouettes/colliders and share the
			# beach material; never recursively coat art, water, or climb visuals.
			var ground_form := false
			if arena == "quadratus" and mesh.mesh is BoxMesh:
				var size: Vector3 = (mesh.mesh as BoxMesh).size
				ground_form = size.y <= 4.0 and minf(size.x, size.z) >= 10.0
			# Basaran's eleven original bare static rock blocks are render-skinned
			# in place. Do not touch geysers, water, art meshes or climb patches.
			var courtyard_floor := arena == "kuromori" and _kuromori_floor(body as StaticBody3D, mesh)
			if _remaining_ground(body as StaticBody3D, mesh, arena) or (floor_mesh and arena != "kuromori") or courtyard_floor or ground_form or (arena == "basaran" and mesh.mesh is BoxMesh):
				result.append(mesh)
	return result

static func _coat(target: MeshInstance3D, arena: String) -> void:
	if not is_instance_valid(target) or not _materials.has(arena): return
	target.material_override = _materials[arena]
	target.set_meta(&"arena_ground_material", arena)

static func append(parent: Node3D, arena: String) -> void:
	# Distinct bank and pit resources; never mutate Saru's original shared stone.
	if arena == "saru": append(parent, "saru_chasm")
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
