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
## Master volume 0..1.
var volume := 0.8
## The player's own keys: {action: [{"key": code} | {"mouse": button}, ...]} (InputSetup).
var bindings := {}
## The save slot last played (1..GameState.SLOTS).
var slot := 1


func to_dict() -> Dictionary:
	return {"version": VERSION, "mouse_sensitivity": mouse_sensitivity, "invert_y": invert_y,
		"ride_relative": ride_relative, "show_help": show_help, "show_debug": show_debug,
		"volume": volume, "bindings": bindings, "slot": slot}


## Fills from a saved dictionary; unknown or broken values keep their defaults.
func from_dict(d: Dictionary) -> void:
	if int(d.get("version", -1)) != VERSION:
		return
	mouse_sensitivity = clampf(float(d.get("mouse_sensitivity", mouse_sensitivity)), 0.0005, 0.01)
	invert_y = bool(d.get("invert_y", invert_y))
	ride_relative = bool(d.get("ride_relative", ride_relative))
	show_help = bool(d.get("show_help", show_help))
	show_debug = bool(d.get("show_debug", show_debug))
	volume = clampf(float(d.get("volume", volume)), 0.0, 1.0)
	# Keys as whole numbers again (JSON reads every number as a float).
	bindings = {}
	var b: Variant = d.get("bindings", {})
	if b is Dictionary:
		for action in b:
			var events := []
			for e in (b[action] if b[action] is Array else []):
				if e is Dictionary:
					var clean := {}
					for k in e:
						clean[String(k)] = int(e[k])
					events.append(clean)
			bindings[String(action)] = events
	slot = clampi(int(d.get("slot", slot)), 1, GameState.SLOTS)


## Volume and keys onto the engine (the rest goes to the input source, rider and HUD).
func apply_engine() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	InputSetup.apply_bindings(bindings)


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
