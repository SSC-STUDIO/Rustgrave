shader_type spatial;
render_mode unshaded, cull_back;

// Banded lava sampled on a coarse world grid so it reads as hand-placed pixels.

uniform vec4 cool : source_color = vec4(0.36, 0.07, 0.04, 1.0);
uniform vec4 mid : source_color = vec4(0.80, 0.26, 0.06, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.76, 0.29, 1.0);
uniform float texels_per_unit = 6.0;
uniform float speed = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = floor(world_pos.xz * texels_per_unit) / texels_per_unit;
	float t = TIME * speed;
	float w = sin(p.x * 1.3 + p.y * 0.7 + t * 2.0 + sin(p.y * 0.9 - t))
			+ sin(p.y * 1.9 - p.x * 0.4 - t * 1.4 + sin(p.x * 1.1 + t * 0.7));
	w = clamp(w * 0.25 + 0.5, 0.0, 1.0);
	float band = clamp(floor(w * 4.0), 0.0, 3.0) / 3.0;
	vec3 c = band < 0.5 ? mix(cool.rgb, mid.rgb, band * 2.0) : mix(mid.rgb, hot.rgb, band * 2.0 - 1.0);
	ALBEDO = c;
}
