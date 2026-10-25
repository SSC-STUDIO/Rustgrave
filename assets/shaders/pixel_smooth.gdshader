shader_type canvas_item;
render_mode unshaded;

// Pixel-art expansion for the 640x360 world image, evaluated per output pixel.
// Scale3x (AdvMAME3x) when the content rect is exactly 3x (1080p), Scale2x/EPX
// otherwise (2x, 4x = 2x then nearest 2x, ...). Both only round diagonal
// stair-steps between contrasting texels; flat areas, gradients and 1px
// details pass through untouched, so the result still reads as pixel art
// instead of a blurred photo. `smoothing = false` is a plain nearest blit.

uniform bool smoothing = true;
uniform int scale_hint = 3;
// Lit gradients differ by a hair from texel to texel; treat those as equal so
// the rules only fire on real edges.
uniform float tolerance : hint_range(0.0, 0.5) = 0.08;

bool same(vec4 a, vec4 b) {
	return distance(a.rgb, b.rgb) < tolerance && abs(a.a - b.a) < tolerance;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 px = UV * size;
	vec2 ip = floor(px);
	vec2 f = px - ip;
	vec2 d = 1.0 / size;
	vec2 c = (ip + 0.5) * d;
	vec4 tE = texture(TEXTURE, c);
	vec4 o = tE;
	if (smoothing && scale_hint > 1) {
		vec4 tB = texture(TEXTURE, c + vec2(0.0, -d.y)); // up
		vec4 tD = texture(TEXTURE, c + vec2(-d.x, 0.0)); // left
		vec4 tF = texture(TEXTURE, c + vec2(d.x, 0.0));  // right
		vec4 tH = texture(TEXTURE, c + vec2(0.0, d.y));  // down
		bool DB = same(tD, tB);
		bool BF = same(tB, tF);
		bool DH = same(tD, tH);
		bool HF = same(tH, tF);
		if (scale_hint == 3) {
			vec4 tA = texture(TEXTURE, c + vec2(-d.x, -d.y));
			vec4 tC = texture(TEXTURE, c + vec2(d.x, -d.y));
			vec4 tG = texture(TEXTURE, c + vec2(-d.x, d.y));
			vec4 tI = texture(TEXTURE, c + vec2(d.x, d.y));
			int cx = int(floor(f.x * 3.0));
			int cy = int(floor(f.y * 3.0));
			if (cy == 0) {
				if (cx == 0) {
					if (DB && !BF && !DH) { o = tD; }
				} else if (cx == 1) {
					if ((DB && !BF && !DH && !same(tE, tC)) || (BF && !DB && !HF && !same(tE, tA))) { o = tB; }
				} else {
					if (BF && !DB && !HF) { o = tF; }
				}
			} else if (cy == 1) {
				if (cx == 0) {
					if ((DB && !BF && !DH && !same(tE, tG)) || (DH && !DB && !HF && !same(tE, tA))) { o = tD; }
				} else if (cx == 2) {
					if ((BF && !DB && !HF && !same(tE, tI)) || (HF && !DH && !BF && !same(tE, tC))) { o = tF; }
				}
			} else {
				if (cx == 0) {
					if (DH && !DB && !HF) { o = tD; }
				} else if (cx == 1) {
					if ((DH && !DB && !HF && !same(tE, tI)) || (HF && !DH && !BF && !same(tE, tG))) { o = tH; }
				} else {
					if (HF && !DH && !BF) { o = tF; }
				}
			}
		} else {
			bool left = f.x < 0.5;
			bool top = f.y < 0.5;
			if (top && left) {
				if (DB && !DH && !BF) { o = tB; }
			} else if (top) {
				if (BF && !DB && !HF) { o = tF; }
			} else if (left) {
				if (DH && !HF && !DB) { o = tD; }
			} else {
				if (HF && !BF && !DH) { o = tH; }
			}
		}
	}
	COLOR = o;
}
