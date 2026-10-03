shader_type spatial;
render_mode cull_disabled;
uniform vec4 water_color : source_color = vec4(0.16, 0.3, 0.34, 0.78);
uniform float radius = 30.0;
uniform float clock = 0.0;
uniform float amplitude = 0.08;
uniform vec4 ripples[8];
varying vec2 local_xz;
float wave(vec2 p) {
	return amplitude * (sin(dot(p, vec2(0.85, 0.42)) * 1.1 + clock * 1.8)
		+ 0.5 * sin(dot(p, vec2(-0.3, 0.95)) * 1.7 + clock * 2.2));
}
void vertex() {
	local_xz = VERTEX.xz;
	VERTEX.y += wave(local_xz);
	for (int i = 0; i < 8; i++) {
		float age = clock - ripples[i].z;
		float d = distance(local_xz, ripples[i].xy);
		if (age >= 0.0 && age < 3.0) {
			VERTEX.y += ripples[i].w * exp(-age * 1.8) * exp(-pow(d - age * 3.0, 2.0) * 2.0);
		}
	}
	float e = 0.03;
	NORMAL = normalize(vec3((wave(local_xz - vec2(e, 0)) - wave(local_xz + vec2(e, 0))) / (2.0 * e),
		1.0, (wave(local_xz - vec2(0, e)) - wave(local_xz + vec2(0, e))) / (2.0 * e)));
}
void fragment() {
	if (length(local_xz) > radius) { discard; }
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(water_color.rgb, vec3(0.52, 0.66, 0.68), fresnel * 0.35);
	ROUGHNESS = 0.16;
	SPECULAR = 0.75;
	ALPHA = mix(water_color.a, 0.92, fresnel);
}
