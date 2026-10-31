shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec2 step_uv = SCREEN_PIXEL_SIZE * 2.0;
	vec3 color = texture(screen_texture, SCREEN_UV).rgb * 0.4;
	color += texture(screen_texture, SCREEN_UV + vec2(step_uv.x, 0.0)).rgb * 0.15;
	color += texture(screen_texture, SCREEN_UV - vec2(step_uv.x, 0.0)).rgb * 0.15;
	color += texture(screen_texture, SCREEN_UV + vec2(0.0, step_uv.y)).rgb * 0.15;
	color += texture(screen_texture, SCREEN_UV - vec2(0.0, step_uv.y)).rgb * 0.15;
	COLOR = vec4(color, 1.0);
}
