class_name ArgusRuins
extends Node3D
## A fallen gallery slab pivots into a ramp when its counterweight is struck.
## The same body and collider move; access is a physical change to the terrain.
const PLATE := Vector3(6, 0.08, 2)
const RAMP_START := Vector3(18, 0, 44)
const RAMP_RISE := 12.0
const RAMP_RUN := 48.0
var activated := false
var route_open := false
var impacts := 0
var weight := 0.0
var ramp: StaticBody3D
var _plate_mesh: MeshInstance3D

func _ready() -> void:
	process_physics_priority = -20
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.43, 0.4, 0.33)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.28, 0.28, 0.25)
	var slab_length := Vector2(RAMP_RISE, RAMP_RUN).length()
	ramp = TerrainKit.box(self, RAMP_START + Vector3(0, -0.6, -slab_length * 0.5), Vector3(7, 1.2, slab_length), stone)
	ramp.name = "HingedGalleryRamp"
	for side: float in [-1.0, 1.0]:
		TerrainKit.box(self, Vector3(side * 18, 11.5, -7), Vector3(7, 1, 8), stone)
		for z: float in [-10.0, -4.0]:
			TerrainKit.box(self, Vector3(side * 20, 5.5, z), Vector3(2.4, 11, 2.4), dark)
	TerrainKit.box(self, Vector3(0, 11.5, -6), Vector3(36, 1, 4), stone).name = "GalleryBridge"
	TerrainKit.box(self, Vector3(0, 11.5, -3.8), Vector3(3.6, 1, 2.5), stone).name = "JumpToGuardian"
	TerrainKit.box(self, Vector3(0, 8, -24), Vector3(48, 16, 3), dark)
	var plate := TerrainKit.box(self, PLATE - Vector3.UP * 0.08, Vector3(3.6, 0.16, 3.6), dark)
	plate.name = "StompCounterweight"
	_plate_mesh = plate.get_child(1) as MeshInstance3D
	_refresh()

func _physics_process(delta: float) -> void:
	weight = move_toward(weight, 1.0 if activated else 0.0, delta / 2.5)
	route_open = weight >= 0.999
	_refresh()

func _refresh() -> void:
	if ramp == null:
		return
	var angle := atan2(RAMP_RISE, RAMP_RUN) * smoothstep(0.0, 1.0, weight)
	var basis := Basis(Vector3.RIGHT, angle)
	var length := Vector2(RAMP_RISE, RAMP_RUN).length()
	ramp.transform = Transform3D(basis, RAMP_START + basis * Vector3(0, -0.6, -length * 0.5))
	var mat := _plate_mesh.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color(0.08, 0.32, 0.42) if activated else Color(0.45, 0.17, 0.03)
	mat.emission_energy_multiplier = 0.65

func receive_impact(point: Vector3) -> bool:
	var local := to_local(point)
	if activated or Vector2(local.x - PLATE.x, local.z - PLATE.z).length() > 3.0:
		return false
	activated = true
	impacts += 1
	return true

func reset() -> void:
	activated = false
	route_open = false
	weight = 0.0
	impacts = 0
	_refresh()
