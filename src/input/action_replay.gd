class_name ActionReplay
extends Node
## Records or plays back a player's PlayerActions, tick by tick. The simulation is
## deterministic, so the same start and the same actions give the same run: a recorded
## playtest can be replayed exactly (a bug report becomes a reproducible file).
##
## Each physics tick, right before the player reads its actions (after any input source
## or bot wrote them), the recorder stores them; the player in playback gets them put
## back at the same point. Frames are keyed to the player's own tick count (and to which
## player it is, as GameWorld builds a new one per region), so a replay lines up however
## the world around it was started. Only ticks where something changed are stored (plus the
## one-tick presses). The file is binary (exact floats) and compressed:
##   {"version", "header": {...}, "frames": [[[player #, player tick], snapshot, ride], ...]}
## ``header`` is free-form (what is needed to recreate the start: scene, seeds, save).
##
## Markers: while recording, what a viewer wants to find again is noted with its tick:
## the player's deaths, hits taken, hurting falls, regions entered, colossi defeated, bug
## reports (``mark()``). They are saved with the frames: [[tick, kind, text], ...].

enum Mode { RECORD, PLAY }

const VERSION := 1

var mode := Mode.RECORD
var player: PlayerCharacter
## When set, asked every tick for the current player (GameWorld rebuilds the player with
## every region).
var player_source: Callable
var header := {}
var tick := 0
var frames: Array = []
## Optional second actor stream. Absent in historical solo recordings.
var companion_frames: Array = []
var companion_events: Array = []
var companion_regroups: Array = []
var markers: Array = []
var checkpoints: Array = []
## Simulation checkpoints every 10 seconds, captured after the complete physics tick.
var checkpoint_every := 600
## Playback: the recording ran out.
var finished := false

var _last: Array = []
var _next := 0
var _player_id := 0
var _segment := -1
var _companion_last: Array = []
var _companion_next := 0
var _companion_id := 0
var _companion_segment := -1
var _event_next := 0
var _regroup_next := 0
var _companion_last_mode := "off"
var _join_actor: PlayerCharacter
var _join_actor_tick := 0
var _join_tick := -1


static func recorder(p: PlayerCharacter, p_header := {}) -> ActionReplay:
	var r := ActionReplay.new()
	r.mode = Mode.RECORD
	r.player = p
	r.header = p_header
	r.name = "ActionReplay"
	return r


static func player_for(p: PlayerCharacter, data: Dictionary) -> ActionReplay:
	var r := ActionReplay.new()
	r.mode = Mode.PLAY
	r.player = p
	r.header = data.get("header", {})
	r.frames = data.get("frames", [])
	r.companion_frames = data.get("companion_frames", [])
	r.companion_events = data.get("companion_events", [])
	r.companion_regroups = data.get("companion_regroups", [])
	r.markers = data.get("markers", [])
	r.checkpoints = data.get("checkpoints", [])
	r.name = "ActionReplay"
	return r


func _ready() -> void:
	# Early, to hand the hook to a new player before it runs its first tick.
	process_physics_priority = -100
	var g := get_parent() as GameWorld
	if g and mode == Mode.PLAY:
		g.replay_driven = true
		g.cancel_companion_decision()
		g._sync_companion()
	_bind()
	_bind_companion()
	if g:
		var first_tick := CompanionFirstTick.new()
		first_tick.recorder = self
		add_child(first_tick)
		var tap := CheckpointTap.new()
		tap.recorder = self
		tap.game = g
		add_child(tap)
	if mode == Mode.RECORD and g:
		header["world_layout"] = g.layout_version
		header["companion_mode"] = String(g.companion_mode)
		_companion_last_mode = String(g.companion_mode)
		checkpoint(g)
		g.region_loaded.connect(func(kind: StringName) -> void: mark(&"region", String(kind)))
		g.colossus_defeated.connect(func(kind: StringName) -> void: mark(&"defeat", String(kind)))
		g.companion_regrouped.connect(func(position: Vector3) -> void: companion_regroups.append([tick, position]))


## Notes ``kind`` (death, hit, fall, region, defeat, report) at this tick. Hits close
## together (a blow and the drowning after it) are one marker.
func mark(kind: StringName, text := "") -> void:
	if mode != Mode.RECORD:
		return
	if kind == &"hit" and not markers.is_empty() and markers[-1][1] == "hit" and tick - int(markers[-1][0]) < 60:
		return
	markers.append([tick, String(kind), text])


func _physics_process(_delta: float) -> void:
	tick += 1
	var game := get_parent() as GameWorld
	if game:
		if mode == Mode.RECORD:
			if String(game.companion_mode) != _companion_last_mode:
				_companion_last_mode = String(game.companion_mode)
				companion_events.append([tick, _companion_last_mode])
		else:
			while _event_next < companion_events.size() and int(companion_events[_event_next][0]) <= tick:
				game.set_companion_mode(companion_events[_event_next][1])
				_event_next += 1
	_bind()
	_bind_companion()


func _bind_companion() -> void:
	var game := get_parent() as GameWorld
	if not game:
		return
	var actor := game.companion()
	if not is_instance_valid(actor):
		_companion_id = 0
		return
	if actor.get_instance_id() == _companion_id:
		return
	_companion_id = actor.get_instance_id()
	_companion_segment += 1
	_companion_last = []
	actor.action_hook = _on_companion_tick
	if mode == Mode.PLAY:
		# SceneTree may defer newly inserted physics nodes to the following tick.
		# A recording joined between ticks, so replay owes this actor its first frame.
		_join_actor = actor
		_join_actor_tick = actor.ticks
		_join_tick = tick


