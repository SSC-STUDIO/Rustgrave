class_name TitleGauge
extends Control
## The title screen's journey gauge: 14 chapter cells.
## Default is the old vertical rod (act names beside it). The title note calls
## `use_horizontal()` and gets one faint rail instead: lit cells, a pulsing current
## cell, and a tick at each act start. No stacked numerals.
## Act boundaries (醒 / 疑 / 铸 / 破 = nodes 1-3, 4-7, 8-11, 12-14).

const TICKS := 14
const SPACING := 19.0
const TOP := 8.0
const ROD_X := 196.0
## Leftmost ink of the ruler (the act tick). The journey summary stops 8px before this
## so the two-line recap never runs under 壹贰叁 or the act glyphs.
const INK_LEFT := 146.0
const ACT_STARTS := [0, 3, 7, 11]
const PULSE_FPS := 8.0
## Horizontal rail: one cell per hall lantern. 14 × 14px fits the 208px note.
const H_PITCH := 14.0
const LANTERN_FPS := 12.0
const COL_ROD := Color("#4A2A18")
const COL_ROD_LIT := Color("#A0522D")
const COL_EMBER := Color("#FFC14A")
const COL_HOT := Color("#FFF0C0")
const COL_COLD := Color("#3A3036")
const COL_COLD_EDGE := Color("#241C22")
const COL_BONE := Color("#E8B090")

var _done: Array[bool] = []
var _current := -1
var _numerals: PackedStringArray = []
var _acts: PackedStringArray = []
var _t := 0.0
var _step := -1
## Title note sets this. The vertical rod ignores it.
var horizontal := false
var _lantern_pulse := 1.0


