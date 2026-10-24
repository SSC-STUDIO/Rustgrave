shader_type canvas_item;

uniform vec2 fade_rows = vec2(0.6, 1.0);

void fragment() {
	// CanvasItem COLOR already contains the sprite texture and its tint.
	COLOR.a *= 1.0 - smoothstep(fade_rows.x, fade_rows.y, UV.y);
}
