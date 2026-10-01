shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D peat_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 uv=world_position.xz*.11;
 float mask=smoothstep(.3,2.8,world_position.y)*(.55+.25*sin(world_position.x*.05)*sin(world_position.z*.07));
 ALBEDO=mix(texture(peat_texture,uv).rgb,texture(moss_texture,uv*.82).rgb,mask);
 ROUGHNESS=.92; SPECULAR=.15;
}
