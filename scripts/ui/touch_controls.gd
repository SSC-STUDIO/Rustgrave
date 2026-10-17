class_name TouchControls
extends CanvasLayer
## On-screen rust/ember pad for phones and tablets.
##
## Lives on the UI host (1280×720 design), not inside the 640×360 world viewport.
## Presses the same InputMap actions keyboard/mouse already use.

const BTN := 56.0
const BTN_LG := 68.0
const GAP := 10.0
const EDGE := 18.0

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
	# Right: Attack (large) + Jump / Dash / Interact in a compact diamond.
	var host := Control.new()
	host.name = "ActionCluster"
	host.anchor_left = 1.0
	host.anchor_right = 1.0
	host.anchor_top = 1.0
	host.anchor_bottom = 1.0
	host.offset_left = -(EDGE + BTN_LG + GAP + BTN)
	host.offset_right = -EDGE
	host.offset_top = -(EDGE + BTN_LG + GAP + BTN)
	host.offset_bottom = -EDGE
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(host)

	var attack := _make_button(&"attack", "斩", BTN_LG, false)
	attack.position = Vector2(BTN + GAP, BTN + GAP)
	attack.size = Vector2(BTN_LG, BTN_LG)
	host.add_child(attack)

	var jump := _make_button(&"jump", "跳", BTN, false)
	jump.position = Vector2(BTN + GAP + (BTN_LG - BTN) * 0.5, 0.0)
	jump.size = Vector2(BTN, BTN)
	host.add_child(jump)

	var dash := _make_button(&"dash", "冲", BTN, false)
	dash.position = Vector2(0.0, BTN + GAP + (BTN_LG - BTN) * 0.5)
	dash.size = Vector2(BTN, BTN)
	host.add_child(dash)

	var interact := _make_button(&"interact", "互", BTN, false)
	interact.position = Vector2(BTN + GAP + BTN_LG - BTN * 0.25,
			BTN + GAP + BTN_LG - BTN * 0.25)
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
	var w := BTN * 3.0 + GAP * 1.6
	row.offset_left = -(EDGE + w)
	row.offset_right = -EDGE
	row.offset_top = -(EDGE + BTN_LG + GAP + BTN + GAP + BTN * 0.85)
	row.offset_bottom = -(EDGE + BTN_LG + GAP + BTN + GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(row)
	row.add_child(_make_button(&"hookshot", "钩", BTN * 0.85, true))
	row.add_child(_make_button(&"socket_1", "1", BTN * 0.85, true))
	row.add_child(_make_button(&"socket_2", "2", BTN * 0.85, true))


func _add_pause_button() -> void:
	# PauseMenu listens for ui_cancel *events*, not Input.action_press — toggle directly.
	var pause_btn := _make_button(&"", "Ⅱ", BTN * 0.85, false, true)
	pause_btn.name = "PauseButton"
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_btn.grow_vertical = Control.GROW_DIRECTION_END
	pause_btn.offset_left = -(EDGE + BTN * 0.85)
	pause_btn.offset_right = -EDGE
	pause_btn.offset_top = EDGE
	pause_btn.offset_bottom = EDGE + BTN * 0.85
	_pad.add_child(pause_btn)


func _make_button(action: StringName, caption: String, size: float,
		tap_release: bool, is_pause: bool = false) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.theme_type_variation = &"MenuRowNormal"
	wrap.focus_mode = Control.FOCUS_NONE

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
	wrap.theme_type_variation = &"MenuRowSelected" if down else &"MenuRowNormal"
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


func _apply_safe_area() -> void:
	if _pad == null:
		return
	var insets := TouchInput.safe_insets_ui(get_tree().root)
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
