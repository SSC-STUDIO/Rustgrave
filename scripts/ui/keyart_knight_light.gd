extends Control
## 标题 keyart 中央骑士的呼吸光影（纯表现，不碰存档/输入）：
## · 铁桥上的落影（像素椭圆，压暗）
## · 绕开骑士本体的阶梯暖色轮廓光（环带，不是糊在角色身上的色块）
## · 天井光柱里缓慢明灭的浮尘
## 坐标直接用 keyart 的 1280×720 设计坐标。

const CENTER := Vector2(616.0, 372.0)
const FEET := Vector2(618.0, 520.0)
const WARM := Color(1.0, 0.58, 0.22)
const DUST := Color(1.0, 0.72, 0.34)

var pulse := 0.5

var _time := 0.0


func _ready() -> void:
	name = "KnightLight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(1280.0, 720.0)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	pulse = 0.5 + 0.5 * sin(TAU * _time / 4.8)
	queue_redraw()


func _draw() -> void:
	_draw_back_haze()
	_draw_beam_rays()
	_draw_ground_shadow()
	_draw_rim_light()
	_draw_beam_dust()


## 落影：三层压暗椭圆，贴住铁桥面。
func _draw_ground_shadow() -> void:
	for i in 3:
		var radii := Vector2(54.0 - i * 12.0, 9.0 - i * 2.0)
		var alpha := 0.10 + 0.05 * float(i)
		_fill_ellipse(FEET + Vector2(0.0, float(i) * 1.0), radii,
				Color(0.0, 0.0, 0.0, alpha))


## 轮廓光：只画环带，骑士身体中间留空；呼吸时亮度轻微变化。
func _draw_rim_light() -> void:
	# 只留一道很淡的大轮廓，避免变成"轨道线"。
	var halo := (0.035 + 0.025 * pulse)
	_stroke_ellipse(CENTER + Vector2(4.0, -6.0), Vector2(164.0, 232.0), 2.0,
			Color(WARM.r, WARM.g, WARM.b, halo))
	# 剑尖/肩头几粒高光，随呼吸闪一下。
	var tip := CENTER + Vector2(52.0, -74.0)
	var blink := 0.18 + 0.22 * pulse
	draw_rect(Rect2(tip, Vector2(2.0, 2.0)), Color(WARM.r, WARM.g, WARM.b, blink))
	draw_rect(Rect2(tip + Vector2(-12.0, 10.0), Vector2(2.0, 2.0)),
			Color(WARM.r, WARM.g, WARM.b, blink * 0.6))
	draw_rect(Rect2(CENTER + Vector2(24.0, -20.0), Vector2(2.0, 2.0)),
			Color(WARM.r, WARM.g, WARM.b, blink * 0.5))


## 光柱浮尘：几粒缓慢上下漂的亮尘，不引入新粒子系统。
func _draw_beam_dust() -> void:
	for i in 6:
		var seed := float(i) * 1.7
		var x := CENTER.x - 58.0 + fmod(seed * 41.0, 116.0)
		var drift := fmod(_time * (4.0 + float(i % 3) * 2.0) + seed * 30.0, 220.0)
		var y := CENTER.y + 96.0 - drift
		var alpha := 0.16 + 0.16 * pulse * (0.5 + 0.5 * sin(_time * 1.7 + seed))
		draw_rect(Rect2(Vector2(roundf(x), roundf(y)), Vector2(2.0, 2.0)),
				Color(DUST.r, DUST.g, DUST.b, alpha))


## 骑士背后的暖雾：三层叠加的像素椭圆（阶梯状柔光），把身影从冷灰背景里托出来。
func _draw_back_haze() -> void:
	var breathe := 0.55 + 0.45 * pulse
	_fill_ellipse(CENTER + Vector2(4.0, -14.0), Vector2(168.0, 226.0),
			Color(WARM.r, WARM.g, WARM.b, 0.020 * breathe))
	_fill_ellipse(CENTER + Vector2(4.0, -12.0), Vector2(120.0, 176.0),
			Color(WARM.r, WARM.g, WARM.b, 0.024 * breathe))
	_fill_ellipse(CENTER + Vector2(2.0, -8.0), Vector2(76.0, 128.0),
			Color(WARM.r, WARM.g, WARM.b, 0.030 * breathe))


## 天井光柱的两缕边光：极淡的竖向亮带，随呼吸轻微起伏。
func _draw_beam_rays() -> void:
	var flick := 0.55 + 0.45 * pulse
	for i in 2:
		var x := CENTER.x - 92.0 + float(i) * 184.0
		var w := 20.0 - float(i) * 6.0
		var col := Color(WARM.r, WARM.g, WARM.b, 0.035 * flick)
		var y := 176.0
		while y < 470.0:
			var t := (y - 176.0) / 294.0
			draw_rect(Rect2(Vector2(roundf(x + t * 10.0), y), Vector2(w, 4.0)),
					Color(col.r, col.g, col.b, col.a * (0.5 + 0.5 * t)))
			y += 6.0


func _fill_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var y := -radii.y
	while y <= radii.y:
		var t := y / radii.y
		var half := radii.x * sqrt(maxf(0.0, 1.0 - t * t))
		if half >= 1.0:
			draw_rect(Rect2(Vector2(center.x - roundf(half), center.y + roundf(y)),
					Vector2(roundf(half) * 2.0, 2.0)), color)
		y += 2.0


func _stroke_ellipse(center: Vector2, radii: Vector2, thickness: float,
		color: Color) -> void:
	var y := -radii.y
	while y <= radii.y:
		var t := y / radii.y
		var half := radii.x * sqrt(maxf(0.0, 1.0 - t * t))
		if half >= 1.0:
			var yy := center.y + roundf(y)
			draw_rect(Rect2(Vector2(center.x - roundf(half), yy),
					Vector2(thickness, 2.0)), color)
			draw_rect(Rect2(Vector2(center.x + roundf(half) - thickness, yy),
					Vector2(thickness, 2.0)), color)
		y += 2.0
