class_name TouchControls
extends CanvasLayer
## On-screen rust/ember pad for phones and tablets.
##
## Lives on the UI host (1280×720 design), not inside the 640×360 world viewport.
## Presses the same InputMap actions keyboard/mouse already use.

const BTN := 56.0
const BTN_LG := 68.0
## 次级键（钩 / 1 / 2 / 暂停）与 UiKit.TOUCH_MIN 同高，不再缩到 47.6。
const BTN_SUB := 52.0
const GAP := 10.0
const EDGE := 18.0
## 动作簇的边长：大斩 68 + 间隙 10 + 小键 56。四个键都排在这个方框内。
const ACTION_BOX := BTN_LG + GAP + BTN

var _root: Control
var _pad: Control
var _pause_menu: PauseMenu
var _held: Dictionary = {}  # StringName -> true while we own the press
var _visible_wanted := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	WorldClock.isolate_ui_layer(self)
	PresentationMetrics.bind_layer(self)
	_build()
	_refresh_visibility()
	get_tree().root.size_changed.connect(_apply_safe_area)


func bind_pause(menu: PauseMenu) -> void:
	_pause_menu = menu


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_pad = Control.new()
	_pad.name = "Pad"
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pad)

	_add_move_cluster()
	_add_action_cluster()
	_add_secondary_cluster()
	_add_pause_button()
	_apply_safe_area()


func _add_move_cluster() -> void:
	var row := HBoxContainer.new()
	row.name = "MoveCluster"
	row.add_theme_constant_override("separation", int(GAP))
	row.anchor_left = 0.0
	row.anchor_right = 0.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = EDGE
	row.offset_right = EDGE + BTN * 2.0 + GAP
	row.offset_top = -(EDGE + BTN)
	row.offset_bottom = -EDGE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(row)
	row.add_child(_make_button(&"move_left", "←", BTN, false))
	row.add_child(_make_button(&"move_right", "→", BTN, false))


func _add_action_cluster() -> void:
	# 2×2 的动作方块：斩在右下（最大），跳在左下，冲在右上，互在左上。
	# 旧版把"互"放在 120,120 + 56，实际会伸出屏幕右下 24px；这里全部收进
	# ACTION_BOX，任何按键都不越出安全边。
	var host := Control.new()
	host.name = "ActionCluster"
	host.anchor_left = 1.0
	host.anchor_right = 1.0
	host.anchor_top = 1.0
	host.anchor_bottom = 1.0
	host.offset_left = -(EDGE + ACTION_BOX)
	host.offset_right = -EDGE
	host.offset_top = -(EDGE + ACTION_BOX)
	host.offset_bottom = -EDGE
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(host)

	var attack := _make_button(&"attack", "斩", BTN_LG, false)
	attack.position = Vector2(BTN + GAP, BTN + GAP)
	attack.size = Vector2(BTN_LG, BTN_LG)
	host.add_child(attack)

	var jump := _make_button(&"jump", "跳", BTN, false)
	jump.position = Vector2(0.0, BTN + GAP)
	jump.size = Vector2(BTN, BTN)
	host.add_child(jump)

	var dash := _make_button(&"dash", "冲", BTN, false)
	dash.position = Vector2(BTN + GAP, 0.0)
	dash.size = Vector2(BTN, BTN)
	host.add_child(dash)

	var interact := _make_button(&"interact", "互", BTN, false)
	interact.position = Vector2.ZERO
	interact.size = Vector2(BTN, BTN)
	host.add_child(interact)


