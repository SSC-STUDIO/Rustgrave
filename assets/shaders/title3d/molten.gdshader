shader_type spatial;

// Title forge hall — molten river surface (the lava chasm under the iron bridge).
//
// The river runs along world Z between `river_bounds` (the kit's LAVA_Z_BACK ..
// LAVA_Z_FRONT) and the bridge crosses it along X, so the flow marches along +Z
// toward the camera. The material is unshaded and self-lit: the colour ramp is a
// pure function of two world-anchored noise layers plus the distance to the
// banks, and ALBEDO is pushed into HDR (>1) so the Forward+ Glow pass blooms the
// hottest veins. It is *not* lit by the volumetric fog; the pit OmniLight next to
// the surface handles the fog light, and this shader supplies the colour.
//
// Uniforms are driven by `TitleLighting` from the active grade (heat / colours /
// emission) and by `TitleLighting.advance()` through `molten_time`, so the lava
// is deterministic and headless-testable.
render_mode unshaded, cull_back;

// Colour ramp from cold slag to white-hot metal.
uniform vec4 cool_color : source_color = vec4(0.26, 0.09, 0.05, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.34, 0.09, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.74, 0.32, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 0.88, 0.66, 1.0);

// HDR multiplier; >1 by default so Glow (hdr_threshold 0.9) catches the veins.
uniform float emission_energy : hint_range(0.0, 16.0) = 2.2;
// Furnace heat 0..1.5 driven by the grade (`pit_energy`); 0 = dark, cold slag.
uniform float heat : hint_range(0.0, 2.0) = 1.0;
// Seconds since the rig started.
uniform float molten_time = 0.0;
// World metres per second of the sheet flow along +Z.
uniform float flow_speed : hint_range(-2.0, 2.0) = 0.30;
uniform float noise_scale : hint_range(0.01, 4.0) = 0.52;
// Second layer scale/speed ratio, gives the "two currents" look.
uniform float layer_ratio : hint_range(1.0, 4.0) = 1.73;
// Bright foam width (metres) along the two banks and the far/near ends.
uniform float foam_width : hint_range(0.01, 3.0) = 0.75;
uniform float foam_strength : hint_range(0.0, 4.0) = 1.15;
// 0 = smooth ramp, >1 = pixel-art colour steps.
uniform float band_count : hint_range(0.0, 24.0) = 6.0;
// Flow streaks riding the surface (0 disables).
uniform float streak_strength : hint_range(0.0, 2.0) = 0.55;
// x = min x, y = max x, z = min z, w = max z of the river quad in world space.
uniform vec4 river_bounds = vec4(-8.5, 8.5, -22.0, 12.0);

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

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

// Two octaves: cheap enough for the 640x360 pixel stage.
float fbm2(vec2 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.17 + vec2(7.3, 2.9)) * 0.38;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ---- two currents ------------------------------------------------------
	vec2 uv_a = world_pos.xz * noise_scale + vec2(0.0, -flow_speed) * molten_time;
	vec2 uv_b = world_pos.xz * noise_scale * layer_ratio
			+ vec2(0.14, -flow_speed * 1.47) * molten_time + vec2(11.7, 3.1);
	float n_a = fbm2(uv_a);
	float n_b = fbm2(uv_b);
	float heat_n = clamp(mix(n_a, n_b, 0.46) * 1.18 - 0.07, 0.0, 1.0);

	// ---- crust islands and their hot rims ---------------------------------
	float crust_mix = n_a * 0.62 + n_b * 0.38;
	float crust = smoothstep(0.58, 0.78, crust_mix);
	float crust_rim = smoothstep(0.48, 0.60, crust_mix) * (1.0 - smoothstep(0.60, 0.72, crust_mix));

	// ---- bank / end foam (the chasm walls chill the metal) ----------------
	float bank_dist = min(
			min(world_pos.x - river_bounds.x, river_bounds.y - world_pos.x),
			min(world_pos.z - river_bounds.z, river_bounds.w - world_pos.z));
	float bank = 1.0 - smoothstep(0.0, max(foam_width, 0.001), max(bank_dist, 0.0));
	float foam_field = value_noise(world_pos.xz * (noise_scale * 5.3)
			+ vec2(0.0, -flow_speed * 2.4) * molten_time);
	float bank_foam = bank * smoothstep(0.22, 0.72, foam_field);

	// ---- flow streaks (fast thin lines riding the current) ----------------
	float streak_field = value_noise(vec2(world_pos.x * 5.1, world_pos.z * 0.28 - molten_time * flow_speed * 2.6));
	float streaks = smoothstep(0.78, 0.96, streak_field) * streak_strength;

	// ---- colour ramp -------------------------------------------------------
	vec3 col = mix(cool_color.rgb, mid_color.rgb, smoothstep(0.10, 0.55, heat_n));
	col = mix(col, hot_color.rgb, smoothstep(0.52, 0.90, heat_n));
	col = mix(col, cool_color.rgb * 0.42, crust * 0.85);
	col = mix(col, hot_color.rgb * 1.18, crust_rim * 0.55);
	col = mix(col, hot_color.rgb, clamp(streaks, 0.0, 1.0) * 0.35);
	col = mix(col, foam_color.rgb, clamp((bank_foam + streaks * 0.5) * foam_strength, 0.0, 1.0));

	// Pixel-art step: quantise the ramp, never the HDR gain.
	if (band_count >= 1.0) {
		col = floor(col * band_count + 0.5) / band_count;
	}

	// ---- HDR emission ------------------------------------------------------
	float gain = emission_energy * mix(0.30, 1.00, clamp(heat, 0.0, 1.5) * 0.667);
	ALBEDO = clamp(col * gain, vec3(0.0), vec3(64.0));
}
