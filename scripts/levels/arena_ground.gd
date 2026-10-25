extends Node2D
## 透视地面带。脚底纵深 252–328 对齐砖面：远行细、暗、冷，近行高、亮、暖。
## 竖缝朝车道中线收敛。后缘矮墙，前缘厚边。像素坐标取整。
## 砖面整体压暗，左半偏冷灰蓝、右半偏暖炉红，把单位衬托出来。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var _y0: Array[int] = []
var _y1: Array[int] = []


func _ready() -> void:
	name = "DepthGround"
	z_index = -8
	var weights: Array[float] = []
	var sum := 0.0
	for i in 8:
		var w := 0.22 + pow(float(i + 1) / 8.0, 2.05)
		weights.append(w)
		sum += w
	var y := int(ArenaCatalog.DEPTH_BACK)
	var front := int(ArenaCatalog.DEPTH_FRONT)
	for i in 8:
		var h := maxi(3, int(round(float(front - int(ArenaCatalog.DEPTH_BACK)) * weights[i] / sum)))
		if i == 7:
			h = front - y
		if h < 3:
			h = 3
		_y0.append(y)
		_y1.append(y + h)
		y += h


func _draw() -> void:
	var span := int(ArenaCatalog.LANE_LENGTH)
	var back := int(ArenaCatalog.DEPTH_BACK)
	var front := int(ArenaCatalog.DEPTH_FRONT)
	draw_rect(Rect2(0, back - 28, span, front - back + 56), Color(0.04, 0.03, 0.028))
	_wall(span, back)
	for i in _y0.size():
		_row(i, span)
	_scorch()
	_grates(span)
	_inlay(span)
	_lane_glow(span)
	_guides(span)
	_sigil()
	_lip(span, front)


func _wall(span: int, back: int) -> void:
	var top := back - 26
	var y := top
	while y < back:
		var t := float(y - top) / 26.0
		draw_rect(Rect2(0, y, span, 1), _stone(float(span) * 0.5, 0.07 + t * 0.1, 0.0))
		y += 1
	# 墙面砖缝，两道。
	draw_rect(Rect2(0, top + 8, span, 1), Color(0.03, 0.024, 0.026, 0.9))
	draw_rect(Rect2(0, top + 17, span, 1), Color(0.03, 0.024, 0.026, 0.9))
	var x := 0
	while x < span:
		var merlon := 22
		var gap := 14
		draw_rect(Rect2(x, top - 8, merlon, 8), _stone(float(x), 0.14, 0.03))
		draw_rect(Rect2(x, top - 8, merlon, 1), _stone(float(x), 0.3, 0.08))
		x += merlon + gap
	# 墙沿一道暖光，把它从熔河前分出来。
	var wx := 0
	while wx < span:
		var side := float(wx) / float(span)
		draw_rect(Rect2(wx, back - 1, 8, 2), Color(lerpf(0.4, 0.95, side), lerpf(0.42, 0.5, side), lerpf(0.5, 0.3, side), 0.5))
		wx += 8


func _row(index: int, span: int) -> void:
	var y0 := _y0[index]
	var y1 := _y1[index]
	var t := 0.0
	if _y0.size() > 1:
		t = float(index) / float(_y0.size() - 1)
	var brick := int(round(lerpf(14.0, 30.0, t)))
	if brick % 2 != 0:
		brick += 1
	var x := 0
	if index % 2 == 1:
		x = -brick / 2
	while x < span:
		var x2 := x + brick
		var top_a := _seam(float(x), float(y0))
		var top_b := _seam(float(x2), float(y0))
		var bot_a := _seam(float(x), float(y1))
		var bot_b := _seam(float(x2), float(y1))
		var alt := 0.0
		if (int(x / brick) + index) % 2 == 0:
			alt = 0.028
		var mid_x := float(x) + float(brick) * 0.5
		var fill := _stone(mid_x, lerpf(0.075, 0.3, t), alt + t * 0.05)
		draw_colored_polygon(PackedVector2Array([
			Vector2(round(top_a), y0),
			Vector2(round(top_b), y0),
			Vector2(round(bot_b), y1 - 1),
			Vector2(round(bot_a), y1 - 1),
		]), fill)
		draw_line(Vector2(round(top_b), y0), Vector2(round(bot_b), y1), Color(0.03, 0.024, 0.024, 0.9), 1.0)
		x = x2


## 塔基与祭台前的灼痕：两轮同心暗斑，假装被火常年烤过。
func _scorch() -> void:
	var spots := [900.0, 1280.0, 2560.0, 2940.0, 1920.0]
	for sx in spots:
		var cy := 300.0
		if sx == 1920.0:
			cy = 312.0
		draw_circle(Vector2(sx, cy), 30.0, Color(0.02, 0.015, 0.015, 0.32))
		draw_circle(Vector2(sx, cy), 18.0, Color(0.01, 0.008, 0.008, 0.38))


## 排水格栅：兵线之间的暗栅格，前后错位排列。
func _grates(span: int) -> void:
	var x := 256
	var row := 0
	while x < span - 64:
		var y := 276 if row % 2 == 0 else 306
		var gx := _seam(float(x), float(y))
		draw_rect(Rect2(round(gx) - 13, y, 26, 6), Color(0.03, 0.024, 0.024, 0.9))
		var slat := 0
		while slat < 4:
			draw_rect(Rect2(round(gx) - 10 + slat * 6, y + 1, 2, 4), Color(0.09, 0.08, 0.08))
			slat += 1
		x += 384
		row += 1


