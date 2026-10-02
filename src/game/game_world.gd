class_name GameWorld
extends Node3D
## The whole game in one continuous world (WorldMap): the valley in the middle, and
## behind each gate a corridor to that colossus' arena. One player, one Agro, one camera
## for the whole game; no loading between the valley and an arena.
##
##   new game / load -> the temple in the valley
##   through the open gate -> the corridor: that colossus wakes up (built, simulated)
##   back through the gate into the valley -> it goes again (the fight starts over)
##   defeated -> (the fall of the colossus) -> fade -> the temple, saved, the next gate open
##   all four defeated -> the temple, every gate closed, the end
##
## Only one colossus exists at a time. ``region_kind`` is where the game is: VALLEY, or
## the colossus that is awake. Everything runs in physics ticks (bots, tests and the
## FPS-independence check).

signal region_loaded(kind: StringName)
signal colossus_defeated(colossus: StringName)
signal game_completed

enum Phase { PLAYING, FADE_OUT, LOADING, FADE_IN }

const VALLEY := &"valley"
## Brain seeds of the arenas (each fight is the same fight every time).
const SEEDS := {&"valus": 7, &"quadratus": 11, &"gaius": 13, &"phaedra": 17}

@export var with_input := true
@export var with_art := true
## Save file ("" = never save, e.g. tests that do not want to touch user://).
@export var save_path := GameState.DEFAULT_PATH
@export var fade_time := 0.6
## Seconds the fall of a defeated colossus is shown before going back to the temple.
@export var outro_time := 12.0
## Added to the arenas' brain seeds (soaks play other fights; 0 in the game).
@export var seed_offset := 0

var state := GameState.new()
## Player settings, applied to the input, rider and HUD.
var settings := Settings.new()
## The world (valley, corridors, arenas, actors).
var region: Node3D
var region_kind: StringName = &""
## The arenas in the world: {kind: {"root", "xf", "points"}}.
var arenas := {}
## The current objects: player, horse, camera, hud, input, gates, valley; while a
## colossus is awake also colossus, encounter, arena (its root) and the colossus' name.
var refs := {}
var phase := Phase.PLAYING
## Seconds since the last change of region_kind.
var region_time := 0.0
var transitions := 0

var _phase_t := 0.0
var _resets_seen := 0
var _awake: Array[Node] = []
var _fade: ColorRect
var _sun: DirectionalLight3D


## Starts the game: loads the save (unless ``new_game``) and builds the temple.
func start(new_game := false) -> void:
	state = GameState.new()
	if not new_game and save_path != "":
		state.load_from(save_path)
	phase = Phase.PLAYING
	_fade.color.a = 0.0
	_build_world()


## Starts from a given progress (a replay's start), without touching the save file.
func start_from(progress: Dictionary) -> void:
	state = GameState.new()
	state.from_dict(progress)
	phase = Phase.PLAYING
	_fade.color.a = 0.0
	_build_world()


## Back to the title: the world goes, the progress stays saved.
func stop() -> void:
	if is_instance_valid(region):
		remove_child(region)
		region.free()
	region = null
	refs = {}
	arenas = {}
	_awake.clear()
	region_kind = &""
	phase = Phase.PLAYING
	_fade.color.a = 0.0


func has_save() -> bool:
	return save_path != "" and FileAccess.file_exists(save_path)


