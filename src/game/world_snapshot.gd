class_name WorldSnapshot
extends RefCounted
## Binary simulation checkpoints. Nodes are referenced by stable names/type ordinals,
## never addresses. Native RIDs, input hooks and rendering resources are rebuilt.
const VERSION := 1
const SKIP := ["action_hook", "_exclude", "terrain_rids", "_slam_point", "debug_draw", "_params", "_shape", "_sphere", "_last_observation"]
var root: Node
var objects := []
var object_ids := {}
var node_ids := {}
var decoded := []
var native_references := {}
var recorded_nodes := {}

static func capture(game: GameWorld) -> Dictionary:
	if not is_instance_valid(game.region):
		return {}
	var codec := WorldSnapshot.new()
	codec.root = game.region
	codec._index_nodes(codec.root)
	var nodes := []
	codec._capture_nodes(codec.root, nodes)
	# Script-controlled native nodes include warning disks, moving ruin slabs and
	# arrow visuals. Their transforms/visibility must survive a mid-fight seek too.
	for id in codec.native_references:
		var node: Node = codec.native_references[id]
		if not codec.recorded_nodes.has(id) and node is Node3D and codec.root.is_ancestor_of(node):
			var record := {"key": codec._key(node), "fields": {}}
			codec._native_state(node, record)
			nodes.append(record)
	return {"version": VERSION, "progress": game.state.to_dict(), "region": String(game.region_kind),
		"world_layout": game.layout_version,
		"seed_offset": game.seed_offset, "phase": game.phase, "phase_t": game._phase_t,
		"region_time": game.region_time, "transitions": game.transitions, "resets_seen": game._resets_seen,
		"nodes": nodes, "objects": codec.objects}

static func restore(game: GameWorld, data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION:
		return false
	game.seed_offset = int(data.get("seed_offset", 0))
	game.layout_version = int(data.get("world_layout", 1))
	game.start_from(data.get("progress", {}))
	# Water and static anchor references may belong to any arena. Build their gameplay
	# ground now; leave render dressing in its incremental queue.
	for arena_kind: StringName in game.arenas:
		game.ensure_arena(arena_kind)
	var kind := StringName(data.get("region", "valley"))
	if kind != GameWorld.VALLEY:
		if not game.arenas.has(kind):
			return false
		game._wake(kind)
	var codec := WorldSnapshot.new()
	codec.root = game.region
	codec.objects = data.get("objects", [])
	# Allocate every referenced object before filling any fields (cycles / sharing).
	for item: Dictionary in codec.objects:
		var instance: Object = null
		if item.get("rng", false):
			instance = RandomNumberGenerator.new()
		else:
			var path := String(item.script)
			if not path.begins_with("res://src/") or ".." in path:
				return false
			var script := load(path) as GDScript
			if script:
				instance = script.new(null) if path.ends_with("player_riding.gd") else script.new()
		codec.decoded.append(instance)
	# Arrow visuals are dynamic: recreate them before resolving their node references.
	for record: Dictionary in data.get("nodes", []):
		if record.get("arrow_count", 0) > 0:
			var arrows := ArrowSystem.of(game.player())
			for i in int(record.arrow_count):
				arrows.spawn(Vector3.ZERO, Vector3.FORWARD)
	for i in codec.objects.size():
		var item: Dictionary = codec.objects[i]
		var instance: Object = codec.decoded[i]
		if instance is RandomNumberGenerator:
			instance.seed = item.seed
			instance.state = item.state
		elif instance:
			codec._apply_fields(instance, item.fields)
	for record: Dictionary in data.get("nodes", []):
		var node := codec._find(record.key)
		if node == null:
			push_error("Checkpoint node missing: " + str(record.key))
			return false
		codec._apply_fields(node, record.fields)
		# Entering the tree seeds AnimatableBody3D's native last-valid pose. Merely
		# assigning the transform leaves its first physics tick at the spawn pose.
		var resync := node is AnimatableBody3D and (node as AnimatableBody3D).sync_to_physics
		var parent := node.get_parent()
		var sibling := node.get_index()
		if resync:
			(node as AnimatableBody3D).sync_to_physics = false
			parent.remove_child(node)
		if node is Node3D and record.has("transform"):
			(node as Node3D).transform = record.transform
			if record.has("visible"):
				(node as Node3D).visible = bool(record.visible)
			(node as Node3D).reset_physics_interpolation()
		if node is CharacterBody3D:
			(node as CharacterBody3D).velocity = record.get("velocity", Vector3.ZERO)
		if node is CollisionObject3D:
			(node as CollisionObject3D).collision_layer = int(record.get("layer", 1))
			(node as CollisionObject3D).collision_mask = int(record.get("mask", 1))
		if resync:
			parent.add_child(node)
			parent.move_child(node, sibling)
		if node is PhysicsBody3D and record.has("physics_transform"):
			PhysicsServer3D.body_set_state((node as PhysicsBody3D).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, record.physics_transform)
		if resync:
			(node as AnimatableBody3D).sync_to_physics = true
		if node is CollisionShape3D:
			var disabled := bool(record.get("disabled", false))
			(node as CollisionShape3D).disabled = disabled
			# Encounter creation can queue a reset for the same property. Restore
			# also queues its value last so the new world keeps the saved patches.
			node.set_deferred(&"disabled", disabled)
		if node is Skeleton3D:
			for i in record.get("bones", []).size():
				(node as Skeleton3D).set_bone_pose(i, record.bones[i])
	game.phase = int(data.get("phase", 0))
	game._phase_t = float(data.get("phase_t", 0.0))
	game.region_time = float(data.get("region_time", 0.0))
	game.transitions = int(data.get("transitions", 0))
	game._resets_seen = int(data.get("resets_seen", 0))
	game._fade.color.a = clampf(game._phase_t / game.fade_time, 0.0, 1.0) if game.phase == GameWorld.Phase.FADE_OUT else 0.0
	for horse in game.region.find_children("*", "Horse", true, false):
		(horse as Horse)._refresh_terrain()
	for water in WaterBody.all(game.get_tree()):
		water._sync_visual()
	if game.colossus() and game.colossus().has_method(&"encounter_hint"):
		(game.refs.hud as PlayerHud).message = game.colossus().call(&"encounter_hint")
	return true

func _index_nodes(n: Node) -> void:
	node_ids[n.get_instance_id()] = _key(n)
	for child in n.get_children():
		_index_nodes(child)

func _capture_nodes(n: Node, records: Array) -> void:
	var script := n.get_script() as Script
	var simulation := script and script.resource_path.begins_with("res://src/") and not n is PlayerHud and not n is WaterCameraEffects and not n is FlatInputSource and not n is TravelerArt and not n is ColossusArtV3 and not n is WeaponArt
	if simulation or n is Skeleton3D or n is CollisionShape3D and n.get_parent() is BodySegment:
		var record := {"key": _key(n), "fields": _fields(n) if simulation else {}}
		_native_state(n, record)
		if n is Skeleton3D:
			record.bones = []
			for i in (n as Skeleton3D).get_bone_count():
				record.bones.append((n as Skeleton3D).get_bone_pose(i))
		if n is ArrowSystem:
			record.arrow_count = (n as ArrowSystem).arrows.size()
		records.append(record)
		recorded_nodes[n.get_instance_id()] = true
	for child in n.get_children():
		_capture_nodes(child, records)

func _native_state(n: Node, record: Dictionary) -> void:
	if n is Node3D:
		record.transform = (n as Node3D).transform
		record.visible = (n as Node3D).visible
	if n is CharacterBody3D:
		record.velocity = (n as CharacterBody3D).velocity
	if n is CollisionObject3D:
		record.layer = (n as CollisionObject3D).collision_layer
		record.mask = (n as CollisionObject3D).collision_mask
	if n is PhysicsBody3D:
		record.physics_transform = SurfaceAnchor.body_query_transform(n)
	if n is CollisionShape3D:
		record.disabled = (n as CollisionShape3D).disabled

func _fields(object: Object) -> Dictionary:
	var fields := {}
	for property in object.get_property_list():
		var name := String(property.name)
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) or name in SKIP:
			continue
		var value: Variant = object.get(name)
		if _supported(value):
			fields[name] = _encode(value)
	return fields

