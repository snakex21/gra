class_name WaterBody
extends Node3D
## A body of still water: a disc of ``radius`` round this node whose surface is at this
## node's height. Wherever the ground inside it is lower than the surface, there is water.
## No collision: the player swims (PlayerCharacter.State.SWIM), Agro treats deep water as
## an edge, a colossus can swim in it. Optional visual: a translucent disc.
##
## Queries go through the group "water" (static helpers below), so any scene can have
## any number of them.

@export var radius := 30.0
@export var show_surface := true
@export var color := Color(0.16, 0.3, 0.34, 0.78)
@export var wave_amplitude := 0.08
var clock := 0.0
var ripple_events := PackedVector4Array()
var _ripple_next := 0
var _material: ShaderMaterial
var splashes := 0


func _ready() -> void:
	add_to_group(&"water")
	for i in 8:
		ripple_events.append(Vector4(0, 0, -100, 0))
	if show_surface:
		var m := PlaneMesh.new()
		m.size = Vector2.ONE * radius * 2.0
		m.subdivide_width = 64
		m.subdivide_depth = 64
		_material = ShaderMaterial.new()
		_material.shader = preload("res://src/fx/water_surface.gdshader")
		_material.set_shader_parameter(&"radius", radius)
		_material.set_shader_parameter(&"water_color", color)
		_material.set_shader_parameter(&"amplitude", wave_amplitude)
		var mi := MeshInstance3D.new()
		mi.name = "Surface"
		mi.mesh = m
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_sync_visual()

func _physics_process(delta: float) -> void:
	clock += delta
	_sync_visual()

func _sync_visual() -> void:
	if _material:
		_material.set_shader_parameter(&"clock", clock)
		_material.set_shader_parameter(&"ripples", ripple_events)

## Mean water level stays stable for swimming; small render waves never move colliders.
func splash(at: Vector3, impact_speed: float) -> void:
	var local := to_local(at)
	ripple_events[_ripple_next] = Vector4(local.x, local.z, clock, clampf(impact_speed * 0.035, 0.04, 0.4))
	_ripple_next = (_ripple_next + 1) % 8
	splashes += 1
	if DisplayServer.get_name() == "headless":
		return
	Sfx.play(self, &"splash", Vector3(at.x, surface(), at.z))
	var drops := CPUParticles3D.new()
	drops.name = "SplashDrops"
	drops.amount = 18
	drops.lifetime = 0.65
	drops.one_shot = true
	drops.explosiveness = 1.0
	drops.direction = Vector3.UP
	drops.spread = 45.0
	drops.initial_velocity_min = 1.5
	drops.initial_velocity_max = clampf(impact_speed * 0.35, 2.5, 6.0)
	drops.gravity = Vector3.DOWN * 9.8
	drops.scale_amount_min = 0.035
	drops.scale_amount_max = 0.085
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	drops.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.83, 0.9, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drops.material_override = mat
	add_child(drops)
	drops.global_position = Vector3(at.x, surface(), at.z)
	drops.finished.connect(drops.queue_free)
	drops.emitting = true


func contains_xz(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius


func surface() -> float:
	return global_position.y


## The water surface above ``p`` (any water body round it), or NAN when there is none.
static func surface_at(tree: SceneTree, p: Vector3) -> float:
	if tree == null:
		return NAN
	for w in tree.get_nodes_in_group(&"water"):
		var wb := w as WaterBody
		if wb and wb.contains_xz(p):
			return wb.surface()
	return NAN


## The water bodies of a tree (cached by callers that query every tick).
static func all(tree: SceneTree) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	if tree:
		for w in tree.get_nodes_in_group(&"water"):
			if w is WaterBody:
				out.append(w)
	return out
