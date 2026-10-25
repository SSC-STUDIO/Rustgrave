shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Hard-edged contact disc under units; keeps them grounded when sun shadows
// are off or fall behind them.

uniform vec4 color : source_color = vec4(0.05, 0.03, 0.06, 0.5);

void fragment() {
	vec2 d = UV - vec2(0.5);
	ALBEDO = color.rgb;
	ALPHA = color.a * step(dot(d, d), 0.25);
}
