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
##   · 改键：选中一行 → "按下新按键…"，下一个键盘键或手柄按键就是新键；Esc 取消；
##     与别的动作冲突会互换并提示；Esc / 回车保留。PageUp / PageDown（手柄肩键）换页。
##   · 从暂停菜单打开时不会取消暂停：本层只管自己的显示，树的暂停状态不碰。

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")
const Plate := preload("res://scripts/ui/menu_plate.gd")

const TAB_AUDIO := 0
const TAB_DISPLAY := 1
const TAB_KEYS := 2
const TAB_ASSIST := 3
const TAB_TITLES: Array[String] = ["声 音", "画 面", "键 位", "辅 助"]
## 每页一句说明，写在外壳的底部提示带上（不再是页内脚注，页内只留仪表行）。
const TAB_HINTS: Array[String] = [
	"拖动即时生效 · 松手后自动写入 · 主音量同时压住音乐与氛围的上限",
	"震动 / 闪光强度同时作用于战斗反馈与过场演出 · 三种缩放共用一条整数画布",
	"回车改键 · 键盘与手柄按键 / 轴都能改 · 冲突自动互换 · 方向键 / K / 鼠标 / 触控保持原样",
	"100% 是现在的平衡 · 受伤 / 毒素调低更轻松 · 弹反窗口调高更宽容",
]

const STEP := 5.0
const SAVE_DELAY := 0.5
const NOTICE_HOLD := 4.0
const ROW_WIDTH := 700.0
## 两列键位在 900px 卡片里：2×380 + 24 = 784，仍小于 832 的内容宽。
## 旧值 480 时网格 984px，会从花边卡两侧各挤出 76px。
const KEY_COLUMN_WIDTH := 380.0
const TICK_INTERVAL := 0.045

const BUS_NAMES := {
	&"Master": "主音量",
	&"Music": "音乐",
	&"Sfx": "音效",
	&"Ambience": "氛围",
}

## 数值读数框：嵌在行尾的小仪表舱（暗底 + 锈线框 + 顶光底影），滑条百分比、
## 开关状态、键帽都坐在同一种舱里，整页读起来是一套仪表。
class ReadoutCell:
	extends Control

	## 开状态的舱描一道余烬边（布尔开关用；数值舱保持锈色）。
	var lit := false:
		set(value):
			lit = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(88.0, 30.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(1.0, 0.0, w - 2.0, h), Color(0.03, 0.022, 0.05, 0.85))
		draw_rect(Rect2(0.0, 1.0, w, h - 2.0), Color(0.03, 0.022, 0.05, 0.85))
		var edge := Color(0.62, 0.40, 0.18, 0.9) if lit else Color(0.42, 0.26, 0.16, 0.8)
		draw_rect(Rect2(1.0, 0.0, w - 2.0, 1.0), edge)
		draw_rect(Rect2(1.0, h - 1.0, w - 2.0, 1.0), edge)
		draw_rect(Rect2(0.0, 1.0, 1.0, h - 2.0), edge)
		draw_rect(Rect2(w - 1.0, 1.0, 1.0, h - 2.0), edge)
		# 顶光 / 底影：一点舱室深度
		draw_rect(Rect2(2.0, 1.0, w - 4.0, 1.0), Color(0.9, 0.7, 0.5, 0.07))
		draw_rect(Rect2(2.0, h - 2.0, w - 4.0, 1.0), Color(0.0, 0.0, 0.0, 0.3))

## 提示开关等没有专属接口的选项走 Settings.value；键名与各系统约定一致。
const OPT_FULLSCREEN := &"fullscreen"
const OPT_SMOOTHING := &"pixel_smoothing"
var _display_choices: Dictionary = {}

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tab := TAB_AUDIO
## 瞬时消息（改键结果等）写进外壳的底部提示带，盖过该页的常驻说明几秒。
var _hint: Label
var _notice_text := ""
var _back: Button
var _reset_keys: Button

