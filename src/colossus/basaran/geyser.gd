class_name BasaranGeyser
extends Node3D
## Deterministic vent: a visible warning, a water jet, then a quiet interval.
enum Phase { QUIET, WARNING, ERUPTING }
var radius := 6.5
var clock := 0.0
var offset := 0.0
var phase := Phase.QUIET
var _jet: MeshInstance3D
var _ring: MeshInstance3D

func _ready() -> void:
	add_to_group(&"basaran_geysers")
	process_physics_priority = -20
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.22, 0.22, 0.19)
	TerrainKit.box(self, Vector3(0, -0.12, 0), Vector3(8, 0.2, 8), rock)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.75, 0.78, 0.48)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.55)
	_jet = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.7
	cylinder.bottom_radius = 2.7
	cylinder.height = 1.0
	_jet.mesh = cylinder
	_jet.material_override = mat
	add_child(_jet)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.8
	torus.outer_radius = 3.2
	_ring.mesh = torus
	_ring.position.y = 0.08
	_ring.material_override = mat
	add_child(_ring)
	_refresh()

func _physics_process(delta: float) -> void:
	clock += delta
	_refresh()

func _refresh() -> void:
	var t := fposmod(clock + offset, 17.0)
	phase = Phase.QUIET if t < 5.0 else (Phase.WARNING if t < 8.0 else Phase.ERUPTING)
	var height := 13.0 + sin(clock * 11.0) * 0.9 if phase == Phase.ERUPTING else (0.5 if phase == Phase.WARNING else 0.05)
	_jet.scale.y = height
	_jet.position.y = height * 0.5
	_jet.visible = phase != Phase.QUIET
	_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(clock * 5.0))

func contains(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() <= radius

func reset() -> void:
	clock = 0.0
	_refresh()
