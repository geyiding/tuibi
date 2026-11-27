shader_type spatial;
render_mode shading_model_unlit, cull_disabled;

uniform sampler2D albedo_map : filter_linear_mipmap, repeat_disable;
uniform float brightness : hint_range(0.5, 2.5, 0.05) = 1.12;

vec3 srgb_to_linear(vec3 c) {
    return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void fragment() {
    vec3 tex = texture(albedo_map, UV).rgb;
    ALBEDO = srgb_to_linear(max(tex, vec3(0.0))) * brightness;
}
