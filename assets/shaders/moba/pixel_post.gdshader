shader_type canvas_item;
render_mode unshaded;

// Final pass on the low-resolution 3D image: optional ordered dither and
// nearest-colour palette lock. Both work in source texels; texel_origin is the
// camera's texel position (mod 4) so the dither pattern stays fixed to the
// world while the camera scrolls.

uniform bool palette_on = false;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D palette_tex : filter_nearest;
uniform int palette_size = 1;
uniform vec2 source_size = vec2(644.0, 364.0);
uniform vec2 texel_origin = vec2(0.0);

float bayer2(vec2 a) {
	a = floor(a);
	return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	if (dither_strength > 0.0) {
		vec2 tc = floor(UV * source_size) + texel_origin;
		c += (bayer4(tc) - 0.5) * dither_strength * 0.12;
	}
	if (palette_on) {
		vec3 best = c;
		float best_d = 1e9;
		for (int i = 0; i < 64; i++) {
			if (i >= palette_size) {
				break;
			}
			vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
			vec3 d = c - p;
			float dist = dot(d * d, vec3(0.30, 0.59, 0.11));
			if (dist < best_d) {
				best_d = dist;
				best = p;
			}
		}
		c = best;
	}
	COLOR = vec4(c, 1.0);
}
