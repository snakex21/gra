class_name GameBot
extends Node
## Plays the whole game through PlayerActions, like a person: in the valley it finds the
## way with the sword's beam only (it turns the view until the beam gathers into one
## line; it never reads the gate's position), rides Agro that way, checks the beam again
## from the saddle every few seconds, and in an arena hands the fight to that colossus'
## bot (ValusBot / QuadratusBot / GaiusBot). Back at the temple, it starts again.
##
##   FIND (beam, standing) -> TO_HORSE -> MOUNT -> RIDE (beam checks, detours) -> ARENA
##
## Every phase has a timeout, recorded as a stall. Used by tests/game_soak.gd.

signal finished(result: Dictionary)

enum Phase { FIND, TO_HORSE, MOUNT, RIDE, ARENA, DONE }

const TIMEOUTS := {Phase.FIND: 20.0, Phase.TO_HORSE: 40.0, Phase.MOUNT: 10.0, Phase.RIDE: 150.0, Phase.ARENA: 420.0}
## Seconds between beam checks while riding.
const RIDE_CHECK := 7.0

var game: GameWorld
var verbose := false
var phase := Phase.FIND
var phase_time := 0.0
var time := 0.0
var events: Array[String] = []
var stats := {"stalls": [], "beam_sweeps": 0, "beam_locks": 0, "beam_unlit": 0, "detours": 0, "valley_time": 0.0,
	"ride_time": 0.0, "fights": {}, "boss_results": []}
var result := {}

var boss_bot: Node
var _heading := Vector3.FORWARD
var _sweep_yaw := 0.0
var _sweep_dir := 1.0
var _sweep_best := -1.0
var _sweep_prev := 0.0
var _sweeping := false
var _since_check := 0.0
var _slow := 0.0
var _detour := 0.0
var _detour_side := 1.0
var _dismounting := false


func setup(p_game: GameWorld) -> void:
	game = p_game
	game.region_loaded.connect(_on_region)
	game.game_completed.connect(func() -> void: _finish(true, "all colossi defeated"))
	if game.region_kind != &"":
		_on_region(game.region_kind)


func _ready() -> void:
	process_physics_priority = -6


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE or game == null or game.player() == null:
		return
	time += delta
	phase_time += delta
	if TIMEOUTS.has(phase) and phase_time > TIMEOUTS[phase]:
		stats.stalls.append(Phase.keys()[phase])
		_log("STALL in %s (%.0f s)" % [Phase.keys()[phase], phase_time])
		_enter(Phase.FIND if phase != Phase.ARENA else Phase.ARENA)
		if phase == Phase.ARENA:
			_finish(false, "arena timeout")
			return
	if game.phase != GameWorld.Phase.PLAYING:
		_player().actions.clear()
		return
	if game.region_kind == GameWorld.VALLEY:
		stats.valley_time += delta
	match phase:
		Phase.FIND:
			_find(delta)
		Phase.TO_HORSE:
			_to_horse()
		Phase.MOUNT:
			_mount()
		Phase.RIDE:
			_ride(delta)
		Phase.ARENA:
			_arena()


func _player() -> PlayerCharacter:
	return game.player()


func _horse() -> Horse:
	return game.refs.get("horse")


# --- valley ------------------------------------------------------------------------------

## Turns the view with the beam raised until it gathers. Returns true when locked
## (``_heading`` is then the way). Works standing and in the saddle.
func _sweep(delta: float) -> bool:
	var p := _player()
	var a := p.actions
	a.beam_held = true
	if not _sweeping:
		_sweeping = true
		_sweep_yaw = atan2(-_heading.x, -_heading.z)
		_sweep_best = -1.0
		_sweep_prev = 0.0
		stats.beam_sweeps += 1
	if p.beam.raise < 1.0:
		a.view_basis = Basis(Vector3.UP, _sweep_yaw)
		return false
	if not p.beam.lit:
		stats.beam_unlit += 1
	var f := p.beam.focus
	if p.beam.locked:
		_heading = Basis(Vector3.UP, _sweep_yaw) * Vector3.FORWARD
		_sweeping = false
		a.beam_held = false
		stats.beam_locks += 1
		return true
	# Fast while the beam is scattered, slow once it starts to gather; turn back when
	# it fades again (we went past the line).
	if f > 0.3 and f < _sweep_prev - 0.03:
		_sweep_dir = -_sweep_dir
	_sweep_prev = f
	var speed := 1.4 if f < 0.3 else 0.35
	_sweep_yaw += _sweep_dir * speed * delta
	a.view_basis = Basis(Vector3.UP, _sweep_yaw)
	return false


func _find(delta: float) -> void:
	var p := _player()
	p.actions.move = Vector2.ZERO
	if p.is_riding():
		_enter(Phase.RIDE)
		return
	if _sweep(delta):
		_log("beam locked: heading %s" % str(_heading.snapped(Vector3.ONE * 0.01)))
		_enter(Phase.TO_HORSE)


func _to_horse() -> void:
	var p := _player()
	var a := p.actions
	if p.is_riding():
		_enter(Phase.RIDE)
		return
	var h := _horse()
	var seat := h.saddle_transform().origin
	var d := _flat(seat - p.global_position)
	if d.length() < 2.2:
		_enter(Phase.MOUNT)
		return
	if d.length() > 30.0 and int(phase_time * 60.0) % 120 == 0:
		a.press_call()
	a.view_basis = Basis.looking_at(d.normalized())
	a.move = Vector2(0, 1)


