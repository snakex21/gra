@tool
extends Node3D
## Self-contained desert art study. No actors, controllers, navigation or gameplay.
const SaltAsset = preload("res://art/scripts/saltwind_asset.gd")
const TerrainMaterial = preload("res://materials/saltwind/terrain.tres")
@export var include_collision := true
@export var include_catalogue := false
var landscape: Node3D
var catalogue: Node3D
var asset_count := 0
var catalogue_count := 0
var vegetation_instances := 0
var terrain_triangles := 0
var distant_triangles := 0
var scatter_signature := ""

static func height_at(x: float, z: float) -> float:
	var sides := smoothstep(42.0, 170.0, absf(x))
	var h := sides * (5.0 + 4.0 * sin(x * .025 + z * .014) * sin(z * .02))
	h += smoothstep(125.0, 220.0, -z) * (3.0 + 2.0 * cos(x * .022))
	return h

func _ready() -> void:
	if get_child_count() == 0:
		build()

func build() -> void:
	if get_child_count() > 0:
		return
	landscape = Node3D.new()
	landscape.name = "Landscape"
	add_child(landscape)
	_terrain()
	_landmarks()
	_details()
	if include_catalogue:
		_build_catalogue()

func place(id: String, p: Vector3, yaw := 0.0, size := Vector3.ONE, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.set_script(SaltAsset)
	n.model_id = id
	n.collidable = include_collision if parent == null else false
	n.lod_distances = Vector3(55, 145, 800) if parent == null else Vector3(900, 1100, 1500)
	n.name = "%s_%03d" % [id, asset_count + catalogue_count]
	n.position = p
	n.rotation.y = yaw
	n.scale = size
	n.cast_shadows = not id in ["tiered_escarpment", "tabletop_mesa", "dry_fan_grass", "saltbrush_cushion", "dry_seed_reeds", "tumble_cage"]
	if parent == null:
		landscape.add_child(n)
		asset_count += 1
	else:
		parent.add_child(n)
		catalogue_count += 1
	return n

func grounded(id: String, x: float, z: float, yaw := 0.0, scale_value := 1.0, bury := .12) -> Node3D:
	var base_height := height_at(x,z)
	var record: Dictionary = SaltAsset.records()[id]
	if record.category == "geology":
		# Sink large formations to the lowest footprint sample on uneven dunes.
		# Centre-only placement can leave an eroded bank visibly hovering.
		for dx in [-.5,0.0,.5]:
			for dz in [-.5,0.0,.5]:
				var offset := Vector3(dx*float(record.nominal_size[0]),0,dz*float(record.nominal_size[2])).rotated(Vector3.UP,yaw)*scale_value
				base_height = minf(base_height,height_at(x+offset.x,z+offset.z))
	return place(id, Vector3(x,base_height-bury,z),yaw,Vector3.ONE*scale_value)

func _landmarks() -> void:
	# A quiet salt basin opens onto a deliberately asymmetric gate and wind tower.
	place("wind_gate_13m",Vector3(0,0,-60))
	place("wind_sieve_tower",Vector3(21,0,-76),-.09,Vector3(1.2,1.5,1.2))
	place("ribbed_salt_pillar",Vector3(-13,0,-65),.06)
	place("ribbed_salt_pillar",Vector3(-23,-1.2,-67),-.13)
	place("sunken_retaining_wall",Vector3(-15,-.8,-60))
	place("sunken_retaining_wall",Vector3(15,-1.5,-60))
	place("stepped_sun_plinth",Vector3(0,-1.6,-78))
	place("buried_stair_8m",Vector3(0,-1.8,-68))
	place("fallen_fractured_lintel",Vector3(-15,0,-43),-.42)
	place("notched_waystone",Vector3(9,0,-31),.16)
	place("notched_waystone",Vector3(12,-1.4,6),.1)
	for row in [[-57.0,-38.0,"forked_spire",1.5,.4],[-85.0,-84.0,"blade_fin",1.7,.7],[67.0,-59.0,"eroded_needle",1.5,-.3],[92.0,-90.0,"hoodoo_crown",1.3,.6],[-59.0,28.0,"mushroom_outcrop",1.0,.1],[56.0,24.0,"wind_yardang",1.0,-.7],[88.0,4.0,"undercut_bank",1.3,.4]]:
		grounded(row[2],row[0],row[1],row[4],row[3],.65)
	for row in [[-137.0,-209.0,"tiered_escarpment",2.1,.1],[8.0,-270.0,"tabletop_mesa",2.4,-.12],[145.0,-176.0,"serrated_ridge",3.6,-.7],[-203.0,-69.0,"tabletop_mesa",2.9,.4],[238.0,-57.0,"tiered_escarpment",2.0,-1.1]]:
		grounded(row[2],row[0],row[1],row[4],row[3],1.2)
	# A two-metre scale staff makes the empty approach's scale explicit.
	var staff_materials: Array[StandardMaterial3D] = []
	for color in [Color(.22,.24,.22),Color(.78,.76,.68)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		staff_materials.append(m)
	for i in 8:
		_slab("ScaleStaff2m",Vector3(5,.125+i*.25,-54),Vector3(.14,.25,.14),landscape,staff_materials[i%2])

func _details() -> void:
	for row in [[-10.0,25.0,"salt_polygon_plates",1.2,.0],[-15.0,20.0,"salt_pressure_ridge",1.0,.4],[17.0,23.0,"crust_shelf",1.0,-.2],[24.0,14.0,"dry_rill_banks",1.0,.3],[-23.0,13.0,"mineral_blades",1.0,.0],[14.0,36.0,"salt_rosette",1.0,.0],[-33.0,-5.0,"root_snag",1.0,.7],[32.0,-25.0,"dead_flat_acacia",1.0,-.6],[-38.0,18.0,"arched_thorn",1.0,.0],[28.0,22.0,"spear_fan",1.0,.0]]:
		grounded(row[2],row[0],row[1],row[4],row[3],.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47063
	var all_positions: Array[String] = []
	# Four 40m cells each side: bounded sparse foliage batches and three real LODs.
	for side in [-1.0,1.0]:
		for cell in 4:
			for typ in 3:
				var id: String = ["dry_fan_grass","saltbrush_cushion","tumble_cage"][typ]
				var transforms: Array[Transform3D] = []
				var center := Vector3(side*47,0,40-cell*40)
				for i in 16:
					var p := center + Vector3(rng.randf_range(-15,15),0,rng.randf_range(-18,18))
					if sin(p.x*.21)*cos(p.z*.14)<.0:
						continue
					p.y = height_at(p.x,p.z)
					all_positions.append(str(p))
					transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.65,1.15)),p-center))
				for level in 3:
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = SaltAsset.mesh_for(id,level)
					mm.instance_count = transforms.size()
					for i in transforms.size():
						mm.set_instance_transform(i,transforms[i])
					var instance := MultiMeshInstance3D.new()
					instance.name = "DryCell_%d_%d_%d_%d" % [int(side),cell,typ,level]
					instance.position = center
					instance.multimesh = mm
					instance.material_override = SaltAsset.ATLAS
					instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					instance.visibility_range_begin = [0.0,38.0,78.0][level]
					instance.visibility_range_end = [38.0,78.0,140.0][level]
					landscape.add_child(instance)
				vegetation_instances += transforms.size()
	scatter_signature = "|".join(all_positions).sha256_text()

