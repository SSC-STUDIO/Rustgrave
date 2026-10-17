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
const SHAPES := {Kind.PRIMARY: Plate.Shape.PRIMARY, Kind.SECONDARY: Plate.Shape.SECONDARY,
		Kind.GHOST: Plate.Shape.GHOST}
const CURSOR_X := {Kind.PRIMARY: 30.0, Kind.SECONDARY: 24.0, Kind.GHOST: 26.0}
## 每格板向左伸出的挂架短钉：接到标题屏的竖脊上，选中时烧成余烬色。
const TICK_LEN := 24.0
const TICK_DIM := Color("#4A2A18")
const TICK_LIT := Color("#FFC14A")

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
func _build_plate_row() -> void:
	var shape: int = SHAPES[kind]
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
	_cursor_x = CURSOR_X[kind]
	_cursor.position = Vector2(_cursor_x - 8.0, (height - cursor_h) * 0.5)
	add_child(_cursor)


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


func _draw() -> void:
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


func _refresh_plate() -> void:
	var shape: int = SHAPES[kind]
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