func _mount() -> void:
	var p := _player()
	var a := p.actions
	a.move = Vector2.ZERO
	if p.is_riding():
		if p.riding.phase == PlayerRiding.Phase.RIDING:
			_enter(Phase.RIDE)
		return
	if int(phase_time * 60.0) % 15 == 0:
		a.press_interact()
	if phase_time > 3.0:
		_enter(Phase.TO_HORSE)


func _ride(delta: float) -> void:
	var p := _player()
	var a := p.actions
	if not p.is_riding():
		_enter(Phase.TO_HORSE)
		return
	stats.ride_time += delta
	var c := _horse().controller
	_since_check += delta
	if _sweeping or _since_check > RIDE_CHECK:
		# Beam check from the saddle: steer relative to the horse meanwhile (straight on).
		p.riding.steer_relative = true
		a.move = Vector2(0, 0.6)
		a.grab_held = false
		if _sweep(delta):
			_since_check = 0.0
			p.riding.steer_relative = false
		elif phase_time > 0.0 and _since_check > RIDE_CHECK + 8.0:
			# The beam does not gather here (shadow): ride on, try again later.
			_sweeping = false
			a.beam_held = false
			_since_check = 0.0
			p.riding.steer_relative = false
		return
	p.riding.steer_relative = false
	a.beam_held = false
	var dir := _heading
	# Stuck against something: veer off to one side for a while.
	if c.speed < 1.0:
		_slow += delta
	else:
		_slow = maxf(0.0, _slow - delta)
	if _slow > 2.5 and _detour <= 0.0:
		_detour = 2.5
		_detour_side = -_detour_side
		_slow = 0.0
		stats.detours += 1
		_log("detour (%s)" % ("left" if _detour_side < 0.0 else "right"))
	if _detour > 0.0:
		_detour -= delta
		dir = Basis(Vector3.UP, 1.1 * _detour_side) * dir
	a.view_basis = Basis.looking_at(dir)
	a.move = Vector2(0, 1)
	a.grab_held = false
	if c.speed < 9.0 and int(phase_time * 60.0) % 45 == 0:
		a.press_jump()   # kick: up to a gallop


# --- arena -------------------------------------------------------------------------------

func _on_region(kind: StringName) -> void:
	if is_instance_valid(boss_bot):
		boss_bot.queue_free()
	boss_bot = null
	_sweeping = false
	_since_check = 0.0
	_dismounting = false
	if phase == Phase.DONE:
		return
	_log("region %s" % kind)
	if kind == GameWorld.VALLEY:
		_heading = _player().facing
		_enter(Phase.RIDE if _player().is_riding() else Phase.FIND)
	else:
		_enter(Phase.ARENA)


func _arena() -> void:
	var p := _player()
	if boss_bot != null:
		return
	var kind := game.region_kind
	var a := p.actions
	if p.is_riding() and kind != &"quadratus":
		# Valus and Gaius are fought on foot: off the horse first.
		a.move = Vector2.ZERO
		a.grab_held = true
		if int(phase_time * 60.0) % 20 == 0:
			a.press_interact()
		return
	if p.riding.is_active() and p.riding.phase != PlayerRiding.Phase.RIDING:
		return   # still getting on or off
	a.move = Vector2.ZERO
	a.beam_held = false
	a.grab_held = false
	var e: BossEncounter = game.refs.encounter
	match kind:
		&"valus":
			var b := ValusBot.new()
			b.verbose = verbose
			game.region.add_child(b)
			b.setup(p, game.refs.colossus, e)
			b.finished.connect(_on_boss_finished.bind(kind))
			boss_bot = b
		&"gaius":
			var b := GaiusBot.new()
			b.verbose = verbose
			game.region.add_child(b)
			b.setup(p, game.refs.colossus, e)
			b.finished.connect(_on_boss_finished.bind(kind))
			boss_bot = b
		&"phaedra":
			var b := PhaedraBot.new()
			b.verbose = verbose
			game.region.add_child(b)
			b.setup(p, game.refs.colossus, e)
			b.finished.connect(_on_boss_finished.bind(kind))
			boss_bot = b
		&"quadratus":
			var b := QuadratusBot.new()
			b.verbose = verbose
			b.use_horse = p.is_riding()
			game.region.add_child(b)
			b.setup(p, game.refs.colossus, e, game.refs.horse)
			b.finished.connect(_on_boss_finished.bind(kind))
			boss_bot = b
	_log("fight %s (%s)" % [kind, "riding" if p.is_riding() else "on foot"])


func _on_boss_finished(r: Dictionary, kind: StringName) -> void:
	var entry := {"boss": String(kind), "won": r.get("won", false), "time": r.get("time", 0.0), "why": r.get("why", ""), "resets": r.get("resets", 0)}
	stats.boss_results.append(entry)
	stats.fights[String(kind)] = entry
	_log("fight %s: %s in %.1f s" % [kind, "WIN" if entry.won else "LOSS", entry.time])
	if not entry.won:
		_finish(false, "lost to %s (%s)" % [kind, entry.why])


# --- helpers -----------------------------------------------------------------------------

func _enter(p: Phase) -> void:
	if p != phase:
		_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	_slow = 0.0
	_detour = 0.0


func _finish(won: bool, why: String) -> void:
	if phase == Phase.DONE:
		return
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "game_time": game.state.play_time, "deaths": game.state.deaths}
	_log("FINISHED %s (%s) after %.1f s" % ["WIN" if won else "LOSS", why, time])
	phase = Phase.DONE
	var p := _player()
	if p:
		p.actions.clear()
	finished.emit(result)


func _log(s: String) -> void:
	var line := "[%6.1f] %s" % [time, s]
	events.append(line)
	if verbose:
		print(line)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
