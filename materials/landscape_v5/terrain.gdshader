shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled, shadows_disabled;

// Original procedural ground_v6 textures: no copied imagery. World coordinates
// keep chunk seams exact; two rotated, incommensurate scales suppress obvious
// tiling. Existing vertex biome colour is retained as a bounded climate tint.
// Balanced/high: eleven texture fetches; low: four, with no normal fetches.
// Shared 3 x 512px colour + 3 x 512px normal + 256px macro allocations.
// Visual only: never displace VERTEX or alter travel geometry/physics/layouts.
uniform sampler2D ground_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_macro : filter_linear_mipmap, repeat_enable;
uniform float tile_metres = 4.5;
uniform float normal_strength = 0.48;
uniform bool low_detail = false;
varying vec3 ground_world;
varying vec3 ground_world_normal;

vec2 rotate_ground(vec2 p) {
	return vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
}

vec3 ground_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

vec3 ground_srgb(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, step(c, vec3(0.0031308)));
}

vec3 ground_sample(sampler2D tex, vec2 uv, vec2 uv2) {
	vec3 a = texture(tex, uv).rgb;
	if (low_detail) {
		return OUTPUT_IS_SRGB ? ground_linear(a) : a;
	}
	vec3 b = texture(tex, uv2).rgb;
	// Compatibility exposes sRGB samples and decodes ALBEDO after fragment().
	// Keep blend/tint arithmetic linear here, as Forward+ and Blender already do.
	if (OUTPUT_IS_SRGB) {
		a = ground_linear(a);
		b = ground_linear(b);
	}
	return mix(a, b, 0.28);
}

vec3 ground_normal(sampler2D tex, vec2 uv) {
	// RGTC stores XY only. Reconstruct Z explicitly rather than reading an
	// undefined blue channel; this also matches the uncompressed authoring PNG.
	vec2 xy = texture(tex, uv).rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void vertex() {
	ground_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	// The generated terrain supplies UVs/normals but no tangent channel. Supply
	// an explicit X/Z frame for its world-planar normal maps, including slopes.
	TANGENT = normalize(vec3(NORMAL.y, -NORMAL.x, 0.0));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	vec2 p = ground_world.xz;
	vec3 macro_a = texture(ground_macro, p * 0.0031).rgb;
	vec3 macro = macro_a;
	if (!low_detail) {
		vec3 macro_b = texture(ground_macro, rotate_ground(p) * 0.0117 + vec2(0.31, 0.67)).rgb;
		macro = mix(macro_a, macro_b, 0.35);
	}
	vec2 warped = p + (macro.rg - vec2(0.5)) * 7.0;
	vec2 uv = warped / tile_metres;
	vec2 uv2 = rotate_ground(warped) * (0.417 / tile_metres) + vec2(0.19, 0.73);
	vec3 grass = ground_sample(ground_grass, uv, uv2);
	vec3 soil = ground_sample(ground_soil, uv, uv2);
	vec3 rock = ground_sample(ground_rock, uv, uv2);
	float dry = clamp((COLOR.r - COLOR.g + 0.02) * 7.0, 0.0, 1.0);
	grass = mix(grass, grass * vec3(1.14, 0.95, 0.77), dry * 0.72);
	float soil_weight = clamp(smoothstep(0.40, 0.69, macro.r) * 0.68 + dry * 0.26, 0.0, 1.0);
	float slope = 1.0 - smoothstep(0.72, 0.96, abs(ground_world_normal.y));
	float exposure = max(slope, smoothstep(34.0, 82.0, ground_world.y) * 0.28);
	float rock_weight = clamp(exposure + smoothstep(0.63, 0.83, macro.g) * 0.46, 0.0, 1.0);
	vec3 biome = clamp(COLOR.rgb / vec3(0.30, 0.36, 0.25), vec3(0.58), vec3(1.38));
	vec3 base = mix(mix(grass, soil, soil_weight), rock, rock_weight);
	vec3 linear_albedo = base * mix(vec3(1.0), biome, 0.52) * mix(0.83, 1.13, macro.b);
	ALBEDO = OUTPUT_IS_SRGB ? ground_srgb(linear_albedo) : linear_albedo;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.0;
	if (!low_detail) {
		vec3 ng = ground_normal(grass_normal, uv);
		vec3 ns = ground_normal(soil_normal, uv);
		vec3 nr = ground_normal(rock_normal, uv);
		NORMAL_MAP = normalize(mix(mix(ng, ns, soil_weight), nr, rock_weight)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = mix(0.94, 0.87, rock_weight);
}
