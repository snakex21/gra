class_name GameWorld
extends Node3D
## The whole game: the valley and the three arenas as regions, one loaded at a time.
##
##   new game / load -> VALLEY (temple) -- through the open gate --> ARENA (the next colossus)
##   ARENA: defeated -> (the fall of the colossus) -> VALLEY, back at the temple, saved
##          back out through the arena entrance -> VALLEY, at that gate
##   all three defeated -> VALLEY, every gate closed, the end
##
## Only the loaded region simulates (one colossus at a time). Moving between regions is
## a short fade; whoever rode through the gate arrives in the saddle. The player, Agro,
## the camera and the HUD are rebuilt with each region (the arenas own theirs); what
## carries over is the GameState and whether the player was riding.
## Everything runs in physics ticks (bots, tests and the FPS-independence check).

signal region_loaded(kind: StringName)
signal colossus_defeated(colossus: StringName)
signal game_completed

enum Phase { PLAYING, FADE_OUT, LOADING, FADE_IN }

const VALLEY := &"valley"
## Brain seeds of the arenas (each fight is the same fight every time).
const SEEDS := {&"valus": 7, &"quadratus": 11, &"gaius": 13}
## How far behind the arena entrance the way back to the valley starts (arena frame, +Z).
const ARENA_EXIT_Z := 104.0

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
var region: Node3D
var region_kind: StringName = &""
## The current region's objects: player, horse, camera, hud, input, and in an arena
## colossus + encounter, in the valley gates.
var refs := {}
var phase := Phase.PLAYING
## Seconds in the current region.
var region_time := 0.0
var transitions := 0

var _phase_t := 0.0
var _next_kind: StringName = &""
var _arrive_riding := false
var _arrive_gate: StringName = &""
var _resets_seen := 0
var _fade: ColorRect
var _sun: DirectionalLight3D


## Starts the game: loads the save (unless ``new_game``) and builds the temple.
func start(new_game := false) -> void:
	if not new_game and save_path != "":
		state.load_from(save_path)
	_build_region(VALLEY)


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
			_build_region(_next_kind)
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
	if region_kind == VALLEY:
		var next := state.next_colossus()
		var gates: Dictionary = refs.gates
		p.beam.target = (gates[next].trigger as Vector3) if next != &"" else Vector3.INF
		if p.beam.locked and refs.has("hud"):
			# The hint has done its job once the beam gathered.
			(refs.hud as PlayerHud).message = ""
		if next != &"" and Valley.passed_gate(gates[next], p.global_position):
			_go(next, p.is_riding())
		return
	# Arena.
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
	elif e.state == BossEncounter.State.RUNNING and p.global_position.z > ARENA_EXIT_Z:
		# Back out through the entrance: to the valley, at this arena's gate.
		_arrive_gate = region_kind
		_go(VALLEY, p.is_riding())


func _go(kind: StringName, riding: bool) -> void:
	_next_kind = kind
	_arrive_riding = riding
	phase = Phase.FADE_OUT
	_phase_t = 0.0
	transitions += 1


func _save() -> void:
	if save_path != "":
		state.save(save_path)


func _build_region(kind: StringName) -> void:
	if is_instance_valid(region):
		remove_child(region)
		region.free()
	refs = {}
	region = Node3D.new()
	region.name = "Region_%s" % kind
	add_child(region)
	region_kind = kind
	region_time = 0.0
	_resets_seen = 0
	if kind == VALLEY:
		_build_valley()
	else:
		_build_arena(kind)
	var p := player()
	p.beam.sun_direction = Valley.SUN_DIRECTION.normalized()
	if _arrive_riding:
		var h: Horse = refs.horse
		# Agro under the player, already moving on.
		h.teleport(p.global_position, atan2(-p.facing.x, -p.facing.z))
		p.riding.mount_now(h)
	_arrive_riding = false
	_arrive_gate = &""
	region_loaded.emit(kind)
	if kind == VALLEY and state.is_complete():
		game_completed.emit()


func _build_valley() -> void:
	var v := Valley.build(region, state.next_colossus(), with_art)
	var spawn: Vector3 = v.spawn
	var yaw: float = v.spawn_yaw
	var horse_at: Vector3 = v.horse
	if _arrive_gate != &"":
		# Coming back from an arena: just inside its gate, facing the valley.
		var g: Dictionary = v.gates[_arrive_gate]
		var out: Vector3 = g.out
		spawn = Valley.on_ground((g.pos as Vector3) - out * 10.0, 0.95)
		yaw = atan2(out.x, out.z)
		horse_at = Valley.on_ground((g.pos as Vector3) - out * 13.0 + out.cross(Vector3.UP) * 3.0)
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
	refs = {"player": p, "horse": horse, "camera": cam, "hud": hud, "input": input, "gates": v.gates, "valley": v}


func _valley_message() -> String:
	if state.is_complete():
		return "Wszystkie kolosy pokonane"
	if state.defeated.is_empty():
		return "Unieś miecz do słońca (V), światło wskaże drogę"
	return ""


func _build_arena(kind: StringName) -> void:
	var r: Dictionary
	match kind:
		&"valus":
			r = ValusArena.build_encounter(region, with_input, SEEDS[kind] + seed_offset, with_art)
			r.colossus = r.valus
		&"quadratus":
			r = QuadratusArena.build_encounter(region, with_input, SEEDS[kind] + seed_offset, with_art)
			r.colossus = r.quadratus
		&"gaius":
			r = GaiusArena.build_encounter(region, with_input, SEEDS[kind] + seed_offset, with_art)
			r.colossus = r.gaius
	refs = r
