class_name MenuItem
extends Control
## 一行菜单。默认形态沿用主题的 Button 样式盒（暂停菜单 / 结局选择用它）；
## 标题屏用三档异形板：PRIMARY 右端收成箭头、SECONDARY 右端剪出燕尾、
## GHOST 只留双层描边——形状由 MenuPlate 用同一套调色板现画，不新增贴图。
##
## 不用 Button，因为选中态需要在键盘导航下自己控制（Button 的 focus 框会叠在
## normal 之上），而且要挂帧动画火苗。样式仍然只从主题取，保证与全局一致。
##
## 刻意不做几何缩放：像素字体一旦被非整数倍缩放就会出灰边，所以“呼吸”走
## modulate 亮度，位移走整数像素。

signal activated
## 鼠标移到本行上时发出，菜单容器据此把选中项挪过来。
signal hover_requested

const Plate := preload("res://scripts/ui/menu_plate.gd")

enum Kind { DEFAULT, PRIMARY, SECONDARY, GHOST }

const HEIGHT := 52.0
const SELECTED_INDENT := 8.0
const BREATH_PERIOD := 1.6
const BREATH_MIN := 1.0
const BREATH_MAX := 1.18

## 异形板的形状/状态与光标、火盆在板内的位置（设计像素，落在 2px 栅格上）。
const SHAPES_COMPACT := {
	Kind.PRIMARY: Plate.Shape.RAIL_PRIMARY,
	Kind.SECONDARY: Plate.Shape.RAIL_SECONDARY,
	Kind.GHOST: Plate.Shape.RAIL_GHOST,
}
const SHAPES := {Kind.PRIMARY: Plate.Shape.PRIMARY, Kind.SECONDARY: Plate.Shape.SECONDARY,
		Kind.GHOST: Plate.Shape.GHOST}
const CURSOR_X := {Kind.PRIMARY: 30.0, Kind.SECONDARY: 24.0, Kind.GHOST: 26.0}
## 每格板向左伸出的挂架短钉：接到标题屏的竖脊上，选中时烧成余烬色。
const TICK_LEN := 24.0
const TICK_DIM := Color("#4A2A18")
const TICK_LIT := Color("#FFC14A")

## "铁条"版式（v3 标题屏）：不用异形板，只画一条压暗的铁条 + 左缘灯口 + 余烬光标；
## 三档仍对应 PRIMARY / SECONDARY / GHOST（宽度递减，GHOST 只剩描边）。行高仍是 52（触控下限）。
const STRIP_H := 40.0
const STRIP_WIDTH := {Kind.PRIMARY: 344.0, Kind.SECONDARY: 304.0, Kind.GHOST: 248.0}
const STRIP_CURSOR_X := 14.0
const STRIP_LABEL_X := 48.0
## 选中条整体右移 4px（缓动），像被从架上抽出半寸。
const STRIP_SHIFT := 4.0
const LAND_SHIFT := 28.0
const STRIP_RUST := Color("#8B4513")
const STRIP_IRON := Color("#4A3E44")
const STRIP_EMBER := Color("#FFC14A")
## 灯标行的字从这里开始，左边留给吊灯。
const LAMP_LABEL_X := 56.0
## 灯标行右侧的行内小注（「继续旅程」行的章节/进度，10px 小字）：贴右缘、不撑高行。
const NOTE_INLINE_W := 96.0
const NOTE_INLINE_RIGHT := 8.0
const NOTE_INLINE_SIZE := 10
## 灯标行：行内注离字尾的距离。
const NOTE_INLINE_GAP := 14.0

