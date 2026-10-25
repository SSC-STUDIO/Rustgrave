shader_type canvas_item;

// 熔河的流动层：把无缝的流纹贴图（river_current.png，与 pit_river 同画布）沿 x
// 缓慢卷动。调用方只喂整像素位移，最近邻采样下不会出灰边。加色、不受点光。

render_mode blend_add;

uniform float scroll_px = 0.0;

void fragment() {
	vec2 uv = UV;
	uv.x = fract(uv.x + scroll_px * TEXTURE_PIXEL_SIZE.x);
	COLOR = texture(TEXTURE, uv);
}