func _terrain() -> void:
	# Nine exact 160m chunks; shared samples mean no tile cracks.
	for cz in 3:
		for cx in 3:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in 32:
				for x in 32:
					for c in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
						_terrain_vertex(st,-240+cx*160+(x+c.x)*5,-240+cz*160+(z+c.y)*5)
			var mesh := MeshInstance3D.new()
			mesh.name = "SaltBasin_%d_%d" % [cx,cz]
			mesh.mesh = st.commit()
			mesh.material_override = TerrainMaterial
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			landscape.add_child(mesh)
			terrain_triangles += 2048
	if include_collision:
		var body := StaticBody3D.new()
		body.name = "SaltBasinHeightfield"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := HeightMapShape3D.new()
		shape.map_width = 97
		shape.map_depth = 97
		var heights := PackedFloat32Array()
		for z in 97:
			for x in 97:
				heights.append(height_at((x-48)*5.0,(z-48)*5.0))
		shape.map_data = heights
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.scale = Vector3(5,1,5)
		body.add_child(collision)
		landscape.add_child(body)
	var coords: Array[float] = []
	for x in range(-600,-240,30):
		coords.append(float(x))
	for x in range(-240,241,5):
		coords.append(float(x))
	for x in range(270,601,30):
		coords.append(float(x))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in coords.size()-1:
		for x in coords.size()-1:
			if coords[x]>=-240 and coords[x]<240 and coords[z]>=-240 and coords[z]<240:
				continue
			for c in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				_terrain_vertex(st,coords[x+c.x],coords[z+c.y])
			distant_triangles += 2
	var distant := MeshInstance3D.new()
	distant.name = "StitchedDistantSaltGround_NoCollision"
	distant.mesh = st.commit()
	distant.material_override = TerrainMaterial
	distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landscape.add_child(distant)

func _terrain_vertex(st: SurfaceTool, x: float, z: float) -> void:
	st.set_uv(Vector2(x,z)*.1)
	st.set_normal(Vector3(height_at(x-.5,z)-height_at(x+.5,z),1,height_at(x,z-.5)-height_at(x,z+.5)).normalized())
	st.add_vertex(Vector3(x,height_at(x,z),z))

func _slab(node_name: String, p: Vector3, size: Vector3, parent: Node3D, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = p
	node.material_override = material
	parent.add_child(node)

func _build_catalogue() -> void:
	catalogue = Node3D.new()
	catalogue.name = "KitCatalogue"
	catalogue.position = Vector3(0,0,800)
	add_child(catalogue)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.19,.23,.24)
	mat.roughness = 1
	_slab("CatalogueBackdrop",Vector3(0,-.4,0),Vector3(102,.5,108),catalogue,mat)
	var i := 0
	for id in SaltAsset.records():
		var record: Dictionary = SaltAsset.records()[id]
		var p := Vector3((1.5-i%4)*22,0,(1.5-(i%16)/4)*24)
		var extent: float = maxf(record.nominal_size[0],maxf(record.nominal_size[1],record.nominal_size[2]))
		var fit: float = clampf(11.5/extent,.12,6.0)
		var item := place(id,p,0,Vector3.ONE*fit,catalogue)
		item.set_meta("catalogue_page",i/16)
		item.set_meta("display_scale",fit)
		item.set_meta("label_anchor",p+Vector3(0,0,-8.5))
		i += 1
	catalogue.visible = false

func show_catalogue(enabled: bool) -> void:
	landscape.visible = not enabled
	if catalogue != null:
		catalogue.visible = enabled
