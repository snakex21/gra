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
	r.name = "ActionReplay"
	return r


func _ready() -> void:
	# Early, to hand the hook to a new player before it runs its first tick.
	process_physics_priority = -100
	_bind()


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


## Called by the player at the start of its tick, before it reads its actions.
func _on_player_tick(p: PlayerCharacter) -> void:
	var key := [_segment, p.ticks]
	if mode == Mode.RECORD:
		var s := p.actions.snapshot()
		var ride := p.riding.steer_relative
		var state := [s, ride]
		# One-tick presses always count as a change.
		if state != _last or s[7] or s[8] or s[9] or s[10]:
			frames.append([key, s, ride])
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
	return {"version": VERSION, "header": header, "frames": frames, "ticks": tick}


func save(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(to_dict())
	f.close()
	return true


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	f.close()
	if not (data is Dictionary) or int((data as Dictionary).get("version", -1)) != VERSION:
		return {}
	return data
