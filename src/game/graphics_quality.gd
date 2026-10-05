class_name GraphicsQuality
extends RefCounted
## Render-only presets. Call after world construction or a settings change,
## never from a frame callback. Directional atlas size is RenderingServer-global.
## Godot 4.6 supports these MSAA, atlas and cascade APIs in Compatibility too.

const DEFAULT_PROFILE := "balanced"
const PROFILES := {
	"low": {
		"msaa": Viewport.MSAA_DISABLED,
		"directional_atlas": 1024, "positional_atlas": 512, "depth_16_bits": true,
		"directional_mode": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"directional_distance": 45.0, "directional_fade": 0.65,
		"blend_splits": false, "split_1": 0.25,
		"positional_shadow_distance": 16.0, "mesh_lod_threshold": 3.0,
	},
	"balanced": {
		"msaa": Viewport.MSAA_2X,
		"directional_atlas": 2048, "positional_atlas": 1024, "depth_16_bits": true,
		"directional_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"directional_distance": 100.0, "directional_fade": 0.75,
		"blend_splits": false, "split_1": 0.25,
		"positional_shadow_distance": 32.0, "mesh_lod_threshold": 1.5,
	},
	"high": {
		"msaa": Viewport.MSAA_4X,
		"directional_atlas": 4096, "positional_atlas": 2048, "depth_16_bits": false,
		"directional_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"directional_distance": 180.0, "directional_fade": 0.85,
		"blend_splits": true, "split_1": 0.10,
		"positional_shadow_distance": 64.0, "mesh_lod_threshold": 1.0,
	},
}

# Avoid reallocating the renderer-global atlas when newly built regions receive
# the same preset. These static render values never belong to a world snapshot.
static var directional_atlas_size := -1
static var directional_atlas_16_bits := true

static func normalize(profile: String) -> String:
	var id := profile.strip_edges().to_lower()
	return id if PROFILES.has(id) else DEFAULT_PROFILE

static func parameters(profile: String = DEFAULT_PROFILE) -> Dictionary:
	return (PROFILES[normalize(profile)] as Dictionary).duplicate(true)

static func apply(world: Node, profile: String = DEFAULT_PROFILE) -> void:
	if not is_instance_valid(world): return
	world.set_meta(&"environment_groundcover_profile", normalize(profile))
	ForbiddenLandsTerrain.set_ground_quality(normalize(profile))
	var config := parameters(profile)
	var size := int(config.directional_atlas)
	var depth_16 := bool(config.depth_16_bits)
	if directional_atlas_size != size or directional_atlas_16_bits != depth_16:
		RenderingServer.directional_shadow_atlas_set_size(size, depth_16)
		directional_atlas_size = size
		directional_atlas_16_bits = depth_16
	var viewport := world as Viewport if world is Viewport else world.get_viewport()
	if viewport: _viewport(viewport, config)
	# One traversal per explicit apply. No process node, timers or scene-tree hook.
	var pending: Array[Node] = [world]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Viewport and node != viewport:
			_viewport(node as Viewport, config)
		elif node is DirectionalLight3D:
			var sun := node as DirectionalLight3D
			sun.directional_shadow_mode = int(config.directional_mode)
			sun.directional_shadow_max_distance = float(config.directional_distance)
			sun.directional_shadow_fade_start = float(config.directional_fade)
			sun.directional_shadow_blend_splits = bool(config.blend_splits)
			sun.directional_shadow_split_1 = float(config.split_1)
			sun.directional_shadow_split_2 = 0.30
			sun.directional_shadow_split_3 = 0.60
		elif node is MultiMeshInstance3D and node.has_meta(&"groundcover_kind"):
			EnvironmentGroundcover.apply_quality(node as MultiMeshInstance3D, normalize(profile))
		elif node is OmniLight3D or node is SpotLight3D:
			var light := node as Light3D
			# Shadow-only cutoff for lights with authored distance fade. Keep the
			# fade enable, light fade distances, intensity and radius untouched:
			# enabling fade for the sword would dim its cave illumination too.
			light.distance_fade_shadow = float(config.positional_shadow_distance)
		for child in node.get_children(): pending.append(child)

static func _viewport(viewport: Viewport, config: Dictionary) -> void:
	viewport.msaa_3d = int(config.msaa)
	viewport.positional_shadow_atlas_16_bits = bool(config.depth_16_bits)
	viewport.positional_shadow_atlas_size = int(config.positional_atlas)
	# Reserve one larger tile for the cave spotlight, then smaller local lights.
	viewport.set_positional_shadow_atlas_quadrant_subdiv(0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1)
	viewport.set_positional_shadow_atlas_quadrant_subdiv(1, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)
	viewport.set_positional_shadow_atlas_quadrant_subdiv(2, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)
	viewport.set_positional_shadow_atlas_quadrant_subdiv(3, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16)
	# Automatic mesh LOD is viewport-owned, not Camera3D-owned in Godot 4.6.
	# This leaves the project's manual LOD visibility ranges and colliders alone.
	viewport.mesh_lod_threshold = float(config.mesh_lod_threshold)
