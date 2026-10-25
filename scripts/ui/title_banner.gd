extends "res://scripts/ui/title_prop.gd"
## 破旗：挂在屋架下的一面撕烂的旗，被熔河升上来的热气吹得摆动。
##
## 画法：旗布是一摞 4px 高的横条，越往下横向位移越大（8 帧/秒一档，整像素），
## 左右两边各有一道锯齿撕口，下沿撕成长短不一的几缕。炉火旺，热气足，摆幅大；
## 熄火的炉子旗布是软的，几乎不动。gust 是菜单聚焦「操作说明」时的一阵风（0..1，由 TitleWorld 衰减）。
## 节点：1 个（旗不需要光晕）。节点原点 = 旗杆正中的下沿。

const WIDTH := 16
const HALF := 8
const ROWS := 11
const ROW_H := 4
## 每一行左边 / 右边被撕掉的宽度。
const TEAR_L: Array[int] = [0, 1, 0, 0, 2, 1, 0, 1, 0, 2, 3]
const TEAR_R: Array[int] = [0, 0, 1, 0, 0, 2, 1, 3, 1, 0, 4]
## 下沿的几缕：每缕 [起点 x, 宽, 额外长度（像素）]。
const FRINGE: Array = [[1, 3, 6], [5, 2, 2], [8, 3, 9], [12, 2, 4]]
const CLOTH := Color("#5C2A26")
const CLOTH_LIGHT := Color("#7C3A30")
const CLOTH_DARK := Color("#3A1A1C")
const EMBLEM := Color("#B08A4A")
const POLE := Color("#3C343C")

## 这面旗自己的相位（两面旗不同步）。
var phase := 0.0
## 一阵风：0..1，TitleWorld 每帧写进来并衰减。
var gust := 0.0


func _init() -> void:
	has_glow = false


## 摆幅（像素）：炉温越高越大，再加上阵风。
func amplitude() -> float:
	return lerpf(0.8, 3.0, clampf(heat, 0.0, 1.3) / 1.3) + clampf(gust, 0.0, 1.0) * 3.0


## 此刻第 row 行的横向位移（整像素）。
func shift_of(row: int) -> int:
	var f := float(row) / float(ROWS - 1)
	var snap := floorf(_t * 8.0) / 8.0
	return int(roundf(sin(snap * 2.4 + phase + float(row) * 0.62) * amplitude() * f))


func _draw() -> void:
	var left := -HALF
	# 旗杆
	draw_rect(Rect2(left - 2, -3, WIDTH + 4, 3), OUTLINE)
	draw_rect(Rect2(left - 1, -2, WIDTH + 2, 2), POLE)
	draw_rect(Rect2(left - 1, -2, WIDTH + 2, 1), IRON_LIGHT)
	var warm := em(Color(0.9, 0.38, 0.14, 0.55 * heat01()))
	for r in ROWS:
		var shift := shift_of(r)
		var x0 := left + TEAR_L[r] + shift
		var w := WIDTH - TEAR_L[r] - TEAR_R[r]
		var y := r * ROW_H
		draw_rect(Rect2(x0, y, w, ROW_H), CLOTH)
		# 褶皱：竖着两道明暗条，三行一换
		var fold := CLOTH_LIGHT if r % 3 != 1 else CLOTH_DARK
		draw_rect(Rect2(x0 + 3, y, 2, ROW_H), fold)
		draw_rect(Rect2(x0 + w - 4, y, 1, ROW_H), CLOTH_DARK)
	# 下沿撕成几缕
	var last := ROWS - 1
	var bottom_shift := shift_of(last)
	for strip in FRINGE:
		var sx := int(strip[0])
		var sw := int(strip[1])
		var extra := int(strip[2])
		draw_rect(Rect2(left + sx + bottom_shift, ROWS * ROW_H, sw, extra), CLOTH)
	# 徽记：一把竖着的剑，只剩半截（被撕掉了）
	var mid := shift_of(4)
	draw_rect(Rect2(-1 + mid, 6, 2, 12), EMBLEM)
	draw_rect(Rect2(-4 + mid, 12, 8, 2), EMBLEM)
	# 炉里的热气烤在旗布下沿的一道暖光
	draw_rect(Rect2(left + TEAR_L[last] + bottom_shift, ROWS * ROW_H - 1, WIDTH - TEAR_L[last] - TEAR_R[last], 1), warm)
