shader_type spatial;

// The creature art on a card: alpha blended over the background, cropped to the visible part of the
// picture with uv_scale / uv_offset, with the same contrast control as the background.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float contrast : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	vec4 texel = texture(albedo_texture, UV * uv_scale + uv_offset) * tint;
	ALBEDO = clamp((texel.rgb - vec3(0.2)) * contrast + vec3(0.2), 0.0, 1.0);
	ALPHA = texel.a;
}
