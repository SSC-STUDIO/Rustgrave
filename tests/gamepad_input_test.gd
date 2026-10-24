extends TestCase
## 手柄映射、轴死区、手柄改键往返与 KeyLabels 设备切换测试。

const TEST_PATH := "user://rustgrave_test_gamepad_settings.cfg"

var _old_path := ""


func setup() -> void:
	_old_path = Settings.save_path
	Settings.save_path = TEST_PATH
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")
	KeyLabels.set_device(KeyLabels.DEVICE_KEYBOARD)
	Settings.load_settings()


func teardown() -> void:
	KeyLabels.set_device(KeyLabels.DEVICE_KEYBOARD)
	Settings.reset_keys(false)
	Settings.save_path = _old_path
	Settings.load_settings()
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_every_rebindable_action_has_default_gamepad_binding() -> void:
	for action in Settings.REBINDABLE:
		var tok := Settings.default_pad_for(action)
		ok(not tok.is_empty(), "%s 默认配有手柄输入 (%s)" % [String(action), tok])
		var ev := Settings.decode_pad_token(tok)
		ok(ev != null, "%s 手柄编码可反解" % String(action))
		if ev != null:
			ok(ev.is_action_pressed(action), "%s 手柄事件能触发 InputMap 动作" % String(action))


func test_start_and_escape_cancel_without_consuming_skill_button() -> void:
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	ok(start.is_action_pressed(&"ui_cancel"), "真实 Start 事件映射到暂停 / 返回")
	eq(Settings.rebind_pad_action(&"jump", start, false), &"reserved", "Start 仍不可重绑")

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	ok(escape.is_action_pressed(&"ui_cancel"), "Esc 仍映射到暂停 / 返回")
	eq(Settings.rebind_action(&"jump", KEY_ESCAPE, false), &"reserved", "Esc 仍不可重绑")

	var skill := InputEventJoypadButton.new()
	skill.button_index = JOY_BUTTON_B
	skill.pressed = true
	ok(skill.is_action_pressed(&"skill_1"), "B 继续触发技能 1")
	ok(not skill.is_action_pressed(&"ui_cancel"), "B 不触发暂停 / 返回")


func test_move_axis_deadzone_filters_stick_drift() -> void:
	almost(InputMap.action_get_deadzone(&"move_left"), 0.2, 0.01, "move_left 死区为 0.2")
	almost(InputMap.action_get_deadzone(&"move_right"), 0.2, 0.01, "move_right 死区为 0.2")

	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = -0.12
	ok(not drift.is_action_pressed(&"move_left"), "小于死区的摇杆漂移不触发 move_left")
	almost(drift.get_action_strength(&"move_left"), 0.0, 0.001, "死区内动作强度为 0")

	var push_left := InputEventJoypadMotion.new()
	push_left.axis = JOY_AXIS_LEFT_X
	push_left.axis_value = -0.85
	ok(push_left.is_action_pressed(&"move_left"), "跨过死区的左推摇杆触发 move_left")
	ok(push_left.get_action_strength(&"move_left") > 0.5, "跨过死区后动作强度有效")

	var push_right := InputEventJoypadMotion.new()
	push_right.axis = JOY_AXIS_LEFT_X
	push_right.axis_value = 0.85
	ok(push_right.is_action_pressed(&"move_right"), "跨过死区的右推摇杆触发 move_right")

	var dpad_left := InputEventJoypadButton.new()
	dpad_left.button_index = JOY_BUTTON_DPAD_LEFT
	dpad_left.pressed = true
	ok(dpad_left.is_action_pressed(&"move_left"), "十字键左也能触发 move_left")


