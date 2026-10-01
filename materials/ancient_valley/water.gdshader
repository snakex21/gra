shader_type spatial;
render_mode diffuse_burley, cull_disabled, specular_disabled;
uniform vec2 wind_direction = vec2(0.8,0.35);
uniform float wind_strength = 0.35;
varying vec3 p;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float wave=sin(dot(p.xz,wind_direction)*1.7+TIME*.65)*sin(p.z*2.1-TIME*.42);
 ALBEDO=mix(vec3(.025,.075,.078),vec3(.06,.13,.12),wave*.15+.3);
 ROUGHNESS=.65;METALLIC=0.0;
 // Opaque surface, no refraction, SSR, depth read, or planar reflection pass.
 NORMAL=normalize(NORMAL+vec3(wave*.015,0.0,cos(p.x*2.3+TIME)*.012));
}