func _init() -> void:
	custom_minimum_size = Vector2(208.0, TOP + 12.0 + float(TICKS - 1) * SPACING + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	for id in GameContext.LEVEL_ORDER:
		_numerals.append(ChapterText.number_of(id))
	for act in ChapterText.ACTS:
		_acts.append(String(act["name"]))
	for i in TICKS:
		_done.append(false)


## The title's short note: a horizontal 14-cell rail, not a column of numerals.
func use_horizontal() -> void:
	horizontal = true
	custom_minimum_size = Vector2(4.0 + float(TICKS - 1) * H_PITCH + 8.0, 16.0)
	size = custom_minimum_size


## 0..1 brightness shared with the hall lanterns (TitleWorld.lantern_pulse).
func set_lantern_pulse(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(_lantern_pulse, next):
		return
	_lantern_pulse = next
	if horizontal:
		queue_redraw()


## `done` = per-chapter cleared flags (14), `current` = saved chapter index or -1.
func set_journey(done: Array[bool], current: int) -> void:
	_done = done.duplicate()
	while _done.size() < TICKS:
		_done.append(false)
	_current = current
	queue_redraw()


func current_index() -> int:
	return _current


func lit_count() -> int:
	var n := 0
	for d in _done:
		if d:
			n += 1
	return n


## Centre of tick `i` in this control's coordinates.
func tick_position(i: int) -> Vector2:
	if horizontal:
		return Vector2(4.0 + float(i) * H_PITCH, 8.0)
	return Vector2(ROD_X, TOP + 6.0 + float(i) * SPACING)


func _process(delta: float) -> void:
	_t += delta
	var fps := LANTERN_FPS if horizontal else PULSE_FPS
	var step := int(_t * fps)
	if step != _step and (horizontal or _current >= 0):
		_step = step
		queue_redraw()


func _draw() -> void:
	if horizontal:
		_draw_horizontal()
		return
	var last := TOP + 6.0 + float(TICKS - 1) * SPACING
	draw_rect(Rect2(ROD_X - 1.0, TOP - 4.0, 2.0, last - TOP + 12.0), COL_ROD)
	var lit_to := -1
	for i in _done.size():
		if _done[i]:
			lit_to = i
	if lit_to >= 0:
		# 点亮段先铺一层炉温辉光，再压亮色杆芯。
		var lit_len := tick_position(lit_to).y - TOP + 6.0
		draw_rect(Rect2(ROD_X - 3.0, TOP - 4.0, 6.0, lit_len), Color(1.0, 0.6, 0.2, 0.08))
		draw_rect(Rect2(ROD_X - 1.0, TOP - 4.0, 2.0, lit_len), COL_ROD_LIT)
	var font := get_theme_default_font()
	var current_act := -1
	for a in ACT_STARTS.size():
		var start: int = ACT_STARTS[a]
		var end: int = ACT_STARTS[a + 1] if a + 1 < ACT_STARTS.size() else TICKS
		if _current >= start and _current < end:
			current_act = a
	for a in ACT_STARTS.size():
		var i: int = ACT_STARTS[a]
		var y := tick_position(i).y
		if i > 0:
			# 上一幕整幕通关时，这道分隔线烧成余烬色。
			var sep_col := COL_ROD
			var prev_done := true
			for p in range(ACT_STARTS[a - 1], i):
				if p >= _done.size() or not _done[p]:
					prev_done = false
					break
			if prev_done:
				sep_col = Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.6)
			var sep := y - SPACING * 0.5
			draw_rect(Rect2(ROD_X - 22.0, sep, 22.0, 1.0), sep_col)
		# 幕名收在刻度杆左侧，给旅程摘要留出一整列。
		draw_rect(Rect2(INK_LEFT, y - 3.0, 6.0, 1.0),
				COL_EMBER if a == current_act else COL_ROD)
		draw_rect(Rect2(INK_LEFT, y - 3.0, 1.0, 6.0),
				COL_EMBER if a == current_act else COL_ROD)
		if font != null and a < _acts.size():
			var act_col := COL_EMBER if a == current_act else Color(COL_BONE.r, COL_BONE.g, COL_BONE.b, 0.55)
			act_col.a = 0.92 if a == current_act else 0.55
			draw_string(font, Vector2(INK_LEFT + 8.0, y + 4.0), _acts[a], HORIZONTAL_ALIGNMENT_LEFT, 16.0, 12,
					act_col)
	for i in TICKS:
		var c := tick_position(i)
		var is_done := i < _done.size() and _done[i]
		var is_now := i == _current
		if is_now:
			_draw_current(c)
		elif is_done:
			_diamond(c, 3, COL_EMBER, Color("#8B4513"))
			draw_rect(Rect2(c.x - 9.0, c.y - 9.0, 18.0, 18.0), Color(1.0, 0.7, 0.25, 0.06))
		else:
			_diamond(c, 3, COL_COLD, COL_COLD_EDGE)
		if font != null and i < _numerals.size():
			var col := COL_BONE if is_done or is_now else Color(0.55, 0.52, 0.5)
			col.a = 0.9 if is_now else (0.7 if is_done else 0.38)
			draw_string(font, Vector2(ROD_X - 24.0, c.y + 4.0), _numerals[i], HORIZONTAL_ALIGNMENT_RIGHT, 20.0,
					12, col)


func _draw_horizontal() -> void:
	var y := 8.0
	var x0 := 4.0
	var span := float(TICKS - 1) * H_PITCH
	draw_rect(Rect2(x0, y, span, 1.0), COL_ROD)
	var lit_to := -1
	for i in _done.size():
		if _done[i]:
			lit_to = i
	if lit_to > 0:
		draw_rect(Rect2(x0, y, float(lit_to) * H_PITCH, 1.0),
				Color(COL_ROD_LIT.r, COL_ROD_LIT.g, COL_ROD_LIT.b, 0.85 * _lantern_pulse))
	for a in ACT_STARTS.size():
		var i: int = ACT_STARTS[a]
		if i <= 0:
			continue
		var x := x0 + float(i) * H_PITCH
		draw_rect(Rect2(x, y - 4.0, 1.0, 9.0), COL_ROD)
	for i in TICKS:
		var c := tick_position(i)
		var is_done := i < _done.size() and _done[i]
		var is_now := i == _current
		var hot := COL_EMBER
		hot.a = 0.55 + 0.45 * _lantern_pulse
		if is_now:
			var pulse := 0.65 + 0.35 * _lantern_pulse
			draw_rect(Rect2(c.x - 4.0, c.y - 4.0, 8.0, 8.0), Color(1.0, 0.62, 0.22, 0.16 * pulse))
			_diamond(c, 3, COL_EMBER.lerp(COL_HOT, pulse - 0.65), Color("#8B4513"))
		elif is_done:
			_diamond(c, 2, hot, Color("#8B4513"))
		else:
			_diamond(c, 2, Color(COL_COLD.r, COL_COLD.g, COL_COLD.b, 0.55), COL_COLD_EDGE)


## 7x7 pixel diamond (radius 3) with a darker 1px edge.
func _diamond(c: Vector2, r: int, fill: Color, edge: Color) -> void:
	for dy in range(-r, r + 1):
		var half := r - absi(dy)
		draw_rect(Rect2(c.x - half - 1.0, c.y + dy, 2.0 * half + 3.0, 1.0), edge)
	for dy in range(-r + 1, r):
		var half := r - 1 - absi(dy)
		draw_rect(Rect2(c.x - half, c.y + dy, 2.0 * half + 1.0, 1.0), fill)


func _draw_current(c: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * TAU / 1.6)
	draw_rect(Rect2(c.x - 12.0, c.y - 12.0, 24.0, 24.0), Color(1.0, 0.7, 0.25, 0.07 + 0.08 * pulse))
	draw_rect(Rect2(c.x - 8.0, c.y - 8.0, 16.0, 16.0), Color(1.0, 0.7, 0.25, 0.10 + 0.10 * pulse))
	_diamond(c, 5, COL_EMBER.lerp(COL_HOT, pulse), Color("#8B4513"))
	draw_rect(Rect2(c.x - 1.0, c.y - 1.0, 3.0, 3.0), COL_HOT)
	# a short lead line from the rod toward the chapter text
	draw_rect(Rect2(c.x - 28.0, c.y, 20.0, 1.0), Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.35 + 0.35 * pulse))
