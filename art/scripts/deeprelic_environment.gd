@tool
extends Node3D
## Dedicated pack7 composition; earlier environments remain unchanged.
const Relic = preload("res://art/scripts/deeprelic_asset.gd")
const Cave = preload("res://art/scripts/hollowvault_asset.gd")
@export var include_collision := false
func put(script: Script, id: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var item := Node3D.new()
	item.set_script(script); item.model_id=id; item.position=pos; item.rotation.y=yaw
	item.collidable=include_collision; add_child(item)
	return item
func _ready() -> void:
	if get_child_count()>0:return
	put(Cave,"great_closed_dome",Vector3.ZERO)
	put(Cave,"vault_tunnel_12m",Vector3(0,0,-33))
	put(Cave,"stalagmite_great",Vector3(-17,0,-9))
	put(Cave,"stalagmite_cluster",Vector3(17,0,-11))
	put(Cave,"calcite_curtain",Vector3(-10,13,-12))
	put(Relic,"processional_arch",Vector3(0,0,-17))
	put(Relic,"processional_stair",Vector3(0,0,-9))
	put(Relic,"offering_table",Vector3(0,2.52,-13))
	# Raised altar platform supports the upper stair landing.
	put(Cave,"fallen_slab",Vector3(0,.6,-13))
	for x in [-8,8]:put(Relic,"horned_column",Vector3(x,0,-10))
	put(Relic,"empty_niche_shrine",Vector3(-12,0,-15),.35)
	put(Relic,"mineral_font",Vector3(10,0,-16))
	put(Relic,"carved_memorial",Vector3(13,0,-8),-.45)
	put(Relic,"parapet_crossing_10m",Vector3(-9,0,3),.25)
	put(Relic,"narrow_arch",Vector3(-10,0,-3),.25)
	put(Relic,"short_drum_column",Vector3(10,0,1))
	put(Relic,"fractured_column",Vector3(14,0,4))
	put(Relic,"fallen_column_drums",Vector3(14,0,8),.7)
	put(Relic,"broken_lintel_gate",Vector3(11,0,13),-.4)
	put(Relic,"broken_crossing",Vector3(-13,0,13),.7)
	put(Relic,"low_curb_crossing_6m",Vector3(-4,0,12),1.2)
	put(Relic,"utility_stair",Vector3(15,0,-2),-.8)
	put(Relic,"stair_with_landing",Vector3(-15,0,-4),.8)
	put(Relic,"torn_lean_to",Vector3(5,0,8),-.25)
	put(Relic,"cold_hearth",Vector3(3,0,12))
	put(Relic,"abandoned_bedroll",Vector3(5,0,8))
	put(Relic,"timber_bench",Vector3(2,0,14),.2)
	put(Relic,"provisions_table",Vector3(8,0,10),-.25)
	put(Relic,"expedition_chest",Vector3(7,0,7),-.25)
	put(Relic,"small_lockbox",Vector3(8,1.33,10),-.25)
	put(Relic,"supply_crate_stack",Vector3(10,0,7),.1)
	put(Relic,"sealed_storage_jar",Vector3(9,0,9))
	put(Relic,"stone_coffer",Vector3(-7,0,-13),.3)
	for p in [Vector3(2,0,10),Vector3(-4,0,-14),Vector3(4,0,-14)]:put(Relic,"unlit_lamp",p)
