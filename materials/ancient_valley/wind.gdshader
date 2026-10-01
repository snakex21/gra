shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 wind_direction = vec2(0.8,0.35);
uniform float wind_strength : hint_range(0.0,2.0) = 0.35;
varying vec3 local_pos;
void vertex(){
 local_pos=VERTEX;
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float weight=clamp(VERTEX.y*.16,0.0,1.0);
 // Tall canopies move subtly; ground foliage keeps roots fixed.
 VERTEX.xz += wind_direction*wind_strength*weight*sin(TIME*1.2+p.x*.32+p.z*.24)*.26;
}
void fragment(){ALBEDO=texture(atlas,UV).rgb; ROUGHNESS=1.0;}
