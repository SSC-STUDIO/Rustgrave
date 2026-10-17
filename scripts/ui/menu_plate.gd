extends RefCounted
## 标题屏的异形菜单板：轮廓由代码画，颜色与"四道环 + 抖动内芯"的结构照抄
## tools/gen_ui_kit.py 里 btn_* 贴图的生成规则，因此这只是把同一套素材换个形状，
## 不新增任何贴图、不改主题、不改配色。
##
## 三类板：PRIMARY 右端收成箭头（主行动"向前"），SECONDARY 右端剪一道燕尾缺口，
## GHOST 只有双层描边（"离开"这类第三层动作用）。状态：normal / selected / disabled
## 与 MenuRow* 用同一套颜色环，所以悬停即亮、禁用即暗，和项目里其他按钮同源。
##
## 本文件不写 class_name：菜单项按 preload 引用它，与 ui_ornament.gd 同一套做法，
## 避免全局类还没注册时的鸡生蛋问题。

## PRIMARY 主行动（右端箭头）/ SECONDARY 次行动（右端燕尾）/ GHOST 第三层（四只角标）/
## TAG 两头都切角的"标牌"，给需要任意宽度的 Button、标签页当 9-slice 底。
enum Shape { PRIMARY, SECONDARY, GHOST, TAG }
enum State { NORMAL, SELECTED, DISABLED, GHOST, GHOST_SELECTED, GHOST_DISABLED }

const CELL := 2

## gen_ui_kit.PAL 的子集（锈墓 UI 像素画的调色板）。
const PAL := {
	"0": Color("#120E14"), "1": Color("#241C22"), "3": Color("#6B5A5E"),
	"4": Color("#14101F"), "5": Color("#1E1830"), "6": Color("#2A2140"),
	"7": Color("#4A2A18"), "8": Color("#8B4513"), "9": Color("#A0522D"),
	"v": Color("#3A2012"), "c": Color("#FFC14A"),
}

## 每一环的 [上/左色, 下/右色]；环序即 btn_* 贴图的四道环（由外向内）。
const RINGS := {
	State.NORMAL: [["0", "0"], ["3", "1"], ["7", "7"], ["6", "6"]],
	State.SELECTED: [["0", "0"], ["c", "8"], ["9", "9"], ["8", "7"]],
	State.DISABLED: [["0", "0"], ["1", "1"], ["5", "5"], ["4", "4"]],
	State.GHOST: [["0", "0"], ["8", "8"]],
	State.GHOST_SELECTED: [["0", "0"], ["c", "8"]],
	State.GHOST_DISABLED: [["0", "0"], ["5", "5"]],
}
## [底色, 抖动色]；空数组 = 透空内芯（GHOST）。
const FILL := {
	State.NORMAL: ["5", "4"],
	State.SELECTED: ["7", "v"],
	State.DISABLED: ["4", "4"],
	State.GHOST: [],
	State.GHOST_SELECTED: [],
	State.GHOST_DISABLED: [],
}

## 每种板的毛坯：body 宽、高、切角、右端外伸（箭头）/内剪（燕尾）的最大值。
const SPECS := {
	Shape.PRIMARY: {"w": 440, "h": 60, "cham": 6, "grow": 20, "notch": 0},
	Shape.SECONDARY: {"w": 320, "h": 52, "cham": 6, "grow": 0, "notch": 20},
	Shape.GHOST: {"w": 280, "h": 52, "cham": 4, "grow": 0, "notch": 0},
	Shape.TAG: {"w": 240, "h": 52, "cham": 8, "grow": 0, "notch": 0},
}
## GHOST 不是一整只板，而是四只角标：臂长（像素，2px 的倍数）。
const GHOST_ARM := 18

static var _cache := {}


## 整块板的贴图尺寸（含右端箭头的外伸部分）。
static func plate_size(shape: int) -> Vector2:
	var spec: Dictionary = SPECS[shape]
	var extra := 0
	if int(spec["grow"]) > 0:
		extra = _max_grow(int(spec["h"]), int(spec["grow"]))
	return Vector2(float(int(spec["w"]) + extra), float(spec["h"]))


## 文字区宽（不算右端箭头外伸的那一截）。
static func body_width(shape: int) -> float:
	return float(SPECS[shape]["w"])


static func frame_height(shape: int) -> float:
	return float(SPECS[shape]["h"])


static func _max_grow(h: int, grow_max: int) -> int:
	var best := 0
	for b in h / CELL:
		best = maxi(best, int(_grow(h, b * CELL, grow_max)))
	return best


static func _grow(h: int, y: int, grow_max: int) -> float:
	var dist := absf(float(y) + float(CELL) * 0.5 - float(h) * 0.5)
	return _quantize(maxf(0.0, float(grow_max) - dist))


static func _notch(h: int, y: int, notch_max: int) -> float:
	var dist := absf(float(y) + float(CELL) * 0.5 - float(h) * 0.5)
	return _quantize(maxf(0.0, float(notch_max) - dist * 2.0))


static func _quantize(value: float) -> float:
	return float(int(value) / CELL * CELL)


## 每一行 2px 带的 [起点, 终点)（未做环内缩）。
static func _spans(w: int, h: int, shape: int) -> Array:
	var spec: Dictionary = SPECS[shape]
	var cham := int(spec["cham"])
	var grow_max := int(spec["grow"])
	var notch_max := int(spec["notch"])
	var out := []
	for b in h / CELL:
		var y := b * CELL
		var top := y
		var bottom := h - y - CELL
		var inset := 0
		if top < cham:
			inset = maxi(inset, cham - top)
		if bottom < cham:
			inset = maxi(inset, cham - bottom)
		var x0 := inset
		var x1 := w - inset
		if grow_max > 0:
			x1 += int(_grow(h, y, grow_max))
		if notch_max > 0:
			x1 -= int(_notch(h, y, notch_max))
		out.append(Vector2i(x0, x1))
	return out


