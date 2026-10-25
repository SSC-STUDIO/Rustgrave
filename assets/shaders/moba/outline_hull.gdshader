shader_type spatial;
render_mode unshaded, cull_front;

// Inverted hull: the enlarged twin of a part, drawn back faces only, leaves a
// ring about one render texel wide around the silhouette.

uniform vec4 outline_color : source_color = vec4(0.07, 0.05, 0.06, 1.0);

void fragment() {
	ALBEDO = outline_color.rgb;
}
