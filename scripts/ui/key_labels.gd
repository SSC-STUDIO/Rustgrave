class_name KeyLabels
extends Object
## 键位文案的唯一出口：界面里任何一处"按 X"都从 Settings 取，改键后自动跟随。
## 提示模板里用 {action} 占位，例如 "按 {socket_1} / {socket_2} 镶核"。

const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_GAMEPAD := &"gamepad"

## 玩家可见的动作名（设置 → 键位、操作说明共用）。
const ACTION_NAMES := {
	&"move_left": "向左移动",
	&"move_right": "向右移动",
	&"jump": "跳跃",
	&"dash": "冲刺",
	&"attack": "挥砍",
	&"interact": "交互",
	&"socket_1": "镶入 1 号插座",
	&"socket_2": "镶入 2 号插座",
	&"hookshot": "钩锁",
	&"skill_1": "主动技能 1",
	&"skill_2": "主动技能 2",
	&"map": "地图",
}

## OS.get_keycode_string 给的是英文名，这里把常见的几个换成界面里已经在用的写法。
const PRETTY := {
	"Space": "空格",
	"Escape": "Esc",
	"Left": "←",
	"Right": "→",
	"Up": "↑",
	"Down": "↓",
	"Enter": "回车",
	"Backspace": "退格",
	"Tab": "Tab",
	"Shift": "Shift",
	"Ctrl": "Ctrl",
	"Alt": "Alt",
}

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "十字上",
	JOY_BUTTON_DPAD_DOWN: "十字下",
	JOY_BUTTON_DPAD_LEFT: "十字左",
	JOY_BUTTON_DPAD_RIGHT: "十字右",
}

static var _device: StringName = DEVICE_KEYBOARD


static func device() -> StringName:
	return _device


static func is_gamepad() -> bool:
	return _device == DEVICE_GAMEPAD


static func set_device(dev: StringName) -> void:
	var next := DEVICE_GAMEPAD if dev == DEVICE_GAMEPAD else DEVICE_KEYBOARD
	if _device == next:
		return
	_device = next
	if is_instance_valid(Settings):
		Settings.changed.emit(&"keys")


static func notify_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			set_device(DEVICE_GAMEPAD)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= 0.35:
			set_device(DEVICE_GAMEPAD)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			set_device(DEVICE_KEYBOARD)
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			set_device(DEVICE_KEYBOARD)


static func pretty(raw: String) -> String:
	return String(PRETTY.get(raw, raw))


static func pad_token_label(token: String) -> String:
	if token.is_empty():
		return "—"
	if token.begins_with("btn:"):
		var idx := int(token.substr(4))
		return String(PAD_BUTTON_NAMES.get(idx, "手柄%d" % idx))
	if token.begins_with("axis:"):
		var parts := token.split(":")
		if parts.size() >= 3:
			var axis := int(parts[1])
			var dir := int(parts[2])
			match axis:
				JOY_AXIS_LEFT_X:
					return "左摇杆左" if dir < 0 else "左摇杆右"
				JOY_AXIS_LEFT_Y:
					return "左摇杆上" if dir < 0 else "左摇杆下"
				JOY_AXIS_RIGHT_X:
					return "右摇杆左" if dir < 0 else "右摇杆右"
				JOY_AXIS_RIGHT_Y:
					return "右摇杆上" if dir < 0 else "右摇杆下"
				JOY_AXIS_TRIGGER_LEFT:
					return "LT"
				JOY_AXIS_TRIGGER_RIGHT:
					return "RT"
				_:
					return "轴%d%s" % [axis, "-" if dir < 0 else "+"]
	return token


## 当前激活设备（键鼠 / 手柄）下绑定在 action 上的首个按键（Settings 说了算）。
static func label(action: StringName) -> String:
	if _device == DEVICE_GAMEPAD:
		return Settings.pad_label(action)
	return pretty(Settings.key_label(action))


static func keyboard_label(action: StringName) -> String:
	return pretty(Settings.key_label(action))


static func gamepad_label(action: StringName) -> String:
	return Settings.pad_label(action)


static func action_name(action: StringName) -> String:
	return String(ACTION_NAMES.get(action, String(action)))


## InputMap 里 action 的其余键盘键（箭头、K 之类 Settings 不改的备用键），
## 已经与首键重复的会被去掉。
static func extra_keys(action: StringName) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	var first := keyboard_label(action)
	var skipped_first := false
	for event in InputMap.action_get_events(action):
		if not event is InputEventKey:
			continue
		if not skipped_first:
			skipped_first = true
			continue
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var text := pretty(OS.get_keycode_string(code))
		if text != first and not out.has(text):
			out.append(text)
	return out


## 把模板里的 {action} 换成当前键名；未知占位原样保留，便于一眼看出写错。
## On-screen pad captions (TouchControls): touch sessions name the button, not a key.
const TOUCH_CAPS := {
	&"attack": "斩", &"jump": "跳", &"dash": "冲", &"interact": "互",
	&"hookshot": "钩", &"socket_1": "1", &"socket_2": "2",
}


static func format(template: String) -> String:
	if not template.contains("{"):
		return template
	var out := template
	var touch := TouchInput.wants_overlay()
	for action in Settings.REBINDABLE:
		var token := "{%s}" % String(action)
		if out.contains(token):
			out = out.replace(token, touch_label(action) if touch and TOUCH_CAPS.has(action) else label(action))
	return out


## 「斩」-style caption of the pad button for an action.
static func touch_label(action: StringName) -> String:
	return "「%s」" % String(TOUCH_CAPS.get(action, String(action)))


## 其他系统硬编码的交互提示（"E 点燃余烬巢"）开头那个 "E " 换成当前交互键。
static func localize_prompt(text: String) -> String:
	if text.begins_with("E "):
		if TouchInput.wants_overlay():
			return touch_label(&"interact") + text.substr(1)
		return label(&"interact") + text.substr(1)
	return text


## 交互提示拆成"键帽 + 文案"两段，交给 HUD 画成[S] 点燃余烬巢。
##   · 键位取自 Settings（改键后自动跟随），和设置页的键位列同一个出口；
##   · 触屏上换成触控板那颗交互键的字（"互"），提示里就不再出现按不到的 E；
##   · 不带键位的提示（"门已锁住"）返回空键帽，HUD 只画一行文案。
static func prompt_parts(text: String) -> Dictionary:
	if text.begins_with("E "):
		var key := "互" if TouchInput.wants_overlay() else label(&"interact")
		return {"key": key, "body": text.substr(2).strip_edges()}
	return {"key": "", "body": text}