## Settings onto the current region (and every later one).
func apply_settings(s: Settings) -> void:
	settings = s
	var input: Variant = refs.get("input")
	if input is FlatInputSource:
		(input as FlatInputSource).mouse_sensitivity = s.mouse_sensitivity
		(input as FlatInputSource).invert_y = s.invert_y
	if player():
		player().riding.steer_relative = s.ride_relative
	var hud: Variant = refs.get("hud")
	if hud is PlayerHud:
		(hud as PlayerHud).show_help = s.show_help
		(hud as PlayerHud).show_debug = s.show_debug


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 160.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3.ZERO, -Valley.SUN_DIRECTION.normalized(), Vector3.UP)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(env)
	ArenaArt._daylight(self)
	var layer := CanvasLayer.new()
	layer.layer = 10
	_fade = ColorRect.new()
	_fade.color = Color(0.92, 0.93, 0.95, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	add_child(layer)
	# After the region (player, colossus, encounter) each tick.
	process_physics_priority = 60


func player() -> PlayerCharacter:
	return refs.get("player")


func colossus() -> Colossus:
	return refs.get("colossus")


func _physics_process(delta: float) -> void:
	if region_kind == &"":
		return   # at the title: nothing loaded
	state.play_time += delta
	region_time += delta
	match phase:
		Phase.PLAYING:
			_play(delta)
		Phase.FADE_OUT:
			_phase_t += delta
			_fade.color.a = clampf(_phase_t / fade_time, 0.0, 1.0)
			if _phase_t >= fade_time:
				phase = Phase.LOADING
		Phase.LOADING:
			# Back at the temple after a victory: the world again, with the next gate open.
			_build_world()
			phase = Phase.FADE_IN
			_phase_t = 0.0
		Phase.FADE_IN:
			_phase_t += delta
			_fade.color.a = 1.0 - clampf(_phase_t / fade_time, 0.0, 1.0)
			if _phase_t >= fade_time:
				phase = Phase.PLAYING


func _play(_delta: float) -> void:
	var p := player()
	if p == null:
		return
	var gates: Dictionary = refs.gates
	if region_kind == VALLEY:
		var next := state.next_colossus()
		p.beam.target = (gates[next].trigger as Vector3) if next != &"" else Vector3.INF
		if p.beam.locked and refs.has("hud"):
			# The hint has done its job once the beam gathered.
			(refs.hud as PlayerHud).message = ""
		if next != &"" and Valley.passed_gate(gates[next], p.global_position):
			_wake(next)
		return
	# A colossus is awake.
	var c := colossus()
	var e: BossEncounter = refs.encounter
	p.beam.target = c.beam_target() if not c.is_defeated() else Vector3.INF
	var wp := c.beam_weak_point()
	if wp and p.beam.focus > 0.3:
		# The beam rests on the weak point: it lights up (the oldest guide in the game).
		wp.revealed = maxf(wp.revealed, p.beam.focus)
	if e.resets != _resets_seen:
		state.deaths += e.resets - _resets_seen
		_resets_seen = e.resets
	if e.state == BossEncounter.State.DEFEATED and e.time - e.defeat_time >= outro_time:
		state.mark_defeated(region_kind)
		colossus_defeated.emit(region_kind)
		_save()
		_go(VALLEY, false)
	elif e.state == BossEncounter.State.RUNNING and _back_in_valley(gates[region_kind], p.global_position):
		# Back through the gate into the valley: the colossus goes, the fight starts over.
		_sleep()


## Fade to the temple (after a victory). ``riding`` is kept for old callers.
func _go(_kind: StringName, _riding: bool) -> void:
	phase = Phase.FADE_OUT
	_phase_t = 0.0
	transitions += 1


func _save() -> void:
	if save_path != "":
		state.save(save_path)


static func _back_in_valley(gate: Dictionary, p: Vector3) -> bool:
	var d: Vector3 = p - (gate.pos as Vector3)
	var out: Vector3 = (gate.out as Vector3).normalized()
	var along := d.dot(out)
	var across := d - out * along
	across.y = 0.0
	return along < -Valley.GATE_TRIGGER * 0.5 and across.length() < Valley.GATE_WIDTH


## The whole world, the player and Agro at the temple.
func _build_world() -> void:
	if is_instance_valid(region):
		remove_child(region)
		region.free()
	refs = {}
	_awake.clear()
	region = Node3D.new()
	region.name = "World"
	add_child(region)
	var v := Valley.build(region, state.next_colossus(), with_art, true)
	arenas = WorldMap.build(region, _build_arena, with_art)
	_spawn_actors(v.spawn, v.spawn_yaw, v.horse)
	refs.gates = v.gates
	refs.valley = v
	region_kind = VALLEY
	region_time = 0.0
	_resets_seen = 0
	apply_settings(settings)
	region_loaded.emit(VALLEY)
	if state.is_complete():
		game_completed.emit()


## An arena's ground and layout in its root (local frame), with its art.
func _build_arena(kind: StringName, root: Node3D) -> Dictionary:
	var points: Dictionary
	match kind:
		&"valus", &"gaius":
			points = ValusArena.build(root)
		&"quadratus":
			points = QuadratusArena.build(root)
		&"phaedra":
			points = PhaedraArena.build(root)
	_disc_ground(root)
	if with_art:
		match kind:
			&"valus":
				ArenaArt.dress_arena(root, Vector3(0, 0, 1), 55.0)
			&"gaius":
				ArenaArt.dress_arena(root, Vector3(0, 0, 1), 55.0, 5113)
			&"quadratus":
				ArenaArt.dress_arena(root, Vector3(0, 0, 1), 75.0, 4021)
			&"phaedra":
				ArenaArt.dress_fen(root, points.tunnels, 75.0, 6047)
	return points


## The arenas' square test ground becomes a disc (they sit side by side in the world).
static func _disc_ground(root: Node3D) -> void:
	var ground := root.get_node_or_null("Ground")
	if ground == null:
		return
	for c in ground.get_children():
		if c is CollisionShape3D:
			var cyl := CylinderShape3D.new()
			cyl.radius = WorldMap.GROUND_RADIUS
			cyl.height = 2.0
			(c as CollisionShape3D).shape = cyl
		elif c is MeshInstance3D:
			var m := CylinderMesh.new()
			m.top_radius = WorldMap.GROUND_RADIUS
			m.bottom_radius = WorldMap.GROUND_RADIUS
			m.height = 2.0
			m.radial_segments = 48
			(c as MeshInstance3D).mesh = m
			(c as MeshInstance3D).position = Vector3(0, -1, 0)


func _spawn_actors(spawn: Vector3, yaw: float, horse_at: Vector3) -> void:
	var horse := Horse.new()
	horse.name = "Agro"
	region.add_child(horse)
	horse.teleport(horse_at, yaw)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	region.add_child(p)
	p.global_position = spawn
	p.facing = Basis(Vector3.UP, yaw) * Vector3.FORWARD
	p.spawn_transform = p.global_transform
	p.actions.view_basis = Basis(Vector3.UP, yaw)
	p.beam.sun_direction = Valley.SUN_DIRECTION.normalized()
	p.reset_physics_interpolation()
	var cam := PlayerCamera.new()
	cam.name = "Camera1"
	cam.player = p
	region.add_child(cam)
	cam.current = true
	cam.snap_behind_player()
	var input: FlatInputSource = null
	if with_input:
		input = FlatInputSource.new()
		input.actions = p.actions
		input.view = cam
		region.add_child(input)
	var layer := CanvasLayer.new()
	var hud := PlayerHud.new()
	hud.player = p
	hud.camera = cam
	hud.horse = horse
	hud.message = _valley_message()
	layer.add_child(hud)
	region.add_child(layer)
	refs.merge({"player": p, "horse": horse, "camera": cam, "hud": hud, "input": input}, true)


func _valley_message() -> String:
	if state.is_complete():
		return "Wszystkie kolosy pokonane"
	if state.defeated.is_empty():
		return "Unieś miecz do słońca (V), światło wskaże drogę"
	return ""


## The colossus behind ``kind``'s gate wakes up: built in its arena, with its encounter.
func _wake(kind: StringName) -> void:
	var a: Dictionary = arenas[kind]
	var root: Node3D = a.root
	var xf: Transform3D = a.xf
	var yaw := xf.basis.get_euler().y
	var p := player()
	var horse: Horse = refs.horse
	var c: Colossus
	match kind:
		&"valus":
			c = Valus.new()
		&"quadratus":
			c = Quadratus.new()
		&"gaius":
			c = Gaius.new()
		&"phaedra":
			var ph := Phaedra.new()
			ph.tunnels = PhaedraArena.tunnels_in_world(a.points.tunnels, xf)
			ph.arena_radius = 65.0
			refs.tunnels = ph.tunnels
			c = ph
	c.name = String(kind).capitalize()
	c.set(&"brain_seed", SEEDS[kind] + seed_offset)
	# Every colossus starts at its arena's centre facing the way in (local +Z).
	c.rotation.y = PI
	root.add_child(c)
	c.call(&"teleport", xf.origin, yaw + PI)
	c.call(&"reset_encounter", c.global_transform, true)
	if with_art:
		if c is Valus:
			ArenaArt.dress_valus(c)
		else:
			ArenaArt.skin_colossus(c)
	var e := BossEncounter.new()
	e.name = "Encounter"
	root.add_child(e)
	var players: Array[PlayerCharacter] = [p]
	e.setup(c, players, horse)
	# A death puts the player (and Agro) back at the arena's way in.
	e.horse_start = Transform3D(xf.basis, xf * ValusArena.HORSE_START)
	p.spawn_transform = Transform3D(xf.basis, xf * ValusArena.PLAYER_START)
	var arrows := ArrowSystem.of(p)
	e.encounter_reset.connect(func(_n: int) -> void: arrows.clear())
	_awake = [c, e]
	if c is HumanoidBoss:
		var draw := CombatDebugDraw.new()
		draw.valus = c
		root.add_child(draw)
		_awake.append(draw)
		refs.debug_draw = draw
	else:
		refs.debug_draw = c.debug_draw
	(refs.camera as PlayerCamera).focus_target = c
	var hud: PlayerHud = refs.hud
	hud.colossus = c
	hud.encounter = e
	hud.message = ""
	refs.colossus = c
	refs.encounter = e
	refs.arena = root
	refs[kind] = c
	_change_region(kind)


## The awake colossus goes (the player went back into the valley).
func _sleep() -> void:
	var p := player()
	var kind := region_kind
	ArrowSystem.of(p).clear()
	(refs.camera as PlayerCamera).focus_target = null
	var hud: PlayerHud = refs.hud
	hud.colossus = null
	hud.encounter = null
	p.auto_respawn = true
	var g: Dictionary = refs.gates[kind]
	p.spawn_transform = Transform3D(Basis(Vector3.UP, atan2((g.out as Vector3).x, (g.out as Vector3).z)), Valley.on_ground((g.pos as Vector3) - (g.out as Vector3) * 10.0, 0.95))
	for n in _awake:
		if is_instance_valid(n):
			n.queue_free()
	_awake.clear()
	for k in ["colossus", "encounter", "arena", "debug_draw", "tunnels", kind]:
		refs.erase(k)
	_change_region(VALLEY)


func _change_region(kind: StringName) -> void:
	region_kind = kind
	region_time = 0.0
	_resets_seen = 0
	transitions += 1
	region_loaded.emit(kind)
