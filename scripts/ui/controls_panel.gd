class_name ControlsPanel
extends CanvasLayer
## 操作说明面板：四段键位做成 2×2 的玻璃键位卡，每张卡一个小题头，下面每行左边是动作，
## 右边是一排键帽（KeyCapPanel）。标题屏与暂停菜单共用，也是原先挤在 HUD 右上角那行操作提示的新家。
##
## 键名全部取自 Settings（经 KeyLabels），玩家在设置里改键后这里自动跟随：
## 每次 open() 和每次 Settings 发出 &"keys" 变更时重写键帽。
##
## 之所以是 CanvasLayer 而不是 Control：这个面板生成时就是隐藏的，而隐藏的
## Control 不会被排版（子节点的锚点算在 0x0 的父矩形上，面板会缩在左上角）。
## CanvasLayer 下的 Control 以视口为父矩形，隐藏期间也能正确排版。
## 调用方负责设置 layer（要盖在自己那层之上）。

signal closed

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")
const Modal := preload("res://scripts/ui/ui_modal.gd")
## 压暗到 0.76：这一层通常盖在暂停菜单上，底下的卡片要压到看不出字来，玻璃卡才不会透出串行。
const VEIL := 0.76
const CARD_GAP_H := 16
const CARD_GAP_V := 12

