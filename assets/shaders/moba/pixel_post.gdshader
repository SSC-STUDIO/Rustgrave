shader_type canvas_item;
render_mode unshaded;

// Final pass on the low-resolution 3D image. The arena renders one render pixel
// per output texel; the title screen supersamples the 3D pass (render_scale 2-3)
// and this pass box-filters it back down, so lighting gradients stay smooth while
// the final image still lands on a chunky texel grid. Optional ordered dither,
// nearest-colour palette lock, vignette, grain and heat haze all work in OUTPUT
// texels; texel_origin is the camera's texel position (mod 4) so the dither
// pattern stays fixed to the world while the camera moves. Every title-only
// uniform defaults to neutral, so the arena output is unchanged.

uniform bool palette_on = false;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D palette_tex : filter_nearest;
uniform int palette_size = 1;
// Render pixels of the whole target, margins included.
uniform vec2 source_size = vec2(644.0, 364.0);
// Output texels of the whole target, margins included.
uniform vec2 output_size = vec2(644.0, 364.0);
// Render pixels per output texel: 1 = arena, 2-3 = supersampled title screen.
uniform int render_scale = 1;
uniform vec2 texel_origin = vec2(0.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
// Heat haze around a projected point (UV). Neutral at strength 0.
uniform vec2 haze_center = vec2(0.5);
uniform float haze_radius = 0.0;
uniform float haze_strength = 0.0;
uniform float haze_time = 0.0;

float bayer2(vec2 a) {
	a = floor(a);
	return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Built-in TEXTURE cannot be passed to a helper function in Godot's shader
// compiler (custom samplers are only supported for uniforms), so the box filter
// is inlined in fragment().
void fragment() {
	vec2 uv = UV;
	vec2 out_size = output_size.x > 0.0 ? output_size : source_size;
	if (haze_strength > 0.0 && haze_radius > 0.0) {
		float d = distance(UV * source_size, haze_center * source_size);
		float m = 1.0 - smoothstep(0.0, haze_radius, d);
		if (m > 0.0) {
			vec2 wob = vec2(
				sin(UV.y * 90.0 + haze_time * 6.0) + 0.5 * sin(UV.y * 37.0 - haze_time * 2.3),
				cos(UV.x * 70.0 + haze_time * 4.7)
			) * haze_strength * 0.004 * m;
			uv += wob;
		}
	}
	vec3 c;
	if (render_scale <= 1) {
		c = texture(TEXTURE, uv).rgb;
	} else {
		vec2 texel = 1.0 / source_size;
		vec2 base = uv - 0.5 * texel * float(render_scale);
		vec3 sum = vec3(0.0);
		float inv = 1.0 / float(render_scale * render_scale);
		for (int y = 0; y < 3; y++) {
			if (y >= render_scale) {
				break;
			}
			for (int x = 0; x < 3; x++) {
				if (x >= render_scale) {
					break;
				}
				vec2 off = (vec2(float(x), float(y)) + 0.5) * texel;
				sum += texture(TEXTURE, base + off).rgb;
			}
		}
		c = sum * inv;
	}
	if (dither_strength > 0.0) {
		vec2 tc = floor(UV * out_size) + texel_origin;
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
	if (vignette_strength > 0.0) {
		vec2 q = UV - 0.5;
		float v = smoothstep(0.15, 0.75, length(q) * 1.35);
		c *= 1.0 - vignette_strength * v;
	}
	if (grain_strength > 0.0) {
		float g = hash12(floor(UV * out_size) + vec2(haze_time * 13.0, haze_time * 7.0)) - 0.5;
		c += g * grain_strength * 0.10;
	}
	c *= tint.rgb;
	COLOR = vec4(c, 1.0);
}
