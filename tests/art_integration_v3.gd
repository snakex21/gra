extends Node
## Short acceptance of the actual campaign/trial hooks. No repeated boss fights.
var failures := 0
var report := {"campaign": [], "trials": [], "checkpoints": []}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	check(not OS.has_environment("NO_ART"), "Integration requires the production art hooks (NO_ART unset)")
	var game := _game()
	game.start(true)
	_freeze_physics(game)
	_check_actors(game.refs, "campaign")
	for kind: StringName in BossRoster.PLAYABLE:
		game._wake(kind)
		_freeze_physics(game)
		await get_tree().process_frame
		report.campaign.append(_check_encounter(game.colossus(), game.refs.arena, kind, "campaign"))
		game._sleep()
		await get_tree().process_frame
	game.free()
	await get_tree().process_frame
	for kind: StringName in BossRoster.PLAYABLE:
		await _trial(kind)
	await _paired_checkpoint()
	await _dormin_checkpoint()
	check(report.campaign.size() == 21 and report.trials.size() == 21, "Incomplete campaign/trial roster")
	check(report.checkpoints.size() == 2, "Checkpoint cases were not both run")
	report["failures"] = failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/art_integration_v3.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ART_INTEGRATION_V3: %d failures; %d campaign wakes; %d native trials; %d binary checkpoints" % [failures, report.campaign.size(), report.trials.size(), report.checkpoints.size()])
	get_tree().quit(1 if failures else 0)

func _game() -> GameWorld:
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	game.set_physics_process(false)
	return game

func _freeze_physics(node: Node) -> void:
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_physics(child)

func _check_actors(refs: Dictionary, context: String) -> void:
	var p := refs.player as PlayerCharacter
	var h := refs.horse as Horse
	var traveler := p.visual.get_node_or_null("TravelerArt") as TravelerArt
	check(traveler != null and is_instance_valid(traveler.model), context + " TravelerArt ready hook missing")
	check(p.visual._blade != null and p.actions != null and p.find_children("*", "CollisionShape3D", true, false).size() > 0, context + " native player/sword missing")
	for bone in AgroArt.BONES:
		var art := h.get_node_or_null("Vis_%s/AgroArtV3" % bone)
		check(art != null and art.get_child_count() == 3, context + " Agro ready hook incomplete: " + String(bone))
	check(h.find_children("*", "CollisionShape3D", true, false).size() > 0, context + " horse collider missing")

func _check_encounter(c: Colossus, arena: Node, kind: StringName, context: String) -> Dictionary:
	var bodies: Array[Colossus] = [c]
	if c is CelosiaCenobia:
		bodies.clear()
		for guardian in c.guardians:
			bodies.append(guardian)
		check(c.guardians.size() == 2 and c.weak_points.size() == 2, context + " paired coordinator incomplete")
	var segments := 0
	var colliders := 0
	var patches := 0
	var sigils := 0
	var lods := 0
	for body in bodies:
		check(body.skeleton != null and body.skeleton.get_bone_count() > 0, context + "/" + String(kind) + " native rig missing")
		check(not body.segments.is_empty(), context + "/" + String(kind) + " native segments missing")
		if not body is Dormin:
			check(body.get_node_or_null("ColossiV3Render") is ColossusArtV3, context + "/" + String(kind) + " V3 adapter missing")
		for segment: BodySegment in body.segments:
			segments += 1
			check(segment.colossus == body and segment.bone_idx >= 0 and segment.bone_idx < body.skeleton.get_bone_count(), context + "/" + String(kind) + " segment detached from original rig")
			var art := segment.get_node_or_null("DorminArtV3" if body is Dormin else "ColossiV3Visual")
			check(art != null, context + "/" + String(kind) + " segment sculpture missing: " + String(segment.bone_name))
			if art:
				check(art.find_children("*", "CollisionObject3D", true, false).is_empty() and art.find_children("*", "CollisionShape3D", true, false).is_empty(), context + "/" + String(kind) + " cosmetic collision added")
				for level in 3:
					var visual := art.get_node_or_null("LOD%d" % level) as MeshInstance3D
					check(visual != null and visual.mesh != null, context + "/" + String(kind) + " missing LOD%d" % level)
					lods += 1 if visual != null else 0
			var physical := 0
			for child in segment.get_children():
				if child is CollisionShape3D:
					check(child.shape != null, context + "/" + String(kind) + " empty native collider")
					physical += 1
					colliders += 1
					patches += 1 if child is ClimbPatch else 0
				elif child is WeakPoint:
					sigils += 1
					check(child.segment == segment and is_instance_valid(child._mesh) and child._mesh.mesh != null and not art.is_ancestor_of(child), context + "/" + String(kind) + " native sigil lost or dressed over")
	# Flying guardians deliberately retain render-only wing segments in their native rig.
	check(colliders > 0 and patches > 0 and sigils > 0, context + "/" + String(kind) + " physical body, climb route or sigils missing")
	_check_puzzle(c, arena, context)
	var before := _physics(c)
	var nodes_before := c.find_children("*", "Node", true, false).size()
	ArenaArt.dress_colossus_v3(c, kind)
	check(before == _physics(c) and nodes_before == c.find_children("*", "Node", true, false).size(), context + "/" + String(kind) + " repeated hook changed native state or duplicated art")
	return {"kind": String(kind), "bodies": bodies.size(), "segments": segments, "colliders": colliders, "climb_patches": patches, "sigils": sigils, "lod_nodes": lods, "native_state_unchanged": before == _physics(c)}

