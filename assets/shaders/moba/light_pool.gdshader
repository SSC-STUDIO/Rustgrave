shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Fake light under torches and crystals: a ground quad with stepped rings.
// Real omni lights are avoided in the pixel mode; Compatibility adds them in
// sRGB space on top of the shadow-casting sun, so they blow out unpredictably,
// and every lit mesh pays for them.

// Display-space colour times strength. Compatibility writes unshaded output
// without sRGB encoding and blends on the encoded image, so each ring adds
// exactly this much on screen.
uniform vec3 glow = vec3(0.18, 0.13, 0.05);
uniform float rings = 3.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float level = r < 1.0 ? 1.0 - floor(r * rings) / rings : 0.0;
	if (flicker > 0.0) {
		float ph = dot(NODE_POSITION_WORLD, vec3(1.7, 0.0, 2.3));
		float wave = 0.5 + 0.5 * sin(TIME * 9.0 + ph) * sin(TIME * 5.3 + ph * 1.9);
		level *= floor((1.0 - flicker * wave) * 4.0 + 0.5) * 0.25;
	}
	ALBEDO = glow * level;
}
