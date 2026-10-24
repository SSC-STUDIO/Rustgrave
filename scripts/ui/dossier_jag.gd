extends Control
## 右栏左缘的"参差不齐"装饰：两块从板身伸出的箭头状铁舌，模仿左侧菜单板的
## 箭头/燕尾轮廓；纯代码 2px 像素绘制，颜色取自 MenuPlate 同一套调色板。
## 只画在板身之外（x < BODY_LEFT），内容区不会压到。

const OUTLINE := Color("#120E14")
const RIM := Color("#8B4513")
const RIM_DARK := Color("#4A2A18")
const FILL := Color("#1E1830")
const DITHER := Color("#14101F")
const RIVET := Color("#FFC14A")

## 板身左缘在 wrap 内的 x：贴图位置 24 + 箭头宽 44。
const BODY_LEFT := 68.0

## [顶部 y, 底部 y, 最远伸出 px]；板高 402，两块铁舌分居上三分之一与下三分之一。
const TABS := [
	[82.0, 140.0, 38.0],
	[300.0, 358.0, 26.0],
]


var _time := 0.0


func _ready() -> void:
	name = "DossierJag"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(408.0, 344.0)
	set_process(true)


func _process(delta: float) -> void:
	# 只让尖端余烬铆钉呼吸，不整块重绘板身。
	_time += delta
	queue_redraw()


func _draw() -> void:
	for tab in TABS:
		_draw_tab(float(tab[0]), float(tab[1]), float(tab[2]))


func _draw_tab(top: float, bottom: float, reach: float) -> void:
	var mid := (top + bottom) * 0.5
	var half := (bottom - top) * 0.5
	var y := top
	while y < bottom:
		var t := 1.0 - absf((y + 1.0 - mid) / half)
		var ext := floorf(maxf(0.0, reach * t) / 2.0) * 2.0
		var x0 := BODY_LEFT - ext
		if ext >= 2.0:
			# 外侧黑边 + 锈边，往里是暗底 + 抖动内芯。
			draw_rect(Rect2(x0, y, 2.0, 2.0), OUTLINE)
			draw_rect(Rect2(x0 + 2.0, y, 2.0, 2.0), RIM_DARK)
			var fill_w := BODY_LEFT - x0 - 4.0
			if fill_w > 0.0:
				draw_rect(Rect2(x0 + 4.0, y, fill_w + 2.0, 2.0), FILL)
				var dot_x := x0 + 4.0 + fmod(y, 8.0)
				while dot_x < BODY_LEFT:
					draw_rect(Rect2(dot_x, y, 2.0, 2.0), DITHER)
					dot_x += 8.0
		y += 2.0
	# 舌根上下各压一道横边，和板身接缝对齐；尖端一颗余烬铆钉。
	draw_rect(Rect2(BODY_LEFT - reach, top - 2.0, reach, 2.0), OUTLINE)
	draw_rect(Rect2(BODY_LEFT - reach, bottom, reach, 2.0), OUTLINE)
	var breathe := 0.55 + 0.45 * sin(TAU * (_time / 3.6) + top)
	draw_rect(Rect2(BODY_LEFT - reach + 2.0, mid - 3.0, 4.0, 6.0), RIM)
	draw_rect(Rect2(BODY_LEFT - reach + 4.0, mid - 1.0, 2.0, 2.0),
			Color(RIVET.r, RIVET.g, RIVET.b, breathe))
