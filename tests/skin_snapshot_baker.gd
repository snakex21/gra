extends SceneTree
## Generator-independent export fixtures. Can run in a minimal temporary project
## containing only this script and tools/art/skin_snapshot_baker.gd.
const Baker = preload("res://tools/art/skin_snapshot_baker.gd")
var failed := false
var checks := 0
var fixture: Node3D
var skeleton: Skeleton3D
var instance: MeshInstance3D
var shared_material: StandardMaterial3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("SKIN_BAKE_TEST: " + message)

func close_vec(actual: Vector3, expected: Vector3, message: String) -> void:
	check(actual.distance_to(expected) < 0.00025, "%s: got %s expected %s" % [message, actual, expected])

func tangent(arrays: Array, index: int) -> Vector3:
	var values: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	return Vector3(values[index * 4], values[index * 4 + 1], values[index * 4 + 2])

func make_mesh(eight_weights := false) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,1)])
	var normal := Vector3(1,1,0).normalized()
	var direction := Vector3(1,-1,0).normalized()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal,normal,normal])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([direction.x,direction.y,0,1,direction.x,direction.y,0,-1,direction.x,direction.y,0,1])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(0,1)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(.25,.25),Vector2(.75,.25),Vector2(.25,.75)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED,Color.GREEN,Color.BLUE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	# Skin bindings are reversed relative to bone indices: bind0 -> bone1.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex in 3:
		for slot in (8 if eight_weights else 4):
			bones.append(0 if slot == 0 else 1)
			var weight := 0.0
			if vertex == 0 and slot == 0: weight = 1.0
			if vertex == 1 and slot == 1: weight = 1.0
			if vertex == 2 and slot == 0: weight = .25
			if vertex == 2 and slot == (7 if eight_weights else 1): weight = .75
			weights.append(weight)
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight_weights else 0)
	mesh.surface_set_material(0, shared_material)
	return mesh

func setup() -> void:
	fixture = Node3D.new()
	fixture.name = "SyntheticFixture"
	root.add_child(fixture)
	fixture.transform = Transform3D(Basis(Vector3.UP, .31), Vector3(9,8,7))
	skeleton = Skeleton3D.new()
	skeleton.name = "Rig"
	fixture.add_child(skeleton)
	skeleton.add_bone("Root")
	skeleton.add_bone("Moved")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(2,3,4)))
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(-2,1,3)))
	skeleton.reset_bone_poses()
	shared_material = StandardMaterial3D.new()
	shared_material.resource_name = "SharedMaterialMustStayUntouched"
	shared_material.albedo_color = Color(.2,.3,.4,1)
	instance = MeshInstance3D.new()
	instance.name = "SyntheticMesh"
	var skin := Skin.new()
	skin.add_named_bind("Moved", skeleton.get_bone_global_rest(1).affine_inverse())
	skin.add_bind(0, skeleton.get_bone_global_rest(0).affine_inverse())
	instance.skin = skin
	instance.mesh = make_mesh()
	instance.skeleton = NodePath("../Rig")
	fixture.add_child(instance)
	instance.transform = Transform3D(Basis(Vector3.RIGHT, .17), Vector3(3,2,1))

func round_trip(mesh: Mesh) -> void:
	var snapshot := Node3D.new()
	snapshot.name = "SyntheticSnapshot"
	root.add_child(snapshot)
	var clone := MeshInstance3D.new()
	clone.name = "BakedSkin"
	clone.mesh = mesh
	clone.transform = instance.global_transform
	snapshot.add_child(clone)
	clone.owner = snapshot
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_scene(snapshot,state) == OK, "GLTF accepts baked snapshot")
	var buffer := document.generate_buffer(state)
	check(not buffer.is_empty(), "GLB binary generated")
	if not buffer.is_empty():
		var json_size := buffer.decode_u32(12)
		var gltf: Dictionary = JSON.parse_string(buffer.slice(20,20 + json_size).get_string_from_utf8())
		check(not gltf.has("skins"), "GLB has no discarded/unbaked skins")
		var attributes: Dictionary = gltf.meshes[0].primitives[0].attributes
		check(not attributes.has("JOINTS_0") and not attributes.has("WEIGHTS_0"), "GLB has no stale joint/weight arrays")
		var imported_state := GLTFState.new()
		check(document.append_from_buffer(buffer,"",imported_state) == OK, "GLB round-trip imports")
		var imported := document.generate_scene(imported_state)
		root.add_child(imported)
		var meshes := imported.find_children("*","MeshInstance3D",true,false)
		check(meshes.size() == 1, "GLB retains exactly one mesh")
		if meshes.size() == 1:
			var restored := meshes[0] as MeshInstance3D
			var expected := mesh.surface_get_arrays(0)
			var actual := restored.mesh.surface_get_arrays(0)
			for vertex in 3:
				close_vec(actual[Mesh.ARRAY_VERTEX][vertex],expected[Mesh.ARRAY_VERTEX][vertex],"GLB posed local vertex %d" % vertex)
				close_vec(restored.global_transform * actual[Mesh.ARRAY_VERTEX][vertex],clone.global_transform * expected[Mesh.ARRAY_VERTEX][vertex],"GLB posed world vertex %d" % vertex)
			check(restored.skin == null, "Round-trip remains static")
		imported.free()
	snapshot.free()