var _sliders: Dictionary = {}       # id(StringName) -> HSlider
var _value_labels: Dictionary = {}  # id -> Label
var _row_bgs: Dictionary = {}       # id -> Panel
var _row_accents: Dictionary = {}   # id -> ColorRect（左缘灯口）
var _value_cells: Dictionary = {}   # id -> ReadoutCell（读数舱）
var _value_flash: Dictionary = {}   # id -> 剩余闪光 1..0（滑条值刚变时读数亮一下）
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
	# 弹窗卡片：背景只压暗、不铺黑；标题带与底部提示带由外壳统一给。
	_shell = Modal.build(self, {
		"title": "设 置",
		"kicker": "锻 炉 仪 表",
		"size": Vector2(900.0, 700.0),
		"hint": TAB_HINTS[TAB_AUDIO],
		"back": "Esc 返回",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	_hint = _shell["hint"] as Label
	# 设置页点空白处不关闭：误触会丢掉正在拖的滑条 / 改键，只走 Esc 与"返回"。
	var body := _shell["body"] as Control

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	body.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		tab.custom_minimum_size = Vector2(156.0, UiKit.TOUCH_MIN)
		tab.pressed.connect(_select_tab.bind(i))
		# 键盘 / 手柄在标签行上左右移动就是换页；鼠标悬停不换页，点击才换。
		tab.focus_entered.connect(_select_tab.bind(i))
		# 当前页标签底下压着一根余烬短棒：换页时亮过去，和标题屏的灯口同一语汇。
		var ember_bar := ColorRect.new()
		ember_bar.name = "EmberBar"
		ember_bar.color = UiKit.EMBER
		ember_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		ember_bar.offset_left = 18.0
		ember_bar.offset_right = -18.0
		ember_bar.offset_top = -4.0
		ember_bar.offset_bottom = -1.0
		ember_bar.modulate.a = 0.0
		ember_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(ember_bar)
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	var host := Control.new()
	host.name = "Pages"
	host.custom_minimum_size = Vector2.ZERO
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(host)
	_pages.append(_build_audio_page(host))
	_pages.append(_build_display_page(host))
	_pages.append(_build_keys_page(host))
	_pages.append(_build_assist_page(host))

	# 瞬时消息直接写外壳的提示带（_say / _apply_hint），页内不再单开一行。
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


## 每页最后一行 ↓ 落到页脚「返回」，页脚 ↑ 回到当前页最后一行；键位页的
## 「恢复默认键位」与「返回」用 ←→ 串起来。换页时重算，避免焦点走进隐藏页。
func _wire_page_tail() -> void:
	if _back == null or _pages.is_empty():
		return
	var controls := _page_controls(_pages[_tab])
	if controls.is_empty():
		return
	var last := controls[controls.size() - 1]
	last.focus_neighbor_bottom = last.get_path_to(_back)
	_back.focus_neighbor_top = _back.get_path_to(last)
	if _reset_keys.visible:
		_reset_keys.focus_neighbor_right = _reset_keys.get_path_to(_back)
		_back.focus_neighbor_left = _back.get_path_to(_reset_keys)
	else:
		_reset_keys.focus_neighbor_right = NodePath()
		_back.focus_neighbor_left = NodePath()


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
	button.theme_type_variation = &"PlateButton"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(230.0, UiKit.TOUCH_MIN)
	button.mouse_entered.connect(button.grab_focus)
	return button


func _page(host: Control, node_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name + "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host.add_child(scroll)
	var page := VBoxContainer.new()
	page.name = node_name
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
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
	page.add_child(_display_choice(&"resolution", "窗 口 分 辨 率"))
	page.add_child(_display_choice(&"display_fit", "缩 放 策 略"))
	page.add_child(_display_choice(&"vsync", "垂 直 同 步"))
	page.add_child(_toggle_row(OPT_FULLSCREEN, "全 屏"))
	page.add_child(_toggle_row(OPT_SMOOTHING, "像 素 平 滑"))
	page.add_child(_slider_row(&"shake", "震 屏 强 度"))
	page.add_child(_slider_row(&"flash", "闪 光 强 度"))
	return page


func _display_choice(id: StringName, title: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, UiKit.TOUCH_MIN)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(_name_label(title, 230.0))
	var choice := OptionButton.new()
	choice.name = String(id)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = UiKit.TOUCH_MIN
	if id == &"resolution":
		for res in DisplayFit.PRESET_RESOLUTIONS:
			choice.add_item("%d × %d" % [res.x, res.y])
		var saved: Variant = Settings.value(id, Vector2i(1280, 720))
		choice.select(maxi(0, DisplayFit.PRESET_RESOLUTIONS.find(saved)))
	elif id == &"display_fit":
		for text in ["等比自适应", "扩展视野", "整数像素"]:
			choice.add_item(text)
		choice.select(int(Settings.value(id, DisplayFit.FitMode.INTEGER)))
	else:
		choice.add_item("关")
		choice.add_item("开")
		choice.select(1 if bool(Settings.value(id, true)) else 0)
	choice.item_selected.connect(_on_display_selected.bind(id))
	row.add_child(choice)
	_display_choices[id] = choice
	return row


func _on_display_selected(index: int, id: StringName) -> void:
	match id:
		&"resolution":
			DisplayFit.apply_resolution(DisplayFit.PRESET_RESOLUTIONS[index])
			_sync_toggle(OPT_FULLSCREEN)
		&"display_fit":
			DisplayFit.apply_fit_mode(index as DisplayFit.FitMode, null, true)
		&"vsync":
			DisplayFit.apply_vsync(index == 1)


func _build_assist_page(host: Control) -> Control:
	var page := _page(host, "AssistPage")
	page.add_child(_toggle_row(HintService.SETTING_ENABLED, "教 学 提 示"))
	for spec in [[&"assist_incoming", "受 伤 倍 率"], [&"assist_parry", "弹 反 窗 口"],
			[&"assist_toxin", "毒 素 速 率"], [&"subtitle_speed", "字 幕 速 度"],
			[&"text_scale", "文 本 缩 放"]]:
		var row := _slider_row(spec[0], spec[1])
		var slider := _sliders[spec[0]] as HSlider
		var limits: Vector2 = Settings.ASSIST_LIMITS[spec[0]]
		slider.min_value = limits.x * 100.0
		slider.max_value = limits.y * 100.0
		page.add_child(row)
	return page


func _build_keys_page(host: Control) -> Control:
	var page := _page(host, "KeysPage")
	var grid := GridContainer.new()
	grid.name = "KeyGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	page.add_child(grid)
	# 左列、右列，先按列填：Godot 的 GridContainer 逐行放，所以交错排。
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


## 行左缘的灯口：常态是暗锈，焦点 / 悬停时烧成余烬色（标题屏铁条的同一语汇）。
func _row_accent(row: Control, id: StringName) -> void:
	var accent := ColorRect.new()
	accent.name = "Accent"
	accent.color = Color(0.42, 0.26, 0.16, 0.7)
	accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	accent.offset_left = 6.0
	accent.offset_right = 9.0
	accent.offset_top = 12.0
	accent.offset_bottom = -12.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(accent)
	_row_accents[id] = accent


## 行尾的读数舱：数值 / 状态 / 键帽都装进同一种暗舱，页面读起来是一套仪表。
## 长文本（分辨率、缩放模式）会把舱撑到文字的实际宽度，往左吃掉行内的弹性空当。
func _readout_cell(id: StringName, value: Label) -> Control:
	var cell := ReadoutCell.new()
	cell.name = "Cell"
	value.set_anchors_preset(Control.PRESET_FULL_RECT)
	value.offset_left = 6.0
	value.offset_right = -6.0
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(value)
	_value_cells[id] = cell
	return cell


## 读数舱按文字实际宽度撑开（分辨率 / 缩放模式这类长值）。
func _fit_cell(id: StringName) -> void:
	var cell := _value_cells.get(id) as Control
	var label := _value_labels.get(id) as Label
	if cell == null or label == null:
		return
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null:
		return
	var w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	cell.custom_minimum_size.x = maxf(88.0, ceilf(w) + 16.0)


## 滑条轨道下的刻度：每 10% 一道细刻，1/4 处一道主刻（仪表感，也为拖动手感给参照）。
func _slider_ticks(row: Control) -> void:
	var ticks := Control.new()
	ticks.name = "Ticks"
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 轨道区间由行布局常量推出：Content 左右各让 20，名字列 170 + 间距 14，
	# 读数舱 88 + 间距 14；垂直方向压在轨道的中线上。
	var x0 := 20.0 + 170.0 + 14.0
	var x1 := ROW_WIDTH - 20.0 - 88.0 - 14.0
	ticks.position = Vector2(x0, 0.0)
	ticks.size = Vector2(x1 - x0, UiKit.TOUCH_MIN)
	row.add_child(ticks)
	ticks.draw.connect(func() -> void:
		# 轨道贴图盖在中线（y≈26）上：刻度从轨道下沿垂下来，像仪表的标尺。
		for i in 11:
			var f := float(i) / 10.0
			var x: float = roundf(4.0 + f * (ticks.size.x - 8.0))
			var major := i % 5 == 0
			var h := 6.0 if major else 3.0
			var col := Color(0.60, 0.38, 0.20, 0.6) if major else Color(0.42, 0.26, 0.16, 0.5)
			ticks.draw_rect(Rect2(x, 30.0, 1.0, h), col))
	ticks.queue_redraw()


func _slider_row(id: StringName, title: String) -> Control:
	var row := Control.new()
	row.name = "Row_%s" % String(id)
	row.custom_minimum_size = Vector2(ROW_WIDTH, UiKit.TOUCH_MIN)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := _row_bg()
	row.add_child(bg)
	_row_bgs[id] = bg
	_row_accent(row, id)
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
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(_readout_cell(id, value))
	_slider_ticks(row)
	_sliders[id] = slider
	_value_labels[id] = value
	return row


## 整行就是一个按钮：名字在左，当前值在右（值坐在读数舱里）。
func _button_row(id: StringName, title: String, width: float) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"SettingsButton"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(width, UiKit.TOUCH_MIN)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.mouse_entered.connect(button.grab_focus)
	_row_accent(button, id)
	var content := _row_content(button)
	content.add_child(_name_label(title, 190.0 if width > 600.0 else 170.0))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	var value := UiKit.label("", &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(_readout_cell(id, value))
	return button


## 开关行的"开/关"染色：开是余烬金、关是灰。整页扫一眼就知道哪几项开着，
## 不用逐行读字 —— 键位行的键帽不染色（本色已经是琥珀），只有布尔值才需要
## 状态色，否则"关"字比键名还醒目，反而抢焦点。
func _paint_toggle(label: Label, on: bool) -> void:
	label.text = "开" if on else "关"
	label.modulate = UiKit.EMBER if on else Color(UiKit.ASH.r, UiKit.ASH.g, UiKit.ASH.b, 0.75)
	# 开状态的读数舱描一道余烬边：整页扫一眼就知道哪几项开着。
	var cell := label.get_parent() as ReadoutCell
	if cell != null:
		cell.lit = on


func _toggle_row(id: StringName, title: String) -> Control:
	var button := _button_row(id, title, ROW_WIDTH)
	button.name = "Toggle_%s" % String(id)
	button.pressed.connect(_on_toggle_pressed.bind(id))
	# 开关行和滑条行一样：焦点 / 悬停点亮左缘灯口。
	button.focus_entered.connect(_set_row_focus.bind(id, true))
	button.focus_exited.connect(_set_row_focus.bind(id, false))
	_toggles[id] = button
	_value_labels[id] = button.get_node("Content/Cell/Value")
	return button


func _key_row(action: StringName) -> Control:
	var button := _button_row(action, KeyLabels.action_name(action), KEY_COLUMN_WIDTH)
	button.name = "Key_%s" % String(action)
	button.pressed.connect(_on_key_pressed.bind(action))
	# 焦点所在的行也换选中贴图：键位页没有滑条那样的行底联动，
	# 全靠这层让"当前在改哪一行"在鼠标和键盘下同源。
	button.focus_entered.connect(_set_row_focus.bind(action, true))
	button.focus_exited.connect(_set_row_focus.bind(action, false))
	_key_buttons[action] = button
	_key_caps[action] = button.get_node("Content/Cell/Value")
	return button


# --- 同步显示 ------------------------------------------------------------------

func _sync_all() -> void:
	for id in _sliders:
		_sync_slider(id)
	for id in _toggles:
		_sync_toggle(id)
	_sync_keys()


func _slider_percent(id: StringName) -> float:
	match id:
		&"shake":
			return Settings.shake_scale * 100.0
		&"flash":
			return Settings.flash_scale * 100.0
		&"assist_incoming", &"assist_parry", &"assist_toxin", &"subtitle_speed", &"text_scale":
			return float(Settings.value(id, 1.0)) * 100.0
		_:
			return Settings.assist(id) * 100.0 if Settings.ASSIST_LIMITS.has(id) else Settings.volume_percent(id)


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
	var label := _value_labels.get(id) as Label
	if label == null:
		return
	_paint_toggle(label, _toggle_state(id))


func _sync_keys() -> void:
	for action in _key_caps:
		var cap := _key_caps[action] as Label
		if action == _capturing:
			cap.text = "按下新按键…"
			# 抓键中的那一行：键帽染成余烬色、行底换成选中贴图。整页只有这一行
			# 亮着，"现在按哪个键都算数"才不会被读成"界面卡住了"。
			cap.modulate = UiKit.EMBER
			var bg := _row_bgs.get(action) as Panel
			if bg != null:
				bg.theme_type_variation = &"SettingsRowFocused"
		else:
			cap.text = KeyLabels.label(action)
			cap.modulate = Color.WHITE
			# 焦点行的行底由 focus_exited / focus_entered 维护；抓键结束时
			# 如果焦点还在这一行，selected 贴图要继续留着，不能在这里清掉。
			if _key_buttons.get(action) != null \
					and not (_key_buttons[action] as Button).has_focus():
				var normal := _row_bgs.get(action) as Panel
				if normal != null:
					normal.theme_type_variation = &"SettingsRowNormal"
		# 键帽文字长度会变（"按下新按键…" 比 "J" 长得多）：读数舱跟着文字走。
		_fit_cell(action)


func _set_row_focus(id: StringName, focused: bool) -> void:
	var accent := _row_accents.get(id) as ColorRect
	if accent != null:
		accent.color = UiKit.EMBER if focused else Color(0.42, 0.26, 0.16, 0.7)
	var bg := _row_bgs.get(id) as Panel
	if bg != null:
		bg.theme_type_variation = &"SettingsRowFocused" if focused else &"SettingsRowNormal"
		return
	# 键位 / 开关行整行是一个按钮：没有独立行底，直接把选中贴图换到按钮的
	# normal 上 —— 这样悬停和键盘焦点共用同一个"这一行亮了"的信号。
	var button := _toggles.get(id) as Button
	if button == null:
		button = _key_buttons.get(id) as Button
	if button == null:
		return
	var style := Plate.style_box(Plate.Shape.TAG, \
			Plate.State.SELECTED if focused else Plate.State.NORMAL)
	button.add_theme_stylebox_override("normal", style)


func _on_setting_changed(key: StringName) -> void:
	if _building or _root == null:
		return
	if key == &"keys":
		_sync_keys()
	elif _sliders.has(key):
		_sync_slider(key)


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
		_pages[i].get_parent().visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(false)
		_set_tab_ember(i, i == _tab)
	_tab_buttons[_tab].set_pressed_no_signal(true)
	_reset_keys.visible = _tab == TAB_KEYS
	_wire_page_tail()
	_apply_hint()


## 底部提示带：有瞬时消息时盖着消息，平时写当前页的那句说明。
func _apply_hint() -> void:
	if _hint == null:
		return
	if _notice_text != "":
		_hint.text = _notice_text
	else:
		_hint.text = TAB_HINTS[_tab]


## 标签下的余烬短棒：当前页亮起（快入慢出），其余熄掉。headless / 构建期直接落位。
func _set_tab_ember(i: int, on: bool) -> void:
	var bar := _tab_buttons[i].get_node_or_null("EmberBar") as CanvasItem
	if bar == null:
		return
	var target := 1.0 if on else 0.0
	if _building or DisplayServer.get_name() == "headless" or not is_inside_tree():
		bar.modulate.a = target
		return
	var tw := create_tween()
	tw.tween_property(bar, "modulate:a", target, 0.22 if on else 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	_closing = false
	_cancel_capture()
	_notice_text = ""
	_sync_all()
	_show_page(TAB_AUDIO)
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_select")
	# 可见之后才能拿焦点。
	_focus_first.call_deferred()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_cancel_capture()
	flush()
	GameContext.suppress_gameplay_input()
	UiKit.sfx(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


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
			_notice_text = ""
			if _hint != null:
				_hint.modulate = Color.WHITE
			_apply_hint()
	# 读数闪光衰减（只在滑条值刚变过时才逐帧跑）。
	if not _value_flash.is_empty():
		var done: Array = []
		for id in _value_flash:
			var left: float = maxf(0.0, float(_value_flash[id]) - delta * 2.6)
			_value_flash[id] = left
			var label := _value_labels.get(id) as Label
			if label != null:
				label.modulate = Color.WHITE.lerp(UiKit.EMBER, left)
			if left <= 0.0:
				done.append(id)
		for id in done:
			_value_flash.erase(id)


func _say(text: String) -> void:
	_notice_text = text
	_notice_left = NOTICE_HOLD
	_apply_hint()


# --- 滑条 / 开关 ---------------------------------------------------------------

func _on_slider_changed(value: float, id: StringName) -> void:
	if _building:
		return
	match id:
		&"shake":
			Settings.set_shake_scale(value / 100.0, false)
		&"flash":
			Settings.set_flash_scale(value / 100.0, false)
		&"assist_incoming", &"assist_parry", &"assist_toxin", &"subtitle_speed", &"text_scale":
			Settings.set_value(id, clampf(value / 100.0, 0.5, 1.5), false)
		_:
			if Settings.ASSIST_LIMITS.has(id):
				Settings.set_value(id, value / 100.0, false)
			else:
				Settings.set_volume_percent(id, value, false)
	(_value_labels[id] as Label).text = "%d%%" % int(round(value))
	# 读数舱亮一下：值刚变的那一下读数烧成余烬色，随后慢慢退回去。
	_value_flash[id] = 1.0
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
	# 抓键期间提示带烧成余烬色：整屏只有这一处在等输入，必须一眼能找到。
	if _hint != null:
		_hint.modulate = UiKit.EMBER
	_notice_left = 0.0  # 抓键期间提示常驻，直到完成或取消


func _cancel_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_sync_keys()
	_notice_text = ""
	if _hint != null:
		_hint.modulate = Color.WHITE
	_apply_hint()


## 抓键入口：返回 true 表示这个事件被改键流程吃掉了。测试可以直接喂 InputEventKey / 手柄按键或轴。
func handle_capture_event(event: InputEvent) -> bool:
	if _capturing == &"":
		return false
	if event is InputEventKey and event.is_action_pressed(&"ui_cancel"):
		_cancel_capture()
		return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			# 抓键期间键盘的松开 / 连发也不能漏给界面（空格会触发按钮）。
			return true
		var physical := int(key.physical_keycode)
		if physical == 0:
			# 只带 keycode 的事件（合成输入）：QWERTY 下两者同值。
			physical = int(key.keycode)
		KeyLabels.set_device(KeyLabels.DEVICE_KEYBOARD)
		finish_capture(physical)
		return true
	if event is InputEventJoypadButton:
		var btn := event as InputEventJoypadButton
		if not btn.pressed:
			return true
		if btn.button_index == JOY_BUTTON_START:
			_cancel_capture()
			return true
		KeyLabels.set_device(KeyLabels.DEVICE_GAMEPAD)
		finish_pad_capture(Settings.encode_pad_event(btn))
		return true
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < 0.6:
			return false
		KeyLabels.set_device(KeyLabels.DEVICE_GAMEPAD)
		finish_pad_capture(Settings.encode_pad_event(motion))
		return true
	return false


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


func finish_pad_capture(token: String) -> void:
	var action := _capturing
	if action == &"":
		return
	var result := Settings.rebind_pad_action(action, token)
	_capturing = &""
	_sync_keys()
	var key_name := KeyLabels.label(action)
	if result == &"reserved":
		_say("这个按键不能用（Start 留给菜单）")
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
	return _notice_text


func back_button() -> Button:
	return _back


func tab_button(index: int) -> Button:
	return _tab_buttons[index]


## 切页（工具 / 测试 / 手柄肩键共用）。可见时把焦点送进新页的第一行：
## 否则换页后焦点还留在上一页已隐藏的控件上，页面上一个高亮都没有。
func show_tab(index: int) -> void:
	_select_tab(index)
	if visible:
		_focus_first.call_deferred()