## 键位表：[键位模板, 说明]。{action} 在显示时换成当前绑定；{attack2} 是挥砍的备用键
## （K，Settings 不改它），移动行的箭头同理由 KeyLabels.extra_keys 补在后面。
## 固定的键（Tab、Esc、鼠标）直接写字。
const ROWS: Array[Array] = [
	["{move_left} / {move_right}", "移动（沉重惯性）"],
	["{jump}", "跳跃 · 落地后可再跳一次"],
	["{dash}", "冲刺 · 带无敌帧"],
	["{hookshot}", "钩锁 · 需先镶嵌钩锁核"],
	["{attack} / 鼠标左键", "挥砍 · 判定帧碰到敌弹即弹反"],
	["{attack2} / 鼠标右键", "同为挥砍 · 判定末段或收刀时再按可接三连"],
	["{skill_1} / {skill_2}", "主动技能 1 / 2 · 冷却好了才能放"],
	["{interact}", "交互 · 废料堆 / 插座台 / 净化祠"],
	["{socket_1} / {socket_2}", "把锈核插入剑的 1 / 2 号插座"],
	["按住 Tab", "查看目标 · 天气 · 剑核名称"],
	["Esc", "暂停 / 返回"],
	["触控板", "手机/平板：左移右移 · 右斩跳冲互 · 上钩/1/2 · Ⅱ暂停"],
]
## 分组：{起始行, 组名}。12 行摊成移动 / 战斗 / 交互与剑核 / 系统四张卡（2×2），
## 行序就是这个分组顺序，key_text(index) 仍按行号取。
const GROUPS: Array[Dictionary] = [
	{"start": 0, "count": 4, "title": "移 动"},
	{"start": 4, "count": 3, "title": "战 斗"},
	{"start": 7, "count": 2, "title": "交 互 · 剑 核"},
	{"start": 9, "count": 3, "title": "系 统"},
]

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _scroll: ScrollContainer
## 每行键帽列（HBox）：refresh() 时按当前绑定重排。下标 = ROWS 的行号。
var _chip_boxes: Array[HBoxContainer] = []


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
	_shell = Modal.build(self, {
		"title": "操 作 说 明",
		"size": Vector2(900.0, 620.0),
		"hint": "↑↓ 滚动",
		"back": "Esc / 回车 返回",
		"veil": VEIL,
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	# 遮罩会吃掉鼠标事件，所以点击关闭必须走 gui_input —— 被 GUI 消化的事件
	# 不会再进 _unhandled_input。
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())

	var body := _shell["body"] as Control
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	_scroll.add_child(column)

	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", CARD_GAP_H)
	grid.add_theme_constant_override("v_separation", CARD_GAP_V)
	column.add_child(grid)
	_chip_boxes.resize(ROWS.size())
	for group in GROUPS:
		grid.add_child(_group_card(group))

	column.add_child(UiKit.label("弹反不是单独的格挡键 —— 巨剑的判定帧打中弹丸就会把它打回去",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("键位可在 设置 → 键位 里修改",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	refresh()


## 一张键位卡：玻璃铁框底 + 小题头 + 各行（动作 | 键帽）。
func _group_card(group: Dictionary) -> Control:
	var title := String(group["title"])
	var card := PanelContainer.new()
	card.name = "Card_" + title.replace(" ", "")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var glass := _glass_card()
	if glass != null:
		card.add_theme_stylebox_override(&"panel", glass)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 2)
	card.add_child(inner)
	inner.add_child(_group_header(title))
	var start_index := int(group["start"])
	for i in range(start_index, start_index + int(group["count"])):
		inner.add_child(_key_row(i))
	return card


## 键位卡底：主题的铁框板（HintPanel），复制一份压成卡片透明度，内边距收紧到键位列的宽度。
static func _glass_card() -> StyleBox:
	var base := UiKit.extras_theme().get_stylebox(&"panel", &"HintPanel") as StyleBoxTexture
	if base == null:
		return null
	var box := base.duplicate() as StyleBoxTexture
	box.modulate_color = Color(1.0, 1.0, 1.0, GlassKit.CARD_ALPHA)
	box.content_margin_left = 16.0
	box.content_margin_top = 8.0
	box.content_margin_right = 16.0
	box.content_margin_bottom = 8.0
	return box


## 卡片题头：GlassKit 的 kicker（12px 余烬小字）+ 一道锈色发丝线，和故事页、暂停页的题头同一语汇。
func _group_header(title: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Group_" + title.replace(" ", "")
	row.add_theme_constant_override("separation", 10)
	var label := GlassKit.kicker(title)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var rule := Ornaments.stub_rule(false)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	return row


## 一行：左边是动作说明，右边是键帽列（每个键一枚小铁牌，右对齐）。
## 说明用 12px（TinyHintLabel）：键帽是这张卡的主角，24px 的说明在 900 宽的卡里每行会折成三四行，
## 四张卡放不进 620 高；12px 说明配 24px 键帽，和键位表的读法一致，行高也压得下来。
func _key_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row%d" % index
	row.add_theme_constant_override("separation", 10)
	var action := UiKit.label(String(ROWS[index][1]), &"TinyHintLabel")
	action.name = "Action"
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(action)
	var chips := HBoxContainer.new()
	chips.name = "Keys"
	chips.size_flags_horizontal = Control.SIZE_SHRINK_END
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", 4)
	row.add_child(chips)
	_chip_boxes[index] = chips
	return row


func _chip(text: String) -> Control:
	var plate := UiKit.panel(&"KeyCapPanel")
	plate.name = "Chip"
	var key := UiKit.label(text, &"KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(key)
	return plate


## 把键帽列重写成当前绑定（含备用键）。公开：测试与改键后直接调用。
func refresh() -> void:
	for i in _chip_boxes.size():
		var box := _chip_boxes[i]
		if box == null:
			continue
		for old in box.get_children():
			box.remove_child(old)
			old.queue_free()
		for text in key_chips(i):
			box.add_child(_chip(text))


## 第 i 行的键位文字（整段，和设置页键帽同一个出口）。
func key_text(index: int) -> String:
	var template := _template(index)
	var text := KeyLabels.format(template)
	var arrows := _arrows_for(template)
	if arrows != "":
		text += "  " + arrows
	return text


## 第 i 行的键帽列：每个键一枚（"A / D" + 备用箭头 → A、D、←、→）。
func key_chips(index: int) -> PackedStringArray:
	var template := _template(index)
	var out := PackedStringArray()
	for part in KeyLabels.format(template).split(" / "):
		var chip := String(part).strip_edges()
		if chip != "":
			out.append(chip)
	var arrows := _arrows_for(template)
	if arrows != "":
		out.append_array(arrows.split("/"))
	return out


## 模板里的 {attack2} 换成挥砍的备用键；没有备用键就把这一段去掉。
func _template(index: int) -> String:
	var template := String(ROWS[index][0])
	if template.begins_with("{attack2}"):
		var alt := KeyLabels.extra_keys(&"attack")
		if alt.is_empty():
			template = template.replace("{attack2} / ", "")
		else:
			template = template.replace("{attack2}", alt[0])
	return template


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
	_closing = false
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_scroll.scroll_vertical += 48
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - 48)
		get_viewport().set_input_as_handled()