## 阵营镶嵌条：后缘外侧，左蓝右红的断续亮条。
func _inlay(span: int) -> void:
	var x := 32
	while x < span - 32:
		var side := float(x) / float(span)
		var col := Color(lerpf(0.3, 0.9, side), lerpf(0.5, 0.35, side), lerpf(1.0, 0.15, side), 0.3)
		var y := 255
		var x0 := _seam(float(x), float(y))
		var x1 := _seam(float(x + 44), float(y))
		draw_line(Vector2(round(x0), y), Vector2(round(x1), y), col, 2.0)
		x += 96


## 三条兵线下的柔光衬底，让引导纹在暗砖上也读得出来。
func _lane_glow(span: int) -> void:
	var lanes: Array[float] = [262.0, 290.0, 318.0]
	for lane_y in lanes:
		var y := int(lane_y)
		var bright := absf(lane_y - 290.0) < 1.0
		var col := Color(0.85, 0.6, 0.3, 0.07)
		if bright:
			col = Color(0.95, 0.68, 0.32, 0.11)
		var x := 0
		while x < span:
			var x0 := _seam(float(x), float(y))
			var x1 := _seam(float(x + 8), float(y))
			draw_line(Vector2(round(x0), y + 1), Vector2(round(x1), y + 1), col, 3.0)
			x += 8


func _guides(span: int) -> void:
	var lanes: Array[float] = [262.0, 290.0, 318.0]
	for lane_y in lanes:
		var y := int(lane_y)
		var bright := absf(lane_y - 290.0) < 1.0
		var x := 8
		while x < span - 8:
			var dash := 10
			if bright:
				dash = 14
			var x0 := _seam(float(x), float(y))
			var x1 := _seam(float(x + dash), float(y))
			var col := Color(0.6, 0.5, 0.4, 0.4)
			if bright:
				col = Color(1.0, 0.72, 0.35, 0.6)
			draw_line(Vector2(round(x0), y), Vector2(round(x1), y), col, 1.0)
			x += dash + 8
	var mark := 96
	var cx := mark
	while cx < span:
		var tip := _seam(float(cx), 290.0)
		var left := _seam(float(cx - 5), 294.0)
		var right := _seam(float(cx + 5), 294.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(round(tip), 288),
			Vector2(round(right), 294),
			Vector2(round(left), 294),
		]), Color(0.95, 0.6, 0.25, 0.5))
		cx += mark


## 中路中心的炉纹徽记，祭台正下方。
func _sigil() -> void:
	var cx := float(ArenaCatalog.LANE_LENGTH) * 0.5
	var cy := 290.0
	var gold := Color(0.95, 0.68, 0.3, 0.3)
	draw_arc(Vector2(cx, cy), 34.0, 0.0, TAU, 28, gold, 1.5)
	draw_arc(Vector2(cx, cy), 24.0, 0.0, TAU, 22, Color(1.0, 0.75, 0.38, 0.22), 1.0)
	for i in 4:
		var a := TAU * float(i) / 4.0
		draw_line(Vector2(cx + cos(a) * 24.0, cy + sin(a) * 24.0 * 0.35),
			Vector2(cx + cos(a) * 34.0, cy + sin(a) * 34.0 * 0.35), gold, 1.0)


func _lip(span: int, front: int) -> void:
	var y := front
	while y < front + 6:
		var t := float(y - front) / 6.0
		draw_rect(Rect2(0, y, span, 1), _stone(float(span) * 0.5, 0.34 - t * 0.12, 0.08))
		y += 1
	# 前缘顶线一道暖高光。
	var x := 0
	while x < span:
		var side := float(x) / float(span)
		draw_rect(Rect2(x, front, 8, 1), Color(lerpf(0.5, 0.95, side), lerpf(0.42, 0.5, side), lerpf(0.45, 0.3, side), 0.6))
		x += 8
	draw_rect(Rect2(0, front + 6, span, 10), Color(0.045, 0.028, 0.024, 0.95))
	draw_rect(Rect2(0, front + 16, span, 16), Color(0.02, 0.014, 0.016))


func _seam(bottom_x: float, y: float) -> float:
	var front := ArenaCatalog.DEPTH_FRONT
	var back := ArenaCatalog.DEPTH_BACK
	var k := clampf((front - y) / maxf(1.0, front - back), 0.0, 1.0)
	var pull := (ArenaCatalog.LANE_LENGTH * 0.5 - bottom_x) / (ArenaCatalog.LANE_LENGTH * 0.5)
	return bottom_x + pull * 48.0 * k


## 阵营染色石色：左半冷灰蓝，右半暖炉红；shade 控制明度，warm 加暖底。
func _stone(x: float, shade: float, warm: float) -> Color:
	var side := clampf(x / ArenaCatalog.LANE_LENGTH, 0.0, 1.0)
	var r := shade * lerpf(0.72, 1.3, side) + warm
	var g := shade * lerpf(0.8, 0.6, side) + warm * 0.35
	var b := shade * lerpf(1.05, 0.42, side)
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0))
