class_name KeyLabels
extends Object
## 键位文案的唯一出口：界面里任何一处"按 X"都从 Settings 取，改键后自动跟随。
## 提示模板里用 {action} 占位，例如 "按 {socket_1} / {socket_2} 镶核"。

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
	&"world_map": "地图",
}

## 最近一次输入来自手柄时，提示改画这套键帽（和 Settings 装上的默认手柄一致）。
const PAD_GLYPHS := {
	&"move_left": "←",
	&"move_right": "→",
	&"jump": "A",
	&"dash": "B",
	&"attack": "X",
	&"interact": "Y",
	&"socket_1": "LB",
	&"socket_2": "RB",
	&"hookshot": "RT",
	&"skill_1": "LT",
	&"skill_2": "↑",
	&"world_map": "Select",
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


static func pretty(raw: String) -> String:
	return String(PRETTY.get(raw, raw))


## 当前绑定在 action 上的首个键盘键（Settings 说了算）。
static func label(action: StringName) -> String:
	if Settings.using_gamepad and PAD_GLYPHS.has(action):
		return String(PAD_GLYPHS[action])
	return pretty(Settings.key_label(action))


static func action_name(action: StringName) -> String:
	return String(ACTION_NAMES.get(action, String(action)))


## InputMap 里 action 的其余键盘键（箭头、K 之类 Settings 不改的备用键），
## 已经与首键重复的会被去掉。
static func extra_keys(action: StringName) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	var first := label(action)
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
