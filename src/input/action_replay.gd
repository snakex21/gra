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
	r.markers = data.get("markers", [])
	r.checkpoints = data.get("checkpoints", [])
	r.name = "ActionReplay"
	return r


func _ready() -> void:
	# Early, to hand the hook to a new player before it runs its first tick.
	process_physics_priority = -100
	_bind()
	var g := get_parent() as GameWorld
	if mode == Mode.RECORD and g:
		header["world_layout"] = g.layout_version
		checkpoint(g)
		var tap := CheckpointTap.new()
		tap.recorder = self
		tap.game = g
		add_child(tap)
		g.region_loaded.connect(func(kind: StringName) -> void: mark(&"region", String(kind)))
		g.colossus_defeated.connect(func(kind: StringName) -> void: mark(&"defeat", String(kind)))


## Notes ``kind`` (death, hit, fall, region, defeat, report) at this tick. Hits close
## together (a blow and the drowning after it) are one marker.
func mark(kind: StringName, text := "") -> void:
	if mode != Mode.RECORD:
		return
	if kind == &"hit" and not markers.is_empty() and markers[-1][1] == "hit" and tick - int(markers[-1][0]) < 60:
		return
	markers.append([tick, String(kind), text])


func _physics_process(_delta: float) -> void:
	_bind()
	tick += 1


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
	return {"version": VERSION, "header": header, "frames": frames, "ticks": tick, "markers": markers, "checkpoints": checkpoints}

func checkpoint(game: GameWorld) -> void:
	var world := WorldSnapshot.capture(game)
	if not world.is_empty():
		checkpoints.append({"tick": tick, "world": world, "cursor": frames.size(), "segment": _segment})

func resume_checkpoint(saved: Dictionary) -> void:
	tick = int(saved.tick)
	_next = int(saved.cursor)
	_segment = int(saved.segment)
	player = player_source.call() if player_source.is_valid() else player
	_player_id = player.get_instance_id()
	player.action_hook = _on_player_tick
	finished = false

class CheckpointTap extends Node:
	var recorder: ActionReplay
	var game: GameWorld
	func _ready() -> void:
		process_physics_priority = 900
	func _physics_process(_delta: float) -> void:
		if recorder.tick > 0 and recorder.tick % recorder.checkpoint_every == 0:
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