static func texture(shape: int, state: int) -> Texture2D:
	var key := "%d:%d" % [shape, state]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(_paint(shape, state))
	_cache[key] = tex
	return tex


## 把整块板包成 9-slice 样式盒：标签页、对话框这类宽度不固定的控件直接吃它。
## 左右/上下只切掉"切角 + 四道环"的宽度，中段平铺 —— 抖动内芯按 1:1 重复，
## 不会被拉成一片纯色（和 theme_rust 里 btn_* 的作法一致）。
static func style_box(shape: int, state: int) -> StyleBoxTexture:
	var spec: Dictionary = SPECS[shape]
	var ring_w := (RINGS[state] as Array).size() * CELL
	var margin := float(int(spec["cham"]) + ring_w)
	var sb := StyleBoxTexture.new()
	sb.texture = texture(shape, state)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = margin + 10.0
	sb.content_margin_right = margin + 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb


static func _paint(shape: int, state: int) -> Image:
	var spec: Dictionary = SPECS[shape]
	var body_w := int(spec["w"])
	var h := int(spec["h"])
	var bands := h / CELL
	var spans := _spans(body_w, h, shape)
	var width := body_w
	for sp in spans:
		width = maxi(width, int(sp.y))
	var img := Image.create(width, h, false, Image.FORMAT_RGBA8)

	var rings: Array = RINGS[state]
	var ring_count := rings.size()
	var colors := []
	for ring in rings:
		colors.append([PAL[ring[0]], PAL[ring[1]]])
	if shape == Shape.GHOST:
		_paint_brackets(img, body_w, h, colors)
		return img
	var fill: Array = FILL[state]
	var has_fill := fill.size() == 2
	var base: Color = PAL[fill[0]] if has_fill else Color(0, 0, 0, 0)
	var alt: Color = PAL[fill[1]] if has_fill else Color(0, 0, 0, 0)

	for b in bands:
		var sp: Vector2i = spans[b]
		var y := b * CELL
		var cell_l := sp.x / CELL
		var cell_r := sp.y / CELL
		# 这一带里"纯内芯"的列区间：离四条边都超过环数。
		var inner_l := cell_l + ring_count
		var inner_r := cell_r - ring_count
		var has_inner := has_fill and inner_r > inner_l \
				and b >= ring_count and bands - 1 - b >= ring_count
		var scan_r := inner_l if has_inner else cell_r
		for cx in range(cell_l, scan_r):
			_fill(img, cx * CELL, y, CELL, CELL, _ring_color(colors, b, bands, cx, cell_l, cell_r))
		# 右端环带
		for cx in range(maxi(inner_r, scan_r), cell_r):
			_fill(img, cx * CELL, y, CELL, CELL, _ring_color(colors, b, bands, cx, cell_l, cell_r))
		if not has_inner:
			continue
		_fill(img, inner_l * CELL, y, (inner_r - inner_l) * CELL, CELL, base)
		var cx2 := inner_l
		while cx2 < inner_r:
			if (cx2 + b) % 2 == 1:
				_fill(img, cx2 * CELL, y, CELL, CELL, alt)
			cx2 += 1
	return img


## 一个 2px 格子落在哪一环：取到上/下/左/右四条边的最小距离。
## 上、左算受光面，下、右算背光面，平手按受光处理（外环两种颜色常常相同）。
static func _ring_color(colors: Array, b: int, bands: int, cx: int, cell_l: int, cell_r: int) -> Color:
	var top := b
	var bottom := bands - 1 - b
	var left := cx - cell_l
	var right := cell_r - 1 - cx
	var nearest := mini(mini(top, bottom), mini(left, right))
	if nearest >= colors.size():
		return Color(0, 0, 0, 0)
	var pair: Array = colors[nearest]
	var lit := top == nearest or left == nearest
	return pair[0] if lit else pair[1]


## GHOST 画成四只 L 形角标：上沿、左侧受光，下沿、右侧压暗，
## 中间完全透空 —— 第三层动作不该和上面两档抢同一只"盒子"的形状。
static func _paint_brackets(img: Image, body_w: int, h: int, colors: Array) -> void:
	for k in colors.size():
		var pair: Array = colors[k]
		var inset := k * CELL
		var arm := GHOST_ARM - inset
		if arm <= 0:
			continue
		var x0 := inset
		var x1 := body_w - inset - CELL
		var y0 := inset
		var y1 := h - inset - CELL
		# 上沿 / 下沿
		_fill(img, x0, y0, arm, CELL, pair[0])
		_fill(img, x1 - arm + CELL, y0, arm, CELL, pair[0])
		_fill(img, x0, y1, arm, CELL, pair[1])
		_fill(img, x1 - arm + CELL, y1, arm, CELL, pair[1])
		# 左右竖臂
		_fill(img, x0, y0, CELL, arm, pair[0])
		_fill(img, x0, y1 - arm + CELL, CELL, arm, pair[1])
		_fill(img, x1, y0, CELL, arm, pair[1])
		_fill(img, x1, y1 - arm + CELL, CELL, arm, pair[1])


static func _fill(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	if w <= 0 or h <= 0:
		return
	if x < 0:
		w += x
		x = 0
	var max_x := img.get_width()
	if x + w > max_x:
		w = max_x - x
	if w <= 0:
		return
	img.fill_rect(Rect2i(x, y, w, h), color)
