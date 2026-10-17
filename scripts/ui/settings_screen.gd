class_name SettingsScreen
extends CanvasLayer
## 设置界面：声音 / 画面 / 键位三页，标题屏与暂停菜单共用（与 ControlsPanel 同一套挂法）。
##
## 一切走 Settings 自动加载：音量、震屏与闪光强度、键位改动立刻生效并落盘，
## 不在这里重复实现总线或键位逻辑。滑条拖动期间只改内存，松手 / 停手 SAVE_DELAY 秒后
## 才写一次文件（Settings.set_* 的 persist 参数），关闭界面时一定冲刷。
##
## 操作：
##   · 键鼠 / 手柄 / 触屏全部走 Godot 原生焦点：↑↓ 换行，←→ 调滑条（在标签行上换页），
##     Enter / 点击确认，Esc 返回；悬停即选中。所有可点元素 ≥ UiKit.TOUCH_MIN (52) 高。
##   · 改键：选中一行 → "按下新按键…"，下一个键盘键就是新键；Esc 取消；
##     与别的动作冲突会互换并提示；Esc / 回车保留。PageUp / PageDown（手柄肩键）换页。
##   · 从暂停菜单打开时不会取消暂停：本层只管自己的显示，树的暂停状态不碰。

signal closed

const TAB_AUDIO := 0
const TAB_DISPLAY := 1
const TAB_KEYS := 2
const TAB_TITLES: Array[String] = ["声 音", "画 面", "键 位"]

const STEP := 5.0
const SAVE_DELAY := 0.5
const NOTICE_HOLD := 4.0
const ROW_WIDTH := 700.0
const KEY_COLUMN_WIDTH := 480.0
const PAGE_HEIGHT := 330.0
const TICK_INTERVAL := 0.045

const BUS_NAMES := {
	&"Master": "主音量",
	&"Music": "音乐",
	&"Sfx": "音效",
	&"Ambience": "氛围",
}

## 提示开关等没有专属接口的选项走 Settings.value；键名与各系统约定一致。
const OPT_FULLSCREEN := &"fullscreen"
const OPT_SMOOTHING := &"pixel_smoothing"

var _root: Control
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tab := TAB_AUDIO
var _notice: Label
var _back: Button
var _reset_keys: Button
var _viewport_label: Label

var _sliders: Dictionary = {}       # id(StringName) -> HSlider
var _value_labels: Dictionary = {}  # id -> Label
var _row_bgs: Dictionary = {}       # id -> Panel
var _toggles: Dictionary = {}       # id -> Button
var _key_buttons: Dictionary = {}   # action -> Button
var _key_caps: Dictionary = {}      # action -> Label

var _capturing: StringName = &""
var _dirty := false
var _save_left := 0.0
var _notice_left := 0.0
var _tick_cool := 0.0
var _building := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)
	Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	flush()
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


# --- 构建 ---------------------------------------------------------------------

