shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_metres = 5.0;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_metres;
	float variation = sin(world_pos.x * .12) * cos(world_pos.z * .11) * .5 + .5;
	vec3 earth = mix(texture(grass, uv).rgb, texture(soil, uv).rgb, (1.0-variation)*.35);
	vec3 base = mix(earth, texture(sand, uv).rgb, smoothstep(.35, .86, variation)*.72);
	float road_x = sin(world_pos.z * .027) * 4.0 - 1.0;
	float road = 1.0 - smoothstep(2.0, 3.8, abs(world_pos.x - road_x));
	base = mix(base, texture(path, uv).rgb, road * .92);
	float slope = 1.0 - smoothstep(.55, .9, abs(world_normal.y));
	base = mix(base, texture(rock, uv).rgb, slope);
	ALBEDO = base;
	ROUGHNESS = 1.0;
}
