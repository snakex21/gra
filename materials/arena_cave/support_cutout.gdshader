shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Only hide the redundant support TOP beneath verified existing Hollowvault
// floor coverage, common to LOD0/1/2. No displacement and no physics change.
// Insets leave the transition gap, outer rim and tunnel end supported/visible.
uniform vec4 base_color : source_color = vec4(0.18, 0.19, 0.18, 1.0);
varying vec3 support_local;
void vertex() { support_local = VERTEX; }
void fragment() {
	vec2 p = support_local.xz;
	bool chamber = dot(p / vec2(22.0, 28.0), p / vec2(22.0, 28.0)) < 1.0;
	bool tunnel = abs(p.x) < 5.5 && p.y > 29.55 && p.y < 167.95;
	// Beyond 740m retain support: floor native LOD2 culls at800m.
	// Every point in the mask is <40m from its module bounds centre.
	// Keep opaque support at extreme grazing angles: imported dome is
	// 0.233mm below it; this bounds the floor-ray shift below0.234m.
	bool clear_floor_angle = dot(normalize(NORMAL), normalize(-VERTEX)) > 0.001;
	if (clear_floor_angle && length(VERTEX) < 740.0 && abs(support_local.y - 1.0) < 0.01 && (chamber || tunnel)) { discard; }
	ALBEDO = base_color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
