class_name CaveArena
## Hollowvault shell and Deeprelic ruins over a closed, stable gameplay enclosure.
const PLAYER_START := Vector3(0, 0.95, 90)
const HORSE_START := Vector3(4.5, 0, 87)

static func build(parent: Node3D) -> Dictionary:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.19, 0.18)
	var ground := TerrainKit.box(parent, Vector3(0, -1, 0), Vector3(350, 2, 350), dark)
	ground.name = "Ground"
	for mesh in ground.get_children():
		if mesh is GeometryInstance3D:
			mesh.layers = 2
	# Main chamber: clear crown / climb route; a ceiling blocks sunlight in greybox too.
	for b in [[Vector3(-22.5, 13, 0), Vector3(2, 26, 58)], [Vector3(22.5, 13, 0), Vector3(2, 26, 58)],
		[Vector3(0, 13, -29), Vector3(47, 26, 2)], [Vector3(0, 26, 0), Vector3(47, 2, 60)],
		[Vector3(-14, 13, 29), Vector3(17, 26, 2)], [Vector3(14, 13, 29), Vector3(17, 26, 2)],
		[Vector3(0, 17, 29), Vector3(12, 20, 2)]]:
		var wall := TerrainKit.box(parent, b[0], b[1], dark)
		wall.name = "CaveShell"
		wall.set_meta(&"cave_shell", true)
	# Entrance tunnel reaches the world corridor; Agro fits, the boss cannot leave.
	for b in [[Vector3(-6.4, 3.5, 99), Vector3(1.2, 7, 140)], [Vector3(6.4, 3.5, 99), Vector3(1.2, 7, 140)],
		[Vector3(0, 7, 99), Vector3(14, 1, 140)]]:
		var wall := TerrainKit.box(parent, b[0], b[1], dark)
		wall.set_meta(&"cave_shell", true)
	# Narrow mineral buttresses frame two hiding places and stay clear of the calf route.
	for side in [-1.0, 1.0]:
		TerrainKit.box(parent, Vector3(side * 17.5, 8, -15), Vector3(3, 16, 8), dark)
	return {"player": [PLAYER_START, 0.0], "horse": [HORSE_START, 0.0]}

static func dress(parent: Node3D) -> void:
	for child in parent.get_children():
		if child.has_meta(&"cave_shell"):
			for mesh in child.get_children():
				if mesh is MeshInstance3D:
					mesh.visible = false
	_asset(parent, "hollowvault", "great_closed_dome", Vector3.ZERO)
	for i in 12:
		_asset(parent, "hollowvault", "vault_tunnel_12m", Vector3(0, 0, 35.5 + i * 11.5))
	for side in [-1.0, 1.0]:
		_asset(parent, "hollowvault", "stalagmite_great", Vector3(side * 18.5, 0, -18))
		_asset(parent, "hollowvault", "calcite_curtain", Vector3(side * 19.0, 0, -10))
		_asset(parent, "deeprelic", "fractured_column", Vector3(side * 14, 0, 19))
		_asset(parent, "deeprelic", "unlit_lamp", Vector3(side * 7, 0, 23))
	_asset(parent, "deeprelic", "offering_table", Vector3(0, 0, -23))
	_asset(parent, "deeprelic", "abandoned_bedroll", Vector3(-16, 0, 20))
	_asset(parent, "deeprelic", "expedition_chest", Vector3(-18, 0, 20))
	_asset(parent, "deeprelic", "broken_lintel_gate", Vector3(0, 0, 27))
	for side in [-1.0, 1.0]:
		ArenaArt.encounter_prop(parent, "cave_relic_lamp", Vector3(side * 8, 0, 20), 0.0, 2)
		ArenaArt.encounter_prop(parent, "cave_offering_marker", Vector3(side * 4, 0, -22), 0.0, 2)

static func _asset(parent: Node3D, kit: String, id: String, pos: Vector3) -> void:
	if ArenaArt._planner:
		ArenaArt._planner.add(func() -> void: _asset(parent, kit, id, pos))
		return
	var n := Node3D.new()
	n.set_script(load("res://art/scripts/%s_asset.gd" % kit))
	n.name = "CaveArt_" + id
	n.set(&"model_id", id)
	n.set(&"collidable", false)
	n.position = pos
	parent.add_child(n)
	for mesh in n.get_children():
		if mesh is GeometryInstance3D:
			mesh.layers = 2
			# Only one LOD casts: overlapping dome LODs create stripes in the spot shadow.
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mesh.name == "LOD0" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func build_encounter(parent: Node3D, with_input := false, with_art := true) -> Dictionary:
	build(parent)
	if with_art:
		dress(parent)
	var c := CaveColossus.new()
	c.name = "CaveColossus"
	parent.add_child(c)
	c.teleport(Vector3.ZERO, PI)
	c.reset_encounter(c.global_transform, true)
	if with_art:
		ArenaArt.dress_cave_colossus(c)
	var horse := Horse.new()
	horse.name = "Agro"
	parent.add_child(horse)
	horse.teleport(HORSE_START, 0.0)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	parent.add_child(p)
	p.global_position = PLAYER_START
	p.spawn_transform = p.global_transform
	p.beam.lantern = true
	var cam := PlayerCamera.new()
	cam.player = p
	cam.focus_target = c
	parent.add_child(cam)
	cam.current = true
	cam.snap_behind_player()
	var e := BossEncounter.new()
	parent.add_child(e)
	var players: Array[PlayerCharacter] = [p]
	e.setup(c, players, horse)
	if with_input:
		var input := FlatInputSource.new()
		input.actions = p.actions
		input.view = cam
		parent.add_child(input)
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = cam
	hud.horse = horse
	hud.colossus = c
	hud.encounter = e
	hud.message = "V — światło miecza. Wywab kolosa ze szczeliny."
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	parent.add_child(layer)
	return {"player": p, "colossus": c, "horse": horse, "camera": cam, "encounter": e, "hud": hud}
