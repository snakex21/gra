shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D salt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sediment_albedo : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    float basin = (1.0-smoothstep(24.0,86.0,abs(world_position.x))) * (1.0-smoothstep(0.3,3.7,world_position.y));
    float slope = smoothstep(0.65,0.94,world_normal.y);
    vec3 salt = texture(salt_albedo,world_position.xz/18.0).rgb;
    vec3 sediment = texture(sediment_albedo,world_position.xz/12.0).rgb;
    float bands = .97+.03*sin(world_position.x*.06+world_position.z*.014);
    ALBEDO = mix(sediment,salt,basin*slope)*bands;
    ROUGHNESS = .96;
    SPECULAR = .08;
}