## 菜单项 id（MenuList.add_item 写入；标题测试/旧调用按它读行）。
var id: StringName = &""
## 标题屏的紧凑板：同样的三档形状，映射到更矮更短的一组 SPECS。
var compact := false
## 铁条版式（MenuList.strip_style 在 add_child 之前写入）。
var strip := false
## 标题屏的灯标版式：不画条，字本身被外面的吊灯照亮（TitleLampCursor 每帧写入 lamp_light）。
var lamp := false
## 0 = 这行在灯的照不到的地方，1 = 灯芯正对着这行。
var lamp_light := 0.0
## 账簿/手札的墨水版式：墨水字、选中时变暖、行首余烬点、淡墨下划线。
var ink := false
## 压在不透明深色面板上的铁条（回看页）：底色更深、几乎不透明，才不会和卡片的紫底混成一片。
var dark_plate := false
## 开屏"落位"：1 = 整条向左偏移 LAND_SHIFT 并等着淡入，0 = 在原位。
var land := 0.0:
	set(value):
		land = value
		_apply_land()
var kind: Kind = Kind.DEFAULT
## 挂钉只属于"铁架"版式（标题屏 / 暂停菜单）；对话框里的板不要向左伸的挂钉。
var show_tick := true:
	set(value):
		show_tick = value
		queue_redraw()
var disabled := false:
	set(value):
		disabled = value
		_refresh()

## 禁用行的字色透明度（默认 0.90；「继续旅程」无档时压到 0.55，让"先点燃余烬"更明确）。
## 描边走主题的独立颜色，不跟着这个 alpha 一起淡掉。
var disabled_alpha := 0.90:
	set(value):
		disabled_alpha = value
		if lamp:
			_paint_lamp()
			queue_redraw()
## 非选中 / 选中都保持的基础色调（确认信里「确认覆盖」行压暗到 0.85，不再提亮）。
var tint := Color.WHITE:
	set(value):
		tint = value
		_refresh()

var selected := false:
	set(value):
		if selected == value:
			return
		selected = value
		_refresh()

var _text := ""
var _panel: Panel
var _plate: TextureRect
var _label: Label
var _note: Label
## 小注是行内右侧（不撑高行），还是悬挂铁签（试炼未解锁）。
var _note_inline := false
var _lock_tag: LockTag
var _cursor: TextureRect
var _brazier: Node2D
var _time := 0.0
var _cursor_x := 0.0
var _cursor_base_y := 0.0
var _cursor_tween: Tween
var _shift_tween: Tween

## 悬挂在锁定菜单项下方的铁签（T2）：一根 ~6px 小链 + 12px 小字。
class LockTag:
	extends Control

	var _chain_x := 18.0
	var _tag_h := 12.0
	var _chain_len := 6.0

	func _init() -> void:
		name = "LockTag"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# 6px 小链
		var cx := _chain_x
		draw_line(Vector2(cx, 0.0), Vector2(cx, _chain_len), Color(0.45, 0.40, 0.38, 0.85), 1.0)
		draw_rect(Rect2(cx - 1.0, 1.0, 3.0, 2.0), Color(0.55, 0.48, 0.42, 0.9))
		draw_rect(Rect2(cx - 1.0, 4.0, 3.0, 2.0), Color(0.38, 0.32, 0.30, 0.9))
		# 12px 铁签底板
		var tag_rect := Rect2(0.0, _chain_len, size.x, _tag_h)
		draw_rect(tag_rect, Color(0.09, 0.075, 0.11, 0.88))
		# 铁签边框与阴影
		draw_rect(Rect2(0.0, _chain_len, size.x, 1.0), Color(0.32, 0.26, 0.22, 0.85))
		draw_rect(Rect2(0.0, _chain_len + _tag_h - 1.0, size.x, 1.0), Color(0.20, 0.16, 0.15, 0.85))
		draw_rect(Rect2(0.0, _chain_len, 1.0, _tag_h), Color(0.30, 0.24, 0.20, 0.85))
		draw_rect(Rect2(size.x - 1.0, _chain_len, 1.0, _tag_h), Color(0.20, 0.16, 0.15, 0.85))
		# 链扣铆钉
		draw_rect(Rect2(cx - 1.0, _chain_len + 1.0, 2.0, 2.0), Color(0.68, 0.58, 0.42, 0.95))


func _init(text: String = "", item_kind: Kind = Kind.DEFAULT) -> void:
	_text = text
	kind = item_kind