func test_gamepad_rebind_swaps_persists_and_resets() -> void:
	var default_jump := Settings.default_pad_for(&"jump")
	var default_attack := Settings.default_pad_for(&"attack")
	eq(default_jump, "btn:%d" % JOY_BUTTON_A)
	eq(default_attack, "btn:%d" % JOY_BUTTON_X)

	# 把 jump 改到 X（原属 attack）应触发互换
	var swapped := Settings.rebind_pad_action(&"jump", JOY_BUTTON_X)
	eq(swapped, &"attack", "手柄按键冲突时与原动作互换")
	eq(Settings.pad_for(&"jump"), "btn:%d" % JOY_BUTTON_X)
	eq(Settings.pad_for(&"attack"), "btn:%d" % JOY_BUTTON_A)

	# 落盘后重读仍保持手柄改键
	Settings.load_settings()
	eq(Settings.pad_for(&"jump"), "btn:%d" % JOY_BUTTON_X, "重读设置后 jump 仍为 X")
	eq(Settings.pad_for(&"attack"), "btn:%d" % JOY_BUTTON_A, "重读设置后 attack 仍为 A")

	var ev_x := InputEventJoypadButton.new()
	ev_x.button_index = JOY_BUTTON_X
	ev_x.pressed = true
	ok(ev_x.is_action_pressed(&"jump"), "X 现在触发 jump")

	# Start 键保留给菜单，拒绝绑定
	eq(Settings.rebind_pad_action(&"jump", JOY_BUTTON_START, false), &"reserved")

	# 恢复默认同时还原手柄映射
	Settings.reset_keys()
	Settings.load_settings()
	eq(Settings.pad_for(&"jump"), default_jump, "恢复默认后 jump 回到 A")
	eq(Settings.pad_for(&"attack"), default_attack, "恢复默认后 attack 回到 X")


func test_settings_screen_captures_gamepad_button_and_axis() -> void:
	var screen := SettingsScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_tab(SettingsScreen.TAB_KEYS)
	await get_tree().process_frame

	screen.begin_capture(&"jump")
	eq(screen.capturing(), &"jump")
	var btn := InputEventJoypadButton.new()
	btn.button_index = JOY_BUTTON_Y
	btn.pressed = true
	ok(screen.handle_capture_event(btn), "设置页抓键吃掉手柄按键")
	eq(screen.capturing(), &"")
	eq(Settings.pad_for(&"jump"), "btn:%d" % JOY_BUTTON_Y)
	eq(KeyLabels.device(), KeyLabels.DEVICE_GAMEPAD, "手柄抓键后自动切到手柄提示")
	eq(screen.key_cap_text(&"jump"), "Y", "键帽立即显示手柄键名 Y")

	# 抓键支持扳机轴输入
	screen.begin_capture(&"dash")
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_LEFT
	trig.axis_value = 0.9
	ok(screen.handle_capture_event(trig), "设置页抓键吃掉手柄扳机轴")
	eq(Settings.pad_for(&"dash"), "axis:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	eq(screen.key_cap_text(&"dash"), "LT")

	screen.queue_free()
	await get_tree().process_frame


func test_key_labels_switches_between_keyboard_and_gamepad_on_last_input() -> void:
	KeyLabels.set_device(KeyLabels.DEVICE_KEYBOARD)
	eq(KeyLabels.label(&"jump"), "空格")
	eq(KeyLabels.format("按 {jump} 起跳"), "按 空格 起跳")
	eq(KeyLabels.localize_prompt("E 点燃余烬巢"), "E 点燃余烬巢")
	eq(KeyLabels.prompt_parts("E 点燃余烬巢")["key"], "E")

	var pad_ev := InputEventJoypadButton.new()
	pad_ev.button_index = JOY_BUTTON_A
	pad_ev.pressed = true
	KeyLabels.notify_input(pad_ev)
	eq(KeyLabels.device(), KeyLabels.DEVICE_GAMEPAD)
	eq(KeyLabels.label(&"jump"), "A")
	eq(KeyLabels.format("按 {jump} 起跳"), "按 A 起跳")
	eq(KeyLabels.localize_prompt("E 点燃余烬巢"), "Y 点燃余烬巢")
	eq(KeyLabels.prompt_parts("E 点燃余烬巢")["key"], "Y")

	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_SPACE
	key_ev.pressed = true
	KeyLabels.notify_input(key_ev)
	eq(KeyLabels.device(), KeyLabels.DEVICE_KEYBOARD)
	eq(KeyLabels.label(&"jump"), "空格")
	eq(KeyLabels.prompt_parts("E 点燃余烬巢")["key"], "E")
