class_name ProcTextures
## Original textures generated in code for Agro and the Wanderer (no image files, nothing
## taken from any game): noise-based albedo and a normal map derived from it, made once
## (fixed seeds, deterministic) and cached. Render only: no gameplay reads them.
##
##   coat     very dark bay hair: fine streaks along the body
##   mane     near-black long strands
##   hoof     dark horn with growth rings
##   leather  saddle leather with wear and a stitched edge
##   blanket  woven saddle blanket (dyed bands)
##   linen    the Wanderer's tunic: a plain weave
##   cloak    darker, felted wool with frayed patches
##   skin     slight variation
##   hair     dark strands

const SIZE := 256

static var _materials := {}


## True where textures are worth making (not in headless tests / benchmarks).
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## The textured material, or ``fallback`` (a plain colour) when textures are off.
static func or_plain(kind: StringName, fallback: Color) -> StandardMaterial3D:
	if enabled():
		return material(kind)
	var m := StandardMaterial3D.new()
	m.albedo_color = fallback
	return m


static func material(kind: StringName) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	# Object-space triplanar: the box / capsule greybox parts need no UVs.
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	match kind:
		&"coat":
			_apply(m, _hair(Color(0.16, 0.1, 0.07), Color(0.07, 0.045, 0.035), 11, 18.0, 0.12), 0.75, Vector3.ONE * 2.2, 0.6)
		&"mane":
			_apply(m, _hair(Color(0.05, 0.04, 0.035), Color(0.015, 0.012, 0.01), 12, 30.0, 0.05), 0.65, Vector3.ONE * 3.0, 0.8)
		&"hoof":
			_apply(m, _rings(Color(0.22, 0.2, 0.17), Color(0.12, 0.11, 0.09), 13), 0.55, Vector3.ONE * 4.0, 0.5)
		&"leather":
			_apply(m, _leather(Color(0.36, 0.2, 0.1), 14), 0.6, Vector3.ONE * 2.0, 0.7)
		&"blanket":
			_apply(m, _woven(Color(0.48, 0.16, 0.12), Color(0.78, 0.66, 0.42), 15, 6), 0.95, Vector3.ONE * 1.5, 0.4)
		&"linen":
			_apply(m, _weave(Color(0.72, 0.68, 0.58), 16), 0.95, Vector3.ONE * 3.0, 0.5)
		&"cloak":
			_apply(m, _felt(Color(0.13, 0.16, 0.17), 17), 1.0, Vector3.ONE * 2.0, 0.6)
		&"skin":
			_apply(m, _noise_tex(Color(0.78, 0.6, 0.47), Color(0.7, 0.52, 0.4), 18, 0.08), 0.7, Vector3.ONE * 4.0, 0.15)
		&"hair":
			_apply(m, _hair(Color(0.18, 0.12, 0.08), Color(0.08, 0.05, 0.035), 19, 26.0, 0.0), 0.7, Vector3.ONE * 4.0, 0.6)
		&"belt":
			_apply(m, _leather(Color(0.24, 0.15, 0.09), 20), 0.6, Vector3.ONE * 3.0, 0.5)
		_:
			m.albedo_color = Color.MAGENTA
	_materials[kind] = m
	return m


static func _apply(m: StandardMaterial3D, img: Image, roughness: float, scale: Vector3, bump: float) -> void:
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(_normal_map(img, bump * 4.0))
	m.roughness = roughness
	# Cloth, hair and skin: no glossy highlight (only leather and horn keep a little).
	m.metallic_specular = 0.5 if roughness < 0.7 else 0.15
	m.uv1_scale = scale


