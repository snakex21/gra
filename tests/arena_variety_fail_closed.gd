extends SceneTree
## Isolated in-memory path substitution; production data is never changed.
## Expected warnings/errors identify deliberately missing or malformed inputs.
## Run: godot --headless --path . --script tests/arena_variety_fail_closed.gd

func bytes_sha256(data:PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original:=FileAccess.get_file_as_string("res://src/world/arena_variety_dressing.gd")
	var reference:Dictionary=ArenaVarietyDressing.sample("quadratus")[0]
	var bounds:AABB=reference.transform*ArenaVarietyDressing.bounds_for(reference.kind)
	var rows:={}
	var failed:=false
	var cases:={
		"missing_file":null,
		"malformed_json":"{",
		"missing_arenas":"{\"schema_version\":1}",
		"missing_arena":"{\"schema_version\":1,\"arenas\":{\"phaedra\":[]}}",
		"empty_obstacles":"{\"schema_version\":1,\"arenas\":{\"quadratus\":[],\"phaedra\":[],\"avion\":[]}}",
		"wrong_arenas_type":"{\"schema_version\":1,\"arenas\":[]}",
		"missing_entry_fields":"{\"schema_version\":1,\"arenas\":{\"quadratus\":[{}],\"phaedra\":[{}],\"avion\":[{}]}}",
		"bad_entry_vector":"{\"schema_version\":1,\"arenas\":{\"quadratus\":[{\"position\":[0,0],\"size\":[2,2,2]}],\"phaedra\":[],\"avion\":[]}}",
		"bad_entry_numbers":"{\"schema_version\":1,\"arenas\":{\"quadratus\":[{\"position\":[\"invalid\",0,0],\"size\":[2,2,2]}],\"phaedra\":[],\"avion\":[]}}",
		"negative_size":"{\"schema_version\":1,\"arenas\":{\"quadratus\":[{\"position\":[0,0,0],\"size\":[-2,2,2]}],\"phaedra\":[],\"avion\":[]}}"
	}
	var late:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ArenaVarietyDressing.CLEARANCE_PATH))
	late.arenas.phaedra=[{}]
	cases["late_invalid_arena"]=JSON.stringify(late)
	for kind:String in cases:
		var path:="res://tests/output/clearance_fault_"+kind+".json"
		if cases[kind]!=null:
			var fixture_file:=FileAccess.open(path,FileAccess.WRITE)
			fixture_file.store_string(cases[kind]);fixture_file.close()
		var source:=original.replace("class_name ArenaVarietyDressing\n","").replace(ArenaVarietyDressing.CLEARANCE_PATH,path)
		var script:=GDScript.new();script.source_code=source
		if script.reload()!=OK: failed=true;continue
		var actual:bool=script.allowed("quadratus",bounds)
		var again:bool=script.allowed("quadratus",bounds)
		var fixture:=Node3D.new();root.add_child(fixture)
		script.append(fixture,"quadratus")
		var sampled:Array=script.sample("quadratus")
		rows[kind]={"placement_rejected":not actual,"repeated_call_rejected":not again,"no_partial_cache":script._obstacles.is_empty(),"append_is_noop":fixture.get_child_count()==0,"sample_is_empty":sampled.is_empty()}
		for passed:bool in rows[kind].values():
			if not passed:failed=true
		fixture.free()
	var old_validation:="""static func _clearance_ready() -> bool:
 if not _obstacles.is_empty(): return true
 var parsed = JSON.parse_string(FileAccess.get_file_as_string(CLEARANCE_PATH))
 if not parsed is Dictionary or not parsed.has("arenas"): return false
 for arena: String in parsed.arenas:
  var footprints := []
  for entry: Dictionary in parsed.arenas[arena]:
   var p: Array = entry.position
   var size: Array = entry.size
   footprints.append(Rect2(Vector2(p[0],p[2]),Vector2(size[0],size[2])).grow(.25))
  _obstacles[arena] = footprints
 return true

"""
	var first:=original.find("static func _clearance_ready()")
	var last:=original.find("static func mesh_for(",first)
	var earlier:=GDScript.new()
	earlier.source_code=(original.substr(0,first)+old_validation+original.substr(last)).replace("class_name ArenaVarietyDressing\n","")
	if earlier.reload()!=OK:failed=true
	var output_unchanged:={}
	for arena:String in ArenaVarietyDressing.CONFIG:
		var current:=var_to_bytes(ArenaVarietyDressing.sample(arena))
		var previous:=var_to_bytes(earlier.sample(arena))
		output_unchanged[arena]={"exact_placement_bytes_unchanged":current==previous,"sha256":bytes_sha256(current)}
		if current!=previous:failed=true
	var result:={"cases":rows,"validation_only_change":output_unchanged,"failed":failed}
	var file:=FileAccess.open("res://tests/output/variety_fail_closed.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("VARIETY_FAIL_CLOSED_EXPECTED_ERRORS: ",JSON.stringify(rows))
	quit(1 if failed else 0)
