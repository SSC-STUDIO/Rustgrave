extends Control
## Chapter cards and boss name plates. Fixed 640x360 composition.
## The opening itself is the real cemetery, not a drawn slide.

const FONT := preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
const INK := Color("100e18")
const RUST := Color("975336")
const EMBER := Color("ffc174")

var shot := ""
var age := 0.0
var heading := ""
var subheading := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if shot != "chapter" and shot != "boss":
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(640, 360))
	_card()


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
	draw_rect(Rect2(0, 0, 640, 360), Color(0.035, 0.02, 0.04, 0.08 if boss else 0.52))
	# The boss flourish occupies the sky beside the health HUD. Combat remains
	# live: feet, ground hazards and attack telegraphs must stay visible.
	var y := 78.0 if boss else 142.0
	var center_x := 410.0 if boss else 320.0
	draw_rect(Rect2(200 if boss else 0, y - 29, 420 if boss else 640, 79), Color(0.04, 0.025, 0.05, 0.88))
	var extent := (155.0 if boss else 190.0) * smoothstep(0.0, 0.65, age)
	draw_line(Vector2(center_x - extent, y - 29), Vector2(center_x + extent, y - 29), RUST)
	draw_line(Vector2(center_x - extent, y + 50), Vector2(center_x + extent, y + 50), RUST)
	_center_text(subheading, y - 10, 10, Color("c89372"), center_x)
	_center_text(heading, y + 21, 22, Color("f5dfbd"), center_x)
	for side in [-1, 1]:
		var p := Vector2(center_x + side * (extent + 9), y + 10)
		draw_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)]), PackedColorArray([EMBER]))
	if boss:
		_motes(false)


func _text(value: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string(FONT, pos + Vector2(1, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	draw_string(FONT, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center_text(value: String, y: float, font_size: int, color: Color, center_x: float = 320.0) -> void:
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2(center_x - width * 0.5, y), font_size, color)