## Normal map from the albedo's brightness (central differences, wrapping at the edges).
static func _normal_map(img: Image, strength: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			lum[y * w + x] = img.get_pixel(x, y).get_luminance()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var dx := lum[y * w + (x + 1) % w] - lum[y * w + (x - 1 + w) % w]
			var dy := lum[((y + 1) % h) * w + x] - lum[((y - 1 + h) % h) * w + x]
			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return out


static func _noise(seed_value: int, freq: float, octaves := 3) -> FastNoiseLite:
	var f := FastNoiseLite.new()
	f.seed = seed_value
	f.frequency = freq
	f.fractal_octaves = octaves
	return f


## Hair: noise stretched along one axis (streaks), plus a soft large-scale shade.
static func _hair(light: Color, dark: Color, seed_value: int, stretch: float, mottling: float) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var fine := _noise(seed_value, 0.02, 2)
	var big := _noise(seed_value + 100, 0.008, 3)
	for y in SIZE:
		for x in SIZE:
			var v := fine.get_noise_2d(x * stretch * 0.1, y * 2.2) * 0.5 + 0.5
			var s := big.get_noise_2d(x, y) * mottling
			img.set_pixel(x, y, dark.lerp(light, clampf(v + s, 0.0, 1.0)))
	return img


static func _rings(light: Color, dark: Color, seed_value: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var n := _noise(seed_value, 0.03, 2)
	for y in SIZE:
		for x in SIZE:
			var ring := 0.5 + 0.5 * sin(y * 0.35 + n.get_noise_2d(x, y) * 3.0)
			img.set_pixel(x, y, dark.lerp(light, ring * 0.7 + 0.15))
	return img


static func _leather(base: Color, seed_value: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var grain := _noise(seed_value, 0.09, 3)
	var wear := _noise(seed_value + 7, 0.012, 2)
	for y in SIZE:
		for x in SIZE:
			var g := grain.get_noise_2d(x, y) * 0.12
			var w := clampf(wear.get_noise_2d(x, y) * 0.8 + 0.1, 0.0, 0.35)
			var c := base.darkened(0.15).lerp(base.lightened(0.25), w) * (1.0 + g)
			# A stitched seam near two edges of every tile.
			if (y == 18 or y == SIZE - 18) and x % 9 < 5:
				c = Color(0.75, 0.68, 0.5)
			img.set_pixel(x, y, c)
	return img


static func _woven(a: Color, b: Color, seed_value: int, bands: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var n := _noise(seed_value, 0.15, 1)
	for y in SIZE:
		for x in SIZE:
			var band := int(floor(float(y) / (SIZE / float(bands)))) % 3
			var base := a if band == 0 else (b if band == 1 else a.darkened(0.4))
			var thread := 0.88 + 0.12 * float((x / 2 + y / 2) % 2)
			img.set_pixel(x, y, base * (thread + n.get_noise_2d(x, y) * 0.06))
	return img


## Plain weave: alternating over / under threads with a little irregularity.
static func _weave(base: Color, seed_value: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var n := _noise(seed_value, 0.05, 2)
	var slub := _noise(seed_value + 3, 0.2, 1)
	for y in SIZE:
		for x in SIZE:
			var cell := ((x / 3) + (y / 3)) % 2
			var t := 0.86 + 0.14 * float(cell) + slub.get_noise_2d(x * 4.0, y) * 0.05
			img.set_pixel(x, y, base * (t + n.get_noise_2d(x, y) * 0.08))
	return img


static func _felt(base: Color, seed_value: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var fibre := _noise(seed_value, 0.25, 2)
	var patch := _noise(seed_value + 11, 0.01, 3)
	for y in SIZE:
		for x in SIZE:
			var f := fibre.get_noise_2d(x, y) * 0.1
			var p := clampf(patch.get_noise_2d(x, y), 0.0, 1.0) * 0.35
			img.set_pixel(x, y, base.lerp(base.lightened(0.35), p) * (1.0 + f))
	return img


static func _noise_tex(a: Color, b: Color, seed_value: int, amount: float) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var n := _noise(seed_value, 0.04, 3)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, a.lerp(b, clampf(0.5 + n.get_noise_2d(x, y) * (0.5 + amount), 0.0, 1.0)))
	return img
