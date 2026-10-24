shader_type canvas_item;

// "Forged in" reveal for the title logo: a slanted front sweeps left to right; behind it
// the letters are white-hot, then ember, then settle into the logo's own amber/rust.
// Heat is posterised into `steps` bands so it stays pixel-art (no smooth glow).
// progress 0 = nothing visible, 1 = the plain logo.

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.02, 0.8) = 0.28;
uniform float slant : hint_range(0.0, 1.0) = 0.35;
uniform float steps : hint_range(2.0, 8.0) = 4.0;
uniform vec4 hot : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.76, 0.29, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float pos = UV.x + UV.y * slant;
	float front = progress * (1.0 + trail + slant);
	float behind = front - pos;
	if (behind <= 0.0 || tex.a < 0.01) {
		COLOR = vec4(tex.rgb, 0.0);
	} else {
		float heat = clamp(1.0 - behind / trail, 0.0, 1.0);
		heat = floor(heat * steps) / steps;
		vec3 c = tex.rgb;
		c = mix(c, ember.rgb, step(0.25, heat) * 0.9);
		c = mix(c, hot.rgb, step(0.74, heat));
		COLOR = vec4(c, tex.a);
	}
}