func _on_companion_tick(actor: PlayerCharacter) -> void:
	var key := [_companion_segment, actor.ticks]
	if mode == Mode.RECORD:
		var snapshot := actor.actions.snapshot()
		var state := [snapshot, actor.riding.steer_relative]
		if state != _companion_last or snapshot[7] or snapshot[8] or snapshot[9] or snapshot[10]:
			companion_frames.append([key, snapshot, actor.riding.steer_relative, tick])
			_companion_last = state
		return
	var applied := false
	while _companion_next < companion_frames.size() and _before_or_at(companion_frames[_companion_next][0], key):
		var frame: Array = companion_frames[_companion_next]
		actor.actions.restore(frame[1])
		actor.riding.steer_relative = frame[2]
		_companion_next += 1
		applied = true
	if not applied:
		actor.actions.restore(_without_presses(actor.actions.snapshot()))


## The hook goes onto the current player (a new one per region in GameWorld).
func _bind() -> void:
	if player_source.is_valid():
		player = player_source.call()
	if not is_instance_valid(player) or player.get_instance_id() == _player_id:
		return
	_player_id = player.get_instance_id()
	_segment += 1
	_last = []
	player.action_hook = _on_player_tick
	if mode == Mode.RECORD:
		player.died.connect(func() -> void: mark(&"death"))
		player.hit_taken.connect(func(dmg: float, source: StringName) -> void: mark(&"hit", "%s %.0f" % [source, dmg]))
		player.landed.connect(func(speed: float, _tier: int, dmg: float) -> void:
			if dmg > 0.0:
				mark(&"fall", "%.0f m/s, -%.0f" % [speed, dmg]))


## Called by the player at the start of its tick, before it reads its actions.
func _on_player_tick(p: PlayerCharacter) -> void:
	var key := [_segment, p.ticks]
	if mode == Mode.RECORD:
		var s := p.actions.snapshot()
		var ride := p.riding.steer_relative
		var state := [s, ride]
		# One-tick presses always count as a change.
		if state != _last or s[7] or s[8] or s[9] or s[10]:
			frames.append([key, s, ride, tick])
			_last = state
		return
	var applied := false
	while _next < frames.size() and _before_or_at(frames[_next][0], key):
		var f: Array = frames[_next]
		p.actions.restore(f[1])
		p.riding.steer_relative = f[2]
		_next += 1
		applied = true
	if not applied:
		# Between recorded changes: held values stay, a one-tick press never repeats.
		p.actions.restore(_without_presses(p.actions.snapshot()))
	finished = _next >= frames.size()


static func _before_or_at(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] <= b[1])


static func _without_presses(s: Array) -> Array:
	var c := s.duplicate()
	for i in range(7, 11):
		c[i] = false
	return c


func to_dict() -> Dictionary:
	return {"version": VERSION, "header": header, "frames": frames, "companion_frames": companion_frames,
		"companion_events": companion_events, "companion_regroups": companion_regroups,
		"ticks": tick, "markers": markers, "checkpoints": checkpoints}

func checkpoint(game: GameWorld) -> void:
	var world := WorldSnapshot.capture(game)
	if not world.is_empty():
		checkpoints.append({"tick": tick, "world": world, "cursor": frames.size(), "segment": _segment,
			"companion_cursor": companion_frames.size(), "companion_segment": _companion_segment,
			"companion_event_cursor": companion_events.size(), "companion_regroup_cursor": companion_regroups.size()})

func resume_checkpoint(saved: Dictionary) -> void:
	tick = int(saved.tick)
	_next = int(saved.cursor)
	_segment = int(saved.segment)
	player = player_source.call() if player_source.is_valid() else player
	_player_id = player.get_instance_id()
	player.action_hook = _on_player_tick
	finished = false
	_join_actor = null
	_join_tick = -1
	_companion_next = int(saved.get("companion_cursor", 0))
	_companion_segment = int(saved.get("companion_segment", -1))
	_event_next = int(saved.get("companion_event_cursor", 0))
	_regroup_next = int(saved.get("companion_regroup_cursor", 0))
	var game := get_parent() as GameWorld
	if game and is_instance_valid(game.companion()):
		_companion_id = game.companion().get_instance_id()
		game.companion().action_hook = _on_companion_tick
	else:
		_companion_id = 0

class CompanionFirstTick extends Node:
	var recorder: ActionReplay
	func _ready() -> void:
		# After ordinary PlayerCharacter(0), before projectiles(20) and encounter(50).
		process_physics_priority = 1
	func _physics_process(delta: float) -> void:
		if recorder.mode != Mode.PLAY or recorder._join_tick != recorder.tick:
			return
		var actor := recorder._join_actor
		if is_instance_valid(actor) and actor.is_physics_processing() and actor.ticks == recorder._join_actor_tick:
			actor._physics_process(delta)
		recorder._join_actor = null
		recorder._join_tick = -1

class CheckpointTap extends Node:
	var recorder: ActionReplay
	var game: GameWorld
	func _ready() -> void:
		process_physics_priority = 900
	func _physics_process(_delta: float) -> void:
		if recorder.mode == Mode.PLAY:
			while recorder._regroup_next < recorder.companion_regroups.size() and int(recorder.companion_regroups[recorder._regroup_next][0]) <= recorder.tick:
				game.regroup_companion(recorder.companion_regroups[recorder._regroup_next][1])
				recorder._regroup_next += 1
		elif recorder.tick > 0 and recorder.tick % recorder.checkpoint_every == 0:
			recorder.checkpoint(game)


func save(path: String) -> bool:
	path = PortablePaths.prepare(path)
	if path == "":
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(to_dict())
	f.close()
	return true


static func load_file(path: String) -> Dictionary:
	path = PortablePaths.resolve(path)
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	f.close()
	if not (data is Dictionary) or int((data as Dictionary).get("version", -1)) != VERSION:
		return {}
	return data
