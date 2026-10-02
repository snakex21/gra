@tool
extends Node3D
## Art-only enclosed cavern. No actors, gameplay, climbing or controller changes.
const Asset = preload("res://art/scripts/hollowvault_asset.gd")
@export var include_collision := false
var placements := 0
func put(id: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var item := Node3D.new()
	item.set_script(Asset)
	item.model_id = id
	item.position = pos
	item.rotation.y = yaw
	item.collidable = include_collision
	item.lod_distances = Vector3(65,150,800)
	add_child(item)
	placements += 1
	return item
func _ready() -> void:
	if get_child_count() > 0: return
	put("great_closed_dome",Vector3.ZERO)
	put("vault_tunnel_12m",Vector3(0,0,-33))
	put("side_closed_dome",Vector3(0,0,-52))
	put("vault_tunnel_12m",Vector3(0,0,33))
	put("buried_gate",Vector3(0,0,-25))
	put("buried_altar",Vector3(0,0,-52))
	put("buried_stairs",Vector3(0,0,-13))
	put("travertine_pool",Vector3(9,.02,-3))
	put("flowstone_shelf",Vector3(15,0,1))
	put("fused_column",Vector3(-12,0,-4))
	put("calcite_curtain",Vector3(-9,13,-9),.5)
	for i in 14:
		var a := i*2.399
		var p := Vector3(cos(a)*17,0,sin(a)*21)
		put("stalagmite_great" if i%3==0 else "stalagmite_cluster",p,a)
		put("cave_boulder_small",p*.9,a)
	for i in 13:
		var a := i*2.399
		var rr := 0.25+0.45*float(i%4)/3.0
		var p := Vector3(cos(a)*22*rr,0,sin(a)*28*rr)
		p.y = 6+20*sqrt(1-rr*rr)-8
		put("stalactite_great",p,a)
	for i in 8:
		put("buried_lantern",Vector3(-5 if i%2==0 else 5,0,18-i*8))
	for i in 4:
		put("buried_pillar",Vector3(-7 if i%2==0 else 7,0,-13-i*3))
	put("fallen_slab",Vector3(-14,0,12),.6)
	put("talus_scatter",Vector3(13,0,12))
	put("buried_marker",Vector3(5,0,13))
