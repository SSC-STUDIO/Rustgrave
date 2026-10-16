extends Control
## Three hand-drawn pixel tableaux. Fixed 640x360 composition, no random nodes,
## shaders, downloaded art, or gameplay state. Animated by the presentation clock.

const SKY := preload("res://assets/env/parallax_sky_px.png")
const MOUNTAINS := preload("res://assets/env/parallax_far_mountains_px.png")
const GRAVES := preload("res://assets/env/parallax_graveyard_px.png")
const KNIGHT := preload("res://assets/characters/player_fantasy_knight/idle/idle_0.png")
const FONT := preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
const INK := Color("100e18")
const IRON := Color("39303c")
const RUST := Color("975336")
const EMBER := Color("ffc174")

var shot := "relic"
var age := 0.0
var heading := ""
var subheading := ""
var number := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(640, 360))
	if shot == "chapter" or shot == "boss":
		_card()
		return
	draw_rect(Rect2(0, 0, 640, 360), INK)
	match shot:
		"relic": _relic()
		"grave": _grave()
		"furnace": _furnace()
	_motes(shot == "grave")
	# Soft stepped vignette and perforated iron frame, all on the pixel grid.
	for i in 6:
		var alpha := 0.035 + float(i) * 0.012
		draw_rect(Rect2(i * 4, 18, 4, 310), Color(0, 0, 0, alpha))
		draw_rect(Rect2(636 - i * 4, 18, 4, 310), Color(0, 0, 0, alpha))
	draw_rect(Rect2(0, 0, 640, 29), INK)
	draw_rect(Rect2(0, 319, 640, 41), INK)
	draw_line(Vector2(32, 30), Vector2(608, 30), Color("66413c"))
	_text("R U S T G R A V E   /   记 忆 残 片", Vector2(36, 26), 10, Color("9e8278"))
	_text("0%d" % (number + 1), Vector2(576, 26), 10, EMBER)
	for i in 3:
		draw_rect(Rect2(36 + i * 22, 309, 16, 2), EMBER if i == number else IRON)
	_text(heading, Vector2(38, 75), 22, Color("eee0c9"))
	_text(subheading, Vector2(40, 94), 10, Color("b09083"))


func _relic() -> void:
	# Ruined kiln skyline, with a very slow push across three depths.
	for layer_index in 3:
		var tint := Color("211c2a").lerp(INK, float(layer_index) * 0.25)
		for i in 18:
			var x := float(i * 42 - 36) - fmod(age * (layer_index + 1) * 0.8, 42.0)
			var h := float(36 + (i * 29 + layer_index * 19) % 95)
			var bottom := 228.0 + layer_index * 28
			draw_rect(Rect2(x, bottom - h, 29, h), tint)
			draw_polygon(PackedVector2Array([Vector2(x - 3, bottom - h), Vector2(x + 14, bottom - h - 23), Vector2(x + 32, bottom - h)]), PackedColorArray([tint]))
			if layer_index == 0:
				draw_rect(Rect2(x + 12, bottom - h + 18, 3, 10), Color("664337"))
	for i in 36:
		var x := float(i * 21 - 32)
		var y := 277.0 + sin(i * 3.1) * 12.0
		draw_polygon(PackedVector2Array([Vector2(x, 320), Vector2(x + 5, y), Vector2(x + 26, y - 7), Vector2(x + 35, 320)]), PackedColorArray([Color("24202a")]))
	# Oversized rusted blade; its three sockets will carry the voices below.
	# The origin also needs the canvas scale when drawing into the native UI.
	draw_set_transform(Vector2(388, 205) * size / Vector2(640, 360), -0.48, size / Vector2(640, 360))
	draw_polygon(PackedVector2Array([Vector2(-20, -99), Vector2(0, -130), Vector2(20, -99), Vector2(17, 72), Vector2(-17, 72)]), PackedColorArray([Color("553c3d")]))
	draw_polygon(PackedVector2Array([Vector2(-13, -96), Vector2(0, -119), Vector2(0, 68), Vector2(-13, 68)]), PackedColorArray([Color("8b6356")]))
	for i in 23:
		var x := float((i * 7) % 26 - 13)
		var y := float((i * 37) % 165 - 95)
		draw_rect(Rect2(x, y, 3 + i % 3, 2), RUST if i % 3 == 0 else IRON)
	for i in 3:
		var p := Vector2(0, -60 + i * 42)
		draw_rect(Rect2(p - Vector2(9, 10), Vector2(18, 20)), INK)
		draw_rect(Rect2(p - Vector2(6, 7), Vector2(12, 14)), RUST)
		draw_rect(Rect2(p - Vector2(2, 4), Vector2(4, 8)), Color("f09250").lerp(EMBER, (sin(age * 1.8 + i) + 1) * 0.5))
	draw_rect(Rect2(-35, 59, 70, 10), IRON)
	draw_rect(Rect2(-5, 69, 10, 34), RUST)
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(640, 360))
	# Foreground diagonal chains.
	for i in 20:
		draw_rect(Rect2(455 + i * 11, 245 - i * 6, 10, 5), Color("19151f"), false, 2)


