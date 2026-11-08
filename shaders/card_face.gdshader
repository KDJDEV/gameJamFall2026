shader_type spatial;

// The card background. Like the plain material it replaces (alpha cut-out, crisp pixels), plus a
// contrast control that pushes the colours away from mid-grey.
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform float contrast : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	// 0.2 in linear light is mid-grey.
	ALBEDO = clamp((texel.rgb - vec3(0.2)) * contrast + vec3(0.2), 0.0, 1.0);
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
