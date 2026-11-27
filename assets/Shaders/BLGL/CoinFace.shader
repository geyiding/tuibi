shader_type spatial;
render_mode shading_model_unlit, blend_mix, cull_disabled;

uniform sampler2D albedo_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float brightness : hint_range(0.5, 2.5, 0.05) = 1.28;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    vec4 tex = texture(albedo_map, UV);
    ALBEDO = srgb_to_linear(max(tex.rgb, vec3(0.0))) * brightness;
    ALPHA = tex.a;
}