func _grave() -> void:
	var drift := minf(age, 12.0)
	draw_texture_rect(SKY, Rect2(-10 - drift * 0.3, 25, 680, 310), false, Color("b2a8bb"))
	draw_texture_rect(MOUNTAINS, Rect2(-18 - drift * 0.8, 85, 690, 250), false, Color("76647c"))
	draw_texture_rect(GRAVES, Rect2(-30 - drift * 1.8, 82, 720, 255), false, Color("807482"))
	draw_rect(Rect2(0, 279, 640, 45), Color("17141e"))
	for i in 8:
		var x := float(i * 96 - 36)
		var y := float(260 + i % 3 * 8)
		draw_rect(Rect2(x, y - 33, 7, 60), Color("29232e"))
		draw_rect(Rect2(x - 10, y - 24, 28, 6), Color("29232e"))
	# Texture stays at integer scale; a slow ember breath lights the wake.
	var knight_size := KNIGHT.get_size() * 3.0
	draw_texture_rect(KNIGHT, Rect2(Vector2(370, 286) - knight_size * Vector2(0.5, 1.0), knight_size), false, Color("c6b4ac"))
	for i in range(5, 0, -1):
		draw_circle(Vector2(365, 275), i * 5, Color(1.0, 0.35, 0.12, 0.012 * (sin(age * 2) + 1.4)))
	for i in 5:
		var x := fmod(float(i * 151) + age * 5.0, 800.0) - 100.0
		draw_ellipse_band(Vector2(x, 252.0 + i * 9), 160.0, Color(0.45, 0.39, 0.48, 0.06))


func draw_ellipse_band(p: Vector2, width: float, color: Color) -> void:
	for j in 4:
		draw_rect(Rect2(p + Vector2(j * 8, j * 2), Vector2(width - j * 16, 2)), color)


func _furnace() -> void:
	var center := Vector2(376, 189)
	for i in range(10, 0, -1):
		draw_circle(center, 18 + i * 12, Color(0.64, 0.22, 0.12, 0.026))
	for i in 12:
		var a := float(i) * TAU / 12.0 + age * 0.017
		var p := center + Vector2.from_angle(a) * 88
		draw_arc(center, 88, a, a + 0.36, 7, Color("704837"), 7)
		draw_line(p, center + Vector2.from_angle(a) * 105, IRON, 5)
	draw_arc(center, 65, -age * 0.035, TAU - age * 0.035, 48, RUST, 2)
	for i in 7:
		var a := float(i) * TAU / 7.0 - age * 0.025
		draw_line(center + Vector2.from_angle(a) * 37, center + Vector2.from_angle(a) * 60, Color("bc7950"), 4)
	var pulse := (sin(age * 2.0) + 1.0) * 0.5
	draw_circle(center, 24 + pulse * 2, Color("9c432d"))
	draw_circle(center, 15, Color("f39a55"))
	draw_circle(center, 7, EMBER)
	for i in 3:
		draw_rect(Rect2(373 - i * 3, 216, 6 + i * 6, 103), Color(1, 0.44, 0.19, 0.06))
	for side in [0, 1]:
		for i in 7:
			var x := float(i * 33) if side == 0 else float(640 - i * 33)
			var h := float(60 + (i * 43) % 90)
			draw_rect(Rect2(x - 20, 0, 29, h), Color("201a24"))
	draw_polygon(PackedVector2Array([Vector2(0, 320), Vector2(0, 280), Vector2(105, 276), Vector2(216, 301), Vector2(429, 301), Vector2(520, 278), Vector2(640, 272), Vector2(640, 320)]), PackedColorArray([INK]))


func _motes(falling: bool) -> void:
	for i in 52:
		var speed := 5.0 + float(i % 7) * 1.7
		var x := fposmod(float(i * 137) + age * (2 + i % 3), 660.0) - 10.0
		var y := fposmod(float(i * 79) + age * speed * (1 if falling else -1), 294.0) + 28.0
		var bright := (sin(age * 1.6 + i) + 1.0) * 0.5
		var tint := Color(0.8, 0.68, 0.62, 0.18 + bright * 0.25) if falling else Color(1.0, 0.53, 0.24, 0.15 + bright * 0.55)
		draw_rect(Rect2(Vector2(x, y).floor(), Vector2(2, 2) if i % 9 == 0 else Vector2.ONE), tint)


func _card() -> void:
	var boss := shot == "boss"
	draw_rect(Rect2(0, 0, 640, 360), Color(0.035, 0.02, 0.04, 0.24 if boss else 0.52))
	var y := 220.0 if boss else 142.0
	draw_rect(Rect2(0, y - 29, 640, 79), Color(0.04, 0.025, 0.05, 0.88))
	var extent := 190.0 * smoothstep(0.0, 0.65, age)
	draw_line(Vector2(320 - extent, y - 29), Vector2(320 + extent, y - 29), RUST)
	draw_line(Vector2(320 - extent, y + 50), Vector2(320 + extent, y + 50), RUST)
	_center_text(subheading, y - 10, 10, Color("c89372"))
	_center_text(heading, y + 21, 22, Color("f5dfbd"))
	for side in [-1, 1]:
		var p := Vector2(320 + side * (extent + 9), y + 10)
		draw_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)]), PackedColorArray([EMBER]))
	if boss:
		_motes(false)


func _text(value: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string(FONT, pos + Vector2(1, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	draw_string(FONT, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center_text(value: String, y: float, font_size: int, color: Color) -> void:
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2((640 - width) * 0.5, y), font_size, color)
