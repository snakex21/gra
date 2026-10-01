@tool
extends Node3D
## Self-contained wetland art study. No actors, controllers, navigation or gameplay.
const MireAsset = preload("res://art/scripts/mirewood_asset.gd")
const TerrainMaterial = preload("res://materials/mirewood/terrain.tres")
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
	var shore := smoothstep(60.0,170.0,absf(x))
	return -1.2 + shore*(3.0+1.5*sin(x*.022+z*.017)*sin(z*.019)) + smoothstep(145.0,230.0,-z)*4.0

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
	n.set_script(MireAsset)
	n.model_id = id
	n.collidable = include_collision if parent == null else false
	n.lod_distances = Vector3(55, 145, 800) if parent == null else Vector3(900, 1100, 1500)
	n.name = "%s_%03d" % [id, asset_count + catalogue_count]
	n.position = p
	n.rotation.y = yaw
	n.scale = size
	n.cast_shadows = not id in ["broad_sedge", "cattail_rush", "marsh_fern", "lily_pad_raft", "hanging_moss"]
	if parent == null:
		landscape.add_child(n)
		asset_count += 1
	else:
		parent.add_child(n)
		catalogue_count += 1
	return n

func grounded(id: String, x: float, z: float, yaw := 0.0, scale_value := 1.0, bury := .12) -> Node3D:
	var base_height := height_at(x,z)
	var record: Dictionary = MireAsset.records()[id]
	if record.category == "geology":
		# Sink large formations to the lowest footprint sample on uneven dunes.
		# Centre-only placement can leave an eroded bank visibly hovering.
		for dx in [-.5,0.0,.5]:
			for dz in [-.5,0.0,.5]:
				var offset := Vector3(dx*float(record.nominal_size[0]),0,dz*float(record.nominal_size[2])).rotated(Vector3.UP,yaw)*scale_value
				base_height = minf(base_height,height_at(x+offset.x,z+offset.z))
	return place(id, Vector3(x,base_height-bury,z),yaw,Vector3.ONE*scale_value)

func _landmarks() -> void:
	# A dark reflecting pool is held open between island silhouettes.
	var water := MeshInstance3D.new()
	water.name = "OpaqueStillFen_NoReflectionPass"
	var plane := PlaneMesh.new()
	plane.size = Vector2(450,450)
	water.mesh = plane
	water.position.y = .05
	water.material_override = preload("res://materials/mirewood/water.tres")
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landscape.add_child(water)
	place("rootbound_gate",Vector3(0,.1,-54),0,Vector3(1.6,1.6,1.6))
	place("buried_moss_passage",Vector3(-24,.2,-64),-.17,Vector3.ONE*1.4)
	place("drowned_shrine",Vector3(17,-.3,-75),.2,Vector3.ONE*1.5)
	place("moss_retaining_wall",Vector3(-13,-.2,-57),.1)
	place("moss_retaining_wall",Vector3(15,-.5,-59),-.12)
	place("drowned_stairs",Vector3(0,-.1,-46),PI)
	place("rootwell_ring",Vector3(26,.15,-31))
	place("fen_waystone",Vector3(8,.0,-19),-.1)
	for row in [[-26.,-42.,1.4,.2],[34.,-66.,1.6,-.4],[-50.,-93.,2.0,.6],[59.,-109.,1.8,.3],[-74.,-36.,1.2,-.4],[52.,-8.,1.1,.3],[-31.,22.,1.2,.5]]:
		place("fen_elder_tree",Vector3(row[0],-.2,row[1]),row[3],Vector3.ONE*row[2])
	for row in [[-24.,-44.,1.4],[32.,-62.,1.4],[-49.,-93.,1.9],[53.,-110.,1.5],[-29.,25.,1.3],[29.,5.,1.6],[-40.,-10.,1.5]]:
		place("root_island",Vector3(row[0],-.1,row[1]),row[0]*.1,Vector3.ONE*row[2])
	place("crescent_island",Vector3(21,-.1,31),.35,Vector3.ONE*1.8)
	place("hollow_elder_trunk",Vector3(-15,.1,-22),.3)
	place("hollow_fallen_log",Vector3(23,0,9),-.7)
	place("fallen_root_tree",Vector3(-23,0,17),.5)
	place("woven_root_bridge",Vector3(-18,0,-37),.3)
	place("buttress_root",Vector3(-29,0,-43),.7)
	for i in range(10):
		var id := "boardwalk_8m"
		if i in [2,6]: id = "boardwalk_railed"
		if i == 4: id = "boardwalk_broken"
		place(id,Vector3(0,0,34-i*8))
	place("boardwalk_turn",Vector3(0,0,42))
	place("mooring_landing",Vector3(0,0,50))
	place("old_mooring_piles",Vector3(5,0,46))
	for side in [-1.,1.]:
		for i in range(9):
			place("root_bank_16m",Vector3(side*(66+5*sin(i)),.1,-115+i*26),PI*.5,Vector3(1.6,1.3,1.5))
			if i in [1,5]:
				place("hollow_elder_trunk",Vector3(side*(77+5*sin(i)),1,-112+i*26),i*.4,Vector3.ONE*(.65+.13*(i%3)))
	for row in [[12.,19.],[-16.,3.],[31.,-16.],[-36.,-53.],[13.,-39.]]:
		place("peat_hummock",Vector3(row[0],0,row[1]),row[0],Vector3.ONE*1.7)
	place("hanging_moss",Vector3(-2,15,-57),0,Vector3.ONE*1.7)

