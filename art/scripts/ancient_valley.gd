@tool
extends Node3D
## Standalone 360 m art test. No gameplay scripts, player, AI, or camera controller.
const Asset = preload("res://art/scripts/valley_asset.gd")
const TerrainMaterial = preload("res://materials/ancient_valley/terrain.tres")
const WindMaterial = preload("res://materials/ancient_valley/wind.tres")
@export var scatter_seed := 24017
@export var vegetation_candidates := 3600
@export var include_collision := true
@export var wind_direction := Vector2(.8,.35)
@export_range(0.0,2.0) var wind_strength := .35
var asset_count := 0
var vegetation_instances := 0
var terrain_triangles := 0
var scatter_fingerprint := 0

static func height_at(x: float,z: float) -> float:
	var h := 1.4*sin(x*.023)*cos(z*.024)
	h += 20.0*smoothstep(65.0,145.0,absf(x))
	h += 8.0*smoothstep(70.0,155.0,z)
	var lake_r := Vector2((x-40)*.91,(z-42)*1.12).length() + 1.8*sin(x*.16)*cos(z*.15)
	var lake := 1.0-smoothstep(20.0,34.0,lake_r)
	h=lerpf(h,-3.0,lake)
	# A broad sunken canyon off the main travel axis.
	var canyon := (1.0-smoothstep(8.0,20.0,absf(x+96.0)))*smoothstep(-10.0,40.0,z)
	h-=canyon*11.0
	# Stable flat modular temple precinct, blended into surrounding terrain.
	var temple := 1.0-smoothstep(13.0,25.0,Vector2(x+32,z-28).length())
	h=lerpf(h,1.4,temple)
	return h

func _ready() -> void:
	if get_child_count()==0: build()

func place(id: String,p: Vector3,yaw := 0.0,size := 1.0,collision := "hull") -> Node3D:
	var n := Node3D.new()
	n.set_script(Asset)
	n.name=id+"_%03d"%asset_count
	n.model_id=id
	n.collidable=include_collision and collision!="none"
	n.collision_kind=collision
	n.position=p+Vector3.UP*height_at(p.x,p.z)
	n.rotation.y=yaw
	n.scale=Vector3.ONE*size
	n.lod_distances=Vector3(45,105,340) if id not in ["cliff","rock_arch"] else Vector3(90,190,580)
	add_child(n)
	asset_count+=1
	return n

