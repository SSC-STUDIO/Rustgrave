class_name TitleGauge
extends Control
## The title screen's journey gauge: 14 chapter ticks along a thin vertical rod.
## Cleared chapters are lit ember diamonds, the current one pulses, the rest are cold
## iron. Act boundaries (醒 / 债 / 铸 / 炉 = chapters 1-3, 4-7, 8-11, 12-14) get a
## short bar and the act's glyph. Drawn in 1px/2px rects, redrawn at the pulse rate.

const TICKS := 14
const SPACING := 19.0
const TOP := 8.0
const ROD_X := 196.0
const ACT_STARTS := [0, 3, 7, 11]
const PULSE_FPS := 8.0
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
	return Vector2(ROD_X, TOP + 6.0 + float(i) * SPACING)


func _process(delta: float) -> void:
	_t += delta
	var step := int(_t * PULSE_FPS)
	if step != _step and _current >= 0:
		_step = step
		queue_redraw()


func _draw() -> void:
	var last := TOP + 6.0 + float(TICKS - 1) * SPACING
	draw_rect(Rect2(ROD_X - 1.0, TOP - 4.0, 2.0, last - TOP + 12.0), COL_ROD)
	var lit_to := -1
	for i in _done.size():
		if _done[i]:
			lit_to = i
	if lit_to >= 0:
		draw_rect(Rect2(ROD_X - 1.0, TOP - 4.0, 2.0, tick_position(lit_to).y - TOP + 6.0), COL_ROD_LIT)
	var font := get_theme_default_font()
	for a in ACT_STARTS.size():
		var i: int = ACT_STARTS[a]
		var y := tick_position(i).y
		if i > 0:
			var sep := y - SPACING * 0.5
			draw_rect(Rect2(ROD_X - 26.0, sep, 26.0, 1.0), COL_ROD)
		if font != null and a < _acts.size():
			draw_string(font, Vector2(ROD_X - 92.0, y + 4.0), _acts[a], HORIZONTAL_ALIGNMENT_LEFT, 20.0, 12,
					Color(COL_BONE.r, COL_BONE.g, COL_BONE.b, 0.55))
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
			draw_string(font, Vector2(ROD_X - 22.0 - 24.0, c.y + 4.0), _numerals[i], HORIZONTAL_ALIGNMENT_RIGHT, 24.0,
					12, col)


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
	draw_rect(Rect2(c.x - 34.0, c.y, 24.0, 1.0), Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.35 + 0.35 * pulse))
