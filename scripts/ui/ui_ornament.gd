extends Control
## 全 UI 共用的像素铁件：插座剑（标题屏）、墓志短铆钉、铆钉横线、菜单架竖脊。
##
## 全部落在 2px 栅格上（与 UI 套件的 DESIGN_SCALE 一致），用绘制而不是新贴图，
## 因此标题屏 / 暂停菜单 / 设置页可以共用同一套铁件而不用各存一张 png。
## 不在本文件里写类名：这个脚本第一次被编译时全局类还没注册。

const CELL := 2
## 剑比横线粗一档，否则夹在 726px 的字标旁边会收成一根针。
const SWORD_CELL := 4
const SWORD_W := 13
const KIND_SWORD := 0
const KIND_RULE := 1
const KIND_STUB := 2
## 菜单架左侧的竖脊：把整列按钮串成一只挂在墙上的铁架。
const KIND_SPINE := 3
const SPINE_W := 20
## 从天花板垂到竖脊的锁链：标题屏两侧各挂一根，和背景垂链同语汇。
const KIND_CHAIN := 4
const CHAIN_W := 8
const PAL := {
	"0": Color("#120E14"),
	"7": Color("#4A2A18"),
	"8": Color("#8B4513"),
	"9": Color("#A0522D"),
	"b": Color("#FF8C00"),
	"c": Color("#FFC14A"),
	"e": Color("#E4DCCC"),
}
const SWORD: PackedStringArray = [
	"......c......",
	".....c9c.....",
	"....c989c....",
	"....98889....",
	"....98089....",
	"....90c09....",
	"....98089....",
	"....98889....",
	"....99899....",
	"....9e8e9....",
	"....99899....",
	"....99899....",
	"...c99899c...",
	"..998989899..",
	".c99.....99c.",
	".99.......99.",
	".....989.....",
	".....9c9.....",
	".....070.....",
	"....98889....",
	"...988b889...",
	"....98889....",
	".....989.....",
]
const DIAMOND: PackedStringArray = [
	"...c...",
	"..c9c..",
	".c989c.",
	"c98b89c",
	".c989c.",
	"..c9c..",
	"...c...",
]

var kind := KIND_SWORD
var rivet_on_left := true


static func sword() -> Control:
	return _make(KIND_SWORD)


static func rivet_rule(rule_width: float = 722.0) -> Control:
	var mark = _make(KIND_RULE)
	mark.custom_minimum_size = Vector2(rule_width, 16)
	return mark


static func stub_rule(on_left: bool) -> Control:
	return _make(KIND_STUB, on_left)


## 竖脊：一条 2px 锈线 + 一道压影，两端铆钉、中段一颗菱形铁花。
static func spine(height: float = 300.0) -> Control:
	var mark = _make(KIND_SPINE)
	mark.custom_minimum_size = Vector2(SPINE_W, height)
	return mark


static func chain(chain_height: float = 120.0) -> Control:
	var mark = _make(KIND_CHAIN)
	mark.custom_minimum_size = Vector2(CHAIN_W, chain_height)
	return mark


static func _make(which: int, on_left: bool = true) -> Control:
	var mark = load("res://scripts/ui/ui_ornament.gd").new()
	mark.kind = which
	mark.rivet_on_left = on_left
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark._apply_size()
	return mark


func _apply_size() -> void:
	if kind == KIND_SWORD:
		custom_minimum_size = Vector2((SWORD_W + 2) * SWORD_CELL, (SWORD.size() + 2) * SWORD_CELL)
	elif kind == KIND_RULE:
		custom_minimum_size = Vector2(722, 16)
	elif kind == KIND_SPINE:
		custom_minimum_size = Vector2(SPINE_W, 300)
	elif kind == KIND_CHAIN:
		custom_minimum_size = Vector2(CHAIN_W, 120)
	else:
		custom_minimum_size = Vector2(104, 16)


func _draw() -> void:
	if kind == KIND_SWORD:
		_draw_sword()
	elif kind == KIND_RULE:
		_draw_rule()
	elif kind == KIND_SPINE:
		_draw_spine()
	elif kind == KIND_CHAIN:
		_draw_chain()
	else:
		_draw_stub()


func _draw_sword() -> void:
	var h := SWORD.size()
	for y in h:
		var row := SWORD[y]
		for x in SWORD_W:
			if row[x] == ".":
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= SWORD_W or ny >= h or SWORD[ny][nx] == ".":
						_px_at(nx + 1, ny + 1, PAL["0"], SWORD_CELL)
	for y in h:
		var row := SWORD[y]
		for x in SWORD_W:
			var ch := row[x]
			if ch == ".":
				continue
			_px_at(x + 1, y + 1, PAL[ch], SWORD_CELL)


