shader_type canvas_item;
// Chapter colour grade for backdrop plates (not the play layer): maps each texel's
// value (max channel) onto a rust-dusk ramp and blends it over the authored colour.
// Value order is preserved, so silhouettes and depth layering stay as painted;
// only the hue family moves from Gothicvania violet/magenta to plum, rust and ember.
// COLOR already carries texture x modulate (night darkening, cloud alpha).
uniform float amount : hint_range(0.0, 1.0) = 0.5;
uniform vec3 c0 : source_color = vec3(0.071, 0.039, 0.055);
uniform vec3 c1 : source_color = vec3(0.231, 0.114, 0.141);
uniform vec3 c2 : source_color = vec3(0.416, 0.188, 0.188);
uniform vec3 c3 : source_color = vec3(0.659, 0.333, 0.227);
uniform vec3 c4 : source_color = vec3(0.941, 0.659, 0.408);

vec3 ramp(float v) {
	if (v < 0.35) return mix(c0, c1, v / 0.35);
	if (v < 0.6) return mix(c1, c2, (v - 0.35) / 0.25);
	if (v < 0.8) return mix(c2, c3, (v - 0.6) / 0.2);
	return mix(c3, c4, clamp((v - 0.8) / 0.2, 0.0, 1.0));
}

void fragment() {
	vec4 c = COLOR;
	float v = max(c.r, max(c.g, c.b));
	COLOR = vec4(mix(c.rgb, ramp(v), amount), c.a);
}