func _check_puzzle(c: Colossus, arena: Node, context: String) -> void:
	if c is Argus:
		check(is_instance_valid(c.ruins) and is_instance_valid(c.ruins.ramp) and not c.ruins.route_open, context + " Argus terrain puzzle missing")
	elif c is Saru:
		check(is_instance_valid(c.bridge) and not c.bridge.route_open, context + " Saru bridge puzzle missing")
	elif c is Spider:
		check(c.anchors.size() == 3 and not c.route_open, context + " Spider anchors missing")
	elif c is Basaran:
		check(arena.find_children("*", "BasaranGeyser", true, false).size() >= 2, context + " Basaran geysers missing")
	elif c is Phalanx:
		check(c.sacs.size() == 3 and c.weak_points.size() == 3, context + " Phalanx bow targets missing")
	elif c is Pelagia:
		check(c.teeth.size() == 3 and c.broken_ruins == [false, false, false], context + " Pelagia control teeth missing")
	elif c is Dormin:
		check(c.seals.size() == 3 and c._patches.size() > 0 and c.back_sigil != null, context + " Dormin shadow locks missing")
	elif c is CelosiaCenobia:
		check(c._columns.size() >= 2 and c._flame != null, context + " paired fire/column puzzle missing")
	elif c is Phaedra:
		check(not c.tunnels.is_empty(), context + " Phaedra tunnels missing")

func _physics(c: Colossus) -> Array:
	var state := []
	for child in c.get_children():
		if child is Colossus:
			state.append(_physics(child))
	for i in c.skeleton.get_bone_count():
		state.append([c.skeleton.get_bone_rest(i), c.skeleton.get_bone_pose(i)])
	for segment: BodySegment in c.segments:
		state.append([segment.transform, segment.collision_layer, segment.collision_mask])
		for child in segment.get_children():
			if child is CollisionShape3D:
				state.append([child.get_instance_id(), child.transform, child.shape.get_rid(), child.disabled])
			elif child is WeakPoint:
				state.append([child.transform, child.health, child.state])
	return state

func _trial(kind: StringName) -> void:
	var scene := load(BossRoster.scene(kind)) as PackedScene
	check(scene != null, "Native trial scene missing: " + String(kind))
	if not scene:
		return
	var trial := scene.instantiate()
	add_child(trial)
	_freeze_physics(trial)
	check(trial.get_node_or_null("TrialMenu") is TrialMenu, "TrialMenu hook missing: " + String(kind))
	var refs: Dictionary = trial.get("refs")
	var c := refs.get("colossus", refs.get(kind)) as Colossus
	check(c != null, "Native trial references have no boss: " + String(kind))
	if not c:
		trial.free()
		return
	if not c is Dormin:
		check(c.find_children("ColossiV3Render", "ColossusArtV3", true, false).is_empty(), "Trial dressing unexpectedly ran before deferred hook: " + String(kind))
	await get_tree().process_frame
	await get_tree().process_frame
	_check_actors(refs, "trial/" + String(kind))
	report.trials.append(_check_encounter(c, trial, kind, "trial"))
	trial.free()
	await get_tree().process_frame

func _snapshot(game: GameWorld) -> Dictionary:
	var data: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	for node: Dictionary in data.nodes:
		check(not str(node.key).contains("ColossiV3Render") and not str(node.key).contains("TravelerArt"), "Cosmetic adapter was serialized into native node state")
	for object: Dictionary in data.objects:
		check(not String(object.get("script", "")).contains("colossus_art_v3") and not String(object.get("script", "")).contains("traveler_art"), "Cosmetic object serialized")
	return data

