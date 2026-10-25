extends Node2D
## 厅尾的一层空气：横着的薄雾、一道更远的尘光，和几扇会自己明灭的远窗。
##
## 和 HallFar 不在同一个视差深度上，鼠标一动就能看出墙后面还有一层。
## 一个节点、自己画、整像素，不加灯（灯光预算已经满了）。

const WINDOWS: Array[Vector2] = [
	Vector2(36.0, 72.0), Vector2(58.0, 96.0), Vector2(118.0, 64.0),
	Vector2(168.0, 88.0), Vector2(508.0, 70.0), Vector2(548.0, 98.0),
	Vector2(586.0, 76.0),
]
const BAND_Y: Array[float] = [40.0, 74.0, 112.0]

var _t := 0.0
var _step := -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_t += delta
	var step := int(_t * 6.0)
	if step == _step:
		return
	_step = step
	queue_redraw()


func _draw() -> void:
	for i in BAND_Y.size():
		var y := BAND_Y[i]
		var alpha := 0.05 + 0.018 * float(i)
		draw_rect(Rect2(-64.0, y, 780.0, 8.0 + 4.0 * float(i)), Color(0.55, 0.48, 0.58, alpha))
	# 主光柱左边再漏一道更淡的尘光，远一点，所以更窄更冷。
	draw_rect(Rect2(186.0, 6.0, 22.0, 156.0), Color(0.75, 0.68, 0.58, 0.035))
	draw_rect(Rect2(194.0, 6.0, 6.0, 156.0), Color(0.95, 0.86, 0.7, 0.05))
	for i in WINDOWS.size():
		var n := sin(float(_step) * 0.85 + float(i) * 1.7)
		if n < -0.2:
			continue
		var hot := 0.35 + 0.45 * clampf(n, 0.0, 1.0)
		var p := WINDOWS[i]
		draw_rect(Rect2(p, Vector2(3.0, 4.0)), Color(1.0, 0.48, 0.18, hot * 0.4))
		draw_rect(Rect2(p + Vector2(1.0, 1.0), Vector2(1.0, 2.0)), Color(1.0, 0.92, 0.7, hot))
