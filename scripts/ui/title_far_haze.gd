extends Sprite2D
## Ash bands and a few furnace windows drawn on top of HallFar.
## Kept on the existing sprite so the far hall gains a depth layer without
## spending another node — the title world is counted against a hard budget.

const BAND_Y: Array[float] = [72.0, 128.0, 196.0]
const BAND_H: Array[float] = [14.0, 8.0, 18.0]
const WINDOWS: Array[Vector2] = [
	Vector2(148, 92), Vector2(236, 74), Vector2(508, 86), Vector2(572, 108),
]

var forge_heat := 0.4
var _t := 0.0


func set_look(new_heat: float, _lift: Color) -> void:
	forge_heat = new_heat


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var heat := clampf(forge_heat, 0.0, 1.3)
	var cool := 1.0 - clampf(heat, 0.0, 1.0)
	var fog := 0.07 + 0.07 * cool
	var scroll := int(_t * 7.0) % 28
	var width := texture.get_width() if texture != null else 704
	for i in BAND_Y.size():
		var x := -scroll
		var y := BAND_Y[i]
		var h := BAND_H[i]
		var a := fog * (1.0 if i != 1 else 0.65)
		while x < width:
			draw_rect(Rect2(x, y, 16.0, h), Color(0.58, 0.66, 0.76, a))
			x += 28
	for i in WINDOWS.size():
		var flick := 0.7 + 0.3 * sin(_t * (2.2 + float(i) * 0.41) + float(i) * 1.7)
		var on := clampf(0.12 + heat * 0.8, 0.0, 1.0) * flick
		var p := WINDOWS[i]
		draw_rect(Rect2(p, Vector2(4, 3)), Color(0.42, 0.10, 0.04, on * 0.85))
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(2, 1)), Color(1.0, 0.78, 0.42, on))