func _paired_checkpoint() -> void:
	var game := _game()
	game.start(true)
	game._wake(&"celosia_cenobia")
	_freeze_physics(game)
	var pair := game.colossus() as CelosiaCenobia
	# A mixed checkpoint fixture: one opened armour/damaged sigil, one still locked.
	pair.guardians[0].open_armour()
	pair.guardians[0].weak_point.health = 31.25
	pair.guardians[0].mode = PairedSentinel.Mode.RECOVER
	pair.guardians[0].timer = 2.375
	await get_tree().process_frame
	await get_tree().process_frame
	check(pair.guardians[0]._fur.all(func(p: ClimbPatch) -> bool: return not p.disabled) and pair.guardians[1]._fur.all(func(p: ClimbPatch) -> bool: return p.disabled), "Mixed checkpoint fixture did not open its native climb route")
	var data := _snapshot(game)
	var restored := WorldSnapshot.restore(game, data)
	check(restored, "Art-enabled paired binary checkpoint failed to restore")
	_freeze_physics(game)
	await get_tree().process_frame
	await get_tree().process_frame
	pair = game.colossus() as CelosiaCenobia
	_check_actors(game.refs, "restored pair")
	check(pair.guardians[0].armour_open and not pair.guardians[1].armour_open and pair.guardians[0].weak_point.health == 31.25 and pair.guardians[0].timer == 2.375, "Paired mixed armour/progress was lost")
	var gate_states := []
	for i in 2:
		var guardian := pair.guardians[i]
		var render := guardian.get_node_or_null("ColossiV3Render") as ColossusArtV3
		check(render != null and render._gates.size() == 1, "Restored paired wool has no live gate")
		if render:
			render._process(0)
			for gate: Dictionary in render._gates:
				check(is_instance_valid(gate.visual) and gate.visual.visible == (i == 0), "Restored cosmetic wool does not match locked climb route")
				var disabled := []
				for patch: ClimbPatch in gate.patches:
					disabled.append(patch.disabled)
					check(is_instance_valid(patch) and guardian.is_ancestor_of(patch) and patch.disabled == (i == 1), "Restored wool points to missing/stale native climb patch")
				gate_states.append({"guardian": i, "armour_open": guardian.armour_open, "wool_visible": gate.visual.visible, "patch_disabled": disabled})
	report.checkpoints.append({"kind": "celosia_cenobia", "restored": restored, "mixed_armour": true, "health": pair.guardians[0].weak_point.health, "gates": gate_states, "bytes": var_to_bytes(data).size()})
	game.free()
	await get_tree().process_frame

func _dormin_checkpoint() -> void:
	var game := _game()
	game.start(true)
	game._wake(&"dormin")
	_freeze_physics(game)
	var dormin := game.colossus() as Dormin
	dormin.seals[0].broken = true
	dormin.seals[0]._mesh.visible = false
	dormin.seals[1].exposed_left = 3.125
	dormin.seals_broken = 1
	# Let Dormin's authored deferred spawn locks settle before taking the fixture.
	await get_tree().process_frame
	await get_tree().process_frame
	check(dormin._patches.all(func(p: ClimbPatch) -> bool: return p.disabled), "Dormin checkpoint fixture was captured before native spawn locks settled")
	var data := _snapshot(game)
	check(WorldSnapshot.restore(game, data), "Art-enabled Dormin binary checkpoint failed to restore")
	_freeze_physics(game)
	await get_tree().process_frame
	dormin = game.colossus() as Dormin
	_check_actors(game.refs, "restored Dormin")
	check(dormin.seals_broken == 1 and dormin.seals[0].broken and not dormin.seals[0]._mesh.visible and dormin.seals[1].exposed_left == 3.125, "Dormin shadow lock progress lost")
	for patch: ClimbPatch in dormin._patches:
		check(is_instance_valid(patch) and dormin.is_ancestor_of(patch) and patch.disabled, "Dormin locked native climb patches not restored")
	var metric := _check_encounter(dormin, game.refs.arena, &"dormin", "restored")
	report.checkpoints.append({"kind": "dormin", "restored": true, "shadow_locks": dormin.seals_broken, "segments": metric.segments, "lod_nodes": metric.lod_nodes, "bytes": var_to_bytes(data).size()})
	game.free()
	await get_tree().process_frame
