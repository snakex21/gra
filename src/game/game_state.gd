class_name GameState
extends RefCounted
## Progress through the game: which colossi are defeated, in a fixed order, and the save
## file (JSON, offline, in user://). Nothing else is saved: a loaded game always starts
## at the temple, like after every won fight.

const VERSION := 1
const ORDER: Array[StringName] = [&"valus", &"quadratus", &"gaius", &"phaedra", &"hydrus"]
const DEFAULT_PATH := "user://save.json"

var defeated: Array[StringName] = []
## Simulation seconds played (fights and travel).
var play_time := 0.0
## Number of deaths (encounter resets) over the whole game.
var deaths := 0


## The colossus the beam leads to, or &"" when all are defeated.
func next_colossus() -> StringName:
	for c in ORDER:
		if not defeated.has(c):
			return c
	return &""


func is_complete() -> bool:
	return next_colossus() == &""


func mark_defeated(c: StringName) -> void:
	if ORDER.has(c) and not defeated.has(c):
		defeated.append(c)


func to_dict() -> Dictionary:
	var names: Array[String] = []
	for c in defeated:
		names.append(String(c))
	return {"version": VERSION, "defeated": names, "play_time": play_time, "deaths": deaths}


## Fills this state from a saved dictionary. Unknown names and broken values are ignored;
## returns false (and leaves a new game) when the data is not a save of this game.
func from_dict(d: Dictionary) -> bool:
	defeated.clear()
	play_time = 0.0
	deaths = 0
	if int(d.get("version", -1)) != VERSION or not (d.get("defeated") is Array):
		return false
	# Kept in story order whatever the file says (and no gaps: the order is fixed).
	var listed: Array = d.defeated
	for c in ORDER:
		if listed.has(String(c)):
			defeated.append(c)
		else:
			break
	play_time = maxf(0.0, float(d.get("play_time", 0.0)))
	deaths = maxi(0, int(d.get("deaths", 0)))
	return true


func save(path := DEFAULT_PATH) -> bool:
	# Write to a temporary file first so a crash never leaves half a save.
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## Loads ``path``; a missing or unreadable file gives a new game (and false).
func load_from(path := DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		from_dict({})
		return false
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		from_dict({})
		return false
	return from_dict(data)
