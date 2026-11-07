shader_type canvas_item;

// Full-screen "waking up" effect: eyelids (top and bottom) open while the picture
// goes from blurred to sharp. openness 0 is pitch black, 1 is fully open.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 1.0) = 1.0;
uniform float openness : hint_range(0.0, 1.0) = 0.0;
uniform float max_lod = 5.0;
uniform float lid_softness = 0.25;

void fragment() {
	vec2 uv = SCREEN_UV;
	float lod = blur * max_lod;
	vec2 spread = SCREEN_PIXEL_SIZE * exp2(lod) * 0.5;
	vec3 color = textureLod(screen_texture, uv, lod).rgb * 0.4;
	color += textureLod(screen_texture, uv + vec2(spread.x, 0.0), lod).rgb * 0.15;
	color += textureLod(screen_texture, uv - vec2(spread.x, 0.0), lod).rgb * 0.15;
	color += textureLod(screen_texture, uv + vec2(0.0, spread.y), lod).rgb * 0.15;
	color += textureLod(screen_texture, uv - vec2(0.0, spread.y), lod).rgb * 0.15;
	float distance_from_center = abs(uv.y - 0.5) * 2.0;
	float edge = openness * (1.0 + lid_softness);
	float lid = 1.0 - smoothstep(edge - lid_softness, edge, distance_from_center);
	COLOR = vec4(color * lid, 1.0);
}