func run() -> void:
	setup()
	var source_hash := Baker.digest(instance.mesh.surface_get_arrays(0))
	var source_transform := instance.global_transform
	var source_skin := instance.skin
	var identity := Baker.bake(instance)
	check(identity.ok, "Identity rest bake succeeds")
	if not identity.ok:
		print(identity)
		fixture.free()
		quit(1)
		return
	var arrays: Array = identity.mesh.surface_get_arrays(0)
	var original: Array = instance.mesh.surface_get_arrays(0)
	for index in 3:
		close_vec(arrays[Mesh.ARRAY_VERTEX][index], original[Mesh.ARRAY_VERTEX][index], "Identity rest vertex %d" % index)
		close_vec(arrays[Mesh.ARRAY_NORMAL][index], original[Mesh.ARRAY_NORMAL][index], "Identity normal %d" % index)
		close_vec(tangent(arrays,index), tangent(original,index), "Identity tangent %d" % index)
	check(identity.proof.bindings[0].resolved_bone_index == 1 and identity.proof.bindings[1].resolved_bone_index == 0, "Named and index bindings resolved independently of bind slot")
	check(identity.proof.surfaces[0].skin_arrays_removed, "Skin arrays removed from static snapshot")
	check(identity.proof.surfaces[0].source_array_sha256 == source_hash, "Source proof hash is exact")
	check(identity.proof.surfaces[0].source_array_sha256 != identity.proof.surfaces[0].baked_array_sha256, "Source skin arrays and baked arrays explicitly differ")

	var movement := Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(4,5,6))
	skeleton.set_bone_global_pose(1, movement * skeleton.get_bone_global_rest(1))
	var posed := Baker.bake(instance)
	check(posed.ok, "Rotated/translated and blended bake succeeds")
	if posed.ok:
		arrays = posed.mesh.surface_get_arrays(0)
		close_vec(arrays[Mesh.ARRAY_VERTEX][0], Vector3(4,6,6), "Known rotated/translated vertex")
		close_vec(arrays[Mesh.ARRAY_VERTEX][1], Vector3(0,1,0), "Unmoved root vertex")
		close_vec(arrays[Mesh.ARRAY_VERTEX][2], Vector3(1,1.25,2.5), "Known quarter-weight blend")
		close_vec(arrays[Mesh.ARRAY_NORMAL][0], Vector3(-1,1,0).normalized(), "Rotated normal")
		close_vec(arrays[Mesh.ARRAY_NORMAL][2], Vector3(.5,1,0).normalized(), "Weighted normal")
		close_vec(tangent(arrays,0), Vector3(1,1,0).normalized(), "Rotated tangent")
		close_vec(tangent(arrays,2), Vector3(1,-.5,0).normalized(), "Weighted tangent")
		for slot in [Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			check(Baker.digest(arrays[slot]) == Baker.digest(original[slot]), "Preserved array channel %d" % slot)
		check(arrays[Mesh.ARRAY_TANGENT][3] == 1.0 and arrays[Mesh.ARRAY_TANGENT][7] == -1.0, "Both tangent handedness signs preserved")
		round_trip(posed.mesh)
		check(posed.mesh.surface_get_material(0) != shared_material, "Baked material is a private copy")
		posed.mesh.surface_get_material(0).albedo_color = Color.MAGENTA
		check(shared_material.albedo_color == Color(.2,.3,.4,1), "Editing clone cannot mutate shared material")

	# Scale oracle deliberately matches Godot's shader, not inverse transpose.
	var scaled := Transform3D(Basis.from_scale(Vector3(2,1,.5)), Vector3.ZERO)
	skeleton.set_bone_global_pose(1, scaled * skeleton.get_bone_global_rest(1))
	var scale_result := Baker.bake(instance)
	check(scale_result.ok, "Nonuniform scaling succeeds")
	if scale_result.ok:
		arrays = scale_result.mesh.surface_get_arrays(0)
		close_vec(arrays[Mesh.ARRAY_VERTEX][0], Vector3(2,0,0), "Scaled position")
		close_vec(arrays[Mesh.ARRAY_NORMAL][0], Vector3(2,1,0).normalized(), "Renderer-equivalent scaled normal")
		close_vec(tangent(arrays,0), Vector3(2,-1,0).normalized(), "Renderer-equivalent scaled tangent")
		close_vec(arrays[Mesh.ARRAY_NORMAL][2], Vector3(1.25,1,0).normalized(), "Renderer-equivalent scale blend normal")
	check(Baker.digest(instance.mesh.surface_get_arrays(0)) == source_hash, "Repeated bakes never mutate source arrays")
	check(instance.global_transform == source_transform and instance.skin == source_skin, "Source transform/skin unchanged")
	check(instance.mesh.surface_get_material(0) == shared_material, "Source material assignment unchanged")

	instance.mesh = make_mesh(true)
	var eight := Baker.bake(instance)
	check(eight.ok, "Eight-bone-weight array succeeds")
	if eight.ok:
		arrays = eight.mesh.surface_get_arrays(0)
		close_vec(arrays[Mesh.ARRAY_VERTEX][2], Vector3(0,0,.875), "Eighth influence is included")
		check((eight.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) == 0, "Eight-weight skin flag removed")
	instance.mesh = make_mesh()
	# Parent-relative rests must cancel globally, including generated implicit Skin.
	skeleton.set_bone_parent(1,0)
	skeleton.reset_bone_poses()
	instance.skin = null
	var implicit := Baker.bake(instance)
	check(implicit.ok, "Implicit rest skin on hierarchical skeleton succeeds")
	if implicit.ok:
		check(implicit.proof.skin_origin == "registered_implicit_rest_skin", "Implicit skin source recorded")
		arrays = implicit.mesh.surface_get_arrays(0)
		for vertex in 3:
			close_vec(arrays[Mesh.ARRAY_VERTEX][vertex],original[Mesh.ARRAY_VERTEX][vertex],"Hierarchical inverse rest vertex %d" % vertex)
	skeleton.set_bone_parent(1,-1)
	skeleton.reset_bone_poses()
	instance.skin = source_skin

	# Reject malformed data without asking Godot to load malformed geometry.
	var bad_arrays := instance.mesh.surface_get_arrays(0)
	bad_arrays[Mesh.ARRAY_BONES][0] = 99
	var known_transforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
	check(not Baker._bake_arrays(bad_arrays,known_transforms,0).ok, "Reject bad bind index")
	bad_arrays = instance.mesh.surface_get_arrays(0)
	bad_arrays[Mesh.ARRAY_WEIGHTS].fill(0.0)
	check(not Baker._bake_arrays(bad_arrays,known_transforms,0).ok, "Reject zero skin weights")
	bad_arrays = instance.mesh.surface_get_arrays(0)
	bad_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP])
	check(not Baker._bake_arrays(bad_arrays,known_transforms,0).ok, "Reject malformed normal array")
	instance.skeleton = NodePath("../MissingSkeleton")
	check(not Baker.bake(instance).ok, "Reject missing skeleton")
	instance.skeleton = NodePath("../Rig")
	instance.skin.set_bind_name(0,"MissingBone")
	check(not Baker.bake(instance).ok, "Reject unresolved named binding, without bone-zero fallback")
	instance.skin.set_bind_name(0,"Moved")
	var morph := ArrayMesh.new()
	morph.add_blend_shape("UnsupportedMorph")
	instance.mesh = morph
	check(not Baker.bake(instance).ok, "Reject malformed empty blend-shape mesh")
	var rigid_arrays := make_mesh().surface_get_arrays(0)
	rigid_arrays[Mesh.ARRAY_BONES] = null
	rigid_arrays[Mesh.ARRAY_WEIGHTS] = null
	var blend_arrays := []
	blend_arrays.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]: blend_arrays[slot] = rigid_arrays[slot]
	morph.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,rigid_arrays,[blend_arrays])
	instance.mesh = null
	instance.mesh = morph
	var neutral_morph := Baker.bake(instance)
	check(neutral_morph.ok, "Unskinned exactly-zero blend shape is safely supported")
	if neutral_morph.ok:
		check(neutral_morph.mesh.get_blend_shape_count() == 0, "Verified neutral morph clone contains no stale shapes")
		check(neutral_morph.proof.blend_shapes[0].weight == 0.0, "Neutral shape weight is recorded")
	instance.set_blend_shape_value(0,.5)
	check(not Baker.bake(instance).ok, "Reject unsupported nonzero morph without exporting rest pose")

	instance.skin = null
	instance.skeleton = NodePath("")
	instance.mesh = BoxMesh.new()
	instance.mesh.material = shared_material
	var rigid := Baker.bake(instance)
	check(rigid.ok and not rigid.proof.skinned, "Rigid primitive meshes remain supported")
	if rigid.ok:
		check(rigid.mesh != instance.mesh and rigid.mesh.surface_get_material(0) != shared_material, "Rigid clone mesh/material isolated too")
	fixture.free()
	print("SKIN_SNAPSHOT_BAKER_", "FAIL" if failed else "OK", " checks=", checks, " Godot=", Engine.get_version_info().string)
	quit(1 if failed else 0)
