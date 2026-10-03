shader_type spatial;
render_mode specular_disabled, cull_disabled, shadows_disabled;

// Reuse the stone tile of the one shared atlas as subtle greyscale ground detail.
// One texture fetch; no extra terrain texture allocation or multi-layer blend.
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 tile_uv = fract(UV * 0.13) * vec2(0.23, 0.46) + vec2(0.26, 0.52);
	vec3 detail = texture(atlas, tile_uv).rgb;
	float grain = clamp(dot(detail, vec3(0.333333)) * 2.4, 0.68, 1.15);
	ALBEDO = COLOR.rgb * mix(0.86, grain, 0.65);
	ROUGHNESS = 1.0;
}