func _supported(value: Variant) -> bool:
	if typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return false
	if value is Object:
		return is_instance_valid(value) and (value is Node or value is RandomNumberGenerator or value.get_script() != null)
	return true

func _encode(value: Variant) -> Variant:
	if value is Node:
		native_references[value.get_instance_id()] = value
		return {"$node": _key(value)}
	if value is Object:
		var id: int = value.get_instance_id()
		if object_ids.has(id):
			return {"$object": object_ids[id]}
		var index := objects.size()
		object_ids[id] = index
		objects.append({})
		if value is RandomNumberGenerator:
			objects[index] = {"rng": true, "seed": value.seed, "state": value.state}
		else:
			objects[index] = {"script": value.get_script().resource_path, "fields": _fields(value)}
		return {"$object": index}
	if value is Array:
		var values := []
		for item in value:
			values.append(_encode(item) if _supported(item) else null)
		var script: Script = value.get_typed_script()
		return {"$array": values, "type": value.get_typed_builtin(), "class": value.get_typed_class_name(), "script": script.resource_path if script else ""}
	if value is Dictionary:
		var pairs := []
		for k in value:
			if not _supported(k) or not _supported(value[k]):
				continue
			var key: Variant = {"$id": node_ids[k]} if k is int and node_ids.has(k) else _encode(k)
			pairs.append([key, _encode(value[k])])
		return {"$dict": pairs}
	return value

func _decode(value: Variant) -> Variant:
	if not value is Dictionary:
		return value
	if value.has("$node"):
		return _find(value["$node"])
	if value.has("$id"):
		var n := _find(value["$id"])
		return n.get_instance_id() if n else 0
	if value.has("$object"):
		return decoded[int(value["$object"])]
	if value.has("$array"):
		var out := []
		for item in value["$array"]:
			out.append(_decode(item))
		if int(value.type) != TYPE_NIL:
			var script: Script = load(String(value.script)) if value.script != "" else null
			return Array(out, int(value.type), StringName(value["class"]), script)
		return out
	if value.has("$dict"):
		var out := {}
		for pair in value["$dict"]:
			out[_decode(pair[0])] = _decode(pair[1])
		return out
	return value

func _apply_fields(object: Object, fields: Dictionary) -> void:
	for name in fields:
		object.set(name, _decode(fields[name]))

func _key(n: Node) -> Array:
	if n == root:
		return []
	if not root.is_ancestor_of(n):
		return ["$outside"]
	var parent := n.get_parent()
	var path := _key(parent)
	var label := String(n.name)
	if label.begins_with("@"):
		var index := 0
		for sibling in parent.get_children():
			if sibling == n:
				break
			if sibling.get_class() == n.get_class():
				index += 1
		path.append([n.get_class(), index])
	else:
		path.append(label)
	return path

func _find(path: Array) -> Node:
	var current := root
	for step in path:
		var next: Node = null
		var index := 0
		for child in current.get_children():
			if step is String and String(child.name) == step:
				next = child
				break
			if step is Array and child.get_class() == step[0]:
				if index == int(step[1]):
					next = child
					break
				index += 1
		if next == null:
			return null
		current = next
	return current
