class_name BiomeGroundcover
extends RefCounted
## Layout-five cosmetic ecology. Bounded, spatially clustered, independently seeded.
## Existing roads, terrain, authored landmarks and all simulation state are untouched.
const KINDS := ["biome_seedgrass", "biome_rush", "biome_fern", "biome_wildflowers", "biome_heather", "biome_dry_scrub", "biome_gravel"]
const ROWS := 24
const SPACING := 256.0 / ROWS
const FOCUS_ROWS := 64
# Authored ecology anchors on existing land, not new geometry or gameplay nodes.
# Four separated pockets per broad region leave the routes and long views open.
const FOCAL_PATCHES := [
	Vector4(-505,-480,92,80), Vector4(-830,-556,88,76), Vector4(-1018,-502,90,82), Vector4(-582,-840,84,76),
	Vector4(-1060,600,90,78), Vector4(-832,142,80,72), Vector4(-1300,0,90,82), Vector4(214,1130,92,80),
	Vector4(-270,-1440,88,76), Vector4(-750,-1290,84,74), Vector4(-1074,-1134,90,80), Vector4(250,-1700,78,70),
	Vector4(940,-400,92,82), Vector4(1120,-750,88,76), Vector4(980,640,90,78), Vector4(1380,586,82,72),
	Vector4(1480,550,82,74), Vector4(738,1378,80,70), Vector4(-1906,-916,84,76), Vector4(-1468,1146,80,70),
	Vector4(-42,-806,90,78), Vector4(-250,-650,82,72), Vector4(236,604,86,74), Vector4(-304,-204,84,76)
]

static func patches_in_chunk(origin: Vector2i) -> Array:
	var result := []
	var bounds := Rect2(Vector2(origin), Vector2(256,256))
	for patch: Vector4 in FOCAL_PATCHES:
		var extent := Vector2(patch.z,patch.w) * 1.23
		if bounds.intersects(Rect2(Vector2(patch.x,patch.y)-extent,extent*2)):
			result.append(patch)
	return result

static func focus_at(p: Vector2, patches: Array) -> float:
	var focus := 0.0
	for patch: Vector4 in patches:
		var offset := p - Vector2(patch.x,patch.y)
		var ripple := .10 * sin(p.x*.047 + p.y*.026) + .07 * cos(p.y*.059-p.x*.017)
		var distance := Vector2(offset.x/patch.z,offset.y/patch.w).length() + ripple
		focus = maxf(focus,1.0-smoothstep(.48,1.05,distance))
	return focus

static func state_for(origin: Vector2i, layout: int) -> Dictionary:
	var state := EnvironmentGroundcover._route_state(origin, layout)
	state.rng.seed = 194731 + origin.x * 191 + origin.y * 337
	state.focus_patches = patches_in_chunk(origin)
	state.total_rows = ROWS if state.focus_patches.is_empty() else FOCUS_ROWS
	state.biome_pockets = true
	state.palettes = {}
	return state

