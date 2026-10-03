extends RefCounted
## Portable safe checkpoints reuse the replay codec. Campaign victories are authoritative.
const VERSION := 1
const INTERVAL := 60.0

static func world_path(slot_path: String) -> String:
	return PortablePaths.resolve(slot_path) + ".world"

static func safe_to_checkpoint(game: GameWorld) -> bool:
	if game.phase != GameWorld.Phase.PLAYING or not is_instance_valid(game.region):
		return false
	var p := game.player()
	if p == null or p.dead or p.balance.state == Balance.State.FALLEN or p.sword.is_busy():
		return false
	if p.is_riding():
		return p.riding.phase == PlayerRiding.Phase.RIDING
	if p.state != PlayerCharacter.State.GROUND:
		return false
	var body := p.get_support_body()
	return body != null and not (game.colossus() and game.colossus().owns_body(body))

static func save(game: GameWorld, slot_path: String) -> bool:
	if slot_path == "" or not is_instance_valid(game.region):
		return false
	# Keep an earlier safe checkpoint while climbing, falling or fighting on a body.
	if not safe_to_checkpoint(game):
		return game.state.save(slot_path)
	var data := WorldSnapshot.capture(game)
	if data.is_empty():
		return false
	var path := PortablePaths.prepare(world_path(slot_path))
	if path == "":
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var({"version": VERSION, "world": data}, false)
	file.flush()
	var write_ok := file.get_error() == OK
	file.close()
	if not write_ok or DirAccess.rename_absolute(temporary, path) != OK:
		return false
	return game.state.save(slot_path)

static func restore(game: GameWorld, slot_path: String) -> bool:
	var path := world_path(slot_path)
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var payload: Variant = file.get_var(false)
	file.close()
	if not payload is Dictionary or int(payload.get("version", -1)) != VERSION or not payload.get("world") is Dictionary:
		return false
	var data: Dictionary = payload.world
	var current := GameState.new()
	if not current.load_from(slot_path):
		return false
	var saved := GameState.new()
	if not saved.from_dict(data.get("progress", {})) or saved.defeated != current.defeated:
		# A victory saved after this checkpoint must never be undone.
		return false
	if not WorldSnapshot.restore(game, data):
		game.start_from(current.to_dict())
		return false
	game.state.play_time = maxf(game.state.play_time, current.play_time)
	game.state.deaths = maxi(game.state.deaths, current.deaths)
	game.apply_settings(game.settings, false)
	return true

static func clear(slot_path: String) -> void:
	DirAccess.remove_absolute(world_path(slot_path))
