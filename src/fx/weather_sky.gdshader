shader_type sky;
// Three bounded value-noise octaves at most, no TIME, texture or volumetric pass.
uniform vec4 sky_top : source_color = vec4(0.28, 0.46, 0.55, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.77, 0.79, 0.69, 1.0);
uniform vec4 ground_color : source_color = vec4(0.45, 0.48, 0.42, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.84, 0.83, 0.73, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.88, 0.64, 1.0);
uniform vec3 sun_direction = vec3(0.1, 0.9, 0.3);
uniform vec3 moon_direction = vec3(-0.1, -0.9, -0.3);
uniform vec2 cloud_shift = vec2(0.0);
uniform float cloud_coverage = 0.2;
uniform float cloud_detail = 1.0;
uniform float daylight = 1.0;
uniform float anomaly = 0.0;

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x), u.y);
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float altitude = max(d.y, 0.0);
	float gradient = smoothstep(0.0, 0.72, altitude);
	vec3 base = mix(sky_horizon.rgb, sky_top.rgb, gradient);
	if (d.y < 0.0) {
		base = mix(sky_horizon.rgb, ground_color.rgb, smoothstep(0.0, 0.4, -d.y));
	}
	// Cheap cubemap: ambient/reflections are color-driven, clouds only draw behind geometry.
	if (AT_CUBEMAP_PASS) {
		COLOR = base;
	} else {
		vec2 p = d.xz / (0.20 + abs(d.y)) * 2.4 + cloud_shift;
		float n = noise21(p);
		if (cloud_detail > 0.5) { n = n * 0.70 + noise21(p * 2.07 + vec2(5.2, 1.3)) * 0.30; }
		if (cloud_detail > 1.5) { n = n * 0.86 + noise21(p * 4.03 + vec2(1.4, 8.1)) * 0.14; }
		float threshold = mix(0.88, 0.26, cloud_coverage);
		float clouds = smoothstep(threshold, threshold + 0.20, n) * smoothstep(0.01, 0.18, altitude) * cloud_coverage;
		base = mix(base, cloud_color.rgb * (0.78 + n * 0.22), clouds * 0.92);
		float solar = max(dot(d, normalize(sun_direction)), 0.0);
		float lunar = max(dot(d, normalize(moon_direction)), 0.0);
		float sun_disk = smoothstep(0.99976, 0.99986, solar) * smoothstep(-0.02, 0.05, sun_direction.y);
		float moon_disk = smoothstep(0.99969, 0.99982, lunar) * smoothstep(-0.02, 0.05, moon_direction.y) * (1.0 - daylight);
		base += sun_color.rgb * (sun_disk * 0.85 + pow(solar, 64.0) * 0.19) * (1.0 - clouds * 0.90) * daylight;
		vec3 moon_side = normalize(cross(normalize(moon_direction), vec3(0.0, 1.0, 0.0)));
		float moon_shade = clamp(0.68 + dot(d, moon_side) * 12.0, 0.42, 0.95);
		base += vec3(0.60, 0.70, 0.88) * moon_disk * moon_shade * (1.0 - clouds);
		vec2 star_coordinates = d.xz / (0.20 + altitude) * 140.0;
		vec2 star_grid = floor(star_coordinates);
		float star_point = 1.0 - smoothstep(0.06, 0.22, length(fract(star_coordinates) - vec2(0.5)));
		float stars = star_point * step(0.9985, hash21(star_grid)) * smoothstep(0.12, 0.45, altitude) * (1.0 - clouds) * pow(1.0 - daylight, 3.0);
		base += vec3(0.25, 0.30, 0.36) * stars;
		// A fixed dim stain in the low cloud layer, no flashes or markers.
		if (anomaly > 0.001) {
			float stain = smoothstep(0.0, 0.08, altitude) * (1.0 - smoothstep(0.08, 0.35, altitude));
			stain *= smoothstep(0.2, 0.8, noise21(p * 0.45 + vec2(7.0)));
			base = mix(base, base * vec3(0.73, 0.68, 0.86) + vec3(0.018, 0.007, 0.025), stain * anomaly * 0.32);
		}
		COLOR = max(base, vec3(0.0));
	}
}
