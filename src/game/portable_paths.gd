class_name PortablePaths
extends RefCounted
## Writable application data always travels with the project / exported executable.
const DATA := "res://data/"

static func resolve(path: String) -> String:
	# Older callers and recordings may still use user://. Never write into the profile.
	var relative := path.trim_prefix("user://") if path.begins_with("user://") else path.trim_prefix(DATA)
	if path.begins_with("user://") or path.begins_with(DATA):
		var root := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
		return root.path_join("data").path_join(relative)
	return path

static func prepare(path: String) -> String:
	var resolved := resolve(path)
	var err := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if err != OK:
		push_error("Nie można zapisać danych w folderze gry: " + resolved.get_base_dir())
		return ""
	return resolved
