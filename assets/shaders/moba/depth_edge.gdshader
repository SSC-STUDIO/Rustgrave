shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

// Optional screen-space outline from depth discontinuities, drawn on the
// farther pixel of each edge. Used only when the spike toggles it on, so a
// renderer that lacks depth-texture reads fails there and nowhere else.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.07, 0.05, 0.06, 1.0);
uniform float depth_range = 120.0;
uniform float threshold = 0.35;
uniform bool reverse_z = false;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float depth_at(vec2 uv) {
	float d = texture(depth_tex, uv).r;
	return reverse_z ? 1.0 - d : d;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float c = depth_at(SCREEN_UV);
	float m = max(
			max(c - depth_at(SCREEN_UV + vec2(px.x, 0.0)), c - depth_at(SCREEN_UV - vec2(px.x, 0.0))),
			max(c - depth_at(SCREEN_UV + vec2(0.0, px.y)), c - depth_at(SCREEN_UV - vec2(0.0, px.y))));
	ALBEDO = line_color.rgb;
	ALPHA = step(threshold, m * depth_range);
}
