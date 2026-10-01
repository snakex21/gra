shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dry : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ruin : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 p;
varying vec3 n;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;n=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
vec3 ground_sample(sampler2D tex, vec2 uv){
 vec2 r=mat2(vec2(.8,.6),vec2(-.6,.8))*uv;
 return (texture(tex,uv).rgb+texture(tex,r*.371+vec2(.13,.71)).rgb+texture(tex,r*.619+vec2(.49,.23)).rgb)/3.0;
}
void fragment(){
 vec2 uv=p.xz*.22;
 float patch=sin(p.x*.041)*cos(p.z*.035)*.5+.5;
 vec3 soil=ground_sample(dry,uv);
 vec3 base=mix(soil,ground_sample(grass,uv),smoothstep(.18,.76,patch));
 float dry_patch=1.0-smoothstep(22.0,42.0,distance(p.xz,vec2(58,-22)));
 base=mix(base,soil*vec3(1.1,1.02,.88),dry_patch);
 float shore=1.0-smoothstep(24.0,34.0,distance(p.xz,vec2(40,42)));
 base=mix(base,ground_sample(sand,uv),shore);
 float wet=shore*(1.0-smoothstep(-.5,.5,p.y));
 base=mix(base,soil*.40,wet);
 float road=1.0-smoothstep(2.5,5.2,abs(p.x-(sin(p.z*.023)*12.0-10.0)));
 base=mix(base,ground_sample(path,uv),road*.92);
 float ruins=1.0-smoothstep(14.0,24.0,distance(p.xz,vec2(-32,28)));
 base=mix(base,ground_sample(ruin,uv),ruins*.5);
 float slope=1.0-smoothstep(.55,.88,abs(n.y));
 base=mix(base,ground_sample(rock,uv),slope);
 ALBEDO=base;ROUGHNESS=mix(.98,.29,wet);
}