static func palette(p: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var w := ForbiddenLandsTerrain.biome_weights(p.x, p.y)
	var h := ForbiddenLandsTerrain.surface_height(p.x, p.y, 5)
	var coastal := Vector2((p.x + 220) / 1950, (p.y + 150) / 2000).length()
	var kinds := ["biome_seedgrass", "biome_wildflowers"]
	var density := .86
	var region := "meadow"
	# Weighted selection feathers ecotones rather than introducing hard bands.
	if rng.randf() < w.volcanic:
		kinds = ["biome_gravel", "biome_dry_scrub"]
		density = .26
		region = "volcanic"
	elif coastal > .89 and h < 8 and rng.randf() < .85:
		kinds = ["biome_rush", "biome_heather"] if h < 1 else ["biome_heather", "biome_gravel"]
		density = .64
		region = "shore"
	elif rng.randf() < w.desert:
		kinds = ["biome_dry_scrub", "biome_gravel"]
		density = .40
		region = "desert"
	elif rng.randf() < w.forest:
		kinds = ["biome_fern", "biome_heather"]
		density = .93
		region = "forest"
	elif rng.randf() < w.highland:
		kinds = ["biome_heather", "biome_seedgrass"] if rng.randf() < .7 else ["biome_dry_scrub", "biome_gravel"]
		density = .66
		region = "highland"
	elif rng.randf() < w.eastern:
		kinds = ["biome_rush", "biome_seedgrass"] if h < 9 else ["biome_heather", "biome_wildflowers"]
		density = .79
		region = "eastern"
	elif rng.randf() < .20:
		kinds = ["biome_seedgrass", "biome_heather"]
	return {"kinds": kinds, "density": density, "region": region,
		"a": Vector2(rng.randf_range(12, 28), rng.randf_range(12, 28)),
		"b": Vector2(rng.randf_range(36, 54), rng.randf_range(32, 54)),
		"angle": rng.randf_range(-PI, PI)}

static func sample_rows(state: Dictionary, candidate_limit: int) -> bool:
	var origin: Vector2i = state.origin
	var rng: RandomNumberGenerator = state.rng
	var rows: int = state.total_rows
	var spacing := 256.0 / rows
	var start := int(state.row) * rows + int(state.get("column", 0))
	var end := mini(rows * rows, start + candidate_limit)
	for candidate in range(start, end):
		var ix := candidate % rows
		var iz := floori(float(candidate) / rows)
		var p := Vector2(origin) + Vector2((ix + .5) * spacing, (iz + .5) * spacing) + Vector2(rng.randf_range(-spacing*.28, spacing*.28), rng.randf_range(-spacing*.28, spacing*.28))
		var cell := Vector2i(floori(p.x / 64), floori(p.y / 64))
		if not state.palettes.has(cell):
			state.palettes[cell] = palette(Vector2(cell) * 64 + Vector2(32,32), rng)
		var eco: Dictionary = state.palettes[cell]
		var local := p - Vector2(cell) * 64
		var da: Vector2 = (local - eco.a).rotated(eco.angle)
		var db: Vector2 = (local - eco.b).rotated(eco.angle)
		var pocket := maxf(exp(-Vector2(da.x / 26, da.y / 17).length_squared()), exp(-Vector2(db.x / 22, db.y / 25).length_squared()))
		var focus := focus_at(p, state.focus_patches)
		# Compensate the finer grid outside focal pockets; extra candidates do
		# not silently multiply the ordinary world background population.
		var background_density: float = eco.density * (.10 + .90 * pocket) * pow(float(ROWS)/rows,2)
		var density := lerpf(background_density,.94,focus)
		if rng.randf() > density:
			continue
		var kind: String = eco.kinds[0] if rng.randf() < .70 else eco.kinds[1]
		if not EnvironmentGroundcover.allowed(p, false, state.layout, 210, 12.0):
			continue
		var height := ForbiddenLandsTerrain.surface_height(p.x, p.y, state.layout)
		var dx := (ForbiddenLandsTerrain.surface_height(p.x + 2, p.y, state.layout) - height) / 2
		var dz := (ForbiddenLandsTerrain.surface_height(p.x, p.y + 2, state.layout) - height) / 2
		var normal := Vector3(-dx, 1, -dz).normalized()
		var size := rng.randf_range(1.45, 2.25)
		var vertical := rng.randf_range(.78, 1.40)
		if kind == "biome_gravel":
			size = rng.randf_range(1.0, 1.65)
			vertical = rng.randf_range(.7, 1.2)
		var basis := (Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rng.randf_range(-PI, PI))).scaled_local(Vector3(size, vertical, size))
		var batch_cell := Vector2i(floori(p.x / 128) * 2, floori(p.y / 128) * 2)
		if not state.cells.has(batch_cell): state.cells[batch_cell] = {}
		if not state.cells[batch_cell].has(kind): state.cells[batch_cell][kind] = []
		state.cells[batch_cell][kind].append(Transform3D(basis, Vector3(p.x, height - .035, p.y)))
	state.row = floori(float(end) / rows)
	state.column = end % rows
	return end == rows * rows

static func sample_chunk(origin: Vector2i, layout: int) -> Dictionary:
	var state := state_for(origin, layout)
	sample_rows(state, state.total_rows * state.total_rows)
	EnvironmentGroundcover._shuffle_route_cells(state.cells, state.rng)
	return state.cells

static func route_kind(kind: String, p: Vector2) -> String:
	# Cosmetic type only: preserve every approved placement, size and RNG call.
	# Each route batch gains one seedgrass accent; the approved shrub mass stays.
	var roll := fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)
	if kind == "grass_meadow_soft" and roll < .18:
		return "biome_seedgrass"
	return kind