func build() -> void:
	WindMaterial.set_shader_parameter("wind_direction",wind_direction)
	WindMaterial.set_shader_parameter("wind_strength",wind_strength)
	_terrain()
	# 24 x 20 m temple; 4 m floor/module snapping and unobstructed entrance.
	for x in 6:
		for z in 5:
			place("floor",Vector3(-42+x*4,.02,20+z*4),0,1,"none")
	for x in [-42,-22]:
		for z in [20,28,36]:
			place("column" if z!=28 else "column_broken",Vector3(x,.18,z))
	for x in [-40,-36,-32,-28,-24]:
		place("beam_4m",Vector3(x,6.82,36))
	place("arch",Vector3(-32,.18,18),0,1,"opening_boxes")
	place("stairs",Vector3(-32,-.1,15),0,1,"stair_ramp_v2")
	place("altar",Vector3(-32,.18,31))
	place("relief",Vector3(-32,.18,38))
	place("wall_corner",Vector3(-42,.18,38))
	place("wall_broken",Vector3(-24,.18,38))
	place("door",Vector3(-22,.18,31),PI*.5,1,"opening_boxes")
	place("rubble_0",Vector3(-46,0,25),.4)
	place("rubble_1",Vector3(-21,0,14),1.4)
	for i in 7:
		place("channel",Vector3(-12+i*4,0,36),0,1,"channel_boxes")
	# Landmark and canyon edges. Preserve open central basin and long sightlines.
	place("rock_arch",Vector3(-91,0,81),-.22,2.0,"rock_arch_boxes")
	# Overlapping escarpment masses, not an evenly spaced perimeter fence.
	var clusters := [Vector3(-133,0,124),Vector3(-41,0,169),Vector3(93,0,156),Vector3(164,0,51),Vector3(-164,0,-40)]
	for i in clusters.size():
		for j in 3:
			var p: Vector3=clusters[i]+Vector3((j-1)*15,-4.5-j*.8,sin(j*1.9+i)*7)
			var mass := place("cliff",p,.24*sin(i+j*.8)+(PI*.5 if i>2 else 0.0),1.0)
			mass.scale=Vector3(1.75+j*.22,.65+.3*sin(i*1.7+j)+j*.22,1.8)
			mass.position.y=ground_min(p,28,16)-1.5
			if j==1:
				var shelf := place("ledge",p+Vector3(5,-2,-6),.2*i,1.0)
				shelf.scale=Vector3(2.4,1.5,1.8)
				shelf.position.y=ground_min(shelf.position,20,12)-.5
	place("ledge",Vector3(-79,0,52),.2,1.8)
	var rng := RandomNumberGenerator.new()
	rng.seed=scatter_seed
	for i in 54:
		var p := Vector3(rng.randf_range(-125,125),0,rng.randf_range(-95,118))
		if absf(p.x-(sin(p.z*.023)*12-10))<14 or Vector2(p.x-40,p.z-42).length()<37 or Vector2(p.x+32,p.z-28).length()<28:
			continue
		# Sparse edge groupings rather than filling the central empty space.
		if absf(p.x)<52 and p.z<5:continue
		place(["slate_","chalk_","basalt_"][i%3]+str(i%3),p,rng.randf()*TAU,rng.randf_range(.8,1.8))
	for row in [["tree_oak",Vector3(-51,0,14)],["tree_cypress",Vector3(-52,0,40)],["tree_cypress",Vector3(-49,0,44)],["tree_willow",Vector3(68,0,38)],["tree_willow",Vector3(61,0,62)],["tree_dead",Vector3(63,0,-29)]]:
		place(row[0],row[1],rng.randf()*TAU,1,"trunk")
	for i in 14:
		place("shrub_heather" if i%2==0 else "shrub_thorn",Vector3(-60+rng.randf()*16,0,5+rng.randf()*50),rng.randf()*TAU,1,"none")
	place("roots",Vector3(-50,0,15),.2,1,"none")
	_horizon()
	_water()
	_scatter(rng)

func _terrain() -> void:
	# 9 spatial chunks: culling locality, one shared seven-surface material.
	for cz in 3:
		for cx in 3:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in 40:
				for x in 40:
					for c in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
						var px: float = -180.0+cx*120+(x+c.x)*3
						var pz: float = -180.0+cz*120+(z+c.y)*3
						st.set_uv(Vector2(px,pz)*.2)
						st.set_normal(Vector3(height_at(px-.5,pz)-height_at(px+.5,pz),1.0,height_at(px,pz-.5)-height_at(px,pz+.5)).normalized())
						st.add_vertex(Vector3(px,height_at(px,pz),pz))
			var n := MeshInstance3D.new()
			n.name="Terrain_%d_%d"%[cx,cz]
			n.mesh=st.commit()
			n.material_override=TerrainMaterial
			n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			terrain_triangles+=3200
	if include_collision:
		var body := StaticBody3D.new()
		body.name="ArtTerrainCollision_91x91"
		body.collision_layer=1;body.collision_mask=0
		var shape := HeightMapShape3D.new()
		shape.map_width=91;shape.map_depth=91
		var heights := PackedFloat32Array()
		for z in 91:
			for x in 91:heights.append(height_at((x-45)*4.0,(z-45)*4.0))
		shape.map_data=heights
		var col := CollisionShape3D.new()
		col.shape=shape;col.scale=Vector3(4,1,4)
		body.add_child(col);add_child(body)

