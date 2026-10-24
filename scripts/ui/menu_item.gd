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
const LAND_SHIFT := 28.0
const STRIP_RUST := Color("#8B4513")
const STRIP_IRON := Color("#4A3E44")
const STRIP_EMBER := Color("#FFC14A")

## 菜单项 id（MenuList.add_item 写入；标题测试/旧调用按它读行）。
var id: StringName = &""
## 标题屏的紧凑板：同样的三档形状，映射到更矮更短的一组 SPECS。
var compact := false
## 铁条版式（MenuList.strip_style 在 add_child 之前写入）。
var strip := false
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
var _cursor: TextureRect
var _brazier: Node2D
var _time := 0.0
var _cursor_x := 0.0
var _cursor_tween: Tween


func _init(text: String = "", item_kind: Kind = Kind.DEFAULT) -> void:
	_text = text
	kind = item_kind


func _ready() -> void:
	if kind == Kind.DEFAULT:
		_build_default_row()
	elif strip:
		_build_strip_row()
	else:
		_build_plate_row()
	mouse_entered.connect(func() -> void:
		if not disabled:
			hover_requested.emit())
	_refresh()


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
	_note.position = Vector2(width - 120.0, 0.0)
	_note.size = Vector2(104.0, HEIGHT)
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.visible = false
	add_child(_note)
	_brazier = UiKit.EmberField.build(Rect2(STRIP_CURSOR_X - 8.0, 8.0, 28.0, HEIGHT - 16.0), 3, 0)
	add_child(_brazier)
	_cursor = UiKit.sprite_rect(UiKit.TEX_CURSOR)
	var art := _cursor.texture
	var cursor_h := art.get_height() if art != null else 28
	_cursor_x = STRIP_CURSOR_X
	_cursor.position = Vector2(_cursor_x - 8.0, (HEIGHT - cursor_h) * 0.5)
	add_child(_cursor)


## 条右端的小字（例如试炼未解锁时的"第七章后解锁"）；空串 = 不显示。
func set_note(value: String) -> void:
	if _note == null:
		return
	_note.text = value
	_note.visible = value != ""


func _apply_land() -> void:
	if _label == null or not strip:
		return
	var ox := -land * LAND_SHIFT
	_label.position.x = STRIP_LABEL_X + ox
	if _note != null:
		_note.position.x = size.x - 120.0 + ox
	queue_redraw()


func set_text(value: String) -> void:
	_text = value
	if _label != null:
		_label.text = value


func _process(delta: float) -> void:
	if not selected or disabled:
		return
	_time += delta
	var breath := lerpf(BREATH_MIN, BREATH_MAX, 0.5 + 0.5 * sin(TAU * _time / BREATH_PERIOD))
	# 只动 rgb：alpha 留给开屏淡入用，每帧整体覆盖会把淡入吃掉。
	modulate = Color(breath, breath, breath, modulate.a)


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


func _draw() -> void:
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


func _refresh() -> void:
	if _label == null:
		return
	if kind == Kind.DEFAULT:
		_refresh_default()
	elif strip:
		_refresh_strip()
		queue_redraw()
	else:
		_refresh_plate()
		queue_redraw()
	var lit := selected and not disabled
	_cursor.visible = lit
	_brazier.visible = lit
	if not lit:
		modulate = Color.WHITE
		_time = 0.0
	set_process(lit)


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
