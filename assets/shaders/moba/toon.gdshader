shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Stepped toon lighting for the 3D pixel mode. Base colour comes from vertex
// colours (one shared material for every rigid part); vertex alpha is an
// emission mask: 1 = lit, 0 = fully emissive. Textured variants multiply a
// nearest-sampled luminance texture projected on the dominant world axis so the
// texel density is the same on every surface. The texture holds plain
// multipliers, so it is sampled without sRGB decoding.

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_tex : filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float texels_per_unit = 16.0;
uniform float tex_size = 32.0;
uniform float emission_gain = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float band_high : hint_range(0.0, 1.0) = 0.55;
uniform float band_low : hint_range(0.0, 1.0) = 0.12;
uniform float mid_level : hint_range(0.0, 1.0) = 0.6;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.22;
// Linear colour times energy; the kit sets it for every toon material.
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
	float emit = 1.0 - COLOR.a;
	float pulse = 1.0;
	if (flicker > 0.0) {
		float ph = dot(NODE_POSITION_WORLD, vec3(1.7, 0.0, 2.3));
		float wave = 0.5 + 0.5 * sin(TIME * 9.0 + ph) * sin(TIME * 5.3 + ph * 1.9);
		pulse = floor((1.0 - flicker * wave) * 4.0 + 0.5) * 0.25;
	}
	ALBEDO = base * (1.0 - emit);
	EMISSION = base * emit * emission_gain * pulse;
}

// Ambient rides on the sun instead of the Environment (keep that ambient at 0).
// Compatibility draws a shadow-casting sun in an extra pass that is blended
// after sRGB encoding, so base-pass ambient plus sun would add in sRGB space and
// over-brighten every lit surface whenever shadows are on.
// The shadow floor is sun-only too: omni lights reach every mesh whose AABB
// they touch, even out of range, so a floor there would light whole merged
// parts once per nearby light.
void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		float level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : shadow_level);
		DIFFUSE_LIGHT += level * LIGHT_COLOR / PI + ambient_light;
	} else {
		float level = ndl > band_high ? 1.0 : (ndl > band_low ? mid_level : 0.0);
		DIFFUSE_LIGHT += level * LIGHT_COLOR / PI;
	}
}