func _ready() -> void:
	if kind == Kind.DEFAULT:
		_build_default_row()
	elif ink:
		_build_ink_row()
	elif lamp:
		_build_lamp_row()
	elif strip:
		_build_strip_row()
	else:
		_build_plate_row()
	mouse_entered.connect(func() -> void:
		if not disabled:
			hover_requested.emit())
	_refresh()


## 账簿/手札版式：墨水字，行首余烬点，底部淡墨下划线。
func _build_ink_row() -> void:
	var width: float = STRIP_WIDTH.get(kind, 344.0)
	custom_minimum_size = Vector2(width, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_tick = false
	_label = UiKit.label(_text, &"MenuItemLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_label.position = Vector2(32.0, 0.0)
	_label.size = Vector2(width - 44.0, HEIGHT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color("#221A15"))
	_label.add_theme_constant_override("outline_size", 0)
	_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	add_child(_label)

	_note = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_note.position = Vector2(width - 124.0, 0.0)
	_note.size = Vector2(100.0, HEIGHT)
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.visible = false
	add_child(_note)


## 主题样式盒的行底 —— 暂停菜单、结局选择、覆盖存档确认框继续用这一套。
func _build_default_row() -> void:
	custom_minimum_size = Vector2(420.0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_label = UiKit.label(_text, &"MenuItemLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	# 选中行左侧点一小簇余烬，是标题屏那套粒子的缩小版。
	_brazier = UiKit.EmberField.build(Rect2(14.0, 8.0, 22.0, HEIGHT - 16.0), 4, 0)
	add_child(_brazier)

	_cursor = UiKit.sprite_rect(UiKit.TEX_CURSOR)
	var art := _cursor.texture
	_cursor.position = Vector2(38.0, (HEIGHT - (art.get_height() if art != null else 28)) * 0.5)
	add_child(_cursor)


## 标题屏的异形板：板面形状/状态全在 MenuPlate，这里只负责摆字、光标和火苗。
func _shape() -> int:
	if compact and kind != Kind.DEFAULT:
		return SHAPES_COMPACT[kind]
	return SHAPES[kind]


func _build_plate_row() -> void:
	var shape: int = _shape()
	var size := Plate.plate_size(shape)
	var body_w := Plate.body_width(shape)
	var height := Plate.frame_height(shape)
	custom_minimum_size = size
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP

	_plate = TextureRect.new()
	_plate.texture = Plate.texture(shape, Plate.State.NORMAL)
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate.stretch_mode = TextureRect.STRETCH_KEEP
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size = size
	add_child(_plate)

	_label = UiKit.label(_text, &"MenuItemLabel", HORIZONTAL_ALIGNMENT_CENTER)
	if compact:
		# 紧凑板高度只有 48/40，字号跟着收一档，字才不会顶满上下沿。
		_label.add_theme_font_size_override("font_size", 28)
	_label.position = Vector2.ZERO
	_label.size = Vector2(body_w, height)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	_brazier = UiKit.EmberField.build(
			Rect2(CURSOR_X[kind] - 16.0, 10.0, 26.0, height - 20.0), 3, 0)
	add_child(_brazier)

	_cursor = UiKit.sprite_rect(UiKit.TEX_CURSOR)
	var art := _cursor.texture
	var cursor_h := art.get_height() if art != null else 28
	_cursor_x = CURSOR_X[kind] - (6.0 if compact else 0.0)
	_cursor.position = Vector2(_cursor_x - 8.0, (height - cursor_h) * 0.5)
	add_child(_cursor)


## 铁条版式：压暗的条身 + 左缘灯口 + 余烬光标，文字左对齐。
func _build_strip_row() -> void:
	var width: float = STRIP_WIDTH[kind]
	custom_minimum_size = Vector2(width, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_tick = false
	_label = UiKit.label(_text, &"MenuItemLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_label.position = Vector2(STRIP_LABEL_X, 0.0)
	_label.size = Vector2(width - STRIP_LABEL_X - 16.0, HEIGHT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_note = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	# 右端让开削角阶梯（最外 8px 是斜面），小字收在条身内。
	_note.position = Vector2(width - 124.0, 0.0)
	_note.size = Vector2(100.0, HEIGHT)
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.visible = false
	add_child(_note)
	_brazier = UiKit.EmberField.build(Rect2(STRIP_CURSOR_X - 8.0, 8.0, 28.0, HEIGHT - 16.0), 3, 0)
	add_child(_brazier)
	_cursor = UiKit.sprite_rect(UiKit.TEX_CURSOR)
	var art := _cursor.texture
	var cursor_h := art.get_height() if art != null else 28
	_cursor_x = STRIP_CURSOR_X
	_cursor_base_y = (HEIGHT - cursor_h) * 0.5
	_cursor.position = Vector2(_cursor_x - 8.0, _cursor_base_y)
	add_child(_cursor)


## 灯标行：和铁条一样宽、一样高（触控区不变），但不画条身。字从左侧让开一盏灯的位置。
func _build_lamp_row() -> void:
	var width: float = STRIP_WIDTH[kind]
	custom_minimum_size = Vector2(width, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_tick = false
	_label = UiKit.label(_text, &"MenuItemLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_label.position = Vector2(LAMP_LABEL_X, 0.0)
	_label.size = Vector2(width - LAMP_LABEL_X - 12.0, HEIGHT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", 1)
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))
	add_child(_label)

	_note = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_note.position = Vector2(width - 124.0, 0.0)
	_note.size = Vector2(100.0, HEIGHT)
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.visible = false
	add_child(_note)


## 吊灯每帧告诉这一行自己被照到多少。选中行还会自己呼吸，不依赖这个值。
func set_lamp_light(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(lamp_light, next):
		return
	lamp_light = next
	if lamp:
		_paint_lamp()


## 条右端的小字（例如试炼未解锁时的"第七章后解锁"）；空串 = 不显示。
## inline=true：灯标行右侧的 10px 行内注（章节/进度），行高保持 52，不挂铁签。
func set_note(value: String, inline: bool = false) -> void:
	if _note == null:
		return
	if inline:
		_note_inline = true
		_note.text = value
		_note.visible = value != ""
		_note.modulate = Color.WHITE
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if lamp else HORIZONTAL_ALIGNMENT_RIGHT
		_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_note.clip_text = true
		_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_note.add_theme_font_size_override("font_size",
				mini(roundi(float(NOTE_INLINE_SIZE) * Settings.assist(&"text_scale")), 12))
		_note.add_theme_color_override("font_color", Color(0.73, 0.67, 0.58, 0.92))
		_note.add_theme_constant_override("outline_size", 1)
		_note.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))
		_note.position = Vector2(_inline_note_x(), 0.0)
		_note.size = Vector2(NOTE_INLINE_W, HEIGHT)
		queue_redraw()
		return
	_note.text = value
	var has_text := value != ""
	_note.visible = has_text
	if lamp:
		if has_text and _lock_tag == null:
			_lock_tag = LockTag.new()
			_lock_tag.position = Vector2(LAMP_LABEL_X + 6.0, 31.0)
			_lock_tag.size = Vector2(88.0, 18.0)
			add_child(_lock_tag)
			_note.reparent(_lock_tag)
			_note.position = Vector2(0.0, 6.0)
			_note.size = Vector2(88.0, 12.0)
			_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_note.add_theme_font_size_override("font_size", 10)
			_note.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62, 0.9))
			_note.add_theme_constant_override("outline_size", 1)
			_note.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))
		if _lock_tag != null:
			_lock_tag.visible = has_text
		if has_text and _label != null:
			_label.position.y = 2.0
			_label.size.y = 26.0
		elif _label != null:
			_label.position.y = 0.0
			_label.size.y = HEIGHT
	elif has_text:
		_note.add_theme_font_size_override("font_size", 10)
		_note.modulate = Color(0.70, 0.65, 0.60, 0.85)


func _apply_land() -> void:
	if _label == null or not (strip or lamp):
		return
	var ox := -land * LAND_SHIFT
	_label.position.x = (LAMP_LABEL_X if lamp else STRIP_LABEL_X) + ox
	if _lock_tag != null:
		_lock_tag.position.x = LAMP_LABEL_X + 6.0 + ox
	elif _note != null:
		if _note_inline:
			_note.position.x = _inline_note_x() + ox
		else:
			_note.position.x = size.x - 124.0 + ox
	queue_redraw()


## 行内注的左端：灯标行紧跟在字后面（不悬在条的右端），其余版式靠右。
func _inline_note_x() -> float:
	var right: float = STRIP_WIDTH.get(kind, 344.0) - NOTE_INLINE_RIGHT - NOTE_INLINE_W
	if not lamp or _label == null:
		return right
	var text_w := _label.get_theme_font(&"font").get_string_size(_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _label.get_theme_font_size(&"font_size")).x
	return minf(LAMP_LABEL_X + text_w + NOTE_INLINE_GAP, right)


func set_text(value: String) -> void:
	_text = value
	if _label != null:
		_label.text = value


func _process(delta: float) -> void:
	if not selected or disabled:
		return
	_time += delta
	if ink:
		_paint_ink()
		queue_redraw()
		return
	if lamp:
		_paint_lamp()
		queue_redraw()
		return
	var breath := lerpf(BREATH_MIN, BREATH_MAX, 0.5 + 0.5 * sin(TAU * _time / BREATH_PERIOD))
	# 只动 rgb：alpha 留给开屏淡入用，每帧整体覆盖会把淡入吃掉。
	modulate = Color(breath, breath, breath, modulate.a)
	# 铁条的光标轻轻起落：整数像素，字形不出灰边。
	if strip and _cursor != null:
		_cursor.position.y = _cursor_base_y + float(roundi(sin(TAU * _time / 0.9)))


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
		accept_event()


## 条身：2px 栅格上的深色铁条，右端两角削成阶梯，左缘一根灯口（选中时烧成余烬色）。
func _draw_strip() -> void:
	var w := size.x
	var h := STRIP_H
	var y0 := floorf((size.y - h) * 0.5)
	var ox := -land * LAND_SHIFT
	var lit := selected and not disabled
	var fill := Color(0.055, 0.04, 0.075, 0.74)
	if dark_plate:
		fill = Color(0.028, 0.022, 0.038, 0.96)
	var edge := Color(0.30, 0.17, 0.10, 0.85)
	var accent := STRIP_RUST if kind == Kind.PRIMARY else STRIP_IRON
	if kind == Kind.GHOST:
		fill.a = 0.36
	if disabled:
		fill = Color(0.04, 0.035, 0.05, 0.5)
		edge = Color(0.18, 0.15, 0.17, 0.7)
		accent = Color(0.22, 0.19, 0.2)
	elif lit:
		fill = Color(0.17, 0.09, 0.05, 0.88)
		edge = Color(0.86, 0.5, 0.18, 0.95)
		accent = STRIP_EMBER
	var x0 := 0.0 + ox
	if lit:
		# 条外一圈炉温光晕：选中条像刚从火里抽出来。
		draw_rect(Rect2(x0 - 2.0, y0 - 2.0, w - 4.0, h + 4.0), Color(1.0, 0.55, 0.15, 0.07))
		draw_rect(Rect2(x0 - 1.0, y0 - 1.0, w - 6.0, h + 2.0), Color(1.0, 0.65, 0.22, 0.10))
	# body, right end chamfered in 2px steps (4 steps = 8px)
	draw_rect(Rect2(x0, y0 + 8.0, w - 8.0, h - 16.0), fill)
	for i in 4:
		var inset := 8.0 - 2.0 * float(i)
		draw_rect(Rect2(x0, y0 + 2.0 * float(i), w - inset, 2.0), fill)
		draw_rect(Rect2(x0, y0 + h - 2.0 * float(i + 1), w - inset, 2.0), fill)
	# hairlines top and bottom
	draw_rect(Rect2(x0 + 4.0, y0, w - 12.0, 1.0), edge)
	draw_rect(Rect2(x0 + 4.0, y0 + h - 1.0, w - 12.0, 1.0), edge)
	# the lamp tab on the left edge
	draw_rect(Rect2(x0, y0, 4.0, h), accent)
	if lit:
		draw_rect(Rect2(x0 + 4.0, y0 + 1.0, 56.0, h - 2.0), Color(1.0, 0.6, 0.2, 0.16))
		draw_rect(Rect2(x0 + 4.0, y0 + 1.0, 28.0, h - 2.0), Color(1.0, 0.7, 0.25, 0.14))
		draw_rect(Rect2(x0 + 1.0, y0 + 4.0, 2.0, h - 8.0), Color(1.0, 0.94, 0.7))
		# 削角尖上一粒余烬：右端不再是个闷头。
		draw_rect(Rect2(x0 + w - 10.0, y0 + h * 0.5 - 2.0, 4.0, 4.0), Color(0.55, 0.28, 0.10))
		draw_rect(Rect2(x0 + w - 9.0, y0 + h * 0.5 - 1.0, 2.0, 2.0), Color(1.0, 0.85, 0.45))


func _draw() -> void:
	if kind != Kind.DEFAULT and ink:
		_draw_ink()
		return
	if kind != Kind.DEFAULT and lamp:
		_draw_lamp()
		return
	if kind != Kind.DEFAULT and strip:
		_draw_strip()
		return
	if kind == Kind.DEFAULT or not show_tick:
		return
	# 板子向左伸一根挂架短钉，接到标题屏的竖脊上；选中时整根烧亮。
	var lit := selected and not disabled
	draw_rect(Rect2(-TICK_LEN, size.y * 0.5 - 2.0, TICK_LEN, 2.0),
			TICK_LIT if lit else TICK_DIM)
	draw_rect(Rect2(-TICK_LEN, size.y * 0.5, TICK_LEN, 2.0),
			Color("#3A2012") if lit else Color("#241C22"))


func _notification(what: int) -> void:
	# 短钉的位置取自本行高度：容器排版完成后第一次拿到真实尺寸，要重画。
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		# 容器重排会重置 position：选中条的抽出量补回来（不播缓动）。
		_apply_shift(selected and not disabled, true)


func _refresh() -> void:
	if _label == null:
		return
	# 可点的行给一只手形光标；禁用行退回箭头，别让玩家以为还能点。
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	if kind == Kind.DEFAULT:
		_refresh_default()
	elif ink:
		_refresh_ink()
		queue_redraw()
	elif lamp:
		_refresh_lamp()
		queue_redraw()
	elif strip:
		_refresh_strip()
		queue_redraw()
	else:
		_refresh_plate()
		queue_redraw()
	var lit := selected and not disabled
	if _cursor != null:
		_cursor.visible = lit
	if _brazier != null:
		_brazier.visible = lit
	if not lit:
		# 灯标与墨水行的淡入淡出走 modulate.a（开屏 / 退场）。这里不能把 alpha 打回 1。
		if lamp or ink:
			modulate = Color(tint.r, tint.g, tint.b, modulate.a)
		else:
			modulate = tint
		_time = 0.0
	set_process(lit)


func _refresh_ink() -> void:
	_paint_ink()


func _paint_ink() -> void:
	if _label == null or not ink:
		return
	if disabled:
		_label.add_theme_color_override("font_color", Color(0.68, 0.64, 0.60, 0.70))
		return
	if selected:
		var breath := 0.5 + 0.5 * sin(TAU * _time / BREATH_PERIOD)
		var col: Color = Color("#221A15").lerp(Color("#8A3D16"), breath * 0.5 + 0.25)
		_label.add_theme_color_override("font_color", col)
	else:
		_label.add_theme_color_override("font_color", Color("#221A15"))


func _draw_ink() -> void:
	if _label == null or not selected or disabled:
		return
	var cy := floorf(size.y * 0.5)
	# 行首余烬点指示 (Ember pip indicator at x = 16)
	var pip_center := Vector2(16.0, cy)
	GlassKit.diamond(self, pip_center, 4.0, Color("#C0392B"))
	GlassKit.diamond(self, pip_center, 2.0, Color("#FFC14A"))
	# 淡墨下划线 (Faint sepia underline)
	var x0 := _label.position.x
	var font := _label.get_theme_font(&"font")
	var font_sz := _label.get_theme_font_size(&"font_size")
	var text_w := 120.0
	if font != null:
		text_w = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
	var y_line := floorf(cy + 13.0)
	draw_rect(Rect2(x0, y_line, text_w, 1.0), Color(0.45, 0.28, 0.16, 0.55))


## 灯标：字色跟着灯走。禁用行保持冷灰，灯照过来也不亮。
func _refresh_lamp() -> void:
	_paint_lamp()


func _paint_lamp() -> void:
	if _label == null or not lamp:
		return
	if disabled:
		# 禁用行：冷灰 + 可调的透明度；描边仍由主题给的高对比深色独立画。
		_label.add_theme_color_override("font_color",
				Color(0.68, 0.64, 0.60, clampf(disabled_alpha, 0.0, 1.0)))
		return
	var warmth := lamp_light
	if selected:
		var breath := 0.5 + 0.5 * sin(TAU * _time / BREATH_PERIOD)
		warmth = maxf(warmth, lerpf(0.88, 1.0, breath))
	var cold_col := Color(0.65, 0.60, 0.54)
	var warm_bake := Color(0.90, 0.65, 0.36)
	var col: Color
	if warmth < 0.55:
		col = cold_col.lerp(warm_bake, warmth / 0.55)
	else:
		col = warm_bake.lerp(UiKit.EMBER, (warmth - 0.55) / 0.45)
	if warmth > 0.85:
		col = col.lerp(Color(1.0, 0.96, 0.84), (warmth - 0.85) / 0.15)
	_label.add_theme_color_override("font_color", col)


## 选中行底下一条烧着的细线：从字的左端亮起，长度就是这一行字的真实宽度
## （不是写死的一小截），行首左侧再点一粒 3x5px 的火星。不画条身。
func _draw_lamp() -> void:
	if _label == null or not selected or disabled:
		return
	var x := _label.position.x
	var y := floorf(size.y * 0.5 + 12.0)
	if y > size.y - 2.0:
		return
	var span := underline_span()
	if span < 8.0:
		return
	draw_rect(Rect2(x, y, span, 1.0), Color(1.0, 0.45, 0.14, 0.45))
	draw_rect(Rect2(x, y, minf(span, 22.0), 1.0), Color(1.0, 0.92, 0.7, 0.95))
	# 行首 3x5px 余烬：下划线从这里"点着"。
	var cy := floorf(size.y * 0.5)
	draw_rect(Rect2(x - 9.0, cy - 2.0, 3.0, 5.0), Color(0.55, 0.28, 0.10, 0.9))
	draw_rect(Rect2(x - 9.0, cy - 2.0, 3.0, 2.0), Color(1.0, 0.78, 0.35, 0.95))


## 选中行下划线的长度：这一行字的实际宽度，不超过行内可用宽（测试可读）。
func underline_span() -> float:
	if _label == null:
		return 0.0
	var avail := maxf(size.x - _label.position.x - 16.0, 0.0)
	var font := _label.get_theme_font(&"font")
	if font == null:
		return avail
	var font_size := _label.get_theme_font_size(&"font_size")
	var text_w := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return minf(ceilf(text_w), avail)


func _refresh_default() -> void:
	if disabled:
		_panel.theme_type_variation = &"MenuRowDisabled"
		_label.theme_type_variation = &"MenuItemLabelDisabled"
	elif selected:
		_panel.theme_type_variation = &"MenuRowSelected"
		_label.theme_type_variation = &"MenuItemLabelSelected"
	else:
		_panel.theme_type_variation = &"MenuRowNormal"
		_label.theme_type_variation = &"MenuItemLabel"
	position.x = SELECTED_INDENT if selected and not disabled else 0.0


## 铁条：只换文字档位和光标位置（条身在 _draw_strip 里按状态画）。
func _refresh_strip() -> void:
	if disabled:
		_label.theme_type_variation = &"MenuItemLabelDisabled"
	elif selected:
		_label.theme_type_variation = &"MenuItemLabelSelected"
	else:
		_label.theme_type_variation = &"MenuItemLabel"
	var lit := selected and not disabled
	var tx := _cursor_x + (0.0 if lit else -8.0)
	if _cursor.position.x != tx and is_inside_tree():
		if _cursor_tween != null and _cursor_tween.is_valid():
			_cursor_tween.kill()
		_cursor_tween = create_tween()
		_cursor_tween.tween_property(_cursor, "position:x", tx, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_brazier.modulate.a = 1.0 if lit else 0.0
	_apply_shift(lit)


## 选中条向右抽出 4px。容器重排会把 position 重置回 0，NOTIFICATION_RESIZED 里补回来。
func _apply_shift(lit: bool, instant: bool = false) -> void:
	if not strip:
		return
	var tx := STRIP_SHIFT if lit else 0.0
	if is_equal_approx(position.x, tx):
		return
	if instant or not is_inside_tree():
		position.x = tx
		return
	if _shift_tween != null and _shift_tween.is_valid():
		_shift_tween.kill()
	_shift_tween = create_tween()
	_shift_tween.tween_property(self, "position:x", tx, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 确认这一格：条身上一道白热闪光扫过（TitleScreen._confirm_effect 调用）。
func flash() -> void:
	if not (strip or lamp) or not is_inside_tree():
		return
	var overlay := ColorRect.new()
	overlay.name = "ConfirmFlash"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var y0 := floorf((HEIGHT - STRIP_H) * 0.5)
	var flash_h := STRIP_H
	var flash_x := 0.0
	var flash_w := size.x
	if lamp:
		# 灯标没有条身：白热只扫过字的那一条，不铺一整块板。
		y0 = floorf(size.y * 0.5 - 10.0)
		flash_h = 20.0
		flash_x = LAMP_LABEL_X
		flash_w = minf(160.0, size.x - flash_x)
	overlay.position = Vector2(flash_x, y0)
	overlay.size = Vector2(flash_w, flash_h)
	overlay.color = Color(1.0, 0.9, 0.68, 0.0)
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	overlay.material = blend
	add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "color:a", 0.55, 0.06)
	tw.tween_property(overlay, "color:a", 0.0, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(overlay.queue_free)


func _refresh_plate() -> void:
	var shape: int = _shape()
	var state := Plate.State.NORMAL
	if disabled:
		state = Plate.State.GHOST_DISABLED if kind == Kind.GHOST else Plate.State.DISABLED
		_label.theme_type_variation = &"MenuItemLabelDisabled"
	elif selected:
		state = Plate.State.GHOST_SELECTED if kind == Kind.GHOST else Plate.State.SELECTED
		_label.theme_type_variation = &"MenuItemLabelSelected"
	else:
		state = Plate.State.GHOST if kind == Kind.GHOST else Plate.State.NORMAL
		_label.theme_type_variation = &"MenuItemLabel"
	_plate.texture = Plate.texture(shape, state)
	# 选中时光标从板内滑进来：只用整数像素，字形不出灰边。连续悬停时先掐掉上一段，
	# 免得两段 tween 抢同一个属性。
	var lit := selected and not disabled
	var tx := _cursor_x + (0.0 if lit else -8.0)
	if _cursor.position.x != tx and is_inside_tree():
		if _cursor_tween != null and _cursor_tween.is_valid():
			_cursor_tween.kill()
		_cursor_tween = create_tween()
		_cursor_tween.tween_property(_cursor, "position:x", tx, 0.12) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_brazier.modulate.a = 1.0 if lit else 0.0