func _build() -> void:
	_building = true
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiKit.extras_theme()
	add_child(_root)
	_root.add_child(UiKit.scrim(0.90, 0.90, 0.90))

	var frame := UiKit.panel(&"OrnatePanel")
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 100.0
	frame.offset_right = -100.0
	frame.offset_top = 24.0
	frame.offset_bottom = -24.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)
	column.add_child(UiKit.label("设 置", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TAB_TITLES.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = TAB_TITLES[i]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_ALL
		tab.custom_minimum_size = Vector2(190.0, UiKit.TOUCH_MIN)
		tab.pressed.connect(_select_tab.bind(i))
		# 键盘 / 手柄在标签行上左右移动就是换页；鼠标悬停不换页，点击才换。
		tab.focus_entered.connect(_select_tab.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	var host := Control.new()
	host.name = "Pages"
	host.custom_minimum_size = Vector2(0.0, PAGE_HEIGHT)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(host)
	_pages.append(_build_audio_page(host))
	_pages.append(_build_display_page(host))
	_pages.append(_build_keys_page(host))

	_notice = UiKit.label("", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_notice.name = "Notice"
	_notice.custom_minimum_size = Vector2(0.0, 30.0)
	column.add_child(_notice)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	_reset_keys = _footer_button("恢复默认键位", &"ResetKeys")
	_reset_keys.pressed.connect(_on_reset_keys)
	footer.add_child(_reset_keys)
	_back = _footer_button("返 回", &"Back")
	_back.pressed.connect(close)
	footer.add_child(_back)

	column.add_child(UiKit.label("↑↓ 选择 · ←→ 调整 · Enter 确认 · Esc 返回",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_building = false
	_wire_focus()
	_sync_all()
	_show_page(TAB_AUDIO)


## 页面第一行 ↑ 回到"自己的"标签，标签 ↓ 进自己页的第一行——不靠几何距离猜，
## 否则居中的第一行向上会跳到中间那个标签，顺手把页换了。
func _wire_focus() -> void:
	for i in _pages.size():
		var first := _page_controls(_pages[i])
		if first.is_empty():
			continue
		var top_row: Array[Control] = [first[0]]
		# 键位页的第一行是左右两个按钮。
		if i == TAB_KEYS and first.size() > 1:
			top_row.append(first[1])
		for control in top_row:
			control.focus_neighbor_top = control.get_path_to(_tab_buttons[i])
		_tab_buttons[i].focus_neighbor_bottom = _tab_buttons[i].get_path_to(first[0])


func _page_controls(page: Control) -> Array[Control]:
	var out: Array[Control] = []
	for node in page.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode == Control.FOCUS_ALL:
			out.append(control)
	return out


func _footer_button(text: String, node_name: StringName) -> Button:
	var button := Button.new()
	button.name = String(node_name)
	button.text = text
	button.theme_type_variation = &"SettingsButton"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(230.0, UiKit.TOUCH_MIN)
	button.mouse_entered.connect(button.grab_focus)
	return button


func _page(host: Control, node_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = node_name
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.alignment = BoxContainer.ALIGNMENT_BEGIN
	page.add_theme_constant_override("separation", 6)
	host.add_child(page)
	return page


func _build_audio_page(host: Control) -> Control:
	var page := _page(host, "AudioPage")
	for bus in Settings.VOLUME_BUSES:
		# 总线不在布局里（音频包还没加 Music 时）就不摆出一个没用的滑条。
		if AudioServer.get_bus_index(bus) < 0:
			continue
		page.add_child(_slider_row(bus, String(BUS_NAMES.get(bus, String(bus)))))
	return page


func _build_display_page(host: Control) -> Control:
	var page := _page(host, "DisplayPage")
	page.add_child(_toggle_row(OPT_FULLSCREEN, "全 屏"))
	page.add_child(_toggle_row(OPT_SMOOTHING, "像 素 平 滑"))
	page.add_child(_slider_row(&"shake", "震 屏 强 度"))
	page.add_child(_slider_row(&"flash", "闪 光 强 度"))
	page.add_child(_toggle_row(HintService.SETTING_ENABLED, "教 学 提 示"))
	_viewport_label = UiKit.label("", &"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_viewport_label.name = "ViewportInfo"
	page.add_child(_viewport_label)
	return page


func _build_keys_page(host: Control) -> Control:
	var page := _page(host, "KeysPage")
	var grid := GridContainer.new()
	grid.name = "KeyGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	# 左列 5 行、右列 4 行，先按列填：Godot 的 GridContainer 逐行放，所以交错排。
	var actions: Array[StringName] = Settings.REBINDABLE
	var left_count := int(ceil(actions.size() / 2.0))
	for i in left_count:
		grid.add_child(_key_row(actions[i]))
		if i + left_count < actions.size():
			grid.add_child(_key_row(actions[i + left_count]))
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(KEY_COLUMN_WIDTH, 0.0)
			grid.add_child(spacer)
	var note := UiKit.label("方向键、K、鼠标与触控保持原样 · 键位按物理位置记录",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER)
	page.add_child(note)
	return page


## 行底（Panel）+ 内容。焦点 / 悬停时行底换成"选中"贴图，名字变琥珀色。
func _row_bg() -> Panel:
	var bg := Panel.new()
	bg.name = "Bg"
	bg.theme_type_variation = &"SettingsRowNormal"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


func _row_content(row: Control) -> HBoxContainer:
	var content := HBoxContainer.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20.0
	content.offset_right = -20.0
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)
	return content


func _name_label(text: String, width: float) -> Label:
	var label := UiKit.label(text, &"BodyLabel")
	label.name = "Name"
	label.custom_minimum_size = Vector2(width, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _slider_row(id: StringName, title: String) -> Control:
	var row := Control.new()
	row.name = "Row_%s" % String(id)
	row.custom_minimum_size = Vector2(ROW_WIDTH, UiKit.TOUCH_MIN)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := _row_bg()
	row.add_child(bg)
	_row_bgs[id] = bg
	var content := _row_content(row)
	content.add_child(_name_label(title, 170.0))
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = STEP
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.custom_minimum_size = Vector2(240.0, UiKit.TOUCH_MIN)
	slider.value_changed.connect(_on_slider_changed.bind(id))
	slider.drag_ended.connect(_on_slider_drag_ended)
	slider.focus_entered.connect(_set_row_focus.bind(id, true))
	slider.focus_exited.connect(_set_row_focus.bind(id, false))
	slider.mouse_entered.connect(slider.grab_focus)
	content.add_child(slider)
	var value := UiKit.label("100%", &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Value"
	value.custom_minimum_size = Vector2(76.0, 0.0)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(value)
	_sliders[id] = slider
	_value_labels[id] = value
	return row


## 整行就是一个按钮：名字在左，当前值在右。
func _button_row(id: StringName, title: String, width: float) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"SettingsButton"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(width, UiKit.TOUCH_MIN)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.mouse_entered.connect(button.grab_focus)
	var content := _row_content(button)
	content.add_child(_name_label(title, 190.0 if width > 600.0 else 170.0))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	var value := UiKit.label("", &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(value)
	return button


func _toggle_row(id: StringName, title: String) -> Control:
	var button := _button_row(id, title, ROW_WIDTH)
	button.name = "Toggle_%s" % String(id)
	button.pressed.connect(_on_toggle_pressed.bind(id))
	_toggles[id] = button
	_value_labels[id] = button.get_node("Content/Value")
	return button


func _key_row(action: StringName) -> Control:
	var button := _button_row(action, KeyLabels.action_name(action), KEY_COLUMN_WIDTH)
	button.name = "Key_%s" % String(action)
	button.pressed.connect(_on_key_pressed.bind(action))
	_key_buttons[action] = button
	_key_caps[action] = button.get_node("Content/Value")
	return button


# --- 同步显示 ------------------------------------------------------------------

func _sync_all() -> void:
	for id in _sliders:
		_sync_slider(id)
	for id in _toggles:
		_sync_toggle(id)
	_sync_keys()
	if _viewport_label != null:
		_viewport_label.text = "视口 %s · 整数倍像素缩放" % DisplayFit.get_resolution_string()


func _slider_percent(id: StringName) -> float:
	match id:
		&"shake":
			return Settings.shake_scale * 100.0
		&"flash":
			return Settings.flash_scale * 100.0
		_:
			return Settings.volume_percent(id)


func _sync_slider(id: StringName) -> void:
	var slider := _sliders[id] as HSlider
	var pct := _slider_percent(id)
	slider.set_value_no_signal(pct)
	(_value_labels[id] as Label).text = "%d%%" % int(round(pct))


func _toggle_state(id: StringName) -> bool:
	match id:
		OPT_FULLSCREEN:
			return DisplayFit.is_fullscreen()
		OPT_SMOOTHING:
			return GamePresentation.pixel_smoothing
		_:
			return bool(Settings.value(id, true))


func _sync_toggle(id: StringName) -> void:
	(_value_labels[id] as Label).text = "开" if _toggle_state(id) else "关"


func _sync_keys() -> void:
	for action in _key_caps:
		var cap := _key_caps[action] as Label
		if action == _capturing:
			cap.text = "按下新按键…"
		else:
			cap.text = KeyLabels.label(action)


func _set_row_focus(id: StringName, focused: bool) -> void:
	var bg := _row_bgs.get(id) as Panel
	if bg != null:
		bg.theme_type_variation = &"SettingsRowFocused" if focused else &"SettingsRowNormal"


func _on_setting_changed(key: StringName) -> void:
	if _building or _root == null:
		return
	if key == &"keys":
		_sync_keys()


# --- 页面 ----------------------------------------------------------------------

func current_tab() -> int:
	return _tab


func _select_tab(index: int) -> void:
	if _building or index == _tab and _pages[index].visible:
		return
	_cancel_capture()
	_show_page(index)
	UiKit.sfx(&"ui_tick", &"ui_move")


func _show_page(index: int) -> void:
	_tab = clampi(index, 0, _pages.size() - 1)
	for i in _pages.size():
		_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(false)
	_tab_buttons[_tab].set_pressed_no_signal(true)
	_reset_keys.visible = _tab == TAB_KEYS
	if _viewport_label != null and _tab == TAB_DISPLAY:
		_viewport_label.text = "视口 %s · 整数倍像素缩放" % DisplayFit.get_resolution_string()


## 当前页第一个能拿焦点的控件。
func first_control() -> Control:
	for node in _pages[_tab].find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	return null


func _focus_first() -> void:
	var first := first_control()
	if first != null:
		first.grab_focus()


# --- 开合 ----------------------------------------------------------------------

func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_cancel_capture()
	_notice.text = ""
	_sync_all()
	_show_page(TAB_AUDIO)
	visible = true
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_select")
	# 可见之后才能拿焦点。
	_focus_first.call_deferred()


func close() -> void:
	if not visible:
		return
	_cancel_capture()
	flush()
	visible = false
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_back")
	closed.emit()


## 把还没落盘的改动写出去（拖动期间只改内存）。
func flush() -> void:
	if _dirty:
		_dirty = false
		_save_left = 0.0
		Settings.save_settings()


func _mark_dirty() -> void:
	_dirty = true
	_save_left = SAVE_DELAY


func _process(delta: float) -> void:
	_tick_cool = maxf(0.0, _tick_cool - delta)
	if _dirty:
		_save_left -= delta
		if _save_left <= 0.0:
			flush()
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0 and _capturing == &"":
			_notice.text = ""


func _say(text: String) -> void:
	_notice.text = text
	_notice_left = NOTICE_HOLD


# --- 滑条 / 开关 ---------------------------------------------------------------

func _on_slider_changed(value: float, id: StringName) -> void:
	if _building:
		return
	match id:
		&"shake":
			Settings.set_shake_scale(value / 100.0, false)
		&"flash":
			Settings.set_flash_scale(value / 100.0, false)
		_:
			Settings.set_volume_percent(id, value, false)
	(_value_labels[id] as Label).text = "%d%%" % int(round(value))
	_mark_dirty()
	if _tick_cool <= 0.0:
		_tick_cool = TICK_INTERVAL
		UiKit.sfx(&"ui_tick", &"ui_move")


func _on_slider_drag_ended(_changed: bool) -> void:
	flush()


func _on_toggle_pressed(id: StringName) -> void:
	_cancel_capture()
	match id:
		OPT_FULLSCREEN:
			DisplayFit.toggle_fullscreen()
			Settings.set_value(OPT_FULLSCREEN, DisplayFit.is_fullscreen())
		OPT_SMOOTHING:
			GamePresentation.set_pixel_smoothing(not GamePresentation.pixel_smoothing)
			Settings.set_value(OPT_SMOOTHING, GamePresentation.pixel_smoothing)
		_:
			Settings.set_value(id, not bool(Settings.value(id, true)))
	_sync_toggle(id)
	if _viewport_label != null:
		_viewport_label.text = "视口 %s · 整数倍像素缩放" % DisplayFit.get_resolution_string()
	UiKit.sfx(&"ui_select")


# --- 改键 ----------------------------------------------------------------------

func capturing() -> StringName:
	return _capturing


func _on_key_pressed(action: StringName) -> void:
	if _capturing == action:
		_cancel_capture()
		return
	begin_capture(action)


func begin_capture(action: StringName) -> void:
	if not Settings.REBINDABLE.has(action):
		return
	_capturing = action
	_sync_keys()
	_say("按下「%s」的新按键 · Esc 取消" % KeyLabels.action_name(action))
	_notice_left = 0.0  # 抓键期间提示常驻，直到完成或取消


func _cancel_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_sync_keys()
	_notice.text = ""


## 抓键入口：返回 true 表示这个事件被改键流程吃掉了。测试可以直接喂 InputEventKey。
func handle_capture_event(event: InputEvent) -> bool:
	if _capturing == &"":
		return false
	if event.is_action_pressed(&"ui_cancel"):
		_cancel_capture()
		return true
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		# 抓键期间键盘的松开 / 连发也不能漏给界面（空格会触发按钮）。
		return true
	var physical := int(key.physical_keycode)
	if physical == 0:
		# 只带 keycode 的事件（合成输入）：QWERTY 下两者同值。
		physical = int(key.keycode)
	finish_capture(physical)
	return true


func finish_capture(physical: int) -> void:
	var action := _capturing
	if action == &"":
		return
	var result := Settings.rebind_action(action, physical)
	_capturing = &""
	_sync_keys()
	var key_name := KeyLabels.label(action)
	if result == &"reserved":
		_say("这个键不能用（Esc 与 回车 留给菜单）")
	elif result == &"":
		_say("「%s」已改为 %s" % [KeyLabels.action_name(action), key_name])
	else:
		_say("「%s」与「%s」的按键已互换" % [KeyLabels.action_name(action),
				KeyLabels.action_name(result)])


func _on_reset_keys() -> void:
	_cancel_capture()
	Settings.reset_keys()
	_sync_keys()
	_say("键位已恢复默认")
	UiKit.sfx(&"ui_select")


func _input(event: InputEvent) -> void:
	if visible and handle_capture_event(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_down") or _is_shoulder(event, JOY_BUTTON_RIGHT_SHOULDER):
		_step_tab(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_up") or _is_shoulder(event, JOY_BUTTON_LEFT_SHOULDER):
		_step_tab(-1)
		get_viewport().set_input_as_handled()


func _is_shoulder(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed \
			and (event as InputEventJoypadButton).button_index == button


func _step_tab(step: int) -> void:
	_select_tab(posmod(_tab + step, _pages.size()))
	_focus_first()


# --- 测试 / 工具用 -------------------------------------------------------------

func slider_for(id: StringName) -> HSlider:
	return _sliders.get(id) as HSlider


func toggle_for(id: StringName) -> Button:
	return _toggles.get(id) as Button


func key_button_for(action: StringName) -> Button:
	return _key_buttons.get(action) as Button


func key_cap_text(action: StringName) -> String:
	return (_key_caps[action] as Label).text if _key_caps.has(action) else ""


func notice_text() -> String:
	return _notice.text


func back_button() -> Button:
	return _back


func tab_button(index: int) -> Button:
	return _tab_buttons[index]


func show_tab(index: int) -> void:
	_select_tab(index)