func _add_secondary_cluster() -> void:
	var row := HBoxContainer.new()
	row.name = "SecondaryCluster"
	row.add_theme_constant_override("separation", int(GAP * 0.8))
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	var w := BTN_SUB * 3.0 + GAP * 1.6
	row.offset_left = -(EDGE + w)
	row.offset_right = -EDGE
	row.offset_top = -(EDGE + ACTION_BOX + GAP + BTN_SUB)
	row.offset_bottom = -(EDGE + ACTION_BOX + GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(row)
	row.add_child(_make_button(&"hookshot", "钩", BTN_SUB, true))
	row.add_child(_make_button(&"socket_1", "1", BTN_SUB, true))
	row.add_child(_make_button(&"socket_2", "2", BTN_SUB, true))


func _add_pause_button() -> void:
	# PauseMenu listens for ui_cancel *events*, not Input.action_press — toggle directly.
	var pause_btn := _make_button(&"", "Ⅱ", BTN_SUB, false, true)
	pause_btn.name = "PauseButton"
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_btn.grow_vertical = Control.GROW_DIRECTION_END
	pause_btn.offset_left = -(EDGE + BTN_SUB)
	pause_btn.offset_right = -EDGE
	pause_btn.offset_top = EDGE
	pause_btn.offset_bottom = EDGE + BTN_SUB
	_pad.add_child(pause_btn)


## 触控钮的铁框：menu_plate 的 TAG 板只改着色透明度（与弹窗卡同一个 GlassKit.CARD_ALPHA）。
## TouchKey = 冷铁环；TouchKeyDown = 余烬环（按下即亮，松开回到冷铁）。
static var _keys: Theme


static func key_theme() -> Theme:
	if _keys == null:
		_keys = Theme.new()
		_keys.set_type_variation(&"TouchKey", &"Panel")
		_keys.set_stylebox("panel", &"TouchKey", _key_box(UiKit.Plate.State.NORMAL))
		_keys.set_type_variation(&"TouchKeyDown", &"Panel")
		_keys.set_stylebox("panel", &"TouchKeyDown", _key_box(UiKit.Plate.State.SELECTED))
	return _keys


static func _key_box(state: int) -> StyleBoxTexture:
	var box := UiKit.Plate.style_box(UiKit.Plate.Shape.TAG, state)
	box.modulate_color = Color(1.0, 1.0, 1.0, GlassKit.CARD_ALPHA)
	# 按钮整块都是字的底：内容边距归零，字由 FULL_RECT 的 KeyCapLabel 居中。
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	return box


func _make_button(action: StringName, caption: String, size: float,
		tap_release: bool, is_pause: bool = false) -> Control:
	var wrap := Panel.new()
	wrap.name = "Btn_%s" % (String(action) if action != &"" else "pause")
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.theme = key_theme()
	wrap.theme_type_variation = &"TouchKey"
	wrap.focus_mode = Control.FOCUS_NONE
	# Tools / tests find a button by what it does, not by its caption.
	wrap.set_meta("action", action)
	wrap.set_meta("pause", is_pause)

	var label := UiKit.label(caption, &"KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(label)

	wrap.gui_input.connect(func(event: InputEvent) -> void:
		_on_pad_input(wrap, action, tap_release, is_pause, event))
	wrap.mouse_exited.connect(func() -> void:
		if not tap_release and not is_pause and action != &"":
			_release_action(action)
			_set_pressed_look(wrap, false))
	return wrap


func _on_pad_input(wrap: Control, action: StringName, tap_release: bool,
		is_pause: bool, event: InputEvent) -> void:
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pressed = touch.pressed
		released = not touch.pressed
	elif event is InputEventMouseButton:
		# On real touchscreens mouse is emulated from the same finger — ignore it
		# so multitouch (hold ← while tapping 斩) is not collapsed to one pointer.
		if TouchInput.has_touchscreen():
			return
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = mouse.pressed
		released = not mouse.pressed
	else:
		return
	if pressed:
		if is_pause:
			_toggle_pause()
			_flash_look(wrap)
		elif tap_release:
			_pulse_action(action)
			_flash_look(wrap)
		else:
			_press_action(action)
			_set_pressed_look(wrap, true)
		wrap.accept_event()
	elif released and not tap_release and not is_pause:
		_release_action(action)
		_set_pressed_look(wrap, false)
		wrap.accept_event()


func _toggle_pause() -> void:
	if _pause_menu == null or not is_instance_valid(_pause_menu):
		return
	if _pause_menu.is_open():
		_pause_menu.close()
	else:
		_pause_menu.open()


func _pulse_action(action: StringName) -> void:
	_press_action(action)
	# Keep just_pressed visible for the current frame; release next idle tick.
	call_deferred("_release_action", action)


func _flash_look(wrap: Control) -> void:
	_set_pressed_look(wrap, true)
	get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if is_instance_valid(wrap):
			_set_pressed_look(wrap, false))

func _set_pressed_look(wrap: Control, down: bool) -> void:
	wrap.theme_type_variation = &"TouchKeyDown" if down else &"TouchKey"
	wrap.modulate = Color(1.15, 0.95, 0.7) if down else Color.WHITE


func _press_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	if _held.has(action):
		return
	Input.action_press(action)
	_held[action] = true


func _release_action(action: StringName) -> void:
	if not _held.has(action):
		return
	if InputMap.has_action(action):
		Input.action_release(action)
	_held.erase(action)


func release_all() -> void:
	var keys: Array = _held.keys()
	for action in keys:
		_release_action(action as StringName)


## 触控按钮（测试与无障碍检查用）：只收真正的可点板，不把装饰 Panel 算进去。
func buttons() -> Array[Control]:
	var out: Array[Control] = []
	if _pad == null:
		return out
	for node in _pad.find_children("*", "Panel", true, false):
		var control := node as Control
		if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append(control)
	return out


func _apply_safe_area() -> void:
	apply_safe_insets(TouchInput.safe_insets_ui(get_tree().root))


## 把刘海/圆角安全区收进触控板：整块 pad 缩进安全区内，簇仍贴安全区的角。
## 公开是为了让 headless 测试喂一组手机边距进来验证按钮不会滑到刘海底下
## （真实刘海值只有设备知道，桌面/headless 都是 0）。
func apply_safe_insets(insets: Vector4) -> void:
	if _pad == null:
		return
	_pad.offset_left = insets.x
	_pad.offset_top = insets.y
	_pad.offset_right = -insets.z
	_pad.offset_bottom = -insets.w


func _pause_open() -> bool:
	return _pause_menu != null and is_instance_valid(_pause_menu) and _pause_menu.is_open()


func _should_show() -> bool:
	if not TouchInput.wants_overlay():
		return false
	if _pause_open():
		return false
	if Director.choice_hold or Director.is_input_locked():
		return false
	return true


func _refresh_visibility() -> void:
	var show := _should_show()
	if show == _visible_wanted and visible == show:
		return
	_visible_wanted = show
	visible = show
	if not show:
		release_all()


func _process(_delta: float) -> void:
	_refresh_visibility()


func _exit_tree() -> void:
	release_all()