func _water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader=preload("res://materials/ancient_valley/water.gdshader")
	mat.set_shader_parameter("wind_direction",wind_direction)
	mat.set_shader_parameter("wind_strength",wind_strength)
	var lake := MeshInstance3D.new()
	lake.name="OpaqueLake_96Triangles_NoReflectionPass"
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		st.set_normal(Vector3.UP);st.add_vertex(Vector3.ZERO)
		for a in [i*TAU/64.0,(i+1)*TAU/64.0]:
			st.set_normal(Vector3.UP);st.add_vertex(Vector3(cos(a)*25.0,0,sin(a)*20.4))
	var mesh := st.commit()
	lake.mesh=mesh;lake.position=Vector3(40,-.35,42);lake.material_override=mat
	lake.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	var canal := MeshInstance3D.new()
	canal.name="ShallowCanal_NoSimulation"
	var plane := PlaneMesh.new();plane.size=Vector2(28,.95)
	canal.mesh=plane;canal.position=Vector3(0,1.17,36);canal.material_override=mat
	canal.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(canal)

func _scatter(rng: RandomNumberGenerator) -> void:
	var chunks: Dictionary={}
	for i in vegetation_candidates:
		var p := Vector3(rng.randf_range(-116,116),0,rng.randf_range(-100,118))
		if absf(p.x-(sin(p.z*.023)*12-10))<6 or Vector2(p.x+32,p.z-28).length()<24 or Vector2(p.x-40,p.z-42).length()<26:continue
		if sin(p.x*.077)*cos(p.z*.058)<.18:continue
		p.y=height_at(p.x,p.z)
		var typ := i%4
		var key := Vector3i(floori(p.x/24),floori(p.z/24),typ)
		if not chunks.has(key):chunks[key]=[]
		chunks[key].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.65,1.3)),p))
		vegetation_instances+=1
		scatter_fingerprint=(scatter_fingerprint+int(p.x*100)*31+int(p.z*100)*17)&0x7fffffff
	for key: Vector3i in chunks:
		var center := Vector3(key.x*24+12,0,key.y*24+12)
		var transforms: Array=chunks[key]
		for level in 3:
			var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
			mm.mesh=Asset.mesh_for(["grass_dry_v2","fern","reed","moss_patch"][key.z],level)
			mm.instance_count=transforms.size()
			for j in transforms.size():
				var xf: Transform3D=transforms[j];xf.origin-=center;mm.set_instance_transform(j,xf)
			var n := MultiMeshInstance3D.new();n.name="Vegetation_%s_LOD%d"%[key,level]
			n.multimesh=mm;n.position=center;n.material_override=WindMaterial
			n.visibility_range_begin=[0,32,62][level];n.visibility_range_end=[32,62,95][level]
			n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)

func _horizon() -> void:
	# Non-collidable, coarse terrain continuation prevents a cut-off horizon.
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-300,300,20):
		for x in range(-300,300,20):
			if x>=-180 and x<180 and z>=-180 and z<180:continue
			for c in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var px: float=x+c.x*20;var pz: float=z+c.y*20
				var edge := smoothstep(180.0,280.0,maxf(absf(px),absf(pz)))
				var h := height_at(px,pz)+edge*(12+10*sin(px*.025)+8*cos(pz*.032))
				st.set_normal(Vector3.UP);st.set_uv(Vector2(px,pz)*.2);st.add_vertex(Vector3(px,h,pz))
	var n := MeshInstance3D.new();n.name="DistantTerrain_1152Triangles_NoCollision";n.mesh=st.commit();n.material_override=TerrainMaterial
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n)

static func ground_min(p: Vector3,rx: float,rz: float) -> float:
	var h := INF
	for x in [-1.0,0.0,1.0]:
		for z in [-1.0,0.0,1.0]:h=minf(h,height_at(p.x+x*rx,p.z+z*rz))
	return h
