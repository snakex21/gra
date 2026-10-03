class_name GameState
extends RefCounted
## Progress through the game: which colossi are defeated, in a fixed order, and the save
## file (offline JSON beside the game). A loaded campaign always starts
## at the temple, like after every won fight.

const VERSION := 2
const ORDER: Array[StringName] = BossRoster.PLAYABLE
const DEFAULT_PATH := "res://data/save.json"
## Save slots (slot 1 is the save file of the earlier versions).
const SLOTS := 3

var defeated: Array[StringName] = []
## Old recordings retain their six-boss sequence and geography.
var legacy_replay := false
## Simulation seconds played (fights and travel).
var play_time := 0.0
## Number of deaths (encounter resets) over the whole game.
var deaths := 0


static func slot_path(slot: int) -> String:
	return DEFAULT_PATH if slot <= 1 else "res://data/save_%d.json" % slot


## A slot as the menu shows it: "3/5 kolosów, 42 min" ("" when empty).
static func describe(path: String) -> String:
	path = PortablePaths.resolve(path)
	if not FileAccess.file_exists(path):
		return ""
	var s := GameState.new()
	if not s.load_from(path):
		return ""
	if s.is_complete():
		return "ukończona, %d min" % int(s.play_time / 60.0)
	return "%d/%d kolosów, %d min" % [s.defeated.size(), ORDER.size(), int(s.play_time / 60.0)]


## The colossus the beam leads to, or &"" when all are defeated.
func next_colossus() -> StringName:
	for c in BossRoster.LEGACY if legacy_replay else ORDER:
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
	var version := int(d.get("version", -1))
	if version not in [1, VERSION] or not (d.get("defeated") is Array):
		return false
	# Inserting a boss must preserve earlier victories by name. Legacy saves validate
	# their original prefix, then map those wins into the expanded campaign.
	var listed: Array = d.defeated
	if version == 1:
		var prefix := []
		for c in BossRoster.LEGACY:
			if not listed.has(String(c)):
				break
			prefix.append(String(c))
		listed = prefix
	for c in ORDER:
		if listed.has(String(c)):
			defeated.append(c)
	play_time = maxf(0.0, float(d.get("play_time", 0.0)))
	deaths = maxi(0, int(d.get("deaths", 0)))
	return true


func save(path := DEFAULT_PATH) -> bool:
	path = PortablePaths.prepare(path)
	if path == "":
		return false
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
	path = PortablePaths.resolve(path)
	if not FileAccess.file_exists(path):
		from_dict({})
		return false
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		from_dict({})
		return false
	return from_dict(json.data)
