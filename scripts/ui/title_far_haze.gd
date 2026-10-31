extends Node2D
## 厅尾的一层空气：横着的薄雾、熔河向上的暖反光、一道更远的尘光，和几扇会自己明灭的远窗。
##
## 和 HallFar 不在同一个视差深度上，鼠标一动就能看出墙后面还有一层。
## 自下而上的暖反光将熔河的火光往上送至远厅中段（y=180），平滑连接冷色远景与暖色前景。
## 一个节点、自己画、整像素，不加灯（灯光预算已经满了）。

const WINDOWS: Array[Vector2] = [
	Vector2(36.0, 72.0), Vector2(58.0, 96.0), Vector2(118.0, 64.0),
	Vector2(168.0, 88.0), Vector2(508.0, 70.0), Vector2(548.0, 98.0),
	Vector2(586.0, 76.0),
]

# 暖反光几何参数
const BOUNCE_TOP_Y := 180.0
const BOUNCE_BOTTOM_Y := 340.0
const BOUNCE_X := -96.0
const BOUNCE_W := 832.0
const BOUNCE_BANDS := 8

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
	_draw_warm_bounce()

	# 两条雾带对着飘，整像素，所以墙后面是在动的空气而不是一块平涂。
	var drift_a := roundf(sin(_t * 0.17) * 28.0)
	var drift_b := roundf(sin(_t * 0.11 + 1.4) * -18.0)
	draw_rect(Rect2(-96.0 + drift_a, 46.0, 860.0, 10.0), Color(0.55, 0.48, 0.58, 0.05))
	draw_rect(Rect2(-80.0 + drift_b, 78.0, 820.0, 16.0), Color(0.48, 0.42, 0.52, 0.07))
	draw_rect(Rect2(-64.0, 114.0, 780.0, 8.0), Color(0.42, 0.38, 0.46, 0.04))
	# 主光柱左边再漏一道更淡的尘光，远一点，所以更窄更冷。
	var shaft := 0.7 + 0.3 * sin(_t * 0.23)
	draw_rect(Rect2(186.0, 6.0, 22.0, 156.0), Color(0.75, 0.68, 0.58, 0.03 * shaft))
	draw_rect(Rect2(194.0, 6.0, 6.0, 156.0), Color(0.95, 0.86, 0.7, 0.055 * shaft))
	for i in WINDOWS.size():
		var n := sin(float(_step) * 0.85 + float(i) * 1.7)
		if n < -0.2:
			continue
		var hot := 0.35 + 0.45 * clampf(n, 0.0, 1.0)
		var p := WINDOWS[i]
		draw_rect(Rect2(p, Vector2(3.0, 4.0)), Color(1.0, 0.48, 0.18, hot * 0.4))
		draw_rect(Rect2(p + Vector2(1.0, 1.0), Vector2(1.0, 2.0)), Color(1.0, 0.92, 0.7, hot))


func _draw_warm_bounce() -> void:
	# 熔河自下而上的暖反光：从熔河面（y=340）向上爬升，到远厅中段（y=180）渐隐消失
	# 模拟熔岩对流呼吸（6fps 步进），将冷色远景与近处熔河平滑衔接
	var pulse := 0.88 + 0.12 * sin(_t * 1.4) + 0.05 * sin(_t * 2.9 + 0.7)
	var band_h := (BOUNCE_BOTTOM_Y - BOUNCE_TOP_Y) / float(BOUNCE_BANDS) # 20px 每段（2px 整数对齐）

	for i in BOUNCE_BANDS:
		# 从下往上计算：i=0 为底部 (y=320..340)，i=7 为顶部 (y=180..200)
		var y_top := BOUNCE_BOTTOM_Y - float(i + 1) * band_h
		var u := (float(i) + 0.5) / float(BOUNCE_BANDS) # 归一化高度 0.0 (底) -> 1.0 (顶)
		var falloff := (1.0 - u) * (1.0 - u) # 二次衰减

		# 底部浓郁熔岩橙 -> 中段暖赭色 -> 顶端淡紫灰渐隐
		var col: Color
		if u < 0.5:
			col = Color(0.96, 0.40, 0.12).lerp(Color(0.82, 0.38, 0.18), u * 2.0)
		else:
			col = Color(0.82, 0.38, 0.18).lerp(Color(0.50, 0.35, 0.42), (u - 0.5) * 2.0)
		col.a = 0.15 * falloff * pulse
		draw_rect(Rect2(BOUNCE_X, y_top, BOUNCE_W, band_h), col)

	# 底层熔岩近处轻微漂移的对流热气带
	var convection_drift := roundf(sin(_t * 0.22) * 16.0)
	draw_rect(Rect2(-80.0 + convection_drift, 304.0, 800.0, 12.0), Color(1.0, 0.45, 0.14, 0.035 * pulse))