func _details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 58231
	var signature: Array[String] = []
	# 24m cells allow actual cluster culling; opaque leaves never alpha-blend.
	for side in [-1,1]:
		for cell in range(8):
			var center := Vector3(side*39.0,0,-102+cell*24)
			for typ in range(3):
				var id: String = ["cattail_rush","broad_sedge","lily_pad_raft"][typ]
				var transforms: Array[Transform3D] = []
				for k in range(26 if typ<2 else 10):
					var p := Vector3(rng.randf_range(-12,12),.08,rng.randf_range(-11,11))
					if typ<2:p.x += side*12.0
					var scale_value := rng.randf_range(.65,1.25)
					transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),p))
					signature.append(str(center+p))
				for level in range(3):
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = MireAsset.mesh_for(id,level)
					mm.instance_count = transforms.size()
					for k in transforms.size():mm.set_instance_transform(k,transforms[k])
					var batch := MultiMeshInstance3D.new()
					batch.name = "WetlandCell_%d_%d_%d_%d" % [side,cell,typ,level]
					batch.position = center
					batch.multimesh = mm
					batch.material_override = MireAsset.ATLAS
					batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					batch.visibility_range_begin = [0.,38.,78.][level]
					batch.visibility_range_end = [38.,78.,140.][level]
					landscape.add_child(batch)
				vegetation_instances += transforms.size()
	scatter_signature = "|".join(signature).sha256_text()

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
			mesh.name = "PeatBasin_%d_%d" % [cx,cz]
			mesh.mesh = st.commit()
			mesh.material_override = TerrainMaterial
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			landscape.add_child(mesh)
			terrain_triangles += 2048
	if include_collision:
		var body := StaticBody3D.new()
		body.name = "PeatBasinHeightfield"
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
	distant.name = "StitchedDistantPeatGround_NoCollision"
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
	_slab("CatalogueBackdrop",Vector3(0,-.4,0),Vector3(110,.5,65),catalogue,mat)
	var i := 0
	for id in MireAsset.records():
		var record: Dictionary = MireAsset.records()[id]
		var p := Vector3((1.5-i%4)*22,0,(.5-(i%8)/4)*28)
		var extent: float = maxf(record.nominal_size[0],maxf(record.nominal_size[1],record.nominal_size[2]))
		var fit: float = clampf(13.0/extent,.12,6.0)
		var item := place(id,p,0,Vector3.ONE*fit,catalogue)
		item.set_meta("catalogue_page",i/8)
		item.set_meta("display_scale",fit)
		item.set_meta("label_anchor",p+Vector3(0,0,-8.5))
		i += 1
	catalogue.visible = false

func show_catalogue(enabled: bool) -> void:
	landscape.visible = not enabled
	if catalogue != null:
		catalogue.visible = enabled