func _draw_rule() -> void:
	var width := custom_minimum_size.x
	var diamond_w := float(DIAMOND[0].length() * CELL)
	var diamond_x := (width - diamond_w) * 0.5
	var gap := 8.0
	var left_break := diamond_x - gap
	var right_break := diamond_x + diamond_w + gap
	# 线头伸进铆钉底下，避免钉和线之间裂开一缝。
	# 余烬发丝压在锈底上，暗底里仍看得见，两端再收暗。
	_span(12.0, left_break, 8.0, PAL["c"])
	_span(right_break, width - 12.0, 8.0, PAL["c"])
	_span(64.0, left_break, 10.0, PAL["9"])
	_span(right_break, width - 64.0, 10.0, PAL["9"])
	_span(12.0, 80.0, 8.0, PAL["8"])
	_span(width - 80.0, width - 12.0, 8.0, PAL["8"])
	_rivet(8.0, 6.0)
	_rivet(width - 14.0, 6.0)
	_rivet(left_break - 6.0, 6.0)
	_rivet(right_break, 6.0)
	_diamond(Vector2(diamond_x, 2.0))


## 竖脊：锈线在左、压影在右，两端各一颗铆钉，中段一颗菱形铁花。
## 菜单每一行都从这道脊上"挂"出来，整列才不会散在半空中。
func _draw_spine() -> void:
	var height := custom_minimum_size.y
	var line_x := 8.0
	draw_rect(Rect2(line_x, 4.0, 2.0, height - 8.0), PAL["9"])
	draw_rect(Rect2(line_x + 2.0, 4.0, 2.0, height - 8.0), PAL["0"])
	draw_rect(Rect2(line_x, 4.0, 2.0, height * 0.35), PAL["8"])
	_rivet(line_x - 2.0, 0.0)
	_rivet(line_x - 2.0, height - 6.0)
	_diamond(Vector2(line_x - 6.0, height * 0.5 - 7.0))


func _draw_stub() -> void:
	var width := custom_minimum_size.x
	var line_x := 8.0 if rivet_on_left else 0.0
	var line_w := width - 8.0
	draw_rect(Rect2(line_x, 8.0, line_w, 2.0), PAL["9"])
	draw_rect(Rect2(line_x, 10.0, line_w, 2.0), PAL["7"])
	if rivet_on_left:
		draw_rect(Rect2(width - 28.0, 8.0, 28.0, 2.0), PAL["7"])
	else:
		draw_rect(Rect2(0.0, 8.0, 28.0, 2.0), PAL["7"])
	var rivet_x := 4.0 if rivet_on_left else width - 10.0
	_rivet(rivet_x, 6.0)


## 2px 像素锁链：长短环交替，顶部/底部带吊扣，颜色压暗到近背景的锈色。
func _draw_chain() -> void:
	var h: float = custom_minimum_size.y
	var w: float = custom_minimum_size.x
	var dark := PAL["7"]
	var lit := PAL["9"]
	var y := 0.0
	var i := 0
	while y < h - 6.0:
		if i % 2 == 0:
			draw_rect(Rect2(1.0, y + 2.0, 2.0, 6.0), dark)
			draw_rect(Rect2(w - 3.0, y + 2.0, 2.0, 6.0), dark)
			draw_rect(Rect2(1.0, y + 6.0, w - 2.0, 2.0), lit)
		else:
			draw_rect(Rect2(0.0, y + 2.0, w, 2.0), dark)
			draw_rect(Rect2(w * 0.5 - 1.0, y, 2.0, 8.0), lit)
		y += 6.0
		i += 1
	# 吊扣：上端一块小铁板，下端收进竖脊铆钉的位置。
	draw_rect(Rect2(-2.0, 0.0, w + 4.0, 2.0), lit)
	draw_rect(Rect2(w * 0.5 - 2.0, 2.0, 4.0, 4.0), dark)
	draw_rect(Rect2(-2.0, h - 6.0, w + 4.0, 2.0), lit)
	draw_rect(Rect2(w * 0.5 - 2.0, h - 10.0, 4.0, 4.0), dark)


func _rivet(x: float, y: float) -> void:
	draw_rect(Rect2(x, y, 6, 6), PAL["7"])
	draw_rect(Rect2(x, y, 6, 2), PAL["9"])
	draw_rect(Rect2(x + 2, y + 2, 2, 2), PAL["c"])


func _span(x0: float, x1: float, y: float, color: Color) -> void:
	if x1 <= x0:
		return
	draw_rect(Rect2(x0, y, x1 - x0, 2.0), color)


func _diamond(origin: Vector2) -> void:
	var s := float(CELL)
	for y in DIAMOND.size():
		var row := DIAMOND[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			draw_rect(Rect2(origin + Vector2(x, y) * s, Vector2(s, s)), PAL[ch])


func _px_at(x: int, y: int, color: Color, cell: int) -> void:
	draw_rect(Rect2(x * cell, y * cell, cell, cell), color)
