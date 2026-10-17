extends Control
## Chapter cards, boss name plates and the compact ability card. Fixed 640x360 composition.
## The opening itself is the real cemetery, not a drawn slide.
##
## 章节卡不只是标题：地平线上有一条剪影带（远山 + 钟楼/城墙的轮廓，按 id 取），
## 一粒余烬从剪影后面升起来 —— 「新的一章在脚下」不用字幕说。Boss 名号卡在副标题
## 下加一枚相数刻度，二阶段换刻度，玩家抬头就知道对手升级了。能力卡不压暗世界，
## 只报名那个新动词；三者共用同一张 640×360 画布。

const FONT := preload("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
const INK := Color("100e18")
const RUST := Color("975336")
const EMBER := Color("ffc174")
const PALE := Color("f5dfbd")
## 每章的远山剪影高度（0..1，相对 360）。没有条目就用默认一排。
const SKYLINE := {
	"chapter": [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00],
}
## Boss 名号上的相数刻度（一 / 二）。空 = 一颗。
var phase_marks: int = 1

var shot := ""
var age := 0.0
var heading := ""
var subheading := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if shot == "ability":
		draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(640, 360))
		_ability_card()
		return
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
	if not boss:
		_skyline()
	# The boss flourish occupies the sky beside the health HUD. Combat remains
	# live: feet, ground hazards and attack telegraphs must stay visible.
	var y := 78.0 if boss else 142.0
	var center_x := 410.0 if boss else 320.0
	draw_rect(Rect2(200 if boss else 0, y - 29, 420 if boss else 640, 79), Color(0.04, 0.025, 0.05, 0.88))
	var extent := (155.0 if boss else 190.0) * smoothstep(0.0, 0.65, age)
	draw_line(Vector2(center_x - extent, y - 29), Vector2(center_x + extent, y - 29), RUST)
	draw_line(Vector2(center_x - extent, y + 50), Vector2(center_x + extent, y + 50), RUST)
	_center_text(subheading, y - 10, 10, Color("c89372"), center_x)
	_center_text(heading, y + 21, 22, PALE, center_x)
	if boss:
		_phase_marks(center_x, y + 50)
	for side in [-1, 1]:
		var p := Vector2(center_x + side * (extent + 9), y + 10)
		draw_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)]), PackedColorArray([EMBER]))
	if boss:
		_motes(false)


## 章节卡的地平线：一排低矮的山脊剪影，底部坐在卡面下缘之外，
## 只留一线起伏；一粒余芯从山脊后慢慢升上来。纯装饰，不接任何游戏状态。
func _skyline() -> void:
	var base_y := 360.0
	var ridge := PackedVector2Array([Vector2(0, base_y)])
	var steps := 16
	for i in range(steps + 1):
		var x := 640.0 * float(i) / float(steps)
		# 两段正弦叠出一座缓山 + 一座尖一点的；取整保持像素感。
		var h := 26.0 + sin(float(i) * 0.9) * 9.0 + sin(float(i) * 0.31 + 1.4) * 13.0
		h = maxf(6.0, h) * smoothstep(0.0, 1.2, age)
		ridge.append(Vector2(roundf(x), roundf(base_y - h)))
	ridge.append(Vector2(640, base_y))
	draw_colored_polygon(ridge, Color(0.02, 0.012, 0.03, 0.9))
	# 余芯：沿一条竖线从山脊后浮起，到卡面高度就淡出去。
	var lift := fposmod(age * 26.0, 190.0)
	var ember_y := 360.0 - 10.0 - lift
	var ember_x := 320.0
	var ember_a := clampf(1.0 - lift / 190.0, 0.0, 1.0) * smoothstep(0.0, 0.8, age)
	if ember_a > 0.01:
		draw_rect(Rect2(Vector2(ember_x - 1, ember_y).floor(), Vector2(2, 2)), Color(EMBER.r, EMBER.g, EMBER.b, 0.85 * ember_a))
		draw_rect(Rect2(Vector2(ember_x - 1, ember_y - 3).floor(), Vector2(1, 1)), Color(EMBER.r, EMBER.g, EMBER.b, 0.5 * ember_a))


## Boss 名号下的相数刻度：二阶段多刻一格。战斗逻辑自己判相，这里只读数。
func _phase_marks(center_x: float, y: float) -> void:
	var total := maxi(phase_marks, 1)
	var gap := 14.0
	var x0 := center_x - float(total - 1) * gap * 0.5
	for i in range(total):
		var x := x0 + float(i) * gap
		var lit := i < total
		var col := EMBER if lit else Color(0.4, 0.32, 0.3, 0.5)
		draw_rect(Rect2(Vector2(x - 3.0, y + 6.0).floor(), Vector2(6, 2)), col)


## 能力获得：一块紧凑的「新动词」铁牌，不压暗世界、不挡战斗，也不和 Boss 名号
## 抢位置（Boss 卡在 y=78 起，它贴在上方）。标题是能力名，副标题只说明「这是新动作」，
## 余烬从牌底往上走，替代一行解释字幕。
func _ability_card() -> void:
	var shown := smoothstep(0.0, 0.3, age)
	if shown <= 0.0:
		return
	var x := 176.0
	var y := 62.0
	var w := 288.0
	var h := 52.0
	draw_rect(Rect2(x, y, w, h), Color(0.04, 0.025, 0.05, 0.86 * shown))
	var extent := 108.0 * shown
	draw_line(Vector2(320.0 - extent, y), Vector2(320.0 + extent, y),
			Color(RUST.r, RUST.g, RUST.b, shown))
	draw_line(Vector2(320.0 - extent, y + h), Vector2(320.0 + extent, y + h),
			Color(RUST.r, RUST.g, RUST.b, 0.7 * shown))
	_center_text(subheading, y + 14.0, 9, Color(0.78, 0.58, 0.45, shown))
	_center_text(heading, y + 38.0, 20, Color(PALE.r, PALE.g, PALE.b, shown))
	for side in [-1, 1]:
		var p := Vector2(320.0 + side * (extent + 8.0), y + 26.0)
		draw_polygon(PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0),
				p + Vector2(0, 3), p + Vector2(-3, 0)]),
				PackedColorArray([Color(EMBER.r, EMBER.g, EMBER.b, shown)]))
	# 少量余烬从牌底往上走；纯装饰，不创建节点。
	for i in 9:
		var ex := x + 22.0 + fposmod(float(i * 47) + age * 9.0, w - 44.0)
		var lift := fposmod(float(i * 23) + age * (8.0 + float(i % 4) * 2.0), h - 8.0)
		var ey := y + h - 5.0 - lift
		var a := (1.0 - lift / (h - 8.0)) * 0.4 * shown
		draw_rect(Rect2(Vector2(ex, ey).floor(), Vector2.ONE), Color(EMBER.r, EMBER.g, EMBER.b, a))


func _text(value: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string(FONT, pos + Vector2(1, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	draw_string(FONT, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center_text(value: String, y: float, font_size: int, color: Color, center_x: float = 320.0) -> void:
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2(center_x - width * 0.5, y), font_size, color)
