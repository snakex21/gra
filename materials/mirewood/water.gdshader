shader_type spatial;
render_mode diffuse_burley;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float ripple=sin(wp.x*1.7+sin(wp.z*.39))*sin(wp.z*1.1+wp.x*.23);
 ALBEDO=vec3(.105,.16,.14)+ripple*.006;
 ROUGHNESS=.37;SPECULAR=.4;
 NORMAL_MAP=vec3(.5+ripple*.008,.5+sin(wp.x*.5+wp.z)*.008,1.);
}
