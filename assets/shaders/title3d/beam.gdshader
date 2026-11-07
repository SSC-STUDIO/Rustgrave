shader_type spatial;

// Title forge hall — skylight / window light-shaft card.
//
// One additive, unshaded quad stretched along the shaft axis (see
// `TitleLighting._build_beam_cards`): the fragment mask is built from the card's
// own UV frame (radial falloff across the card, soft ends along it) and from a
// noise field anchored in WORLD space, so the drifting dust is a property of the
// hall and not of the quad. Everything is driven by uniforms, so the whole look
// is a pure function of (beam_time, cloud, emission_energy, …) and can be tested
// deterministically from the lighting rig.
//
// Forward+ notes: additive cards must never write depth and must not be
// premultiplied twice; blending is handled by `blend_add` with SRC_ALPHA/ONE, so
// ALBEDO * ALPHA is exactly what is added to the HDR buffer. ALBEDO is allowed to
// exceed 1.0 on purpose: that is what Glow (hdr_threshold 0.9) picks up.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Cool daylight of the hall, tinted by the active grade.
uniform vec4 beam_color : source_color = vec4(0.60, 0.76, 1.0, 1.0);
// HDR multiplier fed by the grade (shaft energy); >1 so Glow catches the core.
uniform float emission_energy : hint_range(0.0, 16.0) = 2.4;
// Global card opacity (intro / quit fades).
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// Cloud-shadow factor for the shaft (1 = open sky, 0.7 = dimmed), CPU driven.
uniform float cloud : hint_range(0.0, 2.0) = 1.0;
// Seconds since the rig started; the only clock the shader reads.
uniform float beam_time = 0.0;

uniform float noise_scale : hint_range(0.01, 8.0) = 1.15;
// World metres per second: x = drift across the beam, y = fall along the beam.
uniform vec2 scroll_speed = vec2(0.035, 0.42);
// 0 = constant beam, 1 = fully dust-modulated.
uniform float dust_density : hint_range(0.0, 2.0) = 0.85;
// Softness of the two long edges (radial falloff) and of the two ends.
uniform float radial_softness : hint_range(0.05, 4.0) = 1.25;
uniform float end_softness : hint_range(0.05, 4.0) = 1.60;
// Core tightening of the across-profile: >1 = thin hot core with wide corona.
uniform float core_power : hint_range(0.1, 6.0) = 1.70;
// 0 = smooth gradient, >1 = pixel-art steps of this many levels.
uniform float band_count : hint_range(0.0, 24.0) = 7.0;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Cheap smooth value noise (no texture fetch: the pixel stage wants a tiny cost).
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ---- card frame -------------------------------------------------------
	// UV.x runs across the shaft, UV.y along it (0 = top end, 1 = bottom end).
	float across01 = clamp(UV.x, 0.0, 1.0);
	float along01 = clamp(UV.y, 0.0, 1.0);

	// Radial falloff across the card: a soft corona with a tighter hot core.
	float across = clamp(1.0 - abs(across01 * 2.0 - 1.0), 0.0, 1.0);
	float radial = pow(across, core_power) * mix(1.0, 1.0 + radial_softness, across * across);

	// Both ends fade out: the shaft must not show a hard quad edge.
	float top_fade = smoothstep(0.0, clamp(0.16 * end_softness, 0.001, 0.5), along01);
	float bottom_fade = smoothstep(0.0, clamp(0.30 * end_softness, 0.001, 0.5), 1.0 - along01);
	float ends = top_fade * bottom_fade;

	// ---- world-anchored drifting dust ------------------------------------
	// The noise field lives on the hall's YZ plane (the shaft travels down and
	// toward the camera), scrolled by beam_time so the dust falls through the
	// light instead of sliding with the quad.
	vec2 field = vec2(world_pos.x * 0.65 + world_pos.z * 0.35, world_pos.y) * noise_scale;
	field += vec2(scroll_speed.x, -scroll_speed.y) * beam_time;
	float n_lo = value_noise(field);
	float n_hi = value_noise(field * 2.37 + vec2(17.3, 5.1));
	float dust = mix(1.0, 0.35 + 1.30 * (n_lo * 0.68 + n_hi * 0.32), clamp(dust_density, 0.0, 2.0));

	// ---- combine ----------------------------------------------------------
	float mask = radial * ends * dust * clamp(cloud, 0.0, 2.0) * clamp(opacity, 0.0, 1.0);
	mask = clamp(mask, 0.0, 1.0);
	if (band_count >= 1.0) {
		// Quantise only the *mask*: the colour ramp stays smooth so the additive
		// halo does not band against the dark hall.
		mask = floor(mask * band_count + 0.5) / band_count;
	}

	ALBEDO = beam_color.rgb * emission_energy;
	ALPHA = mask;
}
