extends SceneTree
## Stable old-layout geometry samples for comparison against the exact base commit.
static func fingerprint(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()
func _initialize() -> void:
	var result := {}
	for layout in [1,2,3,4,5]:
		var samples := []
		for z in range(-2304,1792,64):
			for x in range(-2304,1792,64):
				samples.append(ForbiddenLandsTerrain.surface_height(x+13.375,z+29.625,layout))
		result[str(layout)] = {"surface_samples":samples.size(),"surface_sha256":fingerprint(samples),"road_edges_sha256":fingerprint(ForbiddenLands.road_edges(layout)),"regions_sha256":fingerprint(ForbiddenLands.regions(layout))}
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1: quit(2); return
	var file:=FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("HISTORY_FINGERPRINT_OK")
	quit()
