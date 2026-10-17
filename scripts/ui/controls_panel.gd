class_name ControlsPanel
extends CanvasLayer
## 操作说明面板：华丽边框 + 键位表。标题屏与暂停菜单共用，
## 也是原先挤在 HUD 右上角那行操作提示的新家。
##
## 键名全部取自 Settings（经 KeyLabels），玩家在设置里改键后这里自动跟随：
## 每次 open() 和每次 Settings 发出 &"keys" 变更时重写键位列。
##
## 之所以是 CanvasLayer 而不是 Control：这个面板生成时就是隐藏的，而隐藏的
## Control 不会被排版（子节点的锚点算在 0x0 的父矩形上，面板会缩在左上角）。
## CanvasLayer 下的 Control 以视口为父矩形，隐藏期间也能正确排版。
## 调用方负责设置 layer（要盖在自己那层之上）。

signal closed

## 键位表：[键位模板, 说明]。{action} 在显示时换成当前绑定；{attack2} 是挥砍的备用键
## （K，Settings 不改它），移动行的箭头同理由 KeyLabels.extra_keys 补在后面。
## 固定的键（Tab、Esc、鼠标）直接写字。
const ROWS: Array[Array] = [
	["{move_left} / {move_right}", "移动（沉重惯性）"],
	["{jump}", "跳跃 · 落地后可再跳一次"],
	["{dash}", "冲刺 · 带无敌帧"],
	["{attack} / 鼠标左键", "挥砍 · 判定帧碰到敌弹即弹反"],
	["{attack2} / 鼠标右键", "同为挥砍 · 判定末段或收刀时再按可接三连"],
	["{interact}", "交互 · 废料堆 / 插座台 / 净化祠"],
	["{socket_1} / {socket_2}", "把锈核插入剑的 1 / 2 号插座"],
	["{hookshot}", "钩锁 · 需先镶嵌钩锁核"],
	["按住 Tab", "查看目标 · 天气 · 剑核名称"],
	["Esc", "暂停 / 返回"],
	["触控板", "手机/平板：左移右移 · 右斩跳冲互 · 上钩/1/2 · Ⅱ暂停"],
]

var _root: Control
var _key_labels: Array[Label] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)
	Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# 遮罩会吃掉鼠标事件，所以点击关闭必须走 gui_input —— 被 GUI 消化的事件
	# 不会再进 _unhandled_input。
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(_root)

	_root.add_child(UiKit.scrim(0.86, 0.86, 0.86))

	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 140.0
	frame.offset_right = -140.0
	frame.offset_top = 32.0
	frame.offset_bottom = -32.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)

	column.add_child(UiKit.label("操 作 说 明", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for row in ROWS:
		var key := UiKit.label(String(row[0]), &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		key.custom_minimum_size = Vector2(250.0, 0.0)
		grid.add_child(key)
		_key_labels.append(key)
		grid.add_child(UiKit.label(String(row[1]), &"BodyLabel"))

	column.add_child(UiKit.divider())
	column.add_child(UiKit.label("弹反不是单独的格挡键 —— 巨剑的判定帧打中弹丸就会把它打回去",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("键位可在 设置 → 键位 里修改",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("Esc / 回车  返回", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	refresh()


## 把键位列重写成当前绑定（含备用键）。公开：测试与改键后直接调用。
func refresh() -> void:
	for i in _key_labels.size():
		_key_labels[i].text = key_text(i)


## 第 i 行的键位文字。
func key_text(index: int) -> String:
	var template := String(ROWS[index][0])
	if template.begins_with("{attack2}"):
		var alt := KeyLabels.extra_keys(&"attack")
		if alt.is_empty():
			template = template.replace("{attack2} / ", "")
		else:
			template = template.replace("{attack2}", alt[0])
	var text := KeyLabels.format(template)
	var arrows := _arrows_for(template)
	if arrows != "":
		text += "  " + arrows
	return text


## 移动行的备用键（←/→，Settings 不改它们）补在后面。
func _arrows_for(template: String) -> String:
	if not template.contains("{move_left}"):
		return ""
	var parts: Array[String] = []
	parts.append_array(KeyLabels.extra_keys(&"move_left"))
	parts.append_array(KeyLabels.extra_keys(&"move_right"))
	return "/".join(parts)


func _on_setting_changed(key: StringName) -> void:
	if key == &"keys":
		refresh()


func open() -> void:
	refresh()
	visible = true
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible:
		return
	visible = false
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
