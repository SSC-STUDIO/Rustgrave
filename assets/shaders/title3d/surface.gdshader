shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, ambient_light_disabled;

// Title forge-hall surface shader — Forward+ only, written for the linear
// renderer. There is deliberately no GL-Compatibility workaround here: one
// lighting pass, one ambient term.
//
// Base colour comes from the merged vertex colour, optionally multiplied by a
// 32x32 greyscale texture projected on the dominant world axis (so the texel
// density is identical on every wall, floor and prop, no UVs needed).
// Vertex alpha is an emission mask: 1 = lit surface, 0 = fully emissive
// (0.5 = half). Emission is what paints the forge mouth, windows and embers.
//
// The title's ambient light is a shader uniform instead of the Environment: it
// is added once, in the directional branch of light(). Keep the Environment's
// ambient light at zero; `ambient_light_disabled` above makes sure it cannot be
// added twice.
//
// light() is a three-band toon ramp that works for DirectionalLight3D and
// OmniLight3D/SpotLight3D alike. Directional lights fall back to
// `shadow_level` below `band_low` (so the sun always lifts the unlit faces),
// omni lights fall to zero (a floor there would leak onto every merged part
// whose AABB the light touches).

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_tex : filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float texels_per_unit = 16.0;
uniform float tex_size = 32.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float emission_gain = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed = 9.0;
uniform float band_high : hint_range(0.0, 1.0) = 0.55;
uniform float band_low : hint_range(0.0, 1.0) = 0.12;
uniform float mid_level : hint_range(0.0, 1.0) = 0.6;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.22;
// Optional hard specular glint (0 = off). Metal accents turn it on.
uniform float specular_band : hint_range(0.0, 1.0) = 0.0;
uniform float specular_sharpness : hint_range(1.0, 128.0) = 26.0;
// Linear colour times energy; the kit sets it for every title material.
uniform vec3 ambient_light = vec3(0.096, 0.206, 0.206);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb * tint.rgb;
	if (use_texture) {
		// World-axis projected greyscale multiplier: pick the plane the face is
		// most aligned with, then project in metres. `texels_per_unit` is the
		// density, so no stretch and no per-mesh UV authoring.
		vec3 n = abs(world_normal);
		vec2 uv;
		if (n.y >= n.x && n.y >= n.z) {
			uv = world_pos.xz;
		} else if (n.x >= n.z) {
			uv = vec2(world_pos.z, -world_pos.y);
		} else {
			uv = vec2(world_pos.x, -world_pos.y);
		}
		base *= texture(albedo_tex, uv * texels_per_unit / tex_size).rgb;
	}
	float emit = clamp(1.0 - COLOR.a, 0.0, 1.0);
	float pulse = 1.0;
	if (flicker > 0.0) {
		float ph = dot(world_pos, vec3(1.7, 0.0, 2.3));
		float wave = 0.5 + 0.5 * sin(TIME * flicker_speed + ph) * sin(TIME * flicker_speed * 0.59 + ph * 1.9);
		pulse = floor((1.0 - flicker * wave) * 4.0 + 0.5) * 0.25;
	}
	ALBEDO = base * (1.0 - emit);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = base * emit * emission_gain * pulse;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Directional lights report ATTENUATION = 1.0; omni/spot carry distance and
	// shadow attenuation there.
	float reach = clamp(ATTENUATION, 0.0, 1.0);
	float level;
	if (LIGHT_IS_DIRECTIONAL) {
		level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : shadow_level);
		// The title ambient is added exactly once, by the sun.
		DIFFUSE_LIGHT += ambient_light;
	} else {
		level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : 0.0);
	}
	vec3 light_energy = LIGHT_COLOR * reach / PI;
	DIFFUSE_LIGHT += level * light_energy;
	if (specular_band > 0.0 && metallic > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float glint = pow(clamp(dot(NORMAL, half_vec), 0.0, 1.0), specular_sharpness);
		SPECULAR_LIGHT += step(1.0 - specular_band, glint) * light_energy * metallic;
	}
}
