class_name Settings
extends RefCounted
## Player settings (offline JSON in user://, separate from the save game). Applied by the
## game to its input source, rider and HUD; gameplay itself never reads them.

const VERSION := 1
const DEFAULT_PATH := "user://settings.json"

var mouse_sensitivity := 0.0025
var invert_y := false
## Steer Agro relative to the horse instead of the camera.
var ride_relative := false
var show_help := true
var show_debug := false


func to_dict() -> Dictionary:
	return {"version": VERSION, "mouse_sensitivity": mouse_sensitivity, "invert_y": invert_y,
		"ride_relative": ride_relative, "show_help": show_help, "show_debug": show_debug}


## Fills from a saved dictionary; unknown or broken values keep their defaults.
func from_dict(d: Dictionary) -> void:
	if int(d.get("version", -1)) != VERSION:
		return
	mouse_sensitivity = clampf(float(d.get("mouse_sensitivity", mouse_sensitivity)), 0.0005, 0.01)
	invert_y = bool(d.get("invert_y", invert_y))
	ride_relative = bool(d.get("ride_relative", ride_relative))
	show_help = bool(d.get("show_help", show_help))
	show_debug = bool(d.get("show_debug", show_debug))


func save(path := DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


func load_from(path := DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return false
	from_dict(data)
	return true
